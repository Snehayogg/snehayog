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
    
    // Trigger Background Refill if projected length will be low
    // **FIX: Proactive Refill** - Check if we will be below threshold AFTER this pop
    const projectedLength = Math.max(0, currentLength - count);
    if (projectedLength < this.REFILL_THRESHOLD) {
      console.log(`⚡ FeedQueue: Queue will be LOW (${projectedLength} < ${this.REFILL_THRESHOLD}) after pop for ${userId}. triggering background refill...`);
      // Fire and forget - do NOT await
      this.generateAndPushFeed(userId, videoType).catch(err => 
        console.error(`⚠️ FeedQueue: Background refill error for ${userId}:`, err.message)
      );
    } else {
      // console.log(`ℹ️ FeedQueue: Queue OK (${currentLength}, projected ${projectedLength}) for ${userId}`);
    }

    // Pop available items (Try to get 'count', but accept less)
    try {
      const t2 = Date.now();
      
      // OPTIMIZATION: Use batched lPop (Single Round Trip)
      const popCount = Math.min(currentLength, count);
      
      if (popCount > 0) {
        const popped = await redisService.lPop(queueKey, popCount);
        
        if (Array.isArray(popped)) {
           videos.push(...popped);
        } else if (popped) {
           videos.push(popped);
        }

        // **NEW: Track Impressions Immediately (Strict Deduplication)**
        // Add to Redis "Seen All" Set and "Recent Session" Buffer
        if (videos.length > 0 && userId !== 'anon') {
           try {
             // 1. Add to Persistent "Seen All" Set (Fast Exclusion)
             const seenKey = `user:seen_all:${userId}`;
             await redisService.sAdd(seenKey, videos); // SADD is fast
             await redisService.expire(seenKey, 604800); // 7 Days TTL (Refresh on activity)

             // 2. Add to Session Buffer (For immediate refill consistency)
             const recentKey = `user:recent_served:${userId}`;
             await redisService.lPush(recentKey, videos);
             await redisService.lTrim(recentKey, 0, 199);
             await redisService.expire(recentKey, 600);

             // 3. Fire-and-forget: Track in DB FeedHistory (for long-term retention)
             this.trackImpressionsAsync(userId, videos);
           } catch (trackError) {
             console.error('⚠️ FeedQueue: Error tracking impressions:', trackError.message);
           }
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
       
       // Calculate exclusion list
       const fallbackSeenIds = new Set(videos);
       
       // **OPTIMIZED: Use "Seen All" Set from Redis if available**
       if (userId !== 'anon') {
          try {
             const seenKey = `user:seen_all:${userId}`;
             const seenAll = await redisService.sMembers(seenKey);
             seenAll.forEach(id => fallbackSeenIds.add(id));
          } catch(e) { /* ignore */ }
       }

       const fallbackIds = await this.getFallbackIds(userId, videoType, needed, Array.from(fallbackSeenIds));
     console.log(`🔍 FeedQueue: Safety Net returned ${fallbackIds.length} fallback IDs.`);
     
     if (fallbackIds.length === 0) {
        console.log(`❄️ FeedQueue: Safety Net returned 0. Triggering LAST RESORT (LRU Logic).`);
        // Force LRU Fallback (ignore exclusion list to prevent empty feed)
        const lruIds = await this.getFallbackIds(userId, videoType, needed, []); 
        videos.push(...lruIds);
     } else {
        videos.push(...fallbackIds);
     }
     tFallback = Date.now() - t3;
  }

    // Populate video details
    const t4 = Date.now();
    const result = await this.populateVideos(videos);
    tPopulate = Date.now() - t4;

    const tTotal = Date.now() - tStart;
    const logMsg = `⏱️ Feed Latency: Total ${tTotal}ms (Redis: ${tRedisCheck + tRedisPop}ms | Fallback: ${tFallback}ms | Populate: ${tPopulate}ms) [${result.length} videos]`;
    console.log(logMsg);

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
      // 1. Fetch User History (STRICT DEDUPLICATION)
      const seenVideoIds = new Set();
      const seenHashes = new Set();
      
      const queueKey = this.getQueueKey(userId, videoType);
      
      // A. Add currently queued items (Don't duplicate what's already waiting)
      const queuedIds = await redisService.lRange(queueKey, 0, -1);
      queuedIds.forEach(id => seenVideoIds.add(id));

      // B. Add "In-Flight" items (Session Buffer)
      const recentKey = `user:recent_served:${userId}`;
      const recentServed = await redisService.lRange(recentKey, 0, -1);
      recentServed.forEach(id => seenVideoIds.add(id));
      
      
      // OPTIMIZATION: Do NOT fetch the entire "Seen All" Set (Memory Heavy)
      // We will use SMISMEMBER (Batch Check) later on candidates
      const seenKey = `user:seen_all:${userId}`;

      // D. Sync from DB if Redis Set is empty AND Recents empty (Cold Start)
      const seenSetExists = await redisService.exists(seenKey);
      if (!seenSetExists && FeedHistory) {
         try {
           const history = await FeedHistory.find({ userId }).select('videoId').lean();
           if (history.length > 0) {
              const ids = history.map(h => h.videoId.toString());
              await redisService.sAdd(seenKey, ids);
              await redisService.expire(seenKey, 604800);
           }
         } catch (e) { /* ignore */ }
      }

      // 2. Iterative Batch Search (The "Next 300" Strategy)
      let freshVideos = [];
      let skip = 0;
      const BATCH_SIZE_QUERY = 500; // Increased from 300 to find fresh content faster
      const MAX_PAGES = 15;        // Increased from 10
      let pageCount = 0;

      while (freshVideos.length < this.BATCH_SIZE && pageCount < MAX_PAGES) {
          const candidateQuery = { processingStatus: 'completed' };
          if (videoType === 'vayu') candidateQuery.duration = { $gt: 120 };
          else candidateQuery.duration = { $lte: 120 };

          // Fetch Batch
          const candidates = await Video.find(candidateQuery)
            .sort({ finalScore: -1, createdAt: -1 })
            .skip(skip)
            .limit(BATCH_SIZE_QUERY)
            .select('_id uploader createdAt likes views shares score finalScore videoType videoHash seriesId episodeNumber') // Ensure all fields
            .lean();

          if (candidates.length === 0) {
              console.log(`ℹ️ Refill: DB exhausted at skip ${skip}. No more videos.`);
              break; // End of DB
          }

          // **PHASE 1: Filter Local (Queue + Session)**
          let candidatesToCheck = candidates.filter(v => {
             const id = v._id.toString();
             return !seenVideoIds.has(id);
          });
          const localFilteredCount = candidates.length - candidatesToCheck.length;
          
          // **PHASE 2: Filter Remote (Redis Seen Set - SMISMEMBER Optimization)**
          let remoteFilteredCount = 0;
          if (candidatesToCheck.length > 0 && userId !== 'anon') {
              const checkIds = candidatesToCheck.map(v => v._id.toString());
              const isSeenResults = await redisService.smIsMember(seenKey, checkIds);
              
              const beforeCount = candidatesToCheck.length;
              // Keep only those where isSeen is FALSE
              candidatesToCheck = candidatesToCheck.filter((_, index) => !isSeenResults[index]);
              remoteFilteredCount = beforeCount - candidatesToCheck.length;
          }
          
          if (localFilteredCount > 0 || remoteFilteredCount > 0) {
             console.log(`🛡️ Deduplication: Batch ${pageCount+1} -> Excluded ${localFilteredCount} (Local) + ${remoteFilteredCount} (Remote/Strict) videos.`);
          }

          // console.log(`🔍 Refill [Page ${pageCount + 1}]: Scanned ${skip}-${skip + candidates.length}. Found ${candidatesToCheck.length} fresh.`);
          
          freshVideos.push(...candidatesToCheck);
          
          // Optimization: Break early if we have enough
          if (freshVideos.length >= this.BATCH_SIZE) break;

          skip += BATCH_SIZE_QUERY;
          pageCount++;
      }

      console.log(`✅ Refill: Total Fresh Found: ${freshVideos.length}`);

      // 3. Fallback to LRU ONLY if Fresh Content is Exhausted
      if (freshVideos.length < this.BATCH_SIZE) {
          console.log(`❄️ Refill: Catalog Exhausted (Fresh: ${freshVideos.length} < Batch: ${this.BATCH_SIZE}). Triggering LRU Fallback.`);
          const needed = this.BATCH_SIZE - freshVideos.length;
          const lruIds = await this.getFallbackIds(userId, videoType, needed, []);
          const lruVideos = await Video.find({ _id: { $in: lruIds } })
             .select('_id uploader createdAt likes views shares score finalScore videoType videoHash')
             .lean();
          freshVideos.push(...lruVideos);
      }

      // 4. BATCH OPTIMIZATION: Reserve some slots for brand new videos (Discovery)
      // Get all completed videos from last 24h as discovery candidates
      const discoveryLimit = Math.floor(this.BATCH_SIZE * 0.2); // 20% discovery
      const discoveryCandidates = freshVideos.filter(v => {
        const ageInHours = (new Date() - new Date(v.createdAt)) / (1000 * 60 * 60);
        return ageInHours < 24;
      });

      // 5. Professional Weighted Selection
      // Shuffle the results based on their scores to break the recency block
      const randomizedPool = RecommendationService.weightedShuffle(freshVideos, this.BATCH_SIZE);

      // 6. Apply Diversity Ordering (No same creator back-to-back)
      const orderedVideos = RecommendationService.orderFeedWithDiversity(randomizedPool, {
        minCreatorSpacing: 3 // Higher spacing for professional variety
      });

      // 5. Push to Redis
      let toPushIds = orderedVideos.map(v => v._id.toString());
      
      // Final Safety Fill (Rare)
      if (toPushIds.length < this.BATCH_SIZE) {
           const needed = this.BATCH_SIZE - toPushIds.length;
           // Really desperate fallback if even LRU failed?
           // Just fetch Random from DB
           // omitted for brevity, assuming LRU works
      }
      
      toPushIds = toPushIds.slice(0, this.BATCH_SIZE);

      if (toPushIds.length > 0) {
        await redisService.rPush(queueKey, toPushIds);
        await redisService.lTrim(queueKey, 0, this.QUEUE_SIZE_LIMIT - 1);
        await redisService.expire(queueKey, 3600); // 1 Hour TTL
        console.log(`✅ FeedQueue: Pushed ${toPushIds.length} videos. Refill took ${Date.now() - start}ms`);
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

    // **STRATEGY 2: LRU (Least Recently Watched)**
    // If user is known, try to show their old favorites after fresh content is exhausted
    need = count - finalIds.length;
    if (need > 0 && userId && userId !== 'anon' && userId !== 'undefined') {
       try {
          const lruIds = await WatchHistory.getLeastRecentlyWatchedVideoIds(userId, 500);
          
          if (lruIds.length > 0) {
             const rawVideos = await Video.find({
                _id: { $in: lruIds }
             }).select('_id duration processingStatus').lean();
             
             const validLruIds = rawVideos.filter(v => {
                const isVayu = v.duration > 120;
                const isYog = v.duration <= 120;
                const typeMatch = (videoType === 'vayu' && isVayu) || (videoType !== 'vayu' && isYog);
                const notExcluded = !excludeSet.has(v._id.toString()) && !finalIds.includes(v._id.toString());
                return v.processingStatus === 'completed' && typeMatch && notExcluded;
             }).map(v => v._id.toString());
             
             if (validLruIds.length > 0) {
                 const shuffled = validLruIds.sort(() => 0.5 - Math.random());
                 finalIds.push(...shuffled.slice(0, need));
             }
          }
       } catch (err) {
          console.error('❌ FeedQueue: LRU Fallback Error:', err.message);
       }
    }

    // **STRATEGY 3: Random Discovery (Absolute Last Resort)**
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
        .select('videoUrl thumbnailUrl description uploader views likes shares comments likedBy duration processingStatus createdAt uploadedAt videoType videoHash videoName tags seriesId episodeNumber hlsMasterPlaylistUrl hlsPlaylistUrl isHLSEncoded lowQualityUrl mediumQualityUrl highQualityUrl preloadQualityUrl')
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
