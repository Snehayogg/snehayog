import Video from '../models/Video.js';
import FeedHistory from '../models/FeedHistory.js';
import WatchHistory from '../models/WatchHistory.js';
import redisService from './redisService.js';
import RecommendationService from './recommendationService.js';
import mongoose from 'mongoose';

/**
 * Feed Queue Service
 * Implements Event Driven Feed Generation architecture.
 * Manages per-user video queues in Redis lists for instant playback.
 */
class FeedQueueService {
  constructor() {
    this.QUEUE_SIZE_LIMIT = 60;  // Max items in Redis list per user (Reduced for extreme freshness)
    this.REFILL_THRESHOLD = 40;  // Refill when below this (Buffered for safety)
    this.BATCH_SIZE = 50;        // Generate this many videos at once
  }


  /**
   * Get main feed video queue key
   */
  getQueueKey(userId, videoType = 'yog') {
    return `user:feed:${userId}:${videoType}`;
  }

  /**
   * Clear the user's feed queue (for refresh)
   */
  async clearQueue(userId, videoType = 'yog') {
    const queueKey = this.getQueueKey(userId, videoType);
    if (!redisService.getConnectionStatus()) return false;
    
    try {
      await redisService.del(queueKey);
      console.log(`🧹 FeedQueue: Cleared queue for ${userId} (${videoType})`);
      return true;
    } catch (e) {
      console.error(`⚠️ FeedQueue: Clear queue failed for ${userId}:`, e.message);
      return false;
    }
  }

  /**
   * Pop videos from the user's feed queue (INSTANT)
   * @param {string} userId - User ID
   * @param {string} videoType - 'yog' or 'vayu'
   * @param {number} count - Number of videos to pop
   * @returns {Promise<Array>} - Array of Video objects
   */
  /**
   * Pop videos from the user's feed queue (INSTANT)
   * @param {string} userId - User ID
   * @param {string} videoType - 'yog' or 'vayu'
   * @param {number} count - Number of videos to pop
   * @returns {Promise<Array>} - Array of Video objects
   */
  async popFromQueue(userId, videoType = 'yog', count = 10) {
    const queueKey = this.getQueueKey(userId, videoType);
    const seenKey = `user:seen_all:${userId}`;
    const videos = [];
    
    // **METRIC: Start Timer**
    const tStart = Date.now();
    let tRedisCheck = 0;
    let tRedisPop = 0;
    let tFallback = 0;
    let tPopulate = 0;

    // 1. Check current queue length
    let currentLength = 0;
    try {
      const t1 = Date.now();
      currentLength = await redisService.lLen(queueKey);
      tRedisCheck = Date.now() - t1;
    } catch (e) {
      console.error(`⚠️ FeedQueue: Redis lLen failed for ${userId}:`, e.message);
      currentLength = 0;
    }

    // 2. Pop available items from Redis
    let poppedIds = [];
    try {
      const t2 = Date.now();
      const popCount = Math.min(currentLength, count);
      if (popCount > 0) {
        const popped = await redisService.lPop(queueKey, popCount);
        if (Array.isArray(popped)) poppedIds = popped;
        else if (popped) poppedIds = [popped];
      }
      videos.push(...poppedIds);
      tRedisPop = Date.now() - t2;
    } catch (e) {
      console.error(`⚠️ FeedQueue: Redis lPop failed:`, e.message);
    }

    // 3. Mark popped videos as "Seen" IMMEDIATELY to prevent refill duplication
    if (poppedIds.length > 0 && userId !== 'anon' && userId !== 'undefined') {
       try {
          await redisService.sAdd(seenKey, poppedIds);
          await redisService.expire(seenKey, 604800);
          FeedHistory.markAsSeen(userId, poppedIds).catch(e => {}); // Background mark in DB
       } catch (e) {
          console.error('⚠️ FeedQueue: Error marking popped videos as seen:', e.message);
       }
    }

    // 4. Trigger Background Refill if projected length will be low
    // **FIX: Ordering** - Call refill AFTER marking popped videos in 'seenKey' set.
    const projectedLength = Math.max(0, currentLength - poppedIds.length);
    if (projectedLength < this.REFILL_THRESHOLD) {
      console.log(`⚡ FeedQueue: Queue will be LOW (${projectedLength} < ${this.REFILL_THRESHOLD}) for ${userId}. triggering background refill...`);
      // Fire and forget - do NOT await
      this.generateAndPushFeed(userId, videoType).catch(err => 
        console.error(`⚠️ FeedQueue: Background refill error for ${userId}:`, err.message)
      );
    }

    // 5. SAFETY NET: If we don't have enough videos, fill from Fallback immediately
    if (videos.length < count) {
       const t3 = Date.now();
       const needed = count - videos.length;
       console.log(`❄️ FeedQueue: Queue exhausted (got ${videos.length}). Fetching ${needed} from Safety Net.`);
       
       // Calculate exclusion list: Popped + all seen in history
       const initialExcludes = new Set(videos);
       
       if (userId !== 'anon' && userId !== 'undefined') {
          try {
             // Sync seen history if needed
             if (!(await redisService.exists(seenKey))) {
                const history = await FeedHistory.find({ userId }).select('videoId').lean();
                if (history && history.length > 0) {
                   const idsToSync = history.map(h => h.videoId.toString());
                   await redisService.sAdd(seenKey, idsToSync);
                   await redisService.expire(seenKey, 604800);
                   idsToSync.forEach(id => initialExcludes.add(id));
                }
             } else {
                const seenAll = await redisService.sMembers(seenKey);
                seenAll.forEach(id => initialExcludes.add(id));
             }
          } catch(e) { /* ignore */ }
       }

       const fallbackIds = await this.getFallbackIds(userId, videoType, needed, Array.from(initialExcludes));
       if (fallbackIds.length > 0) {
          // Mark Fallback items as seen too
          if (userId !== 'anon' && userId !== 'undefined') {
             await redisService.sAdd(seenKey, fallbackIds);
             FeedHistory.markAsSeen(userId, fallbackIds).catch(e => {});
          }
          videos.push(...fallbackIds);
       }
       tFallback = Date.now() - t3;
    }

    // 6. Populate video details
    const t4 = Date.now();
    const result = await this.populateVideos(videos);
    tPopulate = Date.now() - t4;

    // **SMART: Mark hashes of delivered videos as "Seen"**
    // This prevents re-uploads of the same content from appearing
    if (result.length > 0 && userId !== 'anon' && userId !== 'undefined') {
       const hashes = result.map(v => v.videoHash).filter(Boolean);
       if (hashes.length > 0) {
          const hashKey = `user:seen_hashes:${userId}`;
          redisService.sAdd(hashKey, hashes).catch(() => {});
          redisService.expire(hashKey, 604800).catch(() => {});
       }
    }

    const tTotal = Date.now() - tStart;
    console.log(`⏱️ Feed Latency: Total ${tTotal}ms (Redis: ${tRedisCheck + tRedisPop}ms | Fallback: ${tFallback}ms | Populate: ${tPopulate}ms) [${result.length} videos]`);

    return result;
  }

  /**
   * Async helper to track impressions in DB
   */
  async trackImpressionsAsync(userId, videoIds) {
      if (!FeedHistory || !videoIds || videoIds.length === 0) return;
      try {
          const operations = videoIds.map(videoId => ({
              updateOne: {
                  filter: { userId, videoId },
                  update: { $set: { seenAt: new Date() } },
                  upsert: true
              }
          }));
          await FeedHistory.bulkWrite(operations, { ordered: false });
          // console.log(`👁️ Tracked ${videoIds.length} impressions for ${userId}`);
      } catch (e) {
          console.error('⚠️ FeedQueue: bulkWrite DB Error:', e.message);
      }
  }

  /**
   * Check queue length and trigger refill if needed
   */
  async checkAndRefillQueue(userId, videoType = 'yog') {
    // **LOCK CHECK (Optimization)**: Don't even check length if locked
    const lockKey = `lock:refill:${userId}:${videoType}`;
    if (await redisService.exists(lockKey)) return;

    const queueKey = this.getQueueKey(userId, videoType);
    const length = await redisService.lLen(queueKey);

    if (length < this.REFILL_THRESHOLD) {
      console.log(`⚡ FeedQueue: checkAndRefill - Queue LOW (${length} < ${this.REFILL_THRESHOLD}) for ${userId}. Refilling...`);
      await this.generateAndPushFeed(userId, videoType);
    }
  }

  /**
   * Add creators to "Recent" list to prevent flooding (Interleaving)
   */
  async addRecentCreators(userId, creatorIds) {
    if (!creatorIds || creatorIds.length === 0) return;
    const key = `user:recent_creators:${userId}`;
    try {
      // Push to head
      await redisService.lPush(key, creatorIds);
      // Keep only last 20
      await redisService.lTrim(key, 0, 19);
      // Expire after 1 hour
      await redisService.expire(key, 3600);
    } catch (e) {
      console.error('⚠️ FeedQueue: Error adding recent creators:', e.message);
    }
  }

  /**
   * Get recent creators list to check for spacing
   */
  async getRecentCreators(userId) {
    const key = `user:recent_creators:${userId}`;
    try {
      return await redisService.lRange(key, 0, -1);
    } catch (e) {
      return [];
    }
  }

  /**
   * Generate personalized feed and push to Redis queue
   * @returns {Promise<number>} - Number of videos pushed
   */
  async generateAndPushFeed(userId, videoType = 'yog') {
    console.log('DEBUG: Entered generateAndPushFeed');
    // **1. REFILL LOCK ("Bharosa Lock")**
    // Prevent double-booking race conditions
    const lockKey = `lock:refill:${userId}:${videoType}`;
    console.log('DEBUG: Attempting to acquire lock', lockKey);
    const acquiredLock = await redisService.setLock(lockKey, '1', 15); // 15s lock
    console.log('DEBUG: Lock acquired?', acquiredLock);
    if (!acquiredLock) {
        console.log(`🔒 FeedQueue: Refill locked for ${userId}, skipping duplicate trigger.`);
        return 0;
    }

    const start = Date.now();
    console.log(`♻️ Refill STARTED for ${userId}`);
    
    try {
      // 1. Fetch User History & Context
      const queueKey = this.getQueueKey(userId, videoType);
      
      // Get "Seen" context to avoid duplicates
      const seenVideoIds = new Set();
      
      // A. Currently in Queue
      const queuedIds = await redisService.lRange(queueKey, 0, -1);
      queuedIds.forEach(id => seenVideoIds.add(id));

      // B. In-flight / Session Buffer
      const recentKey = `user:recent_served:${userId}`;
      const recentServed = await redisService.lRange(recentKey, 0, -1);
      recentServed.forEach(id => seenVideoIds.add(id));

      // C. Recent Creators (For Diversity Interleaving)
      // "Who did we just see? Let's give them a break."
      const recentCreatorIds = await this.getRecentCreators(userId);
      const recentCreatorSet = new Set(recentCreatorIds);

      // D. Sync from DB if Cold Start
      const seenKey = `user:seen_all:${userId}`;
      const hashKey = `user:seen_hashes:${userId}`;
      if (FeedHistory && !(await redisService.exists(seenKey))) {
          try {
             const history = await FeedHistory.find({ userId }).select('videoId videoHash').lean();
             if (history.length > 0) {
                 await redisService.sAdd(seenKey, history.map(h => h.videoId.toString()));
                 const hashes = history.map(h => h.videoHash).filter(Boolean);
                 if (hashes.length > 0) await redisService.sAdd(hashKey, hashes);
                 
                 await redisService.expire(seenKey, 604800);
                 await redisService.expire(hashKey, 604800);
             }
          } catch(e) {/* ignore */}
      }

      // Fetch Hashes from Redis for O(1) in-memory Filtering
      const seenHashesSet = await redisService.getSetMembers(hashKey);

      // 2. Iterative Batch Search ("Discovery Aware")

      
      // **SMART RATIO**: Popular (50%), Recent (30%), Discovery (20%)
      let POPULAR_TARGET = Math.ceil(this.BATCH_SIZE * 0.5);
      let RECENT_TARGET = Math.ceil(this.BATCH_SIZE * 0.3);
      let DISCOVERY_TARGET = this.BATCH_SIZE - POPULAR_TARGET - RECENT_TARGET;
      
      let freshVideos = [];
      let recentVideos = [];
      let discoveryVideos = [];

      let skip = 0;
      const BATCH_SIZE_QUERY = 250; 
      const MAX_PAGES = 4; 
      let pageCount = 0;

      // Creator Bucket Caps
      // **DIVERSITY FIX: Max 8 videos per creator per batch, but never consecutive**
      // The orderFeedWithDiversity algorithm enforces minCreatorSpacing=5 gaps between same creator
      const STANDARD_CAP = 8; // Max 8 videos per creator in a 50-video batch
      const THROTTLED_CAP = 3; // Recently-seen creators get max 3 slots
      const creatorCounts = new Map();

      // **STEP A: Fetch Recent Videos (Strictly Fresh)**
      try {
          // Only fetch Recent for Yug (short videos) generally, or if specific constraint allows
          const recentQuery = { processingStatus: 'completed' };
          if (videoType === 'vayu') recentQuery.duration = { $gt: 120 };
          else recentQuery.duration = { $lte: 120 };
          
          if (userId && userId !== 'anon' && userId !== 'undefined') {
              recentQuery.uploader = { $ne: userId };
          }
          
          // Get videos from last 7 days only for "Recent" bucket transparency
          const sevenDaysAgo = new Date();
          sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);
          recentQuery.createdAt = { $gte: sevenDaysAgo };

          const recentCandidates = await Video.find(recentQuery)
             .sort({ createdAt: -1 }) // STRICT TIME SORT
             .limit(50) // Fetch top 50 recent to filter from
             .select('_id uploader createdAt score finalScore videoType seriesId episodeNumber views videoHash')
             .lean();
             
          // Filter Seen & Hashes
          let recentToCheck = recentCandidates.filter(v => !seenVideoIds.has(v._id.toString()));
          if (recentToCheck.length > 0) {
              recentToCheck = recentToCheck.filter(v => !seenHashesSet.has(v.videoHash));
          }
          
          for (const video of recentToCheck) {
             if (recentVideos.length >= RECENT_TARGET) break;
             // **FIX: Normalize uploader ID correctly (handles ObjectId and plain string)**
             const uploaderId = video.uploader
               ? (typeof video.uploader === 'object'
                   ? (video.uploader._id || video.uploader).toString()
                   : video.uploader.toString())
               : 'unknown';
             
             // Check generic cap
             const cc = creatorCounts.get(uploaderId) || 0;
             if (cc < STANDARD_CAP) {
                recentVideos.push(video);
                creatorCounts.set(uploaderId, cc + 1);
                seenVideoIds.add(video._id.toString()); // Mark as picked so Popular/Discovery don't pick again
                if (video.videoHash) seenHashesSet.add(video.videoHash);
             }
          }
          console.log(`🆕 FeedQueue: Found ${recentVideos.length} recent videos.`);
      } catch (e) {
         console.error('⚠️ FeedQueue: Error fetching recent bucket:', e.message);
      }

      // **STEP B: Pagination Loop for Popular & Discovery**
      while ((freshVideos.length < POPULAR_TARGET || discoveryVideos.length < DISCOVERY_TARGET) && pageCount < MAX_PAGES) {
          const candidateQuery = { processingStatus: 'completed' };
          if (videoType === 'vayu') candidateQuery.duration = { $gt: 120 };
          else candidateQuery.duration = { $lte: 120 };

          // Exclude own videos from feed
          if (userId && userId !== 'anon' && userId !== 'undefined') {
              candidateQuery.uploader = { $ne: userId };
          }

          const candidates = await Video.find(candidateQuery)
            .sort({ finalScore: -1, createdAt: -1 })
            .skip(skip)
            .limit(BATCH_SIZE_QUERY)
            .select('_id uploader createdAt score finalScore videoType seriesId episodeNumber views videoHash') 
            .lean();

          if (candidates.length === 0) break; 

          // Filter by Video ID (Redis) & Hash
          let candidatesToCheck = candidates.filter(v => !seenVideoIds.has(v._id.toString()));
          // (Redis check removed within loop for speed - relying on local seenVideoIds set which is synced at start + accumulated)
          // Double check with Redis Seen Set only if not already in local block list (optimization: skip for now)
          
           if (candidatesToCheck.length > 0 && userId !== 'anon') {
             // We already synced seenVideoIds from Redis at the start, so this check is redundant unless dirty read.
             // But for safety against "just watched in another thread", we could check. 
             // For speed, we trust the snapshot we took at start of function.
           }

          // **FATIGUE FILTER: Filter by Content Hash**
          candidatesToCheck = candidatesToCheck.filter(v => !seenHashesSet.has(v.videoHash));
          
          for (const video of candidatesToCheck) {
             // **FIX: Normalize uploader ID correctly (handles ObjectId and plain string)**
             const uploaderId = video.uploader
               ? (typeof video.uploader === 'object'
                   ? (video.uploader._id || video.uploader).toString()
                   : video.uploader.toString())
               : 'unknown';
             const isDiscovery = (video.views || 0) < 1000;
             
             // If this creator was in the "recent" window, skip entirely for this batch
             let currentCap = recentCreatorSet.has(uploaderId) ? THROTTLED_CAP : STANDARD_CAP;
             if (pageCount > 2 && freshVideos.length + discoveryVideos.length < 5) {
                 // Emergency fill mode: allow more per creator only if feed is seriously empty
                 currentCap = Math.max(currentCap, 2); 
             }

             const currentCount = creatorCounts.get(uploaderId) || 0;
             if (currentCount < currentCap) {
                if (isDiscovery && discoveryVideos.length < DISCOVERY_TARGET) {
                    discoveryVideos.push(video);
                    creatorCounts.set(uploaderId, currentCount + 1);
                    seenVideoIds.add(video._id.toString());
                    if (video.videoHash) seenHashesSet.add(video.videoHash);
                } else if (!isDiscovery && freshVideos.length < POPULAR_TARGET) {
                    freshVideos.push(video);
                    creatorCounts.set(uploaderId, currentCount + 1);
                    seenVideoIds.add(video._id.toString());
                    if (video.videoHash) seenHashesSet.add(video.videoHash);
                }
                
                if (freshVideos.length >= POPULAR_TARGET && discoveryVideos.length >= DISCOVERY_TARGET) break;
             }
          }
          
          if (freshVideos.length >= POPULAR_TARGET && discoveryVideos.length >= DISCOVERY_TARGET) break;
          
          skip += BATCH_SIZE_QUERY;
          pageCount++;
      }

      // Combine pools
      let combinedPool = [...recentVideos, ...freshVideos, ...discoveryVideos];

      // 3. **FINAL DEDUPLICATION CHECK & FALLBACK**
      if (combinedPool.length < this.BATCH_SIZE) {
          const needed = this.BATCH_SIZE - combinedPool.length;
          // Use FULL LRU but KEEP exclusion list
          const fallbackIds = await this.getFallbackIds(userId, videoType, needed, Array.from(seenVideoIds));
          if (fallbackIds.length > 0) {
              const fallbackVideos = await Video.find({ _id: { $in: fallbackIds } }).lean();
              combinedPool.push(...fallbackVideos);
          }
      }

      // 4. Shuffle & Order
      const randomizedPool = RecommendationService.weightedShuffle(combinedPool, this.BATCH_SIZE);
      const orderedVideos = RecommendationService.orderFeedWithDiversity(randomizedPool, {
          // **DIVERSITY: Enforce 5 videos between same creator (up from 3)**
          minCreatorSpacing: 4
      });

      const toPushIds = orderedVideos.map(v => v._id.toString()).slice(0, this.BATCH_SIZE);
      
      if (toPushIds.length > 0) {
          await redisService.rPush(queueKey, toPushIds);
          await redisService.lTrim(queueKey, 0, this.QUEUE_SIZE_LIMIT - 1);
          await redisService.expire(queueKey, 3600);
          
          const newCreators = orderedVideos.map(v => v.uploader ? (v.uploader._id || v.uploader).toString() : null).filter(Boolean);
          await this.addRecentCreators(userId, [...new Set(newCreators)]);
          
          console.log(`✅ FeedQueue: Refilled ${toPushIds.length} videos (including discovery).`);
      }

      return toPushIds.length;

    } catch (error) {
      console.error('❌ FeedQueue: Error producing feed:', error);
      return 0;
    }
  }



  /**
   * Get Fallback Video IDs (LRU or Random)
   * Internal helper for both on-demand fallback and queue smoothing.
   */
  async getFallbackIds(userId, videoType = 'yog', count = 10, excludedIds = []) {
    // Normalize excluded IDs to strict strings for filtering
    const excludeSet = new Set(excludedIds.map(id => id.toString()));
    const finalIds = [];

    // **STRATEGY 1: Fresh/Top Discovery (Recent & High Score)**
    // Instead of purely random, prioritize content the user hasn't seen
    // but is either very NEW or has a high DISCOVERY SCORE.
    let need = count - finalIds.length;
    if (need > 0) {
      try {
        const matchStage = { 
          processingStatus: 'completed',
          _id: { $nin: [...Array.from(excludeSet), ...finalIds].map(id => {
              try { return new mongoose.Types.ObjectId(id); } catch(e) { return null; }
          }).filter(Boolean) }
        };

        if (videoType === 'vayu') matchStage.duration = { $gt: 120 };
        else matchStage.duration = { $lte: 120 };

        const discoveryVideos = await Video.find(matchStage)
          .sort({ finalScore: -1, createdAt: -1 }) // Prioritize High Score (which includes Discovery Bonus) + Newest
          .limit(need)
          .select('_id')
          .lean();
        
        if (discoveryVideos.length > 0) {
           finalIds.push(...discoveryVideos.map(v => v._id.toString()));
        }
      } catch (err) {
         console.error('❌ FeedQueue: Discovery Fallback Error:', err.message);
      }
    }

    // **STRATEGY 2: Randomized Global LRU (Comprehensive Coverage)**
    // If we couldn't find enough "New" videos, we re-surface the oldest seen ones.
    need = count - finalIds.length;
    if (need > 0 && userId && userId !== 'anon' && userId !== 'undefined') {
       try {
          // 1. Fetch a large pool of the Oldest Seen videos (up to 1000)
          const lruOldestIds = await FeedHistory.getLRUVideos(userId, 1000);
          
          if (lruOldestIds.length > 0) {
             // 2. Fetch basic data to filter by duration/type
             const rawVideos = await Video.find({
                _id: { $in: lruOldestIds }
             }).select('_id duration processingStatus').lean();
             
             const candidates = rawVideos.filter(v => {
                const isVayu = v.duration > 120;
                const isYog = v.duration <= 120;
                const typeMatch = (videoType === 'vayu' && isVayu) || (videoType !== 'vayu' && isYog);
                // Exclude what's already in finalIds for this request
                return v.processingStatus === 'completed' && typeMatch && !finalIds.includes(v._id.toString());
             }).map(v => v._id.toString());
             
             if (candidates.length > 0) {
                 // **3. RANDOMIZE THE POOL**: This ensures it doesn't feel cyclic
                 const shuffled = candidates.sort(() => 0.5 - Math.random());
                 finalIds.push(...shuffled.slice(0, need));
             }
          }
       } catch (err) {
          console.error('❌ FeedQueue: Global LRU Error:', err.message);
       }
    }

    // **STRATEGY 3: Random Discovery (Absolute Last Resort)**
    // Only used if Strategy 1 & 2 both failed (rare)
    need = count - finalIds.length;
    if (need > 0) {
      try {
        const matchStage = { 
            processingStatus: 'completed',
            _id: { $nin: [...Array.from(excludeSet), ...finalIds].map(id => {
                try { return new mongoose.Types.ObjectId(id); } catch(e) { return null; }
            }).filter(Boolean) }
        };

        if (videoType === 'vayu') matchStage.duration = { $gt: 120 };
        else matchStage.duration = { $lte: 120 };

        const randomVideos = await Video.aggregate([
          { $match: matchStage },
          { $sample: { size: need } }
        ]);
        
        if (randomVideos.length > 0) {
           finalIds.push(...randomVideos.map(v => v._id.toString()));
        }
      } catch (err) {
         console.error('❌ FeedQueue: Random Fallback Error:', err.message);
      }
    }
    
    return finalIds;
  }

  /**
   * Fallback feed when queue is empty (Cold Start OR Exhausted)
   * Now just a wrapper around getFallbackIds + populate
   */
  async fallbackFeed(userId, videoType = 'yog', count = 10, excludedIds = []) {
    // console.log(`❄️ FeedQueue: Serving Immediate Fallback for ${userId}`);
    const ids = await this.getFallbackIds(userId, videoType, count, excludedIds);
    if (ids.length === 0) return [];
    return await this.populateVideos(ids);
  }

  /**
   * Populate video IDs with full details
   */
  /**
   * Populate video IDs with full details (Cached)
   */
  async populateVideos(videoIds) {
    if (!videoIds || videoIds.length === 0) return [];
    
    // Ensure ObjectIds are strings
    const ids = videoIds.map(id => id.toString()).filter(Boolean);
    if (ids.length === 0) return [];

    let start = Date.now();
    let videos = new Array(ids.length).fill(null);
    let missingIndices = [];
    let missingIds = [];

    // 1. Try Fetch from Redis (Batch)
    if (redisService.getConnectionStatus()) {
      const cacheKeys = ids.map(id => `video:data:${id}`);
      try {
        const cachedDocs = await redisService.mget(cacheKeys);
        
        cachedDocs.forEach((doc, index) => {
          if (doc) {
            videos[index] = doc;
          } else {
            missingIndices.push(index);
            missingIds.push(ids[index]);
          }
        });
        
        const hitCount = ids.length - missingIds.length;
        if (hitCount > 0) {
           // console.log(`⚡ FeedQueue: Cache HIT for ${hitCount}/${ids.length} videos`);
        }
      } catch (err) {
        console.error('❌ FeedQueue: Redis MGET error:', err.message);
        missingIndices = ids.map((_, i) => i);
        missingIds = [...ids];
      }
    } else {
      missingIndices = ids.map((_, i) => i);
      missingIds = [...ids];
    }

    // 2. Fetch Missing from MongoDB
    if (missingIds.length > 0) {
      // console.log(`🐢 FeedQueue: Database HIT for ${missingIds.length} videos (Cache Miss)`);
      
      // **OPTIMIZED QUERY:**
      // 1. Removed .populate('comments.user') -> Massive speedup (don't need comment authors in feed)
      // 2. Added .select(...) -> Only fetch fields needed for feed display
      const dbDocs = await Video.find({ _id: { $in: missingIds } })
        .select('videoUrl thumbnailUrl description uploader views likes shares comments likedBy duration processingStatus createdAt uploadedAt videoType videoHash videoName tags seriesId episodeNumber hlsMasterPlaylistUrl hlsPlaylistUrl isHLSEncoded lowQualityUrl mediumQualityUrl highQualityUrl preloadQualityUrl link mediaType')
        .populate('uploader', 'name profilePic googleId username')
        .lean();

      // Create lookup map
      const dbMap = new Map(dbDocs.map(v => [v._id.toString(), v]));

      // Fill missing spots and prepare for Cache Set
      const toCache = [];
      
      missingIndices.forEach((originalIndex, i) => {
        const id = ids[originalIndex]; // OR missingIds[i]
        const video = dbMap.get(id);
        
        if (video) {
          // **CRITICAL: Transform ObjectIds to Strings before Caching**
          // This ensures JSON.stringify/parse works cleanly and matches frontend expectations
          // (Fast transform similar to what we do in routes, simplified)
          if (video._id) video._id = video._id.toString();
          if (video.uploader && video.uploader._id) video.uploader._id = video.uploader._id.toString();
          
          videos[originalIndex] = video;
          toCache.push([`video:data:${id}`, video]);
        }
      });

      // 3. Populate Series Episodes - MOVED TO END
      // Logic was here, but it only ran for cache-miss videos. 
      // Now running it for ALL videos at the end to ensure cached videos get Fresh episodes.

      // 4. Save Fresh Data to Redis (Async - don't block response)
      if (toCache.length > 0 && redisService.getConnectionStatus()) {
        redisService.mset(toCache, 3600) // Cache for 1 hour
          .catch(e => console.error('❌ FeedQueue: Cache Set error:', e.message));
      }
    }

    // Filter out nulls (deleted videos)
    const finalVideos = videos.filter(Boolean);

    // 5. Populate Series Episodes (moved from above)
    // Run for ALL videos (Cached + Fresh)
    const seriesIds = new Set();
    finalVideos.forEach(v => {
      if (v.seriesId) seriesIds.add(v.seriesId);
    });

    if (seriesIds.size > 0) {
      try {
        const sIds = Array.from(seriesIds);
        
        // **SPEEDUP: Use MGET from Redis for series episodes if available**
        // (Optional: Implement series caching if latency persists)

        // Fetch all episodes for these series
        const allEpisodes = await Video.find({ 
          seriesId: { $in: sIds },
          processingStatus: 'completed'
        })
        .select('_id videoName thumbnailUrl episodeNumber seriesId duration')
        .sort({ seriesId: 1, episodeNumber: 1 }) // Grouped by series for faster mapping
        .limit(200) // Safety limit to prevent massive payload hangs
        .lean();
        
        // Group by seriesId
        const episodesMap = new Map();
        allEpisodes.forEach(ep => {
          if (!ep.seriesId) return;
          const sId = ep.seriesId.toString();
          
          if (!episodesMap.has(sId)) {
             episodesMap.set(sId, []);
          }
          
          // Limit episodes per series for feed display (e.g. max 20)
          if (episodesMap.get(sId).length < 20) {
              if (ep._id) ep._id = ep._id.toString();
              episodesMap.get(sId).push(ep);
          }
        });
        
        // Attach episodes to videos
        finalVideos.forEach(v => {
           if (v.seriesId) {
              const sId = v.seriesId.toString();
              if (episodesMap.has(sId)) {
                 v.episodes = episodesMap.get(sId);
              }
           }
        });
        
      } catch (err) {
         console.error('⚠️ FeedQueue: Error fetching series episodes:', err.message);
      }
    }
    
    return finalVideos;
  }
  
  // Helper to populate methods for the array (VideoQueueService needs to output what VideoRoutes expects)
  // Actually, VideoRoutes does the heavy lifting of transformation. 
  // We will just return the Mongoose Documents (lean) and let VideoRoutes transform them.
}

export default new FeedQueueService();
