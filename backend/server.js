import 'dotenv/config';
import 'newrelic';
import express from 'express';
import cors from 'cors';
import path from 'path';
import compression from 'compression';
import { fileURLToPath } from 'url';
import cron from 'node-cron';

// **FIX: Don't disable console.log in production - we need it for Railway debugging**
// Only disable if explicitly requested via DISABLE_CONSOLE_LOG=true

if (process.env.DISABLE_CONSOLE_LOG === 'true') {
  // eslint-disable-next-line no-console
  console.log = () => { };
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
import reportRoutes from './routes/reportRoutes.js';
import notificationRoutes from './routes/notificationRoutes.js';
import searchRoutes from './routes/searchRoutes.js';
import appConfigRoutes from './routes/appConfigRoutes.js';

// Import services
import automatedPayoutService from './services/automatedPayoutService.js';
import adCleanupService from './services/adCleanupService.js';
import redisService from './services/redisService.js';
import monthlyNotificationCron from './services/monthlyNotificationCron.js';
import recommendationScoreCron from './services/recommendationScoreCron.js';

// Import middleware
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';
import { apiVersioning } from './middleware/apiVersioning.js';

const app = express();
app.set('etag', 'strong');

const createCacheMiddleware = (cacheHeader) => (req, res, next) => {
  if (req.method !== 'GET') {
    return next();
  }
  // **FIX: Allow caching if explicitly marked 'public', even with Auth header**
  // Only skip caching if it's NOT public AND has auth header
  if (req.headers.authorization && !cacheHeader.includes('public')) {
    return next();
  }
  
  res.set('Cache-Control', cacheHeader);
  res.set('Vary', 'Authorization');
  return next();
};

// ES Module equivalent of __dirname
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Check required environment variables (support both MONGO_URI and MONGODB_URI)
// **FIX: Don't exit early - allow server to start for healthcheck even if DB is missing**
const mongoUri = process.env.MONGO_URI;
if (!mongoUri) {
  console.warn('⚠️ Missing environment variable: MONGO_URI');
  console.warn('⚠️ Server will start but database features will be unavailable');
} else {
  // Set the environment variable for consistency
  process.env.MONGO_URI = mongoUri;
}

// Port and Host configuration - PRODUCTION SAFE
// Railway injects process.env.PORT (typically 8080)
// Must use 0.0.0.0 to accept connections from Railway's proxy
const PORT = parseInt(process.env.PORT, 10) || 5001;
const HOST = process.env.HOST || '0.0.0.0'; // Railway requires 0.0.0.0

// Validate port is a valid number
if (isNaN(PORT) || PORT < 1 || PORT > 65535) {
  console.error(`❌ Invalid PORT: ${PORT}. Must be 1-65535`);
  process.exit(1);
}

// Asset Links dynamic response (avoid committing real fingerprints)
const assetLinksPackageName = process.env.ANDROID_ASSETLINKS_PACKAGE_NAME;
const assetLinksFingerprintsRaw = process.env.ANDROID_ASSETLINKS_FINGERPRINTS || '';
const assetLinksFingerprints = assetLinksFingerprintsRaw
  .split(',')
  .map((fp) => fp.trim())
  .filter((fp) => fp.length > 0);

if (assetLinksPackageName && assetLinksFingerprints.length > 0) {
  app.get('/.well-known/assetlinks.json', (req, res) => {
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

// Middleware
app.use(compression()); // Enable gzip compression
app.use(express.static(path.join(__dirname, 'public'))); // Serve static files from public
app.use('/.well-known', express.static(path.join(__dirname, 'public/.well-known')))
// Rate Limiter Imports
import { globalLimiter, apiLimiter } from './middleware/rateLimiter.js';

// **ENHANCED: CORS Configuration for Flutter app and Railway**
app.use(cors({
  origin: function (origin, callback) {
    // Allow requests with no origin (like mobile apps, Postman, or curl requests)
    if (!origin) {
      return callback(null, true);
    }

    const allowedOrigins = [
      'https://snehayog.site', // Production web app
      'https://vayug.fly.dev', // Fly.io Production
      'https://cerulean-kashata-b8a907.netlify.app', // Netlify deployment
      /^https:\/\/.*\.netlify\.app$/, // All Netlify subdomains
      'http://localhost', // Local development (any port)
      'http://localhost:5001', // Local development
      'http://localhost:8080', // Flutter web default port
      /^http:\/\/localhost:\d+$/, // Any localhost port (for Flutter web)
      'http://127.0.0.1', // Localhost alternative (any port)
      'http://127.0.0.1:5000', // Localhost alternative
      'http://127.0.0.1:5001', // Localhost alternative
      'http://127.0.0.1:8080', // Flutter web default port
      /^http:\/\/127\.0\.0\.1:\d+$/, // Any 127.0.0.1 port (for Flutter web)
      'http://192.168.0.184:5001', // Local development (LAN)
      'http:/192.168.0.187:5001', // Local development (User Laptop)
      'http://192.168.0.198:5001', // Local development (LAN)
      /^http:\/\/192\.168\.\d+\.\d+:\d+$/, // Any LAN IP (for mobile devices)
      'http://10.0.2.2:5001', // Android emulator
    ];

    // Check if origin matches any allowed pattern
    const isAllowed = allowedOrigins.some(allowed => {
      if (allowed instanceof RegExp) {
        return allowed.test(origin);
      }
      return allowed === origin;
    });

    if (isAllowed) {
      callback(null, true);
    } else {
      // In development, allow all origins as fallback
      if (process.env.NODE_ENV === 'development' || !process.env.NODE_ENV) {
        console.log(`⚠️ CORS: Allowing origin in dev mode: ${origin}`);
        callback(null, true);
      } else {
        callback(new Error('Not allowed by CORS'));
      }
    }
  },
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS', 'PATCH'],
  allowedHeaders: [
    'Content-Type',
    'Authorization',
    'X-Requested-With',
    'Accept',
    'Origin',
    'Access-Control-Request-Method',
    'Access-Control-Request-Headers',
    'x-admin-key',
    'X-Admin-Key',
    'X-RateLimit-Limit',
    'X-RateLimit-Remaining',
    'X-RateLimit-Reset',
    'Retry-After'
  ],
  exposedHeaders: ['Content-Length', 'Content-Range', 'Accept-Ranges', 'X-RateLimit-Limit', 'X-RateLimit-Remaining', 'Retry-After'],
  maxAge: 86400
}));

// Apply Global Rate Limiter (Catch-all for safety)
app.use(globalLimiter);

app.use(express.json({ limit: '100mb' }));
app.use(express.urlencoded({ extended: true, limit: '100mb' }));

// 🚀 PERFORMANCE & ROUTING FIX: Strip redundant /api prefixes
// This handles bugs where frontend or proxy adds extra /api/api
app.use((req, res, next) => {
    if (req.url.startsWith('/api/api')) {
        const originalUrl = req.url;
        // Replace multiple occurrences of /api at the start with just one
        req.url = req.url.replace(/^\/api(\/api)+/, '/api');
        // console.log(`📡 Route Fix: Corrected ${originalUrl} -> ${req.url}`);
    
        // New Relic transaction naming fix (optional but helpful)
        if (typeof newrelic !== 'undefined') {
            newrelic.setTransactionName(req.method + ' ' + req.url);
        }
    }
    next();
});

// Serve static files from uploads directory
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// Serve admin dashboard assets
app.use('/admin', express.static(path.join(__dirname, 'admin')));

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

// Serve app-ads.txt and ads.txt from root
app.get(["/app-ads.txt", "/ads.txt"], (req, res) => {
  res.sendFile(path.join(__dirname, "ads.txt"));
});

// Serve the production APK
app.get('/download/vayu-latest.apk', (req, res) => {
  const apkPath = path.join(__dirname, 'public/download/app-release.apk');
  res.download(apkPath, 'vayu-latest.apk', (err) => {
    if (err) {
      if (!res.headersSent) {
        res.status(404).send('APK not found. Please try again later.');
      }
    }
  });
});


// API Routes
// Note: /api/app-config is excluded from API versioning as it's needed for version detection
app.use('/api/app-config', appConfigRoutes);

// Apply API versioning to all other API routes
// Create a router group for versioned routes
const apiRouter = express.Router();
apiRouter.use('/users', userRoutes);
apiRouter.use('/auth', authRoutes);
apiRouter.use('/ads', createCacheMiddleware('public, max-age=180, stale-while-revalidate=600'), adRoutes);
apiRouter.use('/billing', billingRoutes);
apiRouter.use('/creator-payouts', creatorPayoutRoutes);
apiRouter.use('/videos', createCacheMiddleware('public, max-age=180, stale-while-revalidate=600'), videoRoutes);
apiRouter.use('/admin', adminRoutes);
apiRouter.use('/upload', uploadRoutes);
apiRouter.use('/feedback', feedbackRoutes);
apiRouter.use('/referrals', referralRoutes);
apiRouter.use('/report', reportRoutes);
apiRouter.use('/notifications', notificationRoutes);
apiRouter.use('/search', searchRoutes);

// Apply versioning middleware to the API router
import { verifyToken, passiveVerifyToken } from './utils/verifytoken.js';

// Apply versioning middleware to the API router
// **NEW: Apply Passive Auth BEFORE Rate Limiter**
// This ensures req.user is populated so we can limit by User ID instead of IP
app.use('/api', apiVersioning, passiveVerifyToken, apiLimiter, apiRouter);

// **FIX: Root route handler - serves the landing page for APK distribution
app.get('/', (req, res) => {
  console.log('🔗 Root route hit - Serving Landing Page:', req.url);
  res.sendFile(path.join(__dirname, 'public', 'index.html'));
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
  console.log(`\n🛑 Received ${signal}, shutting down gracefully...`);

  try {
    // Stop cron jobs
    monthlyNotificationCron.stop();
    recommendationScoreCron.stop();
    // console.log('🚀 Running initial score calculation on startup...');
    // RecommendationService.recalculateScopes();

    // Disconnect Redis
    if (redisService.getConnectionStatus()) {
      await redisService.disconnect();
    }

    // Disconnect database
    await databaseManager.disconnect();

    console.log('✅ Graceful shutdown complete');
    process.exit(0);
  } catch (error) {
    console.error('❌ Error during shutdown:', error);
    process.exit(1);
  }
};

// Handle shutdown signals
process.on('SIGTERM', () => gracefulShutdown('SIGTERM'));
process.on('SIGINT', () => gracefulShutdown('SIGINT'));

// Start server - PRODUCTION SAFE with proper error handling
const startServer = async () => {
  try {
    // Log server configuration for debugging
    console.log('🔍 Server Configuration:');
    console.log(`   PORT: ${PORT} (from ${process.env.PORT ? 'process.env.PORT' : 'fallback'})`);
    console.log(`   HOST: ${HOST}`);
    console.log(`   NODE_ENV: ${process.env.NODE_ENV || 'development'}`);

    // **FIX: Start HTTP server FIRST so healthcheck works immediately**
    // Database connection will happen in background (non-blocking)
    const server = app.listen(PORT, HOST, () => {
      const addr = server.address();
      console.log(`🚀 Server running on ${addr.address}:${addr.port}`);
      console.log('✅ Server is ready to accept connections');
      console.log('🔌 Database connecting in background...');
    });

    // Handle server binding errors
    server.on('error', (error) => {
      if (error.code === 'EADDRINUSE') {
        console.error(`❌ Port ${PORT} is already in use`);
        console.error(`   Another process may be using this port`);
        process.exit(1);
      } else if (error.code === 'EACCES') {
        console.error(`❌ Permission denied binding to port ${PORT}`);
        console.error(`   Try using a port > 1024 or run with elevated privileges`);
        process.exit(1);
      } else {
        console.error(`❌ Server binding error: ${error.message}`);
        throw error;
      }
    });

    // Verify successful binding
    server.on('listening', () => {
      const addr = server.address();
      console.log(`✅ Server successfully bound to ${addr.address}:${addr.port}`);

      // Verify port matches what we requested
      if (addr.port === PORT) {
        console.log(`✅ Port binding verified: ${PORT}`);
      } else {
        console.warn(`⚠️ Port mismatch: requested ${PORT}, bound to ${addr.port}`);
      }
    });

    // **FIX: Connect to database in background (non-blocking)**
    // This allows healthcheck to work even if database is slow/failing
    if (mongoUri) {
      databaseManager.connect()
        .then(() => {
          console.log('✅ Database connected successfully');
          // Start services that require database
          automatedPayoutService.startScheduler();

          // Start ad cleanup cron job (run every hour at minute 0)
          cron.schedule('0 * * * *', async () => {
            try {
              await adCleanupService.runCleanup();
            } catch (error) {
              console.error('❌ Error in scheduled ad cleanup:', error);
            }
          });

          // Start monthly notification cron job (runs on 1st of every month at 9:00 AM)
          monthlyNotificationCron.start();

          // Start recommendation score recalculation cron job (runs every 15 minutes)
          recommendationScoreCron.start();
        })
        .catch((error) => {
          console.error('❌ Database connection failed:', error.message);
          console.log('⚠️ App will continue running - database features unavailable');
          console.log('⚠️ Database will retry connection automatically');
        });
    } else {
      console.warn('⚠️ No MongoDB URI - skipping database connection');
      console.warn('⚠️ Database features will be unavailable');
    }

    // **FIX: Connect to Redis in background (non-blocking)**
    redisService.connect()
      .then((redisConnected) => {
        if (redisConnected) {
          console.log('✅ Redis connected successfully - Caching enabled');
        } else {
          console.log('⚠️ Redis connection failed - App will continue without caching');
        }
      })
      .catch((error) => {
        console.error('❌ Redis connection error:', error.message);
        console.log('⚠️ App will continue without Redis caching');
      });

  } catch (error) {
    console.error('❌ Failed to start server:', error);
    console.error('❌ Error details:', {
      code: error.code,
      message: error.message,
      stack: error.stack
    });

    // **FIX: Only exit on critical errors (like port already in use)**
    if (error.code === 'EADDRINUSE' || error.code === 'EACCES') {
      console.error('❌ Critical binding error - exiting');
      process.exit(1);
    } else {
      console.error('⚠️ Server started with errors - healthcheck should still work');
      // Don't exit - allow healthcheck to work
    }
  }
};

startServer();