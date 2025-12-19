import mongoose from 'mongoose';

/**
 * WatchHistory Model
 * Tracks which videos each user has watched for personalized feed recommendations
 * Separate collection for better scalability and query performance
 */
const WatchHistorySchema = new mongoose.Schema({
  userId: {
    type: String, // Google ID (for authenticated users) or deviceId (for anonymous users)
    required: true,
    index: true
  },
  isAuthenticated: {
    type: Boolean,
    default: false, // true if userId is Google ID, false if deviceId
    index: true
  },
  videoId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Video',
    required: true,
    index: true
  },
  watchedAt: {
    type: Date,
    default: Date.now,
    index: true
  },
  watchDuration: {
    type: Number,
    default: 0 // Duration in seconds
  },
  completed: {
    type: Boolean,
    default: false // Whether user watched the full video
  },
  watchCount: {
    type: Number,
    default: 1 // Number of times user watched this video
  },
  lastWatchedAt: {
    type: Date,
    default: Date.now
  }
}, {
  timestamps: true // Adds createdAt and updatedAt
});

// **Composite indexes for efficient queries**

// Index for finding user's watch history
WatchHistorySchema.index({ userId: 1, watchedAt: -1 });

// **PROFESSIONAL: Unique index to prevent duplicate entries per user-video pair**
// This allows same video to be tracked for different users (userId vs deviceId)
// But prevents duplicate entries for same user-video combination
WatchHistorySchema.index({ userId: 1, videoId: 1 }, { unique: true });

// Index for finding recently watched videos
WatchHistorySchema.index({ userId: 1, lastWatchedAt: -1 });

// Index for finding videos watched by users (for analytics)
WatchHistorySchema.index({ videoId: 1, watchedAt: -1 });

/**
 * Static method to get user's watched video IDs
 * @param {String} userId - Google ID or deviceId of the user
 * @param {Number} days - Number of days to look back (optional, null = no limit)
 * @returns {Promise<Array>} Array of video ObjectIds
 */
WatchHistorySchema.statics.getUserWatchedVideoIds = async function(userId, days = null) {
  try {
    const query = { userId: userId };
    
    // Only apply date filter if days is specified
    if (days !== null && days > 0) {
      const cutoffDate = new Date();
      cutoffDate.setDate(cutoffDate.getDate() - days);
      query.lastWatchedAt = { $gte: cutoffDate };
    }
    
    const watchHistory = await this.find(query).select('videoId').lean();
    
    return watchHistory.map(entry => entry.videoId);
  } catch (error) {
    console.error('❌ Error getting user watched video IDs:', error);
    return [];
  }
};

/**
 * Static method to get user's least-recently-watched video IDs
 * Used when user has watched (almost) all videos so we can resurface
 * old content instead of showing only recent uploads.
 *
 * @param {String} userId - Google ID or deviceId of the user
 * @param {Number} limit - Max number of video IDs to return
 * @param {Number} skip - How many entries to skip (for pagination)
 * @returns {Promise<Array>} Array of video ObjectIds ordered by lastWatchedAt ASC
 */
WatchHistorySchema.statics.getLeastRecentlyWatchedVideoIds = async function(
  userId,
  limit = 50,
  skip = 0
) {
  try {
    const history = await this.find({ userId })
      .select('videoId lastWatchedAt')
      .sort({ lastWatchedAt: 1 }) // oldest watches first
      .skip(skip)
      .limit(limit)
      .lean();

    return history.map(entry => entry.videoId);
  } catch (error) {
    console.error('❌ Error getting least-recently-watched video IDs:', error);
    return [];
  }
};

/**
 * Static method to track video watch
 * @param {String} userId - Google ID or deviceId of the user
 * @param {String} videoId - Video ObjectId
 * @param {Object} options - Additional options (duration, completed, isAuthenticated)
 * @returns {Promise<Object>} Watch history entry
 */
WatchHistorySchema.statics.trackWatch = async function(userId, videoId, options = {}) {
  try {
    const { duration = 0, completed = false, isAuthenticated = false } = options;
    
    // Update or create watch history entry
    const watchEntry = await this.findOneAndUpdate(
      { userId: userId, videoId: videoId },
      {
        $set: {
          lastWatchedAt: new Date(),
          watchDuration: duration,
          completed: completed,
          isAuthenticated: isAuthenticated
        },
        $inc: { watchCount: 1 },
        $setOnInsert: {
          watchedAt: new Date()
        }
      },
      {
        upsert: true,
        new: true
      }
    );
    
    return watchEntry;
  } catch (error) {
    console.error('❌ Error tracking watch:', error);
    throw error;
  }
};

/**
 * Static method to check if user has watched a video
 * @param {String} userId - Google ID of the user
 * @param {String} videoId - Video ObjectId
 * @returns {Promise<Boolean>} True if user has watched the video
 */
WatchHistorySchema.statics.hasUserWatched = async function(userId, videoId) {
  try {
    const watchEntry = await this.findOne({
      userId: userId,
      videoId: videoId
    }).lean();
    
    return !!watchEntry;
  } catch (error) {
    console.error('❌ Error checking watch status:', error);
    return false;
  }
};

/**
 * Clear old watch history for a user (older than specified days)
 * Used when user has watched most videos to reset feed variety
 * 
 * @param {String} userId - Google ID or deviceId of the user
 * @param {Number} days - Delete watch history older than X days (default: 30)
 * @returns {Promise<Object>} Result with count of deleted entries
 */
WatchHistorySchema.statics.clearOldWatchHistory = async function(userId, days = 30) {
  try {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - days);
    
    const result = await this.deleteMany({
      userId: userId,
      lastWatchedAt: { $lt: cutoffDate }
    });
    
    console.log(`🧹 Cleared ${result.deletedCount} old watch history entries (older than ${days} days) for user: ${userId}`);
    
    return {
      deletedCount: result.deletedCount,
      cutoffDate: cutoffDate,
      userId: userId
    };
  } catch (error) {
    console.error('❌ Error clearing old watch history:', error);
    throw error;
  }
};

/**
 * Clear all watch history for a user
 * Used when user has watched almost all videos
 * 
 * @param {String} userId - Google ID or deviceId of the user
 * @returns {Promise<Object>} Result with count of deleted entries
 */
WatchHistorySchema.statics.clearAllWatchHistory = async function(userId) {
  try {
    const result = await this.deleteMany({ userId: userId });
    
    console.log(`🧹 Cleared all watch history (${result.deletedCount} entries) for user: ${userId}`);
    
    return {
      deletedCount: result.deletedCount,
      userId: userId
    };
  } catch (error) {
    console.error('❌ Error clearing all watch history:', error);
    throw error;
  }
};

/**
 * Instance method to check if watch is recent (within X days)
 * @param {Number} days - Number of days (default: 30)
 * @returns {Boolean} True if watched recently
 */
WatchHistorySchema.methods.isRecent = function(days = 30) {
  const cutoffDate = new Date();
  cutoffDate.setDate(cutoffDate.getDate() - days);
  return this.lastWatchedAt >= cutoffDate;
};

const WatchHistory = mongoose.model('WatchHistory', WatchHistorySchema);

export default WatchHistory;

