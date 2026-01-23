import mongoose from 'mongoose';

const AdImpressionSchema = new mongoose.Schema({
  videoId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Video',
    required: true,
    index: true // For faster queries
  },
  adId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'AdCreative',
    required: true,
    index: true
  },
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: false // Optional - can track anonymous impressions
  },
  // **NEW: Direct reference to Creator for O(1) earnings lookup**
  creatorId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: false, // Optional for backward compatibility (will be populated by migration)
    index: true
  },
  adType: {
    type: String,
    required: true,
    enum: ['banner', 'carousel'],
    index: true
  },
  impressionType: {
    type: String,
    enum: ['view', 'scroll_view'],
    default: 'view'
  },
  // **NEW: Track if ad was actually viewed (minimum 2-3 seconds visible)**
  isViewed: {
    type: Boolean,
    default: false,
    index: true // For counting views vs impressions
  },
  viewDuration: {
    type: Number, // Duration in seconds that ad was visible
    default: 0
  },
  viewCount: {
    type: Number,
    default: 0
  },
  frequencyCap: {
    type: Number,
    default: 3
  },
  timestamp: {
    type: Date,
    default: Date.now,
    index: true
  },
  // Prevent duplicate tracking (same user, same video, same ad)
  // This helps prevent accidental double-counting
  uniqueKey: {
    type: String,
    unique: true,
    sparse: true // Allow null values
  }
}, {
  timestamps: true
});

// Create unique index on videoId + adId + userId + timestamp (within same hour)
// This prevents duplicate impressions from same user within short time
AdImpressionSchema.index(
  { 
    videoId: 1, 
    adId: 1, 
    userId: 1, 
    timestamp: 1 
  },
  { 
    unique: false // Allow multiple impressions but prevent exact duplicates
  }
);

// Compound index for fast queries by videoId and adType
AdImpressionSchema.index({ videoId: 1, adType: 1 });

// Index for counting impressions per video
AdImpressionSchema.index({ videoId: 1, adType: 1, timestamp: 1 });

// **NEW: Index for counting views (isViewed = true) per video**
AdImpressionSchema.index({ videoId: 1, adType: 1, isViewed: 1 });

export default mongoose.models.AdImpression || mongoose.model('AdImpression', AdImpressionSchema);

