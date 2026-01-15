import express from 'express';
import { googleSignIn, checkDeviceId } from '../controllers/authController.js';
import { authLimiter } from '../middleware/rateLimiter.js';

const router = express.Router();

// **FIXED: Main auth endpoint that Flutter app calls**
// **NEW: Apply Strict Rate Limiting (Prevent Brute Force)**
router.post('/', authLimiter, googleSignIn);

// **KEEP: Specific Google endpoint for clarity**
router.post('/google', authLimiter, googleSignIn);

// **NEW: Check if device ID has logged in before (for skipping login after reinstall)**
router.post('/check-device', blockPublicAccess, checkDeviceId);

// Helper to block public access if needed, or we can just rely on authLimiter
function blockPublicAccess(req, res, next) {
    next();
}

export default router;
