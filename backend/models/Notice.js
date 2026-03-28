import mongoose from 'mongoose';

const NoticeSchema = new mongoose.Schema({
  userId: {
    type: String, // Google ID
    required: true,
    index: true
  },
  title: {
    type: String,
    required: true
  },
  type: {
    type: String,
    enum: ['notice', 'warning', 'info'],
    default: 'notice'
  },
  firstSeenAt: {
    type: Date,
    default: null
  },
  createdAt: {
    type: Date,
    default: Date.now
  }
}, {
  timestamps: true
});

// Helper to check if notice is expired (1 hour after seen)
NoticeSchema.methods.isExpired = function() {
  if (!this.firstSeenAt) return false;
  const hourInMs = 60 * 60 * 1000;
  return (Date.now() - this.firstSeenAt.getTime()) > hourInMs;
};

export default mongoose.models.Notice || mongoose.model('Notice', NoticeSchema);
