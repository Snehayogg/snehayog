import reportService from '../services/reportService.js';
import { validationResult } from 'express-validator';

/**
 * Create new report
 */
export const createReport = async (req, res) => {
  try {
    // Check for validation errors
    const errors = validationResult(req);
    if (!errors.isEmpty()) {
      return res.status(400).json({
        success: false,
        message: 'Validation failed',
        errors: errors.array()
      });
    }

    const reportData = {
      ...req.body,
      reporter: req.user.id // Get user ID from JWT token
    };

    const report = await reportService.createReport(reportData);

    res.status(201).json({
      success: true,
      message: 'Report submitted successfully',
      data: report
    });
  } catch (error) {
    console.error('Create report error:', error);
    res.status(400).json({
      success: false,
      message: error.message
    });
  }
};

/**
 * Get report by ID
 */
export const getReportById = async (req, res) => {
  try {
    const { id } = req.params;
    const report = await reportService.getReportById(id);

    // Check if user has permission to view this report
    if (report.reporter._id.toString() !== req.user.id && !req.user.isAdmin) {
      return res.status(403).json({
        success: false,
        message: 'Access denied'
      });
    }

    res.json({
      success: true,
      data: report
    });
  } catch (error) {
    console.error('Get report error:', error);
    res.status(404).json({
      success: false,
      message: error.message
    });
  }
};

/**
 * Get reports list with filters (Admin/Moderator only)
 */
export const getReportsList = async (req, res) => {
  try {
    const filters = {
      status: req.query.status,
      type: req.query.type,
      priority: req.query.priority,
      severity: req.query.severity,
      assignedModerator: req.query.assignedModerator,
      dateFrom: req.query.dateFrom,
      dateTo: req.query.dateTo
    };

    const pagination = {
      page: parseInt(req.query.page) || 1,
      limit: parseInt(req.query.limit) || 10,
      sortBy: req.query.sortBy || 'createdAt',
      sortOrder: req.query.sortOrder || 'desc'
    };

    // Remove undefined values
    Object.keys(filters).forEach(key => {
      if (filters[key] === undefined) {
        delete filters[key];
      }
    });

    const result = await reportService.getReportsList(filters, pagination);

    res.json({
      success: true,
      data: result.reports,
      pagination: result.pagination
    });
  } catch (error) {
    console.error('Get reports list error:', error);
    res.status(400).json({
      success: false,
      message: error.message
    });
  }
};

/**
 * Update report status (Admin/Moderator only)
 */
export const updateReportStatus = async (req, res) => {
  try {
    const { id } = req.params;
    const { status, moderatorNotes, actionTaken } = req.body;

    const report = await reportService.updateReportStatus(id, status, moderatorNotes, actionTaken);

    res.json({
      success: true,
      message: 'Report status updated successfully',
      data: report
    });
  } catch (error) {
    console.error('Update report status error:', error);
    res.status(400).json({
      success: false,
      message: error.message
    });
  }
};

/**
 * Assign report to moderator (Admin only)
 */
export const assignToModerator = async (req, res) => {
  try {
    const { id } = req.params;
    const { moderatorId } = req.body;

    const report = await reportService.assignToModerator(id, moderatorId);

    res.json({
      success: true,
      message: 'Report assigned to moderator successfully',
      data: report
    });
  } catch (error) {
    console.error('Assign report error:', error);
    res.status(400).json({
      success: false,
      message: error.message
    });
  }
};

/**
 * Get report statistics (Admin only)
 */
export const getReportStats = async (req, res) => {
  try {
    const stats = await reportService.getReportStats();

    res.json({
      success: true,
      data: stats
    });
  } catch (error) {
    console.error('Get report stats error:', error);
    res.status(400).json({
      success: false,
      message: error.message
    });
  }
};

/**
 * Get reports by user
 */
export const getReportsByUser = async (req, res) => {
  try {
    const { userId } = req.params;
    const limit = parseInt(req.query.limit) || 10;

    // Check if user is requesting their own reports or is admin
    if (userId !== req.user.id && !req.user.isAdmin) {
      return res.status(403).json({
        success: false,
        message: 'Access denied'
      });
    }

    const reports = await reportService.getReportsByUser(userId, limit);

    res.json({
      success: true,
      data: reports
    });
  } catch (error) {
    console.error('Get reports by user error:', error);
    res.status(400).json({
      success: false,
      message: error.message
    });
  }
};

/**
 * Get reports by video (Admin/Moderator only)
 */
export const getReportsByVideo = async (req, res) => {
  try {
    const { videoId } = req.params;
    const limit = parseInt(req.query.limit) || 10;

    const reports = await reportService.getReportsByVideo(videoId, limit);

    res.json({
      success: true,
      data: reports
    });
  } catch (error) {
    console.error('Get reports by video error:', error);
    res.status(400).json({
      success: false,
      message: error.message
    });
  }
};

/**
 * Find related reports (Admin/Moderator only)
 */
export const findRelatedReports = async (req, res) => {
  try {
    const { id } = req.params;
    const relatedReports = await reportService.findRelatedReports(id);

    res.json({
      success: true,
      data: relatedReports
    });
  } catch (error) {
    console.error('Find related reports error:', error);
    res.status(400).json({
      success: false,
      message: error.message
    });
  }
};

/**
 * Escalate report (Moderator/Admin only)
 */
export const escalateReport = async (req, res) => {
  try {
    const { id } = req.params;
    const { escalationReason } = req.body;

    if (!escalationReason || escalationReason.trim().length < 10) {
      return res.status(400).json({
        success: false,
        message: 'Escalation reason must be at least 10 characters long'
      });
    }

    const report = await reportService.escalateReport(id, escalationReason.trim());

    res.json({
      success: true,
      message: 'Report escalated successfully',
      data: report
    });
  } catch (error) {
    console.error('Escalate report error:', error);
    res.status(400).json({
      success: false,
      message: error.message
    });
  }
};

/**
 * Delete report (Admin only)
 */
export const deleteReport = async (req, res) => {
  try {
    const { id } = req.params;
    const report = await reportService.deleteReport(id);

    res.json({
      success: true,
      message: 'Report deleted successfully',
      data: report
    });
  } catch (error) {
    console.error('Delete report error:', error);
    res.status(400).json({
      success: false,
      message: error.message
    });
  }
};
