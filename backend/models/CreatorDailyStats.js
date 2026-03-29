import mongoose from 'mongoose';

/**
 * CreatorDailyStats Model
 * Stores pre-computed aggregates for a creator per day.
 * This enables "Sliding Window" analytics without scanning the entire WatchHistory collection.
 */
const creatorDailyStatsSchema = new mongoose.Schema({
  creatorId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true,
    index: true
  },
  date: {
    type: Date,
    required: true,
    index: true
  },
  views: {
    type: Number,
    default: 0
  },
  watchTime: {
    type: Number,
    default: 0 // In seconds
  },
  shares: {
    type: Number,
    default: 0
  },
  skips: {
    type: Number,
    default: 0
  },
  uniqueViewers: {
    type: Number,
    default: 0
  }
}, {
  timestamps: true
});

// Compound index for fast lookup of a creator's stats for a specific day
creatorDailyStatsSchema.index({ creatorId: 1, date: 1 }, { unique: true });

const CreatorDailyStats = mongoose.model('CreatorDailyStats', creatorDailyStatsSchema);

export default CreatorDailyStats;
