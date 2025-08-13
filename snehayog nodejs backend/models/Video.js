import mongoose from 'mongoose';

const commentSchema = new mongoose.Schema({
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
});

const videoSchema = new mongoose.Schema({
  videoName: {
    type: String,
    required: true
  },
  videoUrl: {
    type: String,
    required: true
  },
  thumbnailUrl: {
    type: String,
    required: true
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
  description: {
    type: String,
    required: true
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
  likedBy: [{
    type: String
  }],
  videoType: {
    type: String,
    default: 'reel'
  },
  aspectRatio: {
    type: Number,
    default: 9/16
  },
  duration: {
    type: Number,
    default: 0
  },
  comments: [commentSchema],
  link: {
    type: String,
    default: null
  }
}, {
  timestamps: true
});

// Add indexes for better performance
videoSchema.index({ createdAt: -1 }); // For sorting by upload date
videoSchema.index({ uploader: 1 }); // For finding videos by uploader
videoSchema.index({ videoType: 1 }); // For filtering by video type
videoSchema.index({ likes: -1 }); // For sorting by popularity

// Add compound index for common queries
videoSchema.index({ uploader: 1, createdAt: -1 });

export default mongoose.model('Video', videoSchema);

