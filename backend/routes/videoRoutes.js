import express from 'express';
import multer from 'multer';
import mongoose from 'mongoose';
import Video from '../models/Video.js';
import User from '../models/User.js';
import fs from 'fs'; 
import { verifyToken } from '../utils/verifytoken.js';
import { isCloudinaryConfigured } from '../config.js';
import hybridVideoService from '../services/hybridVideoService.js';
const router = express.Router();



const videoCachingMiddleware = (req, res, next) => {
  // Set aggressive caching headers for video data
  res.setHeader('Cache-Control', 'public, max-age=3600'); // 1 hour cache
  res.setHeader('Accept-Ranges', 'bytes'); // Enable range requests
  res.setHeader('Connection', 'keep-alive'); // Keep connection alive
  res.setHeader('X-Content-Type-Options', 'nosniff'); // Security
  res.setHeader('X-Frame-Options', 'SAMEORIGIN'); // Security
  
  // Add ETag for better caching
  res.setHeader('ETag', `"${Date.now()}"`);
  
  next();
};

// Apply caching middleware to all video routes
router.use(videoCachingMiddleware);

// DEBUG: Check database status - MUST BE FIRST ROUTE
router.get('/debug/database', async (req, res) => {
  try {
    console.log('🔍 DEBUG: Checking database status...');
    
    // Count all videos
    const totalVideos = await Video.countDocuments({});
    console.log('🔍 DEBUG: Total videos in database:', totalVideos);
    
    // Count videos by processing status
    const statusCounts = await Video.aggregate([
      { $group: { _id: '$processingStatus', count: { $sum: 1 } } }
    ]);
    console.log('🔍 DEBUG: Videos by processing status:', statusCounts);
    
    // Count videos by user
    const userCounts = await Video.aggregate([
      { $lookup: { from: 'users', localField: 'uploader', foreignField: '_id', as: 'user' } },
      { $unwind: '$user' },
      { $group: { _id: { googleId: '$user.googleId', name: '$user.name' }, count: { $sum: 1 } } }
    ]);
    console.log('🔍 DEBUG: Videos by user:', userCounts);
    
    // Get sample videos
    const sampleVideos = await Video.find({})
      .select('videoName uploader createdAt processingStatus videoType')
      .populate('uploader', 'googleId name')
      .limit(5)
      .lean();
    
    console.log('🔍 DEBUG: Sample videos:', sampleVideos);
    
    res.json({
      totalVideos,
      statusCounts,
      userCounts,
      sampleVideos,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('❌ DEBUG: Database check failed:', error);
    res.status(500).json({ error: error.message });
  }
});

// **NEW: Data validation middleware to ensure consistent types**
const validateVideoData = (req, res, next) => {
  try {
    // Validate numeric fields in request body
    if (req.body.likes !== undefined) {
      req.body.likes = parseInt(req.body.likes) || 0;
    }
    if (req.body.views !== undefined) {
      req.body.views = parseInt(req.body.views) || 0;
    }
    if (req.body.shares !== undefined) {
      req.body.shares = parseInt(req.body.shares) || 0;
    }
    if (req.body.duration !== undefined) {
      req.body.duration = parseInt(req.body.duration) || 0;
    }
    if (req.body.aspectRatio !== undefined) {
      req.body.aspectRatio = parseFloat(req.body.aspectRatio) || 9/16;
    }
    
    next();
  } catch (error) {
    console.error('❌ Data validation error:', error);
    res.status(400).json({ 
      error: 'Invalid data types in request',
      details: 'Numeric fields must be valid numbers'
    });
  }
};

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
router.post('/upload', verifyToken, validateVideoData, upload.single('video'), async (req, res) => {
  let originalResult = null;
  let hlsResult = null;

  try {
    console.log('🎬 Upload: Starting video upload process with HLS streaming...');
    console.log('🎬 Upload: Request body:', req.body);
    console.log('🎬 Upload: File info:', req.file ? {
      filename: req.file.filename,
      size: req.file.size,
      mimetype: req.file.mimetype,
      path: req.file.path
    } : 'No file');

    // Google ID is now available from verifyToken middleware
    const googleId = req.user.googleId;
    if (!googleId) {
      console.log('❌ Upload: Google ID not found in token');
      if (req.file) fs.unlinkSync(req.file.path);
      return res.status(401).json({ error: 'Google ID not found in token' });
    }

    const { videoName, description, videoType, link } = req.body;

    // 1. Validate file
    if (!req.file || !req.file.path) {
      console.log('❌ Upload: No video file uploaded');
      return res.status(400).json({ error: 'No video file uploaded' });
    }

    // 2. Validate required fields
    if (!videoName || videoName.trim() === '') {
      console.log('❌ Upload: Missing video name');
      fs.unlinkSync(req.file.path);
      return res.status(400).json({ error: 'Video name is required' });
    }

    // 3. Validate MIME type and file integrity
    const allowedTypes = ['video/mp4', 'video/webm', 'video/avi', 'video/mkv', 'video/mov'];
    if (!allowedTypes.includes(req.file.mimetype)) {
      console.log('❌ Upload: Invalid video format:', req.file.mimetype);
      fs.unlinkSync(req.file.path);
      return res.status(400).json({ error: 'Invalid video format' });
    }

    // 3.1 Enhanced file validation
    try {
      const stats = fs.statSync(req.file.path);
      if (stats.size === 0) {
        console.log('❌ Upload: Video file is empty (0 bytes)');
        fs.unlinkSync(req.file.path);
        return res.status(400).json({ error: 'Video file is empty or corrupted' });
      }
      
      if (stats.size < 1024) { // Less than 1KB
        console.log('❌ Upload: Video file too small (likely corrupted):', stats.size);
        fs.unlinkSync(req.file.path);
        return res.status(400).json({ error: 'Video file is too small and likely corrupted' });
      }
      
      console.log('✅ Upload: File validation passed - Size:', stats.size, 'bytes');
    } catch (validationError) {
      console.error('❌ Upload: File validation failed:', validationError);
      fs.unlinkSync(req.file.path);
      return res.status(400).json({ error: 'Failed to validate video file' });
    }

    // 4. Validate user
    console.log('🎬 Upload: Looking for user with Google ID:', googleId);
    const user = await User.findOne({ googleId: googleId });
    if (!user) {
      console.log('❌ Upload: User not found with Google ID:', googleId);
      fs.unlinkSync(req.file.path);
      return res.status(404).json({ error: 'User not found' });
    }
    console.log('✅ Upload: User found:', user.name);

    // 5. Check Cloudinary configuration
    console.log('🔍 Upload: Checking Cloudinary configuration...');
    console.log('🔍 Upload: CLOUD_NAME:', process.env.CLOUD_NAME);
    console.log('🔍 Upload: CLOUD_KEY:', process.env.CLOUD_KEY ? 'Set' : 'Missing');
    console.log('🔍 Upload: CLOUD_SECRET:', process.env.CLOUD_SECRET ? 'Set' : 'Missing');
    
    if (!isCloudinaryConfigured()) {
      console.log('❌ Upload: Cloudinary not configured');
      fs.unlinkSync(req.file.path);
      return res.status(500).json({ 
        error: 'Video upload service not configured. Please contact administrator.',
        details: 'Cloudinary API credentials are missing. Check CLOUDINARY_SETUP.md for setup instructions.',
        solution: 'Create a .env file with CLOUD_NAME, CLOUD_KEY, and CLOUD_SECRET variables'
      });
    }
    
    console.log('✅ Upload: Cloudinary configuration verified');

    // **NEW: Use Pure HLS Processing (FFmpeg → R2) for 100% FREE processing**
    console.log('🚀 Starting Pure HLS Video Processing (FFmpeg → R2)...');
    console.log('💰 Expected cost: $0 processing (FREE!) + $0.015/GB/month storage + $0 bandwidth (FREE!)');
    console.log('📹 Format: HLS (HTTP Live Streaming) - Single 480p quality');
    
    // **NEW: Validate video with hybrid service**
    const videoValidation = await hybridVideoService.validateVideo(req.file.path);
    if (!videoValidation.isValid) {
      fs.unlinkSync(req.file.path);
      return res.status(400).json({ 
        error: 'Invalid video file', 
        details: videoValidation.error 
      });
    }
    
    // **NEW: Create initial video record with pending status**
    const video = new Video({
      videoName: videoName,
      description: description || '',
      link: link || '',
      videoUrl: req.file.path, // Temporary, will be updated after processing
      thumbnailUrl: '', // Will be generated during processing
      uploader: user._id,
      videoType: videoType || 'yog',
      aspectRatio: videoValidation.width / videoValidation.height || 9/16,
      duration: videoValidation.duration || 0,
      processingStatus: 'pending',
      processingProgress: 0,
      isHLSEncoded: false, // Will be updated to true after HLS processing
      likes: 0, views: 0, shares: 0, likedBy: [], comments: [],
      uploadedAt: new Date()
    });
    
    await video.save();
    user.videos.push(video._id);
    await user.save();
    
    console.log('✅ Video record created with ID:', video._id);
    
    // **NEW: Start HLS processing in background (non-blocking)**
    processVideoToHLS(video._id, req.file.path, videoName, user._id.toString());
    
    // **NEW: Return immediate response**
    return res.status(201).json({
      success: true,
      message: 'Video upload started. Processing via FFmpeg → R2 HLS (100% FREE!).',
      video: {
        id: video._id,
        videoName: video.videoName,
        processingStatus: video.processingStatus,
        processingProgress: video.processingProgress,
        estimatedTime: '2-5 minutes',
        format: 'HLS (HTTP Live Streaming)',
        quality: '480p (single quality)',
        costBreakdown: {
          processing: '$0 (FREE! FFmpeg local)',
          storage: '$0.015/GB/month',
          bandwidth: '$0 (FREE forever!)',
          savings: '100% vs cloud processing'
        }
      }
    });
    
  } catch (error) {
    console.error('❌ Upload: Error in video upload process:', error);
    if (req.file) {
      try { fs.unlinkSync(req.file.path); } catch (_) {}
    }
    return res.status(500).json({ 
      error: 'Video upload failed', 
      details: error.message 
    });
  }
});

// **NEW: Pure HLS video processing function (FFmpeg → R2)**
async function processVideoToHLS(videoId, videoPath, videoName, userId) {
  try {
    console.log('🚀 Starting Pure HLS processing (FFmpeg → R2) for:', videoId);
    
    const video = await Video.findById(videoId);
    if (!video) {
      throw new Error('Video not found');
    }

    video.processingStatus = 'processing';
    video.processingProgress = 10;
    await video.save();
    
    // Process video using Pure HLS service (FFmpeg → R2)
    const hlsResult = await hybridVideoService.processVideoToHLS(
      videoPath, 
      videoName, 
      userId
    );

    // Update video with R2 HLS URLs (using custom domain cdn.snehayog.com)
    video.videoUrl = hlsResult.videoUrl; // HLS playlist URL (.m3u8)
    video.hlsPlaylistUrl = hlsResult.hlsPlaylistUrl; // Same as videoUrl
    video.thumbnailUrl = hlsResult.thumbnailUrl;
    video.processingStatus = 'completed';
    video.processingProgress = 100;
    video.isHLSEncoded = true; // Using HLS format
    video.lowQualityUrl = hlsResult.videoUrl; // Single quality (480p)
    
    await video.save();
    console.log('🎉 Pure HLS processing completed for:', videoId);
    console.log('📊 Result:');
    console.log(`   Format: ${hlsResult.format}`);
    console.log(`   Quality: ${hlsResult.quality}`);
    console.log(`   Segments: ${hlsResult.segments}`);
    console.log(`   Total Files: ${hlsResult.totalFiles}`);
    console.log('💰 Cost: $0 processing + $0.015/GB/month storage + $0 bandwidth');
    
  } catch (error) {
    console.error('❌ Error in Pure HLS processing:', error);
    
    try {
      const video = await Video.findById(videoId);
      if (video) {
        video.processingStatus = 'failed';
        video.processingError = error.message;
        await video.save();
      }
    } catch (updateError) {
      console.error('❌ Failed to update video status:', updateError);
    }
  }
}

// **NOTE: Now using Pure HLS Processing (FFmpeg → R2)**
// Upload → FFmpeg (Local, FREE) → HLS (.m3u8 + .ts) → R2 (FREE bandwidth)
// Single 480p quality for cost optimization
// 100% FREE processing + FREE bandwidth = Maximum savings!

// Get videos by user ID (consistently use googleId)
router.get('/user/:googleId', verifyToken, async (req, res) => {
  try {
    const { googleId } = req.params;
    console.log('🎬 Fetching videos for googleId:', googleId);

    // Find user by googleId
    const user = await User.findOne({ googleId: googleId });
    if (!user) {
      console.log('❌ User not found for googleId:', googleId);
      return res.status(404).json({ error: 'User not found' });
    }

    console.log('✅ Found user:', {
      id: user._id,
      name: user.name,
      googleId: user.googleId,
      videosArrayLength: user.videos?.length || 0
    });

    // **IMPROVED: Get videos directly from Video collection using uploader field - only completed videos**
    const videos = await Video.find({ 
      uploader: user._id,
      processingStatus: 'completed' // Only show completed videos
    })
      .populate('uploader', 'name profilePic googleId')
      .sort({ createdAt: -1 }); // Latest videos first

    console.log('🎬 Found videos count:', videos.length);

    if (videos.length === 0) {
      console.log('⚠️ No videos found for user:', user.name);
      return res.json([]);
    }

    // **IMPROVED: Better data formatting and validation**
    const videosWithUrls = videos.map(video => {
      const videoObj = video.toObject();
      
      // **CRITICAL: Ensure all required fields are present**
      const result = {
        _id: videoObj._id?.toString(),
        videoName: videoObj.videoName || 'Untitled Video',
        videoUrl: videoObj.videoUrl || videoObj.hlsMasterPlaylistUrl || videoObj.hlsPlaylistUrl || '',
        thumbnailUrl: videoObj.thumbnailUrl || '',
        description: videoObj.description || '',
        likes: parseInt(videoObj.likes) || 0,
        views: parseInt(videoObj.views) || 0,
        shares: parseInt(videoObj.shares) || 0,
        duration: parseInt(videoObj.duration) || 0,
        aspectRatio: parseFloat(videoObj.aspectRatio) || 9/16,
        videoType: videoObj.videoType || 'reel',
        link: videoObj.link || null,
        uploadedAt: videoObj.uploadedAt?.toISOString?.() || new Date().toISOString(),
        createdAt: videoObj.createdAt?.toISOString?.() || new Date().toISOString(),
        updatedAt: videoObj.updatedAt?.toISOString?.() || new Date().toISOString(),
        // **IMPROVED: Better uploader information**
        uploader: {
          id: videoObj.uploader?._id?.toString() || videoObj.uploader?.toString(),
          name: videoObj.uploader?.name || 'Unknown User',
          profilePic: videoObj.uploader?.profilePic || '',
          googleId: videoObj.uploader?.googleId || ''
        },
        // **HLS Streaming fields**
        hlsMasterPlaylistUrl: videoObj.hlsMasterPlaylistUrl || null,
        hlsPlaylistUrl: videoObj.hlsPlaylistUrl || null,
        isHLSEncoded: videoObj.isHLSEncoded || false,
        likedBy: videoObj.likedBy || [],
        comments: videoObj.comments || []
      };
      
      console.log(`🎬 Video ${result.videoName}:`, {
        id: result._id,
        hasVideoUrl: !!result.videoUrl,
        hasThumbnail: !!result.thumbnailUrl,
        likes: result.likes,
        views: result.views,
        uploader: result.uploader.name,
        uploaderGoogleId: result.uploader.googleId
      });
      
      return result;
    });

    console.log('✅ Sending videos response:', {
      totalVideos: videosWithUrls.length,
      firstVideo: videosWithUrls.isNotEmpty ? videosWithUrls[0].videoName : 'None',
      lastVideo: videosWithUrls.isNotEmpty ? videosWithUrls.last.videoName : 'None'
    });

    res.json(videosWithUrls);
  } catch (error) {
    console.error('❌ Error fetching user videos:', error);
    res.status(500).json({ 
      error: 'Error fetching videos',
      details: error.message 
    });
  }
});




// Get all videos (optimized for performance) - SUPPORTS MP4 AND HLS
router.get('/', async (req, res) => {
  try {
    const { videoType, page = 1, limit = 10 } = req.query;
    console.log('📹 Fetching videos...', { videoType, page, limit });
    
    // Get query parameters for pagination
    const pageNum = parseInt(page) || 1;
    const limitNum = parseInt(limit) || 10;
    const skip = (pageNum - 1) * limitNum;
    
    // Build query filter - Show all videos (remove processing status restriction)
    const queryFilter = {};
    
    // Add videoType filter if specified
    if (videoType && (videoType === 'yog' || videoType === 'sneha')) {
      queryFilter.videoType = videoType;
      console.log('📹 Filtering by videoType:', videoType);
    }
    
    // Debug: Log the query filter
    console.log('🔍 VideoRoutes: Query filter:', JSON.stringify(queryFilter));
    
    // MODIFIED: Return all videos with optional videoType filter
    const [totalVideos, videos] = await Promise.all([
      Video.countDocuments(queryFilter), // Count with filter
      Video.find(queryFilter) // Find with filter
        .select('videoName videoUrl thumbnailUrl likes views shares uploader uploadedAt likedBy videoType aspectRatio duration comments link description hlsMasterPlaylistUrl hlsPlaylistUrl isHLSEncoded') // Include HLS fields
        .populate('uploader', 'name profilePic googleId')
        .populate('comments.user', 'name profilePic googleId')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean()
    ]);

    console.log('📹 Total videos found:', totalVideos);
    console.log('📹 Videos returned:', videos.length);
    
    // Debug: Log first few video details
    if (videos.length > 0) {
      console.log('📹 First video details:', {
        id: videos[0]._id,
        name: videos[0].videoName,
        status: videos[0].processingStatus,
        type: videos[0].videoType
      });
    } else {
      console.log('❌ No videos found in database!');
    }

    // Transform comments to match Flutter app expectations
    const transformedVideos = videos.map(video => ({
      ...video,
      comments: video.comments.map(comment => ({
        _id: comment._id,
        text: comment.text,
        userId: comment.user?.googleId || comment.user?._id || '',
        userName: comment.user?.name || '',
        createdAt: comment.createdAt,
        likes: comment.likes || 0,
        likedBy: comment.likedBy || []
      }))
    }));
    
    console.log(`✅ Found ${videos.length} videos (page ${page}, total: ${totalVideos})`);
    
    res.json({
      videos: transformedVideos,
      hasMore: (pageNum * limitNum) < totalVideos,
      total: totalVideos,
      currentPage: pageNum,
      totalPages: Math.ceil(totalVideos / limitNum),
      filters: {
        videoType: videoType || 'all',
        format: 'mp4_and_hls'
      },
      message: `✅ Fetched ${videos.length} videos successfully${videoType ? ` (${videoType} type)` : ''}`
    });
  } catch (error) {
    console.error('❌ Error fetching videos:', error);
    res.status(500).json({ 
      error: 'Failed to fetch videos',
      message: error.message 
    });
  }
});

// GET /api/videos/:id - Get video by ID for processing status checking
router.get('/:id', verifyToken, async (req, res) => {
  try {
    const videoId = req.params.id;
    console.log('📹 Getting video by ID:', videoId);

    const video = await Video.findById(videoId)
      .populate('uploader', 'name profilePic googleId')
      .populate('comments.user', 'name profilePic googleId');

    if (!video) {
      console.log('❌ Video not found with ID:', videoId);
      return res.status(404).json({ error: 'Video not found' });
    }

    // Transform video data to match frontend expectations
    const videoObj = video.toObject();
    const transformedVideo = {
      _id: videoObj._id?.toString(),
      videoName: videoObj.videoName || 'Untitled Video',
      videoUrl: videoObj.videoUrl || videoObj.hlsMasterPlaylistUrl || videoObj.hlsPlaylistUrl || '',
      thumbnailUrl: videoObj.thumbnailUrl || '',
      description: videoObj.description || '',
      likes: parseInt(videoObj.likes) || 0,
      views: parseInt(videoObj.views) || 0,
      shares: parseInt(videoObj.shares) || 0,
      duration: parseInt(videoObj.duration) || 0,
      aspectRatio: parseFloat(videoObj.aspectRatio) || 9/16,
      videoType: videoObj.videoType || 'yog',
      link: videoObj.link || null,
      uploadedAt: videoObj.uploadedAt?.toISOString?.() || new Date().toISOString(),
      createdAt: videoObj.createdAt?.toISOString?.() || new Date().toISOString(),
      updatedAt: videoObj.updatedAt?.toISOString?.() || new Date().toISOString(),
      // **CRITICAL: Processing status fields**
      processingStatus: videoObj.processingStatus || 'pending',
      processingProgress: videoObj.processingProgress || 0,
      processingError: videoObj.processingError || null,
      // Uploader information
      uploader: {
        id: videoObj.uploader?._id?.toString() || videoObj.uploader?.toString(),
        name: videoObj.uploader?.name || 'Unknown User',
        profilePic: videoObj.uploader?.profilePic || '',
        googleId: videoObj.uploader?.googleId || ''
      },
      // HLS Streaming fields
      hlsMasterPlaylistUrl: videoObj.hlsMasterPlaylistUrl || null,
      hlsPlaylistUrl: videoObj.hlsPlaylistUrl || null,
      isHLSEncoded: videoObj.isHLSEncoded || false,
      likedBy: videoObj.likedBy || [],
      comments: videoObj.comments.map(comment => ({
        _id: comment._id,
        text: comment.text,
        userId: comment.user?.googleId || comment.user?._id || '',
        userName: comment.user?.name || '',
        createdAt: comment.createdAt,
        likes: comment.likes || 0,
        likedBy: comment.likedBy || []
      }))
    };

    console.log('✅ Video retrieved:', {
      id: transformedVideo._id,
      name: transformedVideo.videoName,
      processingStatus: transformedVideo.processingStatus,
      processingProgress: transformedVideo.processingProgress
    });

    res.json(transformedVideo);
  } catch (error) {
    console.error('❌ Error getting video by ID:', error);
    res.status(500).json({ 
      error: 'Failed to get video',
      details: error.message 
    });
  }
});

// POST /api/videos/:id/like - Toggle like for a video (must be before /:id route)
router.post('/:id/like', verifyToken, async (req, res) => {
  try {
    // Get Google ID from token and resolve to User ObjectId
    const googleId = req.user.googleId; // From verifyToken middleware
    const videoId = req.params.id;

    console.log('🔍 Like API: Received request', { googleId, videoId });

    // Validate input
    if (!googleId) {
      console.log('❌ Like API: Missing userId from authentication');
      return res.status(400).json({ error: 'User not authenticated' });
    }

    if (!videoId) {
      console.log('❌ Like API: Missing videoId in params');
      return res.status(400).json({ error: 'Video ID is required' });
    }

    // Resolve the authenticated user to a DB record to get ObjectId
    const user = await User.findOne({ googleId });
    if (!user) {
      console.log('❌ Like API: User not found for googleId:', googleId);
      return res.status(404).json({ error: 'User not found' });
    }
    const userObjectId = user._id; // Mongoose ObjectId

    // Find the video
    const video = await Video.findById(videoId);
    if (!video) {
      console.log('❌ Like API: Video not found with ID:', videoId);
      return res.status(404).json({ error: 'Video not found' });
    }

    console.log('🔍 Like API: Video found, current likes:', video.likes, 'likedBy:', video.likedBy);

    // Check if user has already liked the video
    const likedByStrings = (video.likedBy || []).map(id => id?.toString?.() || String(id));
    const userLikedIndex = likedByStrings.indexOf(userObjectId.toString());
    let wasLiked = false;
    
    if (userLikedIndex > -1) {
      // User has already liked - remove the like
      video.likedBy.splice(userLikedIndex, 1);
      video.likes = Math.max(0, video.likes - 1); // Decrement likes, ensure not negative
      wasLiked = false;
      console.log('🔍 Like API: Removed like, new count:', video.likes);
    } else {
      // User hasn't liked - add the like
      video.likedBy.push(userObjectId);
      video.likes = video.likes + 1; // Increment likes
      wasLiked = true;
      console.log('🔍 Like API: Added like, new count:', video.likes);
    }

    await video.save();
    console.log('✅ Like API: Video saved successfully');

    // Return the updated video with populated fields
    const updatedVideo = await Video.findById(videoId)
      .populate('uploader', 'name profilePic googleId')
      .populate('comments.user', 'name profilePic googleId');

    // Transform comments to match Flutter app expectations
    const videoObj = updatedVideo.toObject();
    
    // **FIXED: Only send fields that frontend VideoModel expects**
    const transformedVideo = {
      _id: videoObj._id?.toString(),
      videoName: videoObj.videoName || '',
      videoUrl: videoObj.videoUrl || videoObj.hlsMasterPlaylistUrl || videoObj.hlsPlaylistUrl || '',
      thumbnailUrl: videoObj.thumbnailUrl || '',
      likes: parseInt(videoObj.likes) || 0,
      views: parseInt(videoObj.views) || 0,
      shares: parseInt(videoObj.shares) || 0,
      description: videoObj.description || '',
      uploader: {
        _id: videoObj.uploader?._id?.toString() || videoObj.uploader?.googleId?.toString() || '',
        name: videoObj.uploader?.name || 'Unknown',
        profilePic: videoObj.uploader?.profilePic || '',
      },
      uploadedAt: videoObj.uploadedAt?.toISOString?.() || new Date().toISOString(),
      likedBy: videoObj.likedBy || [],
      videoType: videoObj.videoType || 'reel',
      aspectRatio: parseFloat(videoObj.aspectRatio) || 9/16,
      duration: parseInt(videoObj.duration) || 0,
      comments: videoObj.comments.map(comment => ({
        _id: comment._id,
        text: comment.text,
        userId: comment.user?.googleId || comment.user?._id || '',
        userName: comment.user?.name || '',
        createdAt: comment.createdAt,
        likes: comment.likes || 0,
        likedBy: comment.likedBy || []
      })),
      link: videoObj.link || null,
      hlsMasterPlaylistUrl: videoObj.hlsMasterPlaylistUrl || null,
      hlsPlaylistUrl: videoObj.hlsPlaylistUrl || null,
      hlsVariants: videoObj.hlsVariants || null,
      isHLSEncoded: videoObj.isHLSEncoded || false,
      lowQualityUrl: videoObj.lowQualityUrl || null,
      mediumQualityUrl: videoObj.mediumQualityUrl || null,
      highQualityUrl: videoObj.highQualityUrl || null,
      preloadQualityUrl: videoObj.preloadQualityUrl || null,
    };

    res.json(transformedVideo);
    
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

// DELETE /api/videos/:id/like - Unlike a video (for API consistency)
router.delete('/:id/like', verifyToken, async (req, res) => {
  try {
    // Get Google ID from token and resolve to User ObjectId
    const googleId = req.user.googleId; // From verifyToken middleware
    const videoId = req.params.id;

    console.log('🔍 Unlike API: Received request', { googleId, videoId });

    // Validate input
    if (!googleId) {
      console.log('❌ Unlike API: No Google ID in token');
      return res.status(401).json({ error: 'Authentication required' });
    }

    if (!videoId) {
      console.log('❌ Unlike API: No video ID provided');
      return res.status(400).json({ error: 'Video ID is required' });
    }

    // Find user by Google ID
    const user = await User.findOne({ googleId: googleId });
    if (!user) {
      console.log('❌ Unlike API: User not found with Google ID:', googleId);
      return res.status(404).json({ error: 'User not found' });
    }

    const userObjectId = user._id;
    console.log('🔍 Unlike API: User ObjectId:', userObjectId);

    // Find the video
    const video = await Video.findById(videoId);
    if (!video) {
      console.log('❌ Unlike API: Video not found with ID:', videoId);
      return res.status(404).json({ error: 'Video not found' });
    }

    console.log('🔍 Unlike API: Video found, current likes:', video.likes, 'likedBy:', video.likedBy);

    // Check if user has liked the video
    const likedByStrings = (video.likedBy || []).map(id => id?.toString?.() || String(id));
    const userLikedIndex = likedByStrings.indexOf(userObjectId.toString());
    
    if (userLikedIndex > -1) {
      // User has liked - remove the like
      video.likedBy.splice(userLikedIndex, 1);
      video.likes = Math.max(0, video.likes - 1); // Decrement likes, ensure not negative
      console.log('🔍 Unlike API: Removed like, new count:', video.likes);
    } else {
      // User hasn't liked - return current state
      console.log('🔍 Unlike API: User has not liked this video');
    }

    await video.save();
    console.log('✅ Unlike API: Video saved successfully');

    // Return the updated video with populated fields
    const updatedVideo = await Video.findById(videoId)
      .populate('uploader', 'name profilePic googleId')
      .populate('comments.user', 'name profilePic googleId');

    if (!updatedVideo) {
      return res.status(404).json({ error: 'Video not found after update' });
    }

    const videoObj = updatedVideo.toObject();
    const transformedVideo = {
      _id: videoObj._id?.toString(),
      videoName: videoObj.videoName || '',
      videoUrl: videoObj.videoUrl || videoObj.hlsMasterPlaylistUrl || videoObj.hlsPlaylistUrl || '',
      thumbnailUrl: videoObj.thumbnailUrl || '',
      likes: parseInt(videoObj.likes) || 0,
      views: parseInt(videoObj.views) || 0,
      shares: parseInt(videoObj.shares) || 0,
      description: videoObj.description || '',
      uploader: {
        _id: videoObj.uploader?._id?.toString() || videoObj.uploader?.googleId?.toString() || '',
        name: videoObj.uploader?.name || 'Unknown',
        profilePic: videoObj.uploader?.profilePic || '',
      },
      uploadedAt: videoObj.uploadedAt?.toISOString?.() || new Date().toISOString(),
      likedBy: videoObj.likedBy || [],
      videoType: videoObj.videoType || 'reel',
      aspectRatio: parseFloat(videoObj.aspectRatio) || 9/16,
      duration: parseInt(videoObj.duration) || 0,
      comments: videoObj.comments.map(comment => ({
        _id: comment._id,
        text: comment.text,
        userId: comment.user?.googleId || comment.user?._id || '',
        userName: comment.user?.name || '',
        createdAt: comment.createdAt,
        likes: comment.likes || 0,
        likedBy: comment.likedBy || []
      })),
      hlsMasterPlaylistUrl: videoObj.hlsMasterPlaylistUrl || null,
      hlsPlaylistUrl: videoObj.hlsPlaylistUrl || null,
      isHLSEncoded: videoObj.isHLSEncoded || false,
      lowQualityUrl: videoObj.lowQualityUrl || null,
      mediumQualityUrl: videoObj.mediumQualityUrl || null,
      highQualityUrl: videoObj.highQualityUrl || null,
      preloadQualityUrl: videoObj.preloadQualityUrl || null,
    };

    res.json(transformedVideo);
    
    console.log('✅ Unlike API: Successfully unliked video');
    
  } catch (err) {
    console.error('❌ Unlike API Error:', err);
    res.status(500).json({ 
      error: 'Failed to unlike video', 
      details: err.message,
      stack: process.env.NODE_ENV === 'development' ? err.stack : undefined
    });
  }
});

// Get video by ID
router.get('/:id', async (req, res) => {
  try {
    const video = await Video.findById(req.params.id)
      .populate('uploader', 'name profilePic googleId')
      .populate('comments.user', 'name profilePic googleId');

    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    // **FIXED: Ensure consistent data types and HLS URL handling**
    const videoObj = video.toObject();
    const formattedVideo = {
      ...videoObj,
      // **FIXED: Ensure numeric fields are numbers**
      likes: parseInt(videoObj.likes) || 0,
      views: parseInt(videoObj.views) || 0,
      shares: parseInt(videoObj.shares) || 0,
      duration: parseInt(videoObj.duration) || 0,
      aspectRatio: parseFloat(videoObj.aspectRatio) || 9/16,
      // **FIXED: Ensure ObjectId fields are properly formatted**
      _id: videoObj._id?.toString() || videoObj._id,
      uploader: videoObj.uploader?._id?.toString() || videoObj.uploader?.toString() || videoObj.uploader,
      // **FIXED: Ensure date fields are properly formatted**
      uploadedAt: videoObj.uploadedAt?.toISOString?.() || videoObj.uploadedAt,
      createdAt: videoObj.createdAt?.toISOString?.() || videoObj.createdAt,
      updatedAt: videoObj.updatedAt?.toISOString?.() || videoObj.updatedAt,
      // **FIXED: Ensure HLS URLs are properly set**
      videoUrl: videoObj.videoUrl || videoObj.hlsMasterPlaylistUrl || videoObj.hlsPlaylistUrl || '',
      hlsMasterPlaylistUrl: videoObj.hlsMasterPlaylistUrl || null,
      hlsPlaylistUrl: videoObj.hlsPlaylistUrl || null,
      isHLSEncoded: videoObj.isHLSEncoded || false,
      // **FIXED: Transform comments to match Flutter app expectations**
      comments: videoObj.comments.map(comment => ({
        _id: comment._id,
        text: comment.text,
        userId: comment.user?.googleId || comment.user?._id || '',
        userName: comment.user?.name || '',
        createdAt: comment.createdAt,
        likes: comment.likes || 0,
        likedBy: comment.likedBy || []
      }))
    };

    console.log('🎬 Get Video by ID - Data types fixed:', {
      videoId: formattedVideo._id,
      videoName: formattedVideo.videoName,
      dataTypes: {
        likes: typeof formattedVideo.likes,
        views: typeof formattedVideo.views,
        shares: typeof formattedVideo.shares,
        duration: typeof formattedVideo.duration,
        aspectRatio: typeof formattedVideo.aspectRatio
      },
      hlsInfo: {
        hasHlsMaster: !!formattedVideo.hlsMasterPlaylistUrl,
        hasHlsPlaylist: !!formattedVideo.hlsPlaylistUrl,
        isHlsEncoded: formattedVideo.isHLSEncoded,
        finalVideoUrl: formattedVideo.videoUrl
      }
    });

    res.json(formattedVideo);
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
    ).populate('comments.user', 'name profilePic googleId');

    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    // Transform comments to match Flutter app expectations
    const videoObj = video.toObject();
    const transformedVideo = {
      ...videoObj,
      comments: videoObj.comments.map(comment => ({
        _id: comment._id,
        text: comment.text,
        userId: comment.user?.googleId || comment.user?._id || '',
        userName: comment.user?.name || '',
        createdAt: comment.createdAt,
        likes: comment.likes || 0,
        likedBy: comment.likedBy || []
      }))
    };

    res.json({
      message: 'Comment added successfully',
      video: transformedVideo
    });
  } catch (err) {
    console.error('Error adding comment:', err);
    res.status(500).json({ error: 'Failed to add comment', details: err.message });
  }
});

// **NEW: Increment video view count (Instagram Reels style)**
router.post('/:id/increment-view', async (req, res) => {
  try {
    const videoId = req.params.id;
    const { userId, duration = 4 } = req.body;

    console.log('🎯 View increment request:', {
      videoId,
      userId,
      duration,
      timestamp: new Date().toISOString()
    });

    // Validate video ID
    if (!videoId || !mongoose.Types.ObjectId.isValid(videoId)) {
      return res.status(400).json({ error: 'Invalid video ID' });
    }

    // Find user by googleId
    const user = await User.findOne({ googleId: userId });
    if (!user) {
      console.log('❌ User not found with Google ID:', userId);
      return res.status(404).json({ error: 'User not found' });
    }

    // Find video
    const video = await Video.findById(videoId);
    if (!video) {
      console.log('❌ Video not found:', videoId);
      return res.status(404).json({ error: 'Video not found' });
    }

    // Check if user has already reached max views (10)
    const existingView = video.viewDetails.find(view => 
      view.user.toString() === user._id.toString()
    );

    if (existingView && existingView.viewCount >= 10) {
      console.log('⚠️ User has reached maximum view count:', {
        userId: user.googleId,
        currentViewCount: existingView.viewCount
      });
      return res.status(200).json({
        message: 'View limit reached',
        viewCount: existingView.viewCount,
        maxViewsReached: true,
        totalViews: video.views
      });
    }

    // Increment view using the model method
    await video.incrementView(user._id, duration);

    console.log('✅ View incremented successfully:', {
      videoId,
      userId: user.googleId,
      newTotalViews: video.views,
      userViewCount: existingView ? existingView.viewCount + 1 : 1
    });

    // Return updated view count
    const updatedExistingView = video.viewDetails.find(view => 
      view.user.toString() === user._id.toString()
    );

    res.json({
      message: 'View incremented successfully',
      totalViews: video.views,
      userViewCount: updatedExistingView ? updatedExistingView.viewCount : 1,
      maxViewsReached: updatedExistingView ? updatedExistingView.viewCount >= 10 : false
    });

  } catch (err) {
    console.error('❌ Error incrementing view:', err);
    res.status(500).json({ 
      error: 'Failed to increment view', 
      details: err.message 
    });
  }
});

// Delete video by ID
router.delete('/:id', verifyToken, async (req, res) => {
  try {
    console.log('🗑️ DELETE VIDEO ROUTE CALLED');
    console.log('🗑️ Video ID:', req.params.id);
    console.log('🗑️ User from token:', req.user);
    console.log('🗑️ User ID type:', req.user.id.runtimeType);
    console.log('🗑️ User ID value:', req.user.id);
    
    const videoId = req.params.id;
    
    // Get video to check ownership
    const video = await Video.findById(videoId);
    if (!video) {
      console.log('❌ Video not found:', videoId);
      return res.status(404).json({ error: 'Video not found' });
    }

    console.log('🗑️ Video found:', {
      id: video._id,
      uploader: video.uploader,
      uploaderType: video.uploader.runtimeType,
      uploaderString: video.uploader.toString()
    });

    // Get user from database to compare ObjectIds
    const user = await User.findOne({ googleId: req.user.googleId });
    if (!user) {
      console.log('❌ User not found with Google ID:', req.user.googleId);
      return res.status(401).json({ error: 'User not found' });
    }

    console.log('🗑️ Comparing user IDs:');
    console.log('   Token User ID:', user._id.toString());
    console.log('   Video uploader:', video.uploader.toString());
    console.log('   Are they equal?', video.uploader.toString() === user._id.toString());

    // Check if user owns the video by comparing ObjectIds
    if (video.uploader.toString() !== user._id.toString()) {
      console.log('❌ Permission denied - user does not own video');
      console.log('   User ID from database:', user._id.toString());
      console.log('   Video uploader ID:', video.uploader.toString());
      return res.status(403).json({ error: 'You can only delete your own videos' });
    }

    // Delete the video
    const deletedVideo = await Video.findByIdAndDelete(videoId);
    if (!deletedVideo) {
      return res.status(404).json({ error: 'Video not found' });
    }

    console.log(`🗑️ Video deleted: ${videoId} by user: ${user._id}`);
    res.json({ success: true, message: 'Video deleted successfully' });
  } catch (error) {
    console.error('❌ Delete video error:', error);
    res.status(500).json({ error: 'Failed to delete video' });
  }
});

// Bulk delete videos
router.post('/bulk-delete', verifyToken, async (req, res) => {
  try {
    const { videoIds, deleteReason, timestamp } = req.body;
    
    // Get user from database to compare ObjectIds
    const user = await User.findOne({ googleId: req.user.googleId });
    if (!user) {
      return res.status(401).json({ error: 'User not found' });
    }

    // Validate request
    if (!videoIds || !Array.isArray(videoIds) || videoIds.length === 0) {
      return res.status(400).json({ error: 'Video IDs are required' });
    }

    console.log(`🗑️ Bulk delete requested: ${videoIds.length} videos by user: ${user._id}`);

    // Find all videos and check ownership
    const videos = await Video.find({ _id: { $in: videoIds } });
    
    if (videos.length === 0) {
      return res.status(404).json({ error: 'No videos found' });
    }

    // Check if user owns all videos by comparing ObjectIds
    const unauthorizedVideos = videos.filter(video => 
      video.uploader.toString() !== user._id.toString()
    );

    if (unauthorizedVideos.length > 0) {
      return res.status(403).json({ 
        error: 'You can only delete your own videos',
        unauthorizedVideos: unauthorizedVideos.map(v => v._id)
      });
    }

    // Delete all videos
    const deleteResult = await Video.deleteMany({ _id: { $in: videoIds } });
    
    console.log(`✅ Bulk delete successful: ${deleteResult.deletedCount} videos deleted`);
    
    res.json({ 
      success: true, 
      message: `${deleteResult.deletedCount} videos deleted successfully`,
      deletedCount: deleteResult.deletedCount
    });

  } catch (error) {
    console.error('❌ Bulk delete error:', error);
    res.status(500).json({ error: 'Failed to delete videos' });
  }
});



// Generate signed Cloudinary URLs for HLS streams
// (Removed duplicate generate-signed-url route defined earlier)

// New video upload endpoint with HLS conversion
// Removed self-hosted HLS upload endpoint

// Serve HLS files
// Removed duplicate local HLS static route

// Generate HLS URL (replaces Cloudinary signed URL)
// Removed self-hosted HLS URL generator

// Clean up temporary HLS directories
router.post('/cleanup-temp-hls', async (req, res) => {
  try {
    const hlsService = (await import('../services/hlsEncodingService.js')).default;
    await hlsService.cleanupTempHLSDirectories();
    res.json({ success: true, message: 'Temporary HLS directories cleaned up' });
  } catch (error) {
    console.error('❌ Error cleaning up temporary HLS directories:', error);
    res.status(500).json({ error: 'Failed to clean up temporary directories' });
  }
});

// Update existing generate-signed-url to use HLS
router.post('/generate-signed-url', verifyToken, async (req, res) => {
  try {
    const { videoUrl, quality = 'hd' } = req.body;

    if (!videoUrl) {
      return res.status(400).json({ success: false, error: 'Video URL is required' });
    }

    if (!isCloudinaryConfigured()) {
      return res.status(500).json({ success: false, error: 'Cloudinary not configured' });
    }

    // Expecting a Cloudinary URL; extract public_id after '/upload/' and before extension
    const uploadIdx = videoUrl.indexOf('/upload/');
    if (uploadIdx === -1) {
      return res.status(400).json({ success: false, error: 'Invalid Cloudinary URL' });
    }

    const afterUpload = videoUrl.substring(uploadIdx + '/upload/'.length);
    // Remove any existing transformations prefix (e.g. sp_hd, fl_segment_2, etc.)
    const parts = afterUpload.split('/');
    // If first part contains a dot or comma, it's a transformation, drop it
    let startIndex = 0;
    if (parts[0].includes(',') || parts[0].startsWith('sp_') || parts[0].startsWith('fl_')) {
      startIndex = 1;
    }
    const publicIdWithExt = parts.slice(startIndex).join('/');
    const publicId = publicIdWithExt.replace(/\.m3u8$/i, '');

    // Map quality to transformation parameters (no streaming profiles)
    const qualityParam = quality === 'sd' ? 'q_auto:eco' : 'q_auto:good';

    const signedUrl = cloudinary.url(publicId, {
      resource_type: 'video',
      type: 'upload',
      secure: true,
      sign_url: true,
      format: 'm3u8',
      transformation: [{ quality: qualityParam }],
      cloud_name: process.env.CLOUD_NAME
    });

    return res.json({ success: true, signedUrl });
  } catch (error) {
    console.error('❌ Error generating Cloudinary signed URL:', error);
    return res.status(500).json({ success: false, error: 'Failed to generate signed URL' });
  }
});

// **NEW: Secure endpoint to get Cloudinary config (without secrets)**
router.get('/cloudinary-config', verifyToken, async (req, res) => {
  try {
    // Only return public config, never secrets
    const config = {
      cloudName: process.env.CLOUD_NAME,
      // API key and secret are never sent to frontend for security
      hasCredentials: !!(process.env.CLOUD_KEY && process.env.CLOUD_SECRET),
    };
    
    res.json({ 
      success: true, 
      config: config,
      message: 'Cloudinary config retrieved successfully'
    });
  } catch (error) {
    console.error('❌ Error getting Cloudinary config:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to get Cloudinary config' 
    });
  }
});



// Get user's videos by user ID
router.get('/user/:userId', verifyToken, async (req, res) => {
  try {
    const { userId } = req.params;
    console.log('🔍 Getting videos for user:', userId);
    
    // Find user by Google ID first, then by MongoDB ObjectId
    let user = await User.findOne({ googleId: userId });
    if (!user) {
      try {
        user = await User.findById(userId);
      } catch (e) {
        // ignore invalid ObjectId errors
      }
    }
    
    if (!user) {
      console.log('❌ User not found:', userId);
      return res.status(404).json({ error: 'User not found' });
    }
    
    console.log('✅ User found:', user.name);
    
    // Get user's videos with population
    const videos = await Video.find({ uploader: user._id })
      .select('videoName videoUrl thumbnailUrl likes views shares uploader uploadedAt likedBy videoType aspectRatio duration comments link description hlsMasterPlaylistUrl hlsPlaylistUrl isHLSEncoded')
      .populate('uploader', 'name profilePic googleId')
      .populate('comments.user', 'name profilePic googleId')
      .sort({ createdAt: -1 })
      .lean();
    
    console.log('🎬 Found videos count:', videos.length);
    if (videos.length === 0) {
      console.log('⚠️ No videos found for user:', user.name);
    }

    // Transform videos to match frontend expectations
    const transformedVideos = videos.map(video => {
      const videoObj = video;
      const result = {
        _id: videoObj._id?.toString(),
        videoName: videoObj.videoName || 'Untitled Video',
        videoUrl: videoObj.videoUrl || videoObj.hlsMasterPlaylistUrl || videoObj.hlsPlaylistUrl || '',
        thumbnailUrl: videoObj.thumbnailUrl || '',
        description: videoObj.description || '',
        likes: parseInt(videoObj.likes) || 0,
        views: parseInt(videoObj.views) || 0,
        shares: parseInt(videoObj.shares) || 0,
        duration: parseInt(videoObj.duration) || 0,
        aspectRatio: parseFloat(videoObj.aspectRatio) || 9/16,
        videoType: videoObj.videoType || 'yog',
        link: videoObj.link || null,
        uploadedAt: videoObj.uploadedAt?.toISOString?.() || new Date().toISOString(),
        createdAt: videoObj.createdAt?.toISOString?.() || new Date().toISOString(),
        updatedAt: videoObj.updatedAt?.toISOString?.() || new Date().toISOString(),
        uploader: {
          id: videoObj.uploader?._id?.toString() || videoObj.uploader?.toString(),
          name: videoObj.uploader?.name || 'Unknown User',
          profilePic: videoObj.uploader?.profilePic || '',
          googleId: videoObj.uploader?.googleId || ''
        },
        hlsMasterPlaylistUrl: videoObj.hlsMasterPlaylistUrl || null,
        hlsPlaylistUrl: videoObj.hlsPlaylistUrl || null,
        isHLSEncoded: videoObj.isHLSEncoded || false,
        likedBy: videoObj.likedBy || [],
        comments: videoObj.comments || []
      };
      
      console.log(`🎬 Video ${result.videoName}:`, {
        id: result._id,
        hasVideoUrl: !!result.videoUrl,
        hasThumbnail: !!result.thumbnailUrl,
        likes: result.likes,
        views: result.views,
        uploader: result.uploader.name,
        uploaderGoogleId: result.uploader.googleId
      });
      
      return result;
    });

    console.log('✅ Sending user videos response:', {
      totalVideos: transformedVideos.length,
      firstVideo: transformedVideos.length > 0 ? transformedVideos[0].videoName : 'None'
    });

    res.json(transformedVideos);
  } catch (error) {
    console.error('❌ Error fetching user videos:', error);
    res.status(500).json({ 
      error: 'Error fetching videos',
      details: error.message 
    });
  }
});

export default router
