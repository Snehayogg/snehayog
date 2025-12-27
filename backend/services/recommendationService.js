import Video from '../models/Video.js';
import WatchHistory from '../models/WatchHistory.js';
import aiSemanticService from './aiSemanticService.js';

/**
 * Balanced Recommendation System Service
 * 
 * Implements a scalable recommendation system based on:
 * - Balanced Watch Score (60%): Combines % completion + raw watch time (capped at 15s)
 * - Engagement Score (20%): Likes + Comments normalized by views
 * - Share Score (20%): Shares normalized by views
 * - Recency Boost: Multiplier for fresh content
 * 
 * Formula:
 * FinalScore = (0.6 × WatchScore + 0.2 × (LikeScore + CommentScore) + 0.2 × ShareScore) × RecencyBoost
 */
class RecommendationService {
  /**
   * Calculate Balanced Watch Score
   * Combines percentage completion (good for short videos) with raw watch time (good for long videos)
   * 
   * @param {Number} totalWatchTime - Total watch time in seconds
   * @param {Number} videoDuration - Video duration in seconds
   * @returns {Number} Watch score between 0 and 1
   */
  static calculateWatchScore(totalWatchTime, videoDuration) {
    if (!videoDuration || videoDuration <= 0) return 0;
    if (!totalWatchTime || totalWatchTime <= 0) return 0;
    
    // First part: Percentage completion (good for short videos)
    const completionScore = totalWatchTime / videoDuration;
    
    // Second part: Raw watch time capped at 15 seconds (industry standard)
    // This rewards long videos that keep users watching
    const rawWatchScore = Math.min(totalWatchTime, 15) / 15;
    
    // Balanced combination: 50% completion + 50% raw watch time
    const watchScore = 0.5 * completionScore + 0.5 * rawWatchScore;
    
    return Math.min(Math.max(watchScore, 0), 1); // Clamp between 0 and 1
  }
  
  /**
   * Calculate Engagement Score (Likes + Comments)
   * Normalized by total views to prevent bias toward high-view videos
   * 
   * @param {Number} totalLikes - Total likes
   * @param {Number} totalComments - Total comments
   * @param {Number} totalViews - Total views
   * @returns {Number} Engagement score between 0 and 1
   */
  static calculateEngagementScore(totalLikes, totalComments, totalViews) {
    if (!totalViews || totalViews <= 0) return 0;
    
    const likeScore = totalLikes / totalViews;
    const commentScore = totalComments / totalViews;
    
    // Combined engagement score
    const engagementScore = likeScore + commentScore;
    
    // Normalize to 0-1 range (assuming max 0.5 engagement rate is excellent)
    return Math.min(engagementScore / 0.5, 1);
  }
  
  /**
   * Calculate Share Score
   * Normalized by total views
   * 
   * @param {Number} totalShares - Total shares
   * @param {Number} totalViews - Total views
   * @returns {Number} Share score between 0 and 1
   */
  static calculateShareScore(totalShares, totalViews) {
    if (!totalViews || totalViews <= 0) return 0;
    
    const shareScore = totalShares / totalViews;
    
    // Normalize to 0-1 range (assuming max 0.1 share rate is excellent)
    return Math.min(shareScore / 0.1, 1);
  }
  
  /**
   * Calculate Recency Boost
   * Balanced approach: Newer videos get a slight boost, but it doesn't dominate
   * More balanced than before to ensure older quality content still gets shown
   * 
   * @param {Date} uploadedAt - Video upload date
   * @returns {Number} Recency boost multiplier (typically 0.7 to 1.0)
   */
  static calculateRecencyBoost(uploadedAt) {
    if (!uploadedAt) return 0.7; // Default reasonable boost for missing date
    
    const now = new Date();
    const uploadDate = new Date(uploadedAt);
    const ageInDays = (now - uploadDate) / (1000 * 60 * 60 * 24);
    
    // More balanced formula: 0.7 + 0.3 / (1 + ageInDays * 0.05)
    // New content (0 days) → 1.0 boost (slight advantage)
    // 10 days old → ~0.9 boost
    // 30 days old → ~0.83 boost
    // 90 days old → ~0.76 boost
    // 180 days old → ~0.73 boost
    // Very old content → ~0.7 boost (still competitive, not penalized too much)
    // This ensures fresh content is discovered but doesn't completely hide older quality content
    const recencyBoost = 0.7 + (0.3 / (1 + ageInDays * 0.05));
    
    return Math.max(recencyBoost, 0.7); // Minimum 0.7 boost (more balanced)
  }
  
  /**
   * Calculate Final Recommendation Score
   * Combines all components with proper weights
   * 
   * @param {Object} videoData - Video data object
   * @param {Number} videoData.totalWatchTime - Total watch time in seconds
   * @param {Number} videoData.duration - Video duration in seconds
   * @param {Number} videoData.likes - Total likes
   * @param {Number} videoData.comments - Total comments (array length or count)
   * @param {Number} videoData.shares - Total shares
   * @param {Number} videoData.views - Total views
   * @param {Date} videoData.uploadedAt - Upload date
   * @returns {Number} Final score (higher is better)
   */
  static calculateFinalScore(videoData) {
    const {
      totalWatchTime = 0,
      duration = 0,
      likes = 0,
      comments = 0,
      shares = 0,
      views = 0,
      uploadedAt
    } = videoData;
    
    // Get comment count (handle both array and number)
    const commentCount = Array.isArray(comments) ? comments.length : (comments || 0);
    
    // Calculate component scores
    const watchScore = this.calculateWatchScore(totalWatchTime, duration);
    const engagementScore = this.calculateEngagementScore(likes, commentCount, views);
    const shareScore = this.calculateShareScore(shares, views);
    const recencyBoost = this.calculateRecencyBoost(uploadedAt);
    
    // Final score formula:
    // 60% watch score + 20% engagement + 20% shares, then multiply by recency boost
    const baseScore = 0.6 * watchScore + 0.2 * engagementScore + 0.2 * shareScore;
    const finalScore = baseScore * recencyBoost;
    
    return Math.max(finalScore, 0); // Ensure non-negative
  }
  
  /**
   * Aggregate total watch time for a video from WatchHistory
   * 
   * @param {String} videoId - Video ObjectId
   * @returns {Promise<Number>} Total watch time in seconds
   */
  static async aggregateTotalWatchTime(videoId) {
    try {
      const result = await WatchHistory.aggregate([
        { $match: { videoId: videoId } },
        { $group: { _id: null, totalWatchTime: { $sum: '$watchDuration' } } }
      ]);
      
      return result.length > 0 ? (result[0].totalWatchTime || 0) : 0;
    } catch (error) {
      console.error(`❌ Error aggregating watch time for video ${videoId}:`, error);
      return 0;
    }
  }
  
  /**
   * Calculate and update score for a single video
   * 
   * @param {String} videoId - Video ObjectId
   * @returns {Promise<Object>} Updated video with new score
   */
  static async calculateAndUpdateVideoScore(videoId) {
    try {
      const video = await Video.findById(videoId);
      if (!video) {
        throw new Error(`Video not found: ${videoId}`);
      }
      
      // Aggregate total watch time from WatchHistory
      const totalWatchTime = await this.aggregateTotalWatchTime(videoId);
      
      // Calculate final score
      const finalScore = this.calculateFinalScore({
        totalWatchTime,
        duration: video.duration || 0,
        likes: video.likes || 0,
        comments: video.comments || [],
        shares: video.shares || 0,
        views: video.views || 0,
        uploadedAt: video.uploadedAt || video.createdAt
      });
      
      // Update video with new score and watch time
      video.totalWatchTime = totalWatchTime;
      video.finalScore = finalScore;
      video.scoreUpdatedAt = new Date();
      
      await video.save();
      
      return {
        videoId: video._id,
        totalWatchTime,
        finalScore,
        watchScore: this.calculateWatchScore(totalWatchTime, video.duration || 0),
        engagementScore: this.calculateEngagementScore(
          video.likes || 0,
          Array.isArray(video.comments) ? video.comments.length : 0,
          video.views || 0
        ),
        shareScore: this.calculateShareScore(video.shares || 0, video.views || 0),
        recencyBoost: this.calculateRecencyBoost(video.uploadedAt || video.createdAt)
      };
    } catch (error) {
      console.error(`❌ Error calculating score for video ${videoId}:`, error);
      throw error;
    }
  }
  
  /**
   * Calculate diversity-aware feed ordering
   * Ensures no same creator appears back-to-back while maintaining score-based ranking
   * 
   * @param {Array} videos - Array of video objects with finalScore and uploader
   * @param {Object} options - Options for ordering
   * @param {Number} options.randomness - Randomness factor (0-1, default: 0.15 for 15%)
   * @param {Number} options.minCreatorSpacing - Minimum videos between same creator (default: 2)
   * @returns {Array} Ordered array of videos with creator diversity
   */
  static orderFeedWithDiversity(videos, options = {}) {
    const {
      randomness = 0.15, // 15% controlled randomness
      minCreatorSpacing = 2 // Minimum 2 videos between same creator
    } = options;

    if (!videos || videos.length === 0) return [];

    // Create a copy to avoid mutating original
    let remaining = videos.map((v, idx) => ({
      ...v,
      originalIndex: idx
    }));

    const ordered = [];
    const creatorLastPositions = new Map(); // Track last position of each creator
    let position = 0;

    while (remaining.length > 0) {
      // Filter candidates that can be placed at current position
      const candidates = remaining.filter(video => {
        const creatorId = video.uploader?._id?.toString() || 
                         video.uploader?.googleId?.toString() || 
                         video.uploader?.id?.toString() || 
                         'unknown';
        const lastPosition = creatorLastPositions.get(creatorId);
        
        // Check spacing requirement
        if (lastPosition !== undefined) {
          const spacing = position - lastPosition - 1;
          if (spacing < minCreatorSpacing) {
            return false;
          }
        }
        return true;
      });

      let selected;

      if (candidates.length === 0) {
        // No candidates meet spacing requirement, relax constraint and take best available
        // This prevents infinite loops when same creator has many videos
        const relaxedCandidates = remaining.filter(video => {
          const creatorId = video.uploader?._id?.toString() || 
                           video.uploader?.googleId?.toString() || 
                           video.uploader?.id?.toString() || 
                           'unknown';
          const lastPosition = creatorLastPositions.get(creatorId);
          return lastPosition === undefined || (position - lastPosition - 1) >= 1;
        });

        if (relaxedCandidates.length > 0) {
          candidates.push(...relaxedCandidates);
        } else {
          // Still none? Just take the first remaining video
          selected = remaining[0];
        }
      }

      if (!selected && candidates.length > 0) {
        // Score-based selection with controlled randomness
        candidates.forEach(candidate => {
          const baseScore = candidate.finalScore || 0;
          const randomAdjustment = (Math.random() - 0.5) * randomness;
          candidate.adjustedScore = baseScore * (1 + randomAdjustment);
        });

        // Sort by adjusted score (descending)
        candidates.sort((a, b) => {
          const scoreDiff = b.adjustedScore - a.adjustedScore;
          if (Math.abs(scoreDiff) > 0.001) {
            return scoreDiff;
          }
          // Tiebreaker: add more randomness
          return Math.random() - 0.5;
        });

        selected = candidates[0];
      }

      if (!selected) {
        selected = remaining[0];
      }

      // Add selected video to ordered list
      ordered.push(selected);

      // Update creator position tracking
      const creatorId = selected.uploader?._id?.toString() || 
                       selected.uploader?.googleId?.toString() || 
                       selected.uploader?.id?.toString() || 
                       'unknown';
      creatorLastPositions.set(creatorId, position);

      // Remove from remaining
      remaining = remaining.filter(v => {
        const vId = v._id?.toString() || v._id;
        const sId = selected._id?.toString() || selected._id;
        return vId !== sId;
      });

      position++;
    }

    // Remove temporary properties
    return ordered.map(({ originalIndex, adjustedScore, ...video }) => video);
  }

  /**
   * Recalculate scores for all videos (or a batch)
   * 
   * @param {Object} options - Options for batch processing
   * @param {Number} options.batchSize - Number of videos to process at once (default: 100)
   * @param {Number} options.limit - Maximum number of videos to process (default: all)
   * @param {Boolean} options.onlyOutdated - Only update videos with old scores (default: false)
   * @param {Number} options.maxAgeMinutes - Max age of score in minutes before considered outdated (default: 30)
   * @returns {Promise<Object>} Statistics about the update
   */
  static async recalculateAllScores(options = {}) {
    const {
      batchSize = 100,
      limit = null,
      onlyOutdated = false,
      maxAgeMinutes = 30
    } = options;
    
    try {
      console.log('🔄 Starting recommendation score recalculation...');
      
      // Build query
      const query = { processingStatus: 'completed' }; // Only process completed videos
      
      if (onlyOutdated) {
        const cutoffDate = new Date();
        cutoffDate.setMinutes(cutoffDate.getMinutes() - maxAgeMinutes);
        query.$or = [
          { scoreUpdatedAt: { $exists: false } },
          { scoreUpdatedAt: { $lt: cutoffDate } }
        ];
      }
      
      // Get total count
      const totalVideos = await Video.countDocuments(query);
      console.log(`📊 Found ${totalVideos} videos to process`);
      
      let processed = 0;
      let errors = 0;
      const startTime = Date.now();
      
      // Process in batches
      let skip = 0;
      const actualLimit = limit || totalVideos;
      
      while (skip < actualLimit && skip < totalVideos) {
        const videos = await Video.find(query)
          .select('_id duration likes comments shares views uploadedAt createdAt')
          .limit(batchSize)
          .skip(skip)
          .lean();
        
        if (videos.length === 0) break;
        
        // Process batch
        for (const video of videos) {
          try {
            await this.calculateAndUpdateVideoScore(video._id);
            processed++;
            
            if (processed % 50 === 0) {
              console.log(`✅ Processed ${processed}/${Math.min(actualLimit, totalVideos)} videos...`);
            }
          } catch (error) {
            errors++;
            console.error(`❌ Error processing video ${video._id}:`, error.message);
          }
        }
        
        skip += batchSize;
      }
      
      const duration = ((Date.now() - startTime) / 1000).toFixed(2);
      
      const stats = {
        totalVideos,
        processed,
        errors,
        duration: `${duration}s`,
        success: errors === 0
      };
      
      console.log(`✅ Score recalculation complete:`, stats);
      return stats;
    } catch (error) {
      console.error('❌ Error in recalculateAllScores:', error);
      throw error;
    }
  }

  /**
   * Real-time session learning (like Instagram/YouTube Shorts)
   * Learns from user's current session and recommends similar content using AI
   * 
   * @param {String} userId - User ID (Google ID or deviceId)
   * @param {String} currentVideoId - Current video ID to exclude from results
   * @param {Number} limit - Number of videos to return
   * @returns {Promise<Array>} Array of recommended videos
   */
  static async getSessionBasedRecommendations(userId, currentVideoId = null, limit = 20) {
    try {
      console.log('🎯 RecommendationService: Getting session-based recommendations for user:', userId);
      
      // Get last 5-10 videos user watched in this session (last 30 minutes)
      const thirtyMinutesAgo = new Date(Date.now() - 30 * 60 * 1000);
      const recentWatches = await WatchHistory.find({ 
        userId,
        watchedAt: { $gte: thirtyMinutesAgo }
      })
        .sort({ watchedAt: -1 })
        .limit(10)
        .populate('videoId')
        .lean();
      
      console.log(`📊 Found ${recentWatches.length} recent watches in session`);
      
      if (recentWatches.length < 2) {
        // Not enough session data, use default recommendations
        console.log('⚠️ Not enough session data, using default recommendations');
        return await this.getDefaultRecommendations(limit, currentVideoId);
      }
      
      // Extract patterns from session
      const sessionPatterns = {
        categories: new Map(),
        tags: new Map(),
        creators: new Map(),
        keywords: new Set(),
        watchedVideoIds: new Set()
      };
      
      recentWatches.forEach(watch => {
        const video = watch.videoId;
        if (!video) return;
        
        // Track watched videos to exclude
        sessionPatterns.watchedVideoIds.add(video._id.toString());
        
        // Category pattern (weighted by watch duration)
        if (video.category) {
          const weight = watch.watchDuration || 1;
          sessionPatterns.categories.set(
            video.category,
            (sessionPatterns.categories.get(video.category) || 0) + weight
          );
        }
        
        // Tag pattern
        if (video.tags && Array.isArray(video.tags)) {
          video.tags.forEach(tag => {
            const weight = watch.watchDuration || 1;
            sessionPatterns.tags.set(
              tag,
              (sessionPatterns.tags.get(tag) || 0) + weight
            );
          });
        }
        
        // Creator pattern
        const creatorId = video.uploader?.toString();
        if (creatorId) {
          const weight = watch.watchDuration || 1;
          sessionPatterns.creators.set(
            creatorId,
            (sessionPatterns.creators.get(creatorId) || 0) + weight
          );
        }
        
        // Keywords from video name/description
        const text = `${video.videoName || ''} ${video.description || ''}`.toLowerCase();
        const keywords = text.split(/\s+/).filter(w => w.length > 3);
        keywords.forEach(kw => sessionPatterns.keywords.add(kw));
      });
      
      // Get top patterns (what user is interested in RIGHT NOW)
      const topCategories = Array.from(sessionPatterns.categories.entries())
        .sort((a, b) => b[1] - a[1])
        .slice(0, 3)
        .map(([cat]) => cat);
      
      const topTags = Array.from(sessionPatterns.tags.entries())
        .sort((a, b) => b[1] - a[1])
        .slice(0, 5)
        .map(([tag]) => tag);
      
      const topCreators = Array.from(sessionPatterns.creators.entries())
        .sort((a, b) => b[1] - a[1])
        .slice(0, 3)
        .map(([creator]) => creator);
      
      console.log('🎯 Session patterns detected:', {
        categories: topCategories,
        tags: topTags.slice(0, 3),
        creators: topCreators.length
      });
      
      // Find similar videos using AI embeddings (like Instagram/YouTube)
      const similarVideos = await this.findSimilarVideosUsingAI(
        recentWatches.map(w => w.videoId).filter(Boolean),
        topCategories,
        topTags,
        currentVideoId,
        Array.from(sessionPatterns.watchedVideoIds),
        limit
      );
      
      return similarVideos;
    } catch (error) {
      console.error('❌ Error in session-based recommendations:', error);
      return await this.getDefaultRecommendations(limit, currentVideoId);
    }
  }

  /**
   * Use AI embeddings to find similar videos (like Instagram/YouTube)
   * This is the key to real-time learning - no hardcoding needed!
   */
  static async findSimilarVideosUsingAI(
    watchedVideos,
    preferredCategories,
    preferredTags,
    excludeVideoId,
    excludeVideoIds,
    limit
  ) {
    try {
      console.log('🤖 Using AI to find similar videos...');
      
      // Get embeddings for watched videos
      const watchedEmbeddings = [];
      for (const video of watchedVideos) {
        if (!video) continue;
        const text = `${video.videoName || ''} ${video.description || ''}`.trim();
        if (!text) continue;
        
        try {
          const embedding = await aiSemanticService.getEmbedding(text);
          if (embedding) {
            watchedEmbeddings.push(embedding);
          }
        } catch (error) {
          console.warn('⚠️ Failed to get embedding for video:', video._id);
        }
      }
      
      if (watchedEmbeddings.length === 0) {
        // Fallback to category/tag matching if AI fails
        console.log('⚠️ No embeddings available, using category/tag matching');
        return await this.findVideosByPatterns(
          preferredCategories,
          preferredTags,
          excludeVideoId,
          excludeVideoIds,
          limit
        );
      }
      
      // Calculate average embedding (user's current interest vector)
      const avgEmbedding = this.calculateAverageEmbedding(watchedEmbeddings);
      if (!avgEmbedding) {
        return await this.findVideosByPatterns(
          preferredCategories,
          preferredTags,
          excludeVideoId,
          excludeVideoIds,
          limit
        );
      }
      
      console.log('✅ Calculated user interest vector from session');
      
      // Build query for candidate videos
      const excludeIds = [excludeVideoId, ...excludeVideoIds].filter(Boolean);
      const query = {
        _id: { $nin: excludeIds },
        processingStatus: 'completed'
      };
      
      // Add category/tag filters to narrow down candidates
      const orConditions = [];
      if (preferredCategories.length > 0) {
        orConditions.push({ category: { $in: preferredCategories } });
      }
      if (preferredTags.length > 0) {
        orConditions.push({ tags: { $in: preferredTags } });
      }
      
      if (orConditions.length > 0) {
        query.$or = orConditions;
      }
      
      // Get candidate videos (more than limit for AI filtering)
      const candidates = await Video.find(query)
        .sort({ finalScore: -1, createdAt: -1 })
        .limit(Math.min(100, limit * 5)) // Get 5x candidates for AI filtering
        .lean();
      
      if (candidates.length === 0) {
        console.log('⚠️ No candidate videos found, using default recommendations');
        return await this.getDefaultRecommendations(limit, excludeVideoId);
      }
      
      console.log(`🤖 Scoring ${candidates.length} candidate videos using AI...`);
      
      // Score each candidate using cosine similarity
      const scoredVideos = [];
      for (const video of candidates) {
        try {
          const text = `${video.videoName || ''} ${video.description || ''}`.trim();
          if (!text) continue;
          
          const videoEmbedding = await aiSemanticService.getEmbedding(text);
          if (!videoEmbedding) continue;
          
          const similarity = aiSemanticService.cosineSimilarity(
            avgEmbedding,
            videoEmbedding
          );
          
          // Combine AI similarity (70%) with base score (30%)
          const baseScore = video.finalScore || 0;
          const normalizedBaseScore = Math.min(baseScore / 10, 1); // Normalize to 0-1
          const combinedScore = (0.7 * similarity) + (0.3 * normalizedBaseScore);
          
          scoredVideos.push({
            video,
            score: combinedScore,
            similarity,
            baseScore: normalizedBaseScore
          });
        } catch (error) {
          // Skip this video if embedding fails
          continue;
        }
      }
      
      // Sort by combined score
      scoredVideos.sort((a, b) => b.score - a.score);
      
      console.log(`✅ AI scoring complete. Top 3 similarities: ${scoredVideos.slice(0, 3).map(s => s.similarity.toFixed(3)).join(', ')}`);
      
      // Return top videos
      return scoredVideos
        .slice(0, limit)
        .map(item => item.video);
        
    } catch (error) {
      console.error('❌ Error in AI-based similarity:', error);
      // Fallback
      return await this.findVideosByPatterns(
        preferredCategories,
        preferredTags,
        excludeVideoId,
        excludeVideoIds,
        limit
      );
    }
  }

  /**
   * Calculate average embedding from multiple embeddings
   * This represents the user's current interest vector
   */
  static calculateAverageEmbedding(embeddings) {
    if (embeddings.length === 0) return null;
    
    const dimension = embeddings[0].length;
    const avg = new Array(dimension).fill(0);
    
    embeddings.forEach(embedding => {
      for (let i = 0; i < dimension; i++) {
        avg[i] += embedding[i];
      }
    });
    
    // Average
    for (let i = 0; i < dimension; i++) {
      avg[i] /= embeddings.length;
    }
    
    // Normalize
    const norm = Math.sqrt(avg.reduce((sum, val) => sum + val * val, 0));
    if (norm > 0) {
      for (let i = 0; i < dimension; i++) {
        avg[i] /= norm;
      }
    }
    
    return avg;
  }

  /**
   * Fallback: Find videos by category/tag patterns (when AI is not available)
   */
  static async findVideosByPatterns(categories, tags, excludeVideoId, excludeVideoIds, limit) {
    const query = {
      _id: { $nin: [excludeVideoId, ...excludeVideoIds].filter(Boolean) },
      processingStatus: 'completed'
    };
    
    const orConditions = [];
    if (categories.length > 0) {
      orConditions.push({ category: { $in: categories } });
    }
    if (tags.length > 0) {
      orConditions.push({ tags: { $in: tags } });
    }
    
    if (orConditions.length > 0) {
      query.$or = orConditions;
    }
    
    return await Video.find(query)
      .sort({ finalScore: -1, createdAt: -1 })
      .limit(limit)
      .lean();
  }

  /**
   * Default recommendations when no session data is available
   */
  static async getDefaultRecommendations(limit, excludeVideoId = null) {
    const query = {
      processingStatus: 'completed'
    };
    
    if (excludeVideoId) {
      query._id = { $ne: excludeVideoId };
    }
    
    return await Video.find(query)
      .sort({ finalScore: -1, createdAt: -1 })
      .limit(limit)
      .lean();
  }
}

export default RecommendationService;

