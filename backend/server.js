import express from 'express';
import dotenv from "dotenv";
dotenv.config();
import cors from 'cors';
import path from 'path';
import compression from 'compression';
import { fileURLToPath } from 'url';
import cron from 'node-cron';

// Disable noisy console.log in production
if (process.env.NODE_ENV === 'production') {
  // eslint-disable-next-line no-console
  console.log = () => {};
}

// Import database manager
import databaseManager from './config/database.js';
import './models/index.js';

// Import routes
import videoRoutes from './routes/videoRoutes.js';
import userRoutes from './routes/userRoutes.js';
import authRoutes from './routes/authRoutes.js';
import adRoutes from './routes/adRoutes/index.js';
import billingRoutes from './routes/billingRoutes.js';
import creatorPayoutRoutes from './routes/creatorPayoutRoutes.js';
import uploadRoutes from './routes/uploadRoutes.js';
import adminRoutes from './routes/adminRoutes.js';
import feedbackRoutes from './routes/feedbackRoutes.js';
import referralRoutes from './routes/referralRoutes.js';

// Import services
import automatedPayoutService from './services/automatedPayoutService.js';
import adCleanupService from './services/adCleanupService.js';

// Import middleware
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';

const app = express();

// ES Module equivalent of __dirname
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Check required environment variables (support both MONGO_URI and MONGODB_URI)
const mongoUri = process.env.MONGO_URI || process.env.MONGODB_URI;
if (!mongoUri) {
  console.error('❌ Missing required environment variable: MONGO_URI or MONGODB_URI');
  process.exit(1);
}

// Set the environment variable for consistency
process.env.MONGO_URI = mongoUri;

// Port and Host configuration
const PORT = process.env.PORT || 5001;
const HOST = process.env.HOST || '0.0.0.0'; // Railway requires 0.0.0.0

// Middleware
app.use(compression()); // Enable gzip compression
app.use('/.well-known', express.static(path.join(__dirname, 'public/.well-known')))
// **ENHANCED: CORS Configuration for Flutter app and Railway**
app.use(cors({
  origin: [
    'https://snehayog.site', // Production web app
    'https://vayu.app',      // Public site that embeds/uses API
    'http://192.168.0.198:5001', // Local development
    'http://192.168.0.188:5001', // Local development (legacy)
    'http://localhost:5001',      // Local development
    'http://10.0.2.2:5001',      // Android emulator
    'http://127.0.0.1:5001',     // Localhost alternative
    '*'                           // Allow all origins for development
  ],
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'PATCH'],
  allowedHeaders: [
    'Content-Type', 
    'Authorization', 
    'X-Requested-With',
    'Accept',
    'Origin',
    'Access-Control-Request-Method',
    'Access-Control-Request-Headers'
  ],
  exposedHeaders: ['Content-Length', 'Content-Range', 'Accept-Ranges'],
  maxAge: 86400
}));

app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// Serve static files from uploads directory
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// Serve HLS files with proper MIME types and CORS
app.use('/hls', (req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, HEAD, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Range, Accept-Ranges, Content-Range');
  res.setHeader('Access-Control-Expose-Headers', 'Content-Length, Content-Range, Accept-Ranges');
  
  // Set proper MIME types for HLS files
  if (req.path.endsWith('.m3u8')) {
    res.setHeader('Content-Type', 'application/vnd.apple.mpegurl');
  } else if (req.path.endsWith('.ts')) {
    res.setHeader('Content-Type', 'video/mp2t');
  }
  
  next();
}, express.static(path.join(__dirname, 'uploads/hls'), {
  // **FIXED: Add better error handling for missing files**
  fallthrough: false,
  setHeaders: (res, path) => {
    // Add cache headers for better performance
    if (path.endsWith('.m3u8')) {
      res.setHeader('Cache-Control', 'public, max-age=300'); // 5 minutes for playlists
    } else if (path.endsWith('.ts')) {
      res.setHeader('Cache-Control', 'public, max-age=86400'); // 24 hours for segments
    }
  }
}));

// **FIXED: Add error handler for HLS files**
app.use('/hls', (err, req, res, next) => {
  console.error('❌ HLS serving error:', err);
  if (err.code === 'ENOENT') {
    res.status(404).json({ error: 'HLS file not found', path: req.path });
  } else {
    res.status(500).json({ error: 'Internal server error serving HLS file' });
  }
});

// API Routes
app.use('/api/users', userRoutes);
app.use('/api/auth', authRoutes);
app.use('/api/ads', adRoutes);
app.use('/api/billing', billingRoutes);
app.use('/api/creator-payouts', creatorPayoutRoutes);
app.use('/api/videos', videoRoutes);
app.use('/api/admin', adminRoutes);
app.use('/api/upload', uploadRoutes);
app.use('/api/feedback', feedbackRoutes);
app.use('/api/referrals', referralRoutes);

// **FIX: Root route handler for referral links: https://snehayog.site/?ref=CODE
// This handles referral links and tries to open the app
app.get('/', (req, res) => {
  console.log('🔗 Root route hit:', req.url, 'Query:', req.query);
  const refCode = req.query.ref || '';
  const appSchemeUrl = refCode 
    ? `snehayog://video/?ref=${refCode}` 
    : 'snehayog://';
  const webUrl = refCode 
    ? `https://snehayog.site/?ref=${refCode}` 
    : 'https://snehayog.site';
  const playStoreUrl = 'https://play.google.com/store/apps/details?id=com.snehayog.app';

  const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Join Vayu - Create • Video • Earn</title>
  <meta name="robots" content="noindex" />
  <style>
    body { font-family: system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif; margin: 0; padding: 24px; background:#fff; color:#111; }
    .card { max-width: 560px; margin: 0 auto; border:1px solid #eee; border-radius: 12px; padding: 20px; box-shadow: 0 8px 24px rgba(0,0,0,.06); text-align: center; }
    h1 { font-size: 24px; margin: 0 0 8px; color: #2563eb; }
    p { margin: 8px 0 16px; color:#444; font-size: 16px; }
    .actions { display:flex; gap:12px; flex-wrap:wrap; justify-content: center; margin-top: 24px; }
    .btn { padding: 14px 24px; border-radius: 10px; text-decoration:none; display:inline-block; font-weight:600; font-size: 16px; }
    .primary { background:#2563eb; color:#fff; }
    .primary:hover { background:#1d4ed8; }
    .secondary { background:#f3f4f6; color:#111; }
    .secondary:hover { background:#e5e7eb; }
    .features { margin-top: 24px; text-align: left; }
    .feature { padding: 12px 0; border-bottom: 1px solid #eee; }
    .feature:last-child { border-bottom: none; }
    .feature strong { color: #2563eb; }
  </style>
  <script>
    // Try deep link first; after a short delay, fall back to Play Store
    function openApp() {
      const now = Date.now();
      const timeout = setTimeout(function() {
        // If the app didn't take focus within ~1s, go to Play Store
        if (Date.now() - now < 1600) {
          window.location.href = '${playStoreUrl}';
        }
      }, 1200);
      window.location.href = '${appSchemeUrl}';
    }
    document.addEventListener('DOMContentLoaded', function() {
      // Auto-attempt deep link on load for convenience
      openApp();
    });
  </script>
  <link rel="canonical" href="${webUrl}" />
  <meta property="og:title" content="Join Vayu - Create • Video • Earn" />
  <meta property="og:description" content="Upload your videos and start earning from day one! Only First 1000 early creators — grab 80% ad revenue" />
  <meta property="og:type" content="website" />
  <meta property="og:url" content="${webUrl}" />
  <meta name="twitter:card" content="summary" />
  <meta name="twitter:title" content="Join Vayu - Create • Video • Earn" />
  <meta name="theme-color" content="#2563eb" />
  <meta http-equiv="refresh" content="0; url=${appSchemeUrl}" />
  ${refCode ? `<meta http-equiv="Refresh" content="0; url=intent://?ref=${refCode}#Intent;scheme=snehayog;package=com.snehayog.app;end">` : ''}
</head>
<body>
  <div class="card">
    <h1>🚀 Welcome to Vayu</h1>
    <p>Create • Video • Earn</p>
    ${refCode ? '<p style="color: #16a34a; font-weight: 600;">🎁 Referral link detected!</p>' : ''}
    <p>Upload your videos and start earning from day one!</p>
    <p><strong>Only First 1000 early creators — grab 80% ad revenue</strong></p>
    <p style="font-size: 14px; color: #666;">No 1000 subs or long watch hours required</p>
    <div class="features">
      <div class="feature"><strong>✓</strong> Upload videos instantly</div>
      <div class="feature"><strong>✓</strong> Earn from day one</div>
      <div class="feature"><strong>✓</strong> 80% ad revenue share</div>
      <div class="feature"><strong>✓</strong> No minimum requirements</div>
    </div>
    <div class="actions">
      <a class="btn primary" href="${appSchemeUrl}" onclick="openApp(); return false;">Open in App</a>
      <a class="btn secondary" href="${playStoreUrl}">Get the App</a>
    </div>
    ${refCode ? `<p class="hint" style="font-size: 12px; color:#666; margin-top:12px;">Referral Code: ${refCode}</p>` : ''}
  </div>
</body>
</html>`;

  console.log('✅ Root route: Sending HTML response');
  res.status(200).send(html);
});

// Lightweight web fallback for shared links: https://snehayog.site/video/:id
// This lets non-app users see a clean page and tries to open the app when installed
app.get('/video/:id', (req, res) => {
  const { id } = req.params;
  const appSchemeUrl = `snehayog://video/${id}`;
  const webUrl = `https://snehayog.site/video/${id}`;
  const playStoreUrl = 'https://play.google.com/store/apps/details?id=com.snehayog.app';

  const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Open in Vayu</title>
  <meta name="robots" content="noindex" />
  <style>
    body { font-family: system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif; margin: 0; padding: 24px; background:#fff; color:#111; }
    .card { max-width: 560px; margin: 0 auto; border:1px solid #eee; border-radius: 12px; padding: 20px; box-shadow: 0 8px 24px rgba(0,0,0,.06); }
    h1 { font-size: 20px; margin: 0 0 8px; }
    p { margin: 8px 0 16px; color:#444; }
    .actions { display:flex; gap:12px; flex-wrap:wrap; }
    .btn { padding: 12px 16px; border-radius: 10px; text-decoration:none; display:inline-block; font-weight:600; }
    .primary { background:#2563eb; color:#fff; }
    .secondary { background:#f3f4f6; color:#111; }
    .hint { font-size: 12px; color:#666; margin-top:12px; }
  </style>
  <script>
    // Try deep link first; after a short delay, fall back to Play Store
    function openApp() {
      const now = Date.now();
      const timeout = setTimeout(function() {
        // If the app didn't take focus within ~1s, go to Play Store
        if (Date.now() - now < 1600) {
          window.location.href = '${playStoreUrl}';
        }
      }, 1200);
      window.location.href = '${appSchemeUrl}';
    }
    document.addEventListener('DOMContentLoaded', function() {
      // Auto-attempt deep link on load for convenience
      openApp();
    });
  </script>
  <link rel="canonical" href="${webUrl}" />
  <meta property="og:title" content="Watch on Vayu" />
  <meta property="og:type" content="website" />
  <meta property="og:url" content="${webUrl}" />
  <meta name="twitter:card" content="summary" />
  <meta name="twitter:title" content="Watch on Vayu" />
  <meta name="theme-color" content="#2563eb" />
  <meta http-equiv="refresh" content="0; url=${appSchemeUrl}" />
  <!-- For Android intent handler (in some browsers) -->
  <meta http-equiv="Refresh" content="0; url=intent://video/${id}#Intent;scheme=snehayog;package=com.snehayog.app;end"> 
</head>
<body>
  <div class="card">
    <h1>Open in Vayu</h1>
    <p>If the app doesn't open automatically, use the buttons below.</p>
    <div class="actions">
      <a class="btn primary" href="${appSchemeUrl}">Open App</a>
      <a class="btn secondary" href="${playStoreUrl}">Get the App</a>
    </div>
    <p class="hint">Link: ${webUrl}</p>
  </div>
</body>
</html>`;

  res.status(200).send(html);
});

// Admin Dashboard route
app.get('/admin/dashboard', (req, res) => {
  res.sendFile(path.join(__dirname, 'admin', 'admin_dashboard.html'));
});

// Health check endpoints (both /health and /api/health)
app.get('/health', (req, res) => {
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

app.get('/api/health', (req, res) => {
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

// 404 handler
app.use(notFoundHandler);

// Error handling middleware
app.use(errorHandler);

// Graceful shutdown
const gracefulShutdown = async (signal) => {
  
  try {
    await databaseManager.disconnect();
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Error during shutdown:', error);
    process.exit(1);
  }
};

// Handle shutdown signals
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// Start server
const startServer = async () => {
  try {
    // Connect to database
    await databaseManager.connect();
    
    // Start automated payout service
    automatedPayoutService.startScheduler();
    
    // Start ad cleanup cron job (run every hour at minute 0)
    cron.schedule('0 * * * *', async () => {
      try {
        await adCleanupService.runCleanup();
      } catch (error) {
        console.error('❌ Error in scheduled ad cleanup:', error);
      }
    });
    
    // Start HTTP server
    app.listen(PORT, HOST, () => {
      
    });
    
  } catch (error) {
    console.error('❌ Failed to start server:', error);
    process.exit(1);
  }
};

startServer();