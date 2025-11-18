import express from 'express';
import { googleSignIn, checkDeviceId } from '../controllers/authController.js';

const router = express.Router();

// **FIXED: Main auth endpoint that Flutter app calls**
router.post('/', googleSignIn);

// **KEEP: Specific Google endpoint for clarity**
router.post('/google', googleSignIn);

// **NEW: Check if device ID has logged in before (for skipping login after reinstall)**
router.post('/check-device', checkDeviceId);

export default router;
