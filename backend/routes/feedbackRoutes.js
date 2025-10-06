import express from 'express';
import {
  createFeedback,
  getFeedbackById,
  getFeedbackList,
  updateFeedbackStatus,
  getFeedbackStats,
  getUserFeedback,
  searchFeedback,
  deleteFeedback
} from '../controllers/feedbackController.js';
import {
  validateFeedbackCreation,
  validateFeedbackUpdate,
  validateFeedbackQuery,
  validateFeedbackSearch
} from '../middleware/feedbackValidation.js';
import { verifyToken } from '../utils/verifytoken.js';

const router = express.Router();

// Middleware to check if user is admin
const isAdmin = (req, res, next) => {
  if (!req.user.isAdmin) {
    return res.status(403).json({
      success: false,
      message: 'Admin access required'
    });
  }
  next();
};

// Public routes (require authentication)
router.post('/', verifyToken, validateFeedbackCreation, createFeedback);
router.get('/search', verifyToken, validateFeedbackSearch, searchFeedback);
router.get('/user/:userId', verifyToken, getUserFeedback);

// Protected routes (user can access their own feedback)
router.get('/:id', verifyToken, getFeedbackById);

// Admin routes
router.get('/', verifyToken, isAdmin, validateFeedbackQuery, getFeedbackList);
router.patch('/:id/status', verifyToken, isAdmin, validateFeedbackUpdate, updateFeedbackStatus);
router.get('/stats/overview', verifyToken, isAdmin, getFeedbackStats);
router.delete('/:id', verifyToken, isAdmin, deleteFeedback);

export default router;
