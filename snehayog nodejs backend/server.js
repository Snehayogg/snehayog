import express from 'express';
import dotenv from 'dotenv';
import cors from 'cors';
import path from 'path';
import compression from 'compression';
import { fileURLToPath } from 'url';

// Import database manager
import databaseManager from './config/database.js';

// Import routes
import videoRoutes from './routes/videoRoutes.js';
import userRoutes from './routes/userRoutes.js';
import authRoutes from './routes/authRoutes.js';
import adRoutes from './routes/adRoutes/index.js';
import billingRoutes from './routes/billingRoutes.js';
import creatorPayoutRoutes from './routes/creatorPayoutRoutes.js';

// Import services
import automatedPayoutService from './services/automatedPayoutService.js';

// Import middleware
import { errorHandler, notFoundHandler } from './middleware/errorHandler.js';

// Load environment variables
dotenv.config();

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
const PORT = process.env.PORT || 5000;
const HOST = process.env.HOST || '0.0.0.0';

console.log('🔧 Server Configuration:');
console.log(`   📍 Port: ${PORT}`);
console.log(`   🌐 Host: ${HOST}`);
console.log(`   🔗 URL: http://${HOST}:${PORT}`);
console.log(`   📱 Flutter App should connect to: http://192.168.0.190:${PORT}`);
console.log('');

// Middleware
app.use(compression()); // Enable gzip compression
app.use(cors());
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
}, express.static(path.join(__dirname, 'uploads/hls')));

// API Routes
app.use('/api/users', userRoutes);
app.use('/api/auth', authRoutes);
app.use('/api/ads', adRoutes);
app.use('/api/billing', billingRoutes);
app.use('/api/creator-payouts', creatorPayoutRoutes);
app.use('/api/videos', videoRoutes);

// Health check endpoints (both /health and /api/health)
app.get('/health', (req, res) => {
  const dbStatus = databaseManager.getConnectionStatus();
  res.json({
    status: 'OK',
    timestamp: new Date().toISOString(),
    database: dbStatus,
    uptime: process.uptime()
  });
});

app.get('/api/health', (req, res) => {
  const dbStatus = databaseManager.getConnectionStatus();
  res.json({
    status: 'OK',
    timestamp: new Date().toISOString(),
    database: dbStatus,
    uptime: process.uptime()
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