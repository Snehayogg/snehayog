import express from 'express';
import { 
  googleSignIn, 
  deviceLogin, 
  refreshAccessToken, 
  logout, 
  logoutAllDevices, 
  getActiveSessions,
  checkDeviceId 
} from '../controllers/authController.js';
import { authLimiter } from '../middleware/rateLimiter.js';
import { verifyToken } from '../utils/verifytoken.js';

const router = express.Router();

/**
 * Public Auth Routes (No auth required)
 */

// Google Sign-In (first-time login / re-authentication)
router.post('/', authLimiter, googleSignIn);
router.post('/google', authLimiter, googleSignIn);

// Device Auto-Login (after app reinstall)
// router.post('/device-login', authLimiter, deviceLogin);

// Refresh Access Token
router.post('/refresh', authLimiter, refreshAccessToken);

// Legacy: Check if device has logged in before
router.post('/check-device', authLimiter, checkDeviceId);

/**
 * Protected Auth Routes (Auth required)
 */

// Logout current device
router.post('/logout', verifyToken, logout);

// Logout all devices
router.post('/logout-all', verifyToken, logoutAllDevices);

// Get active sessions
router.get('/sessions', verifyToken, getActiveSessions);

export default router;
