import express from 'express';
import multer from 'multer';
import Video from '../models/Video.js';
import User from '../models/User.js';
import cloudinary from '../config/cloudinary.js';
import fs from 'fs'; // To delete temp file after upload
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
    const { googleId, videoName, description, videoType, link } = req.body;

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
      link,
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
        videoCount: videos.length,
        link: videos.link,
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

// Get all videos (optimized for performance)
router.get('/', async (req, res) => {
  try {
    console.log('📹 Fetching videos...');
    
    // Get query parameters for pagination
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    const skip = (page - 1) * limit;
    
    // Use Promise.all to run queries in parallel for better performance
    const [totalVideos, videos] = await Promise.all([
      Video.countDocuments(),
      Video.find()
        .select('videoName videoUrl thumbnailUrl likes views shares description uploader uploadedAt likedBy videoType aspectRatio duration comments link')
        .populate('uploader', 'name profilePic')
        .populate('comments.user', 'name profilePic')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean() // Use lean() for better performance (returns plain objects)
    ]);
    
    console.log(`✅ Found ${videos.length} videos (page ${page}, total: ${totalVideos}) in ${Date.now()}ms`);
    
    // Add caching headers for better performance
    res.set({
      'Cache-Control': 'public, max-age=30', // Cache for 30 seconds
      'ETag': `videos-${page}-${limit}-${totalVideos}`,
      'Last-Modified': new Date().toUTCString()
    });
    
    // Return in the format the Flutter app expects
    res.json({
      videos: videos,
      hasMore: (page * limit) < totalVideos,
      total: totalVideos,
      currentPage: page,
      totalPages: Math.ceil(totalVideos / limit)
    });
  } catch (error) {
    console.error('❌ Error fetching videos:', error);
    res.status(500).json({ 
      error: 'Failed to fetch videos',
      message: error.message 
    });
  }
});

// Debug endpoint to get all videos without pagination
router.get('/debug/all', async (req, res) => {
  try {
    console.log('🔍 Debug: Fetching all videos without pagination...');
    
    const videos = await Video.find()
      .populate('uploader', 'name profilePic')
      .populate('comments.user', 'name profilePic')
      .sort({ createdAt: -1 });
    
    console.log(`🔍 Debug: Found ${videos.length} total videos`);
    
    res.json({
      message: 'All videos (debug endpoint)',
      count: videos.length,
      videos: videos
    });
  } catch (error) {
    console.error('❌ Debug endpoint error:', error);
    res.status(500).json({ error: 'Error in debug endpoint' });
  }
});

// POST /api/videos/:id/like - Toggle like for a video (must be before /:id route)
router.post('/:id/like', async (req, res) => {
  try {
    const { userId } = req.body;
    const videoId = req.params.id;

    console.log('🔍 Like API: Received request', { userId, videoId });

    // Find or create user
    let user = await User.findOne({ googleId: userId });
    if (!user) {
      console.log('🔍 Like API: User not found, creating new user with googleId:', userId);
      // Create user if they don't exist
      user = new User({
        googleId: userId,
        name: 'User', // Will be updated later
        email: '', // Will be updated later
        following: [],
        followers: []
      });
      await user.save();
      console.log('✅ Like API: Created new user with ID:', user._id);
    }

    // Find the video
    const video = await Video.findById(videoId);
    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    console.log('🔍 Like API: Video found, current likes:', video.likes, 'likedBy:', video.likedBy);

    // Check if user has already liked the video
    const userLikedIndex = video.likedBy.indexOf(userId);
    let wasLiked = false;
    
    if (userLikedIndex > -1) {
      // User has already liked - remove the like
      video.likedBy.splice(userLikedIndex, 1);
      video.likes = Math.max(0, video.likes - 1); // Decrement likes, ensure not negative
      wasLiked = false;
      console.log('🔍 Like API: Removed like, new count:', video.likes);
    } else {
      // User hasn't liked - add the like
      video.likedBy.push(userId);
      video.likes = video.likes + 1; // Increment likes
      wasLiked = true;
      console.log('🔍 Like API: Added like, new count:', video.likes);
    }

    await video.save();
    console.log('✅ Like API: Video saved successfully');

    // Return the updated video with populated fields
    const updatedVideo = await Video.findById(videoId)
      .populate('uploader', 'name profilePic')
      .populate('comments.user', 'name profilePic');

    res.json({
      ...updatedVideo.toObject(),
      likeAction: wasLiked ? 'added' : 'removed',
      newLikeCount: video.likes
    });
    
    console.log('✅ Like API: Successfully toggled like, returning video');
    
  } catch (err) {
    console.error('❌ Like API Error:', err);
    res.status(500).json({ 
      error: 'Failed to toggle like', 
      details: err.message,
      stack: process.env.NODE_ENV === 'development' ? err.stack : undefined
    });
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


// Delete video by ID
router.delete('/:id', async (req, res) => {
  try {
    const videoId = req.params.id;
    const deletedVideo = await Video.findByIdAndDelete(videoId);
    if (!deletedVideo) {
      return res.status(404).json({ error: 'Video not found' });
    }
    res.json({ success: true, message: 'Video deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: 'Failed to delete video' });
  }
});


export default router