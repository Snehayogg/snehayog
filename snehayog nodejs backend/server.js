const express = require('express');
const app = express();
require('dotenv').config();
const mongoose = require('mongoose');
const cors = require('cors');
const path = require('path');
const fs = require('fs');
const videoRoutes = require('./routes/videoRoutes');
const User = require('./models/User');

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
mongoose.connect(process.env.MONGO_URI, {
  useNewUrlParser: true,
  useUnifiedTopology: true
})
.then(() => console.log("✅ MongoDB connected"))
.catch(err => console.error("❌ MongoDB error", err));


// Routes
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

// Get user by Google ID
app.get('/api/users/:googleId', async (req, res) => {
  try {
    const user = await User.findOne({ googleId: req.params.googleId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    res.json(user);
  } catch (err) {
    console.error('Get user error:', err);
    res.status(500).json({ error: 'Failed to fetch user' });
  }
});

// Add a test endpoint to verify server is working
app.get('/api/test', (req, res) => {
  res.json({ message: 'Server is working!' });
});

// Error handling middleware
app.use((err, req, res, next) => {
  console.error('Server error:', err);
  res.status(500).json({
    error: 'Internal server error',
    message: err.message
  });
});

// Start server
const PORT = process.env.PORT || 5000;

const server = app.listen(PORT, () => {
  console.log(`✅ Server is running on port ${PORT}`);
});
