import admin from 'firebase-admin';
import User from '../models/User.js';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

// ES module equivalents of __filename/__dirname
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Initialize Firebase Admin (will use service account from environment or local file)
let firebaseInitialized = false;

const initializeFirebase = () => {
  if (firebaseInitialized) {
    return;
  }

  try {
    let serviceAccountJson = null;

    // 1) Prefer environment variable in production (Railway, etc.)
    if (process.env.FIREBASE_SERVICE_ACCOUNT) {
      try {
        serviceAccountJson = JSON.parse(process.env.FIREBASE_SERVICE_ACCOUNT);
        console.log('✅ Firebase Admin: Loaded service account from FIREBASE_SERVICE_ACCOUNT env');
      } catch (e) {
        console.error('❌ Firebase Admin: Invalid FIREBASE_SERVICE_ACCOUNT JSON:', e.message);
      }
    }

    // 2) Fallback to local config file for local development
    if (!serviceAccountJson) {
      try {
        const jsonPath = path.join(__dirname, '../config/firebaseServiceAccount.json');
        if (fs.existsSync(jsonPath)) {
          const raw = fs.readFileSync(jsonPath, 'utf8');
          serviceAccountJson = JSON.parse(raw);
          console.log('✅ Firebase Admin: Loaded service account from firebaseServiceAccount.json');
        }
      } catch (e) {
        console.error('❌ Firebase Admin: Error reading firebaseServiceAccount.json:', e.message);
      }
    }

    if (!serviceAccountJson) {
      console.warn(
        '⚠️ Firebase Admin: No service account configured (FIREBASE_SERVICE_ACCOUNT env or config/firebaseServiceAccount.json). Notifications will be disabled.'
      );
      return;
    }

    admin.initializeApp({
      credential: admin.credential.cert(serviceAccountJson)
    });

    firebaseInitialized = true;
    console.log(
      '✅ Firebase Admin initialized successfully for project:',
      serviceAccountJson.project_id || '(unknown project)'
    );
  } catch (error) {
    console.error('❌ Error initializing Firebase Admin:', error.message);
    console.warn('⚠️ Push notifications will be disabled');
  }
};

// Initialize on module load
initializeFirebase();

/**
 * Send notification to a single user by their Google ID
 */
export const sendNotificationToUser = async (googleId, notification) => {
  if (!firebaseInitialized) {
    console.warn('⚠️ Firebase not initialized. Cannot send notification.');
    return { success: false, error: 'Firebase not initialized' };
  }

  try {
    const user = await User.findOne({ googleId });
    
    if (!user || !user.fcmToken) {
      return { 
        success: false, 
        error: 'User not found or no FCM token registered' 
      };
    }

    const message = {
      notification: {
        title: notification.title,
        body: notification.body,
      },
      data: notification.data || {},
      token: user.fcmToken,
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'default',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
          },
        },
      },
    };

    const response = await admin.messaging().send(message);
    console.log('✅ Notification sent successfully:', response);
    
    return { success: true, messageId: response };
  } catch (error) {
    console.error('❌ Error sending notification:', error);
    
    // If token is invalid, remove it from user
    if (error.code === 'messaging/invalid-registration-token' || 
        error.code === 'messaging/registration-token-not-registered') {
      await User.updateOne(
        { googleId },
        { $set: { fcmToken: null } }
      );
      console.log('🗑️ Removed invalid FCM token for user:', googleId);
    }
    
    return { success: false, error: error.message };
  }
};

/**
 * Send notification to multiple users
 */
export const sendNotificationToUsers = async (googleIds, notification) => {
  if (!firebaseInitialized) {
    console.warn('⚠️ Firebase not initialized. Cannot send notifications.');
    return { success: false, error: 'Firebase not initialized' };
  }

  try {
    const users = await User.find({ 
      googleId: { $in: googleIds },
      fcmToken: { $ne: null }
    });

    if (users.length === 0) {
      return { success: false, error: 'No users with FCM tokens found' };
    }

    const tokens = users.map(user => user.fcmToken).filter(Boolean);
    
    if (tokens.length === 0) {
      return { success: false, error: 'No valid FCM tokens found' };
    }

    const message = {
      notification: {
        title: notification.title,
        body: notification.body,
      },
      data: notification.data || {},
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'default',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
          },
        },
      },
    };

    // Send to multiple tokens
    const response = await admin.messaging().sendEachForMulticast({
      tokens,
      ...message,
    });

    console.log(`✅ Sent ${response.successCount} notifications, ${response.failureCount} failed`);

    // Remove invalid tokens
    if (response.failureCount > 0) {
      const invalidTokens = [];
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          invalidTokens.push(tokens[idx]);
        }
      });

      if (invalidTokens.length > 0) {
        await User.updateMany(
          { fcmToken: { $in: invalidTokens } },
          { $set: { fcmToken: null } }
        );
        console.log(`🗑️ Removed ${invalidTokens.length} invalid FCM tokens`);
      }
    }

    return { 
      success: true, 
      successCount: response.successCount,
      failureCount: response.failureCount 
    };
  } catch (error) {
    console.error('❌ Error sending notifications:', error);
    return { success: false, error: error.message };
  }
};

/**
 * Send notification to all users (broadcast)
 */
export const sendNotificationToAll = async (notification) => {
  if (!firebaseInitialized) {
    console.warn('⚠️ Firebase not initialized. Cannot send notifications.');
    return { success: false, error: 'Firebase not initialized' };
  }

  try {
    const users = await User.find({ 
      fcmToken: { $ne: null } 
    }).select('fcmToken');

    if (users.length === 0) {
      return { success: false, error: 'No users with FCM tokens found' };
    }

    const tokens = users.map(user => user.fcmToken).filter(Boolean);

    const message = {
      notification: {
        title: notification.title,
        body: notification.body,
      },
      data: notification.data || {},
      android: {
        priority: 'high',
        notification: {
          sound: 'default',
          channelId: 'default',
        },
      },
      apns: {
        payload: {
          aps: {
            sound: 'default',
          },
        },
      },
    };

    // Firebase allows up to 500 tokens per batch
    const batchSize = 500;
    let successCount = 0;
    let failureCount = 0;

    for (let i = 0; i < tokens.length; i += batchSize) {
      const batch = tokens.slice(i, i + batchSize);
      const response = await admin.messaging().sendEachForMulticast({
        tokens: batch,
        ...message,
      });

      successCount += response.successCount;
      failureCount += response.failureCount;

      // Remove invalid tokens
      if (response.failureCount > 0) {
        const invalidTokens = [];
        response.responses.forEach((resp, idx) => {
          if (!resp.success) {
            invalidTokens.push(batch[idx]);
          }
        });

        if (invalidTokens.length > 0) {
          await User.updateMany(
            { fcmToken: { $in: invalidTokens } },
            { $set: { fcmToken: null } }
          );
        }
      }
    }

    console.log(`✅ Broadcast sent: ${successCount} success, ${failureCount} failed`);
    
    return { 
      success: true, 
      successCount,
      failureCount 
    };
  } catch (error) {
    console.error('❌ Error broadcasting notifications:', error);
    return { success: false, error: error.message };
  }
};

