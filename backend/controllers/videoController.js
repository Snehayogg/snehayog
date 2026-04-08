import mongoose from 'mongoose';
import fs from 'fs';
import path from 'path';
import Video from '../models/Video.js';
import User from '../models/User.js';
import View from '../models/View.js';
import WatchHistory from '../models/WatchHistory.js';
import CreatorDailyStats from '../models/CreatorDailyStats.js';
import FeedHistory from '../models/FeedHistory.js';
import AdImpression from '../models/AdImpression.js';
import redisService from '../services/caching/redisService.js';
import FeedQueueService from '../services/yugFeedServices/feedQueueService.js';
import RecommendationService from '../services/yugFeedServices/recommendationService.js';
import queueService from '../services/yugFeedServices/queueService.js';
import RemovedVideoRecord from '../models/RemovedVideoRecord.js';
import { VideoCacheKeys, invalidateCache } from '../middleware/cacheMiddleware.js';
import { AD_CONFIG } from '../constants/index.js';
import { calculateVideoHash, convertLikedByToGoogleIds } from '../utils/videoUtils.js';
import { serializeVideo, serializeVideos } from '../utils/serializers/videoSerializer.js';
import cloudflareR2Service from '../services/uploadServices/cloudflareR2Service.js';
import { updateCreatorDailyStats } from '../utils/analyticsUtils.js';
import RevenueService from '../services/adServices/revenueService.js';


let hybridVideoService;

/**
 * Cache Management Controllers
 */
export const getCacheStatus = async (req, res) => {
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

    for (const [name, pattern] of Object.entries(cachePatterns)) {
      if (!pattern) continue;

      try {
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
};

export const clearCache = async (req, res) => {
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
      const count = await redisService.clearPattern(pattern);
      clearedCount += count;
      clearedPatterns.push({ pattern, keysCleared: count });
    } else {
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
};

/**
 * Upload and Duplicate Check Controllers
 */
export const checkDuplicate = async (req, res) => {
  try {
    const { videoHash } = req.body;
    const googleId = req.user.googleId;

    if (!videoHash) {
      return res.status(400).json({ error: 'Video hash is required' });
    }

    const user = await User.findOne({ googleId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const existingVideo = await Video.findOne({
      uploader: user._id,
      videoHash: videoHash,
      processingStatus: { $ne: 'failed' } // Ignore failed uploads
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
};

export const uploadVideo = async (req, res) => {
  try {
    console.log('🎬 Upload: Starting video upload process with HLS streaming...');
    
    // Google ID is available from verifyToken middleware
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

    // 3. Validate user
    const user = await User.findOne({ googleId: googleId });
    if (!user) {
      console.log('❌ Upload: User not found with Google ID:', googleId);
      fs.unlinkSync(req.file.path);
      return res.status(404).json({ error: 'User not found' });
    }

    // 4. Calculate video hash for duplicate detection
    let videoHash;
    try {
      videoHash = await calculateVideoHash(req.file.path);
    } catch (hashError) {
      console.error('❌ Upload: Error calculating video hash:', hashError);
      fs.unlinkSync(req.file.path);
      return res.status(500).json({ error: 'Failed to calculate video hash' });
    }

    // 5. Check if same video already exists for this user
    const existingVideo = await Video.findOne({
      uploader: user._id,
      videoHash: videoHash,
      processingStatus: { $ne: 'failed' } // Ignore failed uploads
    });

    if (existingVideo) {
      fs.unlinkSync(req.file.path);
      return res.status(409).json({
        error: 'Duplicate video detected',
        message: 'You have already uploaded this video.',
        existingVideoId: existingVideo._id,
        existingVideoName: existingVideo.videoName
      });
    }

    // 6. Determine video type based on aspect ratio (landscape vs portrait)
    if (!hybridVideoService) {
      const { default: service } = await import('../services/uploadServices/hybridVideoService.js');
      hybridVideoService = service;
    }

    let detectedDuration = 0;
    let detectedWidth = 0;
    let detectedHeight = 0;

    try {
      const videoInfo = await hybridVideoService.getOriginalVideoInfo(req.file.path);
      detectedDuration = videoInfo.duration || 0;
      detectedWidth = videoInfo.width || 0;
      detectedHeight = videoInfo.height || 0;
    } catch (infoError) {
      console.warn('⚠️ Upload: Failed to get video info:', infoError.message);
    }

    // **SOURCE OF TRUTH: Classify based on aspect ratio ONLY**
    let finalVideoType = videoType || 'yog';
    if (detectedWidth > 0 && detectedHeight > 0) {
      const aspectRatio = detectedWidth / detectedHeight;
      if (aspectRatio > 1.0) {
        // Landscape/Horizontal video (e.g., 16:9 = 1.778)
        finalVideoType = 'vayu';
      } else {
        // Portrait/Vertical video (e.g., 9:16 = 0.5625)
        finalVideoType = 'yog';
      }
    } else {
      // Fallback to default if dimensions not detected
      finalVideoType = videoType || 'yog';
    }

    // 7. Create initial video record
    const initialScore = RecommendationService.calculateFinalScore({
      totalWatchTime: 0,
      duration: detectedDuration || 0,
      likes: 0,
      shares: 0,
      views: 0,
      uploadedAt: new Date()
    });

    // **NEW: Generate initial vector embedding for instant discovery**
    let initialEmbedding = null;
    const embeddingText = `${videoName || ''} ${description || ''}`.trim();
    if (embeddingText) {
      try {
        const { default: aiSemanticService } = await import('../services/yugFeedServices/aiSemanticService.js');
        initialEmbedding = await aiSemanticService.getEmbedding(embeddingText);
      } catch (e) {
        console.warn('⚠️ Could not generate initial embedding:', e.message);
      }
    }

    const video = new Video({
      videoName: videoName,
      description: description || '',
      link: link || '',
      uploader: user._id,
      videoType: finalVideoType,
      mediaType: 'video',
      aspectRatio: (detectedWidth && detectedHeight) ? detectedWidth / detectedHeight : undefined,
      duration: detectedDuration || 0,
      originalResolution: { width: detectedWidth || 0, height: detectedHeight || 0 },
      processingStatus: 'pending',
      processingProgress: 0,
      isHLSEncoded: false,
      videoHash: videoHash,
      likes: 0, views: 0, shares: 0, likedBy: [], comments: [],
      uploadedAt: new Date(),
      seriesId: req.body.seriesId || null,
      episodeNumber: parseInt(req.body.episodeNumber) || 0,
      finalScore: initialScore,
      vectorEmbedding: initialEmbedding,
      embeddingVersion: initialEmbedding ? 'v1_minilm' : undefined
    });

    await video.save();
    user.videos.push(video._id);
    await user.save();

    // 8. Invalidate cache
    if (redisService.getConnectionStatus()) {
      await invalidateCache([
        'videos:feed:*',
        `user:feed:${user.googleId}:*`,
        `videos:user:${user.googleId}`,
        VideoCacheKeys.all()
      ]);
    }

    // 9. Background Processing - Respond immediately to user for better speed
    const rawVideoKey = `temp_raw/${user._id}/${Date.now()}_${path.basename(req.file.path)}`;
    const tempFilePath = req.file.path;
    const tempMimeType = req.file.mimetype;

    // We do NOT await this block - it runs in background
    (async () => {
      try {
        // Cloudflare R2 Upload & Queueing
        const { default: cloudflareR2Service } = await import('../services/uploadServices/cloudflareR2Service.js');
        await cloudflareR2Service.uploadFileToR2(tempFilePath, rawVideoKey, tempMimeType);
        
        await queueService.addVideoJob({
            videoId: video._id,
            rawVideoKey: rawVideoKey,
            videoName: videoName,
            userId: user._id.toString()
        });

        console.log(`✅ Upload: Background processing complete for video ${video._id}`);

        // Auto-trigger Dubbing removed (sunsetted)
      } catch (bgError) {
        console.error(`❌ Upload: Background processing failed for video ${video._id}:`, bgError);
      } finally {
        // Cleanup temp file AFTER background processing
        try { 
          if (fs.existsSync(tempFilePath)) {
            fs.unlinkSync(tempFilePath); 
          }
        } catch (e) { 
          console.warn('Failed to cleanup upload', e); 
        }
      }
    })();

    return res.status(201).json({
      success: true,
      message: 'Video upload received! Processing will begin in background.',
      video: {
        id: video._id,
        videoName: video.videoName,
        processingStatus: 'queued',
        estimatedTime: '2-5 minutes',
        costBreakdown: { processing: '$0 (FREE!)', storage: '$0.015/GB/month (R2)', bandwidth: '$0 (FREE forever!)' }
      }
    });

  } catch (error) {
    console.error('❌ Upload: Error:', error);
    if (req.file) {
      try { fs.unlinkSync(req.file.path); } catch (_) { }
    }
    return res.status(500).json({ error: 'Video upload failed', details: error.message });
  }
};

/**
 * Register Video after Direct-to-R2 Upload (Cloudflare Workers Flow)
 */
export const registerUpload = async (req, res) => {
  try {
    const { 
      videoName, 
      description, 
      videoType, 
      link, 
      r2Key, 
      videoHash, 
      duration,
      width,
      height,
      mimeType
    } = req.body;

    const googleId = req.user.googleId;
    if (!googleId) {
      return res.status(401).json({ error: 'User not authenticated' });
    }

    if (!r2Key) {
       return res.status(400).json({ error: 'R2 storage key is required' });
    }

    // 1. Validate user
    const user = await User.findOne({ googleId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // 2. Duplicate detection
    if (videoHash) {
      const existingVideo = await Video.findOne({
        uploader: user._id,
        videoHash: videoHash,
        processingStatus: { $ne: 'failed' }
      });

      if (existingVideo) {
        return res.status(409).json({
          error: 'Duplicate video detected',
          message: 'You have already uploaded this video.',
          existingVideoId: existingVideo._id
        });
      }
    }

    // 3. Determine video type (fallback if not provided/detected)
    let finalVideoType = videoType || 'yog';
    if (width && height) {
      finalVideoType = (width > height) ? 'vayu' : 'yog';
    }

    // 4. Create initial video record
    const initialScore = RecommendationService.calculateFinalScore({
      totalWatchTime: 0,
      duration: duration || 0,
      likes: 0,
      shares: 0,
      views: 0,
      uploadedAt: new Date()
    });

    // **NEW: Initial embedding for instant registration**
    let initialEmbedding = null;
    const embeddingText = `${videoName || ''} ${description || ''}`.trim();
    if (embeddingText) {
       try {
         const { default: aiSemanticService } = await import('../services/yugFeedServices/aiSemanticService.js');
         initialEmbedding = await aiSemanticService.getEmbedding(embeddingText);
       } catch(e) {}
    }

    const video = new Video({
      videoName: videoName || 'Untitled Video',
      description: description || '',
      link: link || '',
      uploader: user._id,
      videoType: finalVideoType,
      mediaType: 'video',
      aspectRatio: (width && height) ? (width / height) : undefined,
      duration: duration || 0,
      originalResolution: { width: width || 0, height: height || 0 },
      processingStatus: 'pending',
      processingProgress: 0,
      isHLSEncoded: false,
      videoHash: videoHash,
      likes: 0, views: 0, shares: 0, likedBy: [], comments: [],
      uploadedAt: new Date(),
      finalScore: initialScore,
      vectorEmbedding: initialEmbedding,
      embeddingVersion: initialEmbedding ? 'v1_minilm' : undefined
    });

    await video.save();
    user.videos.push(video._id);
    await user.save();

    // 5. Trigger Background Processing
    await queueService.addVideoJob({
      videoId: video._id,
      rawVideoKey: r2Key, // This is the key the client used to upload to R2
      videoName: video.videoName,
      userId: user._id.toString()
    });

    // 6. Invalidate cache
    if (redisService.getConnectionStatus()) {
      await invalidateCache([
        'videos:feed:*',
        `user:feed:${user.googleId}:*`,
        VideoCacheKeys.all()
      ]);
    }

    return res.status(201).json({
      success: true,
      message: 'Video registered successfully. Processing started.',
      video: {
        id: video._id,
        videoName: video.videoName,
        processingStatus: 'queued'
      }
    });

  } catch (error) {
    console.error('❌ Register Upload Error:', error);
    return res.status(500).json({ error: 'Failed to register video' });
  }
};

/**
 * Cloudflare Worker Callback (Phase 3: Media Processing)
 * Triggered by worker after R2 upload is confirmed.
 */
export const r2Callback = async (req, res) => {
  try {
    const { event, key, size } = req.body;
    const workerSecret = req.headers['x-worker-secret'];

    // Security check: Match secret from env
    if (workerSecret !== process.env.WORKER_SECRET && process.env.NODE_ENV === 'production') {
      return res.status(403).json({ error: 'Unauthorized worker callback' });
    }

    console.log(`📡 R2 Callback received for ${key} (${event})`);
    
    // Logic: If the video isn't registered yet, we might want to log it
    // Or if it's already registered, we can update its status to "stored"
    const video = await Video.findOne({ 'rawVideoKey': key });
    if (video) {
      video.processingStatus = 'processing';
      await video.save();
      console.log(`✅ Video ${video._id} status updated to processing`);
    }

    return res.json({ success: true });
  } catch (error) {
    console.error('❌ R2 Callback Error:', error);
    return res.status(500).json({ error: 'Callback processing failed' });
  }
};

export const createImageFeedEntry = async (req, res) => {
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
      likes: 0, views: 0, shares: 0, likedBy: [], comments: [],
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
    return res.status(500).json({ error: 'Failed to create image feed entry', details: error.message });
  }
};

/**
 * Video Retrieval Controllers
 */
export const getUserVideos = async (req, res) => {
  try {
    const { googleId } = req.params;
    const cacheKey = VideoCacheKeys.user(googleId);
    
    res.set('Cache-Control', 'public, max-age=300');

    const shouldRefresh = req.query.refresh === 'true';

    if (shouldRefresh && redisService.getConnectionStatus()) {
        await invalidateCache(cacheKey);
        await invalidateCache(`user:profile:${googleId}`);
    }

    if (!shouldRefresh && redisService.getConnectionStatus()) {
      const cached = await redisService.get(cacheKey);
      if (cached) return res.json(cached);
    }

    const userProfileCacheKey = `user:profile:${googleId}`;
    let user = null;

    // **IDENTITY OPTIMIZATION: Check req.user first**
    if (req.user && (req.user.googleId === googleId || req.user.id === googleId) && req.user._id) {
       user = { _id: req.user._id, googleId: googleId };
    }

    if (!user && redisService.getConnectionStatus()) {
      const cached = await redisService.get(userProfileCacheKey);
      // **FIX: Only use cache if _id is a valid 24-char hex ObjectId**
      if (cached && cached._id && /^[a-f0-9]{24}$/i.test(cached._id.toString())) {
        user = cached;
      }
    }

    if (!user) {
      user = await User.findOne({ googleId: googleId }).select('_id googleId').lean();
      if (!user) return res.status(404).json({ error: 'User not found' });

      if (redisService.getConnectionStatus()) {
        await redisService.set(userProfileCacheKey, user, 600);
      }
    }


    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 9;
    let skip = req.query.skip !== undefined ? parseInt(req.query.skip) : (page - 1) * limit;

    const query = {
      uploader: user._id,
      videoUrl: { $exists: true, $ne: null, $ne: '' },
      processingStatus: { $nin: ['failed', 'error'] }
    };

    // **NEW: Filter by videoType or mediaType if provided**
    if (req.query.videoType) {
      query.videoType = req.query.videoType.toLowerCase();
    }
    if (req.query.mediaType) {
      query.mediaType = req.query.mediaType.toLowerCase();
    }

    const requestingGoogleId = req.user?.googleId || req.user?.id;
    const isOwner = requestingGoogleId === googleId;

    // **OPTIMIZATION: Parallelize independent DB queries and rank lookups**
    const [videos, totalValidVideos, rank, cachedEarnings] = await Promise.all([
      Video.find(query)
        .populate('uploader', 'name profilePic googleId')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .select('-description -shares')
        .lean(),
      Video.countDocuments(query),
      (!isOwner) ? RecommendationService.getGlobalCreatorRank(user._id) : Promise.resolve(0),
      (isOwner && redisService.getConnectionStatus()) ? redisService.get(`creator:earnings:${user._id}`) : Promise.resolve(null)
    ]);

    const validVideos = videos.filter(video => video.uploader && video.uploader.name);

    if (validVideos.length !== videos.length) {
      const validVideoIds = validVideos.map(v => v._id);
      // **OPTIMIZATION: Non-blocking data integrity fix**
      User.findByIdAndUpdate(user._id, { $set: { videos: validVideoIds } }).catch(e => console.error('Data sync error:', e));
    }

    const seriesIds = new Set();
    validVideos.forEach(v => { if (v.seriesId) seriesIds.add(v.seriesId); });

    let currentMonthEarnings = 0;
    if (isOwner) {
      if (cachedEarnings !== null) {
        currentMonthEarnings = typeof cachedEarnings === 'object' ? cachedEarnings.amount : parseFloat(cachedEarnings);
      } else {
        try {
            const now = new Date();
            const summary = await RevenueService.getCreatorRevenueSummary(user._id, now.getUTCMonth(), now.getUTCFullYear());
            
            if (summary.success) {
              currentMonthEarnings = summary.thisMonth;
              
              // **OPTIMIZATION: Cache earnings for 15 minutes to avoid heavy aggregations**
              if (redisService.getConnectionStatus()) {
                await redisService.set(`creator:earnings:${user._id}`, { amount: currentMonthEarnings, updatedAt: new Date() }, 900);
              }
            }
        } catch (err) { console.error('⚠️ Error calculating monthly earnings (unified):', err); }
      }
    }

    const episodesMap = new Map();
    if (seriesIds.size > 0) {
      try {
        const allEpisodes = await Video.find({ 
          seriesId: { $in: Array.from(seriesIds) }, 
          processingStatus: 'completed'
        })
          .select('_id videoName thumbnailUrl episodeNumber seriesId duration')
          .sort({ episodeNumber: 1 }).lean();
        allEpisodes.forEach(ep => {
          if (!episodesMap.has(ep.seriesId)) episodesMap.set(ep.seriesId, []);
          ep._id = ep._id.toString();
          episodesMap.get(ep.seriesId).push(ep);
        });
      } catch (err) { console.error('⚠️ Error fetching series episodes:', err); }
    }

    // Inject earnings/rank into uploader object
    const videosWithMetadata = validVideos.map(v => {
      if (v.uploader) {
        if (isOwner) {
          v.uploader.earnings = parseFloat(currentMonthEarnings.toFixed(2));
        } else {
          v.uploader.earnings = 0; // Hide actual earnings
          v.uploader.rank = rank;
        }
      }
      
      if (v.seriesId && episodesMap.has(v.seriesId)) {
        v.episodes = episodesMap.get(v.seriesId);
      }
      return v;
    });

    if (videosWithMetadata.length === 0) return res.json([]);

    const requestingUserGoogleId = req.user?.googleId;
    let requestingUserObjectIdStr = null;
    if (requestingUserGoogleId) {
      const rqUser = await User.findOne({ googleId: requestingUserGoogleId }).select('_id').lean();
      if (rqUser) requestingUserObjectIdStr = rqUser._id.toString();
    }

    const videosSerialized = serializeVideos(videosWithMetadata, req.apiVersion, requestingUserObjectIdStr);
    
    if (redisService.getConnectionStatus()) {
      await redisService.set(cacheKey, videosSerialized, 600);
    }

    return res.json(videosSerialized);
  } catch (error) {
    console.error('❌ Error fetching user videos:', error);
    res.status(500).json({ error: 'Error fetching videos', details: error.message });
  }
};

/**
 * Get Removed Videos for Creator Dashboard (Transparency)
 * Fetches from the Moderation Log collection.
 */
export const getRemovedVideos = async (req, res) => {
  try {
    const googleId = req.user.googleId;
    if (!googleId) return res.status(401).json({ error: 'Unauthorized' });

    // Fetch records from the log collection instead of the main Video collection
    const removedStats = await RemovedVideoRecord.find({ uploaderId: googleId })
      .sort({ removedAt: -1 })
      .lean();

    const result = removedStats.map(v => {
      // Safely handle Date vs String for removedAt (lean results can vary)
      const removedDate = v.removedAt instanceof Date ? v.removedAt : new Date(v.removedAt);
      const expiresAt = new Date(removedDate.getTime() + (3 * 24 * 60 * 60 * 1000));

      return {
        _id: v._id.toString(),
        id: v._id.toString(), // Support both mappings
        videoName: v.videoName,
        thumbnailUrl: v.thumbnailUrl,
        reason: v.reason || 'Violation of Terms',
        removedAt: removedDate.toISOString(),
        expiresAt: expiresAt.toISOString()
      };
    });

    return res.json(result);
  } catch (error) {
    console.error('❌ Error fetching removed videos:', error);
    res.status(500).json({ error: 'Failed to fetch removed videos' });
  }
};

/**
 * Get Global Leaderboard
 */
export const getGlobalLeaderboard = async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 20;
    const leaderboard = await RecommendationService.getGlobalLeaderboard(limit);
    
    // Set caching header for the API response
    res.set('Cache-Control', 'public, max-age=3600'); // Cache for 1 hour on client/CDN
    
    return res.json(leaderboard);
  } catch (error) {
    console.error('❌ Error in getGlobalLeaderboard controller:', error);
    res.status(500).json({ error: 'Failed to fetch global leaderboard' });
  }
};

/**
 * Helper to populate episodes for a list of videos
 * Useful for feed and search results to show series navigation
 */
const populateEpisodesForVideos = async (videos) => {
  if (!videos || videos.length === 0) return;
  
  const seriesIds = new Set();
  videos.forEach(v => { if (v.seriesId) seriesIds.add(v.seriesId); });

  if (seriesIds.size > 0) {
    try {
      const allEpisodes = await mongoose.model('Video').find({ 
        seriesId: { $in: Array.from(seriesIds) }, 
        processingStatus: 'completed'
      })
        .select('_id videoName thumbnailUrl episodeNumber seriesId duration')
        .sort({ episodeNumber: 1 }).lean();
        
      const episodesMap = new Map();
      allEpisodes.forEach(ep => {
        if (!episodesMap.has(ep.seriesId)) episodesMap.set(ep.seriesId, []);
        ep._id = ep._id.toString();
        episodesMap.get(ep.seriesId).push(ep);
      });

      videos.forEach(v => {
        if (v.seriesId && episodesMap.has(v.seriesId)) {
          v.episodes = episodesMap.get(v.seriesId);
        }
      });
    } catch (err) { 
      console.error('⚠️ Error populating series episodes:', err); 
    }
  }
};

export const getFeed = async (req, res) => {
  try {
    let userId = null;
    const userIdFromToken = req.user?.googleId || req.user?.id;
    if (userIdFromToken) {
      userId = userIdFromToken;
    }

    const { videoType: queryVideoType, type: queryType, limit = 10, page = 1, clearSession } = req.query;
    const videoType = queryVideoType || queryType;
    const limitNum = parseInt(limit) || 5;
    const pageNum = parseInt(page) || 1;
    const deviceId = req.headers['x-device-id'];
    const userIdentifier = userId || deviceId || 'anon';
    
    const requestedType = (videoType || 'yog').toLowerCase();
    const type = requestedType; // Only 'yog' or 'vayu'
    console.log('🔍 Video Feed Request - type:', type, 'videoType param:', videoType);
    
    let finalVideos = [];
    let hasMore = false;
    let total = 0;

    // **UNIFIED FEED: Use Queue-based system for ALL video types (Yog & Vayu)**
    console.log(`📡 Feed Request - type: ${type}, user: ${userIdentifier}, limit: ${limitNum}`);
    
    // Clear queue if requested (pull-to-refresh)
    if (clearSession === 'true') {
      console.log(`🧹 Clearing ${type} queue for refresh`);
      await FeedQueueService.clearQueue(userIdentifier, type);
    }
    
    finalVideos = await FeedQueueService.popFromQueue(userIdentifier, type, limitNum);
    console.log(`✅ Queue Results: ${finalVideos.length} videos`);
    
    // Fallback if queue is empty or something failed
    if (finalVideos.length === 0) {
      console.log('⚠️ Queue empty, using fallback pagination');
      const skip = (pageNum - 1) * limitNum;
      const query = { 
        videoType: type,
        processingStatus: 'completed' // This already excludes 'removed'
      };
      
      finalVideos = await Video.find(query)
        .populate('uploader', 'name profilePic googleId')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limitNum)
        .lean();
    }

    hasMore = finalVideos.length > 0;
    total = 9999; // Queue-based feeds use continuous loading
    
    // **NEW: Enforce max 2 consecutive videos per creator across all feed types**
    finalVideos = RecommendationService.enforceMaxConsecutive(finalVideos, 2);

    // Populate episodes
    await populateEpisodesForVideos(finalVideos);

    let rqUserObjectIdStr = req.user?._id;
    if (!rqUserObjectIdStr && userId) {
      const rqUser = await User.findOne({ googleId: userId }).select('_id').lean();
      if (rqUser) {
        rqUserObjectIdStr = rqUser._id.toString();
      }
    }

    const serializedVideos = serializeVideos(finalVideos, req.apiVersion, rqUserObjectIdStr);

    res.json({
      videos: serializedVideos,
      hasMore: hasMore,
      total: total,
      currentPage: pageNum,
      totalPages: Math.ceil(total / limitNum),
      isPersonalized: !!userIdentifier
    });

  } catch (error) {
    console.error('❌ Error fetching videos:', error);
    res.status(500).json({ error: 'Failed to fetch videos', message: error.message });
  }
};

export const getVideoById = async (req, res) => {
  try {
    const videoId = req.params.id;
    const video = await Video.findById(videoId)
      .populate('uploader', 'name profilePic googleId');

    if (!video) return res.status(404).json({ error: 'Video not found' });

    const videoObj = video.toObject();
    const dubbedUrls =
      videoObj.dubbedUrls instanceof Map
        ? Object.fromEntries(videoObj.dubbedUrls.entries())
        : (videoObj.dubbedUrls || null);
    const normalizeUrl = (url) => url ? url.replace(/\\/g, '/') : url;
    const likedByGoogleIds = await convertLikedByToGoogleIds(videoObj.likedBy || []);

    const requestingGoogleId = req.user?.googleId || req.user?.id;
    const rqUserObjectIdStr = req.user?._id;
    
    // **PARALLEL OPTIMIZATION: Fetch series, uploader rank, and liked status in parallel**
    const [episodes, rank, isLiked] = await Promise.all([
      videoObj.seriesId ? 
        Video.find({ seriesId: videoObj.seriesId, processingStatus: 'completed' })
          .select('_id videoName thumbnailUrl episodeNumber seriesId duration')
          .sort({ episodeNumber: 1 }).lean().then(eps => eps.map(ep => ({ ...ep, _id: ep._id.toString() })))
        : Promise.resolve([]),
      (requestingGoogleId !== videoObj.uploader?.googleId?.toString())
        ? RecommendationService.getGlobalCreatorRank(videoObj.uploader?._id)
        : Promise.resolve(0),
      (rqUserObjectIdStr)
        ? Promise.resolve((videoObj.likedBy || []).some(id => id.toString() === rqUserObjectIdStr))
        : Promise.resolve(false)
    ]);

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
      aspectRatio: parseFloat(videoObj.aspectRatio) || 9 / 16,
      videoType: videoObj.videoType || 'yog',
      link: videoObj.link || null,
      uploadedAt: videoObj.uploadedAt?.toISOString?.() || new Date().toISOString(),
      processingStatus: videoObj.processingStatus || 'pending',
      processingProgress: videoObj.processingProgress || 0,
      processingError: videoObj.processingError || null,
      uploader: {
        id: videoObj.uploader?.googleId?.toString() || videoObj.uploader?._id?.toString() || '',
        _id: videoObj.uploader?._id?.toString() || '',
        googleId: videoObj.uploader?.googleId?.toString() || '',
        name: videoObj.uploader?.name || 'Unknown User',
        profilePic: videoObj.uploader?.profilePic || '',
        earnings: (req.user?.googleId === videoObj.uploader?.googleId?.toString()) 
          ? (parseFloat(videoObj.uploader?.earnings) || 0.0)
          : 0.0,
        rank: rank
      },
      hlsMasterPlaylistUrl: videoObj.hlsMasterPlaylistUrl || null,
      hlsPlaylistUrl: videoObj.hlsPlaylistUrl || null,
      isHLSEncoded: videoObj.isHLSEncoded || false,
      seriesId: videoObj.seriesId || null,
      episodeNumber: videoObj.episodeNumber || 0,
      episodes: episodes,
      likedBy: likedByGoogleIds,
      isLiked: isLiked,
      earnings: (req.user?.googleId === videoObj.uploader?.googleId?.toString())
        ? (parseFloat(videoObj.earnings) || 0.0)
        : 0.0,
      dubbedUrls: dubbedUrls
    };

    res.json(transformedVideo);
  } catch (error) {
    console.error('❌ Error getting video by ID:', error);
    res.status(500).json({ error: 'Failed to get video', details: error.message });
  }
};

/**
 * **Update Video Metadata**
 */
export const updateVideo = async (req, res) => {
  try {
    const videoId = req.params.id;
    const googleId = req.user.googleId;
    const { videoName, link, tags, seriesId, episodeNumber } = req.body;

    if (!videoName || videoName.trim() === '') {
      return res.status(400).json({ error: 'Video name is required' });
    }

    const user = await User.findOne({ googleId });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const video = await Video.findById(videoId).populate('uploader', 'name profilePic googleId');
    if (!video) return res.status(404).json({ error: 'Video not found' });

    // Verify ownership
    if (video.uploader._id.toString() !== user._id.toString()) {
      return res.status(403).json({ error: 'Not authorized to update this video' });
    }

    // Update metadata
    video.videoName = videoName.trim();
    
    // Optional fields
    if (link !== undefined) {
      video.link = link.trim();
    }
 
    if (seriesId !== undefined) {
      video.seriesId = seriesId;
    }
 
    if (episodeNumber !== undefined) {
      video.episodeNumber = parseInt(episodeNumber) || 0;
    }

    if (tags !== undefined) {
      if (Array.isArray(tags)) {
        video.tags = tags.map(t => t.trim().toLowerCase()).filter(t => t.length > 0);
      } else if (typeof tags === 'string') {
        video.tags = tags.split(',').map(t => t.trim().toLowerCase()).filter(t => t.length > 0);
      }
    }

    video.updatedAt = new Date();
    await video.save();

    // Invalidate caches
    if (redisService.getConnectionStatus()) {
      const keysToInvalidate = [
        'videos:feed:*',
        `videos:user:${googleId}`,
        VideoCacheKeys.all(),
        VideoCacheKeys.single(videoId),
        `video:data:${videoId}` // individual data cache
      ];

      // If this video is part of a series, invalidate siblings too
      if (video.seriesId) {
        try {
          const siblings = await Video.find({ seriesId: video.seriesId }).select('_id').lean();
          siblings.forEach(s => {
            keysToInvalidate.push(VideoCacheKeys.single(s._id.toString()));
            keysToInvalidate.push(`video:data:${s._id.toString()}`);
          });
        } catch (e) {
          console.error('⚠️ Failed to fetch siblings for cache invalidation:', e.message);
        }
      }

      await invalidateCache(keysToInvalidate);
    }

    // Return the FULL updated video with episodes
    const videoObj = video.toObject();
    
    // Fetch episodes for series sync
    let episodes = [];
    if (videoObj.seriesId) {
      episodes = await Video.find({ 
        seriesId: videoObj.seriesId, 
        processingStatus: 'completed' 
      })
        .select('_id videoName thumbnailUrl episodeNumber seriesId duration')
        .sort({ episodeNumber: 1 }).lean();
      episodes = episodes.map(ep => ({ ...ep, _id: ep._id.toString() }));
    }

    const likedByGoogleIds = await convertLikedByToGoogleIds(videoObj.likedBy || []);
    const transformedVideo = {
      _id: videoObj._id?.toString(),
      videoName: videoObj.videoName,
      videoUrl: videoObj.videoUrl || videoObj.hlsMasterPlaylistUrl || videoObj.hlsPlaylistUrl || '',
      thumbnailUrl: videoObj.thumbnailUrl || '',
      description: videoObj.description || '',
      likes: parseInt(videoObj.likes) || 0,
      views: parseInt(videoObj.views) || 0,
      shares: parseInt(videoObj.shares) || 0,
      duration: parseInt(videoObj.duration) || 0,
      aspectRatio: parseFloat(videoObj.aspectRatio) || 9 / 16,
      videoType: videoObj.videoType || 'yog',
      link: videoObj.link || null,
      uploadedAt: videoObj.uploadedAt?.toISOString?.() || new Date().toISOString(),
      uploader: {
        id: videoObj.uploader?.googleId?.toString() || videoObj.uploader?._id?.toString() || '',
        _id: videoObj.uploader?._id?.toString() || '',
        name: videoObj.uploader?.name || 'Unknown',
        profilePic: videoObj.uploader?.profilePic || '',
      },
      seriesId: videoObj.seriesId || null,
      episodeNumber: videoObj.episodeNumber || 0,
      episodes: episodes,
      tags: videoObj.tags || [],
      isLiked: videoObj.likedBy.some(id => id.toString() === user._id.toString()),
      likedBy: likedByGoogleIds
    };

    res.json({ 
      success: true, 
      message: 'Video updated successfully',
      video: transformedVideo
    });
  } catch (error) {
    console.error('❌ Error updating video:', error);
    res.status(500).json({ error: 'Failed to update video' });
  }
};

/**
 * **Update Video Series**
 * Specialized endpoint for linking multiple videos into a series.
 * This is much more efficient than updating episodes one by one.
 */
export const updateVideoSeries = async (req, res) => {
  try {
    const videoId = req.params.id; // Main identifier
    const googleId = req.user.googleId;
    const { episodeIds, seriesId } = req.body;

    if (!Array.isArray(episodeIds) || episodeIds.length === 0) {
      return res.status(400).json({ error: 'episodeIds array is required' });
    }

    const user = await User.findOne({ googleId }).select('_id').lean();
    if (!user) return res.status(404).json({ error: 'User not found' });

    // 1. Fetch all involved videos to verify ownership
    // Convert to Set to remove duplicates, then back to array
    const uniqueVideoIds = [...new Set([videoId, ...episodeIds])];
    const videos = await Video.find({ _id: { $in: uniqueVideoIds } });

    if (videos.length === 0) {
      return res.status(404).json({ error: 'Videos not found' });
    }

    // Verify ownership for all found videos
    for (const v of videos) {
      if (v.uploader.toString() !== user._id.toString()) {
        return res.status(403).json({ error: `Not authorized to update video: ${v._id}` });
      }
    }

    // 2. Determine target seriesId
    const targetSeriesId = seriesId || `series_${Date.now()}`;

    // 3. Unlink videos that were in the series but are no longer in the episodeIds list
    await Video.updateMany(
      { 
        seriesId: targetSeriesId, 
        uploader: user._id,
        _id: { $nin: uniqueVideoIds } 
      },
      { 
        $set: { 
          seriesId: null, 
          episodeNumber: 0,
          updatedAt: new Date()
        } 
      }
    );

    // 4. Update all provided videos in bulk
    const bulkOps = episodeIds.map((id, index) => ({
      updateOne: {
        filter: { _id: id },
        update: { 
          $set: { 
            seriesId: targetSeriesId, 
            episodeNumber: index + 1, // 1-indexed for episodes
            updatedAt: new Date()
          } 
        }
      }
    }));

    // Ensure the main video is also tagged correctly if not in the episodeIds list
    if (!episodeIds.includes(videoId)) {
      bulkOps.push({
        updateOne: {
          filter: { _id: videoId },
          update: { 
            $set: { 
              seriesId: targetSeriesId,
              updatedAt: new Date()
            } 
          }
        }
      });
    }

    if (bulkOps.length > 0) {
      await Video.bulkWrite(bulkOps);
    }

    // 5. Invalidate Caches for ALL involved videos
    if (redisService.getConnectionStatus()) {
      const keysToInvalidate = [
        'videos:feed:*',
        `videos:user:${googleId}`,
        VideoCacheKeys.all(),
        VideoCacheKeys.single(videoId),
        `video:data:${videoId}`
      ];

      uniqueVideoIds.forEach(id => {
        keysToInvalidate.push(VideoCacheKeys.single(id.toString()));
        keysToInvalidate.push(`video:data:${id.toString()}`);
      });
      
      await invalidateCache(keysToInvalidate);
    }

    // 5. Fetch fresh episodes list for response
    let episodes = await Video.find({ 
      seriesId: targetSeriesId, 
      processingStatus: 'completed' 
    })
    .select('_id videoName thumbnailUrl episodeNumber seriesId duration')
    .sort({ episodeNumber: 1 }).lean();

    episodes = episodes.map(ep => ({ ...ep, _id: ep._id.toString() }));

    res.json({
      success: true,
      message: 'Series linked and updated successfully',
      seriesId: targetSeriesId,
      episodes: episodes
    });

  } catch (error) {
    console.error('❌ Error updating video series:', error);
    res.status(500).json({ error: 'Failed to update video series', message: error.message });
  }
};

/**
 * Watch History Controllers
 */
export const syncWatchHistory = async (req, res) => {
  try {
    const googleId = req.user.googleId;
    const { deviceId } = req.body;

    if (!deviceId) return res.status(400).json({ error: 'deviceId is required' });

    // **IDENTITY OPTIMIZATION: Use pre-resolved req.user._id**
    let userObjectId = req.user._id;
    if (!userObjectId) {
      const user = await User.findOne({ googleId }).select('_id').lean();
      if (!user) return res.status(404).json({ error: 'User not found' });
      userObjectId = user._id;
    }

    // 1. Fetch all watch history for both identities in parallel
    const [userHistory, deviceHistory] = await Promise.all([
      WatchHistory.find({ userId: googleId }).lean(),
      WatchHistory.find({ userId: deviceId }).lean()
    ]);

    const userVideoIds = new Set(userHistory.map(h => h.videoId.toString()));
    const deviceVideoIds = new Set(deviceHistory.map(h => h.videoId.toString()));

    // 2. Prepare Bulk Operations
    const bulkOps = [];

    // Sync Device -> User
    deviceHistory.forEach(entry => {
      if (!userVideoIds.has(entry.videoId.toString())) {
        bulkOps.push({
          insertOne: {
            document: {
              userId: googleId,
              videoId: entry.videoId,
              watchedAt: entry.watchedAt,
              lastWatchedAt: entry.lastWatchedAt,
              watchDuration: entry.watchDuration,
              completed: entry.completed,
              watchCount: entry.watchCount,
              isAuthenticated: true
            }
          }
        });
      }
    });

    // Sync User -> Device
    userHistory.forEach(entry => {
      if (!deviceVideoIds.has(entry.videoId.toString())) {
        bulkOps.push({
          insertOne: {
            document: {
              userId: deviceId,
              videoId: entry.videoId,
              watchedAt: entry.watchedAt,
              lastWatchedAt: entry.lastWatchedAt,
              watchDuration: entry.watchDuration,
              completed: entry.completed,
              watchCount: entry.watchCount,
              isAuthenticated: false
            }
          }
        });
      }
    });

    if (bulkOps.length > 0) {
      await WatchHistory.bulkWrite(bulkOps, { ordered: false });
    }

    if (redisService.getConnectionStatus()) {
      await redisService.clearPattern(`videos:unwatched:ids:${googleId}:*`);
      await redisService.clearPattern(`videos:unwatched:ids:${deviceId}:*`);
    }

    res.json({
      success: true,
      message: 'Watch history synced successfully',
      syncedCount: bulkOps.length,
    });
  } catch (error) {
    console.error('❌ Error syncing watch history:', error);
    res.status(500).json({ error: 'Failed to sync watch history', message: error.message });
  }
};

export const trackWatch = async (req, res) => {
  try {
    const deviceId = req.body.deviceId || req.headers['x-device-id'];
    
    // **OPTIMIZATION: Use Identity from middleware (removes 800ms Google API fallback)**
    const userId = req.user?.googleId || req.user?.id;
    const isAuthenticated = !!req.user;

    const identityId = userId || deviceId;
    const videoId = req.params.id;
    const { duration = 0, completed = false } = req.body;

    if (!identityId) return res.status(400).json({ error: 'User identifier required' });
    if (!videoId || !mongoose.Types.ObjectId.isValid(videoId)) return res.status(400).json({ error: 'Invalid video ID' });

    const SKIM_THRESHOLD = 5;
    const isSkim = duration < SKIM_THRESHOLD;

    if (isSkim) {
      if (redisService.getConnectionStatus()) {
        const skimKey = `videos:seen_recently:${identityId}`;
        await redisService.addToSet(skimKey, [videoId]);
        await redisService.expire(skimKey, 259200);
      }
      await Video.findByIdAndUpdate(videoId, { $inc: { views: 1 } });
    } else {
      const watchEntry = await WatchHistory.trackWatch(identityId, videoId, { duration, completed, isAuthenticated });
      const video = await Video.findByIdAndUpdate(videoId, { $inc: { views: 1 } });
      
      // **NEW: Track Daily Stats (Sliding Window)**
      if (video && video.uploader) {
        updateCreatorDailyStats(video.uploader, { 
          views: 1, 
          watchTime: duration 
        }).catch(err => console.error('DailyStats Error:', err));
      }

      if (redisService.getConnectionStatus()) await redisService.addToLongTermWatchHistory(identityId, [videoId.toString()]);
    }

    // **OPTIMIZATION: Targeted Invalidation (Removes high-latency Redis SCAN/Choking)**
    if (redisService.getConnectionStatus()) {
      // Use fire-and-forget for non-critical cache clearing
      const clearCache = async () => {
        try {
          // Instead of clearPattern (SCAN), we delete most likely specific keys
          const types = ['all', 'yog', 'vayu', 'reel', 'short', 'long'];
          const keysToDel = [];
          
          types.forEach(type => {
            keysToDel.push(`feed:${identityId}:${type}`);
            keysToDel.push(`videos:unwatched:ids:${identityId}:${type}`);
            keysToDel.push(`videos:feed:user:${identityId}:${type}`);
          });
          
          // Pattern still needed for watch:history but we can make it more specific
          // Or just clear the main history key
          keysToDel.push(`watch:history:${identityId}`);
          
          if (keysToDel.length > 0) {
            await Promise.all(keysToDel.map(k => redisService.del(k)));
          }
        } catch (e) {
          console.log('ℹ️ Redis: Background cleanup error (ignored):', e.message);
        }
      };
      
      clearCache(); // Start in background
    }

    res.json({ success: true, message: 'Watch tracked successfully' });
  } catch (error) {
    console.error('❌ Error tracking watch:', error);
    res.status(500).json({ error: 'Failed to track watch', message: error.message });
  }
};

/**
 * **NEW: Track Video Skip**
 * Penalizes videos that users quickly swipe away.
 */
export const trackSkip = async (req, res) => {
  try {
    const userId = req.user?.googleId || req.user?.id || req.headers['x-device-id'];
    const videoId = req.params.id;

    if (!userId) return res.status(400).json({ error: 'User identifier required' });
    if (!videoId || !mongoose.Types.ObjectId.isValid(videoId)) {
      return res.status(400).json({ error: 'Invalid video ID' });
    }

    // 1. Update WatchHistory with isSkip: true
    await WatchHistory.findOneAndUpdate(
      { userId, videoId },
      { 
        $set: { isSkip: true, lastWatchedAt: new Date() },
        $inc: { watchCount: 1 },
        $setOnInsert: { watchedAt: new Date() }
      },
      { upsert: true }
    );

    // 2. Globally penalize the video
    const video = await Video.findByIdAndUpdate(videoId, { $inc: { skipCount: 1 } });

    // **NEW: Track Daily Stats (Sliding Window)**
    if (video && video.uploader) {
      updateCreatorDailyStats(video.uploader, { skips: 1 }).catch(err => console.error('DailyStats Error:', err));
    }

    // 3. Invalidate Redis cache for this user's feed
    if (redisService.getConnectionStatus()) {
      const types = ['all', 'yog', 'vayu', 'reel', 'short', 'long'];
      const keysToDel = types.map(type => `feed:${userId}:${type}`);
      keysToDel.push(`videos:unwatched:ids:${userId}:all`);
      await Promise.all(keysToDel.map(k => redisService.del(k)));
    }

    res.json({ success: true, message: 'Skip tracked successfully' });
  } catch (error) {
    console.error('❌ Error tracking skip:', error);
    res.status(500).json({ error: 'Failed to track skip', message: error.message });
  }
};

/**
 * **NEW: Batch sync watch events**
 * Critical for reducing network overhead for 1M+ users.
 */
export const syncWatchEvents = async (req, res) => {
  try {
    const { events } = req.body;
    const deviceId = req.headers['x-device-id'];
    const userId = req.user?.googleId || req.user?.id;
    const isAuthenticated = !!req.user;
    
    if (!events || !Array.isArray(events) || events.length === 0) {
      return res.status(400).json({ error: 'Missing or invalid events array' });
    }

    const identityId = userId || deviceId;
    if (!identityId) return res.status(400).json({ error: 'User identifier required' });

    const ops = [];
    const videoViewIncrements = {};

    for (const event of events) {
      const { videoId, duration = 0, completed = false, timestamp } = event;
      if (!videoId || !mongoose.Types.ObjectId.isValid(videoId)) continue;

      const eventDate = timestamp ? new Date(timestamp) : new Date();
      
      // Track views atomically
      videoViewIncrements[videoId] = (videoViewIncrements[videoId] || 0) + 1;

      // Track in WatchHistory
      ops.push({
        updateOne: {
          filter: { userId: identityId, videoId: videoId },
          update: {
            $set: {
              lastWatchedAt: eventDate,
              watchDuration: duration,
              completed: completed,
              isAuthenticated: isAuthenticated
            },
            $inc: { watchCount: 1 },
            $setOnInsert: { watchedAt: eventDate }
          },
          upsert: true
        }
      });
    }

    if (ops.length > 0) {
      // 1. Bulk update WatchHistory
      await WatchHistory.bulkWrite(ops, { ordered: false });

      // 2. Define videoOps for Bulk update Video views
      const videoOps = Object.entries(videoViewIncrements).map(([id, inc]) => ({
        updateOne: {
          filter: { _id: id },
          update: { $inc: { views: inc } }
        }
      }));

      if (videoOps.length > 0) {
        await Video.bulkWrite(videoOps, { ordered: false });
      }

      // **NEW: Track Daily Stats (Batch Processing)**
      // Collect per-creator aggregates from the batch
      const creatorDailyStatsMap = {};
      for (const event of events) {
        try {
          const video = await Video.findById(event.videoId).select('uploader').lean();
          if (video && video.uploader) {
            const creatorId = video.uploader.toString();
            if (!creatorDailyStatsMap[creatorId]) {
              creatorDailyStatsMap[creatorId] = { views: 0, watchTime: 0 };
            }
            creatorDailyStatsMap[creatorId].views += 1;
            creatorDailyStatsMap[creatorId].watchTime += (event.duration || 0);
          }
        } catch (e) { /* Ignore individual video fetch errors */ }
      }

      // Update daily stats for each creator found in batch
      for (const [creatorId, stats] of Object.entries(creatorDailyStatsMap)) {
        updateCreatorDailyStats(creatorId, stats).catch(err => console.error('DailyStats Batch Error:', err));
      }

      // 3. Update Redis Long-Term Watch History (Background)
      if (redisService.getConnectionStatus()) {
        const videoIdsStrings = events.map(e => e.videoId.toString());
        redisService.addToLongTermWatchHistory(identityId, videoIdsStrings).catch(e => 
          console.warn('⚠️ Redis: Batch watch sync failed (background):', e.message)
        );
      }
    }

    res.json({ 
      success: true, 
      processed: ops.length,
      message: `Successfully synced ${ops.length} watch events` 
    });

  } catch (error) {
    console.error('❌ Error syncing batch watch events:', error);
    res.status(500).json({ error: 'Failed to sync batch watch events', message: error.message });
  }
};

/**
 * Like Controllers
 */
export const toggleLike = async (req, res) => {
  try {
    const googleId = req.user.googleId;
    const videoId = req.params.id;

    if (!googleId) return res.status(400).json({ error: 'User not authenticated' });
    if (!videoId) return res.status(400).json({ error: 'Video ID is required' });

    const user = await User.findOne({ googleId });
    if (!user) return res.status(404).json({ error: 'User not found' });
    const userObjectId = user._id;

    const video = await Video.findById(videoId);
    if (!video) return res.status(404).json({ error: 'Video not found' });

    const likedByStrings = (video.likedBy || []).map(id => id?.toString?.() || String(id));
    const userLikedIndex = likedByStrings.indexOf(userObjectId.toString());

    let updatedVideo;
    if (userLikedIndex > -1) {
      updatedVideo = await Video.findByIdAndUpdate(videoId, { $pull: { likedBy: userObjectId }, $inc: { likes: -1 } }, { new: true });
    } else {
      updatedVideo = await Video.findByIdAndUpdate(videoId, { $push: { likedBy: userObjectId }, $inc: { likes: 1 } }, { new: true });
    }

    if (!updatedVideo) return res.status(404).json({ error: 'Video not found' });
    if (updatedVideo.likes < 0) { updatedVideo.likes = 0; await updatedVideo.save(); }

    const actualLikedByLength = updatedVideo.likedBy.length;
    if (updatedVideo.likes !== actualLikedByLength) {
      updatedVideo = await Video.findByIdAndUpdate(videoId, { $set: { likes: actualLikedByLength } }, { new: true });
    }

    if (redisService.getConnectionStatus()) {
      await invalidateCache(['videos:feed:*', 'videos:unwatched:ids:*', VideoCacheKeys.single(videoId), VideoCacheKeys.all(), `videos:user:${updatedVideo.uploader?.toString()}`, `videos:user:*`]);
    }

    await updatedVideo.populate('uploader', 'name profilePic googleId');

    const videoObj = updatedVideo.toObject();
    const likedByGoogleIds = await convertLikedByToGoogleIds(videoObj.likedBy || []);

    const transformedVideo = {
      _id: videoObj._id?.toString(),
      videoName: videoObj.videoName || '',
      videoUrl: videoObj.videoUrl || videoObj.hlsMasterPlaylistUrl || videoObj.hlsPlaylistUrl || '',
      thumbnailUrl: videoObj.thumbnailUrl || '',
      likes: likedByGoogleIds.length,
      views: parseInt(videoObj.views) || 0,
      shares: parseInt(videoObj.shares) || 0,
      description: videoObj.description || '',
      uploader: {
        id: videoObj.uploader?.googleId?.toString() || videoObj.uploader?._id?.toString() || '',
        _id: videoObj.uploader?._id?.toString() || '',
        googleId: videoObj.uploader?.googleId?.toString() || '',
        name: videoObj.uploader?.name || 'Unknown',
        profilePic: videoObj.uploader?.profilePic || '',
      },
      uploadedAt: videoObj.uploadedAt?.toISOString?.() || new Date().toISOString(),
      likedBy: likedByGoogleIds,
      isLiked: updatedVideo.likedBy.some(id => id.toString() === userObjectId.toString()),
      videoType: videoObj.videoType || 'yog',
      aspectRatio: parseFloat(videoObj.aspectRatio) || 9 / 16,
      duration: parseInt(videoObj.duration) || 0,
      link: videoObj.link || null,
      hlsMasterPlaylistUrl: videoObj.hlsMasterPlaylistUrl || null,
      hlsPlaylistUrl: videoObj.hlsPlaylistUrl || null,
      isHLSEncoded: videoObj.isHLSEncoded || false
    };

    res.json(transformedVideo);
  } catch (err) {
    console.error('❌ Like API Error:', err);
    res.status(500).json({ error: 'Failed to toggle like', details: err.message });
  }
};

/**
 * Toggle Save Video (Bookmark)
 */
export const toggleSave = async (req, res) => {
  try {
    const googleId = req.user.googleId;
    const videoId = req.params.id;

    if (!googleId) return res.status(400).json({ error: 'User not authenticated' });
    if (!videoId) return res.status(400).json({ error: 'Video ID is required' });

    const user = await User.findOne({ googleId });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const video = await Video.findById(videoId);
    if (!video) return res.status(404).json({ error: 'Video not found' });

    // **REFACTORED: Use NEW async methods**
    const isSaved = await user.isSaved(videoId);
    let saved;

    if (isSaved) {
      await user.unsaveVideo(videoId);
      saved = false;
    } else {
      await user.saveVideo(videoId);
      saved = true;
    }

    // No need for user.save() since methods use updateOne and separate collection

    res.json({
      success: true,
      isSaved: saved,
      message: saved ? 'Video saved to bookmarks' : 'Video removed from bookmarks'
    });
  } catch (error) {
    console.error('Error toggling save:', error);
    res.status(500).json({ error: 'Failed to toggle save' });
  }
};

export const getSavedVideos = async (req, res) => {
  try {
    const googleId = req.user.googleId;
    if (!googleId) return res.status(401).json({ error: 'Authentication required' });

    const user = await User.findOne({ googleId }).select('_id googleId').lean();
    if (!user) return res.status(404).json({ error: 'User not found' });

    // **REFACTORED: Query SavedVideo collection directly**
    const SavedVideo = mongoose.model('SavedVideo');
    const savedEntries = await SavedVideo.find({ user: user._id })
      .populate({
        path: 'video',
        populate: {
          path: 'uploader',
          select: 'name profilePic googleId'
        }
      })
      .sort({ createdAt: -1 })
      .lean();

    // Filter out any entries where video might have been deleted
    const validSavedVideos = savedEntries
      .map(entry => entry.video)
      .filter(v => v != null);

    const requestingUserObjectIdStr = user._id.toString();
    const serializedVideos = serializeVideos(validSavedVideos, req.apiVersion, requestingUserObjectIdStr);

    res.json(serializedVideos);
  } catch (error) {
    console.error('❌ Error fetching saved videos:', error);
    res.status(500).json({ error: 'Failed to fetch saved videos', details: error.message });
  }
};

export const deleteLike = async (req, res) => {
  try {
    const googleId = req.user.googleId;
    const videoId = req.params.id;

    if (!googleId) return res.status(401).json({ error: 'Authentication required' });
    const user = await User.findOne({ googleId });
    if (!user) return res.status(404).json({ error: 'User not found' });
    const userObjectId = user._id;

    const video = await Video.findById(videoId);
    if (!video) return res.status(404).json({ error: 'Video not found' });

    const likedByStrings = (video.likedBy || []).map(id => id?.toString?.() || String(id));
    const userLikedIndex = likedByStrings.indexOf(userObjectId.toString());

    if (userLikedIndex > -1) {
      video.likedBy.splice(userLikedIndex, 1);
      video.likes = Math.max(0, video.likes - 1);
      await video.save();
    }

    if (redisService.getConnectionStatus()) {
      await invalidateCache(['videos:feed:*', 'videos:unwatched:ids:*', VideoCacheKeys.single(videoId), VideoCacheKeys.all(), `videos:user:${video.uploader?.toString()}`, `videos:user:*`]);
    }

    const updatedVideo = await Video.findById(videoId).populate('uploader', 'name profilePic googleId');
    const videoObj = updatedVideo.toObject();
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
      uploader: {
        id: videoObj.uploader?.googleId?.toString() || videoObj.uploader?._id?.toString() || '',
        _id: videoObj.uploader?._id?.toString() || '',
        googleId: videoObj.uploader?.googleId?.toString() || '',
        name: videoObj.uploader?.name || 'Unknown',
        profilePic: videoObj.uploader?.profilePic || '',
      },
      uploadedAt: videoObj.uploadedAt?.toISOString?.() || new Date().toISOString(),
      likedBy: likedByGoogleIds,
      isLiked: updatedVideo.likedBy.some(id => id.toString() === userObjectId.toString()),
      videoType: videoObj.videoType || 'reel',
      aspectRatio: parseFloat(videoObj.aspectRatio) || 9 / 16,
      duration: parseInt(videoObj.duration) || 0,
      hlsMasterPlaylistUrl: videoObj.hlsMasterPlaylistUrl || null,
      hlsPlaylistUrl: videoObj.hlsPlaylistUrl || null,
      isHLSEncoded: videoObj.isHLSEncoded || false
    };

    res.json(transformedVideo);
  } catch (err) {
    console.error('❌ Unlike API Error:', err);
    res.status(500).json({ error: 'Failed to unlike video', details: err.message });
  }
};

/**
 * View Controllers
 */
export const incrementView = async (req, res) => {
  try {
    const videoId = req.params.id;
    const { deviceId } = req.body;
    const googleId = req.user?.googleId;

    if (!videoId) return res.status(400).json({ error: 'Video ID is required' });

    const userIdentifier = googleId || deviceId || 'anonymous';
    const updatedVideo = await Video.findByIdAndUpdate(videoId, { $inc: { views: 1 } }, { new: true });
    if (!updatedVideo) return res.status(404).json({ error: 'Video not found' });

    console.log(`📊 [VIEW] Video: ${videoId}, User: ${userIdentifier}, New Count: ${updatedVideo.views}`);

    // **NEW: Track Daily Stats (Sliding Window)**
    if (updatedVideo.uploader) {
      updateCreatorDailyStats(updatedVideo.uploader, { views: 1 }).catch(err => console.error('DailyStats Error:', err));
    }

    if (userIdentifier && redisService.getConnectionStatus()) {
      // **OPTIMIZATION: Targeted Invalidation (Background)**
      const clearCache = async () => {
        try {
          const types = ['all', 'yog', 'vayu'];
          const keysToDel = [];
          
          types.forEach(type => {
            keysToDel.push(`videos:unwatched:ids:${userIdentifier}:${type}`);
            keysToDel.push(`videos:feed:user:${userIdentifier}:${type}`);
          });
          
          if (keysToDel.length > 0) {
            await Promise.all(keysToDel.map(k => redisService.del(k)));
          }
        } catch (e) {
          // Silent cleanup failure - not critical for user experience
        }
      };
      
      clearCache();
    }

    res.json({ success: true, views: updatedVideo.views });
  } catch (error) {
    console.error('❌ Error incrementing views:', error);
    res.status(500).json({ error: 'Failed to increment views' });
  }
};

/**
 * Video Deletion Controllers
 */
export const deleteVideo = async (req, res) => {
  try {
    const videoId = req.params.id;
    const googleId = req.user.googleId;

    const user = await User.findOne({ googleId });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const video = await Video.findById(videoId);
    if (!video) return res.status(404).json({ error: 'Video not found' });

    if (video.uploader.toString() !== user._id.toString()) {
      return res.status(403).json({ error: 'Not authorized to delete this video' });
    }

    await Video.findByIdAndDelete(videoId);
    await User.findByIdAndUpdate(user._id, { $pull: { videos: videoId } });

    if (redisService.getConnectionStatus()) {
      // **FIX: Robust cache invalidation using patterns**
      await invalidateCache([
        'videos:feed:*', 
        `videos:user:${googleId}`, 
        `user:feed:${googleId}:*`,
        VideoCacheKeys.all(), 
        VideoCacheKeys.single(videoId)
      ]);
    }

    console.log(`✅ Video ${videoId} deleted successfully by user ${googleId}`);
    res.json({ success: true, message: 'Video deleted successfully' });
  } catch (error) {
    console.error('❌ Error deleting video:', error);
    res.status(500).json({ error: 'Failed to delete video' });
  }
};


export const bulkDeleteVideos = async (req, res) => {
  try {
    const { videoIds } = req.body;
    const googleId = req.user.googleId;

    if (!Array.isArray(videoIds) || videoIds.length === 0) {
      return res.status(400).json({ error: 'No video IDs provided' });
    }

    const user = await User.findOne({ googleId });
    if (!user) return res.status(404).json({ error: 'User not found' });

    // **FIX: Explicitly convert hex strings to ObjectIds for $in query reliability**
    const objectIds = videoIds.map(id => new mongoose.Types.ObjectId(id));

    const result = await Video.deleteMany({ 
      _id: { $in: objectIds }, 
      uploader: user._id 
    });

    await User.findByIdAndUpdate(user._id, { 
      $pull: { videos: { $in: objectIds } } 
    });

    if (redisService.getConnectionStatus()) {
      // **FIX: Robust cache invalidation for bulk delete**
      const patterns = [
        'videos:feed:*',
        `videos:user:${googleId}`,
        `user:feed:${googleId}:*`,
        VideoCacheKeys.all()
      ];
      
      // Also clear individual video caches
      for (const id of videoIds) {
        patterns.push(VideoCacheKeys.single(id));
      }

      await invalidateCache(patterns);
    }

    console.log(`✅ Bulk delete: ${result.deletedCount} videos deleted for user ${googleId}`);
    res.json({ 
      success: true, 
      message: `Successfully deleted ${result.deletedCount} videos`,
      deletedCount: result.deletedCount
    });
  } catch (error) {
    console.error('❌ Bulk delete error:', error);
    res.status(500).json({ error: 'Failed to delete videos' });
  }
};

/**
 * Utility & Cleanup Controllers
 */
export const cleanupTempHLS = async (req, res) => {
  try {
    const tempDir = path.join(process.cwd(), 'temp', 'hls');
    if (fs.existsSync(tempDir)) {
      const folders = fs.readdirSync(tempDir);
      let count = 0;
      for (const folder of folders) {
        const folderPath = path.join(tempDir, folder);
        if (fs.statSync(folderPath).isDirectory()) {
          fs.rmSync(folderPath, { recursive: true, force: true });
          count++;
        }
      }
      res.json({ success: true, message: `Cleaned up ${count} temp HLS folders` });
    } else {
      res.json({ success: true, message: 'Temp HLS directory does not exist' });
    }
  } catch (error) {
    console.error('❌ Cleanup error:', error);
    res.status(500).json({ error: 'Failed to cleanup temp HLS' });
  }
};

export const generateSignedUrl = async (req, res) => {
  try {
    const { folder, fileName } = req.body;
    const { default: cloudinary } = await import('cloudinary');
    const signature = cloudinary.v2.utils.api_sign_request(
      { timestamp: Math.round(new Date().getTime() / 1000), folder },
      process.env.CLOUD_SECRET
    );
    res.json({ signature, timestamp: Math.round(new Date().getTime() / 1000), cloudName: process.env.CLOUD_NAME, apiKey: process.env.CLOUD_KEY });
  } catch (error) {
    res.status(500).json({ error: 'Failed to generate signature' });
  }
};

export const getCloudinaryConfig = async (req, res) => {
  res.json({ cloudName: process.env.CLOUD_NAME, apiKey: process.env.CLOUD_KEY, uploadPreset: 'ml_default' });
};

export const cleanupOrphaned = async (req, res) => {
  try {
    const videos = await Video.find({}).select('uploader').lean();
    const videoIds = videos.map(v => v._id);
    const users = await User.find({ videos: { $in: videoIds } });
    
    let updatedCount = 0;
    for (const user of users) {
      const validVideos = user.videos.filter(id => videoIds.some(vid => vid.equals(id)));
      if (validVideos.length !== user.videos.length) {
        user.videos = validVideos;
        await user.save();
        updatedCount++;
      }
    }
    res.json({ success: true, message: `Checked ${users.length} users, updated ${updatedCount}` });
  } catch (error) {
    res.status(500).json({ error: 'Cleanup failed' });
  }
};

export const cleanupBrokenVideos = async (req, res) => {
  try {
    const result = await Video.deleteMany({
      $or: [
        { videoUrl: { $exists: false } },
        { videoUrl: '' },
        { thumbnailUrl: { $exists: false } },
        { thumbnailUrl: '' }
      ],
      processingStatus: 'completed'
    });
    res.json({ success: true, message: `Deleted ${result.deletedCount} broken videos` });
  } catch (error) {
    res.status(500).json({ error: 'Cleanup failed' });
  }
};

export const syncUserVideoArrays = async (req, res) => {
  try {
    const users = await User.find({});
    let totalUpdated = 0;
    for (const user of users) {
      const activeVideos = await Video.find({ uploader: user._id }).select('_id').lean();
      const activeIds = activeVideos.map(v => v._id.toString());
      user.videos = activeIds;
      await user.save();
      totalUpdated++;
    }
    res.json({ success: true, updatedUsers: totalUpdated });
  } catch (error) {
    res.status(500).json({ error: 'Sync failed' });
  }
};

/**
 * Creator Analytics Controller
 * Aggregates stats for all videos owned by a creator
 */
export const getCreatorAnalytics = async (req, res) => {
  try {
    const { userId } = req.params; // This is the Google ID
    
    // Find internal user ID
    const user = await User.findOne({ googleId: userId }).select('_id').lean();
    if (!user) return res.status(404).json({ error: 'User not found' });

    const creatorId = user._id;

    // 1. Get Sliding Window Data (Last 14 Days)
    const today = new Date();
    today.setUTCHours(0, 0, 0, 0);
    const fourteenDaysAgo = new Date(today);
    fourteenDaysAgo.setDate(today.getDate() - 14);
    const sevenDaysAgo = new Date(today);
    sevenDaysAgo.setDate(today.getDate() - 7);

    const dailyStats = await CreatorDailyStats.find({
      creatorId,
      date: { $gte: fourteenDaysAgo }
    }).sort({ date: 1 }).lean();

    // 2. Aggregate Core Metrics from Sliding Window
    let totalViews = 0;
    let totalWatchTime = 0;
    let totalSkips = 0;
    let totalShares = 0; // **FIX: Use actual shares**
    let currViews = 0, prevViews = 0;
    let currWatch = 0, prevWatch = 0;

    dailyStats.forEach(stat => {
      totalViews += (stat.views || 0);
      totalWatchTime += (stat.watchTime || 0);
      totalSkips += (stat.skips || 0);
      totalShares += (stat.shares || 0); // **FIX: Sum actual shares from daily stats**

      const statDate = new Date(stat.date);
      if (statDate >= sevenDaysAgo) {
        currViews += (stat.views || 0);
        currWatch += (stat.watchTime || 0);
      } else {
        prevViews += (stat.views || 0);
        prevWatch += (stat.watchTime || 0);
      }
    });

    const overallAvgDuration = currViews > 0 ? (currWatch / currViews) : 0;
    const overallSkipRate = totalViews > 0 ? (totalSkips / totalViews) : 0;

    const calcGrowth = (curr, prev) => {
      if (prev === 0) return curr > 0 ? 100 : 0;
      return ((curr - prev) / prev) * 100;
    };

    const viewsGrowthRate = calcGrowth(currViews, prevViews);
    const watchTimeGrowthRate = calcGrowth(currWatch, prevWatch);

    const sparklineData = dailyStats
      .filter(s => new Date(s.date) >= sevenDaysAgo)
      .map(s => ({
        date: s.date.toISOString().split('T')[0],
        views: s.views,
        watchTime: parseFloat((s.watchTime / 60).toFixed(1)) // **FIX: Show decimals for precision**
      }));

    // 3. Top Performing Videos (Keep as is, but we could also pre-compute)
    const videos = await Video.find({ uploader: creatorId })
      .sort({ views: -1 })
      .limit(5)
      .select('_id videoName views shares cachedWatchTime')
      .lean();

    const topVideosFormatted = videos.map(v => ({
      id: v._id,
      title: v.videoName,
      views: v.views || 0,
      shares: v.shares || 0,
      watchTime: v.cachedWatchTime || 0
    }));

    // 4. Audience Insights (Looking at ALL creator videos, not just top 5)
    const allUserVideos = await Video.find({ uploader: creatorId }).select('_id').lean();
    const allVideoIds = allUserVideos.map(v => v._id);
    
    // Top Locations
    const topLocationsData = await WatchHistory.aggregate([
      { $match: { videoId: { $in: allVideoIds } } },
      { $lookup: { from: 'users', localField: 'userId', foreignField: 'googleId', as: 'viewer' } },
      { $unwind: "$viewer" },
      { $group: { _id: "$viewer.location.state", count: { $sum: 1 } } },
      { $sort: { count: -1 } },
      { $limit: 3 }
    ]);
    const totalAudienceViews = topLocationsData.reduce((acc, curr) => acc + curr.count, 0);
    const finalTopLocations = topLocationsData.map(stat => ({
      name: stat._id || "Others",
      value: totalAudienceViews > 0 ? Math.round((stat.count / totalAudienceViews) * 100) : 0
    }));

    // Retention (New vs Returning)
    const retentionStats = await WatchHistory.aggregate([
      { $match: { videoId: { $in: allVideoIds } } },
      { $group: { _id: "$userId", watchCount: { $sum: 1 } } },
      { $group: { _id: null, returning: { $sum: { $cond: [{ $gt: ["$watchCount", 1] }, 1, 0] } }, total: { $sum: 1 } } }
    ]);
    const countReturning = retentionStats[0]?.returning || 0;
    const countTotal = retentionStats[0]?.total || 0;
    const countNew = countTotal - countReturning;

    // Active Viewing Hours
    const activeViewingHours = await WatchHistory.aggregate([
      { $match: { videoId: { $in: allVideoIds } } },
      { $group: { _id: { $hour: "$watchedAt" }, count: { $sum: 1 } } },
      { $sort: { "_id": 1 } }
    ]);
    const hourlyMap = Array.from({ length: 24 }, (_, i) => {
      const stat = activeViewingHours.find(h => h._id === i);
      return { hour: i, count: stat ? stat.count : 0 };
    });

    res.json({
      core: {
        totalViews: totalViews || 0,
        totalShares: totalShares || 0, // **FIX: Use real shares**
        totalWatchTime: parseFloat((totalWatchTime / 60).toFixed(1)), // **FIX: Show decimals for precision**
        avgWatchDuration: Math.round(overallAvgDuration),
        skipRate: parseFloat(overallSkipRate.toFixed(2)),
        viewsGrowth: Math.round(viewsGrowthRate),
        watchTimeGrowth: Math.round(watchTimeGrowthRate)
      },
      topVideos: topVideosFormatted,
      dailyPerformance: sparklineData,
      audience: {
        topLocations: finalTopLocations.length > 0 ? finalTopLocations : [{ name: "Global", value: 100 }],
        activeTimes: hourlyMap,
        newVsReturning: {
          new: countNew,
          returning: countReturning
        }
      }
    });

  } catch (error) {
    console.error('❌ Error in getCreatorAnalytics:', error);
    res.status(500).json({ error: 'Failed to fetch creator analytics' });
  }
};
