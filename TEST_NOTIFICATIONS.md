# How to Test Notifications Manually

This guide shows you how to test if push notifications are working in your app.

## 🧪 Testing Methods

### Method 1: Test via API (Recommended)

#### Step 1: Get Your Auth Token

1. **Open your Flutter app** and log in
2. **Check app logs** for your JWT token, OR
3. **Get token from SharedPreferences** (for testing, you can add a debug button)

#### Step 2: Get Your Google ID

You need your `googleId` to send a test notification. You can:
- Check your user profile in the app
- Check database: `User.findOne({ email: 'your@email.com' })`
- Or use the broadcast endpoint to send to all users

#### Step 3: Send Test Notification

**Option A: Send to Yourself**

```bash
curl -X POST https://snehayog.site/api/notifications/send \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "googleId": "YOUR_GOOGLE_ID",
    "title": "Test Notification",
    "body": "This is a test notification to verify everything works!",
    "data": {
      "type": "test",
      "message": "Testing notifications"
    }
  }'
```

**Option B: Send to All Users (Broadcast)**

```bash
curl -X POST https://snehayog.site/api/notifications/broadcast \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test Broadcast",
    "body": "Testing broadcast notifications to all users",
    "data": {
      "type": "test"
    }
  }'
```

**Option C: Trigger Monthly Notification Manually**

```bash
curl -X POST https://snehayog.site/api/notifications/monthly/trigger \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json"
```

### Method 2: Test via Firebase Console

1. **Go to Firebase Console**: https://console.firebase.google.com/
2. **Select your project**: `snehayog`
3. **Navigate to**: Cloud Messaging → Send test message
4. **Get FCM Token from app logs**:
   - Open your Flutter app
   - Check logs for: `✅ FCM Token obtained: ...`
   - Copy the token
5. **Paste token** in Firebase Console
6. **Enter notification**:
   - Title: "Test from Firebase"
   - Body: "Testing notifications"
7. **Click "Test"**

### Method 3: Test via Postman/Thunder Client

1. **Create new POST request**
2. **URL**: `https://snehayog.site/api/notifications/send`
3. **Headers**:
   ```
   Authorization: Bearer YOUR_JWT_TOKEN
   Content-Type: application/json
   ```
4. **Body (JSON)**:
   ```json
   {
     "googleId": "YOUR_GOOGLE_ID",
     "title": "Test from Postman",
     "body": "This is a test notification",
     "data": {
       "type": "test"
     }
   }
   ```
5. **Send request**

## ✅ Verification Checklist

### 1. Check FCM Token Registration

**In Flutter App Logs:**
```
✅ Firebase initialized
✅ Notification permission granted
✅ FCM Token obtained: [token]...
✅ FCM token saved to backend
```

**In Backend Logs:**
```
✅ FCM token saved for user: [name] ([googleId])
```

**In Database:**
```javascript
// Check if token is saved
const user = await User.findOne({ googleId: 'YOUR_GOOGLE_ID' });
console.log('FCM Token:', user.fcmToken);
```

### 2. Check Notification Delivery

**When App is in Foreground:**
- Check app logs for: `📱 Foreground message received`
- Notification data should be logged

**When App is in Background:**
- Notification should appear in system notification tray
- Tapping should open the app

**When App is Terminated:**
- Notification should appear in system notification tray
- Tapping should open the app

### 3. Check Backend Logs

**Successful Send:**
```
✅ Notification sent successfully: [messageId]
```

**Failed Send:**
```
❌ Error sending notification: [error]
```

## 🔍 Troubleshooting

### Issue: "FCM token is null"

**Solution:**
1. Make sure user granted notification permission
2. Check if Firebase is initialized properly
3. Check app logs for FCM token generation errors
4. Try uninstalling and reinstalling the app

### Issue: "User not found or no FCM token registered"

**Solution:**
1. Make sure user is logged in
2. Check if FCM token was saved to backend
3. Verify `googleId` is correct
4. Check database: `User.findOne({ googleId: '...' })`

### Issue: "Firebase not initialized"

**Solution:**
1. Check `FIREBASE_SERVICE_ACCOUNT` environment variable is set
2. Verify service account JSON is valid
3. Check backend logs for Firebase initialization errors

### Issue: Notification Not Received

**Check:**
1. ✅ FCM token is registered in database
2. ✅ Notification permission is granted (iOS)
3. ✅ App is not in Do Not Disturb mode
4. ✅ Device has internet connection
5. ✅ Check Firebase Console for delivery status

## 📱 Quick Test Script

Create a test file: `backend/test-notification.js`

```javascript
import { sendNotificationToUser } from './services/notificationService.js';
import User from './models/User.js';

// Test notification
async function testNotification() {
  try {
    // Replace with your actual Google ID
    const googleId = 'YOUR_GOOGLE_ID';
    
    const result = await sendNotificationToUser(googleId, {
      title: 'Test Notification',
      body: 'This is a test notification!',
      data: {
        type: 'test',
        timestamp: new Date().toISOString()
      }
    });
    
    if (result.success) {
      console.log('✅ Test notification sent successfully!');
      console.log('Message ID:', result.messageId);
    } else {
      console.error('❌ Test notification failed:', result.error);
    }
  } catch (error) {
    console.error('❌ Error:', error);
  }
}

testNotification();
```

Run it:
```bash
node backend/test-notification.js
```

## 🎯 Step-by-Step Testing Process

### Step 1: Verify Setup
- [ ] Firebase Admin is initialized (check backend logs)
- [ ] FCM token is registered (check database)
- [ ] User has notification permission (check app logs)

### Step 2: Send Test Notification
- [ ] Use API endpoint or Firebase Console
- [ ] Check backend logs for success/failure
- [ ] Verify notification is received

### Step 3: Test Different States
- [ ] App in foreground
- [ ] App in background
- [ ] App terminated

### Step 4: Verify Data Handling
- [ ] Notification data is received correctly
- [ ] Deep links work (if configured)
- [ ] Navigation works (if configured)

## 📊 Expected Results

### Success Indicators:
- ✅ Backend logs show: "Notification sent successfully"
- ✅ App receives notification (foreground/background/terminated)
- ✅ Notification appears in system tray
- ✅ Tapping notification opens app (if configured)

### Failure Indicators:
- ❌ Backend logs show errors
- ❌ No notification received
- ❌ Invalid token errors
- ❌ Firebase initialization errors

## 🔗 Useful Commands

**Check cron job status:**
```bash
curl -X GET https://snehayog.site/api/notifications/monthly/status \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**Check user's FCM token:**
```javascript
// In MongoDB or backend console
db.users.findOne({ googleId: "YOUR_GOOGLE_ID" }, { fcmToken: 1 })
```

**List all users with FCM tokens:**
```javascript
db.users.find({ fcmToken: { $ne: null } }, { name: 1, email: 1, fcmToken: 1 })
```

## 💡 Pro Tips

1. **Test with multiple devices** to ensure cross-platform compatibility
2. **Test at different times** to catch timezone issues
3. **Monitor Firebase Console** for delivery analytics
4. **Check server logs** for detailed error messages
5. **Use broadcast sparingly** during testing (sends to all users!)

