import Video from '../../models/Video.js';
import User from '../../models/User.js';
import CreatorDailyStats from '../../models/CreatorDailyStats.js';
import WatchHistory from '../../models/WatchHistory.js';
import redisService from '../../services/caching/redisService.js';

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
        cacheStatus[name] = { pattern, error: error.message };
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
    res.status(500).json({ error: 'Failed to check cache status' });
  }
};

export const clearCache = async (req, res) => {
  try {
    const { pattern, userId, platformId, videoType, clearAll } = req.body;

    if (!redisService.getConnectionStatus()) {
      return res.json({ success: false, message: 'Redis is not connected' });
    }

    let clearedCount = 0;
    const clearedPatterns = [];

    if (clearAll) {
      const patterns = ['videos:*', 'videos:feed:*', 'videos:unwatched:ids:*', 'video:*'];
      for (const p of patterns) {
        const count = await redisService.clearPattern(p);
        clearedCount += count;
        if (count > 0) clearedPatterns.push({ pattern: p, keysCleared: count });
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
        if (count > 0) clearedPatterns.push({ pattern: p, keysCleared: count });
      }
    }

    res.json({ success: true, message: `Cleared ${clearedCount} cache keys`, clearedPatterns });
  } catch (error) {
    console.error('❌ Error clearing cache:', error);
    res.status(500).json({ error: 'Failed to clear cache' });
  }
};

/**
 * Creator Analytics Controller
 */
export const getCreatorAnalytics = async (req, res) => {
  try {
    const { userId } = req.params;
    const user = await User.findOne({ googleId: userId }).select('_id').lean();
    if (!user) return res.status(404).json({ error: 'User not found' });

    const creatorId = user._id;

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

    let totalViews = 0, totalWatchTime = 0, totalSkips = 0, totalShares = 0;
    let currViews = 0, prevViews = 0, currWatch = 0, prevWatch = 0;

    dailyStats.forEach(stat => {
      totalViews += (stat.views || 0);
      totalWatchTime += (stat.watchTime || 0);
      totalSkips += (stat.skips || 0);
      totalShares += (stat.shares || 0);

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

    const sparklineData = dailyStats
      .filter(s => new Date(s.date) >= sevenDaysAgo)
      .map(s => ({
        date: s.date.toISOString().split('T')[0],
        views: s.views,
        watchTime: parseFloat((s.watchTime / 60).toFixed(1))
      }));

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

    const allUserVideos = await Video.find({ uploader: creatorId }).select('_id').lean();
    const allVideoIds = allUserVideos.map(v => v._id);
    
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

    const retentionStats = await WatchHistory.aggregate([
      { $match: { videoId: { $in: allVideoIds } } },
      { $group: { _id: "$userId", watchCount: { $sum: 1 } } },
      { $group: { _id: null, returning: { $sum: { $cond: [{ $gt: ["$watchCount", 1] }, 1, 0] } }, total: { $sum: 1 } } }
    ]);
    const countReturning = retentionStats[0]?.returning || 0;
    const countTotal = retentionStats[0]?.total || 0;
    const countNew = countTotal - countReturning;

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
        totalShares: totalShares || 0,
        totalWatchTime: parseFloat((totalWatchTime / 60).toFixed(1)),
        avgWatchDuration: Math.round(overallAvgDuration),
        skipRate: parseFloat(overallSkipRate.toFixed(2)),
        viewsGrowth: Math.round(calcGrowth(currViews, prevViews)),
        watchTimeGrowth: Math.round(calcGrowth(currWatch, prevWatch))
      },
      topVideos: topVideosFormatted,
      dailyPerformance: sparklineData,
      audience: {
        topLocations: finalTopLocations.length > 0 ? finalTopLocations : [{ name: "Global", value: 100 }],
        activeTimes: hourlyMap,
        newVsReturning: { new: countNew, returning: countReturning }
      }
    });

  } catch (error) {
    console.error('❌ Error in getCreatorAnalytics:', error);
    res.status(500).json({ error: 'Failed to fetch creator analytics' });
  }
};
