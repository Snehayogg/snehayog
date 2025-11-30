# Quick Like Test Guide

## 🚀 Fastest Way to Test

### Step 1: Click Like in Your App
Just click the like button on any video in your Flutter app.

### Step 2: Check Logs

**In Flutter Console, look for:**
```
🔴 ========== LIKE BUTTON CLICKED ==========
🔍 VideoService: Like request URL: ...
📡 VideoService: Like response status: 200
```

**In Backend Console, look for:**
```
🔍 Like API: Received request { googleId: '...', videoId: '...' }
✅ Like API: Successfully toggled like
```

### Step 3: Interpret Results

✅ **If you see both Flutter AND Backend logs:**
- Request is working! Check database if count is wrong.

❌ **If you see Flutter logs but NO Backend logs:**
- Request is sent but not reaching backend (network/URL issue)

❌ **If you see NO Flutter logs:**
- Request is not being sent (check authentication, network)

## 🧪 Use Test Script

```bash
# Get video ID and JWT token from your app logs
cd snehayog/backend
npm run test:like <videoId> <jwtToken>
```

## 📊 Monitor Real-Time

```bash
cd snehayog/backend
npm run monitor:likes
```

## 🔍 What to Check

1. **Flutter logs** → Is request being sent?
2. **Backend logs** → Is request being received?
3. **Database** → Is data being saved?
4. **Response** → Does likes count match likedBy length?

## ❓ Still Not Working?

Read the full guide: `README-LIKE-TESTING.md`

