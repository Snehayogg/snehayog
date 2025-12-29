import express from 'express';
import multer from 'multer';
import mongoose from 'mongoose';
import Video from '../models/Video.js';
import User from '../models/User.js';
import Comment from '../models/Comment.js';
import WatchHistory from '../models/WatchHistory.js';
import RecommendationService from '../services/recommendationService.js';
import fs from 'fs'; 
import path from 'path';
import crypto from 'crypto';
import { verifyToken } from '../utils/verifytoken.js';
import redisService from '../services/redisService.js';
import { VideoCacheKeys, invalidateCache } from '../middleware/cacheMiddleware.js';
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


// **NEW: Cache Management Endpoints**
// GET /api/videos/cache/status - Check cache status
router.get('/cache/status', async (req, res) => {
  try {
    const { userId, platformId, videoType } = req.query;
    
    if (!redisService.getConnectionStatus()) {
      return res.json({
        redisConnected: false,
        message: 'Redis is not connected',
        cacheKeys: []
      });
    }

    const userIdentifier = userId || platformId;
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
    const { pattern, userId, platformId, videoType, clearAll } = req.body;
    
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
      // Clear based on user/platform
      const userIdentifier = userId || platformId;
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
      mediaType: 'video',
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

// **NEW: Create image-based feed entry (product image) without video processing**
// This allows product images to appear in Yug feed & profile like regular videos.
router.post('/image', verifyToken, async (req, res) => {
  try {
    const { imageUrl, videoName, link, videoType, category, tags } = req.body || {};

    if (!imageUrl || typeof imageUrl !== 'string' || !imageUrl.trim()) {
      return res.status(400).json({ error: 'imageUrl is required' });
    }

    const trimmedUrl = imageUrl.trim();
    if (!/^https?:\/\//i.test(trimmedUrl)) {
      return res.status(400).json({ error: 'imageUrl must be a valid HTTP/HTTPS URL' });
    }

    const googleId = req.user.googleId;
    if (!googleId) {
      return res.status(401).json({ error: 'Google ID not found in token' });
    }

    const user = await User.findOne({ googleId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const now = new Date();

    const video = new Video({
      videoName: (videoName && String(videoName).trim()) || 'Product Image',
      description: '',
      link: (link && String(link).trim()) || '',
      videoUrl: trimmedUrl,
      thumbnailUrl: trimmedUrl,
      uploader: user._id,
      videoType: (videoType && String(videoType).toLowerCase() === 'vayu') ? 'vayu' : 'yog',
      mediaType: 'image',
      aspectRatio: 9 / 16,
      duration: 0,
      processingStatus: 'completed',
      processingProgress: 100,
      isHLSEncoded: false,
      likes: 0,
      views: 0,
      shares: 0,
      likedBy: [],
      comments: [],
      uploadedAt: now,
      createdAt: now,
      updatedAt: now,
      ...(category ? { category: String(category).toLowerCase().trim() } : {}),
      ...(Array.isArray(tags) && tags.length
        ? { tags: tags.map((t) => String(t).toLowerCase().trim()).filter(Boolean) }
        : {}),
    });

    await video.save();
    user.videos.push(video._id);
    await user.save();

    if (redisService.getConnectionStatus()) {
      await invalidateCache([
        'videos:feed:*',
        `videos:user:${user.googleId}`,
        VideoCacheKeys.all(),
      ]);
      console.log('🧹 Cache invalidated after image feed entry creation');
    }

    return res.status(201).json({
      success: true,
      message: 'Image feed entry created successfully',
      video: {
        id: video._id,
        videoName: video.videoName,
        videoUrl: video.videoUrl,
        thumbnailUrl: video.thumbnailUrl,
        link: video.link,
        videoType: video.videoType,
        mediaType: video.mediaType,
        uploadedAt: video.uploadedAt,
      },
    });
  } catch (error) {
    console.error('❌ Error creating image feed entry:', error);
    return res.status(500).json({
      error: 'Failed to create image feed entry',
      details: error.message,
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

    // **OPTIMIZED: Cache user profile data**
    const userProfileCacheKey = `user:profile:${googleId}`;
    let user = null;
    
    if (redisService.getConnectionStatus()) {
      user = await redisService.get(userProfileCacheKey);
      if (user) {
        console.log(`⚡ User Profile Cache HIT: ${userProfileCacheKey}`);
      }
    }
    
    if (!user) {
      user = await User.findOne({ googleId: googleId }).lean();
      if (!user) {
        console.log('❌ User not found for googleId:', googleId);
        return res.status(404).json({ error: 'User not found' });
      }
      
      // Cache user profile for 10 minutes
      if (redisService.getConnectionStatus()) {
        await redisService.set(userProfileCacheKey, user, 600);
        console.log(`💾 User Profile Cache SET: ${userProfileCacheKey} (10min TTL)`);
      }
    }

    console.log('✅ Found user:', {
      id: user._id,
      name: user.name,
      googleId: user.googleId,
      videosArrayLength: user.videos?.length || 0
    });

    // **IMPROVED: Get videos directly from Video collection using uploader field**
    const videos = await Video.find({ 
      uploader: user._id,
      videoUrl: { $exists: true, $ne: null, $ne: '' }, // Ensure video URL exists and is not empty
      processingStatus: { $nin: ['failed', 'error'] } // Only exclude explicitly failed videos
    })
      .populate('uploader', 'name profilePic googleId')
      .sort({ createdAt: -1 }); // Simple: newest first

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
        mediaType: videoObj.mediaType || 'video',
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

// **REMOVED: Simple route was blocking the main personalized feed route**
// The main route below (line ~1101) handles all feed logic including:
// - Watch history filtering
// - Personalized feed
// - Creator diversity
// - Regular feed fallback


// Get all videos (optimized for performance) - SUPPORTS MP4 AND HLS
// **NEW: Personalized feed with watch history filtering**
// **NEW: Redis caching integrated for 10x faster response**
// **NOTE: verifyToken is optional - if provided, returns personalized feed; otherwise, regular feed**
router.get('/', async (req, res) => {
  try {
    // **NEW: Log that endpoint was hit**
    console.log('═══════════════════════════════════════════════════════════');
    console.log('📹 GET /api/videos endpoint called');
    console.log('📹 Request query:', req.query);
    console.log('📹 Request headers:', {
      authorization: req.headers.authorization ? 'Present' : 'Missing',
      'x-device-id': req.headers['x-device-id'] || 'Missing',
      'user-agent': req.headers['user-agent']?.substring(0, 50) || 'Unknown',
    });
    console.log('═══════════════════════════════════════════════════════════');
    
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

    const { videoType, page = 1, limit = 10, platformId, clearSession } = req.query;
    
    // **BACKEND-FIRST: Use userId for authenticated users, platformId for anonymous**
    // After login, the frontend should call `/api/videos/sync-watch-history` ONCE to merge histories,
    // then this route will always prioritize userId (googleId) and only use platformId as a fallback.
    const userIdentifier = userId || platformId; // Primary identifier used for personalization
    const isAuthenticated = !!userId;
    const identitySource = userId ? 'userId' : (platformId ? 'platformId' : 'none');
    
    // **NEW: Clear session state if requested (for seamless feed restart)**
    if (clearSession === 'true' && userIdentifier) {
      try {
        await redisService.clearSessionShownVideos(userIdentifier);
        console.log(`🧹 SESSION CLEAR: Cleared session shown videos for feed restart (userIdentifier: ${userIdentifier})`);
      } catch (clearErr) {
        console.log(`⚠️ SESSION CLEAR: Error clearing session state: ${clearErr.message}`);
      }
    }
    
    // **IDENTITY DEBUG: Log per-request identity info to detect flips between userId/platformId**
    console.log('📹 Fetching videos...', { 
      videoType, 
      page, 
      limit, 
      userId: userId || null,
      platformId: platformId || null,
      userIdentifier: userIdentifier || null,
      identitySource,
      hasBothIds: !!(userId && platformId),
      idsMatch: userId && platformId ? userId === platformId : null
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
    // **RELAXED: Show all videos with valid uploader, exclude only failed ones**
    // This ensures all 400+ videos appear in feed
    const baseQueryFilter = {
      uploader: { $exists: true, $ne: null },
      processingStatus: { $ne: 'failed' }, // Only exclude explicitly failed videos
      // Video URL can be videoUrl OR hlsMasterPlaylistUrl OR hlsPlaylistUrl
      $or: [
        { videoUrl: { $exists: true, $ne: null, $ne: '' } },
        { hlsMasterPlaylistUrl: { $exists: true, $ne: null, $ne: '' } },
        { hlsPlaylistUrl: { $exists: true, $ne: null, $ne: '' } }
      ]
    };
    
    // **DEBUG: Log total videos count to diagnose feed issues**
    try {
      const totalVideosInDB = await Video.countDocuments({});
      const matchingBaseFilter = await Video.countDocuments(baseQueryFilter);
      console.log(`📊 Total videos in database: ${totalVideosInDB}`);
      console.log(`📊 Videos matching base filter (completed + valid URL): ${matchingBaseFilter}`);
      console.log(`📊 Excluded by base filter: ${totalVideosInDB - matchingBaseFilter}`);
    } catch (err) {
      console.log(`⚠️ Error counting videos: ${err.message}`);
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
    let unwatchedVideoIds = []; // kept for logging compatibility
    let watchedVideoIds = []; // kept for logging compatibility
    
    // **OPTIMIZED: Try feed cache first (short TTL for freshness while reducing DB load)**
    const feedCacheKey = `feed:${userIdentifier || 'anonymous'}:${videoType || 'all'}:${pageNum}`;
    let cachedFeed = null;
    
    if (redisService.getConnectionStatus()) {
      cachedFeed = await redisService.get(feedCacheKey);
      if (cachedFeed) {
        console.log(`⚡ Feed Cache HIT: ${feedCacheKey}`);
        return res.json(cachedFeed);
      }
      console.log(`💾 Feed Cache MISS: ${feedCacheKey}`);
    }
    
    // **PERSONALIZED LRU FEED: All yog videos in a loop (unwatched first, then oldest watched)**
    if (userIdentifier) {
      console.log(
        '🎯 Using LRU-style personalized feed for user:',
        userIdentifier,
        isAuthenticated ? '(authenticated)' : '(anonymous)',
      );

      // 1) Determine all identities to check for watch history
      // **IMPROVED: Better identity matching - check both userId and platformId comprehensively**
      const userIdsToCheck = [];
      if (userId) userIdsToCheck.push(userId);
      if (platformId) userIdsToCheck.push(platformId);
      if (userIdentifier && !userIdsToCheck.includes(userIdentifier)) {
        userIdsToCheck.push(userIdentifier);
      }
      
      // Remove duplicates
      const uniqueIdsToCheck = [...new Set(userIdsToCheck)];
      
      console.log(
        `🔍 WATCH HISTORY CHECK: Checking for identities:`,
        uniqueIdsToCheck,
        `(userId: ${userId || 'none'}, platformId: ${platformId || 'none'})`,
      );

      // 2) Build a map: videoId -> oldest lastWatchedAt (timestamp)
      // **OPTIMIZED: Cache watch history queries to reduce DB load**
      const historyMap = new Map(); // videoId (string) -> timestamp (number)
      const watchedVideoSet = new Set(); // Track all watched video IDs
      let historyEntries = [];
      
      try {
        if (uniqueIdsToCheck.length > 0) {
          // **OPTIMIZED: Try cache first, then DB**
          const watchHistoryCacheKey = `watch:history:${uniqueIdsToCheck.sort().join(':')}`;
          
          if (redisService.getConnectionStatus()) {
            const cachedHistory = await redisService.get(watchHistoryCacheKey);
            if (cachedHistory && Array.isArray(cachedHistory)) {
              historyEntries = cachedHistory;
              console.log(
                `⚡ Watch History Cache HIT: ${historyEntries.length} entries for identities:`,
                uniqueIdsToCheck,
              );
            } else {
              // Cache miss - fetch from DB
              historyEntries = await WatchHistory.find({
                userId: { $in: uniqueIdsToCheck },
          })
            .select('videoId lastWatchedAt userId')
            .lean();
              
              // Cache for 5 minutes (watch history changes infrequently)
              await redisService.set(watchHistoryCacheKey, historyEntries, 300);
              console.log(
                `💾 Watch History Cache SET: ${historyEntries.length} entries (5min TTL)`,
              );
            }
          } else {
            // Redis unavailable - fetch from DB
            historyEntries = await WatchHistory.find({
              userId: { $in: uniqueIdsToCheck },
            })
              .select('videoId lastWatchedAt userId')
              .lean();
          }

          console.log(
            `📊 LRU FEED: Loaded ${historyEntries.length} watch history entries for identities:`,
            uniqueIdsToCheck,
          );

          // **IMPROVED: Build comprehensive watch history map**
          // Consider a video watched if ANY identity has watched it
          for (const entry of historyEntries) {
            const vid = entry.videoId?.toString();
            if (!vid) continue;

            const currentTime = new Date(entry.lastWatchedAt || 0).getTime();
            const existingTime = historyMap.get(vid);

            // Keep the oldest watch time (most conservative - ensures video stays in "watched" category)
            if (existingTime === undefined || currentTime < existingTime) {
              historyMap.set(vid, currentTime);
            }
            watchedVideoSet.add(vid);
          }

          watchedVideoIds = Array.from(watchedVideoSet).map(
            (id) => new mongoose.Types.ObjectId(id),
          );
          console.log(
            `📊 LRU FEED: Unique watched videos found: ${historyMap.size} (from ${historyEntries.length} history entries)`,
          );
        } else {
          console.log(
            '⚠️ LRU FEED: No identities to check for watch history; treating all videos as never watched.',
          );
        }
      } catch (err) {
        console.error(
          `❌ LRU FEED: Error building history map: ${err.message}`,
        );
        // On error, treat all videos as unwatched (safer than showing watched videos)
      }
      
      // **OPTIMIZED: Session-Based Pagination State - Track videos shown in current session**
      // Uses Redis Set for O(1) lookups and better memory efficiency
      let sessionShownVideoIds = new Set();
      
      try {
        if (redisService.getConnectionStatus() && userIdentifier) {
          // Get videos already shown in this session (using Redis Set - more efficient)
          sessionShownVideoIds = await redisService.getSessionShownVideos(userIdentifier);
          if (sessionShownVideoIds.size > 0) {
            console.log(`📋 SESSION STATE: Found ${sessionShownVideoIds.size} videos already shown in current session (Redis Set)`);
          }
        }
      } catch (sessionErr) {
        console.log(`⚠️ SESSION STATE: Error checking session state (non-critical): ${sessionErr.message}`);
      }

      // 3) Fetch ALL matching videos for this feed (e.g., all yog videos)
      let allVideos = [];
      try {
        allVideos = await Video.find(baseQueryFilter)
          .select(
            'videoName videoUrl thumbnailUrl likes views shares uploader uploadedAt likedBy videoType aspectRatio duration comments link description hlsMasterPlaylistUrl hlsPlaylistUrl isHLSEncoded category tags keywords createdAt',
          )
          .populate('uploader', 'name profilePic googleId')
          .populate('comments.user', 'name profilePic googleId')
          .lean();

        // **FIX: Filter out invalid/null videos from database result**
        allVideos = (allVideos || []).filter(v => v && v._id);

        console.log(
          `📊 LRU FEED: Total videos matching base filter for user: ${allVideos.length}`,
        );
      } catch (err) {
        console.error(
          `❌ LRU FEED: Error fetching videos for personalized feed: ${err.message}`,
        );
        allVideos = []; // Ensure it's an array even on error
      }

      // **NEW: Try session-based recommendations first (like Instagram/YouTube)**
      // This learns from user's current session and recommends similar content using AI
      let sessionBasedVideos = [];
      try {
        if (userIdentifier && pageNum === 1) {
          // Only use session-based recommendations on first page
          console.log('🤖 Attempting session-based AI recommendations...');
          sessionBasedVideos = await RecommendationService.getSessionBasedRecommendations(
            userIdentifier,
            null, // No current video to exclude
            limitNum * 2 // Get more candidates for diversity filtering
          );
          
          if (sessionBasedVideos && sessionBasedVideos.length > 0) {
            console.log(`✅ Session-based recommendations found: ${sessionBasedVideos.length} videos`);
            
            // Apply diversity ordering
            sessionBasedVideos = RecommendationService.orderFeedWithDiversity(sessionBasedVideos, {
              randomness: 0.15,
              minCreatorSpacing: 2
            });
            
            // Limit to requested amount
            sessionBasedVideos = sessionBasedVideos.slice(0, limitNum);
            
            // Populate uploader and comments for session-based videos
            const sessionVideoIds = sessionBasedVideos.map(v => v._id);
            const populatedSessionVideos = await Video.find({
              _id: { $in: sessionVideoIds }
            })
              .select('videoName videoUrl thumbnailUrl likes views shares uploader uploadedAt likedBy videoType aspectRatio duration comments link description hlsMasterPlaylistUrl hlsPlaylistUrl isHLSEncoded category tags keywords createdAt')
              .populate('uploader', 'name profilePic googleId')
              .populate('comments.user', 'name profilePic googleId')
              .lean();
            
            // Maintain order from session-based recommendations
            const orderedSessionVideos = sessionVideoIds.map(id => 
              populatedSessionVideos.find(v => v._id.toString() === id.toString())
            ).filter(Boolean);
            
            if (orderedSessionVideos.length > 0) {
              console.log(`✅ Using ${orderedSessionVideos.length} session-based AI recommendations`);
              // Use session-based videos as primary feed
              finalVideos = orderedSessionVideos;
              
              // Mark these videos as shown in session
              if (redisService.getConnectionStatus() && userIdentifier) {
                const videoIdsToMark = orderedSessionVideos.map(v => v._id.toString());
                await redisService.setSessionShownVideos(userIdentifier, videoIdsToMark);
              }
              
              // Skip LRU feed logic and go to response
              const feedResponse = {
                videos: finalVideos,
                hasMore: true, // Assume more available
                page: pageNum,
                limit: limitNum,
                total: finalVideos.length,
                isPersonalized: true,
                isSessionBased: true // Flag to indicate AI recommendations
              };
              
              // Cache for 30 seconds
              if (redisService.getConnectionStatus() && finalVideos.length > 0) {
                await redisService.set(feedCacheKey, feedResponse, 30);
              }
              
              return res.json(feedResponse);
            }
          } else {
            console.log('⚠️ Session-based recommendations returned no results, using LRU feed');
          }
        }
      } catch (sessionError) {
        console.error('❌ Error in session-based recommendations (falling back to LRU):', sessionError.message);
        // Continue with LRU feed on error
      }

      // 4) Attach lastWatchedAt (null = never watched / highest priority)
      // **FIX: Filter out invalid videos before mapping**
      const videosWithHistory = allVideos
        .filter(v => v && v._id) // Remove invalid videos
        .map((video) => {
          const id = video._id.toString();
        const ts = id ? historyMap.get(id) : undefined;
        return {
          ...video,
          _lastWatchedAt: ts !== undefined ? ts : null, // null => never watched
        };
      });

      // 5) Separate unwatched and watched videos
      // **FIX: Filter out invalid videos (null/undefined/missing _id)**
      const unwatchedVideos = videosWithHistory.filter(v => v && v._id && v._lastWatchedAt === null);
      const watchedVideos = videosWithHistory.filter(v => v && v._id && v._lastWatchedAt !== null);
      
      // **PROFESSIONAL: Time-Based Freshness + Engagement Ranking**
      // Separate unwatched videos into: recent (7 days) and older
      const sevenDaysAgo = Date.now() - (7 * 24 * 60 * 60 * 1000);
      const recentUnwatched = [];
      const olderUnwatched = [];
      
      for (const video of unwatchedVideos) {
        const uploadTime = new Date(video.createdAt || video.uploadedAt || 0).getTime();
        if (uploadTime >= sevenDaysAgo) {
          recentUnwatched.push(video);
        } else {
          olderUnwatched.push(video);
        }
      }
      
      // **ENGAGEMENT-BASED RANKING: Score videos by engagement**
      const calculateEngagementScore = (video) => {
        const likes = video.likes || 0;
        const views = video.views || 0;
        const shares = video.shares || 0;
        const comments = (video.comments?.length || 0);
        
        // Weighted engagement score (likes are most valuable)
        const score = (likes * 2) + views + (shares * 1.5) + (comments * 1.2);
        return score;
      };
      
      // Sort recent unwatched by engagement (high to low)
      recentUnwatched.sort((a, b) => {
        const scoreA = calculateEngagementScore(a);
        const scoreB = calculateEngagementScore(b);
        return scoreB - scoreA; // Descending
      });
      
      // Sort older unwatched by engagement (high to low)
      olderUnwatched.sort((a, b) => {
        const scoreA = calculateEngagementScore(a);
        const scoreB = calculateEngagementScore(b);
        return scoreB - scoreA; // Descending
      });
      
      // **SESSION-BASED SHUFFLE: Use session-based seed for fresh order per session**
      // Each new session gets a fresh seed, but same session maintains consistent order
      // This gives fresh videos on app reopen while maintaining pagination consistency
      let seed = 0;
      const sessionSeedKey = `session:seed:${userIdentifier}:${videoType || 'all'}`;
      
      try {
        if (redisService.getConnectionStatus() && userIdentifier) {
          // Try to get existing session seed from Redis
          const cachedSeed = await redisService.get(sessionSeedKey);
          if (cachedSeed !== null && typeof cachedSeed === 'number') {
            seed = cachedSeed;
            console.log(`🎲 SESSION SEED: Using cached seed for session (seed: ${seed})`);
          } else {
            // New session - generate fresh seed based on timestamp
            const timestamp = Date.now();
            const seedString = `${userIdentifier}_${videoType || 'all'}_${timestamp}`;
            for (let i = 0; i < seedString.length; i++) {
              seed = ((seed << 5) - seed) + seedString.charCodeAt(i);
              seed = seed & seed; // Convert to 32-bit integer
            }
            // Cache seed for this session (24h TTL - same as session state)
            await redisService.set(sessionSeedKey, seed, 86400);
            console.log(`🎲 SESSION SEED: Generated new seed for session (seed: ${seed}, TTL: 24h)`);
          }
        } else {
          // Redis unavailable or no userIdentifier - generate seed from timestamp
          const timestamp = Date.now();
          const seedString = `${userIdentifier || 'anonymous'}_${videoType || 'all'}_${timestamp}`;
          for (let i = 0; i < seedString.length; i++) {
            seed = ((seed << 5) - seed) + seedString.charCodeAt(i);
            seed = seed & seed; // Convert to 32-bit integer
          }
          console.log(`🎲 SESSION SEED: Generated seed without Redis (seed: ${seed})`);
        }
      } catch (seedError) {
        // Fallback: generate seed from timestamp if Redis fails
        console.log(`⚠️ SESSION SEED: Error getting session seed, using fallback: ${seedError.message}`);
        const timestamp = Date.now();
        const seedString = `${userIdentifier || 'anonymous'}_${videoType || 'all'}_${timestamp}`;
        for (let i = 0; i < seedString.length; i++) {
          seed = ((seed << 5) - seed) + seedString.charCodeAt(i);
          seed = seed & seed; // Convert to 32-bit integer
        }
      }
      
      // **DETERMINISTIC SHUFFLE: Seeded shuffle for consistent order per session**
      const seededShuffle = (array, seedValue) => {
        // **FIX: Filter out invalid entries before shuffling**
        const validArray = array.filter(v => v && v._id);
        const shuffled = [...validArray];
        // Simple seeded random function
        let rng = seedValue;
        const random = () => {
          rng = (rng * 9301 + 49297) % 233280;
          return rng / 233280;
        };
        
        for (let i = shuffled.length - 1; i > 0; i--) {
          const j = Math.floor(random() * (i + 1));
          [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
        }
        return shuffled;
      };
      
      // Shuffle within engagement-ranked groups (maintains ranking but adds variety)
      const shuffledRecent = seededShuffle(recentUnwatched, seed);
      const shuffledOlder = seededShuffle(olderUnwatched, seed + 1); // Different seed for older
      
      // Combine: Recent high-engagement first, then older high-engagement, then shuffle mix
      // Mix recent and older in 70/30 ratio for freshness
      const mixedUnwatched = [];
      const recentCount = Math.min(shuffledRecent.length, Math.ceil(shuffledRecent.length * 0.7));
      const olderCount = Math.min(shuffledOlder.length, shuffledRecent.length - recentCount);
      
      // Add top recent videos first
      for (let i = 0; i < recentCount && i < shuffledRecent.length; i++) {
        mixedUnwatched.push(shuffledRecent[i]);
      }
      
      // Interleave older high-engagement videos
      for (let i = 0; i < olderCount && i < shuffledOlder.length; i++) {
        mixedUnwatched.push(shuffledOlder[i]);
      }
      
      // Add remaining videos (shuffled)
      const remainingRecent = shuffledRecent.slice(recentCount);
      const remainingOlder = shuffledOlder.slice(olderCount);
      const allRemaining = [...remainingRecent, ...remainingOlder];
      const shuffledRemaining = seededShuffle(allRemaining, seed + 2);
      mixedUnwatched.push(...shuffledRemaining);
      
      // Sort watched videos by oldest watch time first (least recently watched)
      watchedVideos.sort((a, b) => a._lastWatchedAt - b._lastWatchedAt);
      
      // Combine: Fresh unwatched first (recent + engagement-ranked), then older unwatched, then watched (oldest first)
      // **FIX: Filter out any undefined/null videos before processing**
      const sortedVideos = [...mixedUnwatched, ...watchedVideos].filter(v => v && v._id);
      
      // **SESSION STATE FILTER: Exclude videos already shown in current session**
      // This prevents same videos from appearing again until session ends (24h)
      const videosExcludingSession = sortedVideos.filter(video => {
        if (!video || !video._id) return false; // Skip invalid videos
        const videoId = video._id.toString();
        return !sessionShownVideoIds.has(videoId);
      });
      
      console.log(`📋 SESSION FILTER: ${sortedVideos.length} videos → ${videosExcludingSession.length} after excluding ${sessionShownVideoIds.size} session-shown videos`);
      
      // **CREATOR DIVERSITY: Apply creator diversity filter before pagination**
      // This ensures variety in each page - max 3 videos per creator per page
      const uniqueCreatorVideos = [];
      const creatorCounts = new Map(); // Track how many videos per creator
      const seenVideoIds = new Set(); // Track duplicates
      const maxPerCreator = 3;
      
      for (const video of videosExcludingSession) {
        // **FIX: Skip invalid videos**
        if (!video || !video._id) {
          continue;
        }
        
        const videoId = video._id.toString();
        const creatorId = video.uploader?._id?.toString() || video.uploader?.toString() || null;
        
        // Skip duplicates
        if (seenVideoIds.has(videoId)) {
          continue;
        }
        
        if (creatorId) {
          const currentCount = creatorCounts.get(creatorId) || 0;
          if (currentCount < maxPerCreator) {
            creatorCounts.set(creatorId, currentCount + 1);
            seenVideoIds.add(videoId);
            uniqueCreatorVideos.push(video);
          }
        } else if (!creatorId && !seenVideoIds.has(videoId)) {
          seenVideoIds.add(videoId);
          uniqueCreatorVideos.push(video);
        }
      }
      
      // 6) Pagination over the filtered and sorted list
      const skip = (pageNum - 1) * limitNum;
      const totalVideosForUser = uniqueCreatorVideos.length;
      const pagedVideos = uniqueCreatorVideos.slice(skip, skip + limitNum);
      const hasMore = skip + pagedVideos.length < totalVideosForUser;

      // **FINAL DUPLICATE CHECK: Ensure no duplicate video IDs in response**
      const finalVideoIds = new Set();
      const duplicatesRemoved = [];
      const finalDeduplicatedVideos = [];
      for (const video of pagedVideos) {
        // **FIX: Skip invalid videos**
        if (!video || !video._id) {
          continue;
        }
        const videoId = video._id.toString();
        if (!videoId) continue;
        if (finalVideoIds.has(videoId)) {
          duplicatesRemoved.push(videoId);
          continue;
        }
        finalVideoIds.add(videoId);
        finalDeduplicatedVideos.push(video);
      }
      if (duplicatesRemoved.length > 0) {
        console.log(`⚠️ WARNING: Found ${duplicatesRemoved.length} duplicate video IDs in final response, removed them:`, duplicatesRemoved);
      }
      
      // **OPTIMIZED: UPDATE SESSION STATE: Mark returned videos as shown in session (using Redis Set)**
      try {
        if (redisService.getConnectionStatus() && userIdentifier && finalDeduplicatedVideos.length > 0) {
          // Add new video IDs to session shown set (using Redis Set - more efficient)
          const newShownIds = finalDeduplicatedVideos.map(v => v._id?.toString()).filter(Boolean);
          await redisService.addToSessionShownVideos(userIdentifier, newShownIds);
          console.log(`📋 SESSION STATE: Added ${newShownIds.length} new videos to session shown set (Redis Set)`);
        }
      } catch (sessionErr) {
        console.log(`⚠️ SESSION STATE: Error updating session state (non-critical): ${sessionErr.message}`);
      }
      
      console.log('📊 FINAL FEED SUMMARY (PROFESSIONAL RECOMMENDATION):');
      console.log(`   - Page: ${pageNum}, Limit: ${limitNum}`);
      console.log(`   - Recent unwatched (7 days): ${recentUnwatched.length}`);
      console.log(`   - Older unwatched: ${olderUnwatched.length}`);
      console.log(`   - Total unwatched: ${unwatchedVideos.length} (engagement-ranked + freshness-prioritized)`);
      console.log(`   - Watched videos: ${watchedVideos.length} (LRU sorted)`);
      console.log(`   - Session-shown excluded: ${sessionShownVideoIds.size}`);
      console.log(`   - After creator diversity filter: ${uniqueCreatorVideos.length} videos`);
      console.log(`   - Unique creators in feed: ${creatorCounts.size}`);
      console.log(`   - Videos after duplicate check: ${finalDeduplicatedVideos.length}`);
      console.log(`   - Total available (for user): ${totalVideosForUser}`);
      console.log(`   - hasMore: ${hasMore}`);
      console.log(`   - Shuffle seed: ${seed} (deterministic per user per day)`);

      // **FIXED: Use deduplicated videos instead of overwriting**
      finalVideos = finalDeduplicatedVideos;
      
    } else {
      // Regular feed (no user identifier) - simple sorted by date
      console.log('📹 Using regular feed (no user identifier)');
      
      const skip = (pageNum - 1) * limitNum;
      
      // Fetch more videos to account for creator diversity filter
      // We'll filter to 1 per creator, so fetch 2x to ensure we have enough
      const fetchLimit = limitNum * 2;
      
      let regularVideos = await Video.find(baseQueryFilter)
        .select('videoName videoUrl thumbnailUrl likes views shares uploader uploadedAt likedBy videoType aspectRatio duration comments link description hlsMasterPlaylistUrl hlsPlaylistUrl isHLSEncoded category tags keywords createdAt')
        .populate('uploader', 'name profilePic googleId')
        .populate('comments.user', 'name profilePic googleId')
        .sort({ createdAt: -1 }) // Simple: newest first
        .skip(skip)
        .limit(fetchLimit)
        .lean();
      
      // **DIVERSITY: Allow max 3 videos per creator per page + no duplicate videos**
      const uniqueCreatorRegularVideos = [];
      const regularCreatorCounts = new Map(); // Track how many videos per creator
      const seenRegularVideoIds = new Set();
      const regularMaxPerCreator = 3; // Same as personalized feed
      
      for (const video of regularVideos) {
        if (uniqueCreatorRegularVideos.length >= limitNum) break;
        
        const videoId = video._id?.toString();
        const creatorId = video.uploader?._id?.toString() || video.uploader?.toString() || null;
        
        // Skip duplicates
        if (seenRegularVideoIds.has(videoId)) {
          console.log(`🚫 Regular feed: Skipping duplicate video: ${videoId}`);
          continue;
        }
        
        if (creatorId) {
          const currentCount = regularCreatorCounts.get(creatorId) || 0;
          if (currentCount < regularMaxPerCreator) {
            regularCreatorCounts.set(creatorId, currentCount + 1);
            seenRegularVideoIds.add(videoId);
            uniqueCreatorRegularVideos.push(video);
          } else {
            // Creator already has max videos - skip
            console.log(`🚫 Regular feed: Skipping video from creator with max videos (${regularMaxPerCreator}): ${creatorId}`);
          }
        } else if (!creatorId && !seenRegularVideoIds.has(videoId)) {
          seenRegularVideoIds.add(videoId);
          uniqueCreatorRegularVideos.push(video);
        }
      }
      
      finalVideos = uniqueCreatorRegularVideos.slice(0, limitNum);
      console.log(`✅ Found ${finalVideos.length} videos for regular feed (${regularCreatorCounts.size} unique creators, max ${regularMaxPerCreator} per creator, no duplicates)`);
    }
    
    // **DEBUG: Log final feed stats with watch history info**
    console.log(`═══════════════════════════════════════════════════════════`);
    console.log(`📊 FINAL FEED SUMMARY:`);
    console.log(`   - Page: ${pageNum}, Limit: ${limitNum}`);
    console.log(`   - Videos returned: ${finalVideos.length}`);
    console.log(`   - isPersonalized: ${!!userIdentifier}`);
    console.log(`   - userIdentifier: ${userIdentifier || 'none'}`);
    if (userIdentifier) {
      console.log(`   - userId: ${userId || 'none'}`);
      console.log(`   - platformId: ${platformId || 'none'}`);
      console.log(`   - Watched videos excluded: ${watchedVideoIds?.length || 0}`);
    }
    console.log(`═══════════════════════════════════════════════════════════`);
    
    // **FIXED: Calculate hasMore more accurately**
    // hasMore should be true if we got the requested limit OR if there might be more videos
    // Since creator diversity filter might reduce count, we check if we got full limit
    // For personalized feed, also check if there are more unwatched videos available
    let hasMore = finalVideos.length === limitNum;
    
    // If we got less than limit, try to check if more videos exist
    if (finalVideos.length < limitNum && userIdentifier) {
      // Check if there are more unwatched videos beyond what we fetched
      const identityId = userId || platformId;
      if (identityId) {
        try {
          const watchedVideoIds = await WatchHistory.getUserWatchedVideoIds(identityId, null);
          const unwatchedQuery = {
            ...baseQueryFilter,
            ...(watchedVideoIds.length > 0 && { _id: { $nin: watchedVideoIds } })
          };
          const totalUnwatched = await Video.countDocuments(unwatchedQuery);
          
          // **FIXED: If showing fallback (oldest watched videos), check watch history count instead**
          // When totalUnwatched is 0, we're showing fallback videos, so check if more watched videos exist
          if (totalUnwatched === 0 && watchedVideoIds.length > 0) {
            // We're showing fallback videos - check if there are more watched videos beyond current page
            const totalWatched = watchedVideoIds.length;
            hasMore = totalWatched > (skip + finalVideos.length);
            console.log(`📊 hasMore calculation (fallback): totalWatched=${totalWatched}, current=${skip + finalVideos.length}, hasMore=${hasMore}`);
          } else {
            // Normal case - check unwatched videos
            hasMore = totalUnwatched > (skip + finalVideos.length);
            console.log(`📊 hasMore calculation: totalUnwatched=${totalUnwatched}, current=${skip + finalVideos.length}, hasMore=${hasMore}`);
          }
        } catch (err) {
          console.log(`⚠️ Error calculating hasMore: ${err.message}`);
        }
      }
    } else if (finalVideos.length < limitNum && !userIdentifier) {
      // For regular feed, check total matching videos
      try {
        const totalMatching = await Video.countDocuments(baseQueryFilter);
        hasMore = totalMatching > (skip + finalVideos.length);
        console.log(`📊 hasMore calculation (regular): totalMatching=${totalMatching}, current=${skip + finalVideos.length}, hasMore=${hasMore}`);
      } catch (err) {
        console.log(`⚠️ Error calculating hasMore: ${err.message}`);
      }
    }
    
    // **IMPROVED: Calculate accurate total for pagination**
    let totalCount = finalVideos.length;
    if (userIdentifier) {
      // For personalized feed, use the total after creator diversity filter
      try {
        const watchedVideoIds = await WatchHistory.getUserWatchedVideoIds(userIdentifier, null);
        const unwatchedQuery = {
          ...baseQueryFilter,
          ...(watchedVideoIds.length > 0 && { _id: { $nin: watchedVideoIds } })
        };
        const totalUnwatched = await Video.countDocuments(unwatchedQuery);
        const totalWatched = watchedVideoIds.length;
        totalCount = totalUnwatched + totalWatched; // Approximate total
      } catch (err) {
        // Fallback to current count
        totalCount = finalVideos.length;
      }
    } else {
      // For regular feed, count all matching videos
      try {
        totalCount = await Video.countDocuments(baseQueryFilter);
      } catch (err) {
        totalCount = finalVideos.length;
      }
    }
    
    // **OPTIMIZED: Cache feed response before sending (short TTL for freshness)**
    const feedResponse = {
      videos: finalVideos,
      hasMore,
      page: pageNum,
      limit: limitNum,
      total: totalCount,
      isPersonalized: !!userIdentifier
    };
    
    // Cache for 30 seconds (short TTL ensures freshness while reducing DB load)
    if (redisService.getConnectionStatus() && finalVideos.length > 0) {
      await redisService.set(feedCacheKey, feedResponse, 30);
      console.log(`💾 Feed Cache SET: ${feedCacheKey} (30s TTL)`);
    }
    
    res.json(feedResponse);
    
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
    
    // **FIX: Normalize video URLs to fix Windows path separator issues**
    const normalizeUrl = (url) => {
      if (!url) return url;
      return url.replace(/\\/g, '/');
    };
    
    // **FIX: Convert likedBy ObjectIds to googleIds**
    const likedByGoogleIds = await convertLikedByToGoogleIds(videoObj.likedBy || []);
    
    const transformedVideo = {
      _id: videoObj._id?.toString(),
      videoName: videoObj.videoName,
      videoUrl: normalizeUrl(videoObj.videoUrl),
      thumbnailUrl: normalizeUrl(videoObj.thumbnailUrl),
      likes: videoObj.likes || 0,
      views: videoObj.views || 0,
      shares: videoObj.shares || 0,
      uploader: {
        id: videoObj.uploader?.googleId?.toString() || videoObj.uploader?._id?.toString() || '',
        _id: videoObj.uploader?._id?.toString() || '',
        googleId: videoObj.uploader?.googleId?.toString() || '',
        name: videoObj.uploader?.name || 'Unknown User',
        profilePic: videoObj.uploader?.profilePic || ''
      },
      likedBy: likedByGoogleIds,
      videoType: videoObj.videoType,
      aspectRatio: videoObj.aspectRatio,
      duration: videoObj.duration,
      comments: await Promise.all((videoObj.comments || []).map(async (comment) => {
        const commentLikedByGoogleIds = await convertLikedByToGoogleIds(comment.likedBy || []);
        return {
          _id: comment._id,
          text: comment.text,
          userId: comment.user?.googleId || comment.user?._id || '',
          userName: comment.user?.name || '',
          createdAt: comment.createdAt,
          likes: comment.likes || 0,
          likedBy: commentLikedByGoogleIds
        };
      })),
      link: videoObj.link,
      description: videoObj.description,
      hlsMasterPlaylistUrl: normalizeUrl(videoObj.hlsMasterPlaylistUrl),
      hlsPlaylistUrl: normalizeUrl(videoObj.hlsPlaylistUrl),
      isHLSEncoded: videoObj.isHLSEncoded || false,
      category: videoObj.category,
      tags: videoObj.tags,
      keywords: videoObj.keywords,
      createdAt: videoObj.createdAt,
      uploadedAt: videoObj.uploadedAt
    };

    res.json(transformedVideo);
  } catch (error) {
    console.error('❌ Error fetching video by ID:', error);
    res.status(500).json({
      error: 'Failed to fetch video',
      message: error.message
    });
  }
});

// POST /api/videos/:id/watch - Track video watch for personalized feed
// Supports both authenticated users (via token) and anonymous users (via deviceId)
// (Correct implementation is below - this duplicate broken code was removed)

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
  // **OPTIMIZED: Reduced logging - only log errors to prevent log spam**
  try {
    // Try to get userId from token (authenticated users)
    let userId = null;
    let isAuthenticated = false;
    
    // **BACKEND-FIRST: Get deviceId first (always available for fallback)**
    const deviceId = req.body.deviceId || req.headers['x-device-id'];
    
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
            console.log(`✅ Watch tracking: Using authenticated user (Google ID: ${userId})`);
          } else {
            // Try JWT token
            const jwt = (await import('jsonwebtoken')).default;
            const JWT_SECRET = process.env.JWT_SECRET;
            if (JWT_SECRET) {
              try {
                const decoded = jwt.verify(token, JWT_SECRET);
                userId = decoded.id || decoded.googleId;
                isAuthenticated = true;
                console.log(`✅ Watch tracking: Using authenticated user (JWT, ID: ${userId})`);
              } catch (jwtError) {
                // Token invalid - will use deviceId (this is OK, not an error)
                console.log(`ℹ️ Watch tracking: Token verification failed, using deviceId fallback (deviceId: ${deviceId ? 'present' : 'missing'})`);
              }
            } else {
              console.log(`ℹ️ Watch tracking: JWT_SECRET not set, using deviceId fallback (deviceId: ${deviceId ? 'present' : 'missing'})`);
            }
          }
        } catch (tokenError) {
          // Token verification failed - will use deviceId (this is OK, not an error)
          console.log(`ℹ️ Watch tracking: Token verification error (non-critical), using deviceId fallback (deviceId: ${deviceId ? 'present' : 'missing'})`);
        }
      } else {
        console.log(`ℹ️ Watch tracking: No token provided, using deviceId (deviceId: ${deviceId ? 'present' : 'missing'})`);
      }
    } catch (error) {
      // Error getting token - will use deviceId (this is OK, not an error)
      console.log(`ℹ️ Watch tracking: Error processing token (non-critical), using deviceId fallback (deviceId: ${deviceId ? 'present' : 'missing'})`);
    }
    
    // **SIMPLE IDENTITY RULE: Use googleId (userId) when logged in, deviceId for anonymous**
    // This matches the feed logic - same identity used for tracking and filtering
    const identityId = userId || deviceId;
    
    const videoId = req.params.id;
    const { duration = 0, completed = false } = req.body;

    if (!identityId) {
      return res.status(400).json({ error: 'User identifier (userId or deviceId) required' });
    }

    if (!videoId || !mongoose.Types.ObjectId.isValid(videoId)) {
      return res.status(400).json({ error: 'Invalid video ID' });
    }

    console.log('📊 Tracking video watch:', { 
      identityId, 
      userId: userId || 'none',
      deviceId: deviceId || 'none',
      isAuthenticated: isAuthenticated ? 'authenticated (googleId)' : 'anonymous (deviceId)',
      videoId, 
      duration, 
      completed 
    });

    // **SIMPLE TRACKING: Use single identity (googleId when logged in, deviceId when anonymous)**
    // This ensures watch history is stored under the same identity used in feed filtering
    const watchEntry = await WatchHistory.trackWatch(identityId, videoId, {
      duration,
      completed,
      isAuthenticated
    });
    
    console.log(`✅ Watch tracked successfully for ${isAuthenticated ? 'authenticated (googleId)' : 'anonymous (deviceId)'} user`);

    // Update video view count
    await Video.findByIdAndUpdate(videoId, {
      $inc: { views: 1 }
    });

    // **OPTIMIZED: Smart cache invalidation - clear all related caches**
    if (redisService.getConnectionStatus()) {
      // Clear watch history cache (will be refreshed on next feed request)
      const watchHistoryPattern = `watch:history:${identityId}*`;
      await redisService.clearPattern(watchHistoryPattern);
      console.log(`🧹 Cleared watch history cache for: ${identityId}`);
      
      // Clear feed cache (user will see updated feed after watching)
      const feedCachePattern = `feed:${identityId}:*`;
      await redisService.clearPattern(feedCachePattern);
      console.log(`🧹 Cleared feed cache for: ${identityId}`);
      
      // Clear unwatched IDs cache (for backward compatibility)
      const unwatchedCachePattern = `videos:unwatched:ids:${identityId}:*`;
      await redisService.clearPattern(unwatchedCachePattern);
      
      // Clear old feed cache pattern (for backward compatibility)
      const oldFeedCachePattern = `videos:feed:user:${identityId}:*`;
      await redisService.clearPattern(oldFeedCachePattern);
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

// **PROFESSIONAL: POST /api/videos/sync-watch-history - Sync watch history between userId and deviceId**
// This endpoint should be called when user logs in to merge their anonymous watch history with authenticated history
// This ensures seamless experience - watched videos won't appear again after login
router.post('/sync-watch-history', verifyToken, async (req, res) => {
  try {
    const googleId = req.user.googleId;
    const { deviceId } = req.body;
    
    if (!deviceId) {
      return res.status(400).json({ error: 'deviceId is required' });
    }
    
    console.log('🔄 Syncing watch history:', { googleId, deviceId });
    
    // Get watch history for both identifiers
    const watchedByUserId = await WatchHistory.getUserWatchedVideoIds(googleId, null);
    const watchedByDeviceId = await WatchHistory.getUserWatchedVideoIds(deviceId, null);
    
    console.log(`📊 Watch history before sync: ${watchedByUserId.length} (userId) + ${watchedByDeviceId.length} (deviceId)`);
    
    // Merge: Copy all deviceId watch history to userId
    // This ensures authenticated user gets all their anonymous watch history
    let syncedCount = 0;
    for (const videoId of watchedByDeviceId) {
      try {
        // Check if already exists for userId
        const exists = await WatchHistory.findOne({
          userId: googleId,
          videoId: videoId
        });
        
        if (!exists) {
          // Copy watch history entry from deviceId to userId
          const deviceEntry = await WatchHistory.findOne({
            userId: deviceId,
            videoId: videoId
          });
          
          if (deviceEntry) {
            await WatchHistory.create({
              userId: googleId,
              videoId: videoId,
              watchedAt: deviceEntry.watchedAt,
              lastWatchedAt: deviceEntry.lastWatchedAt,
              watchDuration: deviceEntry.watchDuration,
              completed: deviceEntry.completed,
              watchCount: deviceEntry.watchCount,
              isAuthenticated: true
            });
            syncedCount++;
          }
        }
      } catch (error) {
        console.error(`⚠️ Error syncing video ${videoId}:`, error.message);
        // Continue with other videos
      }
    }
    
    // Also sync in reverse: Copy userId watch history to deviceId (for consistency)
    let reverseSyncedCount = 0;
    for (const videoId of watchedByUserId) {
      try {
        const exists = await WatchHistory.findOne({
          userId: deviceId,
          videoId: videoId
        });
        
        if (!exists) {
          const userEntry = await WatchHistory.findOne({
            userId: googleId,
            videoId: videoId
          });
          
          if (userEntry) {
            await WatchHistory.create({
              userId: deviceId,
              videoId: videoId,
              watchedAt: userEntry.watchedAt,
              lastWatchedAt: userEntry.lastWatchedAt,
              watchDuration: userEntry.watchDuration,
              completed: userEntry.completed,
              watchCount: userEntry.watchCount,
              isAuthenticated: false
            });
            reverseSyncedCount++;
          }
        }
      } catch (error) {
        console.error(`⚠️ Error reverse syncing video ${videoId}:`, error.message);
      }
    }
    
    // Get final counts
    const finalWatchedByUserId = await WatchHistory.getUserWatchedVideoIds(googleId, null);
    const finalWatchedByDeviceId = await WatchHistory.getUserWatchedVideoIds(deviceId, null);
    
    console.log(`✅ Watch history sync complete: ${syncedCount} videos synced to userId, ${reverseSyncedCount} to deviceId`);
    console.log(`📊 Watch history after sync: ${finalWatchedByUserId.length} (userId) + ${finalWatchedByDeviceId.length} (deviceId)`);
    
    // Clear cache for both identifiers
    if (redisService.getConnectionStatus()) {
      await redisService.clearPattern(`videos:unwatched:ids:${googleId}:*`);
      await redisService.clearPattern(`videos:unwatched:ids:${deviceId}:*`);
      console.log('🧹 Cleared cache for both identifiers');
    }
    
    res.json({
      success: true,
      message: 'Watch history synced successfully',
      syncedCount,
      reverseSyncedCount,
      finalCounts: {
        userId: finalWatchedByUserId.length,
        deviceId: finalWatchedByDeviceId.length
      }
    });
  } catch (error) {
    console.error('❌ Error syncing watch history:', error);
    res.status(500).json({
      error: 'Failed to sync watch history',
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
  // **OPTIMIZED: Reduced logging - only log errors to prevent log spam**
  try {
    // Try to get userId from token (authenticated users)
    let userId = null;
    let isAuthenticated = false;
    
    // **BACKEND-FIRST: Get deviceId first (always available for fallback)**
    const deviceId = req.body.deviceId || req.headers['x-device-id'];
    
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
            console.log(`✅ Watch tracking: Using authenticated user (Google ID: ${userId})`);
          } else {
            // Try JWT token
            const jwt = (await import('jsonwebtoken')).default;
            const JWT_SECRET = process.env.JWT_SECRET;
            if (JWT_SECRET) {
              try {
                const decoded = jwt.verify(token, JWT_SECRET);
                userId = decoded.id || decoded.googleId;
                isAuthenticated = true;
                console.log(`✅ Watch tracking: Using authenticated user (JWT, ID: ${userId})`);
              } catch (jwtError) {
                // Token invalid - will use deviceId (this is OK, not an error)
                console.log(`ℹ️ Watch tracking: Token verification failed, using deviceId fallback (deviceId: ${deviceId ? 'present' : 'missing'})`);
              }
            } else {
              console.log(`ℹ️ Watch tracking: JWT_SECRET not set, using deviceId fallback (deviceId: ${deviceId ? 'present' : 'missing'})`);
            }
          }
        } catch (tokenError) {
          // Token verification failed - will use deviceId (this is OK, not an error)
          console.log(`ℹ️ Watch tracking: Token verification error (non-critical), using deviceId fallback (deviceId: ${deviceId ? 'present' : 'missing'})`);
        }
      } else {
        console.log(`ℹ️ Watch tracking: No token provided, using deviceId (deviceId: ${deviceId ? 'present' : 'missing'})`);
      }
    } catch (error) {
      // Error getting token - will use deviceId (this is OK, not an error)
      console.log(`ℹ️ Watch tracking: Error processing token (non-critical), using deviceId fallback (deviceId: ${deviceId ? 'present' : 'missing'})`);
    }
    
    // **SIMPLE IDENTITY RULE: Use googleId (userId) when logged in, deviceId for anonymous**
    // This matches the feed logic - same identity used for tracking and filtering
    const identityId = userId || deviceId;
    
    const videoId = req.params.id;
    const { duration = 0, completed = false } = req.body;

    if (!identityId) {
      return res.status(400).json({ error: 'User identifier (userId or deviceId) required' });
    }

    if (!videoId || !mongoose.Types.ObjectId.isValid(videoId)) {
      return res.status(400).json({ error: 'Invalid video ID' });
    }

    console.log('📊 Tracking video watch:', { 
      identityId, 
      userId: userId || 'none',
      deviceId: deviceId || 'none',
      isAuthenticated: isAuthenticated ? 'authenticated (googleId)' : 'anonymous (deviceId)',
      videoId, 
      duration, 
      completed 
    });

    // **SIMPLE TRACKING: Use single identity (googleId when logged in, deviceId when anonymous)**
    // This ensures watch history is stored under the same identity used in feed filtering
    const watchEntry = await WatchHistory.trackWatch(identityId, videoId, {
      duration,
      completed,
      isAuthenticated
    });
    
    console.log(`✅ Watch tracked successfully for ${isAuthenticated ? 'authenticated (googleId)' : 'anonymous (deviceId)'} user`);

    // Update video view count
    await Video.findByIdAndUpdate(videoId, {
      $inc: { views: 1 }
    });

    // **OPTIMIZED: Smart cache invalidation - clear all related caches**
    if (redisService.getConnectionStatus()) {
      // Clear watch history cache (will be refreshed on next feed request)
      const watchHistoryPattern = `watch:history:${identityId}*`;
      await redisService.clearPattern(watchHistoryPattern);
      console.log(`🧹 Cleared watch history cache for: ${identityId}`);
      
      // Clear feed cache (user will see updated feed after watching)
      const feedCachePattern = `feed:${identityId}:*`;
      await redisService.clearPattern(feedCachePattern);
      console.log(`🧹 Cleared feed cache for: ${identityId}`);
      
      // Clear unwatched IDs cache (for backward compatibility)
      const unwatchedCachePattern = `videos:unwatched:ids:${identityId}:*`;
      await redisService.clearPattern(unwatchedCachePattern);
      
      // Clear old feed cache pattern (for backward compatibility)
      const oldFeedCachePattern = `videos:feed:user:${identityId}:*`;
      await redisService.clearPattern(oldFeedCachePattern);
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
    const { userId, duration = 2, deviceId } = req.body; // **IMPROVED: Added deviceId support for anonymous users**

    console.log('🎯 View increment request:', {
      videoId,
      userId,
      deviceId,
      duration,
      timestamp: new Date().toISOString()
    });

    // Validate video ID
    if (!videoId || !mongoose.Types.ObjectId.isValid(videoId)) {
      return res.status(400).json({ error: 'Invalid video ID' });
    }

    // **IMPROVED: Support both authenticated (userId) and anonymous (deviceId) users**
    let identityId = null;
    let isAuthenticated = false;
    let user = null;
    let userObjectId = null;

    // Try to get authenticated user first
    if (userId) {
      user = await User.findOne({ googleId: userId });
      if (user) {
        identityId = userId;
        isAuthenticated = true;
        userObjectId = user._id;
        console.log('✅ Using authenticated user:', userId);
      }
    }

    // Fallback to deviceId for anonymous users
    if (!identityId && deviceId) {
      identityId = deviceId;
      isAuthenticated = false;
      console.log('✅ Using deviceId for anonymous user:', deviceId);
    }

    if (!identityId) {
      return res.status(400).json({ error: 'User identifier (userId or deviceId) required' });
    }

    // Find video
    const video = await Video.findById(videoId);
    if (!video) {
      console.log('❌ Video not found:', videoId);
      return res.status(404).json({ error: 'Video not found' });
    }

    // **IMPROVED: Mark video as watched/completed when view count is incremented**
    // Use same threshold (2 seconds) for both view increment and watch completion
    try {
      const watchEntry = await WatchHistory.trackWatch(identityId, videoId, {
        duration: duration,
        completed: true, // **NEW: Mark as completed when view count is incremented**
        isAuthenticated: isAuthenticated
      });
      console.log(`✅ Video marked as watched/completed for ${isAuthenticated ? 'authenticated' : 'anonymous'} user`);
      
      // **IMPROVED: Clear cache so user sees updated feed (video won't appear again)**
      if (redisService.getConnectionStatus()) {
        const unwatchedCachePattern = `videos:unwatched:ids:${identityId}:*`;
        await redisService.clearPattern(unwatchedCachePattern);
        const feedCachePattern = `videos:feed:user:${identityId}:*`;
        await redisService.clearPattern(feedCachePattern);
        console.log(`🧹 Cleared cache for ${identityId} after marking video as watched`);
      }
    } catch (watchError) {
      console.log(`⚠️ Error marking video as watched (non-critical): ${watchError.message}`);
      // Continue with view increment even if watch tracking fails
    }

    // **ONLY increment view count for authenticated users (existing behavior)**
    // Anonymous users get watch tracking but not view count increment
    if (user && userObjectId) {
    // Check if user has already reached max views (10)
    const existingView = video.viewDetails.find(view => 
        view.user.toString() === userObjectId.toString()
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
      await video.incrementView(userObjectId, duration);

    console.log('✅ View incremented successfully:', {
      videoId,
      userId: user.googleId,
      newTotalViews: video.views,
      userViewCount: existingView ? existingView.viewCount + 1 : 1
    });

    // Return updated view count
    const updatedExistingView = video.viewDetails.find(view => 
        view.user.toString() === userObjectId.toString()
    );

    res.json({
      message: 'View incremented successfully',
      totalViews: video.views,
      userViewCount: updatedExistingView ? updatedExistingView.viewCount : 1,
        maxViewsReached: updatedExistingView ? updatedExistingView.viewCount >= 10 : false,
        watched: true // **NEW: Indicate video was marked as watched**
      });
    } else {
      // Anonymous user - only watch tracking, no view increment
      console.log('✅ Watch tracking completed for anonymous user (view count not incremented)');
      res.json({
        message: 'Watch tracked successfully (anonymous user)',
        totalViews: video.views,
        userViewCount: 0, // Anonymous users don't increment view count
        maxViewsReached: false,
        watched: true // **NEW: Indicate video was marked as watched**
      });
    }

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
    const videos = await Video.find({ 
      uploader: user._id,
      videoUrl: { $exists: true, $ne: null, $ne: '' }, // Ensure video URL exists and is not empty
      processingStatus: { $nin: ['failed', 'error'] } // Only exclude explicitly failed videos
    })
      .select('videoName videoUrl thumbnailUrl likes views shares uploader uploadedAt likedBy videoType aspectRatio duration comments link description hlsMasterPlaylistUrl hlsPlaylistUrl isHLSEncoded')
      .populate('uploader', 'name profilePic googleId')
      .populate('comments.user', 'name profilePic googleId')
      .sort({ createdAt: -1 }) // Simple: newest first
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
