# Like Feature Testing Guide

This guide helps you test and debug the like feature to verify if requests are reaching the backend.

## Quick Test Methods

### Method 1: Check Flutter Logs (Easiest)

1. **Open your Flutter app** and enable debug logging
2. **Click the like button** on any video
3. **Check the console/logs** for these messages:

```
🔴 ========== LIKE BUTTON CLICKED ==========
🔴 Like Handler: Calling API to sync with backend...
🔍 VideoService: Like request URL: <your-backend-url>/api/videos/<videoId>/like
📡 VideoService: Like response status: 200
✅ VideoService: Like toggled successfully
🔴 Like Handler: API call completed
✅ VideoFeedAdvanced: Synced with backend
```

**If you see these logs:**
- ✅ Request is being sent from Flutter
- ✅ Check backend logs to see if it's received

**If you DON'T see "Like request URL":**
- ❌ Request is not being sent (check network, authentication, etc.)

### Method 2: Check Backend Logs

1. **Open your backend terminal/console**
2. **Click like in the app**
3. **Look for these messages:**

```
🔍 Like API: Received request { googleId: '...', videoId: '...' }
✅ Like API: Video updated successfully with atomic operations, likes: X
✅ Like API: Successfully toggled like, returning video
```

**If you see these logs:**
- ✅ Request reached the backend
- ✅ Database was updated

**If you DON'T see "Received request":**
- ❌ Request is not reaching the backend (check network, URL, etc.)

### Method 3: Use Test Script

#### Step 1: Get Your JWT Token

From your Flutter app logs, find:
```
🔍 VideoService: Like request - Token starts with: <first-20-chars>
```

Or check your app's SharedPreferences for `jwt_token`.

#### Step 2: Get a Video ID

From your Flutter app, note any video ID from the logs or database.

#### Step 3: Run Test Script

```bash
cd snehayog/backend
node scripts/test-like-endpoint.js <videoId> <jwtToken>
```

**Example:**
```bash
node scripts/test-like-endpoint.js 507f1f77bcf86cd799439011 eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**What the script does:**
- ✅ Tests if backend is reachable
- ✅ Tests authentication
- ✅ Tests like endpoint
- ✅ Shows response data
- ✅ Verifies likes count matches likedBy length

### Method 4: Monitor Backend in Real-Time

```bash
cd snehayog/backend
node scripts/monitor-like-requests.js
```

This will show like requests as they come in (if log file exists).

Or manually watch your backend console for:
- `🔍 Like API: Received request`
- `✅ Like API: Successfully toggled like`

## Troubleshooting

### Problem: No logs in Flutter

**Solution:**
- Check if `AppLogger` is enabled
- Check if you're in debug mode
- Check Flutter console output

### Problem: Flutter logs show request, but backend doesn't receive it

**Possible causes:**
1. **Wrong backend URL** - Check `getBaseUrlWithFallback()` in `video_service.dart`
2. **Network issue** - Check internet connection
3. **CORS issue** - Check backend CORS settings
4. **Firewall** - Check if backend port is accessible

**Solution:**
- Verify backend URL in Flutter logs: `🔍 VideoService: Like request URL: ...`
- Test backend URL directly: `curl https://your-backend.com/api/health`

### Problem: Backend receives request but returns error

**Check backend logs for:**
- `❌ Like API Error: ...`
- Authentication errors
- Database errors

**Common errors:**
- `401/403` - Authentication failed (invalid token)
- `404` - Video or user not found
- `500` - Server error (check backend logs)

### Problem: Request succeeds but count reverts

**Possible causes:**
1. **Cache issue** - Backend cache not invalidated
2. **Database sync issue** - Likes count doesn't match likedBy length
3. **Frontend refresh** - App fetches old data from cache

**Solution:**
- Check backend logs for cache invalidation: `🧹 Cache invalidated after like/unlike`
- Check if likes count matches likedBy length in response
- Verify database directly: Check `likes` field vs `likedBy` array length

## Verification Checklist

After clicking like, verify:

- [ ] Flutter logs show "LIKE BUTTON CLICKED"
- [ ] Flutter logs show "Like request URL"
- [ ] Flutter logs show "Like response status: 200"
- [ ] Backend logs show "Received request"
- [ ] Backend logs show "Successfully toggled like"
- [ ] Database `likes` field is updated
- [ ] Database `likedBy` array is updated
- [ ] `likes` count matches `likedBy.length`
- [ ] UI shows correct like count
- [ ] Like persists after app restart

## Quick Debug Commands

```bash
# Test like endpoint
node scripts/test-like-endpoint.js <videoId> <token>

# Monitor backend logs
node scripts/monitor-like-requests.js

# Check backend health
curl https://your-backend.com/api/health

# Check if backend is running
curl https://your-backend.com/api/videos
```

## Need More Help?

1. **Check all logs** (Flutter + Backend) simultaneously
2. **Use test script** to isolate the issue
3. **Check network tab** in browser (if testing web)
4. **Verify database** directly using MongoDB shell

