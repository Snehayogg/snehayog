import express from 'express';
import { verifyToken } from '../utils/verifytoken.js';
import { 
  sendNotificationToUser, 
  sendNotificationToUsers, 
  sendNotificationToAll 
} from '../services/notificationService.js';
import monthlyNotificationCron from '../services/monthlyNotificationCron.js';
import User from '../models/User.js';

const router = express.Router();

/**
 * POST /api/notifications/token
 * Save/update FCM token for the authenticated user
 */
router.post('/token', verifyToken, async (req, res) => {
  try {
    const { fcmToken } = req.body;
    const userId = req.user.id;

    if (!fcmToken) {
      return res.status(400).json({ error: 'FCM token is required' });
    }

    const user = await User.findById(userId);
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    user.fcmToken = fcmToken;
    await user.save();

    console.log(`✅ FCM token saved for user: ${user.name} (${user.googleId})`);

    res.json({ 
      success: true, 
      message: 'FCM token saved successfully' 
    });
  } catch (error) {
    console.error('❌ Error saving FCM token:', error);
    res.status(500).json({ error: 'Failed to save FCM token' });
  }
});

/**
 * POST /api/notifications/send
 * Send notification to a specific user (admin only or self)
 */
router.post('/send', verifyToken, async (req, res) => {
  try {
    const { googleId, title, body, data } = req.body;
    const currentUser = req.user;

    // Allow users to send to themselves, or implement admin check
    if (!googleId || !title || !body) {
      return res.status(400).json({ 
        error: 'googleId, title, and body are required' 
      });
    }

    // Optional: Add admin check here
    // if (currentUser.role !== 'admin' && currentUser.googleId !== googleId) {
    //   return res.status(403).json({ error: 'Unauthorized' });
    // }

    const result = await sendNotificationToUser(googleId, {
      title,
      body,
      data: data || {}
    });

    if (result.success) {
      res.json({ 
        success: true, 
        message: 'Notification sent successfully',
        messageId: result.messageId 
      });
    } else {
      res.status(400).json({ 
        success: false, 
        error: result.error 
      });
    }
  } catch (error) {
    console.error('❌ Error sending notification:', error);
    res.status(500).json({ error: 'Failed to send notification' });
  }
});

/**
 * POST /api/notifications/send-multiple
 * Send notification to multiple users
 */
router.post('/send-multiple', verifyToken, async (req, res) => {
  try {
    const { googleIds, title, body, data } = req.body;

    if (!googleIds || !Array.isArray(googleIds) || googleIds.length === 0) {
      return res.status(400).json({ 
        error: 'googleIds array is required' 
      });
    }

    if (!title || !body) {
      return res.status(400).json({ 
        error: 'title and body are required' 
      });
    }

    const result = await sendNotificationToUsers(googleIds, {
      title,
      body,
      data: data || {}
    });

    if (result.success) {
      res.json({ 
        success: true, 
        message: 'Notifications sent successfully',
        successCount: result.successCount,
        failureCount: result.failureCount
      });
    } else {
      res.status(400).json({ 
        success: false, 
        error: result.error 
      });
    }
  } catch (error) {
    console.error('❌ Error sending notifications:', error);
    res.status(500).json({ error: 'Failed to send notifications' });
  }
});

/**
 * POST /api/notifications/broadcast
 * Send notification to all users (admin only)
 */
router.post('/broadcast', verifyToken, async (req, res) => {
  try {
    const { title, body, data } = req.body;

    if (!title || !body) {
      return res.status(400).json({ 
        error: 'title and body are required' 
      });
    }

    // Optional: Add admin check here
    // if (req.user.role !== 'admin') {
    //   return res.status(403).json({ error: 'Admin access required' });
    // }

    const result = await sendNotificationToAll({
      title,
      body,
      data: data || {}
    });

    if (result.success) {
      res.json({ 
        success: true, 
        message: 'Broadcast sent successfully',
        successCount: result.successCount,
        failureCount: result.failureCount
      });
    } else {
      res.status(400).json({ 
        success: false, 
        error: result.error 
      });
    }
  } catch (error) {
    console.error('❌ Error broadcasting notifications:', error);
    res.status(500).json({ error: 'Failed to broadcast notifications' });
  }
});

/**
 * GET /api/notifications/monthly/status
 * Get monthly notification cron job status
 */
router.get('/monthly/status', verifyToken, async (req, res) => {
  try {
    const status = monthlyNotificationCron.getStatus();
    res.json({
      success: true,
      ...status
    });
  } catch (error) {
    console.error('❌ Error getting monthly notification status:', error);
    res.status(500).json({ error: 'Failed to get status' });
  }
});

/**
 * POST /api/notifications/monthly/trigger
 * Manually trigger monthly notification (for testing)
 */
router.post('/monthly/trigger', verifyToken, async (req, res) => {
  try {
    // Optional: Add admin check here
    // if (req.user.role !== 'admin') {
    //   return res.status(403).json({ error: 'Admin access required' });
    // }

    console.log('🔧 Manual trigger of monthly notification requested');
    await monthlyNotificationCron.triggerManually();
    
    res.json({
      success: true,
      message: 'Monthly notification triggered successfully'
    });
  } catch (error) {
    console.error('❌ Error triggering monthly notification:', error);
    res.status(500).json({ error: 'Failed to trigger monthly notification' });
  }
});

export default router;

