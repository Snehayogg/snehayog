import path from 'path';

export const hlsConfig = {
  // HLS encoding settings - optimized for 500kbps connections (High Efficiency)
  encoding: {
    segmentDuration: 1, // Keep 1s for instant startup
    maxBitrate: 400000, // Cap at 400kbps
    minBitrate: 300000, // Allow dropping lower if needed
    qualityPresets: {
      '480p': { width: 854, height: 480, crf: 28, audioBitrate: '48k', targetBitrate: '400k' }
    },
    // H.264 encoding profile settings - High Profile for max quality/bit
    h264Profile: 'high',     // Better compression efficiency (~30-50% savings vs baseline)
    h264Level: '3.1',        // Supported by 98% of devices
    gopSize: 60,             // 2 seconds GOP to reduce header overhead
    keyframeInterval: 2      // Keyframe every 2 seconds
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

  // Streaming settings - optimized for 480p streaming
  streaming: {
    enableRangeRequests: true,
    enableCompression: false, // Don't compress video files
    enableGzip: false,
    enableFastStart: true,
    enableIndependentSegments: true
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
