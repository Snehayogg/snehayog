import express from 'express';
import { verifyToken } from '../utils/verifytoken.js';
import { requireAdminDashboardKey } from '../middleware/adminDashboardAuth.js';
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
    const userId = req.user.id; // This is Google ID from verifyToken middleware
    const googleId = req.user.googleId || userId;

    if (!fcmToken) {
      return res.status(400).json({ error: 'FCM token is required' });
    }

    // Find user by googleId (not MongoDB _id)
    const user = await User.findOne({ googleId: googleId });
    if (!user) {
      console.error(`❌ User not found with googleId: ${googleId}`);
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
    console.error('Error stack:', error.stack);
    res.status(500).json({ error: 'Failed to save FCM token' });
  }
});

/**
 * POST /api/notifications/send
 * Send notification to a specific user (Admin Dashboard Only)
 */
router.post('/send', requireAdminDashboardKey, async (req, res) => {
  try {
    const { googleId, title, body, data } = req.body;

    if (!googleId || !title || !body) {
      return res.status(400).json({ 
        error: 'googleId, title, and body are required' 
      });
    }

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
 * Send notification to multiple users (Admin Dashboard Only)
 */
router.post('/send-multiple', requireAdminDashboardKey, async (req, res) => {
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
 * Send notification to all users (Admin Dashboard Only)
 */
router.post('/broadcast', requireAdminDashboardKey, async (req, res) => {
  try {
    const { title, body, data } = req.body;

    if (!title || !body) {
      return res.status(400).json({ 
        error: 'title and body are required' 
      });
    }

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
 * Get monthly notification cron job status (Admin Dashboard Only)
 */
router.get('/monthly/status', requireAdminDashboardKey, async (req, res) => {
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
 * Manually trigger monthly notification (Admin Dashboard Only)
 */
router.post('/monthly/trigger', requireAdminDashboardKey, async (req, res) => {
  try {
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

/**
 * POST /api/notifications/verify-installation
 * Check if a specific user still has the app installed
 */
router.post('/verify-installation', requireAdminDashboardKey, async (req, res) => {
  try {
    const { googleId } = req.body;
    console.log(`📡 Route: /verify-installation hit for googleId: ${googleId}`);
    
    if (!googleId) {
      return res.status(400).json({ error: 'googleId is required' });
    }

    const { verifyInstallationStatus } = await import('../services/notificationService.js');
    const result = await verifyInstallationStatus(googleId);

    res.json(result);
  } catch (error) {
    console.error('❌ Error verifying installation:', error);
    res.status(500).json({ error: 'Failed to verify installation' });
  }
});

/**
 * POST /api/notifications/verify-all-installations
 * Bulk check all users to see who has uninstalled the app
 */
router.post('/verify-all-installations', requireAdminDashboardKey, async (req, res) => {
  try {
    const { verifyInstallationStatus } = await import('../services/notificationService.js');
    
    // Get all users who have a token
    // Find all users to ensure we sync those who already have null tokens
    const users = await User.find({}).select('googleId fcmToken isAppUninstalled');
    console.log(`🔍 Syncing & Verifying installation for ${users.length} users...`);

    let installedCount = 0;
    let uninstalledCount = 0;
    let errorCount = 0;
    
    const usersToVerify = [];
    
    // First, mark users with null tokens as uninstalled if they aren't already
    for (const user of users) {
      if (!user.fcmToken) {
        if (!user.isAppUninstalled) {
          await User.updateOne({ _id: user._id }, { $set: { isAppUninstalled: true, lastInstallCheck: new Date() } });
        }
        uninstalledCount++;
      } else {
        usersToVerify.push(user);
      }
    }

    console.log(`📡 Verifying ${usersToVerify.length} users with active tokens in batches...`);

    // Process in chunks of 50 to avoid overwhelming Firebase/Network
    const chunkSize = 50;
    for (let i = 0; i < usersToVerify.length; i += chunkSize) {
      const chunk = usersToVerify.slice(i, i + chunkSize);
      console.log(`⏳ Processing batch ${i / chunkSize + 1}/${Math.ceil(usersToVerify.length / chunkSize)}...`);
      
      const results = await Promise.all(chunk.map(u => verifyInstallationStatus(u.googleId)));
      
      results.forEach(r => {
        if (r.success) {
          if (r.isInstalled) installedCount++;
          else uninstalledCount++;
        } else {
          errorCount++;
        }
      });
    }

    console.log(`🏁 Bulk verification complete. Installed: ${installedCount}, Uninstalled: ${uninstalledCount}, Errors: ${errorCount}`);

    res.json({
      success: true,
      processed: users.length,
      installed: installedCount,
      uninstalled: uninstalledCount,
      errors: errorCount
    });
  } catch (error) {
    console.error('❌ Error in bulk installation verify:', error);
    res.status(500).json({ error: 'Failed to run bulk verification' });
  }
});

export default router;

