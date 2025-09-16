import mongoose from 'mongoose';

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
    required: true
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
    quality: String, // preload, low, medium, high
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
  }
}, {
  timestamps: true
});

// **NEW: Index for faster queries**
videoSchema.index({ uploader: 1, uploadedAt: -1 });
videoSchema.index({ processingStatus: 1 });
videoSchema.index({ 'qualitiesGenerated.quality': 1 });

// **NEW: Virtual field to check if video has multiple qualities**
videoSchema.virtual('hasMultipleQualities').get(function() {
  return !!(this.preloadQualityUrl || this.lowQualityUrl || 
           this.mediumQualityUrl || this.highQualityUrl);
});

// **NEW: Method to get optimal quality URL based on network speed**
videoSchema.methods.getOptimalQualityUrl = function(networkSpeedMbps) {
  if (networkSpeedMbps > 10) {
    return this.highQualityUrl || this.videoUrl; // 1080p for fast networks
  } else if (networkSpeedMbps > 5) {
    return this.mediumQualityUrl || this.videoUrl; // 720p for medium networks
  } else {
    return this.lowQualityUrl || this.videoUrl; // 480p for slow networks
  }
};

// **NEW: Method to get preload quality URL for fast loading**
videoSchema.methods.getPreloadQualityUrl = function() {
  return this.preloadQualityUrl || this.lowQualityUrl || this.videoUrl;
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

export default mongoose.model('Video', videoSchema);

