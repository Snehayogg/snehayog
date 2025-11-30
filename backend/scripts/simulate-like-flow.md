# Simulated Like Flow - Dry Run

This document shows what happens when you click the like button, step by step.

## 🎬 Complete Like Flow Simulation

### Step 1: User Clicks Like Button

**Flutter App:**
```
🔴 ========== LIKE BUTTON CLICKED ==========
🔴 Video ID: 507f1f77bcf86cd799439011
🔴 Video Name: Morning Yoga Flow
🔴 Current User ID: user123
🔴 Current Likes: 41
🔴 Current LikedBy: 41 users
🔴 Like Handler: Current state - wasLiked: false, originalLikes: 41
```

### Step 2: Optimistic UI Update

**Flutter App:**
```
🔴 Like Handler: Updating UI optimistically (before API call)
🔴 Like Handler: Optimistic LIKE - new count: 42
```
*UI shows heart filled and count incremented immediately*

### Step 3: API Request Sent

**Flutter App:**
```
🔴 Like Handler: Calling API to sync with backend...
🔴 Like Handler: API call starting at 2024-01-15T10:30:00.000Z
🔄 VideoService: Toggling like for video: 507f1f77bcf86cd799439011
🔍 VideoService: Like request - Token present: true
🔍 VideoService: Like request - Token length: 245
🔍 VideoService: Like request URL: https://your-backend.com/api/videos/507f1f77bcf86cd799439011/like
🔍 VideoService: User data - googleId: user123
🔍 VideoService: User data - id: user123
```

**Network Request:**
```
POST https://your-backend.com/api/videos/507f1f77bcf86cd799439011/like
Headers:
  Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
  Content-Type: application/json
Body: {}
```

### Step 4: Backend Receives Request

**Backend Console:**
```
🔍 Like API: Received request { googleId: 'user123', videoId: '507f1f77bcf86cd799439011' }
🔍 Like API: Video found, current likes: 41, likedBy: [ObjectId('...'), ...]
🔍 Like API: Added like (atomic operation)
✅ Like API: Video updated successfully with atomic operations, likes: 42
🧹 Cache invalidated after like/unlike - ensuring fresh data on next fetch
```

**Database Operation:**
```javascript
// Atomic MongoDB operation
Video.findByIdAndUpdate(
  videoId,
  { 
    $push: { likedBy: userObjectId },
    $inc: { likes: 1 }
  },
  { new: true }
)
```

### Step 5: Backend Sends Response

**Backend Response:**
```json
{
  "_id": "507f1f77bcf86cd799439011",
  "videoName": "Morning Yoga Flow",
  "likes": 42,
  "likedBy": ["user1", "user2", "user3", "user123"],
  "views": 1234,
  "uploader": {
    "id": "instructor456",
    "name": "Yoga Master",
    "profilePic": "https://..."
  },
  ...
}
```

**Backend Console:**
```
🔍 Like API: Final response data {
  likes: 42,
  likedByLength: 4,
  likedByGoogleIds: '4 users',
  videoId: '507f1f77bcf86cd799439011'
}
✅ Like API: Successfully toggled like, returning video
```

### Step 6: Flutter Receives Response

**Flutter App:**
```
📡 VideoService: Like response status: 200
📡 VideoService: Like response body: {"_id":"507f1f77bcf86cd799439011",...}
✅ VideoService: Like toggled successfully
🔴 Like Handler: API call completed at 2024-01-15T10:30:00.245Z
✅ Successfully toggled like for video 507f1f77bcf86cd799439011
🔴 Like Handler: Backend response - likes: 42, likedBy: 4
```

### Step 7: UI Updated with Backend Data

**Flutter App:**
```
🔴 Like Handler: Updating video in list with backend response
✅ VideoFeedAdvanced: Synced with backend - likes: 42, likedBy: 4
🔴 Like Handler: UI updated with backend data
🔴 ========== LIKE SUCCESSFUL ==========
```

*UI now shows the correct count from backend*

## ❌ Error Scenarios

### Scenario 1: Network Error

**Flutter App:**
```
🔴 Like Handler: Calling API to sync with backend...
❌ Error handling like: Exception: No internet connection
🔴 Like Handler: Reverting optimistic update due to error
🔴 Like Handler: Reverted to original state - likes: 41
🔴 ========== LIKE FAILED ==========
```

### Scenario 2: Authentication Error

**Flutter App:**
```
🔴 Like Handler: Calling API to sync with backend...
📡 VideoService: Like response status: 401
❌ VideoService: Authentication failed (401)
🔴 Like Handler: Reverting optimistic update
```

**Backend Console:**
```
❌ Like API: Missing userId from authentication
```

### Scenario 3: Video Not Found

**Flutter App:**
```
📡 VideoService: Like response status: 404
❌ VideoService: Not found (404)
```

**Backend Console:**
```
❌ Like API: Video not found with ID: 507f1f77bcf86cd799439011
```

### Scenario 4: Count Mismatch (Bug)

**Backend Response:**
```json
{
  "likes": 40,  // Wrong!
  "likedBy": ["user1", "user2", "user3", "user123"]  // 4 users
}
```

**Flutter App:**
```
⚠️ WARNING: Likes count (40) does not match likedBy length (4)!
```

## ✅ Success Indicators

1. ✅ Flutter logs show "LIKE BUTTON CLICKED"
2. ✅ Flutter logs show "Like request URL"
3. ✅ Backend logs show "Received request"
4. ✅ Backend logs show "Successfully toggled like"
5. ✅ Response status is 200
6. ✅ Likes count matches likedBy.length
7. ✅ UI shows updated count
8. ✅ Count persists after app restart

## 🔍 Debugging Checklist

When testing, verify:

- [ ] Flutter logs show button click
- [ ] Flutter logs show request being sent
- [ ] Backend logs show request received
- [ ] Backend logs show database update
- [ ] Response status is 200
- [ ] Response has correct likes count
- [ ] Response likedBy array is correct
- [ ] Likes count matches likedBy.length
- [ ] UI updates correctly
- [ ] Database has correct values
- [ ] Count persists after refresh

## 🧪 Test Commands

```bash
# Dry run (simulation)
node scripts/test-like-endpoint-dryrun.js

# Real test
node scripts/test-like-endpoint.js <videoId> <jwtToken>

# Monitor logs
npm run monitor:likes
```

