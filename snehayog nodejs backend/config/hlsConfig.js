export const hlsConfig = {
  // HLS encoding settings
  encoding: {
    segmentDuration: 6, // seconds per segment
    maxBitrate: 5000000, // 5 Mbps max
    minBitrate: 800000,  // 800 Kbps min
    qualityPresets: {
      '1080p': { width: 1920, height: 1080, crf: 18, audioBitrate: '192k' },
      '720p': { width: 1280, height: 720, crf: 23, audioBitrate: '128k' },
      '480p': { width: 854, height: 480, crf: 28, audioBitrate: '96k' },
      '360p': { width: 640, height: 360, crf: 32, audioBitrate: '64k' }
    }
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

  // Cache settings
  cache: {
    maxAge: 86400, // 24 hours for playlists
    maxAgeSegments: 3600, // 1 hour for video segments
    etag: true,
    lastModified: true
  },

  // Streaming settings
  streaming: {
    enableRangeRequests: true,
    chunkSize: 64 * 1024, // 64KB chunks
    enableCompression: false, // Don't compress video files
    enableGzip: false
  }
};

export const getMimeType = (filename) => {
  const ext = filename.toLowerCase().substring(filename.lastIndexOf('.'));
  return hlsConfig.mimeTypes[ext] || 'application/octet-stream';
};

export const setHLSHeaders = (res, filename) => {
  // Set MIME type
  res.setHeader('Content-Type', getMimeType(filename));
  
  // Set CORS headers
  Object.entries(hlsConfig.corsHeaders).forEach(([key, value]) => {
    res.setHeader(key, value);
  });
  
  // Set cache headers
  if (filename.endsWith('.m3u8')) {
    res.setHeader('Cache-Control', `public, max-age=${hlsConfig.cache.maxAge}`);
  } else if (filename.endsWith('.ts')) {
    res.setHeader('Cache-Control', `public, max-age=${hlsConfig.cache.maxAgeSegments}`);
  }
  
  // Enable range requests for video segments
  if (filename.endsWith('.ts')) {
    res.setHeader('Accept-Ranges', 'bytes');
  }
};
