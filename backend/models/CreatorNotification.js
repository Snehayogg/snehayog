import mongoose from 'mongoose';

const CreatorNotificationSchema = new mongoose.Schema({
  creatorId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true,
    index: true
  },
  message: {
    type: String,
    required: true,
    trim: true,
    maxlength: 150
  },
  title: {
    type: String,
    default: 'New Alert from Creator'
  },
  targetUrl: {
    type: String,
    required: false // Optional link to a video or profile
  },
  sentCount: {
    type: Number,
    default: 0
  },
  clickCount: {
    type: Number,
    default: 0
  },
  revenueGenerated: {
    type: Number,
    default: 0
  },
  sentAt: {
    type: Date,
    default: Date.now
  }
}, {
  timestamps: true
});

export default mongoose.models.CreatorNotification || mongoose.model('CreatorNotification', CreatorNotificationSchema);
