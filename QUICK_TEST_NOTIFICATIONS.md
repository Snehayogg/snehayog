# 🚀 Quick Test Guide - Push Notifications

## Fastest Way to Test (3 Steps)

### Step 1: Get Your Google ID
```bash
# Option A: Check your database
# In MongoDB or backend console:
db.users.findOne({ email: "your@email.com" }, { googleId: 1 })

# Option B: Check app logs when you log in
# Look for user data with googleId field
```

### Step 2: Edit Test Script
Open `backend/test-notification.js` and set:
```javascript
const TEST_GOOGLE_ID = 'YOUR_ACTUAL_GOOGLE_ID';
// OR
const TEST_EMAIL = 'your@email.com';
```

### Step 3: Run Test
```bash
cd snehayog/backend
node test-notification.js
```

**That's it!** Check your device for the notification.

---

## Alternative: Test via API

### Using curl:
```bash
curl -X POST https://snehayog.site/api/notifications/send \
  -H "Authorization: Bearer YOUR_JWT_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "googleId": "YOUR_GOOGLE_ID",
    "title": "Test",
    "body": "Testing notifications"
  }'
```

### Using Postman/Thunder Client:
1. **Method**: POST
2. **URL**: `https://snehayog.site/api/notifications/send`
3. **Headers**:
   - `Authorization: Bearer YOUR_TOKEN`
   - `Content-Type: application/json`
4. **Body**:
   ```json
   {
     "googleId": "YOUR_GOOGLE_ID",
     "title": "Test",
     "body": "Testing notifications"
   }
   ```

---

## Alternative: Test via Firebase Console

1. Go to: https://console.firebase.google.com/
2. Select project: **snehayog**
3. Navigate: **Cloud Messaging** → **Send test message**
4. Get FCM token from app logs: `✅ FCM Token obtained: ...`
5. Paste token and send!

---

## What to Check

### ✅ Success Indicators:
- Backend shows: `✅ Notification sent successfully`
- Device receives notification
- Notification appears in system tray

### ❌ If It Fails:
1. **Check FCM token is registered:**
   ```javascript
   db.users.findOne({ googleId: "YOUR_ID" }, { fcmToken: 1 })
   ```

2. **Check Firebase is initialized:**
   - Backend logs should show: `✅ Firebase Admin initialized successfully`

3. **Check environment variable:**
   ```bash
   echo $FIREBASE_SERVICE_ACCOUNT
   # Should show JSON (or check Railway/env vars)
   ```

---

## Test Different Scenarios

### Test 1: App in Foreground
- Keep app open
- Send notification
- Check app logs: `📱 Foreground message received`

### Test 2: App in Background
- Minimize app
- Send notification
- Check notification tray

### Test 3: App Terminated
- Force close app
- Send notification
- Check notification tray
- Tap to open app

---

## Need Help?

See full guide: `TEST_NOTIFICATIONS.md`

