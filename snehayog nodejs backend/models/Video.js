const mongoose = require('mongoose');

const videoSchema = new mongoose.Schema({
  videoName: {
    type: String,
    required: true
  },
  description: {
    type: String,
    required: true
  },
  videoUrl: {
    type: String,
    required: true
  },
  originalVideoUrl: {
    type: String,
    required: true
  },
  thumbnailUrl: {
    type: String,
    required: true
  },
  views: {
    type: Number,
    default: 0
  },
  likedBy: [{
    type: String  // Store user IDs as strings
  }],
  uploader: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  uploadedAt: {
    type: Date,
    default: Date.now
  },
  videoType: {
    type: String,
    enum: ['reel', 'yog'],
    default: 'reel'
  },
  duration: {
    type: Number,
    default: 0
  },
  aspectRatio: {
    type: Number,
    default: 9/16 // Default for vertical videos
  },
  comments: [{
    user: {
      type: mongoose.Schema.Types.ObjectId,
      ref: 'User',
      required: true
    },
    text: {
      type: String,
      required: true
    },
    createdAt: {
      type: Date,
      default: Date.now
    }
  }],
  shares: {
    type: Number,
    default: 0
  }
});

// Add indexes for better query performance
videoSchema.index({ uploader: 1, uploadedAt: -1 });
videoSchema.index({ videoType: 1, uploadedAt: -1 });
videoSchema.index({ likedBy: 1 });

// Virtual for likes count
videoSchema.virtual('likes').get(function() {
  return this.likedBy.length;
});

// Ensure virtuals are included in JSON
videoSchema.set('toJSON', { virtuals: true });
videoSchema.set('toObject', { virtuals: true });

module.exports = mongoose.model('Video', videoSchema);
