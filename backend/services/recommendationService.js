import Video from '../models/Video.js';
import WatchHistory from '../models/WatchHistory.js';

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
   * Fresh content gets a healthy push, old content gradually reduced
   * 
   * @param {Date} uploadedAt - Video upload date
   * @returns {Number} Recency boost multiplier (typically 0.1 to 1.0)
   */
  static calculateRecencyBoost(uploadedAt) {
    if (!uploadedAt) return 0.1; // Default low boost for missing date
    
    const now = new Date();
    const uploadDate = new Date(uploadedAt);
    const ageInDays = (now - uploadDate) / (1000 * 60 * 60 * 24);
    
    // Formula: 1 / (1 + ageInDays * 0.1)
    // New content (0 days) → 1.0 boost
    // 10 days old → ~0.5 boost
    // 30 days old → ~0.25 boost
    // 90 days old → ~0.1 boost
    const recencyBoost = 1 / (1 + ageInDays * 0.1);
    
    return Math.max(recencyBoost, 0.1); // Minimum 0.1 boost
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
}

export default RecommendationService;

