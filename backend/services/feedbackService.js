import Feedback from '../models/Feedback.js';
import User from '../models/User.js';
import Video from '../models/Video.js';

class FeedbackService {
  /**
   * Create new feedback
   */
  async createFeedback(feedbackData) {
    try {
      // Validate user exists
      const user = await User.findById(feedbackData.user);
      if (!user) {
        throw new Error('User not found');
      }

      // Validate related video if provided
      if (feedbackData.relatedVideo) {
        const video = await Video.findById(feedbackData.relatedVideo);
        if (!video) {
          throw new Error('Related video not found');
        }
      }

      // Auto-determine priority based on rating and type
      if (!feedbackData.priority) {
        feedbackData.priority = this.determinePriority(feedbackData.rating, feedbackData.type);
      }

      const feedback = new Feedback(feedbackData);
      await feedback.save();

      // Populate related data for response
      await feedback.populate([
        { path: 'user', select: 'name email profilePic' },
        { path: 'relatedVideo', select: 'title thumbnail' },
        { path: 'relatedUser', select: 'name profilePic' }
      ]);

      return feedback;
    } catch (error) {
      throw new Error(`Failed to create feedback: ${error.message}`);
    }
  }

  /**
   * Get feedback by ID
   */
  async getFeedbackById(feedbackId) {
    try {
      const feedback = await Feedback.findById(feedbackId)
        .populate('user', 'name email profilePic')
        .populate('relatedVideo', 'title thumbnail')
        .populate('relatedUser', 'name profilePic')
        .populate('assignedTo', 'name email');

      if (!feedback) {
        throw new Error('Feedback not found');
      }

      return feedback;
    } catch (error) {
      throw new Error(`Failed to get feedback: ${error.message}`);
    }
  }

  /**
   * Get feedback list with filters and pagination
   */
  async getFeedbackList(filters = {}, pagination = {}) {
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
        category,
        priority,
        user,
        dateFrom,
        dateTo
      } = filters;

      // Build query
      const query = {};
      
      if (status) query.status = status;
      if (type) query.type = type;
      if (category) query.category = category;
      if (priority) query.priority = priority;
      if (user) query.user = user;
      
      if (dateFrom || dateTo) {
        query.createdAt = {};
        if (dateFrom) query.createdAt.$gte = new Date(dateFrom);
        if (dateTo) query.createdAt.$lte = new Date(dateTo);
      }

      // Execute query with pagination
      const skip = (page - 1) * limit;
      const sortOptions = {};
      sortOptions[sortBy] = sortOrder === 'desc' ? -1 : 1;

      const [feedback, total] = await Promise.all([
        Feedback.find(query)
          .populate('user', 'name email profilePic')
          .populate('relatedVideo', 'title thumbnail')
          .populate('assignedTo', 'name email')
          .sort(sortOptions)
          .skip(skip)
          .limit(limit),
        Feedback.countDocuments(query)
      ]);

      return {
        feedback,
        pagination: {
          page,
          limit,
          total,
          pages: Math.ceil(total / limit)
        }
      };
    } catch (error) {
      throw new Error(`Failed to get feedback list: ${error.message}`);
    }
  }

  /**
   * Update feedback status
   */
  async updateFeedbackStatus(feedbackId, status, adminNotes = null, assignedTo = null) {
    try {
      const feedback = await Feedback.findById(feedbackId);
      if (!feedback) {
        throw new Error('Feedback not found');
      }

      feedback.status = status;
      if (adminNotes) feedback.adminNotes = adminNotes;
      if (assignedTo) feedback.assignedTo = assignedTo;

      if (status === 'resolved') {
        feedback.resolvedAt = new Date();
      } else if (status === 'closed') {
        feedback.closedAt = new Date();
      }

      await feedback.save();
      return feedback;
    } catch (error) {
      throw new Error(`Failed to update feedback status: ${error.message}`);
    }
  }

  /**
   * Get feedback statistics
   */
  async getFeedbackStats() {
    try {
      const stats = await Feedback.getFeedbackStats();
      
      // Get additional stats by type and category
      const [typeStats, categoryStats] = await Promise.all([
        Feedback.aggregate([
          { $group: { _id: '$type', count: { $sum: 1 } } },
          { $sort: { count: -1 } }
        ]),
        Feedback.aggregate([
          { $group: { _id: '$category', count: { $sum: 1 } } },
          { $sort: { count: -1 } }
        ])
      ]);

      return {
        ...stats,
        byType: typeStats,
        byCategory: categoryStats
      };
    } catch (error) {
      throw new Error(`Failed to get feedback stats: ${error.message}`);
    }
  }

  /**
   * Get user's feedback history
   */
  async getUserFeedback(userId, limit = 10) {
    try {
      const feedback = await Feedback.find({ user: userId })
        .populate('relatedVideo', 'title thumbnail')
        .sort({ createdAt: -1 })
        .limit(limit);

      return feedback;
    } catch (error) {
      throw new Error(`Failed to get user feedback: ${error.message}`);
    }
  }

  /**
   * Delete feedback (admin only)
   */
  async deleteFeedback(feedbackId) {
    try {
      const feedback = await Feedback.findByIdAndDelete(feedbackId);
      if (!feedback) {
        throw new Error('Feedback not found');
      }
      return feedback;
    } catch (error) {
      throw new Error(`Failed to delete feedback: ${error.message}`);
    }
  }

  /**
   * Determine priority based on rating and type
   */
  determinePriority(rating, type) {
    // Critical issues get high priority
    if (type === 'bug_report' && rating <= 2) {
      return 'high';
    }
    
    // Feature requests with low rating get medium priority
    if (type === 'feature_request' && rating <= 2) {
      return 'medium';
    }
    
    // General feedback with high rating gets low priority
    if (type === 'general_feedback' && rating >= 4) {
      return 'low';
    }
    
    // Default to medium
    return 'medium';
  }

  /**
   * Search feedback by text
   */
  async searchFeedback(searchTerm, filters = {}) {
    try {
      const query = {
        $or: [
          { title: { $regex: searchTerm, $options: 'i' } },
          { description: { $regex: searchTerm, $options: 'i' } },
          { tags: { $in: [new RegExp(searchTerm, 'i')] } }
        ]
      };

      // Add additional filters
      if (filters.status) query.status = filters.status;
      if (filters.type) query.type = filters.type;

      const feedback = await Feedback.find(query)
        .populate('user', 'name email profilePic')
        .populate('relatedVideo', 'title thumbnail')
        .sort({ createdAt: -1 })
        .limit(50);

      return feedback;
    } catch (error) {
      throw new Error(`Failed to search feedback: ${error.message}`);
    }
  }
}

export default new FeedbackService();
