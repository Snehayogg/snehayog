# Push Notifications Setup Guide

This guide will help you set up Firebase Cloud Messaging (FCM) for free push notifications in your app.

## ✅ What's Already Done

1. ✅ Added `firebase_messaging` and `firebase_core` packages to Flutter
2. ✅ Added `firebase-admin` package to backend
3. ✅ Created notification service in backend
4. ✅ Created notification routes (save token, send notifications)
5. ✅ Added FCM token field to User model
6. ✅ Created Flutter notification service
7. ✅ Integrated Firebase initialization in main.dart

## 🔧 Setup Steps

### 1. Get Firebase Service Account Key

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select your project: **snehayog**
3. Click the gear icon ⚙️ → **Project Settings**
4. Go to **Service Accounts** tab
5. Click **Generate New Private Key**
6. Download the JSON file

### 2. Add Service Account to Backend

Add the Firebase service account JSON as an environment variable:

**For Railway (Production):**
```bash
# In Railway dashboard, add environment variable:
FIREBASE_SERVICE_ACCOUNT=<paste entire JSON content here>
```

**For Local Development:**
Add to your `.env` file:
```env
FIREBASE_SERVICE_ACCOUNT={"type":"service_account","project_id":"snehayog",...}
```

⚠️ **Important:** The entire JSON must be on a single line or properly escaped.

### 3. Install Backend Dependencies

```bash
cd snehayog/backend
npm install
```

### 4. Install Flutter Dependencies

```bash
cd snehayog/frontend
flutter pub get
```

### 5. Android Configuration

The Android manifest already has the necessary permissions. Make sure `google-services.json` is in place (it already is).

### 6. iOS Configuration

1. Make sure `GoogleService-Info.plist` is in `ios/Runner/` (it already is)
2. Enable Push Notifications capability in Xcode:
   - Open `ios/Runner.xcworkspace` in Xcode
   - Select Runner target → Signing & Capabilities
   - Click "+ Capability" → Add "Push Notifications"
   - Add "Background Modes" → Enable "Remote notifications"

## 📱 How to Use

### Send Notification to a User

```javascript
// From backend
POST /api/notifications/send
Headers: Authorization: Bearer <token>
Body: {
  "googleId": "user_google_id",
  "title": "New Video!",
  "body": "Check out this amazing video",
  "data": {
    "type": "video",
    "videoId": "123"
  }
}
```

### Send Notification to Multiple Users

```javascript
POST /api/notifications/send-multiple
Headers: Authorization: Bearer <token>
Body: {
  "googleIds": ["user1_google_id", "user2_google_id"],
  "title": "New Update!",
  "body": "We have exciting news",
  "data": {}
}
```

### Broadcast to All Users

```javascript
POST /api/notifications/broadcast
Headers: Authorization: Bearer <token>
Body: {
  "title": "App Update",
  "body": "New features available!",
  "data": {}
}
```

## 🎯 Example: Send Notification When User Uploads Video

Add this to your video upload route:

```javascript
import { sendNotificationToUsers } from '../services/notificationService.js';

// After video is uploaded successfully
const uploader = await User.findById(video.uploader);
const followers = await User.find({ _id: { $in: uploader.followers } });

if (followers.length > 0) {
  const followerIds = followers.map(f => f.googleId);
  await sendNotificationToUsers(followerIds, {
    title: `${uploader.name} uploaded a new video!`,
    body: video.title || 'Check it out',
    data: {
      type: 'video',
      videoId: video._id.toString()
    }
  });
}
```

## 🧪 Testing

1. **Test Token Registration:**
   - Open the app
   - Check logs for "✅ FCM Token obtained"
   - Check backend logs for "✅ FCM token saved"

2. **Test Sending Notification:**
   ```bash
   curl -X POST https://your-backend.com/api/notifications/send \
     -H "Authorization: Bearer YOUR_TOKEN" \
     -H "Content-Type: application/json" \
     -d '{
       "googleId": "YOUR_GOOGLE_ID",
       "title": "Test",
       "body": "This is a test notification"
     }'
   ```

3. **Test Background Notifications:**
   - Send a notification while app is in background
   - App should show notification in system tray
   - Tapping should open the app

## 📊 Firebase Console

You can also send test notifications from Firebase Console:
1. Go to Firebase Console → Cloud Messaging
2. Click "Send test message"
3. Enter FCM token from app logs
4. Send!

## 🔒 Security Notes

- FCM tokens are automatically removed if invalid
- Only authenticated users can save tokens
- Consider adding admin role check for broadcast endpoint
- Rate limit notification endpoints to prevent abuse

## 💰 Cost

**Firebase Cloud Messaging is 100% FREE** with unlimited messages! 🎉

## 🐛 Troubleshooting

### "Firebase not initialized"
- Check `FIREBASE_SERVICE_ACCOUNT` environment variable is set
- Verify JSON is valid and properly escaped

### "No FCM token registered"
- User needs to grant notification permission
- Check app logs for permission status
- On iOS, user must grant permission manually

### Notifications not received
- Check device has internet connection
- Verify FCM token is saved in database
- Check Firebase Console for delivery status
- Ensure app has notification permission

### Token refresh issues
- Tokens automatically refresh when needed
- Old tokens are cleaned up automatically

## 📚 Resources

- [Firebase Cloud Messaging Docs](https://firebase.google.com/docs/cloud-messaging)
- [Flutter Firebase Messaging](https://firebase.flutter.dev/docs/messaging/overview)

