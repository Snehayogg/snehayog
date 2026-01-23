import mongoose from 'mongoose';
import View from './View.js';

const videoSchema = new mongoose.Schema({
  videoName: {
    type: String,
    required: true,
    trim: true
  },
  videoUrl: {
    type: String,
    required: true
  },
  thumbnailUrl: {
    type: String,
    required: false,
    default: ''
  },
  description: {
    type: String,
    trim: true
  },
  uploader: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  uploadedAt: {
    type: Date,
    default: Date.now
  },
  likes: {
    type: Number,
    default: 0
  },
  views: {
    type: Number,
    default: 0
  },
  // **Refactored: viewDetails removed for performance. Views are now tracked in 'View' collection.**
  
  shares: {
    type: Number,
    default: 0
  },
  likedBy: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User'
  }],
  videoType: {
    type: String,
    default: 'yog'
  },
  // **NEW: Media type for feed entries (video vs image)**
  mediaType: {
  type: String,
  enum: ['video', 'image'],
  default: 'video'
  },
  // **NEW: Category and tags for ad targeting**
  category: {
    type: String,
    trim: true,
    lowercase: true,
    index: true // For faster ad targeting queries
  },
  tags: [{
    type: String,
    trim: true,
    lowercase: true
  }],
  keywords: [{
    type: String,
    trim: true,
    lowercase: true
  }],
  aspectRatio: {
    type: Number,
    default: 9/16
  },
  duration: {
    type: Number,
    default: 0
  },
  comments: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Comment'
  }],
  link: {
    type: String,
    trim: true
  },
  
  // **NEW: Quality URLs for adaptive streaming**
  preloadQualityUrl: {
    type: String,
    description: '360p - Fastest loading for preloading'
  },
  lowQualityUrl: {
    type: String,
    description: '480p - Low quality for slow networks (2-5 Mbps)'
  },
  mediumQualityUrl: {
    type: String,
    description: '720p - Medium quality for average networks (5-10 Mbps)'
  },
  highQualityUrl: {
    type: String,
    description: '1080p - High quality for fast networks (10+ Mbps)'
  },
  
  // **NEW: Video processing status**
  processingStatus: {
    type: String,
    enum: ['pending', 'processing', 'completed', 'failed'],
    default: 'pending'
  },
  processingProgress: {
    type: Number,
    min: 0,
    max: 100,
    default: 0
  },
  processingError: {
    type: String
  },
  
  // **NEW: Video metadata**
  originalSize: {
    type: Number,
    description: 'Original file size in bytes'
  },
  originalFormat: {
    type: String,
    description: 'Original video format (mp4, mov, etc.)'
  },
  originalResolution: {
    width: Number,
    height: Number
  },
  
  // **NEW: Quality metadata**
  qualitiesGenerated: [{
    quality: String, 
    url: String,
    size: Number,
    resolution: {
      width: Number,
      height: Number
    },
    bitrate: String,
    generatedAt: {
      type: Date,
      default: Date.now
    }
  }],
  
  // **NEW: HLS Streaming fields**
  hlsMasterPlaylistUrl: String,
  hlsPlaylistUrl: String,
  hlsVariants: [{
    bandwidth: Number,
    resolution: String,
    url: String
  }],
  isHLSEncoded: {
    type: Boolean,
    default: false
  },
  
  // **NEW: Video hash for duplicate detection**
  videoHash: {
    type: String,
    index: true, // For faster duplicate checks
    sparse: true
  },
  
  // **NEW: Recommendation system fields**
  totalWatchTime: {
    type: Number,
    default: 0, // Total watch time in seconds (aggregated from WatchHistory)
    description: 'Total watch time across all users for recommendation scoring'
  },
  // **NEW: Series/Episode Metadata**
  seriesId: {
    type: String,
    index: true,
    default: null,
    description: 'UUID connecting multiple episodes of a series'
  },
  episodeNumber: {
    type: Number,
    default: 0,
    description: 'Order of the video in the series'
  },

  finalScore: {
    type: Number,
    default: 0, // Final recommendation score (calculated periodically)
    index: true, // Indexed for efficient sorting
    description: 'Balanced recommendation score: 60% watch score + 20% engagement + 20% shares, multiplied by recency boost'
  },
  scoreUpdatedAt: {
    type: Date,
    default: Date.now,
    description: 'Timestamp when finalScore was last calculated'
  }
}, {
  timestamps: true
});

// **NEW: Index for faster queries**
videoSchema.index({ uploader: 1, uploadedAt: -1 });
videoSchema.index({ uploader: 1, createdAt: -1 }); // **OPTIMIZATION: Match route sort order**
videoSchema.index({ processingStatus: 1 });
videoSchema.index({ 'qualitiesGenerated.quality': 1 });
// **NEW: Compound index for faster duplicate queries**
videoSchema.index({ uploader: 1, videoHash: 1 });
// **NEW: Index for recommendation system - sort by finalScore**
videoSchema.index({ finalScore: -1 });

// **NEW: Virtual field to check if video has multiple qualities**
videoSchema.virtual('hasMultipleQualities').get(function() {
  return !!(this.preloadQualityUrl || this.lowQualityUrl || 
           this.mediumQualityUrl || this.highQualityUrl);
});

// Method to get 480p quality URL (standardized for all videos)
videoSchema.methods.get480pUrl = function() {
  return this.lowQualityUrl || this.videoUrl;
};

// **NEW: Method to update processing status**
videoSchema.methods.updateProcessingStatus = function(status, progress = null, error = null) {
  this.processingStatus = status;
  if (progress !== null) this.processingProgress = progress;
  if (error !== null) this.processingError = error;
  return this.save();
};

// **NEW: Method to add quality version**
videoSchema.methods.addQualityVersion = function(quality, url, metadata) {
  this.qualitiesGenerated.push({
    quality,
    url,
    size: metadata.size || 0,
    resolution: metadata.resolution || {},
    bitrate: metadata.bitrate || '',
    generatedAt: new Date()
  });
  
  // Update the corresponding quality URL field
  const fieldName = `${quality}QualityUrl`;
  if (this.schema.paths[fieldName]) {
    this[fieldName] = url;
  }
  
  return this.save();
};

// **PERFORMANCE FIX: Separate View Tracking**
// Instead of embedding views in the Video document (which causes massive documents),
// we now use a separate 'View' collection.

videoSchema.methods.incrementView = async function(userId, duration = 2) {
  // 1. Create a View record (Fire-and-Forget Strategy)
  // We do NOT await this. It runs in the background.
  View.create({
    video: this._id,
    user: userId,
    duration: duration
  }).catch(err => console.error('Error logging view (background):', err));

  // 2. Atomically increment the total views counter
  // usage of $inc ensures no views are lost during concurrent writes
  return this.constructor.updateOne(
    { _id: this._id },
    { $inc: { views: 1 } }
  );
};

export default mongoose.model('Video', videoSchema);

