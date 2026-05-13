import Video from '../../models/Video.js';
import FeedHistory from '../../models/FeedHistory.js';
import redisService from '../caching/redisService.js';
import RecommendationService from './recommendationService.js';
import mongoose from 'mongoose';

/**
 * Feed Queue Service
 * Implements Event Driven Feed Generation architecture.
 * Manages per-user video queues in Redis lists for instant playback.
 */
class FeedQueueService {
  constructor() {
    this.QUEUE_SIZE_LIMIT = 150;  // Max videos to hold in Redis per user
    this.REFILL_THRESHOLD = 40;   // Trigger refill when videos drop below this number
    this.BATCH_SIZE = 110;        // Number of videos to fetch during refill (Threshold + Batch = Limit)
  }

  getQueueKey(userId, videoType = 'yog') {
    return `user:feed:${userId}:${videoType}`;
  }

  async clearQueue(userId, videoType = 'yog') {
    const queueKey = this.getQueueKey(userId, videoType);
    if (!redisService.getConnectionStatus()) return false;
    try {
      await redisService.del(queueKey);
      return true;
    } catch (e) {
      console.error(`⚠️ FeedQueue: Clear queue failed:`, e.message);
      return false;
    }
  }

  async popFromQueue(userId, videoType = 'yog', limit = 5) {
    // OPTIMIZATION: Skip Redis entirely for anonymous users to save commands.
    // Anonymous users get a standard non-personalized feed from MongoDB.
    if (!userId || userId === 'anon' || userId === 'anonymous' || userId === 'undefined') {

      return [];
    }

    const queueKey = this.getQueueKey(userId, videoType);

    const videos = [];
    const tStart = Date.now();
    let currentLength = 0;
    let poppedIds = [];

    try {
      // OPTIMIZATION: Use native LPOP with count (Redis 6.2+) - counts as 1 request on Upstash
      // instead of Lua loop which counts each LPOP separately.
      const [len, popped] = await Promise.all([
        redisService.lLen(queueKey),
        redisService.lPop(queueKey, limit)
      ]);
      
      currentLength = len || 0;
      if (popped) {
        poppedIds = Array.isArray(popped) ? popped : [popped];
      }
    } catch (e) {
      console.error(`⚠️ FeedQueue: Redis lPop failed:`, e.message);
    }

    videos.push(...poppedIds);

    // OPTIMIZATION: Batch Bloom Filter operations and skip for anon users
    if (poppedIds.length > 0 && userId !== 'undefined' && userId !== 'anon') {
       const bfSeenKey = `user:bf_seen:${userId}`;
       // OPTIMIZATION: bfMAdd already calls EXPIRE internally, saving redundant exists/expire calls
       await redisService.bfMAdd(bfSeenKey, poppedIds);
    }

    // Refill trigger - OPTIMIZATION: Only trigger if significantly below threshold
    const projectedLength = Math.max(0, currentLength - poppedIds.length);
    if (projectedLength < this.REFILL_THRESHOLD) {
      this.generateAndPushFeed(userId, videoType).catch(() => {});
    }

    if (videos.length < limit) {
       const needed = limit - videos.length;
       const remainingQueued = projectedLength > 0 ? await redisService.lRange(queueKey, 0, -1) : [];

       const initialExcludes = new Set([...videos, ...remainingQueued]);

       const fallbackIds = await this.getFallbackIds(userId, videoType, needed, Array.from(initialExcludes));
       if (fallbackIds.length > 0) {
          console.log(`⚠️ Served ${fallbackIds.length} videos from MongoDB Fallback for user ${userId}`);
          videos.push(...fallbackIds);
       }
    }

    // Populate and sync hashes to DB
    const result = await this.populateVideos(videos);

    // OPTIMIZATION: Batch all DB operations and reduce Redis calls
    if (result.length > 0 && userId !== 'anon' && userId !== 'undefined') {
       // Primary Deduplication Sync (Hashes + IDs)
       FeedHistory.markAsSeen(userId, result).catch(() => {});

       // OPTIMIZATION: Only add hashes if they exist (reduce empty operations)
       const hashes = result.map(v => v.videoHash).filter(Boolean);
       if (hashes.length > 0) {
          const bfHashKey = `user:bf_hashes:${userId}`;
          // bfMAdd internally handles EXPIRE
          redisService.bfMAdd(bfHashKey, hashes).catch(() => {});
       }
    }

    console.log(`⏱️ Feed Latency: Total ${Date.now() - tStart}ms [${result.length} videos]`);
    return result;
  }

  async ensureBloomFilterSeeded(userId) {
    if (!userId || userId === 'anon' || userId === 'anonymous' || userId === 'undefined' || userId === 'null') return;
    const seededKey = `user:bf_seeded:${userId}`;
    if (await redisService.exists(seededKey)) return;

    const lockKey = `lock:seed:${userId}`;
    if (!(await redisService.setLock(lockKey, '1', 10))) return;

    try {
      console.log(`🔄 FeedQueue: Seeding Bloom Filter for ${userId}...`);
      const bfSeenKey = `user:bf_seen:${userId}`;
      const bfHashKey = `user:bf_hashes:${userId}`;
      const history = await FeedHistory.find({ userId }).sort({ seenAt: -1 }).limit(1000).select('videoId videoHash').lean();

      if (history.length > 0) {
          const ids = history.map(h => h.videoId.toString());
          const hashes = history.map(h => h.videoHash).filter(Boolean);

          // OPTIMIZATION: bfMAdd already calls EXPIRE internally
          await Promise.all([
            redisService.bfMAdd(bfSeenKey, ids),
            hashes.length > 0 ? redisService.bfMAdd(bfHashKey, hashes) : Promise.resolve(),
          ]);
      }
      await redisService.set(seededKey, 'true', 86400);
    } catch (e) {
      console.error('⚠️ FeedQueue: Seeding failed:', e.message);
    }
  }

  async generateAndPushFeed(userId, videoType = 'yog') {
    if (!userId || userId === 'anon' || userId === 'anonymous' || userId === 'undefined' || userId === 'null') return 0;
    const lockKey = `lock:refill:${userId}:${videoType}`;

    if (!(await redisService.setLock(lockKey, '1', 15))) return 0;

    try {
      await this.ensureBloomFilterSeeded(userId);
      let uploaderObjectId = null;
      if (userId && userId !== 'anon') {
        const User = mongoose.model('User');
        const userDoc = await User.findOne({ googleId: userId }).select('_id').lean();
        if (userDoc) uploaderObjectId = userDoc._id;
      }

      const queueKey = this.getQueueKey(userId, videoType);
      const seenVideoIds = new Set();

      // OPTIMIZATION: Combine lRange calls into one
      const [queuedIds, recentServed] = await Promise.all([
        redisService.lRange(queueKey, 0, -1),
        redisService.lRange(`user:recent_served:${userId}`, 0, -1)
      ]);

      queuedIds.forEach(id => seenVideoIds.add(id));
      recentServed.forEach(id => seenVideoIds.add(id));

      const matchQuery = {
          processingStatus: 'completed', 
          videoType,
          uploader: uploaderObjectId ? { $ne: uploaderObjectId } : { $exists: true },
          isSubscriberOnly: { $ne: true } // STRICT: Never show exclusive content in the main feed
      };

      // **OPTIMIZATION: Increase candidate pool to 1500 to allow more discovery**
      const candidates = await Video.find(matchQuery)
        .sort({ finalScore: -1, createdAt: -1 })
        .limit(1500)
        .select('_id uploader createdAt score finalScore videoType videoHash vectorEmbedding').lean();

      console.log(`🔍 FeedQueue: Found ${candidates.length} candidates for ${userId} (${videoType})`);

      if (candidates.length > 0) {
          const memFiltered = candidates.filter(v => !seenVideoIds.has(v._id.toString()));
          const bfSeenKey = `user:bf_seen:${userId}`;
          const bfHashKey = `user:bf_hashes:${userId}`;

          const [sFlags, hFlags] = await Promise.all([
              redisService.bfMExists(bfSeenKey, memFiltered.map(v => v._id.toString())),
              redisService.bfMExists(bfHashKey, memFiltered.map(v => v.videoHash).filter(Boolean))
          ]);

          const hashFlagsMap = new Map(memFiltered.map(v => v.videoHash).filter(Boolean).map((h, i) => [h, hFlags[i]]));
          const finalBatch = [];

          for (let i = 0; i < memFiltered.length; i++) {
              const video = memFiltered[i];
              if (sFlags[i] || (video.videoHash && hashFlagsMap.get(video.videoHash))) continue;
              finalBatch.push(video);
              if (finalBatch.length >= this.BATCH_SIZE) break;
          }

          if (finalBatch.length > 0) {
              const randomized = RecommendationService.weightedShuffle(finalBatch, this.BATCH_SIZE);
              const ordered = RecommendationService.orderFeedWithDiversity(randomized, { minCreatorSpacing: 4 });
              const pushIds = ordered.map(v => v._id.toString());

              const hashes = ordered.map(v => v.videoHash).filter(Boolean);
              await Promise.all([
                redisService.rPush(queueKey, pushIds),
                redisService.lTrim(queueKey, 0, this.QUEUE_SIZE_LIMIT - 1),
                redisService.bfMAdd(bfSeenKey, pushIds),
                hashes.length > 0 ? redisService.bfMAdd(bfHashKey, hashes) : Promise.resolve(),
              ]);
              console.log(`✅ FeedQueue: Pushed ${pushIds.length} videos to Redis for ${userId} (${videoType})`);
          } else {
              console.log(`⚠️ FeedQueue: No new videos to push for ${userId} (${videoType}) after filtering.`);
          }
      }
      return 1;
    } catch (error) {
      console.error('❌ FeedQueue: Refill Error:', error);
      return 0;
    }
  }

  async getFallbackIds(userId, videoType = 'yog', count = 10, excludedIds = []) {
    await this.ensureBloomFilterSeeded(userId);
    const excludeSet = new Set(excludedIds.map(id => id.toString()));
    const finalIds = [];
    const redisAvailable = redisService.getConnectionStatus();

    // Redis-down safety: use DB feed history as strong dedupe source
    if (userId && userId !== 'anon' && userId !== 'undefined' && userId !== 'null') {
      try {
        const recentHistory = await FeedHistory.find({ userId })
          .sort({ seenAt: -1 })
          .limit(300)
          .select('videoId')
          .lean();
        recentHistory.forEach(h => {
          if (h?.videoId) excludeSet.add(h.videoId.toString());
        });
      } catch (e) {}
    }

    // Strategy 1: Discovery with BF lookup
    try {
      const matchStage = { 
        processingStatus: 'completed',
        videoType,
        isSubscriberOnly: { $ne: true }, // STRICT: Never show exclusive content in fallback feed
        _id: { $nin: Array.from(excludeSet).map(id => { try { return new mongoose.Types.ObjectId(id); } catch(e) { return null; } }).filter(Boolean) }
      };

      const candidates = await Video.find(matchStage)
        .sort({ finalScore: -1, createdAt: -1 })
        .limit(200)
        .select('_id videoHash uploader finalScore createdAt')
        .lean();

      if (candidates.length > 0) {
          let filtered = candidates;
          if (redisAvailable) {
            const sFlags = await redisService.bfMExists(`user:bf_seen:${userId}`, candidates.map(v => v._id.toString()));
            filtered = candidates.filter((v, i) => !sFlags[i]);
          }

          // Add controlled randomness + creator diversity so fallback does not feel static
          const randomized = RecommendationService.weightedShuffle(filtered, Math.min(filtered.length, count * 3));
          const ordered = RecommendationService.orderFeedWithDiversity(randomized, { minCreatorSpacing: 3 });
          finalIds.push(...ordered.slice(0, count).map(v => v._id.toString()));
      }
    } catch (e) {
      console.error('⚠️ FeedQueue: getFallbackIds Strategy 1 failed:', e.message);
    }

    // Strategy 2: LRU Fallback
    if (finalIds.length < count && userId && userId !== 'anon') {
       const need = count - finalIds.length;
       const lruOldestIds = await FeedHistory.getLRUVideos(userId, 50, [], 48);
       if (lruOldestIds.length > 0) {
          const filtered = lruOldestIds.filter(id => !excludeSet.has(id.toString()) && !finalIds.includes(id.toString())).slice(0, need);
          finalIds.push(...filtered.map(id => id.toString()));
       }
    }

    return finalIds;
  }

  async populateVideos(videoIds) {
    if (!videoIds || videoIds.length === 0) return [];
    const ids = videoIds.map(id => id.toString()).filter(Boolean);
    const videos = new Array(ids.length).fill(null);
    const missingIds = [];
    const missingIndices = [];

    const cacheKeys = ids.map(id => `video:data:${id}`);
    const cachedDocs = await redisService.mget(cacheKeys);
    
    cachedDocs.forEach((doc, index) => {
      if (doc) videos[index] = doc;
      else { missingIndices.push(index); missingIds.push(ids[index]); }
    });

    if (missingIds.length > 0) {
      const dbDocs = await Video.find({ _id: { $in: missingIds } })
        .select('videoUrl thumbnailUrl description uploader views likes shares comments duration processingStatus createdAt videoHash videoName tags seriesId episodeNumber videoType aspectRatio quizzes')
        .populate('uploader', 'name profilePic googleId username')
        .lean();

      const dbMap = new Map(dbDocs.map(v => [v._id.toString(), v]));
      const toCache = [];
      missingIndices.forEach((origIdx) => {
        const video = dbMap.get(ids[origIdx]);
        if (video) {
          video._id = video._id.toString();
          videos[origIdx] = video;
          toCache.push([`video:data:${video._id}`, video]);
        }
      });
      if (toCache.length > 0) redisService.mset(toCache, 3600).catch(() => {});
    }

    return videos.filter(Boolean);
  }

  async addRecentCreators(userId, creatorIds) {
    if (!creatorIds || creatorIds.length === 0) return;
    const key = `user:recent_creators:${userId}`;
    // OPTIMIZATION: Batch all operations together
    await Promise.all([
      redisService.lPush(key, creatorIds),
      redisService.lTrim(key, 0, 19),
      redisService.expire(key, 3600),
    ]);
  }

  async getRecentCreators(userId) {
    try { return await redisService.lRange(`user:recent_creators:${userId}`, 0, -1); }
    catch (e) { return []; }
  }

  checkBatchDiversity(candidate, existingBatch) {
    if (!candidate.vectorEmbedding || candidate.vectorEmbedding.length === 0) return false;
    const lastFew = existingBatch.slice(-10);
    for (const v of lastFew) {
        if (v.vectorEmbedding && RecommendationService.calculateCosineSimilarity(candidate.vectorEmbedding, v.vectorEmbedding) > 0.85) return true;
    }
    return false;
  }

  /**
   * Merge Guest History into Authenticated User History
   */
  async mergeGuestHistory(deviceId, userId) {
    if (!deviceId || !userId || deviceId === userId || deviceId === 'anon') return;
    console.log(`🔄 FeedQueue: Merging guest history from ${deviceId} to ${userId}`);

    try {
      const guestSeenKey = `user:bf_seen:${deviceId}`;
      const guestHashKey = `user:bf_hashes:${deviceId}`;
      const userSeenKey = `user:bf_seen:${userId}`;
      const userHashKey = `user:bf_hashes:${userId}`;

      // Transfer history in DB
      const guestHistory = await FeedHistory.find({ userId: deviceId }).select('videoId videoHash').lean();
      if (guestHistory.length > 0) {
        await FeedHistory.markAsSeen(userId, guestHistory);

        // OPTIMIZATION: bfMAdd already calls EXPIRE internally
        const ids = guestHistory.map(h => h.videoId.toString());
        const hashes = guestHistory.map(h => h.videoHash).filter(Boolean);

        await Promise.all([
          redisService.bfMAdd(userSeenKey, ids),
          hashes.length > 0 ? redisService.bfMAdd(userHashKey, hashes) : Promise.resolve(),
          redisService.del(guestSeenKey),
          redisService.del(guestHashKey),
          FeedHistory.deleteMany({ userId: deviceId })
        ]);
      }
      console.log(`✅ FeedQueue: Merged guest history successfully.`);
    } catch (e) {
      console.error('❌ FeedQueue: mergeGuestHistory failed:', e.message);
    }
  }
}

export default new FeedQueueService();
