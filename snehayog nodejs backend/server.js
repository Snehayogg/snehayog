import express from 'express';
const app = express();
import dotenv from 'dotenv';
dotenv.config();
import mongoose from 'mongoose';
import cors from 'cors';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';
import videoRoutes from './routes/videoRoutes.js';
import User from './models/User.js'
import userRoutes from './routes/userRoutes.js'
import compression from 'compression';

// ES Module equivalent of __dirname
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

app.use(compression()); // Enable gzip compression for all responses

// Check required environment variables
const requiredEnvVars = ['MONGO_URI'];
const missingEnvVars = requiredEnvVars.filter(envVar => !process.env[envVar]);

// Ensure upload directories exist
const uploadsDir = path.join(__dirname, 'uploads');
const videosDir = path.join(uploadsDir, 'videos');
const thumbnailsDir = path.join(uploadsDir, 'thumbnails');

[uploadsDir, videosDir, thumbnailsDir].forEach(dir => {
  if (!fs.existsSync(dir)) {
    console.log(`Creating directory: ${dir}`);
    fs.mkdirSync(dir, { recursive: true });
  }
});

// List contents of videos directory
console.log('Contents of videos directory:');
fs.readdir(videosDir, (err, files) => {
  if (err) {
    console.error('Error reading videos directory:', err);
  } else {
    console.log('Videos found:', files);
  }
});

// Middleware
app.use(cors());
app.use(express.json());

// Serve static files from uploads directory
app.use('/uploads', express.static(path.join(__dirname, 'uploads')));
app.use('/api/users', userRoutes);

// Log all requests with more details
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.url}`);
  console.log('Headers:', req.headers);
  console.log('Query params:', req.query);
  console.log('Body:', req.body);
  console.log('-------------------');
  next();
});

// Connect to MongoDB
console.log('🔌 Connecting to MongoDB...');
console.log(`📍 MongoDB URI: ${process.env.MONGO_URI}`);

mongoose.connect(process.env.MONGO_URI, {
  useNewUrlParser: true,
  useUnifiedTopology: true,
  serverSelectionTimeoutMS: 5000, // 5 second timeout
  socketTimeoutMS: 45000, // 45 second timeout
})
.then(() => console.log("✅ MongoDB connected successfully"))
.catch(err => {
  console.error("❌ MongoDB connection failed:", err.message);
  console.error("💡 Troubleshooting tips:");
  console.error("   1. Is MongoDB running? Start with: mongod");
  console.error("   2. Check if MongoDB is accessible at: " + process.env.MONGO_URI);
  console.error("   3. For local MongoDB, ensure it's running on port 27017");
  console.error("   4. Check MongoDB logs for any errors");
  console.error("");
  console.error("🔧 Quick fixes:");
  console.error("   - Windows: MongoDB should start as a service automatically");
  console.error("   - macOS: brew services start mongodb-community");
  console.error("   - Linux: sudo systemctl start mongod");
  process.exit(1);
});

app.get('/', async (req, res) => {
  res.json({
    message: 'Snehayog Backend Server is running!',
    status: 'OK',
    timestamp: new Date().toISOString(),
    endpoints: {
      test: '/api/test',
      health: '/api/health',
      simpleTest: '/api/simple-test',
      connectivityTest: '/api/connectivity-test',
      videos: '/api/videos',
      users: '/api/users'
    },
    services: {
      mongodb: 'required',
      server: 'running'
    }
  });
});

// Simple test route that doesn't require external services
app.get('/api/simple-test', (req, res) => {
  res.json({
    message: 'Basic server functionality is working!',
    timestamp: new Date().toISOString(),
    status: 'OK',
    server: 'Snehayog Backend',
    version: '1.0.0'
  });
});

// Basic connectivity test (no external dependencies)
app.get('/api/connectivity-test', (req, res) => {
  res.json({
    message: 'Server is responding to requests!',
    timestamp: new Date().toISOString(),
    status: 'OK',
    test: 'connectivity',
    note: 'This endpoint works without MongoDB or Redis'
  });
});

app.use('/api/videos', videoRoutes);

// User registration endpoint
app.post('/api/users/register', async (req, res) => {
  try {
    const { googleId, name, email, profilePic } = req.body;

    // Check if user already exists
    let user = await User.findOne({ googleId });
    
    if (!user) {
      // Create new user
      user = new User({
        googleId,
        name,
        email,
        profilePic,
      });
      await user.save();
    }

    res.status(201).json(user);
  } catch (err) {
    console.error('User registration error:', err);
    res.status(500).json({ error: 'Failed to register user' });
  }
});

// Add a test endpoint to verify server is working
app.get('/api/test', (req, res) => {
  res.json({ 
    message: 'Server is working!',
    timestamp: new Date().toISOString(),
    status: 'OK'
  });
});

// Health check endpoint
app.get('/api/health', (req, res) => {
  res.json({
    status: 'healthy',
    timestamp: new Date().toISOString(),
    services: {
      mongodb: mongoose.connection.readyState === 1 ? 'connected' : 'disconnected',
      server: 'running'
    }
  });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Server error:', err);
  res.status(500).json({
    error: 'Internal server error',
    message: err.message
  });
});

const PORT = process.env.PORT || 5000;
const HOST = process.env.HOST || '192.168.0.190';

app.listen(PORT, HOST, () => {
  console.log('🚀 Server started successfully!');
  console.log(`📍 Server running at http://${HOST}:${PORT}`);
  console.log(`🔍 Health check: http://${HOST}:${PORT}/api/health`);
  console.log(`🧪 Test endpoint: http://${HOST}:${PORT}/api/test`);
  console.log(`📱 API base URL: http://${HOST}:${PORT}/api`);
  console.log('');
  console.log('📊 Service Status:');
  console.log(`   🟢 Server: Running on ${HOST}:${PORT}`);
  console.log(`   🔵 MongoDB: Required (check logs above)`);
  console.log('');
  console.log('🧪 Test these endpoints:');
  console.log(`   • Basic test: http://${HOST}:${PORT}/api/connectivity-test`);
  console.log(`   • Health check: http://${HOST}:${PORT}/api/health`);
});
