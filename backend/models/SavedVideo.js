import mongoose from 'mongoose';

const SavedVideoSchema = new mongoose.Schema({
  user: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true,
    index: true
  },
  video: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Video',
    required: true,
    index: true
  }
}, {
  timestamps: true
});

// Unique index to prevent duplicate saves
SavedVideoSchema.index({ user: 1, video: 1 }, { unique: true });

export default mongoose.models.SavedVideo || mongoose.model('SavedVideo', SavedVideoSchema);
