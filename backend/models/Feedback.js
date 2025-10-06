import mongoose from 'mongoose';

const FeedbackSchema = new mongoose.Schema({
  user: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  type: {
    type: String,
    enum: ['bug_report', 'feature_request', 'general_feedback', 'user_experience', 'content_issue'],
    required: true
  },
  category: {
    type: String,
    enum: ['video_playback', 'upload_issues', 'ui_ux', 'performance', 'monetization', 'social_features', 'other'],
    required: true
  },
  title: {
    type: String,
    required: true,
    maxlength: 200
  },
  description: {
    type: String,
    required: true,
    maxlength: 2000
  },
  priority: {
    type: String,
    enum: ['low', 'medium', 'high', 'critical'],
    default: 'medium'
  },
  status: {
    type: String,
    enum: ['open', 'in_progress', 'resolved', 'closed', 'duplicate'],
    default: 'open'
  },
  rating: {
    type: Number,
    min: 1,
    max: 5,
    required: true
  },
  deviceInfo: {
    platform: String,
    version: String,
    model: String,
    appVersion: String
  },
  screenshots: [{
    type: String, // URLs to uploaded screenshots
    caption: String
  }],
  relatedVideo: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Video'
  },
  relatedUser: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User'
  },
  tags: [{
    type: String,
    maxlength: 50
  }],
  adminNotes: {
    type: String,
    maxlength: 1000
  },
  assignedTo: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User'
  },
  resolution: {
    type: String,
    maxlength: 1000
  },
  resolvedAt: Date,
  closedAt: Date
}, {
  timestamps: true
});

// Indexes for better query performance
FeedbackSchema.index({ user: 1, createdAt: -1 });
FeedbackSchema.index({ status: 1, priority: 1 });
FeedbackSchema.index({ type: 1, category: 1 });
FeedbackSchema.index({ createdAt: -1 });

// Virtual for formatted creation date
FeedbackSchema.virtual('createdAtFormatted').get(function() {
  return this.createdAt.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric'
  });
});

// Method to update status
FeedbackSchema.methods.updateStatus = function(newStatus, adminNotes = null) {
  this.status = newStatus;
  
  if (adminNotes) {
    this.adminNotes = adminNotes;
  }
  
  if (newStatus === 'resolved') {
    this.resolvedAt = new Date();
  } else if (newStatus === 'closed') {
    this.closedAt = new Date();
  }
  
  return this.save();
};

// Static method to get feedback statistics
FeedbackSchema.statics.getFeedbackStats = async function() {
  const stats = await this.aggregate([
    {
      $group: {
        _id: null,
        total: { $sum: 1 },
        open: { $sum: { $cond: [{ $eq: ['$status', 'open'] }, 1, 0] } },
        inProgress: { $sum: { $cond: [{ $eq: ['$status', 'in_progress'] }, 1, 0] } },
        resolved: { $sum: { $cond: [{ $eq: ['$status', 'resolved'] }, 1, 0] } },
        averageRating: { $avg: '$rating' }
      }
    }
  ]);
  
  return stats[0] || { total: 0, open: 0, inProgress: 0, resolved: 0, averageRating: 0 };
};

export default mongoose.models.Feedback || mongoose.model('Feedback', FeedbackSchema);
