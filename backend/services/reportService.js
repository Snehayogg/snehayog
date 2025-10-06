import Report from '../models/Report.js';
import User from '../models/User.js';
import Video from '../models/Video.js';
import Comment from '../models/Comment.js';

class ReportService {
  /**
   * Create new report
   */
  async createReport(reportData) {
    try {
      // Validate reporter exists
      const reporter = await User.findById(reportData.reporter);
      if (!reporter) {
        throw new Error('Reporter not found');
      }

      // Validate reported entities
      if (reportData.reportedUser) {
        const reportedUser = await User.findById(reportData.reportedUser);
        if (!reportedUser) {
          throw new Error('Reported user not found');
        }
      }

      if (reportData.reportedVideo) {
        const reportedVideo = await Video.findById(reportData.reportedVideo);
        if (!reportedVideo) {
          throw new Error('Reported video not found');
        }
      }

      if (reportData.reportedComment) {
        const reportedComment = await Comment.findById(reportData.reportedComment);
        if (!reportedComment) {
          throw new Error('Reported comment not found');
        }
      }

      // Check for repeat reports
      const isRepeat = await Report.checkRepeatReport(
        reportData.reporter,
        reportData.reportedUser,
        reportData.reportedVideo,
        reportData.type
      );

      if (isRepeat) {
        throw new Error('You have already reported this content recently');
      }

      // Auto-determine priority and severity
      if (!reportData.priority) {
        reportData.priority = this.determinePriority(reportData.type);
      }

      if (!reportData.severity) {
        reportData.severity = this.determineSeverity(reportData.type);
      }

      reportData.isRepeatReport = false;

      const report = new Report(reportData);
      await report.save();

      // Populate related data for response
      await report.populate([
        { path: 'reporter', select: 'name email profilePic' },
        { path: 'reportedUser', select: 'name email profilePic' },
        { path: 'reportedVideo', select: 'title thumbnail' },
        { path: 'reportedComment', select: 'content' }
      ]);

      return report;
    } catch (error) {
      throw new Error(`Failed to create report: ${error.message}`);
    }
  }

  /**
   * Get report by ID
   */
  async getReportById(reportId) {
    try {
      const report = await Report.findById(reportId)
        .populate('reporter', 'name email profilePic')
        .populate('reportedUser', 'name email profilePic')
        .populate('reportedVideo', 'title thumbnail description')
        .populate('reportedComment', 'content author')
        .populate('assignedModerator', 'name email')
        .populate('relatedReports');

      if (!report) {
        throw new Error('Report not found');
      }

      return report;
    } catch (error) {
      throw new Error(`Failed to get report: ${error.message}`);
    }
  }

  /**
   * Get reports list with filters and pagination
   */
  async getReportsList(filters = {}, pagination = {}) {
    try {
      const {
        page = 1,
        limit = 10,
        sortBy = 'createdAt',
        sortOrder = 'desc'
      } = pagination;

      const {
        status,
        type,
        priority,
        severity,
        assignedModerator,
        dateFrom,
        dateTo
      } = filters;

      // Build query
      const query = {};
      
      if (status) query.status = status;
      if (type) query.type = type;
      if (priority) query.priority = priority;
      if (severity) query.severity = severity;
      if (assignedModerator) query.assignedModerator = assignedModerator;
      
      if (dateFrom || dateTo) {
        query.createdAt = {};
        if (dateFrom) query.createdAt.$gte = new Date(dateFrom);
        if (dateTo) query.createdAt.$lte = new Date(dateTo);
      }

      // Execute query with pagination
      const skip = (page - 1) * limit;
      const sortOptions = {};
      sortOptions[sortBy] = sortOrder === 'desc' ? -1 : 1;

      const [reports, total] = await Promise.all([
        Report.find(query)
          .populate('reporter', 'name email profilePic')
          .populate('reportedUser', 'name email profilePic')
          .populate('reportedVideo', 'title thumbnail')
          .populate('assignedModerator', 'name email')
          .sort(sortOptions)
          .skip(skip)
          .limit(limit),
        Report.countDocuments(query)
      ]);

      return {
        reports,
        pagination: {
          page,
          limit,
          total,
          pages: Math.ceil(total / limit)
        }
      };
    } catch (error) {
      throw new Error(`Failed to get reports list: ${error.message}`);
    }
  }

  /**
   * Update report status
   */
  async updateReportStatus(reportId, status, moderatorNotes = null, actionTaken = null) {
    try {
      const report = await Report.findById(reportId);
      if (!report) {
        throw new Error('Report not found');
      }

      report.status = status;
      if (moderatorNotes) report.moderatorNotes = moderatorNotes;
      if (actionTaken) report.actionTaken = actionTaken;

      if (status === 'under_review') {
        report.reviewedAt = new Date();
      } else if (status === 'resolved') {
        report.resolvedAt = new Date();
      }

      await report.save();
      return report;
    } catch (error) {
      throw new Error(`Failed to update report status: ${error.message}`);
    }
  }

  /**
   * Assign report to moderator
   */
  async assignToModerator(reportId, moderatorId) {
    try {
      const report = await Report.findById(reportId);
      if (!report) {
        throw new Error('Report not found');
      }

      const moderator = await User.findById(moderatorId);
      if (!moderator) {
        throw new Error('Moderator not found');
      }

      report.assignedModerator = moderatorId;
      report.status = 'under_review';
      report.reviewedAt = new Date();

      await report.save();
      return report;
    } catch (error) {
      throw new Error(`Failed to assign report to moderator: ${error.message}`);
    }
  }

  /**
   * Get report statistics
   */
  async getReportStats() {
    try {
      const stats = await Report.getReportStats();
      
      // Get additional stats
      const [typeStats, priorityStats, severityStats] = await Promise.all([
        Report.getReportsByType(),
        Report.aggregate([
          { $group: { _id: '$priority', count: { $sum: 1 } } },
          { $sort: { count: -1 } }
        ]),
        Report.aggregate([
          { $group: { _id: '$severity', count: { $sum: 1 } } },
          { $sort: { count: -1 } }
        ])
      ]);

      return {
        ...stats,
        byType: typeStats,
        byPriority: priorityStats,
        bySeverity: severityStats
      };
    } catch (error) {
      throw new Error(`Failed to get report stats: ${error.message}`);
    }
  }

  /**
   * Get reports by user
   */
  async getReportsByUser(userId, limit = 10) {
    try {
      const reports = await Report.find({ 
        $or: [
          { reporter: userId },
          { reportedUser: userId }
        ]
      })
        .populate('reporter', 'name email profilePic')
        .populate('reportedUser', 'name email profilePic')
        .populate('reportedVideo', 'title thumbnail')
        .sort({ createdAt: -1 })
        .limit(limit);

      return reports;
    } catch (error) {
      throw new Error(`Failed to get reports by user: ${error.message}`);
    }
  }

  /**
   * Get reports by video
   */
  async getReportsByVideo(videoId, limit = 10) {
    try {
      const reports = await Report.find({ reportedVideo: videoId })
        .populate('reporter', 'name email profilePic')
        .sort({ createdAt: -1 })
        .limit(limit);

      return reports;
    } catch (error) {
      throw new Error(`Failed to get reports by video: ${error.message}`);
    }
  }

  /**
   * Delete report (admin only)
   */
  async deleteReport(reportId) {
    try {
      const report = await Report.findByIdAndDelete(reportId);
      if (!report) {
        throw new Error('Report not found');
      }
      return report;
    } catch (error) {
      throw new Error(`Failed to delete report: ${error.message}`);
    }
  }

  /**
   * Determine priority based on report type
   */
  determinePriority(type) {
    const highPriorityTypes = ['hate_speech', 'violence', 'nudity', 'underage_user', 'scam'];
    const urgentTypes = ['harassment', 'copyright_violation'];
    
    if (urgentTypes.includes(type)) {
      return 'urgent';
    } else if (highPriorityTypes.includes(type)) {
      return 'high';
    } else if (type === 'spam') {
      return 'low';
    }
    
    return 'medium';
  }

  /**
   * Determine severity based on report type
   */
  determineSeverity(type) {
    const criticalTypes = ['violence', 'nudity', 'underage_user'];
    const severeTypes = ['hate_speech', 'harassment', 'scam'];
    const moderateTypes = ['copyright_violation', 'inappropriate_content'];
    
    if (criticalTypes.includes(type)) {
      return 'critical';
    } else if (severeTypes.includes(type)) {
      return 'severe';
    } else if (moderateTypes.includes(type)) {
      return 'moderate';
    }
    
    return 'minor';
  }

  /**
   * Find related reports
   */
  async findRelatedReports(reportId) {
    try {
      const currentReport = await Report.findById(reportId);
      if (!currentReport) {
        throw new Error('Report not found');
      }

      const query = {
        _id: { $ne: reportId },
        type: currentReport.type,
        status: { $in: ['pending', 'under_review'] }
      };

      // Find reports for the same user or video
      if (currentReport.reportedUser) {
        query.reportedUser = currentReport.reportedUser;
      } else if (currentReport.reportedVideo) {
        query.reportedVideo = currentReport.reportedVideo;
      }

      const relatedReports = await Report.find(query)
        .populate('reporter', 'name email profilePic')
        .sort({ createdAt: -1 })
        .limit(5);

      return relatedReports;
    } catch (error) {
      throw new Error(`Failed to find related reports: ${error.message}`);
    }
  }

  /**
   * Escalate report
   */
  async escalateReport(reportId, escalationReason) {
    try {
      const report = await Report.findById(reportId);
      if (!report) {
        throw new Error('Report not found');
      }

      report.status = 'escalated';
      report.priority = 'urgent';
      report.moderatorNotes = `${report.moderatorNotes || ''}\n\nEscalated: ${escalationReason}`;

      await report.save();
      return report;
    } catch (error) {
      throw new Error(`Failed to escalate report: ${error.message}`);
    }
  }
}

export default new ReportService();
