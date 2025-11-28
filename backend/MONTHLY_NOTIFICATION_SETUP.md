# Monthly Notification Cron Job Setup

This guide explains how the monthly notification cron job works and how to customize it.

## ✅ What's Already Set Up

1. ✅ **Firebase Admin SDK** - Already installed and configured
2. ✅ **Notification Service** - Already created with all necessary functions
3. ✅ **Monthly Cron Job** - Created and integrated into server
4. ✅ **Automatic Startup** - Cron job starts automatically when server starts

## 📅 How It Works

The cron job is configured to run on the **1st of every month at 9:00 AM (Asia/Kolkata timezone)**.

### Cron Expression
```
'0 9 1 * *'
```
- `0` - minute (0th minute)
- `9` - hour (9 AM)
- `1` - day of month (1st day)
- `*` - month (every month)
- `*` - day of week (any day)

## 🎯 Current Notification Message

The default notification sent on the 1st of every month:

**Title:** `Welcome to [Month]! 🎉`  
**Body:** `Start your month with amazing content! Check out what's new on Vayug.`

**Data Payload:**
```json
{
  "type": "monthly_update",
  "month": "January",
  "year": "2025",
  "timestamp": "2025-01-01T09:00:00.000Z"
}
```

## 🔧 Customization

### Change Notification Message

Edit `snehayog/backend/services/monthlyNotificationCron.js`:

```javascript
// Customize your notification message here
const notification = {
  title: `Your Custom Title for ${monthName}! 🎉`,
  body: `Your custom message here.`,
  data: {
    type: 'monthly_update',
    month: monthName,
    year: year.toString(),
    timestamp: currentDate.toISOString(),
    // Add custom data fields here
    customField: 'customValue'
  }
};
```

### Change Schedule

Edit the cron expression in `monthlyNotificationCron.js`:

```javascript
// Example: Run on 1st of every month at 10:00 AM
this.job = cron.schedule('0 10 1 * *', async () => {
  await this.sendMonthlyNotification();
}, {
  scheduled: true,
  timezone: 'Asia/Kolkata'
});
```

**Common Cron Patterns:**
- `'0 9 1 * *'` - 1st of every month at 9:00 AM
- `'0 12 1 * *'` - 1st of every month at 12:00 PM
- `'0 0 1 * *'` - 1st of every month at midnight
- `'0 9 1,15 * *'` - 1st and 15th of every month at 9:00 AM
- `'0 9 * * 1'` - Every Monday at 9:00 AM

### Change Timezone

Edit the timezone in the cron schedule:

```javascript
timezone: 'America/New_York'  // US Eastern Time
timezone: 'Europe/London'      // UK Time
timezone: 'Asia/Tokyo'        // Japan Time
timezone: 'UTC'               // UTC
```

## 🧪 Testing

### Manual Trigger (API)

You can manually trigger the monthly notification for testing:

```bash
# Get your auth token first, then:
curl -X POST https://your-backend.com/api/notifications/monthly/trigger \
  -H "Authorization: Bearer YOUR_TOKEN" \
  -H "Content-Type: application/json"
```

### Check Cron Job Status

```bash
curl -X GET https://your-backend.com/api/notifications/monthly/status \
  -H "Authorization: Bearer YOUR_TOKEN"
```

Response:
```json
{
  "success": true,
  "isRunning": true,
  "schedule": "0 9 1 * * (1st of every month at 9:00 AM)",
  "timezone": "Asia/Kolkata"
}
```

### Test Locally

1. Start your backend server
2. Check logs for: `✅ Monthly notification cron job started`
3. Manually trigger via API or wait for the scheduled time
4. Check logs for notification sending results

## 📊 Monitoring

The cron job logs detailed information:

```
📅 Monthly notification cron: Starting...
📊 Found 150 users with FCM tokens
✅ Monthly notification sent successfully!
   📊 Success: 148 users
   ❌ Failed: 2 users
   ⏱️ Duration: 3.45 seconds
```

## 🔍 Troubleshooting

### Cron Job Not Running

1. **Check if it started:**
   - Look for `✅ Monthly notification cron job started` in server logs
   - Check status via API: `GET /api/notifications/monthly/status`

2. **Check Firebase Configuration:**
   - Ensure `FIREBASE_SERVICE_ACCOUNT` environment variable is set
   - Check Firebase Admin initialization logs

3. **Check Server Time:**
   - Ensure server timezone is correct
   - Verify cron expression matches your timezone

### Notifications Not Received

1. **Check FCM Tokens:**
   - Verify users have valid FCM tokens in database
   - Check for invalid token cleanup logs

2. **Check Firebase Console:**
   - Go to Firebase Console → Cloud Messaging
   - Check delivery reports

3. **Check Logs:**
   - Look for error messages in server logs
   - Check for token invalidation messages

## 🚀 Production Deployment

### Railway/Cloud Deployment

1. **Set Environment Variable:**
   ```bash
   FIREBASE_SERVICE_ACCOUNT=<your-service-account-json>
   ```

2. **Verify Cron Job Starts:**
   - Check server startup logs
   - Should see: `✅ Monthly notification cron job started`

3. **Monitor First Run:**
   - Wait for 1st of month at scheduled time
   - Check logs for execution results
   - Verify notifications are sent

### Local Development

The cron job will start automatically when you run:
```bash
npm start
```

## 📝 Notes

- The cron job automatically handles:
  - Batching notifications (500 tokens per batch)
  - Invalid token cleanup
  - Error handling and logging
  - Graceful shutdown

- The cron job stops automatically when the server shuts down

- You can customize the notification message, schedule, and timezone as needed

## 🔗 Related Files

- `backend/services/monthlyNotificationCron.js` - Cron job service
- `backend/services/notificationService.js` - Notification sending logic
- `backend/server.js` - Server initialization (starts cron job)
- `backend/routes/notificationRoutes.js` - API endpoints

