import { body, param, query } from 'express-validator';

// Feedback validation rules
export const validateFeedbackCreation = [
  // Keep minimal: only description and rating required
  body('type')
    .optional()
    .isIn(['bug_report', 'feature_request', 'general_feedback', 'user_experience', 'content_issue'])
    .withMessage('Invalid feedback type'),

  body('category')
    .optional()
    .isIn(['video_playback', 'upload_issues', 'ui_ux', 'performance', 'monetization', 'social_features', 'other'])
    .withMessage('Invalid feedback category'),

  body('title')
    .optional()
    .trim()
    .isLength({ min: 1, max: 200 })
    .withMessage('Title must be between 1 and 200 characters'),

  body('description')
    .trim()
    .isLength({ min: 10, max: 2000 })
    .withMessage('Description must be between 10 and 2000 characters'),
  
  body('rating')
    .isInt({ min: 1, max: 5 })
    .withMessage('Rating must be between 1 and 5'),
  
  body('priority')
    .optional()
    .isIn(['low', 'medium', 'high', 'critical'])
    .withMessage('Invalid priority level'),
  
  body('relatedVideo')
    .optional()
    .isMongoId()
    .withMessage('Invalid video ID'),
  
  body('relatedUser')
    .optional()
    .isMongoId()
    .withMessage('Invalid user ID'),
  
  body('deviceInfo.platform')
    .optional()
    .trim()
    .isLength({ max: 50 })
    .withMessage('Platform must be less than 50 characters'),
  
  body('deviceInfo.version')
    .optional()
    .trim()
    .isLength({ max: 50 })
    .withMessage('Version must be less than 50 characters'),
  
  body('deviceInfo.model')
    .optional()
    .trim()
    .isLength({ max: 100 })
    .withMessage('Model must be less than 100 characters'),
  
  body('deviceInfo.appVersion')
    .optional()
    .trim()
    .isLength({ max: 50 })
    .withMessage('App version must be less than 50 characters'),
  
  body('tags')
    .optional()
    .isArray()
    .withMessage('Tags must be an array'),
  
  body('tags.*')
    .optional()
    .trim()
    .isLength({ min: 1, max: 50 })
    .withMessage('Each tag must be between 1 and 50 characters')
];

export const validateFeedbackUpdate = [
  param('id')
    .isMongoId()
    .withMessage('Invalid feedback ID'),
  
  body('status')
    .isIn(['open', 'in_progress', 'resolved', 'closed', 'duplicate'])
    .withMessage('Invalid status'),
  
  body('adminNotes')
    .optional()
    .trim()
    .isLength({ max: 1000 })
    .withMessage('Admin notes must be less than 1000 characters'),
  
  body('assignedTo')
    .optional()
    .isMongoId()
    .withMessage('Invalid assigned user ID')
];

export const validateFeedbackQuery = [
  query('page')
    .optional()
    .isInt({ min: 1 })
    .withMessage('Page must be a positive integer'),
  
  query('limit')
    .optional()
    .isInt({ min: 1, max: 100 })
    .withMessage('Limit must be between 1 and 100'),
  
  query('sortBy')
    .optional()
    .isIn(['createdAt', 'updatedAt', 'rating', 'priority', 'status'])
    .withMessage('Invalid sort field'),
  
  query('sortOrder')
    .optional()
    .isIn(['asc', 'desc'])
    .withMessage('Sort order must be asc or desc'),
  
  query('status')
    .optional()
    .isIn(['open', 'in_progress', 'resolved', 'closed', 'duplicate'])
    .withMessage('Invalid status filter'),
  
  query('type')
    .optional()
    .isIn(['bug_report', 'feature_request', 'general_feedback', 'user_experience', 'content_issue'])
    .withMessage('Invalid type filter'),
  
  query('category')
    .optional()
    .isIn(['video_playback', 'upload_issues', 'ui_ux', 'performance', 'monetization', 'social_features', 'other'])
    .withMessage('Invalid category filter'),
  
  query('priority')
    .optional()
    .isIn(['low', 'medium', 'high', 'critical'])
    .withMessage('Invalid priority filter'),
  
  query('dateFrom')
    .optional()
    .isISO8601()
    .withMessage('Invalid date format for dateFrom'),
  
  query('dateTo')
    .optional()
    .isISO8601()
    .withMessage('Invalid date format for dateTo')
];

export const validateFeedbackSearch = [
  query('q')
    .trim()
    .isLength({ min: 2, max: 100 })
    .withMessage('Search query must be between 2 and 100 characters')
];

// Report validation rules
export const validateReportCreation = [
  body('type')
    .isIn([
      'spam', 'harassment', 'hate_speech', 'inappropriate_content', 
      'violence', 'nudity', 'copyright_violation', 'fake_account', 
      'scam', 'underage_user', 'other'
    ])
    .withMessage('Invalid report type'),
  
  body('reason')
    .trim()
    .isLength({ min: 5, max: 500 })
    .withMessage('Reason must be between 5 and 500 characters'),
  
  body('description')
    .trim()
    .isLength({ min: 10, max: 1000 })
    .withMessage('Description must be between 10 and 1000 characters'),
  
  body('reportedUser')
    .optional()
    .isMongoId()
    .withMessage('Invalid reported user ID'),
  
  body('reportedVideo')
    .optional()
    .isMongoId()
    .withMessage('Invalid reported video ID'),
  
  body('reportedComment')
    .optional()
    .isMongoId()
    .withMessage('Invalid reported comment ID'),
  
  body('priority')
    .optional()
    .isIn(['low', 'medium', 'high', 'urgent'])
    .withMessage('Invalid priority level'),
  
  body('severity')
    .optional()
    .isIn(['minor', 'moderate', 'severe', 'critical'])
    .withMessage('Invalid severity level'),
  
  body('evidence')
    .optional()
    .isArray()
    .withMessage('Evidence must be an array'),
  
  body('evidence.*.description')
    .optional()
    .trim()
    .isLength({ max: 200 })
    .withMessage('Evidence description must be less than 200 characters')
];

export const validateReportUpdate = [
  param('id')
    .isMongoId()
    .withMessage('Invalid report ID'),
  
  body('status')
    .isIn(['pending', 'under_review', 'resolved', 'dismissed', 'escalated'])
    .withMessage('Invalid status'),
  
  body('moderatorNotes')
    .optional()
    .trim()
    .isLength({ max: 1000 })
    .withMessage('Moderator notes must be less than 1000 characters'),
  
  body('actionTaken')
    .optional()
    .isIn([
      'no_action', 'warning_issued', 'content_removed', 'user_suspended', 
      'user_banned', 'account_restricted', 'content_hidden', 'escalated_to_legal'
    ])
    .withMessage('Invalid action taken')
];

export const validateReportQuery = [
  query('page')
    .optional()
    .isInt({ min: 1 })
    .withMessage('Page must be a positive integer'),
  
  query('limit')
    .optional()
    .isInt({ min: 1, max: 100 })
    .withMessage('Limit must be between 1 and 100'),
  
  query('sortBy')
    .optional()
    .isIn(['createdAt', 'updatedAt', 'priority', 'severity', 'status'])
    .withMessage('Invalid sort field'),
  
  query('sortOrder')
    .optional()
    .isIn(['asc', 'desc'])
    .withMessage('Sort order must be asc or desc'),
  
  query('status')
    .optional()
    .isIn(['pending', 'under_review', 'resolved', 'dismissed', 'escalated'])
    .withMessage('Invalid status filter'),
  
  query('type')
    .optional()
    .isIn([
      'spam', 'harassment', 'hate_speech', 'inappropriate_content', 
      'violence', 'nudity', 'copyright_violation', 'fake_account', 
      'scam', 'underage_user', 'other'
    ])
    .withMessage('Invalid type filter'),
  
  query('priority')
    .optional()
    .isIn(['low', 'medium', 'high', 'urgent'])
    .withMessage('Invalid priority filter'),
  
  query('severity')
    .optional()
    .isIn(['minor', 'moderate', 'severe', 'critical'])
    .withMessage('Invalid severity filter'),
  
  query('dateFrom')
    .optional()
    .isISO8601()
    .withMessage('Invalid date format for dateFrom'),
  
  query('dateTo')
    .optional()
    .isISO8601()
    .withMessage('Invalid date format for dateTo')
];

export const validateReportAssignment = [
  param('id')
    .isMongoId()
    .withMessage('Invalid report ID'),
  
  body('moderatorId')
    .isMongoId()
    .withMessage('Invalid moderator ID')
];

export const validateReportEscalation = [
  param('id')
    .isMongoId()
    .withMessage('Invalid report ID'),
  
  body('escalationReason')
    .trim()
    .isLength({ min: 10, max: 500 })
    .withMessage('Escalation reason must be between 10 and 500 characters')
];
