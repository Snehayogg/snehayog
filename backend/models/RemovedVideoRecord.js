import mongoose from 'mongoose';

const RemovedVideoRecordSchema = new mongoose.Schema({
  originalVideoId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Video',
    required: true
  },
  uploaderId: {
    type: String, // Google ID
    required: true,
    index: true
  },
  videoName: {
    type: String,
    required: true
  },
  thumbnailUrl: {
    type: String,
    required: true
  },
  reason: {
    type: String,
    required: true
  },
  removedAt: {
    type: Date,
    default: Date.now,
    expires: 259200 // 3 days in seconds (TTL Index)
  }
}, {
  timestamps: true
});

// Build a virtual for expiresAt
RemovedVideoRecordSchema.virtual('expiresAt').get(function() {
  return new Date(this.removedAt.getTime() + (3 * 24 * 60 * 60 * 1000));
});

export default mongoose.models.RemovedVideoRecord || mongoose.model('RemovedVideoRecord', RemovedVideoRecordSchema);
