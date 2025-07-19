const express = require('express');
const multer = require('multer');
const Video = require('../models/Video');
const User = require('../models/User');
const cloudinary = require('../config/cloudinary.js');
const { CloudinaryStorage } = require('multer-storage-cloudinary');
const fs = require('fs'); // To delete temp file after upload
const mongoose = require('mongoose'); // For database health check
const router = express.Router();

// Multer disk storage to get original file first
const tempStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    // Ensure uploads directory exists
    const uploadDir = 'uploads/';
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    // Generate unique filename with timestamp
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, uniqueSuffix + '-' + file.originalname);
  },
});

const upload = multer({
  storage: tempStorage,
  limits: {
    fileSize: 100 * 1024 * 1024, // 100MB limit
  },
  fileFilter: (req, file, cb) => {
    // Check file type
    const allowedMimeTypes = ['video/mp4', 'video/avi', 'video/mov', 'video/wmv', 'video/flv', 'video/webm'];
    if (allowedMimeTypes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Invalid file type. Only video files are allowed.'), false);
    }
  }
});

// POST /api/videos/upload
router.post('/upload', upload.single('video'), async (req, res) => {
  let originalResult = null;
  let compressedResult = null;

  try {
    const { googleId, videoName, description, videoType } = req.body;

    // 1. Validate file
    if (!req.file || !req.file.path) {
      return res.status(400).json({ error: 'No video file uploaded' });
    }

    // 2. Validate MIME type
    const allowedTypes = ['video/mp4', 'video/webm', 'video/avi', 'video/mkv', 'video/mov'];
    if (!allowedTypes.includes(req.file.mimetype)) {
      fs.unlinkSync(req.file.path);
      return res.status(400).json({ error: 'Invalid video format' });
    }

    // 3. Validate user
    const user = await User.findOne({ googleId });
    if (!user) {
      fs.unlinkSync(req.file.path);
      return res.status(404).json({ error: 'User not found' });
    }

    // 4. Upload original video
    originalResult = await cloudinary.uploader.upload(req.file.path, {
      resource_type: 'video',
      folder: 'snehayog-originals',
      timeout: 60000
    });

    // 5. Upload compressed video
    compressedResult = await cloudinary.uploader.upload(req.file.path, {
      resource_type: 'video',
      folder: 'snehayog-videos',
      transformation: [
        { quality: 'auto:good' },
        { fetch_format: 'auto' },
      ],
      timeout: 60000
    });

    if (!originalResult?.secure_url || !compressedResult?.secure_url) {
      fs.unlinkSync(req.file.path);
      return res.status(500).json({ error: 'Cloudinary upload failed' });
    }

    // 6. Generate thumbnail URL
    const thumbnailUrl = compressedResult.secure_url.replace(
      '/upload/',
      '/upload/w_300,h_400,c_fill/'
    );

    // 7. Save video in MongoDB
    const video = new Video({
      videoName,
      description,
      videoUrl: compressedResult.secure_url,
      uploader: user._id,
      videoType: videoType || 'yog', // Default type
    });

    await video.save();

    // 8. Push video to user's video list
    user.videos.push(video._id);
    await user.save();

    // 9. Clean up temp file
    fs.unlinkSync(req.file.path);

    // 10. Respond success
    res.status(201).json({
      message: '✅ Video uploaded & saved successfully',
      video
    });

  } catch (error) {
    console.error('❌ Upload error:', error.message);

    if (req.file?.path && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path); // Clean temp
    }

    res.status(500).json({
      error: '❌ Failed to upload video',
      details: error.message
    });
  }
});


// Note: Video streaming is now handled by Cloudinary directly
// No need for local streaming endpoint as Cloudinary provides optimized video delivery

// Get videos by user ID
router.get('/user/:googleId', async (req, res) => {
  try {
    console.log('Fetching videos for user:', req.params.googleId);

    const user = await User.findOne({ googleId: req.params.googleId });
    if (!user) {
      console.log('User not found');
      return res.status(404).json({ error: 'User not found' });
    }

    console.log('Found user:', {
      id: user._id,
      name: user.name,
      googleId: user.googleId
    });

    // Get user's videos using the new method
    const videos = await user.getVideos();
    console.log('Found videos:', videos.length);

    // Cloudinary URLs are already full URLs, no need to construct them
    const videosWithUrls = videos.map(video => ({
      ...video.toObject(),
      videoUrl: video.videoUrl || '',
      originalVideoUrl: video.originalVideoUrl || '',
      thumbnailUrl: video.thumbnailUrl || ''
    }));

    res.json(videosWithUrls);
  } catch (error) {
    console.error('Error fetching user videos:', error);
    res.status(500).json({ error: 'Error fetching videos' });
  }
});

// Debug endpoint to check video-user relationships
router.get('/debug/user/:googleId', async (req, res) => {
  try {
    const user = await User.findOne({ googleId: req.params.googleId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const videos = await user.getVideos();
    res.json({
      user: {
        id: user._id,
        name: user.name,
        googleId: user.googleId,
        videoCount: videos.length
      },
      videos: videos.map(video => ({
        id: video._id,
        name: video.videoName,
        url: video.videoUrl
      }))
    });
  } catch (error) {
    console.error('Debug endpoint error:', error);
    res.status(500).json({ error: 'Error in debug endpoint' });
  }
});

// Get all videos
router.get('/', async (req, res) => {
  try {
    const page = parseInt(req.query.page, 10) || 1;
    const limit = parseInt(req.query.limit, 10) || 10; // Load 10 videos per page
    const skip = (page - 1) * limit;

    const videos = await Video.find()
      .populate('uploader', 'name profilePic')
      .populate('comments.user', 'name profilePic')
      .sort({ uploadedAt: -1 })
      .skip(skip)
      .limit(limit);

    const totalVideos = await Video.countDocuments();
    const hasMore = (page * limit) < totalVideos;

    // Cloudinary URLs are already full URLs, no need to construct them
    const videosWithUrls = videos.map(video => ({
      ...video.toObject(),
      videoUrl: video.videoUrl || '',
      originalVideoUrl: video.originalVideoUrl || '',
      thumbnailUrl: video.thumbnailUrl || ''
    }));

    res.json({
      videos: videosWithUrls,
      hasMore: hasMore
    });
  } catch (err) {
    console.error('Get videos error:', err);
    res.status(500).json({ error: 'Failed to fetch videos' });
  }
});

// Get video by ID
router.get('/:id', async (req, res) => {
  try {
    const video = await Video.findById(req.params.id)
      .populate('uploader', 'name profilePic')
      .populate('comments.user', 'name profilePic');

    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    res.json(video);
  } catch (err) {
    console.error('Get video error:', err);
    res.status(500).json({ error: 'Failed to fetch video' });
  }
});

router.post('/:id/comments', async (req, res) => {
  try {
    const { userId, text } = req.body;

    const user = await User.findOne({ googleId: userId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const comment = {
      user: user._id,
      text,
      createdAt: new Date(),
    };

    // ✅ Safely push comment without modifying the whole document
    const video = await Video.findByIdAndUpdate(
      req.params.id,
      { $push: { comments: comment } },
      { new: true }
    ).populate('comments.user', 'name profilePic');

    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    res.json(video.comments);
  } catch (err) {
    console.error('Error adding comment:', err);
    res.status(500).json({ error: 'Failed to add comment', details: err.message });
  }
});

module.exports = router;