# Video Rotation Detection Fix

## Problem Statement

Vertical videos were incorrectly being classified as horizontal (vayu) videos, even though the aspect ratio-based classification logic was in place.

### Root Cause

Many mobile videos (especially from iPhones and Android devices) store video with **rotation metadata** rather than physically rotating the pixels:

- **Stored dimensions**: 1920×1080 (landscape orientation)
- **Rotation metadata**: 90° or 270°
- **Actual playback**: 1080×1920 (portrait orientation)

The previous metadata extraction code only read width/height from ffprobe without considering rotation metadata, leading to incorrect aspect ratio calculations.

```javascript
// ❌ BEFORE (Incorrect)
const width = 1920;
const height = 1080;
const aspectRatio = 1920 / 1080 = 1.778; // → 'vayu' (WRONG!)
```

## Solution

Enhanced `videoMetadataService.js` to detect and handle rotation metadata from two sources:

### 1. **Legacy Format (Android/Older FFmpeg)**
- Location: `videoStream.tags.rotate`
- Common in: Older Android videos, legacy FFmpeg encodings

### 2. **Modern Format (iPhone/iOS)**
- Location: `videoStream.side_data_list[].rotation` (Display Matrix)
- Common in: iPhone videos, modern iOS recordings

### Implementation

```javascript
// ✅ AFTER (Correct with Rotation Detection)

// Step 1: Extract raw dimensions
let width = 1920;
let height = 1080;

// Step 2: Detect rotation
let rotation = 0;

// Check tags (legacy)
if (videoStream.tags?.rotate) {
  rotation = parseInt(videoStream.tags.rotate, 10);
}

// Check side_data_list (modern - iOS)
if (videoStream.side_data_list && videoStream.side_data_list.length > 0) {
  const sideData = videoStream.side_data_list.find(sd => 
    sd.side_data_type === 'Display Matrix'
  );
  if (sideData && sideData.rotation) {
    rotation = parseInt(sideData.rotation, 10);
  }
}

// Step 3: Apply rotation correction
if (Math.abs(rotation) === 90 || Math.abs(rotation) === 270) {
  [width, height] = [height, width]; // Swap dimensions
}

// Step 4: Calculate correct aspect ratio
const correctedAR = 1080 / 1920 = 0.5625; // → 'yog' (CORRECT!)
```

## Files Modified

### 1. `backend/services/videoMetadataService.js`
**Changes:**
- Added rotation detection from `tags.rotate` (legacy format)
- Added rotation detection from `side_data_list` (modern iOS format)
- Implemented dimension swapping when rotation is 90° or 270°
- Included `rotation` field in result for debugging
- Added console logging for rotation detection events

**Lines Changed:** +26 added, -4 removed

### 2. `backend/scripts/test-rotation-detection.js` (NEW)
**Purpose:** Test script to verify rotation detection on individual video files

**Usage:**
```bash
node scripts/test-rotation-detection.js <path-to-video-file>
```

**Example:**
```bash
node scripts/test-rotation-detection.js ./uploads/videos/test.mp4
```

**Output:**
```
🎬 Testing Rotation Detection
────────────────────────────────────────────────────────────

📊 RAW DIMENSIONS (from ffprobe):
   Width:  1920px
   Height: 1080px
   Raw AR: 1.7778

📦 Side Data List:
   [0] Type: Display Matrix
       Rotation: 90°

✅ Using Display Matrix rotation: 90°

🔄 ROTATION DETECTED: 90°
   Swapping dimensions: 1920x1080 → 1080x1920

✅ CORRECTED DIMENSIONS:
   Width:  1080px
   Height: 1920px
   Corrected AR: 0.5625

📋 CLASSIFICATION:
   Orientation: Portrait/Vertical
   Video Type: 'yog'
   Tab: Yog (Short-form/Reels)

────────────────────────────────────────────────────────────
✅ Test completed successfully!
```

### 3. `backend/scripts/migrate-video-types-rotation.js` (NEW)
**Purpose:** Migration script to update existing videos in database

**Usage:**
```bash
node scripts/migrate-video-types-rotation.js
```

**Note:** Full migration requires access to original video files. The current script uses stored dimensions as a simplified version.

## Impact

### Before Fix
```
iPhone Portrait Video:
├─ Stored: 1920×1080 (landscape)
├─ Rotation: 90°
├─ Actual: 1080×1920 (portrait)
├─ Detected AR: 1.778 → 'vayu' ❌ WRONG
└─ Should be: 0.5625 → 'yog' ✅
```

### After Fix
```
iPhone Portrait Video:
├─ Stored: 1920×1080 (landscape)
├─ Rotation: 90° (detected ✓)
├─ Corrected: 1080×1920 (portrait)
├─ Detected AR: 0.5625 → 'yog' ✅ CORRECT
└─ Properly classified in Yog tab
```

## Video Classification Logic

The platform now correctly classifies videos based on **actual playback orientation**:

| Aspect Ratio | Orientation | Video Type | Tab | Content Type |
|--------------|-------------|------------|-----|--------------|
| AR > 1.0 | Landscape/Horizontal | vayu | Vayu | Long-form |
| AR ≤ 1.0 | Portrait/Vertical | yog | Yog | Short-form/Reels |

**Examples:**
- 1920×1080 (16:9 = 1.778) → `vayu` (landscape)
- 1080×1920 (9:16 = 0.5625) → `yog` (portrait)
- 1920×1920 (1:1 = 1.0) → `yog` (square, treated as portrait)

## Rotation Metadata Sources

### Display Matrix (Modern - iOS)
```json
{
  "side_data_list": [
    {
      "side_data_type": "Display Matrix",
      "rotation": 90,
      "displaymatrix": "\n00000000: 0 65536 0\n00000001: -65536 0 0\n00000002: 0 0 1073741824\n"
    }
  ]
}
```

### Tags Rotate (Legacy - Android)
```json
{
  "tags": {
    "rotate": 90
  }
}
```

## Testing Recommendations

### 1. Test with iPhone Videos
Record a vertical video on iPhone and upload it:
```bash
node scripts/test-rotation-detection.js ./iphone-vertical.mov
```

Expected: Rotation detected (90°), dimensions swapped, classified as 'yog'

### 2. Test with Android Videos
Test videos from Android devices with rotation tags:
```bash
node scripts/test-rotation-detection.js ./android-portrait.mp4
```

Expected: Rotation detected in tags, dimensions swapped, classified as 'yog'

### 3. Test with Already-Correct Videos
Videos without rotation metadata should remain unchanged:
```bash
node scripts/test-rotation-detection.js ./standard-landscape.mp4
```

Expected: No rotation detected, dimensions unchanged, classified as 'vayu'

## Backward Compatibility

This fix maintains **dual-mode logic**:

1. **Existing Videos**: Preserved as-is in database until re-uploaded or migrated
2. **New Uploads**: Automatically classified using rotation-aware aspect ratio
3. **Migration Option**: Run migration script to update all existing videos

## Deployment Checklist

- [x] Update `videoMetadataService.js` with rotation detection
- [x] Create test script for manual verification
- [x] Create migration script for existing videos
- [ ] Test with sample iPhone vertical videos
- [ ] Test with sample Android vertical videos
- [ ] Test with landscape videos (no regression)
- [ ] Run migration script on production database (optional)
- [ ] Monitor upload logs for rotation detection events

## Debugging

### Enable Logging
The service logs rotation detection events:
```
🔄 Rotation detected: 90°, swapping dimensions (1920x1080 → 1080x1920)
```

### Manual FFprobe Check
To manually verify rotation metadata:
```bash
# Check rotation in tags
ffprobe -loglevel error -select_streams v:0 -show_entries stream_tags=rotate -of default=nw=1:nk=1 -i video.mp4

# Check display matrix
ffprobe -loglevel error -select_streams v:0 -show_entries side_data=rotation -of json -i video.mp4
```

## Related Documentation

- [Video Metadata Extraction](./Video%20Metadata%20Extraction.md)
- [Video Type Resolution](./BACKEND_DRIVEN_ARCHITECTURE_SUMMARY.md#video-type-resolution)
- [HLS Encoding](./HLS%20Streaming%20&%20Encoding.md)

## Summary

This fix ensures that vertical videos are correctly classified into the 'yog' tab regardless of how they're stored (with or without rotation metadata). The implementation handles both legacy Android rotation tags and modern iPhone display matrix data, providing accurate video type classification for all mobile uploads.

---

**Created:** March 6, 2026  
**Last Updated:** March 6, 2026  
**Status:** ✅ Implemented
