import express from 'express';
import dotenv from "dotenv";
dotenv.config();
import cors from 'cors';
import path from 'path';
import compression from 'compression';
import { fileURLToPath } from 'url';

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

// Import services
import automatedPayoutService from './services/automatedPayoutService.js';

// Import middleware
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';

const app = express();

// ES Module equivalent of __dirname
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Check required environment variables
const requiredEnvVars = ['MONGO_URI'];
const missingEnvVars = requiredEnvVars.filter(envVar => !process.env[envVar]);

if (missingEnvVars.length > 0) {
  console.error('❌ Missing required environment variables:', missingEnvVars);
  process.exit(1);
}

// Port and Host configuration
const PORT = process.env.PORT || 5001;
const HOST = process.env.HOST || '192.168.0.190'; // Use your network IP

console.log('🔧 Server Configuration:');
console.log(`   📍 Port: ${PORT}`);
console.log(`   🌐 Host: ${HOST}`);
console.log(`   🔗 URL: http://${HOST}:${PORT}`);
console.log(`   📱 Flutter App should connect to: http://192.168.0.190:${PORT}`);
console.log('');

// Middleware
app.use(compression()); // Enable gzip compression

// **ENHANCED: CORS Configuration for Flutter app**
app.use(cors({
  origin: [
    'http://192.168.0.190:5001', // Backend URL
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
  maxAge: 86400 // 24 hours
}));

app.use(express.json({ limit: '50mb' }));
app.use(express.urlencoded({ extended: true, limit: '50mb' }));

// Request logging middleware
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  next();
});

// Serve static files from uploads directory
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));

// Serve HLS files with proper MIME types and CORS
app.use('/hls', (req, res, next) => {
  // Set CORS headers for HLS streaming
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
app.use('/api/upload', uploadRoutes);

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
  console.log(`\n🔄 Received ${signal}. Starting graceful shutdown...`);
  
  try {
    await databaseManager.disconnect();
    console.log('✅ Database connection closed');
    
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
    
    // Start HTTP server
    app.listen(PORT, HOST, () => {
      console.log(`🚀 Server running on http://${HOST}:${PORT}`);
      console.log('✅ All services initialized successfully');
    });
    
  } catch (error) {
    console.error('❌ Failed to start server:', error);
    process.exit(1);
  }
};

startServer();