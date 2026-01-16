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
    this.QUEUE_SIZE_LIMIT = 100; // Max items in Redis list per user
    this.REFILL_THRESHOLD = 30;  // Refill when below this (Buffered for speed)
    this.BATCH_SIZE = 50;        // Generate this many videos at once
  }


  /**
   * Get main feed video queue key
   */
  getQueueKey(userId, videoType = 'yog') {
    return `user:feed:${userId}:${videoType}`;
  }

  /**
   * Pop videos from the user's feed queue (INSTANT)
   * @param {string} userId - User ID
   * @param {string} videoType - 'yog' or 'vayu'
   * @param {number} count - Number of videos to pop
   * @returns {Promise<Array>} - Array of Video objects
   */
  async popFromQueue(userId, videoType = 'yog', count = 10) {
    const queueKey = this.getQueueKey(userId, videoType);
    const videos = [];
    
    // **METRIC: Start Timer**
    const tStart = Date.now();
    let tRedisCheck = 0;
    let tRedisPop = 0;
    let tFallback = 0;
    let tPopulate = 0;

    // **PERFORMANCE UPDATE: Non-blocking Refill (Safety Net)**
    // logic: Check length. If low, trigger background refill.
    // ALWAYS return immediately using available queue + Fallback/Random if needed.
    // This ensures "Ultra Fast Loading" by never blocking on complex feed generation.
    
    let currentLength = 0;
    try {
      const t1 = Date.now();
      currentLength = await redisService.lLen(queueKey);
      tRedisCheck = Date.now() - t1;
    } catch (e) {
      console.error(`⚠️ FeedQueue: Redis lLen failed for ${userId}:`, e.message);
      // If Redis fails, treat as empty queue and go straight to Fallback
      currentLength = 0;
    }
    
    // Trigger Background Refill if low
    if (currentLength < this.REFILL_THRESHOLD) {
      console.log(`⚡ FeedQueue: Queue LOW (${currentLength} < ${this.REFILL_THRESHOLD}) for ${userId}. triggering background refill...`);
      // Fire and forget - do NOT await
      this.generateAndPushFeed(userId, videoType).catch(err => 
        console.error(`⚠️ FeedQueue: Background refill error for ${userId}:`, err.message)
      );
    } else {
      console.log(`ℹ️ FeedQueue: Queue OK (${currentLength}) for ${userId}`);
    }

    // Pop available items (Try to get 'count', but accept less)
    try {
      const t2 = Date.now();
      
      // OPTIMIZATION: Use batched lPop (Single Round Trip)
      // This reduces Redis latency from ~3000ms to ~200ms on remote connections
      const popCount = Math.min(currentLength, count);
      
      if (popCount > 0) {
        const popped = await redisService.lPop(queueKey, popCount);
        
        if (Array.isArray(popped)) {
           videos.push(...popped);
        } else if (popped) {
           videos.push(popped);
        }
      }
      
      tRedisPop = Date.now() - t2;
    } catch (e) {
      console.error(`⚠️ FeedQueue: Redis lPop failed:`, e.message);
    }

    // **SAFETY NET: If we don't have enough videos, fill from Fallback immediately**
    if (videos.length < count) {
       const t3 = Date.now();
       const needed = count - videos.length;
       console.log(`❄️ FeedQueue: Queue exhausted (got ${videos.length}). Fetching ${needed} from Safety Net immediately.`);
       
       // Calculate exclusion list (Recent History + Current Buffer) to avoid duplicates
       // We accept a small chance of duplicates here for the sake of speed
       const fallbackSeenIds = new Set(videos); // Exclude what we just popped
       
       // Optimization: Only fetch history if totally empty to save time? 
       // No, we should try to exclude recently seen to satisfy "No Same Video" request.
       if (FeedHistory) {
         try {
           // Limit history check to recent 100 items for speed
           const history = await FeedHistory.find({ userId })
             .sort({ seenAt: -1 })
             .limit(100)
             .select('videoId')
             .lean();
           history.forEach(h => fallbackSeenIds.add(h.videoId.toString()));
         } catch (e) { /* ignore */ }
       }

       const fallbackIds = await this.getFallbackIds(userId, videoType, needed, Array.from(fallbackSeenIds));
       videos.push(...fallbackIds);
       tFallback = Date.now() - t3;
    }

    // Populate video details
    const t4 = Date.now();
    const result = await this.populateVideos(videos);
    tPopulate = Date.now() - t4;

    // **METRIC: End Timer & Log**
    const tTotal = Date.now() - tStart;
    
    // Log simply if fast, detailed if slow (>500ms)
    // Always logging total time is useful for monitoring, keeping it concise.
    const logMsg = `⏱️ Feed Latency: Total ${tTotal}ms (Redis: ${tRedisCheck + tRedisPop}ms | Fallback: ${tFallback}ms | Populate: ${tPopulate}ms) [${result.length} videos]`;
    
    if (tTotal > 500) {
      console.warn(`⚠️ SLOW FEED: ${logMsg}`);
    } else {
      console.log(logMsg);
    }

    return result;
  }

  /**
   * Check queue length and trigger refill if needed
   */
  async checkAndRefillQueue(userId, videoType = 'yog') {
    const queueKey = this.getQueueKey(userId, videoType);
    const length = await redisService.lLen(queueKey);

    if (length < this.REFILL_THRESHOLD) {
      console.log(`⚡ FeedQueue: checkAndRefill - Queue LOW (${length} < ${this.REFILL_THRESHOLD}) for ${userId}. Refilling...`);
      await this.generateAndPushFeed(userId, videoType);
    }
  }

  /**
   * Generate personalized feed and push to Redis queue
   * @returns {Promise<number>} - Number of videos pushed
   */
  async generateAndPushFeed(userId, videoType = 'yog') {
    const start = Date.now();
    console.log(`♻️ Refill STARTED for ${userId}`);
    try {
      // 1. Fetch Candidates (FAST - Constant Time)
      // Instead of excluding huge list of seen IDs in DB query, we fetch "Fresh & Popular" candidates first.
      
      const candidateQuery = { 
        processingStatus: 'completed'
      };
      
      if (videoType === 'vayu') candidateQuery.duration = { $gt: 60 };
      else candidateQuery.duration = { $lte: 60 }; // Default yog

      // Fetch latest 300 videos (Candidate Pool)
      // This is always fast regardless of user history size
      let candidates = await Video.find(candidateQuery)
        .sort({ createdAt: -1 })
        .limit(300) 
        .select('_id uploader createdAt likes views shares score finalScore videoType videoHash')
        .lean();

      if (candidates.length === 0) {
          console.log(`⚠️ Refill: No candidates found!`);
          return 0;
      }

      // 2. Fetch User History (LIMITED)
      // We only care if they've seen videos *within* our candidate pool.
      const seenVideoIds = new Set();
      const seenHashes = new Set(); // **NEW: Track seen content hashes**
      
      // Add what's currently in the queue to exclusion list
      const queueKey = this.getQueueKey(userId, videoType);
      const queuedIds = await redisService.lRange(queueKey, 0, -1);
      queuedIds.forEach(id => seenVideoIds.add(id));

      if (FeedHistory) {
         try {
           // **OPTIMIZATION: Parallel Fetch**
           const [recentSeenDocs, seenHashList] = await Promise.all([
             FeedHistory.find({ userId }).sort({ seenAt: -1 }).limit(500).select('videoId').lean(),
             FeedHistory.getSeenContentHashes(userId)
           ]);
            
           recentSeenDocs.forEach(doc => seenVideoIds.add(doc.videoId.toString()));
           seenHashList.forEach(hash => seenHashes.add(hash));
           
           // console.log(`🔍 FeedQueue: Loaded ${seenVideoIds.size} seen IDs and ${seenHashes.size} seen hashes for filtering`);
         } catch (e) {
            console.error('⚠️ FeedQueue: Error fetching history:', e.message);
         }
      }

      // 3. In-Memory Filter (Candidates - Seen)
      // **UPDATED: Filter by BOTH ID AND Content Hash**
      let freshVideos = candidates.filter(v => {
        const id = v._id.toString();
        const hash = v.videoHash;
        
        // Filter out if ID is seen OR if Hash is seen (Classic Duplicate + Content Duplicate)
        if (seenVideoIds.has(id)) return false;
        if (hash && seenHashes.has(hash)) return false;
        
        return true;
      });

      console.log(`🔍 Refill: Filtered ${candidates.length} candidates -> ${freshVideos.length} fresh videos`);

      // Fallback: If Filter Left Nothing?
      // We now handle this by backfilling from Fallback at the end before pushing.


      // 4. Apply Diversity Ordering (No same creator back-to-back)
      // Max 3 per creator
      let uniqueCreatorVideos = [];
      const creatorCounts = new Map();
      const maxPerCreator = 2;

      for (const video of freshVideos) {
        if (!video || !video._id) continue;
        const creatorId = video.uploader?.toString() || 'unknown';
        const currentCount = creatorCounts.get(creatorId) || 0;

        if (currentCount < maxPerCreator) {
          uniqueCreatorVideos.push(video);
          creatorCounts.set(creatorId, currentCount + 1);
        }
      }

      // Interleave
      const orderedVideos = RecommendationService.orderFeedWithDiversity(uniqueCreatorVideos, {
        minCreatorSpacing: 1
      });

      // 4. Push to Redis (only the requested batch size)
      // **PRE-COMPUTED FALLBACK:**
      // If we don't have enough fresh videos, FILL the batch with Safe/Random fallback videos immediately.
      // This ensures the queue is ALWAYS full, so popFromQueue never hits empty and never triggers sync refill.
      
      let toPushIds = orderedVideos.map(v => v._id.toString());
      
      if (toPushIds.length < this.BATCH_SIZE) {
          const needed = this.BATCH_SIZE - toPushIds.length;
           console.log(`📉 FeedQueue: Fresh content low (${toPushIds.length}/${this.BATCH_SIZE}). Backfilling ${needed} from Fallback...`);
          
          const fallbackIds = await this.getFallbackIds(userId, videoType, needed, [...seenVideoIds, ...toPushIds]);
          toPushIds = [...toPushIds, ...fallbackIds];
          
          if (fallbackIds.length > 0) {
            //  console.log(`✅ FeedQueue: Backfilled ${fallbackIds.length} fallback videos into queue.`);
          }
      }
      
      // Limit to Batch Size (in case we had too many fresh ones)
      toPushIds = toPushIds.slice(0, this.BATCH_SIZE);

      if (toPushIds.length > 0) {
        await redisService.rPush(queueKey, toPushIds);
        // Trim to strict limit
        await redisService.lTrim(queueKey, 0, this.QUEUE_SIZE_LIMIT - 1);
        console.log(`✅ FeedQueue: Pushed ${toPushIds.length} videos to ${queueKey}. Refill took ${Date.now() - start}ms`);
      } else {
        console.log(`⚠️ Refill: No videos to push after all steps.`);
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

    // **STRATEGY 1: LRU (Least Recently Watched)**
    // If user is known, try to show their old favorites
    if (userId && userId !== 'anon' && userId !== 'undefined') {
       try {
          // Fetch from DB
          // We look back reasonably far (e.g., 50 videos)
          const lruIds = await WatchHistory.getLeastRecentlyWatchedVideoIds(userId, 50);
          
          if (lruIds.length > 0) {
             const rawVideos = await Video.find({
                _id: { $in: lruIds }
             }).select('_id duration processingStatus').lean();
             
             // Filter valid, matching type, AND NOT SEEN RECENTLY
             const validLruIds = rawVideos.filter(v => {
                const isVayu = v.duration > 60;
                const isYog = v.duration <= 60;
                const typeMatch = (videoType === 'vayu' && isVayu) || (videoType !== 'vayu' && isYog);
                const notExcluded = !excludeSet.has(v._id.toString());
                return v.processingStatus === 'completed' && typeMatch && notExcluded;
             }).map(v => v._id.toString());
             
             if (validLruIds.length > 0) {
                 // console.log(`↺ FeedQueue: Found ${validLruIds.length} LRU videos`);
                 // Shuffle
                 const shuffled = validLruIds.sort(() => 0.5 - Math.random());
                 finalIds.push(...shuffled.slice(0, count));
             }
          }
       } catch (err) {
          console.error('❌ FeedQueue: LRU Fallback Error:', err.message);
       }
    }
    
    // If we have enough LRU ids, return them
    if (finalIds.length >= count) {
      return finalIds.slice(0, count);
    }

    // **STRATEGY 2: Random Discovery (Safety Net)**
    // Fill the remaining spots
    const need = count - finalIds.length;
    // console.log(`❄️ FeedQueue: Need ${need} more videos from Random Discovery`);
    
    try {
      const matchStage = { 
        processingStatus: 'completed',
        _id: { $nin: [...Array.from(excludeSet), ...finalIds].map(id => {
            try { return new mongoose.Types.ObjectId(id); } catch(e) { return null; }
        }).filter(Boolean) }
      };

      if (videoType === 'vayu') matchStage.duration = { $gt: 60 };
      else matchStage.duration = { $lte: 60 };

      // Use Aggregation with $sample for random selection
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
        .select('videoUrl thumbnailUrl description uploader views likes shares comments duration processingStatus createdAt videoType videoHash videoName tags')
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

      // 3. Save Fresh Data to Redis (Async - don't block response)
      if (toCache.length > 0 && redisService.getConnectionStatus()) {
        redisService.mset(toCache, 3600) // Cache for 1 hour
          .catch(e => console.error('❌ FeedQueue: Cache Set error:', e.message));
      }
    }

    // Filter out nulls (deleted videos)
    const finalVideos = videos.filter(Boolean);
    
    // Log final absolute time
    // console.log(`⏱️ FeedQueue: populated ${finalVideos.length} videos in ${Date.now() - start}ms`);
    
    return finalVideos;
  }
  
  // Helper to populate methods for the array (VideoQueueService needs to output what VideoRoutes expects)
  // Actually, VideoRoutes does the heavy lifting of transformation. 
  // We will just return the Mongoose Documents (lean) and let VideoRoutes transform them.
}

export default new FeedQueueService();
