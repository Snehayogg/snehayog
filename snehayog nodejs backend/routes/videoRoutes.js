const express = require('express');
const multer = require('multer');
const path = require('path');
const Video = require('../models/Video');
const User = require('../models/User');
const fs = require('fs');
const mongoose = require('mongoose');
const ffmpeg = require('fluent-ffmpeg');

const router = express.Router();

// Configure multer for video uploads
const storage = multer.diskStorage({
  destination: function (req, file, cb) {
    const uploadDir = path.join(__dirname, '../uploads/videos');
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: function (req, file, cb) {
    cb(null, Date.now() + '-' + file.originalname);
  }
});

const upload = multer({ storage: storage });

// Upload video
router.post('/upload', upload.single('video'), async (req, res) => {
  try {
    const { googleId, videoName, description } = req.body;
    const originalPath = req.file.path;
    const outputFilename = `compressed-${req.file.filename}`;
    const outputPath = path.join(path.dirname(originalPath), outputFilename);

    // --- FFmpeg Compression ---
    ffmpeg(originalPath)
      .output(outputPath)
      .videoCodec('libx264')
      .size('?x480') // 480p height, auto width
      .videoBitrate('500k')
      .on('end', async () => {
        // --- Save to DB after compression ---
        const user = await User.findOne({ googleId });
        if (!user) {
          return res.status(404).json({ error: 'User not found' });
        }

        const video = new Video({
          videoName,
          description,
          videoUrl: `/uploads/videos/${outputFilename}`, // Compressed
          originalVideoUrl: `/uploads/videos/${req.file.filename}`, // Original
          thumbnailUrl: `/uploads/videos/${req.file.filename}.jpg`,
          uploader: user._id,
        });

        await video.save();
        user.videos.push(video._id);
        await user.save();

        res.status(201).json({
          message: 'Video uploaded and compressed successfully',
          video,
        });
      })
      .on('error', (err) => {
        console.error('FFmpeg error:', err);
        res.status(500).json({ error: 'Failed to process video.' });
      })
      .run();
  } catch (error) {
    console.error('Error uploading video:', error);
    res.status(500).json({ error: 'Error uploading video' });
  }
});

// Stream video
router.get('/stream/:filename', (req, res) => {
  const { filename } = req.params;
  const videoPath = path.join(__dirname, '../uploads/videos', filename);

  const stat = fs.statSync(videoPath);
  const fileSize = stat.size;
  const range = req.headers.range;

  if (range) {
    const parts = range.replace(/bytes=/, "").split("-");
    const start = parseInt(parts[0], 10);
    const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;

    const chunksize = (end - start) + 1;
    const file = fs.createReadStream(videoPath, { start, end });
    const head = {
      'Content-Range': `bytes ${start}-${end}/${fileSize}`,
      'Accept-Ranges': 'bytes',
      'Content-Length': chunksize,
      'Content-Type': 'video/mp4',
    };

    res.writeHead(206, head);
    file.pipe(res);
  } else {
    const head = {
      'Content-Length': fileSize,
      'Content-Type': 'video/mp4',
    };
    res.writeHead(200, head);
    fs.createReadStream(videoPath).pipe(res);
  }
});

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

    // Add full URLs to each video
    const videosWithUrls = videos.map(video => {
      const compressedFilename = video.videoUrl ? path.basename(video.videoUrl) : '';
      const originalFilename = video.originalVideoUrl ? path.basename(video.originalVideoUrl) : '';
      const thumbFilename = video.thumbnailUrl ? path.basename(video.thumbnailUrl) : '';

      return {
        ...video.toObject(),
        videoUrl: compressedFilename ? `${req.protocol}://${req.get('host')}/api/videos/stream/${compressedFilename}` : '',
        originalVideoUrl: originalFilename ? `${req.protocol}://${req.get('host')}/api/videos/stream/${originalFilename}` : '',
        thumbnailUrl: thumbFilename ? `${req.protocol}://${req.get('host')}/uploads/thumbnails/${thumbFilename}` : ''
      };
    });

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
    
    // Add full URLs to each video
    const videosWithUrls = videos.map(video => {
      const compressedFilename = video.videoUrl ? path.basename(video.videoUrl) : '';
      const originalFilename = video.originalVideoUrl ? path.basename(video.originalVideoUrl) : '';
      const thumbFilename = video.thumbnailUrl ? path.basename(video.thumbnailUrl) : '';

      return {
        ...video.toObject(),
        videoUrl: compressedFilename ? `${req.protocol}://${req.get('host')}/api/videos/stream/${compressedFilename}` : '',
        originalVideoUrl: originalFilename ? `${req.protocol}://${req.get('host')}/api/videos/stream/${originalFilename}` : '',
        thumbnailUrl: thumbFilename ? `${req.protocol}://${req.get('host')}/uploads/thumbnails/${thumbFilename}` : ''
      };
    });

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

module.exports = router;