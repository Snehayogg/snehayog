/**
 * Simple script to test push notifications
 * 
 * Usage:
 * 1. Set your Google ID in the script below
 * 2. Make sure FIREBASE_SERVICE_ACCOUNT is set in environment
 * 3. Run: node test-notification.js
 */

import dotenv from 'dotenv';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

dotenv.config();

// Set FIREBASE_SERVICE_ACCOUNT from JSON file if not in environment
if (!process.env.FIREBASE_SERVICE_ACCOUNT) {
  const __filename = fileURLToPath(import.meta.url);
  const __dirname = path.dirname(__filename);
  const serviceAccountPath = path.join(__dirname, 'serviceAccountKey.json');
  
  if (fs.existsSync(serviceAccountPath)) {
    console.log('📁 Loading Firebase service account from JSON file...');
    const serviceAccount = JSON.parse(fs.readFileSync(serviceAccountPath, 'utf8'));
    process.env.FIREBASE_SERVICE_ACCOUNT = JSON.stringify(serviceAccount);
    console.log('✅ Firebase service account loaded from file\n');
  } else {
    console.warn('⚠️ serviceAccountKey.json not found. Make sure FIREBASE_SERVICE_ACCOUNT is set in .env');
  }
}

import { sendNotificationToUser, sendNotificationToAll } from './services/notificationService.js';
import User from './models/User.js';
import databaseManager from './config/database.js';

// ============================================
// CONFIGURATION - EDIT THESE VALUES
// ============================================

// Option 1: Test with specific user's Google ID
const TEST_GOOGLE_ID = 'YOUR_GOOGLE_ID_HERE'; // Replace with your actual Google ID

// Option 2: Test with email (will find Google ID automatically)
const TEST_EMAIL = 'sanjeev.yadav1201@gmail.com'; // Replace with your email

// Option 3: Test broadcast to all users (set to true to test)
const TEST_BROADCAST = false; // Set to true to send to all users

// ============================================
// TEST FUNCTION
// ============================================

async function testNotification() {
  try {
    console.log('🧪 Starting notification test...\n');

    // Connect to database
    await databaseManager.connect();
    console.log('✅ Connected to database\n');

    let googleId = TEST_GOOGLE_ID;

    // If Google ID not set, try to find by email
    if (googleId === 'YOUR_GOOGLE_ID_HERE' && TEST_EMAIL) {
      console.log(`🔍 Looking up user by email: ${TEST_EMAIL}`);
      const user = await User.findOne({ email: TEST_EMAIL });
      if (user) {
        googleId = user.googleId;
        console.log(`✅ Found user: ${user.name} (${user.googleId})\n`);
      } else {
        console.error('❌ User not found with email:', TEST_EMAIL);
        process.exit(1);
      }
    }

    // Check if user has FCM token
    if (!TEST_BROADCAST) {
      const user = await User.findOne({ googleId });
      if (!user) {
        console.error('❌ User not found');
        process.exit(1);
      }

      if (!user.fcmToken) {
        console.error('❌ User does not have FCM token registered');
        console.log('💡 Make sure the app is running and user is logged in');
        process.exit(1);
      }

      console.log(`📱 User FCM Token: ${user.fcmToken.substring(0, 20)}...`);
      console.log(`👤 User: ${user.name} (${user.email})\n`);
    }

    // Prepare test notification
    const notification = {
      title: '🧪 Test Notification',
      body: `This is a test notification sent at ${new Date().toLocaleString()}`,
      data: {
        type: 'test',
        timestamp: new Date().toISOString(),
        testId: Math.random().toString(36).substring(7)
      }
    };

    console.log('📤 Sending test notification...\n');
    console.log('Notification Details:');
    console.log(`  Title: ${notification.title}`);
    console.log(`  Body: ${notification.body}`);
    console.log(`  Data: ${JSON.stringify(notification.data, null, 2)}\n`);

    let result;

    if (TEST_BROADCAST) {
      console.log('📢 Broadcasting to ALL users...\n');
      result = await sendNotificationToAll(notification);
    } else {
      console.log(`📤 Sending to user: ${googleId}\n`);
      result = await sendNotificationToUser(googleId, notification);
    }

    // Display results
    console.log('='.repeat(50));
    if (result.success) {
      console.log('✅ TEST SUCCESSFUL!\n');
      if (TEST_BROADCAST) {
        console.log(`📊 Results:`);
        console.log(`   ✅ Success: ${result.successCount} users`);
        console.log(`   ❌ Failed: ${result.failureCount} users`);
      } else {
        console.log(`📱 Message ID: ${result.messageId}`);
      }
      console.log('\n💡 Check your device for the notification!');
    } else {
      console.log('❌ TEST FAILED!\n');
      console.log(`Error: ${result.error}\n`);
      console.log('💡 Troubleshooting:');
      console.log('   1. Check if FIREBASE_SERVICE_ACCOUNT is set');
      console.log('   2. Verify user has FCM token registered');
      console.log('   3. Check Firebase Console for errors');
    }
    console.log('='.repeat(50));

    // Disconnect from database
    await databaseManager.disconnect();
    process.exit(result.success ? 0 : 1);

  } catch (error) {
    console.error('\n❌ Error during test:', error);
    console.error('\nStack trace:', error.stack);
    process.exit(1);
  }
}

// Run the test
testNotification();

