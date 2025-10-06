import express from 'express';
import {
  createReport,
  getReportById,
  getReportsList,
  updateReportStatus,
  assignToModerator,
  getReportStats,
  getReportsByUser,
  getReportsByVideo,
  findRelatedReports,
  escalateReport,
  deleteReport
} from '../controllers/reportController.js';
import {
  validateReportCreation,
  validateReportUpdate,
  validateReportQuery,
  validateReportAssignment,
  validateReportEscalation
} from '../middleware/feedbackValidation.js';
import { verifyToken } from '../utils/verifytoken.js';

const router = express.Router();

// Middleware to check if user is admin or moderator
const isAdminOrModerator = (req, res, next) => {
  if (!req.user.isAdmin && !req.user.isModerator) {
    return res.status(403).json({
      success: false,
      message: 'Admin or Moderator access required'
    });
  }
  next();
};

// Middleware to check if user is admin only
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
router.post('/', verifyToken, validateReportCreation, createReport);
router.get('/user/:userId', verifyToken, getReportsByUser);

// Protected routes (user can access their own reports)
router.get('/:id', verifyToken, getReportById);

// Moderator/Admin routes
router.get('/', verifyToken, isAdminOrModerator, validateReportQuery, getReportsList);
router.patch('/:id/status', verifyToken, isAdminOrModerator, validateReportUpdate, updateReportStatus);
router.get('/stats/overview', verifyToken, isAdminOrModerator, getReportStats);
router.get('/video/:videoId', verifyToken, isAdminOrModerator, getReportsByVideo);
router.get('/:id/related', verifyToken, isAdminOrModerator, findRelatedReports);
router.patch('/:id/escalate', verifyToken, isAdminOrModerator, validateReportEscalation, escalateReport);

// Admin only routes
router.patch('/:id/assign', verifyToken, isAdmin, validateReportAssignment, assignToModerator);
router.delete('/:id', verifyToken, isAdmin, deleteReport);

export default router;
