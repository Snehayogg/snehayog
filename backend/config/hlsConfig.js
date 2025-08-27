export const hlsConfig = {
  // HLS encoding settings - optimized for INSTANT startup and efficient streaming
  encoding: {
    segmentDuration: 1, // 1 second per segment for INSTANT startup (was 3 seconds)
    maxBitrate: 2000000, // 2 Mbps max (optimized for mobile)
    minBitrate: 300000,  // 300 Kbps min (240p quality)
    qualityPresets: {
      '720p': { width: 1280, height: 720, crf: 23, audioBitrate: '128k', targetBitrate: '1500k' },
      '480p': { width: 854, height: 480, crf: 23, audioBitrate: '96k', targetBitrate: '800k' },
      '240p': { width: 426, height: 240, crf: 23, audioBitrate: '64k', targetBitrate: '300k' }
    },
    // H.264 encoding profile settings - optimized for fast startup
    h264Profile: 'baseline', // Maximum compatibility across devices
    h264Level: '3.1',        // Broad device support
    gopSize: 30,             // Reduced GOP size for faster startup (was 48)
    keyframeInterval: 1      // Force keyframes every 1 second for instant seeking (was 3)
  },

  // MIME types for HLS files
  mimeTypes: {
    '.m3u8': 'application/vnd.apple.mpegurl',
    '.ts': 'video/mp2t',
    '.m3u': 'application/vnd.apple.mpegurl'
  },

  // CORS headers for streaming
  corsHeaders: {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, HEAD, OPTIONS',
    'Access-Control-Allow-Headers': 'Range, Accept-Ranges, Content-Range',
    'Access-Control-Expose-Headers': 'Content-Length, Content-Range, Accept-Ranges'
  },

  // Cache settings - optimized for INSTANT HLS streaming
  cache: {
    maxAge: 86400, // 24 hours for playlists
    maxAgeSegments: 300, // 5 minutes for video segments (was 30 minutes) - faster updates
    etag: true,
    lastModified: true
  },

  // Streaming settings - optimized for INSTANT adaptive bitrate
  streaming: {
    enableRangeRequests: true,
    chunkSize: 32 * 1024, // 32KB chunks for faster streaming (was 64KB)
    enableCompression: false, // Don't compress video files
    enableGzip: false,
    // HLS specific optimizations for INSTANT startup
    enableAdaptiveBitrate: true,
    enableFastStart: true,
    enableIndependentSegments: true,
    // NEW: Fast startup optimizations
    enableLowLatency: true,
    enablePartialSegmentSupport: true,
    enableDeltaUpdate: true
  }
};

// Complete the getMimeType function

export const getMimeType = (filename) => {
  const ext = path.extname(filename).toLowerCase();
  return hlsConfig.mimeTypes[ext] || 'application/octet-stream';
};

// Add the setHLSHeaders function
export const setHLSHeaders = (res, filename) => {
  const ext = path.extname(filename).toLowerCase();
  const mimeType = getMimeType(filename);
  
  res.setHeader('Content-Type', mimeType);
  res.setHeader('Cache-Control', 'public, max-age=3600');
  
  // Add CORS headers
  Object.entries(hlsConfig.corsHeaders).forEach(([key, value]) => {
    res.setHeader(key, value);
  });
  
  // Add cache headers based on file type
  if (filename.endsWith('.m3u8')) {
    res.setHeader('Cache-Control', `public, max-age=${hlsConfig.cache.maxAge}`);
  } else if (filename.endsWith('.ts')) {
    res.setHeader('Cache-Control', `public, max-age=${hlsConfig.cache.maxAgeSegments}`);
  }
};
