import mongoose from 'mongoose';
import Video from '../../models/Video.js';
import User from '../../models/User.js';
import RemovedVideoRecord from '../../models/RemovedVideoRecord.js';
import RecommendationService from '../../services/yugFeedServices/recommendationService.js';
import FeedQueueService from '../../services/yugFeedServices/feedQueueService.js';
import redisService from '../../services/caching/redisService.js';
import { invalidateCache, VideoCacheKeys } from '../../middleware/cacheMiddleware.js';
import { serializeVideo, serializeVideos } from '../../utils/serializers/videoSerializer.js';
import RevenueService from '../../services/adServices/revenueService.js';

/**
 * Helper to populate episodes for a list of videos
 */
const populateEpisodesForVideos = async (videos) => {
  if (!videos || videos.length === 0) return;
  
  const seriesIds = new Set();
  videos.forEach(v => { if (v.seriesId) seriesIds.add(v.seriesId); });

  if (seriesIds.size > 0) {
    try {
      const allEpisodes = await Video.find({ 
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

    if (req.user && (req.user.googleId === googleId || req.user.id === googleId) && req.user._id) {
       user = { _id: req.user._id, googleId: googleId };
    }

    if (!user && redisService.getConnectionStatus()) {
      const cached = await redisService.get(userProfileCacheKey);
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

    if (req.query.videoType) {
      query.videoType = req.query.videoType.toLowerCase();
    }
    if (req.query.mediaType) {
      query.mediaType = req.query.mediaType.toLowerCase();
    }

    const requestingGoogleId = req.user?.googleId || req.user?.id;
    const isOwner = requestingGoogleId === googleId;

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

    const videosWithMetadata = validVideos.map(v => {
      if (v.uploader) {
        if (isOwner) {
          v.uploader.earnings = parseFloat(currentMonthEarnings.toFixed(2));
        } else {
          v.uploader.earnings = 0;
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

    const videosSerialized = serializeVideos(videosWithMetadata, req.apiVersion, requestingUserObjectIdStr, req.traceId);
    
    if (redisService.getConnectionStatus()) {
      await redisService.set(cacheKey, videosSerialized, 600);
    }

    return res.json(videosSerialized);
  } catch (error) {
    console.error('❌ Error fetching user videos:', error);
    res.status(500).json({ error: 'Error fetching videos', details: error.message });
  }
};

export const getRemovedVideos = async (req, res) => {
  try {
    const googleId = req.user.googleId;
    if (!googleId) return res.status(401).json({ error: 'Unauthorized' });

    const removedStats = await RemovedVideoRecord.find({ uploaderId: googleId })
      .sort({ removedAt: -1 })
      .lean();

    const result = removedStats.map(v => {
      const removedDate = v.removedAt instanceof Date ? v.removedAt : new Date(v.removedAt);
      const expiresAt = new Date(removedDate.getTime() + (3 * 24 * 60 * 60 * 1000));

      return {
        _id: v._id.toString(),
        id: v._id.toString(),
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

export const getGlobalLeaderboard = async (req, res) => {
  try {
    const limit = parseInt(req.query.limit) || 20;
    const leaderboard = await RecommendationService.getGlobalLeaderboard(limit);
    res.set('Cache-Control', 'public, max-age=3600');
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

    const { videoType: queryVideoType, type: queryType, limit = 10, page = 1, clearSession, cursor } = req.query;
    const videoType = queryVideoType || queryType;
    const limitNum = parseInt(limit) || 5;
    const pageNum = parseInt(page) || 1;
    const deviceId = req.headers['x-device-id'];
    const userIdentifier = userId || deviceId || 'anon';
    
    const requestedType = (videoType || 'yog').toLowerCase();
    const type = requestedType;
    
    let finalVideos = [];
    let hasMore = false;
    let total = 0;

    if (clearSession === 'true') {
      await FeedQueueService.clearQueue(userIdentifier, type);
    }
    
    finalVideos = await FeedQueueService.popFromQueue(userIdentifier, type, limitNum);
    
    if (finalVideos.length === 0) {
      const query = { 
        videoType: type,
        processingStatus: 'completed'
      };

      if (cursor) {
        query.createdAt = { $lt: new Date(cursor) };
      }
      
      const videosQuery = Video.find(query)
        .populate('uploader', 'name profilePic googleId')
        .sort({ createdAt: -1 })
        .limit(limitNum);
      
      if (!cursor && pageNum > 1) {
        const skip = (pageNum - 1) * limitNum;
        videosQuery.skip(skip);
      }

      finalVideos = await videosQuery.lean();
    }

    hasMore = finalVideos.length > 0;
    total = 9999;
    
    finalVideos = RecommendationService.enforceMaxConsecutive(finalVideos, 2);
    await populateEpisodesForVideos(finalVideos);

    let rqUserObjectIdStr = req.user?._id;
    if (!rqUserObjectIdStr && userId) {
      const rqUser = await User.findOne({ googleId: userId }).select('_id').lean();
      if (rqUser) rqUserObjectIdStr = rqUser._id.toString();
    }

    const serializedVideos = serializeVideos(finalVideos, req.apiVersion, rqUserObjectIdStr, req.traceId);

    let nextCursor = null;
    if (finalVideos.length > 0) {
      const lastVideo = finalVideos[finalVideos.length - 1];
      nextCursor = lastVideo.createdAt || lastVideo.uploadedAt;
      if (nextCursor instanceof Date) nextCursor = nextCursor.toISOString();
    }

    res.json({
      videos: serializedVideos,
      hasMore: hasMore,
      total: total,
      currentPage: pageNum,
      nextCursor: nextCursor,
      totalPages: Math.ceil(total / limitNum),
      isPersonalized: userIdentifier !== 'anon'
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
    const requestingGoogleId = req.user?.googleId || req.user?.id;
    const rqUserObjectIdStr = req.user?._id;
    
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

    const transformedVideo = serializeVideo(videoObj, req.apiVersion, rqUserObjectIdStr, req.traceId);
    res.json(transformedVideo);
  } catch (error) {
    console.error('❌ Error getting video by ID:', error);
    res.status(500).json({ error: 'Failed to get video', details: error.message });
  }
};
