# 🧪 Testing Guide - Video Share Fix

## Quick Test (5 minutes)

### Test 1: Share Link Format ✅

**Steps:**
1. App open करें
2. Home screen पर जाएं
3. कोई video open करें
4. Share button (📤) दबाएं
5. WhatsApp/Notes में paste करें

**Expected Result:**
```
🎬 Watch "Morning Yoga" on Snehayog!

👤 Created by: Sanjay Kumar
👁️ 1,234 views · ❤️ 56 likes

📱 Open in Snehayog App:
https://snehayog.app/video/abc123

#Snehayog #Yoga #Wellness
```

**✅ Pass if:**
- Link starts with `https://snehayog.app/video/`
- NO cloudinary.com visible
- NO r2.dev visible
- Stats (views, likes) shown

**❌ Fail if:**
- Link contains `cloudinary.com`
- Link contains `r2.dev`
- Direct video file URL visible

---

### Test 2: Share Tracking ✅

**Steps:**
1. Note current share count (e.g., "Share 5")
2. Click share button
3. Share somewhere
4. Reload video or swipe to next and back
5. Check share count

**Expected Result:**
- Share count increased by 1

**✅ Pass if:**
- Share count increments (e.g., 5 → 6)

**❌ Fail if:**
- Share count stays same
- Error message appears

---

## Backend Test (Optional)

### Test 3: Video Analysis Script ✅

**Steps:**
```bash
cd snehayog/backend
npm run analyze:videos
```

**Expected Output:**
```
📊 VIDEO URL DISTRIBUTION
═══════════════════════════════════════════════════════

✅ Cloudflare R2 URLs:  X videos
⚠️  Cloudinary URLs:     Y videos
❌ Local file paths:     Z videos
```

**✅ Pass if:**
- Script runs without errors
- Shows video counts
- Lists videos by type

**❌ Fail if:**
- Database connection error
- Script crashes
- No output shown

---

### Test 4: New Video Upload ✅

**Steps:**
1. App में new video upload करें
2. Processing complete होने दें
3. Database check करें:
   ```bash
   npm run analyze:videos
   ```

**Expected Result:**
- R2 URLs count should increase by 1
- New video URL should contain r2.dev or cloudflare domain

**✅ Pass if:**
- Video URL is R2 URL
- Video plays correctly
- Share link is clean (snehayog.app)

**❌ Fail if:**
- Video URL is Cloudinary
- Processing fails
- Video doesn't play

---

## Integration Test

### Test 5: End-to-End Flow ✅

**Steps:**
1. **Upload** new video
2. **Wait** for processing
3. **Find** video in feed
4. **Play** video (should work)
5. **Like** video
6. **Comment** on video
7. **Share** video
8. **Check** share message

**✅ Pass if ALL work:**
- Video uploads successfully
- Video plays smoothly
- Like/comment work
- Share shows clean link
- Stats update correctly

---

## Edge Cases

### Test 6: Old Video Share ✅

Test with video uploaded before fix:

**Steps:**
1. Find old video (if exists)
2. Try to share
3. Check share link

**Expected:**
- Even old videos should show clean snehayog.app link
- Message format should be new
- Stats should display

---

### Test 7: Multiple Shares ✅

**Steps:**
1. Share same video 3 times
2. Check if count increases each time

**Expected:**
- Share count: Initial → +1 → +2 → +3

---

## Automated Test Commands

```bash
# Backend folder में
cd snehayog/backend

# 1. Video analysis
npm run analyze:videos

# 2. Health check (if available)
npm run test

# 3. Start server
npm run dev
```

```bash
# Frontend folder में
cd snehayog/frontend

# 1. Run tests
flutter test

# 2. Build and test
flutter build apk --debug
flutter install

# 3. Check for issues
flutter analyze
```

---

## Checklist

Before marking as complete:

- [ ] Share button works
- [ ] Share link format is clean (snehayog.app)
- [ ] No Cloudinary URLs visible
- [ ] Share message is professional
- [ ] Stats shown in message
- [ ] Share count increments
- [ ] New videos upload to R2
- [ ] Old videos still work
- [ ] Analysis script runs
- [ ] No errors in console

---

## Troubleshooting

### Issue: Share button doesn't work

**Check:**
1. Internet connection
2. Auth token valid
3. Console for errors

**Fix:**
```dart
// Check in video_actions_widget.dart
// Line 112-139 should have _handleShare method
```

### Issue: Share count not incrementing

**Check:**
1. Backend server running
2. API endpoint `/api/videos/:id/share` working
3. Network request succeeds

**Fix:**
```bash
# Check backend logs
cd snehayog/backend
npm run dev
```

### Issue: Analysis script fails

**Check:**
1. MongoDB connection string in .env
2. Database accessible
3. Correct path to script

**Fix:**
```bash
# Verify .env
cat .env | grep MONGODB_URI

# Test connection
node scripts/migrateCloudinaryToR2.js
```

---

## Success Criteria

✅ **All tests pass**
✅ **Share works smoothly**
✅ **Links are clean**
✅ **No user complaints**
✅ **Stats update correctly**

---

## Report Format

After testing, report:

```
✅ PASS - Share link format correct
✅ PASS - Share tracking works
✅ PASS - New videos use R2
⚠️ WARNING - 5 old videos still on Cloudinary (expected)
✅ PASS - Analysis script works
```

---

**Happy Testing!** 🎉

Questions? Check: `VIDEO_SHARE_FIX.md`

