import mongoose from 'mongoose';
import fs from 'fs';
import path from 'path';
import Video from '../models/Video.js';
import User from '../models/User.js';
import View from '../models/View.js';
import WatchHistory from '../models/WatchHistory.js';
import FeedHistory from '../models/FeedHistory.js';
import AdImpression from '../models/AdImpression.js';
import redisService from '../services/redisService.js';
import FeedQueueService from '../services/feedQueueService.js';
import RecommendationService from '../services/recommendationService.js';
import queueService from '../services/queueService.js';
import { VideoCacheKeys, invalidateCache } from '../middleware/cacheMiddleware.js';
import { AD_CONFIG } from '../constants/index.js';
import { calculateVideoHash, convertLikedByToGoogleIds } from '../utils/videoUtils.js';
import { serializeVideo, serializeVideos } from '../utils/serializers/videoSerializer.js';
import cloudflareR2Service from '../services/cloudflareR2Service.js';

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
      const { default: service } = await import('../services/hybridVideoService.js');
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
      comments: 0,
      shares: 0,
      views: 0,
      uploadedAt: new Date()
    });

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
      finalScore: initialScore
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
        const { default: cloudflareR2Service } = await import('../services/cloudflareR2Service.js');
        await cloudflareR2Service.uploadFileToR2(tempFilePath, rawVideoKey, tempMimeType);
        
        await queueService.addVideoJob({
            videoId: video._id,
            rawVideoKey: rawVideoKey,
            videoName: videoName,
            userId: user._id.toString()
        });

        console.log(`✅ Upload: Background processing complete for video ${video._id}`);
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
            const startOfMonth = new Date(Date.UTC(now.getFullYear(), now.getMonth(), 1));
            const endOfMonth = new Date(Date.UTC(now.getFullYear(), now.getMonth() + 1, 1));

            const impressionStats = await AdImpression.aggregate([
              { $match: { creatorId: user._id, isViewed: true, timestamp: { $gte: startOfMonth, $lt: endOfMonth } } },
              { $group: { _id: '$adType', count: { $sum: 1 } } }
            ]);

            const bannerCpm = AD_CONFIG?.BANNER_CPM ?? 10;
            const carouselCpm = AD_CONFIG?.DEFAULT_CPM ?? 30;
            const creatorShare = AD_CONFIG?.CREATOR_REVENUE_SHARE ?? 0.8;

            let bannerViews = 0, carouselViews = 0;
            impressionStats.forEach(stat => {
              if (stat._id === 'banner') bannerViews = stat.count;
              else carouselViews += stat.count;
            });

            currentMonthEarnings = ((bannerViews / 1000) * bannerCpm + (carouselViews / 1000) * carouselCpm) * creatorShare;
            
            // **OPTIMIZATION: Cache earnings for 15 minutes to avoid heavy aggregations**
            if (redisService.getConnectionStatus()) {
              await redisService.set(`creator:earnings:${user._id}`, { amount: currentMonthEarnings, updatedAt: new Date() }, 900);
            }
        } catch (err) { console.error('⚠️ Error calculating monthly earnings:', err); }
      }
    }

    const episodesMap = new Map();
    if (seriesIds.size > 0) {
      try {
        const allEpisodes = await Video.find({ seriesId: { $in: Array.from(seriesIds) }, processingStatus: 'completed' })
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

    if (type === 'vayu') {
      // **PROGRESSIVE LOADING: Use standard pagination for Vayu (Long-form)**
      // Bypass FeedQueueService to ensure the user can scroll through ALL videos
      const skip = (pageNum - 1) * limitNum;
      
      const query = { 
        videoType: 'vayu',
        processingStatus: 'completed'
      };

      // Check if there are ANY vayu videos in the database
      const totalVayuCount = await Video.countDocuments({ videoType: 'vayu', processingStatus: 'completed' });
      console.log('📊 Total Vayu videos in DB:', totalVayuCount);
      
      // Also check landscape videos that might be misclassified
      const landscapeVideos = await Video.find({ 
        processingStatus: 'completed',
        aspectRatio: { $gt: 1.0 }
      }).select('videoName videoType aspectRatio duration').limit(5).lean();
      
      console.log('🎬 Landscape videos (AR > 1.0):', landscapeVideos.length);
      if (landscapeVideos.length > 0) {
        landscapeVideos.forEach((v, i) => {
          console.log(`  ${i+1}. ${v.videoName} | Type: ${v.videoType} | AR: ${v.aspectRatio?.toFixed(2)} | Duration: ${v.duration}s`);
        });
      }

      // Exclude own videos from feed if user is logged in
      if (userId && userId !== 'anon' && userId !== 'undefined') {
        const user = await User.findOne({ googleId: userId }).select('_id').lean();
        if (user) {
          console.log('👤 User found, excluding own videos from feed:', user._id);
          query.uploader = { $ne: user._id };
        }
      } else {
        console.log('ℹ️ No valid user, showing all videos');
      }

      console.log('📊 Vayu Query:', JSON.stringify(query));
      [finalVideos, total] = await Promise.all([
        Video.find(query)
          .populate('uploader', 'name profilePic googleId')
          .sort({ createdAt: -1 })
          .skip(skip)
          .limit(limitNum)
          .lean(),
        Video.countDocuments(query)
      ]);

      console.log(`✅ Vayu Results: ${finalVideos.length} videos, Total: ${total}`);
      if (finalVideos.length > 0) {
        finalVideos.forEach((v, i) => {
          console.log(`  ${i+1}. ${v.videoName} | Type: ${v.videoType} | AR: ${v.aspectRatio?.toFixed(2)} | Duration: ${v.duration}s`);
        });
      }

      hasMore = skip + finalVideos.length < total;
    } else {
      // **DISCOVERY FEED: Use Queue-based system for Yog (Short-form)**
      console.log('🧘 Yog Feed Request - type:', type, 'userIdentifier:', userIdentifier, 'limit:', limitNum);
      
      // Clear queue if requested (pull-to-refresh)
      if (clearSession === 'true') {
        console.log('🧹 Clearing Yog queue for refresh');
        await FeedQueueService.clearQueue(userIdentifier, type);
      }
      
      finalVideos = await FeedQueueService.popFromQueue(userIdentifier, type, limitNum);
      console.log(`✅ Yog Queue Results: ${finalVideos.length} videos`);
      if (finalVideos.length > 0) {
        finalVideos.forEach((v, i) => {
          console.log(`  ${i+1}. ${v.videoName} | Type: ${v.videoType} | AR: ${v.aspectRatio?.toFixed(2)} | Duration: ${v.duration}s`);
        });
      } else {
        console.log('⚠️ Yog Queue returned NO videos!');
      }
      hasMore = finalVideos.length > 0;
      total = 9999;
    }
    
    // **NEW: Enforce max 2 consecutive videos per creator across all feed types**
    finalVideos = RecommendationService.enforceMaxConsecutive(finalVideos, 2);

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
      await Video.findByIdAndUpdate(videoId, { $inc: { views: 1 } });
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
    await Video.findByIdAndUpdate(videoId, { $inc: { skipCount: 1 } });

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

      // 2. Atomic view increments for Videos
      const videoOps = Object.entries(videoViewIncrements).map(([vId, inc]) => ({
        updateOne: {
          filter: { _id: vId },
          update: { $inc: { views: inc } }
        }
      }));
      await Video.bulkWrite(videoOps, { ordered: false });

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

    const updatedVideo = await Video.findByIdAndUpdate(videoId, { $inc: { views: 1 } }, { new: true });
    if (!updatedVideo) return res.status(404).json({ error: 'Video not found' });

    const userIdentifier = googleId || deviceId;
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
          console.log('ℹ️ Redis: Background cleanup error:', e.message);
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
      await invalidateCache(['videos:feed:*', `videos:user:${googleId}`, VideoCacheKeys.all(), VideoCacheKeys.single(videoId)]);
    }

    res.json({ success: true, message: 'Video deleted successfully' });
  } catch (error) {
    console.error('❌ Error deleting video:', error);
    res.status(500).json({ error: 'Failed to delete video' });
  }
};

/**
 * **Update Video Metadata**
 */
export const updateVideo = async (req, res) => {
  try {
    const videoId = req.params.id;
    const googleId = req.user.googleId;
    const { videoName } = req.body;

    if (!videoName || videoName.trim() === '') {
      return res.status(400).json({ error: 'Video name is required' });
    }

    const user = await User.findOne({ googleId });
    if (!user) return res.status(404).json({ error: 'User not found' });

    const video = await Video.findById(videoId);
    if (!video) return res.status(404).json({ error: 'Video not found' });

    // Verify ownership
    if (video.uploader.toString() !== user._id.toString()) {
      return res.status(403).json({ error: 'Not authorized to update this video' });
    }

    // Update metadata
    video.videoName = videoName.trim();
    video.updatedAt = new Date();
    await video.save();

    // Invalidate caches
    if (redisService.getConnectionStatus()) {
      await invalidateCache([
        'videos:feed:*',
        `videos:user:${googleId}`,
        VideoCacheKeys.all(),
        VideoCacheKeys.single(videoId)
      ]);
    }

    res.json({ 
      success: true, 
      message: 'Video updated successfully',
      video: {
        id: video._id,
        videoName: video.videoName
      }
    });
  } catch (error) {
    console.error('❌ Error updating video:', error);
    res.status(500).json({ error: 'Failed to update video' });
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

    const result = await Video.deleteMany({ _id: { $in: videoIds }, uploader: user._id });
    await User.findByIdAndUpdate(user._id, { $pull: { videos: { $in: videoIds } } });

    if (redisService.getConnectionStatus()) {
      await invalidateCache(['videos:feed:*', `videos:user:${googleId}`, VideoCacheKeys.all()]);
      for (const id of videoIds) await invalidateCache(VideoCacheKeys.single(id));
    }

    res.json({ success: true, message: `Deleted ${result.deletedCount} videos` });
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
