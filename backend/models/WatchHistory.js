import mongoose from 'mongoose';

/**
 * WatchHistory Model
 * Tracks which videos each user has watched for personalized feed recommendations
 * Separate collection for better scalability and query performance
 */
const WatchHistorySchema = new mongoose.Schema({
  userId: {
    type: String, // Google ID
    required: true,
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

// Unique index to prevent duplicate entries (one user can watch a video multiple times)
WatchHistorySchema.index({ userId: 1, videoId: 1 }, { unique: true });

// Index for finding recently watched videos
WatchHistorySchema.index({ userId: 1, lastWatchedAt: -1 });

// Index for finding videos watched by users (for analytics)
WatchHistorySchema.index({ videoId: 1, watchedAt: -1 });

/**
 * Static method to get user's watched video IDs
 * @param {String} userId - Google ID of the user
 * @param {Number} days - Number of days to look back (optional, default: 30)
 * @returns {Promise<Array>} Array of video ObjectIds
 */
WatchHistorySchema.statics.getUserWatchedVideoIds = async function(userId, days = 30) {
  try {
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - days);
    
    const watchHistory = await this.find({
      userId: userId,
      lastWatchedAt: { $gte: cutoffDate }
    }).select('videoId').lean();
    
    return watchHistory.map(entry => entry.videoId);
  } catch (error) {
    console.error('❌ Error getting user watched video IDs:', error);
    return [];
  }
};

/**
 * Static method to track video watch
 * @param {String} userId - Google ID of the user
 * @param {String} videoId - Video ObjectId
 * @param {Object} options - Additional options (duration, completed)
 * @returns {Promise<Object>} Watch history entry
 */
WatchHistorySchema.statics.trackWatch = async function(userId, videoId, options = {}) {
  try {
    const { duration = 0, completed = false } = options;
    
    // Update or create watch history entry
    const watchEntry = await this.findOneAndUpdate(
      { userId: userId, videoId: videoId },
      {
        $set: {
          lastWatchedAt: new Date(),
          watchDuration: duration,
          completed: completed
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

