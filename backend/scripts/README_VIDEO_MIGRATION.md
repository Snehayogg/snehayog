# Video URL Migration Guide

## समस्या क्या है?

जब आप video share करते हैं, तो link में "cloudinary" आता है क्योंकि आपके database में **पुराने videos** अभी भी Cloudinary URLs के साथ stored हैं।

### वर्तमान स्थिति:

- ✅ **नई videos**: Cloudflare R2 में upload होती हैं (FREE bandwidth!)
- ⚠️ **पुरानी videos**: अभी भी Cloudinary URLs के साथ database में हैं
- 🔗 **Share करते समय**: App database से direct URL लेता है

## Solution

### 1️⃣ पहले Analysis करें (Recommended)

यह देखने के लिए कि कितनी videos Cloudinary URLs के साथ हैं:

```bash
cd snehayog/backend
node scripts/migrateCloudinaryToR2.js
```

**Output Example:**
```
📊 VIDEO URL DISTRIBUTION
═══════════════════════════════════════════════════════

✅ Cloudflare R2 URLs:  15 videos
⚠️  Cloudinary URLs:     5 videos (need migration)
❌ Local file paths:     2 videos (processing failed)
```

### 2️⃣ Failed Videos को Clean करें (Optional)

अगर कुछ videos processing में fail हो गई हैं (local file paths के साथ), तो उन्हें delete करें:

```bash
cd snehayog/backend
node scripts/migrateCloudinaryToR2.js --delete-failed
```

## आपके पास 3 Options हैं:

### Option 1: कुछ मत करो (Recommended for now) ✅

**अब से सभी नई videos R2 में upload होंगी और proper links के साथ share होंगी।**

- ✅ Simple और कोई risk नहीं
- ✅ नई videos में कोई issue नहीं
- ⚠️ पुरानी videos अभी भी Cloudinary URLs show करेंगी
- 💰 पुरानी videos के लिए Cloudinary bandwidth charges

**यह best option है अगर:**
- आपके पास कम पुरानी videos हैं (< 10)
- पुरानी videos rarely share होती हैं
- आप risk नहीं लेना चाहते

### Option 2: पुरानी Videos को Re-upload करें

Old videos को delete करके दोबारा upload करें।

**Steps:**
1. Video को locally save करें
2. App में delete करें
3. Fresh upload करें (automatically R2 में जाएगी)

**Pros:**
- ✅ Fresh upload, better quality
- ✅ R2 benefits मिलेंगे
- ✅ कोई migration complexity नहीं

**Cons:**
- ⚠️ Manual work
- ⚠️ Views, likes, comments lost होंगे

### Option 3: Automatic Migration (Advanced) 🔥

Cloudinary से videos download करके R2 में upload करें (सभी data preserve रहेगा)।

**⚠️ यह complex है और अभी implement नहीं है।**

यह approach तब बढ़िया है जब:
- बहुत सारी old videos हैं (> 50)
- Videos को manually re-upload नहीं कर सकते
- Views/likes/comments preserve करने हैं

## Share Functionality में क्या Change हुआ है?

अब share करते समय:

### पहले (Old):
```
🔗 Watch on Snehayog: https://res.cloudinary.com/...
```
- Direct video URL share होता था
- Storage backend visible था

### अब (New): ✅
```
🎬 Watch "Yoga Tutorial" on Snehayog!

👤 Created by: John Doe
👁️ 1,234 views · ❤️ 56 likes

📱 Open in Snehayog App:
https://snehayog.app/video/abc123

#Snehayog #Yoga #Wellness
```

- App deep link share होता है
- Professional message
- Storage backend hidden
- Stats show होते हैं

## अगले Steps:

1. **अभी के लिए:** बस नई videos upload करें - वो automatically R2 में जाएंगी ✅

2. **Check करें:** 
   ```bash
   node scripts/migrateCloudinaryToR2.js
   ```

3. **अगर ज्यादा old videos हैं:** एक-एक करके re-upload करें

4. **Future में:** सभी videos R2 में होंगी और share proper links के साथ होगा

## Technical Details

### Backend Changes:
- ✅ `hybridVideoService.js` - R2 में upload करता है
- ✅ `uploadRoutes.js` - नई videos R2 URLs के साथ save होती हैं
- ✅ Video model में `videoUrl` field R2 URL store करता है

### Frontend Changes:
- ✅ `video_actions_widget.dart` - App deep link share करता है
- ✅ `video_service.dart` - Share tracking improved
- ✅ Direct video URLs share नहीं होते

## Cost Savings

### Cloudinary (Old):
- Storage: $0.02/GB/month
- Bandwidth: $0.04/GB
- Processing: $0.001 per video

### Cloudflare R2 (New):
- Storage: $0.015/GB/month (25% savings)
- **Bandwidth: $0 (FREE!)** 🎉
- Processing: Local FFmpeg (FREE)

**Example with 100 videos (5GB) and 10,000 monthly views:**
- Old: ~$6/month
- New: ~$0.075/month
- **Savings: 98.75%** 💰

## Need Help?

अगर कोई confusion है या help चाहिए तो पूछो!

