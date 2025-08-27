import express from 'express';
import { googleSignIn } from '../controllers/authController.js';

const router = express.Router();

// **FIXED: Main auth endpoint that Flutter app calls**
router.post('/', googleSignIn);

// **KEEP: Specific Google endpoint for clarity**
router.post('/google', googleSignIn);

export default router;
