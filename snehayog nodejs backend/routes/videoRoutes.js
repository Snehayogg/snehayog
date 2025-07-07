const express = require('express');
const multer = require('multer');
const Video = require('../models/Video');
const User = require('../models/User');
const mongoose = require('mongoose');
const cloudinary = require('../config/cloudnary.js');
const { CloudinaryStorage } = require('multer-storage-cloudinary');

const router = express.Router();

// Configure Cloudinary storage for video uploads
const storage = new CloudinaryStorage({
  cloudinary: cloudinary,
  params: {
    folder: 'snehayog-videos',
    resource_type: 'video',
    allowed_formats: ['mp4', 'avi', 'mov', 'mkv', 'webm'],
    transformation: [
      { width: 1080, height: 1920, crop: 'fill' }, // Optimize for mobile
      { quality: 'auto' }
    ]
  }
});

const upload = multer({ storage: storage });

// Upload video to Cloudinary
router.post('/upload', upload.single('video'), async (req, res) => {
  console.log('req.file:', req.file); // uploaded video
  console.log('req.body:', req.body);
  try {
    const { googleId, videoName, description } = req.body;

    if (!req.file || !req.file.path) {
      return res.status(400).json({ error: 'Cloudinary upload failed. No file found.' });
    }

    const videoUrl = req.file.path;
    const thumbnailUrl = videoUrl.includes('/upload/')
      ? videoUrl.replace('/upload/', '/upload/w_300,h_400,c_fill/')
      : '';

    const user = await User.findOne({ googleId });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const video = new Video({
      videoName,
      description,
      videoUrl,
      originalVideoUrl: videoUrl,
      thumbnailUrl,
      uploader: user._id,
    });

    await video.save();
    user.videos.push(video._id);
    await user.save();

    res.status(201).json({
      message: '✅ Video uploaded successfully to Cloudinary',
      video,
    });
  } catch (error) {
    console.error('❌ Upload Error:', error.message, error.stack);
    res.status(500).json({ error: '❌ Failed to upload video', details: error.message });
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