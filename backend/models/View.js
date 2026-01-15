import mongoose from 'mongoose';

const viewSchema = new mongoose.Schema({
  video: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Video',
    required: true,
    index: true // Faster lookup by video
  },
  user: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true,
    index: true // Faster lookup by user
  },
  viewedAt: {
    type: Date,
    default: Date.now
  },
  duration: {
    type: Number,
    default: 0 
  },
  // Optional: Track if this view counted towards monetization or unique view logic
  isCounted: {
    type: Boolean,
    default: true
  }
}, {
  timestamps: true
});

// Compound index to quickly check "Has User X seen Video Y?"
viewSchema.index({ video: 1, user: 1 }, { background: true });

// TTL Index: Optional, if we want to auto-delete views after 1 year to save space?
// For now, let's keep them forever as per "Lifetime Views" logic.

export default mongoose.model('View', viewSchema);
