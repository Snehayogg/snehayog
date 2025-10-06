import feedbackService from '../services/feedbackService.js';
import { validationResult } from 'express-validator';

/**
 * Create new feedback
 */
export const createFeedback = async (req, res) => {
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

    // Apply sensible defaults so frontend can send only rating + description
    const feedbackData = {
      user: req.user.id, // from JWT
      type: req.body.type || 'general_feedback',
      category: req.body.category || 'other',
      title:
        req.body.title && req.body.title.trim().length > 0
          ? req.body.title.trim()
          : (req.body.description || '').trim().split('\n')[0].slice(0, 60),
      description: (req.body.description || '').trim(),
      rating: req.body.rating,
      priority: req.body.priority, // optional
      relatedVideo: req.body.relatedVideo,
      relatedUser: req.body.relatedUser,
      deviceInfo: req.body.deviceInfo,
      tags: Array.isArray(req.body.tags) ? req.body.tags : []
    };

    const feedback = await feedbackService.createFeedback(feedbackData);

    res.status(201).json({
      success: true,
      message: 'Feedback submitted successfully',
      data: feedback
    });
  } catch (error) {
    console.error('Create feedback error:', error);
    res.status(400).json({
      success: false,
      message: error.message
    });
  }
};

/**
 * Get feedback by ID
 */
export const getFeedbackById = async (req, res) => {
  try {
    const { id } = req.params;
    const feedback = await feedbackService.getFeedbackById(id);

    res.json({
      success: true,
      data: feedback
    });
  } catch (error) {
    console.error('Get feedback error:', error);
    res.status(404).json({
      success: false,
      message: error.message
    });
  }
};

/**
 * Get feedback list with filters
 */
export const getFeedbackList = async (req, res) => {
  try {
    const filters = {
      status: req.query.status,
      type: req.query.type,
      category: req.query.category,
      priority: req.query.priority,
      user: req.query.user,
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

    const result = await feedbackService.getFeedbackList(filters, pagination);

    res.json({
      success: true,
      data: result.feedback,
      pagination: result.pagination
    });
  } catch (error) {
    console.error('Get feedback list error:', error);
    res.status(400).json({
      success: false,
      message: error.message
    });
  }
};

/**
 * Update feedback status (Admin only)
 */
export const updateFeedbackStatus = async (req, res) => {
  try {
    const { id } = req.params;
    const { status, adminNotes, assignedTo } = req.body;

    const feedback = await feedbackService.updateFeedbackStatus(id, status, adminNotes, assignedTo);

    res.json({
      success: true,
      message: 'Feedback status updated successfully',
      data: feedback
    });
  } catch (error) {
    console.error('Update feedback status error:', error);
    res.status(400).json({
      success: false,
      message: error.message
    });
  }
};

/**
 * Get feedback statistics (Admin only)
 */
export const getFeedbackStats = async (req, res) => {
  try {
    const stats = await feedbackService.getFeedbackStats();

    res.json({
      success: true,
      data: stats
    });
  } catch (error) {
    console.error('Get feedback stats error:', error);
    res.status(400).json({
      success: false,
      message: error.message
    });
  }
};

/**
 * Get user's feedback history
 */
export const getUserFeedback = async (req, res) => {
  try {
    const { userId } = req.params;
    const limit = parseInt(req.query.limit) || 10;

    // Check if user is requesting their own feedback or is admin
    if (userId !== req.user.id && !req.user.isAdmin) {
      return res.status(403).json({
        success: false,
        message: 'Access denied'
      });
    }

    const feedback = await feedbackService.getUserFeedback(userId, limit);

    res.json({
      success: true,
      data: feedback
    });
  } catch (error) {
    console.error('Get user feedback error:', error);
    res.status(400).json({
      success: false,
      message: error.message
    });
  }
};

/**
 * Search feedback
 */
export const searchFeedback = async (req, res) => {
  try {
    const { q } = req.query;
    
    if (!q || q.trim().length < 2) {
      return res.status(400).json({
        success: false,
        message: 'Search query must be at least 2 characters long'
      });
    }

    const filters = {
      status: req.query.status,
      type: req.query.type
    };

    // Remove undefined values
    Object.keys(filters).forEach(key => {
      if (filters[key] === undefined) {
        delete filters[key];
      }
    });

    const feedback = await feedbackService.searchFeedback(q.trim(), filters);

    res.json({
      success: true,
      data: feedback
    });
  } catch (error) {
    console.error('Search feedback error:', error);
    res.status(400).json({
      success: false,
      message: error.message
    });
  }
};

/**
 * Delete feedback (Admin only)
 */
export const deleteFeedback = async (req, res) => {
  try {
    const { id } = req.params;
    const feedback = await feedbackService.deleteFeedback(id);

    res.json({
      success: true,
      message: 'Feedback deleted successfully',
      data: feedback
    });
  } catch (error) {
    console.error('Delete feedback error:', error);
    res.status(400).json({
      success: false,
      message: error.message
    });
  }
};
