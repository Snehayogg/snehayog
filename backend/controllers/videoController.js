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
import queueService from '../services/queueService.js';
import { VideoCacheKeys, invalidateCache } from '../middleware/cacheMiddleware.js';
import { AD_CONFIG } from '../constants/index.js';
import { calculateVideoHash, convertLikedByToGoogleIds } from '../utils/videoUtils.js';
import { serializeVideo, serializeVideos } from '../utils/serializers/videoSerializer.js';

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

    // 6. Determine video type based on duration
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

    let finalVideoType = videoType || 'yog';
    if (detectedDuration > 60) {
      finalVideoType = 'vayu';
    } else if (detectedDuration > 0) {
      finalVideoType = 'yog';
    }

    // 7. Create initial video record
    const video = new Video({
      videoName: videoName,
      description: description || '',
      link: link || '',
      uploader: user._id,
      videoType: finalVideoType,
      mediaType: 'video',
      aspectRatio: (detectedWidth && detectedHeight) ? detectedWidth / detectedHeight : 9 / 16,
      duration: detectedDuration || 0,
      originalResolution: { width: detectedWidth || 0, height: detectedHeight || 0 },
      processingStatus: 'pending',
      processingProgress: 0,
      isHLSEncoded: false,
      videoHash: videoHash,
      likes: 0, views: 0, shares: 0, likedBy: [], comments: [],
      uploadedAt: new Date(),
      seriesId: req.body.seriesId || null,
      episodeNumber: parseInt(req.body.episodeNumber) || 0
    });

    await video.save();
    user.videos.push(video._id);
    await user.save();

    // 8. Invalidate cache
    if (redisService.getConnectionStatus()) {
      await invalidateCache([
        'videos:feed:*',
        `videos:user:${user.googleId}`,
        VideoCacheKeys.all()
      ]);
    }

    // 9. Background Processing
    const rawVideoKey = `temp_raw/${user._id}/${Date.now()}_${path.basename(req.file.path)}`;
    
    // Cloudflare R2 Upload & Queueing
    const { default: cloudflareR2Service } = await import('../services/cloudflareR2Service.js');
    await cloudflareR2Service.uploadFileToR2(req.file.path, rawVideoKey, req.file.mimetype);
    
    await queueService.addVideoJob({
        videoId: video._id,
        rawVideoKey: rawVideoKey,
        videoName: videoName,
        userId: user._id.toString()
    });

    try { fs.unlinkSync(req.file.path); } catch (e) { console.warn('Failed to cleanup upload', e); }

    return res.status(201).json({
      success: true,
      message: 'Video uploaded and queued for processing.',
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

    if (redisService.getConnectionStatus()) {
      user = await redisService.get(userProfileCacheKey);
    }

    if (!user) {
      user = await User.findOne({ googleId: googleId }).lean();
      if (!user) return res.status(404).json({ error: 'User not found' });

      if (redisService.getConnectionStatus()) {
        await redisService.set(userProfileCacheKey, user, 600);
      }
    }

    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 9;
    let skip = req.query.skip !== undefined ? parseInt(req.query.skip) : (page - 1) * limit;

    const videos = await Video.find({
      uploader: user._id,
      videoUrl: { $exists: true, $ne: null, $ne: '' },
      processingStatus: { $nin: ['failed', 'error'] }
    })
      .populate('uploader', 'name profilePic googleId')
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(limit)
      .select('-description -shares')
      .lean();

    const validVideos = videos.filter(video => video.uploader && video.uploader.name);

    if (validVideos.length !== videos.length) {
      const validVideoIds = validVideos.map(v => v._id);
      await User.findByIdAndUpdate(user._id, { $set: { videos: validVideoIds } });
    }

    const totalValidVideos = await Video.countDocuments({
      uploader: user._id,
      videoUrl: { $exists: true, $ne: null, $ne: '' },
      processingStatus: { $nin: ['failed', 'error'] }
    });

    const seriesIds = new Set();
    validVideos.forEach(v => { if (v.seriesId) seriesIds.add(v.seriesId); });

    let currentMonthEarnings = 0;
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
    } catch (err) { console.error('⚠️ Error calculating monthly earnings:', err); }

    const formattedEarnings = currentMonthEarnings.toFixed(2);
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

    if (validVideos.length === 0) return res.json([]);

    const requestingGoogleId = req.user?.googleId;
    let requestingUserObjectIdStr = null;
    if (requestingGoogleId) {
      const rqUser = await User.findOne({ googleId: requestingGoogleId }).select('_id').lean();
      if (rqUser) requestingUserObjectIdStr = rqUser._id.toString();
    }

    const videosWithUrls = serializeVideos(validVideos, req.apiVersion);
    
    // **METRIC: Track this fetch**
    // console.log(`👤 UserVideos: Fetched ${videosWithUrls.length} videos for ${googleId}`);

    if (redisService.getConnectionStatus()) {
      await redisService.set(cacheKey, videosWithUrls, 600);
    }

    return res.json(videosWithUrls);
  } catch (error) {
    console.error('❌ Error fetching user videos:', error);
    res.status(500).json({ error: 'Error fetching videos', details: error.message });
  }
};

export const getFeed = async (req, res) => {
  try {
    let userId = null;
    try {
      const token = req.headers.authorization?.split(' ')[1];
      if (token) {
        try {
          const googleResponse = await fetch(`https://www.googleapis.com/oauth2/v2/userinfo?access_token=${token}`);
          if (googleResponse.ok) {
            const userInfo = await googleResponse.json();
            userId = userInfo.id;
          } else {
            const jwt = (await import('jsonwebtoken')).default;
            const JWT_SECRET = process.env.JWT_SECRET;
            if (JWT_SECRET) {
              const decoded = jwt.verify(token, JWT_SECRET);
              userId = decoded.id || decoded.googleId;
            }
          }
        } catch (tokenError) { console.log('⚠️ Token verification failed, using regular feed'); }
      }
    } catch (error) { console.log('⚠️ Error checking token, using regular feed'); }

    const { videoType: queryVideoType, type: queryType, limit = 10, page = 1 } = req.query;
    const videoType = queryVideoType || queryType;
    const limitNum = parseInt(limit) || 5;
    const pageNum = parseInt(page) || 1;
    const deviceId = req.headers['x-device-id'];
    const userIdentifier = userId || deviceId || 'anon';
    
    const requestedType = (videoType || 'yog').toLowerCase();
    const type = requestedType === 'vayug' ? 'vayu' : requestedType;
    
    let finalVideos = await FeedQueueService.popFromQueue(userIdentifier, type, limitNum);
    
    let rqUserObjectIdStr = null;
    if (userId) {
      console.log('🔍 getFeed Debug: userId from token:', userId);
      const rqUser = await User.findOne({ googleId: userId }).select('_id').lean();
      if (rqUser) {
        rqUserObjectIdStr = rqUser._id.toString();
        console.log('🔍 getFeed Debug: Found user, ObjectId:', rqUserObjectIdStr);
      } else {
        console.log('⚠️ getFeed Debug: User NOT FOUND in DB for googleId:', userId);
      }
    } else {
      console.log('🔍 getFeed Debug: No userId extracted from token');
    }

    const serializedVideos = serializeVideos(finalVideos, req.apiVersion);

    res.json({
      videos: serializedVideos,
      hasMore: serializedVideos.length > 0,
      total: 9999,
      currentPage: pageNum,
      totalPages: 9999,
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
    const normalizeUrl = (url) => url ? url.replace(/\\/g, '/') : url;
    const likedByGoogleIds = await convertLikedByToGoogleIds(videoObj.likedBy || []);

    let episodes = [];
    if (videoObj.seriesId) {
      try {
        episodes = await Video.find({ seriesId: videoObj.seriesId, processingStatus: 'completed' })
          .select('_id videoName thumbnailUrl episodeNumber seriesId duration')
          .sort({ episodeNumber: 1 }).lean();
        episodes = episodes.map(ep => ({ ...ep, _id: ep._id.toString() }));
      } catch (err) { console.error('⚠️ Error fetching series episodes:', err); }
    }

    const requestingGoogleId = req.user?.googleId;
    let isLiked = false;
    if (requestingGoogleId) {
      const rqUser = await User.findOne({ googleId: requestingGoogleId }).select('_id').lean();
      if (rqUser) {
        const rqUserObjectIdStr = rqUser._id.toString();
        isLiked = (videoObj.likedBy || []).some(id => id.toString() === rqUserObjectIdStr);
      }
    }

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
        profilePic: videoObj.uploader?.profilePic || ''
      },
      hlsMasterPlaylistUrl: videoObj.hlsMasterPlaylistUrl || null,
      hlsPlaylistUrl: videoObj.hlsPlaylistUrl || null,
      isHLSEncoded: videoObj.isHLSEncoded || false,
      seriesId: videoObj.seriesId || null,
      episodeNumber: videoObj.episodeNumber || 0,
      episodes: episodes,
      likedBy: likedByGoogleIds,
      isLiked: isLiked
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

    if (redisService.getConnectionStatus() && deviceId) {
      const deviceHistory = await redisService.getLongTermWatchHistory(deviceId);
      if (deviceHistory.size > 0) {
        await redisService.addToLongTermWatchHistory(googleId, Array.from(deviceHistory));
      }
    }

    if (!deviceId) return res.status(400).json({ error: 'deviceId is required' });

    const watchedByUserId = await WatchHistory.getUserWatchedVideoIds(googleId, null);
    const watchedByDeviceId = await WatchHistory.getUserWatchedVideoIds(deviceId, null);

    let syncedCount = 0;
    for (const videoId of watchedByDeviceId) {
      try {
        const exists = await WatchHistory.findOne({ userId: googleId, videoId: videoId });
        if (!exists) {
          const deviceEntry = await WatchHistory.findOne({ userId: deviceId, videoId: videoId });
          if (deviceEntry) {
            await WatchHistory.create({
              userId: googleId, videoId: videoId, watchedAt: deviceEntry.watchedAt,
              lastWatchedAt: deviceEntry.lastWatchedAt, watchDuration: deviceEntry.watchDuration,
              completed: deviceEntry.completed, watchCount: deviceEntry.watchCount, isAuthenticated: true
            });
            syncedCount++;
          }
        }
      } catch (error) { console.error(`⚠️ Error syncing video ${videoId}:`, error.message); }
    }

    let reverseSyncedCount = 0;
    for (const videoId of watchedByUserId) {
      try {
        const exists = await WatchHistory.findOne({ userId: deviceId, videoId: videoId });
        if (!exists) {
          const userEntry = await WatchHistory.findOne({ userId: googleId, videoId: videoId });
          if (userEntry) {
            await WatchHistory.create({
              userId: deviceId, videoId: videoId, watchedAt: userEntry.watchedAt,
              lastWatchedAt: userEntry.lastWatchedAt, watchDuration: userEntry.watchDuration,
              completed: userEntry.completed, watchCount: userEntry.watchCount, isAuthenticated: false
            });
            reverseSyncedCount++;
          }
        }
      } catch (error) { console.error(`⚠️ Error reverse syncing video ${videoId}:`, error.message); }
    }

    if (redisService.getConnectionStatus()) {
      await redisService.clearPattern(`videos:unwatched:ids:${googleId}:*`);
      await redisService.clearPattern(`videos:unwatched:ids:${deviceId}:*`);
    }

    res.json({
      success: true,
      message: 'Watch history synced successfully',
      syncedCount,
      reverseSyncedCount,
      finalCounts: {
        userId: (await WatchHistory.getUserWatchedVideoIds(googleId, null)).length,
        deviceId: (await WatchHistory.getUserWatchedVideoIds(deviceId, null)).length
      }
    });
  } catch (error) {
    console.error('❌ Error syncing watch history:', error);
    res.status(500).json({ error: 'Failed to sync watch history', message: error.message });
  }
};

export const trackWatch = async (req, res) => {
  try {
    let userId = null;
    let isAuthenticated = false;
    const deviceId = req.body.deviceId || req.headers['x-device-id'];

    try {
      const token = req.headers.authorization?.split(' ')[1];
      if (token) {
        try {
          const googleResponse = await fetch(`https://www.googleapis.com/oauth2/v2/userinfo?access_token=${token}`);
          if (googleResponse.ok) {
            const userInfo = await googleResponse.json();
            userId = userInfo.id;
            isAuthenticated = true;
          } else {
            const jwt = (await import('jsonwebtoken')).default;
            const JWT_SECRET = process.env.JWT_SECRET;
            if (JWT_SECRET) {
              const decoded = jwt.verify(token, JWT_SECRET);
              userId = decoded.id || decoded.googleId;
              isAuthenticated = true;
            }
          }
        } catch (tokenError) { console.log('ℹ️ Watch tracking: Token verification failed'); }
      }
    } catch (error) { console.log('ℹ️ Watch tracking: Error processing token'); }

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

    if (redisService.getConnectionStatus()) {
      await redisService.clearPattern(`watch:history:${identityId}*`);
      await redisService.clearPattern(`feed:${identityId}:*`);
      await redisService.clearPattern(`videos:unwatched:ids:${identityId}:*`);
      await redisService.clearPattern(`videos:feed:user:${identityId}:*`);
    }

    res.json({ success: true, message: 'Watch tracked successfully' });
  } catch (error) {
    console.error('❌ Error tracking watch:', error);
    res.status(500).json({ error: 'Failed to track watch', message: error.message });
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
    if (userIdentifier) {
      await FeedHistory.markAsSeen(userIdentifier, [videoId]);
      if (redisService.getConnectionStatus()) {
        await redisService.clearPattern(`videos:unwatched:ids:${userIdentifier}:*`);
        await redisService.clearPattern(`videos:feed:user:${userIdentifier}:*`);
      }
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
