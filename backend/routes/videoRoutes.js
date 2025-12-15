import express from 'express';
import multer from 'multer';
import mongoose from 'mongoose';
import Video from '../models/Video.js';
import User from '../models/User.js';
import Comment from '../models/Comment.js';
import WatchHistory from '../models/WatchHistory.js';
import fs from 'fs'; 
import path from 'path';
import crypto from 'crypto';
import { verifyToken } from '../utils/verifytoken.js';
import redisService from '../services/redisService.js';
import { VideoCacheKeys, invalidateCache } from '../middleware/cacheMiddleware.js';
import RecommendationService from '../services/recommendationService.js';
// Lazy import to ensure env vars are loaded first
let hybridVideoService;
const router = express.Router();


const videoCachingMiddleware = (req, res, next) => {
  // Default to no-store for API JSON responses served from this router.
  res.setHeader('Cache-Control', 'no-store');
  res.removeHeader('ETag');
  next();
};

// Apply response header middleware to all video routes
router.use(videoCachingMiddleware);

// **NEW: Helper function to calculate video file hash for duplicate detection**
async function calculateVideoHash(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('sha256');
    const stream = fs.createReadStream(filePath);
    
    stream.on('data', (data) => hash.update(data));
    stream.on('end', () => resolve(hash.digest('hex')));
    stream.on('error', (err) => reject(err));
  });
}

// **HELPER: Convert likedBy ObjectIds to googleIds for frontend compatibility**
async function convertLikedByToGoogleIds(likedByArray) {
  if (!Array.isArray(likedByArray) || likedByArray.length === 0) {
    return [];
  }
  
  try {
    // Batch query all users at once for efficiency
    const users = await User.find({
      _id: { $in: likedByArray }
    }).select('googleId').lean();
    
    // Create a map of ObjectId -> googleId
    const idMap = new Map();
    users.forEach(user => {
      if (user.googleId) {
        idMap.set(user._id.toString(), user.googleId.toString());
      }
    });
    
    // Convert ObjectIds to googleIds, filter out any that don't have googleId
    return likedByArray
      .map(id => {
        const idStr = id?.toString?.() || String(id);
        return idMap.get(idStr) || null;
      })
      .filter(Boolean); // Remove nulls
  } catch (error) {
    console.error('❌ Error converting likedBy to googleIds:', error);
    // Fallback: return empty array or original IDs as strings
    return likedByArray.map(id => id?.toString?.() || String(id));
  }
}


// DEBUG: Check database status - MUST BE FIRST ROUTE
router.get('/debug-database', async (req, res) => {
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
    
    // **NEW: Count videos by videoType**
    const videoTypeStats = await Video.aggregate([
      {
        $group: {
          _id: '$videoType',
          count: { $sum: 1 }
        }
      },
      {
        $sort: { count: -1 }
      }
    ]);
    console.log('🔍 DEBUG: Videos by videoType:', JSON.stringify(videoTypeStats, null, 2));
    
    // Count videos with null/undefined videoType
    const nullVideoTypeCount = await Video.countDocuments({
      $or: [
        { videoType: null },
        { videoType: { $exists: false } }
      ]
    });
    if (nullVideoTypeCount > 0) {
      console.log(`🔍 DEBUG: Videos with null/undefined videoType: ${nullVideoTypeCount}`);
    }
    
    // Count completed videos by videoType (videos that can be shown)
    const completedVideoTypeStats = await Video.aggregate([
      {
        $match: {
          processingStatus: 'completed',
          videoUrl: { 
            $exists: true, 
            $ne: null, 
            $ne: '',
            $not: /^uploads[\\\/]/,
            $regex: /^https?:\/\//
          }
        }
      },
      {
        $group: {
          _id: '$videoType',
          count: { $sum: 1 }
        }
      },
      {
        $sort: { count: -1 }
      }
    ]);
    console.log('🔍 DEBUG: Completed videos by videoType (showable):', JSON.stringify(completedVideoTypeStats, null, 2));
    
    // Get sample videos with detailed URL information
    const sampleVideos = await Video.find({})
      .select('videoName uploader createdAt processingStatus videoType videoUrl thumbnailUrl hlsPlaylistUrl hlsMasterPlaylistUrl isHLSEncoded')
      .populate('uploader', 'googleId name')
      .limit(5)
      .lean();
    
    console.log('🔍 DEBUG: Sample videos:', sampleVideos);
    
    // **NEW: Check for broken video URLs**
    const brokenVideos = await Video.find({
      $or: [
        { videoUrl: { $exists: false } },
        { videoUrl: null },
        { videoUrl: '' },
        { videoUrl: { $regex: /^uploads[\\\/]/ } }, // Local file paths
        { processingStatus: 'failed' },
        { processingStatus: 'error' }
      ]
    }).select('videoName videoUrl processingStatus processingError').lean();
    
    console.log('🔍 DEBUG: Broken videos found:', brokenVideos.length);
    
    res.json({
      totalVideos,
      statusCounts,
      userCounts,
      videoTypeStats,
      nullVideoTypeCount,
      completedVideoTypeStats,
      sampleVideos,
      brokenVideos,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('❌ DEBUG: Database check failed:', error);
    res.status(500).json({ error: error.message });
  }
});

// **NEW: Cache Management Endpoints**
// GET /api/videos/cache/status - Check cache status
router.get('/cache/status', async (req, res) => {
  try {
    const { userId, deviceId, videoType } = req.query;
    
    if (!redisService.getConnectionStatus()) {
      return res.json({
        redisConnected: false,
        message: 'Redis is not connected',
        cacheKeys: []
      });
    }

    const userIdentifier = userId || deviceId;
    const cachePatterns = {
      unwatchedIds: userIdentifier 
        ? `videos:unwatched:ids:${userIdentifier}:${videoType || 'all'}`
        : null,
      feed: `videos:feed:${videoType || 'all'}`,
      allVideos: 'videos:*',
      allUnwatched: 'videos:unwatched:ids:*'
    };

    const cacheStatus = {};
    
    // Check each cache key
    for (const [name, pattern] of Object.entries(cachePatterns)) {
      if (!pattern) continue;
      
      try {
        // Get all keys matching pattern
        const keys = await redisService.client.keys(pattern);
        const keysWithTTL = await Promise.all(
          keys.map(async (key) => {
            const ttl = await redisService.ttl(key);
            const exists = await redisService.exists(key);
            return {
              key,
              exists,
              ttl: ttl > 0 ? `${ttl} seconds` : ttl === -1 ? 'No expiry' : 'Expired',
              ttlSeconds: ttl
            };
          })
        );
        
        cacheStatus[name] = {
          pattern,
          keysFound: keys.length,
          keys: keysWithTTL
        };
      } catch (error) {
        cacheStatus[name] = {
          pattern,
          error: error.message
        };
      }
    }

    // Get Redis stats
    const redisStats = await redisService.getStats();

    res.json({
      redisConnected: true,
      redisStats,
      cacheStatus,
      timestamp: new Date().toISOString(),
      message: 'Cache status retrieved successfully'
    });
  } catch (error) {
    console.error('❌ Error checking cache status:', error);
    res.status(500).json({ 
      error: 'Failed to check cache status',
      message: error.message 
    });
  }
});

// POST /api/videos/cache/clear - Clear video cache
router.post('/cache/clear', async (req, res) => {
  try {
    const { pattern, userId, deviceId, videoType, clearAll } = req.body;
    
    if (!redisService.getConnectionStatus()) {
      return res.json({
        success: false,
        message: 'Redis is not connected - cannot clear cache'
      });
    }

    let clearedCount = 0;
    const clearedPatterns = [];

    if (clearAll) {
      // Clear all video-related cache
      const patterns = [
        'videos:*',
        'videos:feed:*',
        'videos:unwatched:ids:*',
        'video:*'
      ];
      
      for (const p of patterns) {
        const count = await redisService.clearPattern(p);
        clearedCount += count;
        if (count > 0) {
          clearedPatterns.push({ pattern: p, keysCleared: count });
        }
      }
    } else if (pattern) {
      // Clear specific pattern
      const count = await redisService.clearPattern(pattern);
      clearedCount += count;
      clearedPatterns.push({ pattern, keysCleared: count });
    } else {
      // Clear based on user/device
      const userIdentifier = userId || deviceId;
      const patterns = [];
      
      if (userIdentifier) {
        patterns.push(`videos:unwatched:ids:${userIdentifier}:*`);
        patterns.push(`videos:feed:user:${userIdentifier}:*`);
      }
      
      if (videoType) {
        patterns.push(`videos:feed:${videoType}`);
        patterns.push(`videos:unwatched:ids:*:${videoType}`);
      }
      
      if (patterns.length === 0) {
        // Default: clear all video cache
        patterns.push('videos:*');
        patterns.push('videos:unwatched:ids:*');
      }
      
      for (const p of patterns) {
        const count = await redisService.clearPattern(p);
        clearedCount += count;
        if (count > 0) {
          clearedPatterns.push({ pattern: p, keysCleared: count });
        }
      }
    }

    res.json({
      success: true,
      message: `Cleared ${clearedCount} cache keys`,
      clearedCount,
      clearedPatterns,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('❌ Error clearing cache:', error);
    res.status(500).json({ 
      error: 'Failed to clear cache',
      message: error.message 
    });
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

// **NEW: POST /api/videos/check-duplicate - Check if video already exists before upload**
router.post('/check-duplicate', verifyToken, async (req, res) => {
  try {
    const { videoHash } = req.body;
    const googleId = req.user.googleId;
    
    if (!videoHash) {
      return res.status(400).json({ error: 'Video hash is required' });
    }

    console.log('🔍 Duplicate check: Checking for video hash:', videoHash);
    console.log('🔍 Duplicate check: User Google ID:', googleId);

    const user = await User.findOne({ googleId });
    if (!user) {
      console.log('❌ Duplicate check: User not found');
      return res.status(404).json({ error: 'User not found' });
    }

    const existingVideo = await Video.findOne({
      uploader: user._id,
      videoHash: videoHash
    });

    if (existingVideo) {
      console.log('⚠️ Duplicate check: Duplicate video found:', existingVideo.videoName);
      return res.json({
        isDuplicate: true,
        existingVideoId: existingVideo._id,
        existingVideoName: existingVideo.videoName,
        message: 'You have already uploaded this video.'
      });
    }

    console.log('✅ Duplicate check: No duplicate found');
    return res.json({ isDuplicate: false });
  } catch (error) {
    console.error('❌ Error checking duplicate:', error);
    res.status(500).json({ error: 'Failed to check duplicate' });
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

    // **NEW: Calculate video hash for duplicate detection**
    console.log('🔍 Upload: Calculating video hash for duplicate detection...');
    let videoHash;
    try {
      videoHash = await calculateVideoHash(req.file.path);
      console.log('✅ Upload: Video hash calculated:', videoHash.substring(0, 16) + '...');
    } catch (hashError) {
      console.error('❌ Upload: Error calculating video hash:', hashError);
      fs.unlinkSync(req.file.path);
      return res.status(500).json({ error: 'Failed to calculate video hash' });
    }

    // **NEW: Check if same video already exists for this user**
    const existingVideo = await Video.findOne({
      uploader: user._id,
      videoHash: videoHash
    });

    if (existingVideo) {
      console.log('⚠️ Upload: Duplicate video detected!');
      console.log('   Existing video:', existingVideo.videoName, '(ID:', existingVideo._id + ')');
      // Delete uploaded file
      fs.unlinkSync(req.file.path);
      return res.status(409).json({
        error: 'Duplicate video detected',
        message: 'You have already uploaded this video.',
        existingVideoId: existingVideo._id,
        existingVideoName: existingVideo.videoName
      });
    }
    console.log('✅ Upload: No duplicate found, proceeding with upload');

    // Video processing uses Cloudflare Stream (FREE transcoding) with HLS fallback
    console.log('✅ Upload: Video processing service ready');

    // **NEW: Use Pure HLS Processing (FFmpeg → R2) for 100% FREE processing**
    console.log('🚀 Starting Pure HLS Video Processing (FFmpeg → R2)...');
    console.log('💰 Expected cost: $0 processing (FREE!) + $0.015/GB/month storage + $0 bandwidth (FREE!)');
    console.log('📹 Format: HLS (HTTP Live Streaming) - Single 480p quality');
    
    // **NEW: Lazy load hybrid service to ensure env vars are loaded**
    if (!hybridVideoService) {
      const { default: service } = await import('../services/hybridVideoService.js');
      hybridVideoService = service;
    }
    
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
    // **FIX: Save original dimensions to preserve aspect ratio**
    const video = new Video({
      videoName: videoName,
      description: description || '',
      link: link || '',
      videoUrl: '', // Will be set after processing - don't store local paths
      thumbnailUrl: '', // Will be generated during processing
      uploader: user._id,
      videoType: videoType || 'yog',
      aspectRatio: (videoValidation.width && videoValidation.height) 
        ? videoValidation.width / videoValidation.height 
        : 9/16, // Default to 9:16 (portrait) if dimensions unavailable
      duration: videoValidation.duration || 0,
      originalResolution: {
        width: videoValidation.width || 0,
        height: videoValidation.height || 0
      },
      processingStatus: 'pending',
      processingProgress: 0,
      isHLSEncoded: false, // Will be updated to true after HLS processing
      videoHash: videoHash, // **NEW: Store video hash for duplicate detection**
      likes: 0, views: 0, shares: 0, likedBy: [], comments: [],
      uploadedAt: new Date()
    });
    
    await video.save();
    user.videos.push(video._id);
    await user.save();
    
    console.log('✅ Video record created with ID:', video._id);
    
    // **NEW: Invalidate cache when new video is uploaded**
    if (redisService.getConnectionStatus()) {
      await invalidateCache([
        'videos:feed:*', // Clear all video feed caches
        `videos:user:${user.googleId}`, // Clear user's video cache
        VideoCacheKeys.all() // Clear all video-related caches
      ]);
      console.log('🧹 Cache invalidated after video upload');
    }
    
    // **NEW: Start video processing in background (non-blocking)**
    processVideoHybrid(video._id, req.file.path, videoName, user._id.toString());
    
    // **NEW: Return immediate response**
    return res.status(201).json({
      success: true,
      message: 'Video upload started. Processing via Cloudflare Stream → R2 (100% FREE transcoding!).',
      video: {
        id: video._id,
        videoName: video.videoName,
        processingStatus: video.processingStatus,
        processingProgress: video.processingProgress,
        estimatedTime: '2-5 minutes',
        format: 'MP4 or HLS (depending on processing method)',
        quality: '480p (single quality)',
        costBreakdown: {
          processing: '$0 (FREE!)',
          storage: '$0.015/GB/month (R2)',
          bandwidth: '$0 (FREE forever!)',
          savings: '100% FREE transcoding'
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
    
    // **NEW: Lazy load hybrid service to ensure env vars are loaded**
    if (!hybridVideoService) {
      const { default: service } = await import('../services/hybridVideoService.js');
      hybridVideoService = service;
    }
    
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
    
    // **FIX: Preserve original aspect ratio and dimensions**
    if (hlsResult.aspectRatio) {
      video.aspectRatio = hlsResult.aspectRatio;
      console.log(`📐 Preserved aspect ratio: ${hlsResult.aspectRatio}`);
    }
    if (hlsResult.width && hlsResult.height) {
      video.originalResolution = {
        width: hlsResult.width,
        height: hlsResult.height
      };
      console.log(`📐 Preserved original dimensions: ${hlsResult.width}x${hlsResult.height}`);
    }
    
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
// **NEW: Redis caching integrated**
router.get('/user/:googleId', verifyToken, async (req, res) => {
  try {
    const { googleId } = req.params;
    console.log('🎬 Fetching videos for googleId:', googleId);

    // **NEW: Generate cache key**
    const cacheKey = VideoCacheKeys.user(googleId);

    // **NEW: Try to get from Redis cache first**
    if (redisService.getConnectionStatus()) {
      const cached = await redisService.get(cacheKey);
      if (cached) {
        console.log(`✅ Cache HIT: ${cacheKey}`);
        return res.json(cached);
      }
      console.log(`❌ Cache MISS: ${cacheKey}`);
    }

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

    // **IMPROVED: Get videos directly from Video collection using uploader field**
    // **UPDATED: Sort by recommendation score (finalScore) instead of createdAt**
    const videos = await Video.find({ 
      uploader: user._id,
      videoUrl: { $exists: true, $ne: null, $ne: '' }, // Ensure video URL exists and is not empty
      processingStatus: { $nin: ['failed', 'error'] } // Only exclude explicitly failed videos
    })
      .populate('uploader', 'name profilePic googleId')
      .sort({ finalScore: -1, createdAt: -1 }); // Sort by recommendation score first, then by creation date

    // **NEW: Filter out videos with invalid uploader references**
    const validVideos = videos.filter(video => {
      return video.uploader && 
             video.uploader._id && 
             video.uploader.name && 
             video.uploader.name.trim() !== '';
    });

    console.log('🎬 Found videos count:', videos.length);
    console.log(`🎬 Valid videos count: ${validVideos.length}`);

    // **NEW: Sync user.videos array with actual valid videos**
    if (validVideos.length !== videos.length) {
      console.log('🔄 Syncing user.videos array with valid videos...');
      const validVideoIds = validVideos.map(v => v._id);
      await User.findByIdAndUpdate(user._id, { 
        $set: { videos: validVideoIds } 
      });
      console.log(`✅ Updated user.videos array: ${videos.length} -> ${validVideos.length} videos`);
    }

    if (validVideos.length === 0) {
      console.log('⚠️ No valid videos found for user:', user.name);
      return res.json([]);
    }

    // **IMPROVED: Better data formatting and validation**
    // **FIX: Convert to async to handle likedBy conversion**
    const videosWithUrls = await Promise.all(validVideos.map(async (video) => {
      const videoObj = video.toObject();
      
      // **CRITICAL: Ensure all required fields are present**
      // **FIX: Normalize video URLs to fix Windows path separator issues**
      const normalizeUrl = (url) => {
        if (!url) return url;
        return url.replace(/\\/g, '/');
      };
      
      // **FIX: Convert likedBy ObjectIds to googleIds**
      const likedByGoogleIds = await convertLikedByToGoogleIds(videoObj.likedBy || []);
      
      const result = {
        _id: videoObj._id?.toString(),
        videoName: (videoObj.videoName && videoObj.videoName.toString().trim()) || 'Untitled Video',
        videoUrl: normalizeUrl(videoObj.videoUrl || videoObj.hlsMasterPlaylistUrl || videoObj.hlsPlaylistUrl || ''),
        thumbnailUrl: normalizeUrl(videoObj.thumbnailUrl || ''),
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
        // **FIX: Use googleId as id for correct profile navigation**
        uploader: {
          id: videoObj.uploader?.googleId?.toString() || videoObj.uploader?._id?.toString() || '',
          _id: videoObj.uploader?._id?.toString() || '',
          googleId: videoObj.uploader?.googleId?.toString() || '',
          name: videoObj.uploader?.name || 'Unknown User',
          profilePic: videoObj.uploader?.profilePic || ''
        },
        // **HLS Streaming fields**
        hlsMasterPlaylistUrl: videoObj.hlsMasterPlaylistUrl || null,
        hlsPlaylistUrl: videoObj.hlsPlaylistUrl || null,
        isHLSEncoded: videoObj.isHLSEncoded || false,
        likedBy: likedByGoogleIds, // **FIXED: Use googleIds instead of ObjectIds**
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
    }));

    console.log('✅ Sending videos response:', {
      totalVideos: videosWithUrls.length,
      firstVideo: videosWithUrls.length > 0 ? videosWithUrls[0].videoName : 'None',
      lastVideo: videosWithUrls.length > 0 ? videosWithUrls[videosWithUrls.length - 1].videoName : 'None'
    });

    // **NEW: Cache the response for 10 minutes (600 seconds)**
    if (redisService.getConnectionStatus()) {
      await redisService.set(cacheKey, videosWithUrls, 600);
      console.log(`✅ Cached user videos: ${cacheKey}`);
    }

    res.json(videosWithUrls);
  } catch (error) {
    console.error('❌ Error fetching user videos:', error);
    res.status(500).json({ 
      error: 'Error fetching videos',
      details: error.message 
    });
  }
});

// Get all videos - SIMPLE feed (latest + light randomness)
// - Only completed & playable videos
// - Optional videoType filter (yog / vayu)
// - Sorted by createdAt DESC, then lightly shuffled within the page
router.get('/', async (req, res) => {
  try {
    console.log('📹 SIMPLE GET /api/videos called');

    const { videoType, page = 1, limit = 10 } = req.query;

    // Pagination params (safe bounds)
    const pageNum = Math.max(1, parseInt(page, 10) || 1);
    const limitNum = Math.min(50, Math.max(1, parseInt(limit, 10) || 10)); // 1..50

    // Base filter: only completed videos with real HTTP/HTTPS URLs
    const filter = {
      uploader: { $exists: true, $ne: null },
      videoUrl: {
        $exists: true,
        $ne: null,
        $ne: '',
        $not: /^uploads[\\\/]/,
        $regex: /^https?:\/\//
      },
      processingStatus: 'completed'
    };

    // Optional videoType filter
    if (videoType) {
      const normalizedType = String(videoType).toLowerCase();
      const normalizedVideoType = normalizedType === 'vayug' ? 'vayu' : normalizedType;

      if (normalizedVideoType === 'yog' || normalizedVideoType === 'vayu') {
        filter.videoType = normalizedVideoType;
        console.log(`📹 Filtering by videoType: ${normalizedVideoType}`);
      } else {
        console.log(`⚠️ Unknown videoType: ${videoType}, showing all videos`);
      }
    }

    const skip = (pageNum - 1) * limitNum;

    // Fetch data + total count in parallel
    const [videos, total] = await Promise.all([
      Video.find(filter)
        .populate('uploader', 'googleId name profileImageUrl')
        .sort({ createdAt: -1 }) // latest first
        .skip(skip)
        .limit(limitNum)
        .lean(),
      Video.countDocuments(filter)
    ]);

    // Light randomness: shuffle only within this page's set
    for (let i = videos.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [videos[i], videos[j]] = [videos[j], videos[i]];
    }

    const hasMore = pageNum * limitNum < total;

    const sanitizedVideos = videos.map(video => ({
      _id: video._id,
      videoName: video.videoName,
      description: video.description || '',
      videoUrl: video.videoUrl,
      thumbnailUrl: video.thumbnailUrl || '',
      videoType: video.videoType || 'yog',
      uploader: video.uploader ? {
        _id: video.uploader._id,
        googleId: video.uploader.googleId,
        name: video.uploader.name,
        profileImageUrl: video.uploader.profileImageUrl || ''
      } : null,
      likes: video.likes || 0,
      views: video.views || 0,
      shares: video.shares || 0,
      createdAt: video.createdAt,
      uploadedAt: video.uploadedAt || video.createdAt,
      duration: video.duration || 0,
      aspectRatio: video.aspectRatio || (9 / 16),
      finalScore: video.finalScore || 0,
      processingStatus: video.processingStatus || 'completed',
      isHLSEncoded: video.isHLSEncoded || false,
      hlsPlaylistUrl: video.hlsPlaylistUrl || video.videoUrl,
      hlsMasterPlaylistUrl: video.hlsMasterPlaylistUrl || '',
      lowQualityUrl: video.lowQualityUrl || video.videoUrl
    }));

    return res.json({
      videos: sanitizedVideos,
      page: pageNum,
      limit: limitNum,
      total,
      hasMore,
      isPersonalized: false
    });
  } catch (error) {
    console.error('❌ SIMPLE /api/videos error:', error);
    return res.status(500).json({
      error: 'Failed to fetch videos',
      details: error.message
    });
  }
});


// Get all videos (optimized for performance) - SUPPORTS MP4 AND HLS
// **NEW: Personalized feed with watch history filtering**
// **NEW: Redis caching integrated for 10x faster response**
// **NOTE: verifyToken is optional - if provided, returns personalized feed; otherwise, regular feed**
router.get('/', async (req, res) => {
  try {
    // **NEW: Log that endpoint was hit**
    console.log('📹 GET /api/videos endpoint called');
    console.log('📹 Request query:', req.query);
    console.log('📹 Request headers:', {
      authorization: req.headers.authorization ? 'Present' : 'Missing',
      'user-agent': req.headers['user-agent']?.substring(0, 50) || 'Unknown',
    });
    
    // Try to get user from token (optional authentication)
    let userId = null;
    try {
      const token = req.headers.authorization?.split(' ')[1];
      if (token) {
        // Try to verify token manually (optional - don't fail if invalid)
        try {
          // Try Google access token first
          const googleResponse = await fetch(`https://www.googleapis.com/oauth2/v2/userinfo?access_token=${token}`);
          if (googleResponse.ok) {
            const userInfo = await googleResponse.json();
            userId = userInfo.id;
            console.log('✅ Google token verified for personalized feed:', userId);
          } else {
            // Try JWT token
            const jwt = (await import('jsonwebtoken')).default;
            const JWT_SECRET = process.env.JWT_SECRET;
            
            // **NEW: Check if JWT_SECRET exists**
            if (!JWT_SECRET) {
              console.log('⚠️ JWT_SECRET not found in environment, skipping JWT verification');
            } else if (JWT_SECRET) {
              try {
                const decoded = jwt.verify(token, JWT_SECRET);
                userId = decoded.id || decoded.googleId;
                console.log('✅ JWT token verified for personalized feed:', userId);
              } catch (jwtError) {
                // **ENHANCED: Log JWT error details for debugging**
                console.log('⚠️ JWT verification failed:', {
                  error: jwtError.message,
                  tokenExpired: jwtError.name === 'TokenExpiredError',
                  invalidSignature: jwtError.message.includes('signature'),
                  jwtSecretExists: !!JWT_SECRET,
                  jwtSecretLength: JWT_SECRET ? JWT_SECRET.length : 0,
                });
                // Token invalid - continue without user (this is OK for optional auth)
                console.log('⚠️ Token verification failed, using regular feed');
              }
            }
          }
        } catch (tokenError) {
          // Token verification failed - continue without personalized feed
          console.log('⚠️ Token verification failed, using regular feed:', tokenError.message);
        }
      } else {
        console.log('ℹ️ No token provided, using regular feed');
      }
    } catch (error) {
      // Error getting token - continue without personalized feed
      console.log('⚠️ Error checking token, using regular feed:', error.message);
    }

    const { videoType, page = 1, limit = 10, deviceId } = req.query;
    
    // **BACKEND-FIRST: Use deviceId for anonymous users, userId for authenticated**
    const userIdentifier = userId || deviceId; // Use userId if authenticated, else deviceId
    const isAuthenticated = !!userId;
    
    // **NEW: Log before proceeding**
    console.log('📹 Fetching videos...', { 
      videoType, 
      page, 
      limit, 
      userId: userId ? 'authenticated' : 'anonymous',
      deviceId: deviceId || 'none',
      userIdentifier: userIdentifier || 'none'
    });
    
    // Get query parameters for pagination
    const pageNum = parseInt(page) || 1;
    const limitNum = parseInt(limit) || 10;
    
    // **IMPROVED: Don't cache shuffled results - cache raw data instead**
    // This ensures different users get different random orders
    // Cache key for unwatched video IDs (not shuffled results)
    const unwatchedCacheKey = userIdentifier
      ? `videos:unwatched:ids:${userIdentifier}:${videoType || 'all'}`
      : null;
    
    // **FIXED: DISABLE CACHE - Always fetch fresh unwatched videos for variety**
    // Cache was causing same videos to appear repeatedly
    // Now we always fetch fresh unwatched videos to ensure variety
    console.log('🔄 Always fetching fresh unwatched videos (cache disabled for variety)');
    
    // Build base query filter
    // **FIXED: Only show completed videos with valid URLs that can actually play**
    const baseQueryFilter = {
      uploader: { $exists: true, $ne: null },
      videoUrl: { 
        $exists: true, 
        $ne: null, 
        $ne: '',
        $not: /^uploads[\\\/]/,
        $regex: /^https?:\/\//
      },
      processingStatus: 'completed' // **FIXED: Only show completed videos that can actually play**
    };
    
    // **DEBUG: Check videoType distribution in database BEFORE filtering**
    try {
      const videoTypeStats = await Video.aggregate([
        {
          $match: {
            uploader: { $exists: true, $ne: null },
            videoUrl: { 
              $exists: true, 
              $ne: null, 
              $ne: '',
              $not: /^uploads[\\\/]/,
              $regex: /^https?:\/\//
            },
            processingStatus: 'completed'
          }
        },
        {
          $group: {
            _id: '$videoType',
            count: { $sum: 1 }
          }
        },
        {
          $sort: { count: -1 }
        }
      ]);
      console.log('📊 Database videoType distribution:', JSON.stringify(videoTypeStats, null, 2));
      
      // Also check null/undefined videoType
      const nullVideoTypeCount = await Video.countDocuments({
        ...baseQueryFilter,
        $or: [
          { videoType: null },
          { videoType: { $exists: false } }
        ]
      });
      if (nullVideoTypeCount > 0) {
        console.log(`📊 Videos with null/undefined videoType: ${nullVideoTypeCount}`);
      }
    } catch (err) {
      console.log('⚠️ Error checking videoType stats:', err.message);
    }
    
    // Add videoType filter if specified
    // **FIXED: Use 'yog' consistently in both frontend and backend**
    if (videoType) {
      const normalizedType = videoType.toLowerCase();
      // Normalize 'vayug' to 'vayu' for consistency (keep 'yog' as is)
      const normalizedVideoType = normalizedType === 'vayug' ? 'vayu' : normalizedType;
      
      if (normalizedVideoType === 'yog' || normalizedVideoType === 'vayu') {
        baseQueryFilter.videoType = normalizedVideoType;
        console.log(`📹 Filtering by videoType: ${normalizedVideoType}`);
        
        // **DEBUG: Check how many videos match this filter**
        const matchingCount = await Video.countDocuments(baseQueryFilter);
        console.log(`📊 Videos matching videoType='${normalizedVideoType}': ${matchingCount}`);
      } else {
        console.log(`⚠️ Unknown videoType: ${videoType}, showing all videos`);
      }
    }
    
    let unwatchedVideos = [];
    let watchedVideos = [];
    let finalVideos = [];
    let unwatchedVideoIds = []; // **FIXED: Declare outside if block for hasMore calculation**
    
    // **NEW: Simple sort by finalScore - uses new balanced recommendation system**
    // Videos are already sorted by finalScore from database query
    // Just return the top N videos based on recommendation score
    function getTopVideosByScore(videos, limit) {
      if (videos.length === 0) return [];
      
      // Sort by finalScore (descending), then by createdAt (descending) as tiebreaker
      const sorted = [...videos].sort((a, b) => {
        const scoreA = a.finalScore || 0;
        const scoreB = b.finalScore || 0;
        
        if (scoreB !== scoreA) {
          return scoreB - scoreA; // Higher score first
        }
        
        // Tiebreaker: newer videos first
        const dateA = new Date(a.createdAt || a.uploadedAt || 0).getTime();
        const dateB = new Date(b.createdAt || b.uploadedAt || 0).getTime();
        return dateB - dateA;
      });
      
      return sorted.slice(0, limit);
    }
    
    // **BACKEND-FIRST: Personalized feed for ALL users (authenticated + anonymous)**
    if (userIdentifier) {
      console.log('🎯 Getting personalized feed for user:', userIdentifier, isAuthenticated ? '(authenticated)' : '(anonymous)');
      
      // Step 1: Get user's watched video IDs (NO LIMIT - backend-first approach)
      // Remove 30-day limit to track all watched videos for better filtering
      let watchedVideoIds = await WatchHistory.getUserWatchedVideoIds(userIdentifier, null);
      console.log(`📊 User has watched ${watchedVideoIds.length} videos (all time)`);
      
      // Step 2: ALWAYS fetch fresh unwatched video IDs (cache disabled for variety)
      // **FIXED: Always fetch fresh - no cache check**
      // This ensures different videos every time, preventing loops
      {
        // **SCALABLE: Dynamic pool size based on total videos for 5000+ videos**
        // First, get total video count to determine optimal pool size
        const totalVideoCount = await Video.countDocuments(baseQueryFilter);
        console.log(`📊 Total videos in database: ${totalVideoCount}`);
        
        // **NEW: Auto-reset watch history if user has watched too many videos**
        // This ensures users always have fresh content to discover
        if (watchedVideoIds.length > 0 && totalVideoCount > 0) {
          const watchedPercentage = (watchedVideoIds.length / totalVideoCount) * 100;
          
          // If user has watched >95% of videos, completely reset watch history
          if (watchedPercentage > 95) {
            console.log(`🔄 User has watched ${watchedPercentage.toFixed(1)}% of videos (>95%) - resetting ALL watch history for fresh feed`);
            const resetResult = await WatchHistory.clearAllWatchHistory(userIdentifier);
            console.log(`✅ Reset complete: Cleared ${resetResult.deletedCount} watch history entries`);
            
            // Refresh watched video IDs (should be empty now)
            watchedVideoIds = [];
          } 
          // If user has watched >80% of videos, clear old watch history (older than 30 days)
          else if (watchedPercentage > 80) {
            console.log(`🔄 User has watched ${watchedPercentage.toFixed(1)}% of videos (>80%) - clearing old watch history (30+ days old)`);
            const clearResult = await WatchHistory.clearOldWatchHistory(userIdentifier, 30);
            console.log(`✅ Old history cleared: Removed ${clearResult.deletedCount} entries`);
            
            // Refresh watched video IDs (excluding recently cleared entries)
            const refreshedWatchedIds = await WatchHistory.getUserWatchedVideoIds(userIdentifier, null);
            watchedVideoIds = refreshedWatchedIds;
            console.log(`📊 Updated: User has ${watchedVideoIds.length} watched videos remaining`);
          }
        }
        
        // **SCALABLE: Adaptive pool size calculation**
        // For 5000+ videos: fetch more IDs to ensure variety
        // Formula: min(50x limit, 30% of total, max 5000)
        // This ensures:
        // - Small libraries (<1000): fetch 50x limit (1000 IDs for limit=20)
        // - Medium libraries (1000-5000): fetch 30% of total
        // - Large libraries (5000+): fetch max 5000 IDs (still manageable)
        const adaptiveMultiplier = totalVideoCount < 1000 ? 50 : 
                                   totalVideoCount < 5000 ? Math.ceil(totalVideoCount * 0.3 / limitNum) : 
                                   Math.ceil(5000 / limitNum);
        const maxIdsToFetch = Math.min(
          limitNum * adaptiveMultiplier, 
          Math.ceil(totalVideoCount * 0.3), // Max 30% of total videos
          5000 // Hard cap for memory safety
        );
        
        console.log(`📊 Adaptive pool size: ${maxIdsToFetch} IDs (${adaptiveMultiplier}x limit, ${((maxIdsToFetch/totalVideoCount)*100).toFixed(1)}% of total)`);
        
        // PERFORMANCE: $nin query is efficient for MongoDB
        // If watchedVideoIds is very large (>1000), MongoDB handles it efficiently with indexes
        const unwatchedQuery = {
          ...baseQueryFilter,
          ...(watchedVideoIds.length > 0 && { _id: { $nin: watchedVideoIds } }) // Exclude watched videos if any
        };
        
        // **NEW: If user has watched too many videos, exclude own videos from initial pool**
        // This prevents own videos from dominating when user has watched most content
        if (userId && watchedVideoIds.length > 0 && totalVideoCount > 0) {
          const watchedPercentage = (watchedVideoIds.length / totalVideoCount) * 100;
          
          // If user has watched >70% of videos, exclude own videos from initial unwatched pool
          // This ensures variety even when they've seen most content
          if (watchedPercentage > 70) {
            try {
              const currentUser = await User.findOne({ googleId: userId }).select('_id').lean();
              if (currentUser) {
                unwatchedQuery.uploader = { $ne: currentUser._id };
                console.log(`📊 User has watched ${watchedPercentage.toFixed(1)}% of videos - excluding own videos from initial pool for better variety`);
              }
            } catch (userError) {
              console.log('⚠️ Could not check user for pool filtering:', userError.message);
            }
          }
        }
        
        // **FIXED: Fetch more videos and shuffle to ensure variety**
        // Fetch 2x more IDs than needed, then shuffle to break deterministic order
        const fetchLimit = Math.min(maxIdsToFetch * 2, totalVideoCount);
        
        const unwatchedVideosRaw = await Video.find(unwatchedQuery)
          .select('_id finalScore uploader')
          .sort({ finalScore: -1, createdAt: -1 }) // Sort by recommendation score first
          .limit(fetchLimit) // Fetch more for variety
          .populate('uploader', '_id googleId')
          .lean();
        
        // **NEW: Shuffle the IDs to break deterministic order**
        // This ensures different videos show even with same scores
        const allIds = unwatchedVideosRaw.map(v => v._id);
        
        // Fisher-Yates shuffle for proper randomization
        for (let i = allIds.length - 1; i > 0; i--) {
          const j = Math.floor(Math.random() * (i + 1));
          [allIds[i], allIds[j]] = [allIds[j], allIds[i]];
        }
        
        // Take first maxIdsToFetch after shuffling
        unwatchedVideoIds = allIds.slice(0, maxIdsToFetch);
        
        console.log(`🎲 Shuffled ${allIds.length} IDs, selected top ${unwatchedVideoIds.length} for variety`);
        
        // **DEBUG: Check variety in fetched unwatched video IDs**
        if (unwatchedVideosRaw.length > 0) {
          const uniqueUploadersInPool = new Set(
            unwatchedVideosRaw
              .map(v => v.uploader?._id?.toString() || v.uploader?.googleId || 'unknown')
              .filter(id => id !== 'unknown')
          );
          console.log(`📊 Unwatched pool variety: ${uniqueUploadersInPool.size} unique uploaders in ${unwatchedVideosRaw.length} videos`);
          
          if (userId) {
            const currentUser = await User.findOne({ googleId: userId }).select('_id').lean();
            if (currentUser) {
              const ownVideosInPool = unwatchedVideosRaw.filter(
                v => v.uploader?._id?.toString() === currentUser._id.toString()
              ).length;
              console.log(`📊 Own videos in unwatched pool: ${ownVideosInPool} out of ${unwatchedVideosRaw.length}`);
              
              // **FIX: If pool has only own videos, clear cache and log warning**
              if (ownVideosInPool === unwatchedVideosRaw.length && unwatchedVideosRaw.length > 0) {
                console.log('⚠️ WARNING: Unwatched pool contains only user\'s own videos! This indicates a problem with video variety.');
                if (redisService.getConnectionStatus() && unwatchedCacheKey) {
                  await redisService.del(unwatchedCacheKey);
                  console.log('🧹 Cleared unwatched video IDs cache to force fresh fetch');
                }
              }
            }
          }
        }
        
        // **FIXED: CACHE DISABLED - Always fetch fresh for maximum variety**
        // Cache was causing same videos to appear repeatedly
        // Now we skip caching to ensure fresh videos every time
        console.log(`✅ Fetched ${unwatchedVideoIds.length} fresh unwatched video IDs (cache disabled for variety)`);
      }
      
      // Step 3: Fetch unwatched videos with full metadata for diversity algorithm
      // **SCALABLE: Adaptive pool size for diversity algorithm with pagination support**
      // For large libraries (5000+), use larger pool for better variety
      // Use pagination offset to get different videos on each page
      const totalVideoCount = await Video.countDocuments(baseQueryFilter);
      const adaptivePoolMultiplier = totalVideoCount > 2000 ? 20 : 15; // Larger pool for big libraries
      const poolSize = Math.min(unwatchedVideoIds.length, limitNum * adaptivePoolMultiplier);
      
      // **FIXED: Better pagination with fresh fetch for each page**
      // For page > 1, we need to fetch fresh unwatched videos excluding already watched ones
      // This ensures different videos on each page
      const paginationOffsetForPool = (pageNum - 1) * limitNum;
      
      // **FIXED: For pagination, fetch fresh unwatched videos excluding already shown**
      // Instead of slicing cached array, fetch fresh videos for this page
      let availableIds = [];
      
      if (pageNum === 1) {
        // First page: use the already fetched unwatchedVideoIds
        availableIds = unwatchedVideoIds.slice(0, poolSize);
      } else {
        // Subsequent pages: fetch fresh unwatched videos with pagination
        // This ensures we get different videos, not same cached ones
        const unwatchedQueryPagination = {
          ...baseQueryFilter,
          ...(watchedVideoIds.length > 0 && { _id: { $nin: watchedVideoIds } })
        };
        
        const freshUnwatched = await Video.find(unwatchedQueryPagination)
          .select('_id finalScore')
          .sort({ finalScore: -1, createdAt: -1 })
          .skip(paginationOffsetForPool)
          .limit(poolSize)
          .lean();
        
        availableIds = freshUnwatched.map(v => v._id);
        console.log(`📄 Page ${pageNum}: Fetched ${availableIds.length} fresh unwatched video IDs (offset: ${paginationOffsetForPool})`);
      }
      
      const idsToUse = Math.min(poolSize, availableIds.length);
      
      console.log(`📊 Fetching top ${idsToUse} unwatched videos by recommendation score (offset: ${paginationOffsetForPool})`);
      
      // Step 4: Fetch unwatched videos sorted by finalScore
      if (availableIds.length > 0) {
        unwatchedVideos = await Video.find({
          ...baseQueryFilter,
          _id: { $in: availableIds }
        })
        .select('videoName videoUrl thumbnailUrl likes views shares uploader uploadedAt likedBy videoType aspectRatio duration comments link description hlsMasterPlaylistUrl hlsPlaylistUrl isHLSEncoded category tags keywords createdAt finalScore')
        .populate('uploader', 'name profilePic googleId')
        .populate('comments.user', 'name profilePic googleId')
        .sort({ finalScore: -1, createdAt: -1 }) // Sort by recommendation score
        .limit(idsToUse)
        .lean();
      }
      
      console.log(`✅ Found ${unwatchedVideos.length} unwatched videos sorted by recommendation score`);
      
      // **NEW: Fallback handling when no unwatched videos are found**
      // This happens when user has watched ALL videos (100% watched)
      if (unwatchedVideos.length === 0 && watchedVideoIds.length > 0) {
        const currentWatchedPercentage = (watchedVideoIds.length / totalVideoCount) * 100;
        console.log(`⚠️ No unwatched videos found! User has watched ${currentWatchedPercentage.toFixed(1)}% of videos`);
        
        // If user has watched 100% (or very close), reset watch history completely
        if (currentWatchedPercentage >= 100 || watchedVideoIds.length >= totalVideoCount) {
          console.log(`🔄 User has watched ALL videos (100%) - resetting watch history for fresh feed`);
          const resetResult = await WatchHistory.clearAllWatchHistory(userIdentifier);
          console.log(`✅ Reset complete: Cleared ${resetResult.deletedCount} watch history entries`);
          
          // Now fetch all videos as unwatched (since history is reset)
          watchedVideoIds = [];
          const allVideos = await Video.find(baseQueryFilter)
            .select('videoName videoUrl thumbnailUrl likes views shares uploader uploadedAt likedBy videoType aspectRatio duration comments link description hlsMasterPlaylistUrl hlsPlaylistUrl isHLSEncoded category tags keywords createdAt finalScore')
            .populate('uploader', 'name profilePic googleId')
            .populate('comments.user', 'name profilePic googleId')
            .sort({ finalScore: -1, createdAt: -1 })
            .limit(limitNum * 3) // Fetch more for variety
            .lean();
          
          unwatchedVideos = allVideos;
          console.log(`✅ After reset: Found ${unwatchedVideos.length} videos (now all unwatched)`);
        } else {
          // Edge case: No unwatched videos but percentage is <100%
          // This might happen if all unwatched videos are filtered out (e.g., processing failed)
          console.log(`⚠️ Edge case: No unwatched videos but watched percentage is ${currentWatchedPercentage.toFixed(1)}%`);
          // Fallback: Show all videos regardless of watch status (user will see watched videos again)
          unwatchedVideos = await Video.find(baseQueryFilter)
            .select('videoName videoUrl thumbnailUrl likes views shares uploader uploadedAt likedBy videoType aspectRatio duration comments link description hlsMasterPlaylistUrl hlsPlaylistUrl isHLSEncoded category tags keywords createdAt finalScore')
            .populate('uploader', 'name profilePic googleId')
            .populate('comments.user', 'name profilePic googleId')
            .sort({ finalScore: -1, createdAt: -1 })
            .limit(limitNum * 3)
            .lean();
          
          console.log(`✅ Fallback: Showing ${unwatchedVideos.length} videos (including watched ones)`);
        }
      }
      
      // **DEBUG: Check variety in unwatched videos**
      if (unwatchedVideos.length > 0) {
        const uniqueUploaders = new Set(unwatchedVideos.map(v => v.uploader?._id?.toString() || 'unknown'));
        console.log(`📊 Unwatched videos variety: ${uniqueUploaders.size} unique uploaders out of ${unwatchedVideos.length} videos`);
        if (uniqueUploaders.size === 1 && userId) {
          console.log('⚠️ WARNING: Only one uploader found in unwatched videos - possible cache issue or limited content');
        }
      }
      
      // **NEW: Use diversity-aware ordering with controlled randomness**
      // Fetch more videos (2x limit) to ensure we have enough for diversity filtering
      let candidateVideos = getTopVideosByScore(unwatchedVideos, limitNum * 2);
      
      // **NEW: Enforce variety - limit own videos to max 30% of feed**
      if (candidateVideos.length > 0 && userId) {
        try {
          const currentUser = await User.findOne({ googleId: userId }).select('_id').lean();
          if (currentUser) {
            const ownVideos = candidateVideos.filter(
              v => v.uploader?._id?.toString() === currentUser._id.toString()
            );
            const otherVideos = candidateVideos.filter(
              v => v.uploader?._id?.toString() !== currentUser._id.toString()
            );
            
            // Limit own videos to max 30% of feed (minimum 1 if available)
            const maxOwnVideos = Math.max(1, Math.floor(limitNum * 0.3));
            if (ownVideos.length > maxOwnVideos) {
              console.log(`⚠️ Limiting own videos: ${ownVideos.length} -> ${maxOwnVideos} (30% max for variety)`);
              const limitedOwnVideos = ownVideos.slice(0, maxOwnVideos);
              candidateVideos = [...limitedOwnVideos, ...otherVideos];
            }
          }
        } catch (userError) {
          console.log('⚠️ Could not check user for variety enforcement:', userError.message);
        }
      }
      
      // **CRITICAL: Final safety check - filter out any watched videos that might have slipped through**
      // This is a double-check to ensure watched videos are NEVER shown (unless watch history was reset)
      // Skip this check if watch history was just reset (watchedVideoIds is empty)
      if (watchedVideoIds.length > 0) {
        finalVideos = candidateVideos.filter(video => {
          const videoId = video._id?.toString();
          return !watchedVideoIds.some(watchedId => watchedId.toString() === videoId);
        });
      } else {
        // Watch history was reset - all videos are now unwatched
        finalVideos = candidateVideos;
      }
      
      // **NEW: Final fallback - if still no videos, fetch all videos regardless of watch status**
      // This ensures user always sees something (edge case: all videos watched but reset failed)
      if (finalVideos.length === 0) {
        console.log(`⚠️ CRITICAL: Still no videos after filtering! Fetching all videos as last resort`);
        const allVideosFallback = await Video.find(baseQueryFilter)
          .select('videoName videoUrl thumbnailUrl likes views shares uploader uploadedAt likedBy videoType aspectRatio duration comments link description hlsMasterPlaylistUrl hlsPlaylistUrl isHLSEncoded category tags keywords createdAt finalScore')
          .populate('uploader', 'name profilePic googleId')
          .populate('comments.user', 'name profilePic googleId')
          .sort({ finalScore: -1, createdAt: -1 })
          .limit(limitNum * 2)
          .lean();
        
        finalVideos = allVideosFallback;
        console.log(`✅ Last resort: Showing ${finalVideos.length} videos (all videos, watch history ignored)`);
      }
      
      // **NEW: Apply diversity-aware ordering - ensures no same creator back-to-back**
      // This method maintains score-based ranking while enforcing creator diversity
      finalVideos = RecommendationService.orderFeedWithDiversity(finalVideos, {
        randomness: 0.15, // 15% controlled randomness for freshness
        minCreatorSpacing: 2 // Minimum 2 videos between same creator
      }).slice(0, limitNum);
      
      console.log(`✅ Applied diversity-aware ordering: ${finalVideos.length} videos ordered with creator spacing`);
      
      // **DEBUG: Verify creator diversity in final feed**
      if (finalVideos.length > 1) {
        const creatorSequence = finalVideos.map(v => {
          return v.uploader?._id?.toString() || 
                 v.uploader?.googleId?.toString() || 
                 v.uploader?.id?.toString() || 
                 'unknown';
        });
        
        // Check for back-to-back same creators (should be 0)
        let backToBackCount = 0;
        for (let i = 1; i < creatorSequence.length; i++) {
          if (creatorSequence[i] === creatorSequence[i - 1]) {
            backToBackCount++;
          }
        }
        
        const uniqueCreators = new Set(creatorSequence).size;
        console.log(`📊 Final feed diversity: ${uniqueCreators} unique creators, ${backToBackCount} back-to-back duplicates (should be 0)`);
        
        if (backToBackCount > 0) {
          console.log('⚠️ WARNING: Found back-to-back same creators in feed - diversity enforcement may need adjustment');
        }
      }
      
      console.log(`✅ Final videos (sorted by recommendation score): ${topUnwatchedVideos.length} unwatched + ${watchedVideos.length} watched = ${finalVideos.length} total`);
      
      // **DEBUG: Check final variety**
      if (finalVideos.length > 0) {
        const finalUniqueUploaders = new Set(finalVideos.map(v => v.uploader?._id?.toString() || v.uploader?.googleId || 'unknown'));
        const currentUserGoogleId = userId || null;
        const ownVideosCount = currentUserGoogleId 
          ? finalVideos.filter(v => v.uploader?.googleId === currentUserGoogleId).length 
          : 0;
        console.log(`📊 Final feed variety: ${finalUniqueUploaders.size} unique uploaders, ${ownVideosCount} own videos out of ${finalVideos.length} total`);
        
        if (ownVideosCount === finalVideos.length && finalVideos.length > 0) {
          console.log('⚠️ WARNING: Feed contains only user\'s own videos! Clearing cache and retrying...');
          // Clear cache to force fresh fetch
          if (redisService.getConnectionStatus() && unwatchedCacheKey) {
            await redisService.del(unwatchedCacheKey);
            console.log('🧹 Cleared unwatched video IDs cache');
          }
        }
      }
      
    } else {
      // **NEW: Regular feed sorted by recommendation score with randomization**
      console.log('📹 Using regular feed (no user identifier) - sorted by recommendation score with randomization');
      
      const skip = (pageNum - 1) * limitNum;
      
      // Fetch more videos for randomization
      const fetchLimit = limitNum * 3; // Fetch 3x for variety
      
      const videos = await Video.find(baseQueryFilter)
        .select('videoName videoUrl thumbnailUrl likes views shares uploader uploadedAt likedBy videoType aspectRatio duration comments link description hlsMasterPlaylistUrl hlsPlaylistUrl isHLSEncoded category tags keywords createdAt finalScore')
        .populate('uploader', 'name profilePic googleId')
        .populate('comments.user', 'name profilePic googleId')
        .sort({ finalScore: -1, createdAt: -1 }) // Sort by recommendation score first, then by creation date
        .skip(skip)
        .limit(fetchLimit)
        .lean();
      
      // **NEW: Apply diversity-aware ordering for regular feed too**
      if (videos.length > 0) {
        finalVideos = RecommendationService.orderFeedWithDiversity(videos, {
          randomness: 0.15, // 15% controlled randomness
          minCreatorSpacing: 2 // Minimum 2 videos between same creator
        }).slice(0, limitNum);
        
        console.log(`✅ Applied diversity-aware ordering to regular feed: ${finalVideos.length} videos`);
      } else {
        finalVideos = videos;
      }
    }

    // **Filter out videos with invalid uploader references**
    const validVideos = finalVideos.filter(video => {
      return video.uploader && 
             video.uploader._id && 
             video.uploader.name && 
             video.uploader.name.trim() !== '';
    });

    console.log(`📹 Filtered out ${finalVideos.length - validVideos.length} videos with invalid uploader references`);
    console.log(`📹 Returning ${validVideos.length} valid videos`);
    
    // **DEBUG: Log detailed breakdown if no videos found**
    if (validVideos.length === 0) {
      console.log('❌ DEBUG: No valid videos found! Breakdown:');
      console.log(`   - finalVideos.length: ${finalVideos.length}`);
      console.log(`   - baseQueryFilter: ${JSON.stringify(baseQueryFilter)}`);
      console.log(`   - userIdentifier: ${userIdentifier || 'none'}`);
      console.log(`   - watchedVideoIds.length: ${watchedVideoIds?.length || 0}`);
      console.log(`   - unwatchedVideoIds.length: ${unwatchedVideoIds?.length || 0}`);
      
      // Check if all videos are being filtered out
      const totalMatchingFilter = await Video.countDocuments(baseQueryFilter);
      console.log(`   - Total videos matching baseQueryFilter: ${totalMatchingFilter}`);
      
      if (userIdentifier && watchedVideoIds?.length > 0) {
        const unwatchedCount = await Video.countDocuments({
          ...baseQueryFilter,
          _id: { $nin: watchedVideoIds }
        });
        console.log(`   - Unwatched videos count: ${unwatchedCount}`);
      }
    }

    // Transform videos to match Flutter app expectations
    // **FIX: Convert to async to handle likedBy conversion**
    const transformedVideos = await Promise.all(validVideos.map(async (video) => {
      // **FIX: Convert likedBy ObjectIds to googleIds**
      const likedByGoogleIds = await convertLikedByToGoogleIds(video.likedBy || []);
      
      return {
        ...video,
        uploader: {
          id: video.uploader?.googleId?.toString() || video.uploader?._id?.toString() || '',
          _id: video.uploader?._id?.toString() || '',
          googleId: video.uploader?.googleId?.toString() || '',
          name: video.uploader?.name || 'Unknown User',
          profilePic: video.uploader?.profilePic || ''
        },
        likedBy: likedByGoogleIds, // **FIXED: Use googleIds instead of ObjectIds**
        comments: await Promise.all((video.comments || []).map(async (comment) => {
          // **FIX: Convert comment likedBy ObjectIds to googleIds**
          const commentLikedByGoogleIds = await convertLikedByToGoogleIds(comment.likedBy || []);
          return {
            _id: comment._id,
            text: comment.text,
            userId: comment.user?.googleId || comment.user?._id || '',
            userName: comment.user?.name || '',
            createdAt: comment.createdAt,
            likes: comment.likes || 0,
            likedBy: commentLikedByGoogleIds // **FIXED: Use googleIds for comment likes**
          };
        })),
        // **NEW: Add isWatched flag if user is authenticated**
        isWatched: userId && Array.isArray(watchedVideos) && watchedVideos.length > 0 
          ? watchedVideos.some(w => w._id.toString() === video._id.toString()) 
          : false
      };
    }));
    
    // Get total count for pagination
    let totalVideos = 0;
    if (userIdentifier) {
      // For personalized feed, count unwatched + watched videos
      const watchedVideoIds = await WatchHistory.getUserWatchedVideoIds(userIdentifier, null);
      const unwatchedCount = await Video.countDocuments({
        ...baseQueryFilter,
        _id: { $nin: watchedVideoIds }
      });
      totalVideos = unwatchedCount + Math.min(watchedVideoIds.length, limitNum); // Approximate
    } else {
      // For regular feed, use actual count
      totalVideos = await Video.countDocuments(baseQueryFilter);
    }
    
    const isPersonalizedFeed = !!userIdentifier;
    const paginationOffset = isPersonalizedFeed ? (pageNum - 1) * limitNum : 0; // Calculate offset for personalized feed

      const response = {
      videos: transformedVideos,
      hasMore: isPersonalizedFeed 
        ? (transformedVideos.length >= limitNum && (unwatchedVideoIds.length > paginationOffset + limitNum || totalVideos > pageNum * limitNum)) // **SCALABLE: Check if more unwatched videos exist based on pagination offset**
        : (pageNum * limitNum) < totalVideos, // For regular feed, use pagination
      total: totalVideos,
      currentPage: pageNum,
      totalPages: Math.ceil(totalVideos / limitNum),
      filters: {
        videoType: videoType || 'all',
        format: 'mp4_and_hls',
        personalized: isPersonalizedFeed
      },
      message: `✅ Fetched ${validVideos.length} valid videos successfully${userIdentifier ? ' (personalized feed)' : ''}${videoType ? ` (${videoType} type)` : ''}`
    };
    
    // **IMPROVED: Don't cache shuffled results - only cache unwatched IDs (already done above)**
    // This ensures different users get different random orders on each request
    
    // **DEBUG: Comprehensive video availability check**
    console.log(`📊 VIDEO AVAILABILITY DEBUG:`);
    console.log(`   - validVideos.length: ${validVideos.length}`);
    console.log(`   - transformedVideos.length: ${transformedVideos.length}`);
    console.log(`   - totalVideos (from query): ${totalVideos}`);
    console.log(`   - videoType filter: ${videoType || 'none'}`);
    console.log(`   - userIdentifier: ${userIdentifier || 'none'}`);
    console.log(`   - isPersonalizedFeed: ${isPersonalizedFeed}`);

    // Check video URL distribution
    if (transformedVideos.length > 0) {
      const cloudflareUrls = transformedVideos.filter(v => v.videoUrl && v.videoUrl.includes('cdn.snehayog.site'));
      const cloudinaryUrls = transformedVideos.filter(v => v.videoUrl && v.videoUrl.includes('cloudinary.com'));
      const otherUrls = transformedVideos.filter(v => v.videoUrl && !v.videoUrl.includes('cdn.snehayog.site') && !v.videoUrl.includes('cloudinary.com'));
      const missingUrls = transformedVideos.filter(v => !v.videoUrl || v.videoUrl === '');
      
      console.log(`   📹 Video URL Distribution:`);
      console.log(`      - Cloudflare (cdn.snehayog.site): ${cloudflareUrls.length}`);
      console.log(`      - Cloudinary: ${cloudinaryUrls.length}`);
      console.log(`      - Other: ${otherUrls.length}`);
      console.log(`      - Missing URLs: ${missingUrls.length}`);
      
      if (cloudflareUrls.length > 0) {
        console.log(`      - Sample Cloudflare URL: ${cloudflareUrls[0].videoUrl?.substring(0, 80)}...`);
      }
      if (cloudinaryUrls.length > 0) {
        console.log(`      - Sample Cloudinary URL: ${cloudinaryUrls[0].videoUrl?.substring(0, 80)}...`);
      }
      if (missingUrls.length > 0) {
        console.log(`      ⚠️ Videos with missing URLs: ${missingUrls.map(v => v.videoName || v._id).join(', ')}`);
      }
    } else {
      // **CRITICAL: No videos in response - check why**
      console.log(`   ❌ NO VIDEOS IN RESPONSE! Checking filters...`);
      
      // Check baseQueryFilter match
      const baseFilterCount = await Video.countDocuments(baseQueryFilter);
      console.log(`   - Videos matching baseQueryFilter: ${baseFilterCount}`);
      console.log(`   - baseQueryFilter: ${JSON.stringify(baseQueryFilter, null, 2)}`);
      
      // Check without videoType filter
      const withoutVideoTypeFilter = { ...baseQueryFilter };
      delete withoutVideoTypeFilter.videoType;
      const withoutVideoTypeCount = await Video.countDocuments(withoutVideoTypeFilter);
      console.log(`   - Videos without videoType filter: ${withoutVideoTypeCount}`);
      
      // Check processingStatus distribution
      const statusCounts = await Video.aggregate([
        {
          $match: {
            uploader: { $exists: true, $ne: null },
            videoUrl: { 
              $exists: true, 
              $ne: null, 
              $ne: '',
              $not: /^uploads[\\\/]/,
              $regex: /^https?:\/\//
            }
          }
        },
        {
          $group: {
            _id: '$processingStatus',
            count: { $sum: 1 }
          }
        }
      ]);
      console.log(`   - Processing status distribution: ${JSON.stringify(statusCounts)}`);
      
      // Check videoType distribution for completed videos
      const videoTypeCounts = await Video.aggregate([
        {
          $match: {
            uploader: { $exists: true, $ne: null },
            videoUrl: { 
              $exists: true, 
              $ne: null, 
              $ne: '',
              $not: /^uploads[\\\/]/,
              $regex: /^https?:\/\//
            },
            processingStatus: 'completed'
          }
        },
        {
          $group: {
            _id: '$videoType',
            count: { $sum: 1 }
          }
        }
      ]);
      console.log(`   - VideoType distribution (completed only): ${JSON.stringify(videoTypeCounts)}`);
    }
    
    console.log(`✅ Found ${validVideos.length} valid videos (page ${pageNum}, total: ${totalVideos})`);
    
    res.json(response);
  } catch (error) {
    console.error('❌ Error fetching videos:', error);
    console.error('❌ Error stack:', error.stack);
    console.error('❌ Error details:', {
      name: error.name,
      message: error.message,
      code: error.code,
    });
    
    // **NEW: Send detailed error response for debugging**
    res.status(500).json({ 
      error: 'Failed to fetch videos',
      message: error.message,
      details: process.env.NODE_ENV === 'development' ? error.stack : undefined,
      timestamp: new Date().toISOString()
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
    
    // **FIX: Normalize video URLs to fix Windows path separator issues**
    const normalizeUrl = (url) => {
      if (!url) return url;
      return url.replace(/\\/g, '/');
    };
    
    // **FIX: Convert likedBy ObjectIds to googleIds**
    const likedByGoogleIds = await convertLikedByToGoogleIds(videoObj.likedBy || []);
    
    const transformedVideo = {
      _id: videoObj._id?.toString(),
      videoName: videoObj.videoName || 'Untitled Video',
      videoUrl: normalizeUrl(videoObj.videoUrl || videoObj.hlsMasterPlaylistUrl || videoObj.hlsPlaylistUrl || ''),
      thumbnailUrl: normalizeUrl(videoObj.thumbnailUrl || ''),
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
      // **FIX: Use googleId as id for correct profile navigation**
      uploader: {
        id: videoObj.uploader?.googleId?.toString() || videoObj.uploader?._id?.toString() || '',
        _id: videoObj.uploader?._id?.toString() || '',
        googleId: videoObj.uploader?.googleId?.toString() || '',
        name: videoObj.uploader?.name || 'Unknown User',
        profilePic: videoObj.uploader?.profilePic || ''
      },
      // HLS Streaming fields
      hlsMasterPlaylistUrl: videoObj.hlsMasterPlaylistUrl || null,
      hlsPlaylistUrl: videoObj.hlsPlaylistUrl || null,
      isHLSEncoded: videoObj.isHLSEncoded || false,
      likedBy: likedByGoogleIds, // **FIXED: Use googleIds instead of ObjectIds**
      comments: await Promise.all((videoObj.comments || []).map(async (comment) => {
        // **FIX: Convert comment likedBy ObjectIds to googleIds**
        const commentLikedByGoogleIds = await convertLikedByToGoogleIds(comment.likedBy || []);
        return {
          _id: comment._id,
          text: comment.text,
          userId: comment.user?.googleId || comment.user?._id || '',
          userName: comment.user?.name || '',
          createdAt: comment.createdAt,
          likes: comment.likes || 0,
          likedBy: commentLikedByGoogleIds // **FIXED: Use googleIds for comment likes**
        };
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

// **BACKEND-FIRST: POST /api/videos/:id/watch - Track video watch for personalized feed**
// Supports both authenticated users (via token) and anonymous users (via deviceId)
router.post('/:id/watch', async (req, res) => {
  try {
    // Try to get userId from token (authenticated users)
    let userId = null;
    let isAuthenticated = false;
    
    try {
      const token = req.headers.authorization?.split(' ')[1];
      if (token) {
        // Try Google access token first
        try {
          const googleResponse = await fetch(`https://www.googleapis.com/oauth2/v2/userinfo?access_token=${token}`);
          if (googleResponse.ok) {
            const userInfo = await googleResponse.json();
            userId = userInfo.id;
            isAuthenticated = true;
          } else {
            // Try JWT token
            const jwt = (await import('jsonwebtoken')).default;
            const JWT_SECRET = process.env.JWT_SECRET;
            if (JWT_SECRET) {
              try {
                const decoded = jwt.verify(token, JWT_SECRET);
                userId = decoded.id || decoded.googleId;
                isAuthenticated = true;
              } catch (jwtError) {
                // Token invalid - will use deviceId
              }
            }
          }
        } catch (tokenError) {
          // Token verification failed - will use deviceId
        }
      }
    } catch (error) {
      // Error getting token - will use deviceId
    }
    
    // **BACKEND-FIRST: Use deviceId for anonymous users**
    const deviceId = req.body.deviceId || req.headers['x-device-id'];
    const userIdentifier = userId || deviceId;
    
    const videoId = req.params.id;
    const { duration = 0, completed = false } = req.body;

    if (!userIdentifier) {
      return res.status(400).json({ error: 'User identifier (userId or deviceId) required' });
    }

    if (!videoId || !mongoose.Types.ObjectId.isValid(videoId)) {
      return res.status(400).json({ error: 'Invalid video ID' });
    }

    console.log('📊 Tracking video watch:', { 
      userIdentifier, 
      isAuthenticated: isAuthenticated ? 'authenticated' : 'anonymous',
      videoId, 
      duration, 
      completed 
    });

    // **BACKEND-FIRST: Track watch history for all users**
    const watchEntry = await WatchHistory.trackWatch(userIdentifier, videoId, {
      duration,
      completed,
      isAuthenticated
    });

    // Update video view count
    await Video.findByIdAndUpdate(videoId, {
      $inc: { views: 1 }
    });

    // **FIXED: Invalidate unwatched video IDs cache (matches new cache key pattern)**
    if (redisService.getConnectionStatus() && userIdentifier) {
      // Clear the unwatched IDs cache so user sees updated feed after watching
      const unwatchedCachePattern = `videos:unwatched:ids:${userIdentifier}:*`;
      await redisService.clearPattern(unwatchedCachePattern);
      console.log(`🧹 Cleared unwatched IDs cache for user: ${userIdentifier}`);
      
      // Also clear old feed cache pattern for backward compatibility
      const feedCachePattern = `videos:feed:user:${userIdentifier}:*`;
      await redisService.clearPattern(feedCachePattern);
      console.log(`🧹 Cleared feed cache for user: ${userIdentifier}`);
    }

    res.json({
      success: true,
      message: 'Watch tracked successfully',
      watchEntry: {
        videoId: watchEntry.videoId,
        watchedAt: watchEntry.watchedAt,
        lastWatchedAt: watchEntry.lastWatchedAt,
        watchCount: watchEntry.watchCount,
        completed: watchEntry.completed
      }
    });
  } catch (error) {
    console.error('❌ Error tracking watch:', error);
    res.status(500).json({
      error: 'Failed to track watch',
      message: error.message
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
    
    // **CRITICAL FIX: Use atomic MongoDB operations to update BOTH likedBy AND likes count simultaneously**
    // This prevents race conditions and ensures data consistency
    let updatedVideo;
    if (userLikedIndex > -1) {
      // User has already liked - remove the like (atomic $pull + $inc operations)
      updatedVideo = await Video.findByIdAndUpdate(
        videoId,
        { 
          $pull: { likedBy: userObjectId },
          $inc: { likes: -1 } // Atomically decrement likes count
        },
        { new: true } // Return updated document
      );
      wasLiked = false;
      console.log('🔍 Like API: Removed like (atomic operation)');
    } else {
      // User hasn't liked - add the like (atomic $push + $inc operations)
      updatedVideo = await Video.findByIdAndUpdate(
        videoId,
        { 
          $push: { likedBy: userObjectId },
          $inc: { likes: 1 } // Atomically increment likes count
        },
        { new: true } // Return updated document
      );
      wasLiked = true;
      console.log('🔍 Like API: Added like (atomic operation)');
    }

    if (!updatedVideo) {
      console.log('❌ Like API: Video not found after update');
      return res.status(404).json({ error: 'Video not found' });
    }

    // **FIX: Ensure likes count doesn't go negative (safety check)**
    if (updatedVideo.likes < 0) {
      console.log('⚠️ Like API: Likes count is negative, resetting to 0');
      updatedVideo.likes = 0;
      await updatedVideo.save();
    }

    // **FIX: Final sync check - ensure likes count matches likedBy length (should match with atomic ops)**
    const actualLikedByLength = updatedVideo.likedBy.length;
    if (updatedVideo.likes !== actualLikedByLength) {
      console.log('⚠️ Like API: Syncing likes count with likedBy length', {
        currentLikes: updatedVideo.likes,
        likedByLength: actualLikedByLength
      });
      // Use atomic update to fix the count
      updatedVideo = await Video.findByIdAndUpdate(
        videoId,
        { $set: { likes: actualLikedByLength } },
        { new: true }
      );
    }

    console.log('✅ Like API: Video updated successfully with atomic operations, likes:', updatedVideo.likes);

    // **CRITICAL: Invalidate ALL caches when video is liked/unliked to ensure fresh data**
    // This ensures likes persist even after app restart, just like Instagram/YouTube
    if (redisService.getConnectionStatus()) {
      try {
        // Clear all possible cache patterns that might contain this video
        await invalidateCache([
          'videos:feed:*', // Clear all video feed caches
          'videos:unwatched:ids:*', // Clear unwatched IDs cache (feed uses this)
          VideoCacheKeys.single(videoId), // Clear single video cache
          VideoCacheKeys.all(), // Clear all video caches
          `videos:user:${updatedVideo.uploader?.toString()}`, // Clear uploader's video cache
          `videos:user:*`, // Clear all user video caches
        ]);
        console.log('🧹 Cache invalidated after like/unlike - ensuring fresh data on next fetch');
      } catch (cacheError) {
        console.error('⚠️ Error invalidating cache (non-critical):', cacheError.message);
        // Don't fail the request if cache invalidation fails
      }
    }

    // **FIX: Populate the updated video (already has latest data from atomic operation)**
    await updatedVideo.populate('uploader', 'name profilePic googleId');
    await updatedVideo.populate('comments.user', 'name profilePic googleId');

    // Transform comments to match Flutter app expectations
    const videoObj = updatedVideo.toObject();
    
    // **FIX: Convert likedBy ObjectIds to googleIds**
    const likedByGoogleIds = await convertLikedByToGoogleIds(videoObj.likedBy || []);
    
    // **CRITICAL: Ensure likes count matches likedBy length before sending response**
    const finalLikesCount = Math.max(0, likedByGoogleIds.length);
    const finalLikes = Math.max(0, parseInt(videoObj.likes) || 0);
    
    // Use the actual likedBy length as the source of truth for likes count
    const correctLikesCount = finalLikesCount;
    
    console.log('🔍 Like API: Final response data', {
      likes: correctLikesCount,
      likedByLength: likedByGoogleIds.length,
      likedByGoogleIds: likedByGoogleIds.length > 0 ? `${likedByGoogleIds.length} users` : 'empty',
      videoId: videoObj._id?.toString()
    });

    // **FIXED: Only send fields that frontend VideoModel expects**
    const transformedVideo = {
      _id: videoObj._id?.toString(),
      videoName: videoObj.videoName || '',
      videoUrl: videoObj.videoUrl || videoObj.hlsMasterPlaylistUrl || videoObj.hlsPlaylistUrl || '',
      thumbnailUrl: videoObj.thumbnailUrl || '',
      likes: correctLikesCount, // **CRITICAL: Use likedBy length as source of truth**
      views: parseInt(videoObj.views) || 0,
      shares: parseInt(videoObj.shares) || 0,
      description: videoObj.description || '',
      // **FIX: Use googleId as id for correct profile navigation**
      uploader: {
        id: videoObj.uploader?.googleId?.toString() || videoObj.uploader?._id?.toString() || '',
        _id: videoObj.uploader?._id?.toString() || '',
        googleId: videoObj.uploader?.googleId?.toString() || '',
        name: videoObj.uploader?.name || 'Unknown',
        profilePic: videoObj.uploader?.profilePic || '',
      },
      uploadedAt: videoObj.uploadedAt?.toISOString?.() || new Date().toISOString(),
      likedBy: likedByGoogleIds, // **FIXED: Use googleIds instead of ObjectIds**
      videoType: videoObj.videoType || 'reel',
      aspectRatio: parseFloat(videoObj.aspectRatio) || 9/16,
      duration: parseInt(videoObj.duration) || 0,
      comments: await Promise.all((videoObj.comments || []).map(async (comment) => {
        // **FIX: Convert comment likedBy ObjectIds to googleIds**
        const commentLikedByGoogleIds = await convertLikedByToGoogleIds(comment.likedBy || []);
        return {
          _id: comment._id,
          text: comment.text,
          userId: comment.user?.googleId || comment.user?._id || '',
          userName: comment.user?.name || '',
          createdAt: comment.createdAt,
          likes: comment.likes || 0,
          likedBy: commentLikedByGoogleIds // **FIXED: Use googleIds for comment likes**
        };
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

    // **CRITICAL: Invalidate ALL caches when video is unliked to ensure fresh data**
    // This ensures likes persist even after app restart, just like Instagram/YouTube
    if (redisService.getConnectionStatus()) {
      try {
        // Clear all possible cache patterns that might contain this video
        await invalidateCache([
          'videos:feed:*', // Clear all video feed caches
          'videos:unwatched:ids:*', // Clear unwatched IDs cache (feed uses this)
          VideoCacheKeys.single(videoId), // Clear single video cache
          VideoCacheKeys.all(), // Clear all video caches
          `videos:user:${video.uploader?.toString()}`, // Clear uploader's video cache
          `videos:user:*`, // Clear all user video caches
        ]);
        console.log('🧹 Cache invalidated after unlike - ensuring fresh data on next fetch');
      } catch (cacheError) {
        console.error('⚠️ Error invalidating cache (non-critical):', cacheError.message);
        // Don't fail the request if cache invalidation fails
      }
    }

    // Return the updated video with populated fields
    const updatedVideo = await Video.findById(videoId)
      .populate('uploader', 'name profilePic googleId')
      .populate('comments.user', 'name profilePic googleId');

    const videoObj = updatedVideo.toObject();
    
    // **FIX: Convert likedBy ObjectIds to googleIds**
    const likedByGoogleIds = await convertLikedByToGoogleIds(videoObj.likedBy || []);
    
    const transformedVideo = {
      _id: videoObj._id?.toString(),
      videoName: videoObj.videoName || '',
      videoUrl: videoObj.videoUrl || videoObj.hlsMasterPlaylistUrl || videoObj.hlsPlaylistUrl || '',
      thumbnailUrl: videoObj.thumbnailUrl || '',
      likes: parseInt(videoObj.likes) || 0,
      views: parseInt(videoObj.views) || 0,
      shares: parseInt(videoObj.shares) || 0,
      description: videoObj.description || '',
      // **FIX: Use googleId as id for correct profile navigation**
      uploader: {
        id: videoObj.uploader?.googleId?.toString() || videoObj.uploader?._id?.toString() || '',
        _id: videoObj.uploader?._id?.toString() || '',
        googleId: videoObj.uploader?.googleId?.toString() || '',
        name: videoObj.uploader?.name || 'Unknown',
        profilePic: videoObj.uploader?.profilePic || '',
      },
      uploadedAt: videoObj.uploadedAt?.toISOString?.() || new Date().toISOString(),
      likedBy: likedByGoogleIds, // **FIXED: Use googleIds instead of ObjectIds**
      videoType: videoObj.videoType || 'reel',
      aspectRatio: parseFloat(videoObj.aspectRatio) || 9/16,
      duration: parseInt(videoObj.duration) || 0,
      comments: await Promise.all((videoObj.comments || []).map(async (comment) => {
        // **FIX: Convert comment likedBy ObjectIds to googleIds**
        const commentLikedByGoogleIds = await convertLikedByToGoogleIds(comment.likedBy || []);
        return {
          _id: comment._id,
          text: comment.text,
          userId: comment.user?.googleId || comment.user?._id || '',
          userName: comment.user?.name || '',
          createdAt: comment.createdAt,
          likes: comment.likes || 0,
          likedBy: commentLikedByGoogleIds // **FIXED: Use googleIds for comment likes**
        };
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
    
    // **FIX: Convert likedBy ObjectIds to googleIds**
    const likedByGoogleIds = await convertLikedByToGoogleIds(videoObj.likedBy || []);
    
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
      likedBy: likedByGoogleIds, // **FIXED: Use googleIds instead of ObjectIds**
      // **FIXED: Transform comments to match Flutter app expectations**
      comments: await Promise.all((videoObj.comments || []).map(async (comment) => {
        // **FIX: Convert comment likedBy ObjectIds to googleIds**
        const commentLikedByGoogleIds = await convertLikedByToGoogleIds(comment.likedBy || []);
        return {
          _id: comment._id,
          text: comment.text,
          userId: comment.user?.googleId || comment.user?._id || '',
          userName: comment.user?.name || '',
          createdAt: comment.createdAt,
          likes: comment.likes || 0,
          likedBy: commentLikedByGoogleIds // **FIXED: Use googleIds for comment likes**
        };
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
    console.log('💬 Comment POST request received:', {
      videoId: req.params.id,
      body: req.body,
      timestamp: new Date().toISOString()
    });

    const { userId, text } = req.body;

    if (!userId || !text) {
      console.log('❌ Missing required fields:', { userId: !!userId, text: !!text });
      return res.status(400).json({ error: 'Missing required fields: userId and text' });
    }

    const user = await User.findOne({ googleId: userId });
    if (!user) {
      console.log('❌ User not found with googleId:', userId);
      return res.status(404).json({ error: 'User not found' });
    }

    console.log('✅ User found:', { userId: user._id, googleId: user.googleId });

    // **FIX: Create a separate Comment document first**
    const newComment = new Comment({
      user: user._id,
      text,
      createdAt: new Date(),
    });

    console.log('💬 Creating comment:', { user: user._id, text });

    // Save the comment document
    const savedComment = await newComment.save();
    console.log('✅ Comment saved:', { commentId: savedComment._id });

    // **FIX: Push the Comment's ObjectId to the Video's comments array**
    const video = await Video.findByIdAndUpdate(
      req.params.id,
      { $push: { comments: savedComment._id } },
      { new: true }
    ).populate({
      path: 'comments',
      populate: {
        path: 'user',
        select: 'name profilePic googleId'
      }
    });

    console.log('✅ Video updated with comment:', { videoId: video._id, commentsCount: video.comments.length });
    console.log('🔍 Video comments after population:', video.comments.map(c => ({
      _id: c._id,
      text: c.text,
      user: c.user,
      hasUser: !!c.user,
      userType: typeof c.user
    })));

    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    // Transform comments to match Flutter app expectations
    const videoObj = video.toObject();
    console.log('🔍 Comment transformation - Raw comments:', videoObj.comments.map(c => ({
      _id: c._id,
      text: c.text,
      user: c.user,
      userType: typeof c.user,
      userName: c.user?.name,
      userGoogleId: c.user?.googleId
    })));
    
    const transformedVideo = {
      ...videoObj,
      comments: await Promise.all((videoObj.comments || []).map(async (comment) => {
        // **FIX: Convert comment likedBy ObjectIds to googleIds**
        const commentLikedByGoogleIds = await convertLikedByToGoogleIds(comment.likedBy || []);
        return {
          _id: comment._id,
          text: comment.text,
          userId: comment.user?.googleId || comment.user?._id || '',
          userName: comment.user?.name || 'User',
          createdAt: comment.createdAt,
          likes: comment.likes || 0,
          likedBy: commentLikedByGoogleIds // **FIXED: Use googleIds for comment likes**
        };
      }))
    };
    
    console.log('🔍 Comment transformation - Transformed comments:', transformedVideo.comments);

    // **FIX: Return comments array directly to match frontend expectations**
    console.log('📤 Sending response:', { commentsCount: transformedVideo.comments.length });
    res.json(transformedVideo.comments);
  } catch (err) {
    console.error('Error adding comment:', err);
    res.status(500).json({ error: 'Failed to add comment', details: err.message });
  }
});

// **NEW: Get comments for a video**
router.get('/:videoId/comments', async (req, res) => {
  try {
    console.log('💬 Comment GET request received:', {
      videoId: req.params.videoId,
      timestamp: new Date().toISOString()
    });

    const video = await Video.findById(req.params.videoId)
      .populate({
        path: 'comments',
        populate: {
          path: 'user',
          select: 'name profilePic googleId'
        }
      });

    if (!video) {
      console.log('❌ Video not found:', req.params.videoId);
      return res.status(404).json({ error: 'Video not found' });
    }

    console.log('✅ Video found with comments:', { 
      videoId: video._id, 
      commentsCount: video.comments.length 
    });

    // Transform comments to match Flutter app expectations
    const transformedComments = await Promise.all((video.comments || []).map(async (comment) => {
      // **FIX: Convert comment likedBy ObjectIds to googleIds**
      const commentLikedByGoogleIds = await convertLikedByToGoogleIds(comment.likedBy || []);
      return {
        _id: comment._id,
        text: comment.text,
        userId: comment.user?.googleId || comment.user?._id || '',
        userName: comment.user?.name || 'User',
        userProfilePic: comment.user?.profilePic || '',
        createdAt: comment.createdAt,
        likes: comment.likes || 0,
        likedBy: commentLikedByGoogleIds // **FIXED: Use googleIds for comment likes**
      };
    }));

    console.log('📤 Sending comments response:', { 
      commentsCount: transformedComments.length,
      comments: transformedComments.map(c => ({
        _id: c._id,
        text: c.text,
        userName: c.userName,
        userId: c.userId
      }))
    });

    res.json(transformedComments);
  } catch (err) {
    console.error('❌ Error fetching comments:', err);
    res.status(500).json({ error: 'Failed to fetch comments', details: err.message });
  }
});

// **NEW: Delete comment route**
router.delete('/:videoId/comments/:commentId', async (req, res) => {
  try {
    console.log('🗑️ Comment DELETE request received:', {
      videoId: req.params.videoId,
      commentId: req.params.commentId,
      timestamp: new Date().toISOString()
    });

    const { userId } = req.body;

    if (!userId) {
      console.log('❌ Missing userId in request body');
      return res.status(400).json({ error: 'Missing required field: userId' });
    }

    // Find the user
    const user = await User.findOne({ googleId: userId });
    if (!user) {
      console.log('❌ User not found with googleId:', userId);
      return res.status(404).json({ error: 'User not found' });
    }

    console.log('✅ User found:', { userId: user._id, googleId: user.googleId });

    // Find the comment and verify ownership
    const comment = await Comment.findById(req.params.commentId);
    if (!comment) {
      console.log('❌ Comment not found:', req.params.commentId);
      return res.status(404).json({ error: 'Comment not found' });
    }

    // Check if the user owns this comment
    if (comment.user.toString() !== user._id.toString()) {
      console.log('❌ User does not own this comment:', {
        commentOwner: comment.user.toString(),
        requestingUser: user._id.toString()
      });
      return res.status(403).json({ error: 'You can only delete your own comments' });
    }

    console.log('✅ Comment ownership verified, proceeding with deletion');

    // Remove comment from video's comments array
    const video = await Video.findByIdAndUpdate(
      req.params.videoId,
      { $pull: { comments: req.params.commentId } },
      { new: true }
    ).populate({
      path: 'comments',
      populate: {
        path: 'user',
        select: 'name profilePic googleId'
      }
    });

    if (!video) {
      console.log('❌ Video not found:', req.params.videoId);
      return res.status(404).json({ error: 'Video not found' });
    }

    // Delete the comment document
    await Comment.findByIdAndDelete(req.params.commentId);

    console.log('✅ Comment deleted successfully:', {
      commentId: req.params.commentId,
      videoId: req.params.videoId,
      remainingComments: video.comments.length
    });

    // Transform comments to match frontend expectations
    const videoObj = video.toObject();
    const transformedVideo = {
      ...videoObj,
      comments: await Promise.all((videoObj.comments || []).map(async (comment) => {
        // **FIX: Convert comment likedBy ObjectIds to googleIds**
        const commentLikedByGoogleIds = await convertLikedByToGoogleIds(comment.likedBy || []);
        return {
          _id: comment._id,
          text: comment.text,
          userId: comment.user?.googleId || comment.user?._id || '',
          userName: comment.user?.name || '',
          createdAt: comment.createdAt,
          likes: comment.likes || 0,
          likedBy: commentLikedByGoogleIds // **FIXED: Use googleIds for comment likes**
        };
      }))
    };

    // Return updated comments array
    console.log('📤 Sending updated comments:', { commentsCount: transformedVideo.comments.length });
    res.json(transformedVideo.comments);

  } catch (err) {
    console.error('❌ Error deleting comment:', err);
    res.status(500).json({ error: 'Failed to delete comment', details: err.message });
  }
});

// **NEW: Increment video view count (Instagram Reels style)**
router.post('/:id/increment-view', async (req, res) => {
  try {
    const videoId = req.params.id;
    const { userId, duration = 2 } = req.body; // **CHANGED: Reduced from 4 to 2 seconds for more lenient view counting**

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

    // **NEW: Remove video reference from user's videos array**
    await User.findByIdAndUpdate(
      user._id,
      { $pull: { videos: videoId } },
      { new: true }
    );

    // **NEW: Invalidate cache when video is deleted**
    if (redisService.getConnectionStatus()) {
      await invalidateCache([
        'videos:feed:*', // Clear all video feed caches
        VideoCacheKeys.single(videoId), // Clear single video cache
        `videos:user:${user.googleId}`, // Clear user's video cache
        VideoCacheKeys.all() // Clear all video-related caches
      ]);
      console.log('🧹 Cache invalidated after video deletion');
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
    
    // **NEW: Remove video references from user's videos array**
    await User.findByIdAndUpdate(
      user._id,
      { $pull: { videos: { $in: videoIds } } },
      { new: true }
    );

    // **NEW: Invalidate cache when videos are bulk deleted**
    if (redisService.getConnectionStatus()) {
      await invalidateCache([
        'videos:feed:*', // Clear all video feed caches
        `videos:user:${user.googleId}`, // Clear user's video cache
        VideoCacheKeys.all() // Clear all video-related caches
      ]);
      console.log('🧹 Cache invalidated after bulk video deletion');
    }
    
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
    // **UPDATED: Sort by recommendation score (finalScore) instead of createdAt**
    const videos = await Video.find({ 
      uploader: user._id,
      videoUrl: { $exists: true, $ne: null, $ne: '' }, // Ensure video URL exists and is not empty
      processingStatus: { $nin: ['failed', 'error'] } // Only exclude explicitly failed videos
    })
      .select('videoName videoUrl thumbnailUrl likes views shares uploader uploadedAt likedBy videoType aspectRatio duration comments link description hlsMasterPlaylistUrl hlsPlaylistUrl isHLSEncoded finalScore')
      .populate('uploader', 'name profilePic googleId')
      .populate('comments.user', 'name profilePic googleId')
      .sort({ finalScore: -1, createdAt: -1 }) // Sort by recommendation score first, then by creation date
      .lean();
    
    // **NEW: Filter out videos with invalid uploader references**
    const validVideos = videos.filter(video => {
      return video.uploader && 
             video.uploader._id && 
             video.uploader.name && 
             video.uploader.name.trim() !== '';
    });
    
    console.log('🎬 Found videos count:', videos.length);
    console.log(`🎬 Valid videos count: ${validVideos.length}`);
    
    // **NEW: Sync user.videos array with actual valid videos**
    if (validVideos.length !== videos.length) {
      console.log('🔄 Syncing user.videos array with valid videos...');
      const validVideoIds = validVideos.map(v => v._id);
      await User.findByIdAndUpdate(user._id, { 
        $set: { videos: validVideoIds } 
      });
      console.log(`✅ Updated user.videos array: ${videos.length} -> ${validVideos.length} videos`);
    }
    
    if (validVideos.length === 0) {
      console.log('⚠️ No valid videos found for user:', user.name);
    }

    // Transform videos to match frontend expectations
    // **FIX: Convert to async to handle likedBy conversion**
    const transformedVideos = await Promise.all(validVideos.map(async (video) => {
      const videoObj = video;
      
      // **FIX: Convert likedBy ObjectIds to googleIds**
      const likedByGoogleIds = await convertLikedByToGoogleIds(videoObj.likedBy || []);
      
      const result = {
        _id: videoObj._id?.toString(),
        videoName: (videoObj.videoName && videoObj.videoName.toString().trim()) || 'Untitled Video',
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
        // **FIX: Use googleId as id for correct profile navigation**
        uploader: {
          id: videoObj.uploader?.googleId?.toString() || videoObj.uploader?._id?.toString() || '',
          _id: videoObj.uploader?._id?.toString() || '',
          googleId: videoObj.uploader?.googleId?.toString() || '',
          name: videoObj.uploader?.name || 'Unknown User',
          profilePic: videoObj.uploader?.profilePic || ''
        },
        hlsMasterPlaylistUrl: videoObj.hlsMasterPlaylistUrl || null,
        hlsPlaylistUrl: videoObj.hlsPlaylistUrl || null,
        isHLSEncoded: videoObj.isHLSEncoded || false,
        likedBy: likedByGoogleIds, // **FIXED: Use googleIds instead of ObjectIds**
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
    }));

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

// **NEW: Cleanup orphaned videos (videos with invalid uploader references)**
router.post('/cleanup-orphaned', verifyToken, async (req, res) => {
  try {
    console.log('🧹 Starting orphaned videos cleanup...');
    
    // Find videos with invalid uploader references
    const orphanedVideos = await Video.find({
      $or: [
        { uploader: { $exists: false } },
        { uploader: null },
        { uploader: { $type: 'string' } } // Invalid ObjectId type
      ]
    });
    
    console.log(`🧹 Found ${orphanedVideos.length} orphaned videos`);
    
    if (orphanedVideos.length === 0) {
      return res.json({ 
        success: true, 
        message: 'No orphaned videos found',
        deletedCount: 0
      });
    }
    
    // Delete orphaned videos
    const orphanedIds = orphanedVideos.map(v => v._id);
    const deleteResult = await Video.deleteMany({ _id: { $in: orphanedIds } });
    
    console.log(`✅ Cleanup successful: ${deleteResult.deletedCount} orphaned videos deleted`);
    
    res.json({ 
      success: true, 
      message: `${deleteResult.deletedCount} orphaned videos deleted successfully`,
      deletedCount: deleteResult.deletedCount,
      orphanedVideoIds: orphanedIds
    });
    
  } catch (error) {
    console.error('❌ Error cleaning up orphaned videos:', error);
    res.status(500).json({ 
      error: 'Failed to cleanup orphaned videos',
      details: error.message 
    });
  }
});


// **NEW: Cloudinary video processing function (Cloudinary → R2)**
async function processVideoHybrid(videoId, videoPath, videoName, userId) {
  try {
    console.log('🚀 Starting hybrid video processing (Cloudinary → R2) for:', videoId);
    
    // **NEW: Update status to processing**
    const video = await Video.findById(videoId);
    if (!video) {
      throw new Error('Video not found');
    }

    video.processingStatus = 'processing';
    video.processingProgress = 10;
    await video.save();
    console.log('📊 Processing status updated to 10%');

    // **NEW: Lazy load hybrid service to ensure env vars are loaded**
    if (!hybridVideoService) {
      const { default: service } = await import('../services/hybridVideoService.js');
      hybridVideoService = service;
    }
    
    // **NEW: Process video using hybrid approach**
    const hybridResult = await hybridVideoService.processVideoHybrid(
      videoPath, 
      videoName, 
      userId
    );

    console.log('✅ Hybrid processing completed');
    console.log('🔗 Hybrid result:', hybridResult);

    // **NEW: Update video record with R2 URLs**
    video.videoUrl = hybridResult.videoUrl; // R2 video URL with FREE bandwidth
    video.thumbnailUrl = hybridResult.thumbnailUrl; // R2 thumbnail URL
    
    // **NEW: Clear old quality URLs (single format now)**
    video.preloadQualityUrl = null;
    video.lowQualityUrl = hybridResult.videoUrl; // Same as main URL (480p)
    video.mediumQualityUrl = null;
    video.highQualityUrl = null;
    
    video.processingStatus = 'completed';
    video.processingProgress = 100;

    // **FIX: Preserve original aspect ratio and dimensions from hybridResult**
    // Use original resolution from hybridResult if available, otherwise get from video file
    if (hybridResult.originalVideoInfo && hybridResult.originalVideoInfo.width && hybridResult.originalVideoInfo.height) {
      // Use original resolution from processing result
      video.aspectRatio = hybridResult.aspectRatio || hybridResult.originalVideoInfo.aspectRatio;
      video.originalResolution = {
        width: hybridResult.originalVideoInfo.width,
        height: hybridResult.originalVideoInfo.height
      };
      console.log(`📐 Preserved original dimensions from result: ${hybridResult.originalVideoInfo.width}x${hybridResult.originalVideoInfo.height}, aspect ratio: ${video.aspectRatio}`);
    } else if (!video.originalResolution || !video.originalResolution.width) {
      // Fallback: Get original video info if not already in video record
      if (!hybridVideoService) {
        const { default: service } = await import('../services/hybridVideoService.js');
        hybridVideoService = service;
      }
      const originalVideoInfo = await hybridVideoService.getOriginalVideoInfo(videoPath);
      
      // Preserve original aspect ratio and dimensions
      if (originalVideoInfo.width && originalVideoInfo.height) {
        video.aspectRatio = originalVideoInfo.aspectRatio;
        video.originalResolution = {
          width: originalVideoInfo.width,
          height: originalVideoInfo.height
        };
        console.log(`📐 Preserved original dimensions from file: ${originalVideoInfo.width}x${originalVideoInfo.height}, aspect ratio: ${originalVideoInfo.aspectRatio}`);
      }
    } else {
      // Use existing aspect ratio if dimensions already saved
      console.log(`📐 Using existing aspect ratio: ${video.aspectRatio}, dimensions: ${video.originalResolution.width}x${video.originalResolution.height}`);
    }
    
    // **NEW: Add hybrid metadata**
    video.originalSize = hybridResult.size || video.originalSize;
    video.originalFormat = 'mp4';

    // **FIX: Use original resolution instead of calculating processed dimensions**
    // Videos are now encoded at original resolution, not scaled to 480p
    const processedWidth = video.originalResolution?.width || hybridResult.width || 854;
    const processedHeight = video.originalResolution?.height || hybridResult.height || 480;

    // **NEW: Add single quality version**
    video.qualitiesGenerated = [{
      quality: 'optimized',
      url: hybridResult.videoUrl,
      size: hybridResult.size,
      resolution: {
        width: processedWidth,
        height: processedHeight
      },
      bitrate: '800k',
      generatedAt: new Date()
    }];

    await video.save();
    console.log('🎉 Hybrid video processing completed successfully!');
    console.log('💰 Cost savings: 93% vs previous setup');
    console.log('📊 Final video data:', {
      id: video._id,
      videoUrl: video.videoUrl,
      thumbnailUrl: video.thumbnailUrl,
      quality: '480p optimized',
      storage: 'Cloudflare R2',
      bandwidth: 'FREE',
      status: video.processingStatus
    });

  } catch (error) {
    console.error('❌ Error in hybrid video processing:', error);
    
    try {
      // **NEW: Update video status and try fallback URL**
      const video = await Video.findById(videoId);
      if (video) {
        // Try to create a fallback URL using the local file
        const isProduction = process.env.NODE_ENV === 'production';
        const baseUrl = isProduction 
          ? 'https://snehayog.site'
          : (process.env.SERVER_URL || 'http://192.168.0.199:5001');
        
        // Create fallback URL for the uploaded file
        const fallbackUrl = `${baseUrl}/${videoPath.replace(/\\/g, '/')}`;
        
        video.videoUrl = fallbackUrl;
        video.processingStatus = 'completed'; // Mark as completed with fallback
        video.processingError = `Hybrid processing failed, using fallback: ${error.message}`;
        await video.save();
        
        console.log('⚠️ Using fallback URL for video:', fallbackUrl);
      }
    } catch (updateError) {
      console.error('❌ Failed to update video status:', updateError);
    }
  }
}

// **NEW: Test video URL accessibility**
router.get('/test-video-url/:videoId', async (req, res) => {
  try {
    const videoId = req.params.videoId;
    console.log('🔍 Testing video URL for video ID:', videoId);
    
    const video = await Video.findById(videoId);
    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }
    
    console.log('📹 Video details:', {
      id: video._id,
      name: video.videoName,
      videoUrl: video.videoUrl,
      thumbnailUrl: video.thumbnailUrl,
      hlsPlaylistUrl: video.hlsPlaylistUrl,
      hlsMasterPlaylistUrl: video.hlsMasterPlaylistUrl,
      isHLSEncoded: video.isHLSEncoded,
      processingStatus: video.processingStatus,
      processingProgress: video.processingProgress
    });
    
    // Test video URL accessibility
    const testResults = {
      videoId: video._id,
      videoName: video.videoName,
      urls: {
        videoUrl: video.videoUrl,
        thumbnailUrl: video.thumbnailUrl,
        hlsPlaylistUrl: video.hlsPlaylistUrl,
        hlsMasterPlaylistUrl: video.hlsMasterPlaylistUrl
      },
      processing: {
        status: video.processingStatus,
        progress: video.processingProgress,
        error: video.processingError
      },
      isHLSEncoded: video.isHLSEncoded,
      recommendations: []
    };
    
    // Check if video URL is accessible
    if (video.videoUrl) {
      try {
        const axios = (await import('axios')).default;
        const response = await axios.head(video.videoUrl, { timeout: 10000 });
        testResults.urlAccessibility = {
          videoUrl: {
            accessible: true,
            statusCode: response.status,
            contentType: response.headers['content-type']
          }
        };
      } catch (urlError) {
        testResults.urlAccessibility = {
          videoUrl: {
            accessible: false,
            error: urlError.message
          }
        };
        testResults.recommendations.push('Video URL is not accessible - check R2 configuration');
      }
    } else {
      testResults.recommendations.push('No video URL found - video processing may have failed');
    }
    
    // Check thumbnail URL
    if (video.thumbnailUrl) {
      try {
        const axios = (await import('axios')).default;
        const response = await axios.head(video.thumbnailUrl, { timeout: 5000 });
        testResults.urlAccessibility.thumbnailUrl = {
          accessible: true,
          statusCode: response.status,
          contentType: response.headers['content-type']
        };
      } catch (thumbError) {
        testResults.urlAccessibility.thumbnailUrl = {
          accessible: false,
          error: thumbError.message
        };
        testResults.recommendations.push('Thumbnail URL is not accessible');
      }
    }
    
    // Add specific recommendations based on processing status
    if (video.processingStatus === 'failed' || video.processingStatus === 'error') {
      testResults.recommendations.push('Video processing failed - check server logs for details');
    } else if (video.processingStatus === 'pending' || video.processingStatus === 'processing') {
      testResults.recommendations.push('Video is still processing - wait for completion');
    } else if (video.processingStatus === 'completed' && !video.videoUrl) {
      testResults.recommendations.push('Processing completed but no video URL - check R2 upload');
    }
    
    res.json(testResults);
    
  } catch (error) {
    console.error('❌ Error testing video URL:', error);
    res.status(500).json({ 
      error: 'Failed to test video URL',
      details: error.message 
    });
  }
});

// **NEW: Cleanup endpoint to remove only recently uploaded videos that don't play**
router.post('/cleanup-broken-videos', verifyToken, async (req, res) => {
  try {
    console.log('🧹 Starting cleanup of recently broken videos...');
    
    // Only target videos uploaded in the last 24 hours that have issues
    const oneDayAgo = new Date(Date.now() - 24 * 60 * 60 * 1000);
    
    // Find recently uploaded videos that are broken or have invalid URLs
    const brokenVideos = await Video.find({
      $and: [
        { uploadedAt: { $gte: oneDayAgo } }, // Only recent videos (last 24 hours)
        {
          $or: [
            { processingStatus: 'failed' },
            { processingStatus: 'error' },
            { videoUrl: { $exists: false } },
            { videoUrl: null },
            { videoUrl: '' },
            { uploader: { $exists: false } },
            { uploader: null }
          ]
        }
      ]
    });
    
    console.log(`🧹 Found ${brokenVideos.length} recently broken videos to clean up`);
    
    if (brokenVideos.length === 0) {
      return res.json({ 
        success: true, 
        message: 'No recently broken videos found',
        deletedCount: 0
      });
    }
    
    // Get video IDs for cleanup
    const brokenVideoIds = brokenVideos.map(v => v._id);
    
    // Remove video references from users' videos arrays
    await User.updateMany(
      { videos: { $in: brokenVideoIds } },
      { $pull: { videos: { $in: brokenVideoIds } } }
    );
    
    // Delete the broken videos
    const deleteResult = await Video.deleteMany({ _id: { $in: brokenVideoIds } });
    
    console.log(`✅ Cleanup successful: ${deleteResult.deletedCount} recently broken videos deleted`);
    
    res.json({ 
      success: true, 
      message: `${deleteResult.deletedCount} recently broken videos deleted successfully`,
      deletedCount: deleteResult.deletedCount,
      brokenVideoIds: brokenVideoIds
    });
    
  } catch (error) {
    console.error('❌ Error cleaning up broken videos:', error);
    res.status(500).json({ 
      error: 'Failed to cleanup broken videos',
      details: error.message 
    });
  }
});

// **NEW: Sync all users' video arrays with actual valid videos**
router.post('/sync-user-video-arrays', verifyToken, async (req, res) => {
  try {
    console.log('🔄 Starting sync of all users\' video arrays...');
    
    const users = await User.find({ videos: { $exists: true, $ne: [] } });
    let totalUpdated = 0;
    let totalUsers = users.length;
    
    for (const user of users) {
      try {
        // Get actual valid videos for this user
        const validVideos = await Video.find({ 
          uploader: user._id,
          videoUrl: { $exists: true, $ne: null, $ne: '' },
          processingStatus: { $nin: ['failed', 'error'] }
        }).select('_id');
        
        const validVideoIds = validVideos.map(v => v._id);
        
        // Update user's videos array if different
        if (validVideoIds.length !== user.videos.length) {
          await User.findByIdAndUpdate(user._id, { 
            $set: { videos: validVideoIds } 
          });
          totalUpdated++;
          console.log(`✅ Updated user ${user.name}: ${user.videos.length} -> ${validVideoIds.length} videos`);
        }
      } catch (userError) {
        console.error(`❌ Error syncing user ${user.name}:`, userError);
      }
    }
    
    console.log(`✅ Sync completed: ${totalUpdated}/${totalUsers} users updated`);
    
    res.json({ 
      success: true, 
      message: `Synced ${totalUpdated} out of ${totalUsers} users`,
      updatedUsers: totalUpdated,
      totalUsers: totalUsers
    });
    
  } catch (error) {
    console.error('❌ Error syncing user video arrays:', error);
    res.status(500).json({ 
      error: 'Failed to sync user video arrays',
      details: error.message 
    });
  }
});

// **NEW: Serve static video files**
router.use('/uploads', express.static('uploads', {
  maxAge: '1d', // Cache for 1 day
  etag: true,
  lastModified: true,
  setHeaders: (res, path) => {
    // Set appropriate headers for video files
    if (path.endsWith('.mp4')) {
      res.setHeader('Content-Type', 'video/mp4');
      res.setHeader('Accept-Ranges', 'bytes');
      res.setHeader('Cache-Control', 'public, max-age=86400'); // 1 day cache
    } else if (path.endsWith('.jpg') || path.endsWith('.jpeg')) {
      res.setHeader('Content-Type', 'image/jpeg');
      res.setHeader('Cache-Control', 'public, max-age=86400'); // 1 day cache
    }
  }
}));

export default router
