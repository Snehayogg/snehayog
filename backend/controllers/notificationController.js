import User from '../models/User.js';
import CreatorNotification from '../models/CreatorNotification.js';
import CreatorDailyStats from '../models/CreatorDailyStats.js';
import Follower from '../models/Follower.js';
import { sendNotificationToUsers } from '../services/notificationServices/notificationService.js';
import mongoose from 'mongoose';

/**
 * Controller for Creator-to-Subscriber Direct Notifications
 */
export const sendCreatorAlert = async (req, res) => {
  try {
    const creatorId = req.user._id; // Authenticated creator
    const { message, title, targetUrl, recipientIds } = req.body;

    if (!message) {
      return res.status(400).json({ success: false, message: 'Message is required' });
    }

    // 1. Enforce 2-per-day limit
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    let dailyStats = await CreatorDailyStats.findOne({ creatorId, date: today });
    if (!dailyStats) {
      dailyStats = new CreatorDailyStats({ creatorId, date: today });
    }

    if (dailyStats.directNotificationsSent >= 2) {
      return res.status(429).json({ 
        success: false, 
        message: 'Daily limit reached. You can only send 2 alerts per day.' 
      });
    }

    // 2. Fetch subscribers (All or Specific)
    let subscriberIds = [];
    if (recipientIds && Array.isArray(recipientIds) && recipientIds.length > 0) {
      // Use specifically selected recipients
      subscriberIds = recipientIds;
    } else {
      // Fetch all subscribers as fallback
      const subscriptionEntries = await Follower.find({ following: creatorId }).select('follower');
      subscriberIds = subscriptionEntries.map(f => f.follower);
    }

    if (subscriberIds.length === 0) {
      return res.status(200).json({ success: true, message: 'No subscribers to notify' });
    }

    // 3. Filter subscribers by preferences (Opt-in/Opt-out)
    const eligibleUsers = await User.find({
      _id: { $in: subscriberIds },
      fcmToken: { $ne: null },
      'notificationPreferences.globalCreatorAlerts': { $ne: false },
      'notificationPreferences.disabledCreators': { $ne: creatorId }
    }).select('googleId fcmToken');

    const targetGoogleIds = eligibleUsers.map(u => u.googleId);

    if (targetGoogleIds.length === 0) {
      return res.status(200).json({ success: true, message: 'No eligible subscribers found for notification' });
    }

    // 4. Create Notification Record for Analytics
    const notificationRecord = new CreatorNotification({
      creatorId,
      message,
      title: title || `Update from ${req.user.name}`,
      targetUrl,
      sentCount: targetGoogleIds.length
    });
    await notificationRecord.save();

    // 5. Trigger FCM
    const fcmResult = await sendNotificationToUsers(targetGoogleIds, {
      title: notificationRecord.title,
      body: message,
      data: {
        type: 'creator_alert',
        notificationId: notificationRecord._id.toString(),
        targetUrl: targetUrl || '',
        creatorId: creatorId.toString()
      }
    });

    // 6. Update Daily Stats Counter
    dailyStats.directNotificationsSent += 1;
    await dailyStats.save();

    res.status(200).json({ 
      success: true, 
      message: 'Alert sent successfully',
      stats: {
        sentTo: targetGoogleIds.length,
        remainingToday: 2 - dailyStats.directNotificationsSent
      }
    });

  } catch (error) {
    console.error('Error sending creator alert:', error);
    res.status(500).json({ success: false, message: 'Internal server error' });
  }
};

/**
 * Update User Notification Preferences
 */
export const updateNotificationPreferences = async (req, res) => {
  try {
    const userId = req.user._id;
    const { globalEnabled, disabledCreatorId, enabledCreatorId } = req.body;

    const user = await User.findById(userId);
    if (!user) return res.status(404).json({ success: false, message: 'User not found' });

    if (globalEnabled !== undefined) {
      user.notificationPreferences.globalCreatorAlerts = globalEnabled;
    }

    if (disabledCreatorId) {
      if (!user.notificationPreferences.disabledCreators.includes(disabledCreatorId)) {
        user.notificationPreferences.disabledCreators.push(disabledCreatorId);
      }
    }

    if (enabledCreatorId) {
      user.notificationPreferences.disabledCreators = user.notificationPreferences.disabledCreators.filter(
        id => id.toString() !== enabledCreatorId.toString()
      );
    }

    await user.save();
    res.status(200).json({ success: true, preferences: user.notificationPreferences });

  } catch (error) {
    res.status(500).json({ success: false, message: 'Error updating preferences' });
  }
};

/**
 * Get Notification Analytics for Revenue Screen
 */
export const getCreatorNotificationStats = async (req, res) => {
  try {
    const creatorId = req.user._id;
    const stats = await CreatorNotification.find({ creatorId })
      .sort({ sentAt: -1 })
      .limit(10);
    
    // Get daily stats for remaining count
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const dailyStats = await CreatorDailyStats.findOne({ creatorId, date: today });
    const remainingToday = dailyStats ? Math.max(0, 2 - dailyStats.directNotificationsSent) : 2;
    
    res.status(200).json({ 
      success: true, 
      stats,
      remainingToday
    });
  } catch (error) {
    res.status(500).json({ success: false, message: 'Error fetching stats' });
  }
};
