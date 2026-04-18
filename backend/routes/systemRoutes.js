import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import databaseManager from '../config/database.js';
import Video from '../models/Video.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const backendRoot = path.join(__dirname, '..');

const router = express.Router();

// Asset Links dynamic response
const assetLinksPackageName = process.env.ANDROID_ASSETLINKS_PACKAGE_NAME;
const assetLinksFingerprintsRaw = process.env.ANDROID_ASSETLINKS_FINGERPRINTS || '';
const assetLinksFingerprints = assetLinksFingerprintsRaw
  .split(',')
  .map((fp) => fp.trim())
  .filter((fp) => fp.length > 0);

if (assetLinksPackageName && assetLinksFingerprints.length > 0) {
  router.get('/.well-known/assetlinks.json', (req, res) => {
    res.json([
      {
        relation: ['delegate_permission/common.handle_all_urls'],
        target: {
          namespace: 'android_app',
          package_name: assetLinksPackageName,
          sha256_cert_fingerprints: assetLinksFingerprints
        }
      }
    ]);
  });
}

// Serve app-ads.txt and ads.txt from root
router.get(["/app-ads.txt", "/ads.txt"], (req, res) => {
  res.sendFile(path.join(backendRoot, "ads.txt"));
});

// Serve the production APK
router.get('/download/vayu-latest.apk', (req, res) => {
  const apkPath = path.join(backendRoot, 'public/download/app-release.apk');
  res.download(apkPath, 'vayu-latest.apk', (err) => {
    if (err) {
      if (!res.headersSent) {
        res.status(404).send('APK not found. Please try again later.');
      }
    }
  });
});

// Root route handler - serves the landing page for APK distribution
router.get('/', (req, res) => {
  res.sendFile(path.join(backendRoot, 'public', 'index.html'));
});

router.get('/video/:id', async (req, res) => {
  // Prevent browser caching of the redirect response
  res.setHeader('Cache-Control', 'no-store, no-cache, must-revalidate, proxy-revalidate');
  res.setHeader('Pragma', 'no-cache');
  res.setHeader('Expires', '0');

  try {
    const { id } = req.params;
    
    // Safety check for ID format
    if (!id || id.length < 12) {
       return res.status(400).send('Invalid Link Format');
    }

    const video = await Video.findById(id).populate('uploader', 'name');

    // App links constants
    const appSchemeUrl = `snehayog://video/${id}`;
    const playStoreUrl = 'https://play.google.com/store/apps/details?id=com.snehayog.app';
    const intentUrl = `intent://video/${id}#Intent;scheme=snehayog;package=com.snehayog.app;end`;

    if (!video) {
        // **SMART FALLBACK**: Don't redirect! Serve a clean error page instead.
        // This stops the Play Store from hijacking the user experience.
        return res.status(200).send(`
          <!doctype html>
          <html>
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>Video Not Found | Vayug</title>
            <style>
              body { margin:0; background:#000; color:#fff; font-family:system-ui; display:flex; align-items:center; justify-content:center; height:100vh; text-align:center; }
              .card { padding:30px; border-radius:30px; border:1px solid #333; background:#0a0a0a; max-width:400px; width:90%; }
              h1 { font-size:22px; margin-bottom:10px; }
              p { color:#777; margin-bottom:30px; }
              .btn { display:block; padding:15px; background:#2563eb; color:#fff; text-decoration:none; border-radius:15px; font-weight:700; }
            </style>
          </head>
          <body>
            <div class="card">
              <div style="font-size:50px; margin-bottom:20px;">🎬</div>
              <h1>Video Unavailable</h1>
              <p>This video link is invalid or the video has been removed.</p>
              <a href="${playStoreUrl}" class="btn">Get Vayug App</a>
              <a href="/" style="display:block; margin-top:20px; color:#555; text-decoration:none;">Go to Homepage</a>
            </div>
          </body>
          </html>
        `);
    }

    // Video Found: Serve the Premium Web Player
    video.incrementView(null, 2, 'embed').catch(err => console.error('Error tracking shared view:', err));

    const baseUrl = `${req.protocol}://${req.get('host')}`;
    const videoStreamUrl = video.hlsMasterPlaylistUrl || video.videoUrl;
    const finalStreamUrl = videoStreamUrl.startsWith('http') ? videoStreamUrl : `${baseUrl}${videoStreamUrl}`;
    const finalThumbnailUrl = (video.thumbnailUrl && video.thumbnailUrl.startsWith('http')) 
      ? video.thumbnailUrl 
      : (video.thumbnailUrl ? `${baseUrl}${video.thumbnailUrl}` : '');

    const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${video.videoName} | Vayug</title>
  
  <meta property="og:title" content="${video.videoName}" />
  <meta property="og:description" content="${video.description || 'Watch on Vayug'}" />
  <meta property="og:image" content="${finalThumbnailUrl}" />
  <meta name="theme-color" content="#2563eb" />

  <style>
    body { margin:0; background:#000; color:#fff; font-family:system-ui; display:flex; flex-direction:column; min-height:100vh; }
    .player { flex:1; display:flex; align-items:center; justify-content:center; background:#000; }
    video { width:100%; max-height:80vh; object-fit:contain; }
    .meta { padding:24px; max-width:800px; margin:0 auto; width:100%; box-sizing:border-box; }
    h1 { font-size:22px; margin:0 0 10px; }
    .btn-row { display:flex; gap:12px; margin-top:25px; flex-wrap:wrap; }
    .btn { padding:14px 24px; border-radius:12px; font-weight:700; text-decoration:none; display:inline-flex; align-items:center; gap:8px; }
    .primary { background:#2563eb; color:#fff; }
    .secondary { border:1px solid #333; color:#fff; background:#111; }
  </style>
</head>
<body>
  <div class="player">
    <video id="v" poster="${finalThumbnailUrl}" controls playsinline autoplay muted></video>
  </div>
  <div class="meta">
    <h1>${video.videoName}</h1>
    <p style="color:#666; font-size:14px;">${video.views.toLocaleString()} views • Shared from Vayug</p>
    <div class="btn-row">
      <a href="${intentUrl}" class="btn primary">Open in App</a>
      <a href="${playStoreUrl}" class="btn secondary">Get the App</a>
    </div>
  </div>

  <script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
  <script>
    const video = document.getElementById('v');
    const src = '${finalStreamUrl}';
    if(Hls.isSupported() && src.includes('.m3u8')) {
      const hls = new Hls(); hls.loadSource(src); hls.attachMedia(video);
    } else { video.src = src; }
  </script>
</body>
</html>`;

    res.status(200).send(html);
  } catch (error) {
    console.error('❌ Social route error:', error);
    res.status(500).send('Error loading video page');
  }
});

// Minimalist external embed route
router.get('/embed/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const video = await Video.findById(id).populate('uploader', 'name');

    if (!video) {
      return res.status(404).send('Video not found');
    }

    // Track view from embed source
    // Passing null for userId to count as a guest view
    video.incrementView(null, 2, 'embed').catch(err => console.error('Error tracking embed view:', err));

    const baseUrl = `${req.protocol}://${req.get('host')}`;
    const videoStreamUrl = video.hlsMasterPlaylistUrl || video.videoUrl;
    const finalStreamUrl = videoStreamUrl.startsWith('http') ? videoStreamUrl : `${baseUrl}${videoStreamUrl}`;
    const finalThumbnailUrl = video.thumbnailUrl.startsWith('http') ? video.thumbnailUrl : `${baseUrl}${video.thumbnailUrl}`;

    const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${video.videoName} - Vayug</title>
  
  <!-- SEO / Open Graph -->
  <meta property="og:title" content="${video.videoName}" />
  <meta property="og:description" content="${video.description || 'Watch this video on Vayug'}" />
  <meta property="og:image" content="${finalThumbnailUrl}" />
  <meta property="og:type" content="video.other" />
  
  <style>
    body { margin: 0; background: #000; overflow: hidden; font-family: system-ui, -apple-system, sans-serif; }
    .player-container { position: relative; width: 100vw; height: 100vh; display: flex; align-items: center; justify-content: center; }
    video { width: 100%; height: 100%; max-height: 100vh; outline: none; }
    .vayu-btn {
      position: absolute; bottom: 20px; right: 20px;
      background: rgba(37, 99, 235, 0.85); color: #fff; padding: 10px 20px;
      border-radius: 50px; text-decoration: none; font-weight: 600; font-size: 14px;
      box-shadow: 0 4px 12px rgba(0,0,0,0.4); opacity: 0; transition: opacity 0.3s, transform 0.2s;
      z-index: 10; display: flex; align-items: center; gap: 8px;
    }
    .vayu-btn:hover { transform: scale(1.05); background: #2563eb; }
    .player-container:hover .vayu-btn { opacity: 1; }
    
    /* Responsive adjustment for small embeds */
    @media (max-width: 400px) {
      .vayu-btn { bottom: 10px; right: 10px; padding: 8px 12px; font-size: 12px; }
    }
  </style>
</head>
<body>
  <div class="player-container">
    <video id="video" poster="${finalThumbnailUrl}" controls playsinline preload="metadata"></video>
    <a href="https://snehayog.site/video/${video._id}" target="_blank" class="vayu-btn">
      <span>Watch on Vayug</span>
      <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"></path><polyline points="15 3 21 3 21 9"></polyline><line x1="10" y1="14" x2="21" y2="3"></line></svg>
    </a>
  </div>

  <script src="https://cdn.jsdelivr.net/npm/hls.js@latest"></script>
  <script>
    document.addEventListener('DOMContentLoaded', function() {
      const video = document.getElementById('video');
      const videoSrc = '${finalStreamUrl}';
      const fallbackSrc = '${video.videoUrl.startsWith('http') ? video.videoUrl : baseUrl + video.videoUrl}';

      if (Hls.isSupported() && videoSrc.includes('.m3u8')) {
        const hls = new Hls({
          capLevelToPlayerSize: true,
          autoStartLoad: true
        });
        hls.loadSource(videoSrc);
        hls.attachMedia(video);
        hls.on(Hls.Events.ERROR, function (event, data) {
          if (data.fatal) {
            console.warn('HLS fatal error, falling back to MP4');
            video.src = fallbackSrc;
          }
        });
      } else if (video.canPlayType('application/vnd.apple.mpegurl')) {
        // Native HLS support (Safari)
        video.src = videoSrc;
      } else {
        // Fallback to MP4
        video.src = fallbackSrc;
      }
    });
  </script>
</body>
</html>`;

    res.setHeader('X-Frame-Options', 'ALLOWALL'); // Explicitly allow embedding
    res.setHeader('Content-Security-Policy', "frame-ancestors *"); // Modern equivalent
    res.status(200).send(html);
  } catch (error) {
    console.error('❌ Embed error:', error);
    res.status(500).send('An error occurred loading the video embed');
  }
});

// Admin Dashboard route
router.get('/admin/dashboard', (req, res) => {
  res.sendFile(path.join(backendRoot, 'admin', 'admin_dashboard.html'));
});

// Health check endpoints
router.get('/health', (req, res) => {
  const dbStatus = databaseManager.getConnectionStatus();
  res.json({
    status: 'OK',
    timestamp: new Date().toISOString(),
    database: dbStatus,
    server: {
      uptime: process.uptime(),
      memory: process.memoryUsage(),
      version: process.version,
      platform: process.platform
    },
    cors: {
      origin: req.headers.origin || 'No origin header',
      method: req.method,
      headers: req.headers
    },
    message: 'Backend is running successfully!'
  });
});

router.get('/api/health', (req, res) => {
  const dbStatus = databaseManager.getConnectionStatus();
  res.json({
    status: 'OK',
    timestamp: new Date().toISOString(),
    database: dbStatus,
    message: 'Backend API is running successfully',
    endpoints: {
      auth: '/api/auth',
      users: '/api/users',
      videos: '/api/videos',
      ads: '/api/ads',
      billing: '/api/billing',
      upload: '/api/upload'
    }
  });
});

export default router;
