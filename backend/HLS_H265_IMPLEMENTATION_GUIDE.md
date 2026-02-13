# H.265 (HEVC) Implementation Guide

This guide explains how to use H.265 encoding in the HLS pipeline for ~50% bandwidth savings at the same visual quality.

## Prerequisites

### 1. FFmpeg with libx265

Your FFmpeg must be compiled with libx265 support:

```bash
# Check if libx265 is available
ffmpeg -encoders | grep libx265
```

If you see `libx265`, you're good. If not:

- **Ubuntu/Debian**: `sudo apt install ffmpeg` (usually includes libx265)
- **Build from source**: Add `--enable-libx265` to your configure flags
- **ffmpeg-static (npm)**: The default package may NOT include libx265. Consider using system FFmpeg or a custom build.

### 2. Verify at Runtime

The service auto-checks and falls back to H.264 if libx265 is missing:

```
✅ H.265 (libx265) encoder available
```

or

```
⚠️ H.265 (libx265) encoder NOT available. Falling back to H.264.
```

---

## Usage

### Single Quality (convertToHLS)

```javascript
import hlsEncodingService from './services/hlsEncodingService.js';

// H.264 (default) - maximum compatibility
await hlsEncodingService.convertToHLS(inputPath, videoId, {
  quality: 'medium',
  segmentDuration: 3,
});

// H.265 - ~50% smaller files, ideal for 500kbps
await hlsEncodingService.convertToHLS(inputPath, videoId, {
  quality: 'medium',
  segmentDuration: 3,
  codec: 'h265',  // ← Enable H.265
});
```

### Adaptive Streaming (generateAdaptiveHLS)

```javascript
// All variants encoded with H.265
await hlsEncodingService.generateAdaptiveHLS(inputPath, videoId, {
  codec: 'h265',
});
```

### Network-Aware (generateNetworkAwareHLS)

```javascript
await hlsEncodingService.generateNetworkAwareHLS(inputPath, videoId, {
  targetBitrate: 'low',  // 240p, 360p for slow networks
  codec: 'h265',
});
```

---

## Where to Pass the Codec Option

Find where your backend calls HLS encoding (e.g., after video upload) and add `codec: 'h265'`:

```javascript
// Example: In your video upload/processing route
const result = await hlsEncodingService.convertToHLS(
  uploadedVideoPath,
  videoId,
  {
    originalVideoInfo: { width, height },
    quality: 'medium',
    codec: 'h265',  // Add this for H.265
  }
);
```

---

## Bitrate Impact

| Codec | 480p @ CRF 28 | 500 kbps capable? |
|-------|---------------|-------------------|
| H.264 | ~800 kbps     | No                |
| H.265 | ~400 kbps     | Yes               |

H.265 at 400k video + 48k audio ≈ 450 kbps total, which fits a 500 kbps connection.

---

## Frontend

No changes needed. ExoPlayer (Android) and AVPlayer (iOS) play HEVC HLS natively when the device supports it. The same `.m3u8` URL works for both codecs.

---

## Rollback

To disable H.265 and use H.264 only, either:
- Omit the `codec` option (defaults to `'h264'`)
- Or set `codec: 'h264'` explicitly
