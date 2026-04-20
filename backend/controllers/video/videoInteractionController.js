import mongoose from 'mongoose';
import Video from '../../models/Video.js';
import User from '../../models/User.js';
import WatchHistory from '../../models/WatchHistory.js';
import redisService from '../../services/caching/redisService.js';
import { invalidateCache, VideoCacheKeys } from '../../middleware/cacheMiddleware.js';
import { updateCreatorDailyStats } from '../../utils/analyticsUtils.js';
import { convertLikedByToGoogleIds } from '../../utils/videoUtils.js';
import { serializeVideos } from '../../utils/serializers/videoSerializer.js';

/**
 * Watch History Controllers
 */
export const syncWatchHistory = async (req, res) => {
  try {
    const googleId = req.user.googleId;
    const { deviceId } = req.body;

    if (!deviceId) return res.status(400).json({ error: 'deviceId is required' });

    let userObjectId = req.user._id;
    if (!userObjectId) {
      const user = await User.findOne({ googleId }).select('_id').lean();
      if (!user) return res.status(404).json({ error: 'User not found' });
      userObjectId = user._id;
    }

    const [userHistory, deviceHistory] = await Promise.all([
      WatchHistory.find({ userId: googleId }).lean(),
      WatchHistory.find({ userId: deviceId }).lean()
    ]);

    const userVideoIds = new Set(userHistory.map(h => h.videoId.toString()));
    const deviceVideoIds = new Set(deviceHistory.map(h => h.videoId.toString()));

    const bulkOps = [];

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
      await WatchHistory.trackWatch(identityId, videoId, { duration, completed, isAuthenticated });
      const video = await Video.findByIdAndUpdate(videoId, { $inc: { views: 1 } });
      
      if (video && video.uploader) {
        updateCreatorDailyStats(video.uploader, { 
          views: 1, 
          watchTime: duration 
        }).catch(err => console.error('DailyStats Error:', err));
      }

      if (redisService.getConnectionStatus()) await redisService.addToLongTermWatchHistory(identityId, [videoId.toString()]);
    }

    if (redisService.getConnectionStatus()) {
      const clearCache = async () => {
        try {
          const types = ['all', 'yog', 'vayu', 'reel', 'short', 'long'];
          const keysToDel = [];
          
          types.forEach(type => {
            keysToDel.push(`feed:${identityId}:${type}`);
            keysToDel.push(`videos:unwatched:ids:${identityId}:${type}`);
            keysToDel.push(`videos:feed:user:${identityId}:${type}`);
          });
          
          keysToDel.push(`watch:history:${identityId}`);
          
          if (keysToDel.length > 0) {
            await Promise.all(keysToDel.map(k => redisService.del(k)));
          }
        } catch (e) {
          console.log('ℹ️ Redis: Background cleanup error (ignored):', e.message);
        }
      };
      
      clearCache();
    }

    res.json({ success: true, message: 'Watch tracked successfully' });
  } catch (error) {
    console.error('❌ Error tracking watch:', error);
    res.status(500).json({ error: 'Failed to track watch', message: error.message });
  }
};

export const trackSkip = async (req, res) => {
  try {
    const userId = req.user?.googleId || req.user?.id || req.headers['x-device-id'];
    const videoId = req.params.id;

    if (!userId) return res.status(400).json({ error: 'User identifier required' });
    if (!videoId || !mongoose.Types.ObjectId.isValid(videoId)) {
      return res.status(400).json({ error: 'Invalid video ID' });
    }

    await WatchHistory.findOneAndUpdate(
      { userId, videoId },
      { 
        $set: { isSkip: true, lastWatchedAt: new Date() },
        $inc: { watchCount: 1 },
        $setOnInsert: { watchedAt: new Date() }
      },
      { upsert: true }
    );

    const video = await Video.findByIdAndUpdate(videoId, { $inc: { skipCount: 1 } });

    if (video && video.uploader) {
      updateCreatorDailyStats(video.uploader, { skips: 1 }).catch(err => console.error('DailyStats Error:', err));
    }

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
      
      videoViewIncrements[videoId] = (videoViewIncrements[videoId] || 0) + 1;

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
      await WatchHistory.bulkWrite(ops, { ordered: false });

      const videoOps = Object.entries(videoViewIncrements).map(([id, inc]) => ({
        updateOne: {
          filter: { _id: id },
          update: { $inc: { views: inc } }
        }
      }));

      if (videoOps.length > 0) {
        await Video.bulkWrite(videoOps, { ordered: false });
      }

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
        } catch (e) {}
      }

      for (const [creatorId, stats] of Object.entries(creatorDailyStatsMap)) {
        updateCreatorDailyStats(creatorId, stats).catch(err => console.error('DailyStats Batch Error:', err));
      }

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

    const isSaved = await user.isSaved(videoId);
    let saved;

    if (isSaved) {
      await user.unsaveVideo(videoId);
      saved = false;
    } else {
      await user.saveVideo(videoId);
      saved = true;
    }

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

    const validSavedVideos = savedEntries
      .map(entry => entry.video)
      .filter(v => v != null);

    const requestingUserObjectIdStr = user._id.toString();
    const serializedVideos = serializeVideos(validSavedVideos, req.apiVersion, requestingUserObjectIdStr, req.traceId);

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

export const incrementView = async (req, res) => {
  try {
    const videoId = req.params.id;
    const { deviceId } = req.body;
    const googleId = req.user?.googleId;

    if (!videoId) return res.status(400).json({ error: 'Video ID is required' });

    const userIdentifier = googleId || deviceId || 'anonymous';
    const updatedVideo = await Video.findByIdAndUpdate(videoId, { $inc: { views: 1 } }, { new: true });
    if (!updatedVideo) return res.status(404).json({ error: 'Video not found' });

    if (updatedVideo.uploader) {
      updateCreatorDailyStats(updatedVideo.uploader, { views: 1 }).catch(err => console.error('DailyStats Error:', err));
    }

    if (userIdentifier && redisService.getConnectionStatus()) {
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
        } catch (e) {}
      };
      
      clearCache();
    }

    res.json({ success: true, views: updatedVideo.views });
  } catch (error) {
    console.error('❌ Error incrementing views:', error);
    res.status(500).json({ error: 'Failed to increment views' });
  }
};
