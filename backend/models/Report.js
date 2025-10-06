import mongoose from 'mongoose';

const ReportSchema = new mongoose.Schema({
  reporter: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  reportedUser: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User'
  },
  reportedVideo: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Video'
  },
  reportedComment: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Comment'
  },
  type: {
    type: String,
    enum: [
      'spam', 'harassment', 'hate_speech', 'inappropriate_content', 
      'violence', 'nudity', 'copyright_violation', 'fake_account', 
      'scam', 'underage_user', 'other'
    ],
    required: true
  },
  reason: {
    type: String,
    required: true,
    maxlength: 500
  },
  description: {
    type: String,
    required: true,
    maxlength: 1000
  },
  priority: {
    type: String,
    enum: ['low', 'medium', 'high', 'urgent'],
    default: 'medium'
  },
  status: {
    type: String,
    enum: ['pending', 'under_review', 'resolved', 'dismissed', 'escalated'],
    default: 'pending'
  },
  severity: {
    type: String,
    enum: ['minor', 'moderate', 'severe', 'critical'],
    default: 'moderate'
  },
  evidence: [{
    type: String, // URLs to screenshots or other evidence
    description: String
  }],
  assignedModerator: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User'
  },
  moderatorNotes: {
    type: String,
    maxlength: 1000
  },
  actionTaken: {
    type: String,
    enum: [
      'no_action', 'warning_issued', 'content_removed', 'user_suspended', 
      'user_banned', 'account_restricted', 'content_hidden', 'escalated_to_legal'
    ]
  },
  resolution: {
    type: String,
    maxlength: 1000
  },
  reportedAt: {
    type: Date,
    default: Date.now
  },
  reviewedAt: Date,
  resolvedAt: Date,
  // Track if this is a repeat report
  isRepeatReport: {
    type: Boolean,
    default: false
  },
  relatedReports: [{
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Report'
  }]
}, {
  timestamps: true
});

// Indexes for better query performance
ReportSchema.index({ reporter: 1, createdAt: -1 });
ReportSchema.index({ reportedUser: 1, status: 1 });
ReportSchema.index({ reportedVideo: 1, status: 1 });
ReportSchema.index({ type: 1, status: 1 });
ReportSchema.index({ priority: 1, status: 1 });
ReportSchema.index({ assignedModerator: 1, status: 1 });
ReportSchema.index({ createdAt: -1 });

// Virtual for formatted creation date
ReportSchema.virtual('createdAtFormatted').get(function() {
  return this.createdAt.toLocaleDateString('en-US', {
    year: 'numeric',
    month: 'long',
    day: 'numeric'
  });
});

// Method to update status
ReportSchema.methods.updateStatus = function(newStatus, moderatorNotes = null, actionTaken = null) {
  this.status = newStatus;
  
  if (moderatorNotes) {
    this.moderatorNotes = moderatorNotes;
  }
  
  if (actionTaken) {
    this.actionTaken = actionTaken;
  }
  
  if (newStatus === 'under_review') {
    this.reviewedAt = new Date();
  } else if (newStatus === 'resolved') {
    this.resolvedAt = new Date();
  }
  
  return this.save();
};

// Method to assign to moderator
ReportSchema.methods.assignToModerator = function(moderatorId) {
  this.assignedModerator = moderatorId;
  this.status = 'under_review';
  this.reviewedAt = new Date();
  return this.save();
};

// Static method to check for repeat reports
ReportSchema.statics.checkRepeatReport = async function(reporterId, reportedUser, reportedVideo, type) {
  const existingReport = await this.findOne({
    reporter: reporterId,
    type: type,
    status: { $in: ['pending', 'under_review'] },
    $or: [
      { reportedUser: reportedUser },
      { reportedVideo: reportedVideo }
    ],
    createdAt: { $gte: new Date(Date.now() - 24 * 60 * 60 * 1000) } // Last 24 hours
  });
  
  return !!existingReport;
};

// Static method to get report statistics
ReportSchema.statics.getReportStats = async function() {
  const stats = await this.aggregate([
    {
      $group: {
        _id: null,
        total: { $sum: 1 },
        pending: { $sum: { $cond: [{ $eq: ['$status', 'pending'] }, 1, 0] } },
        underReview: { $sum: { $cond: [{ $eq: ['$status', 'under_review'] }, 1, 0] } },
        resolved: { $sum: { $cond: [{ $eq: ['$status', 'resolved'] }, 1, 0] } },
        dismissed: { $sum: { $cond: [{ $eq: ['$status', 'dismissed'] }, 1, 0] } }
      }
    }
  ]);
  
  return stats[0] || { total: 0, pending: 0, underReview: 0, resolved: 0, dismissed: 0 };
};

// Static method to get reports by type
ReportSchema.statics.getReportsByType = async function() {
  return await this.aggregate([
    {
      $group: {
        _id: '$type',
        count: { $sum: 1 }
      }
    },
    { $sort: { count: -1 } }
  ]);
};

export default mongoose.models.Report || mongoose.model('Report', ReportSchema);
