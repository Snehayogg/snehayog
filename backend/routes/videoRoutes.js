import express from 'express';
import { verifyToken, passiveVerifyToken } from '../utils/verifytoken.js';
import * as videoController from '../controllers/videoController.js';
import { validateVideoData, upload } from '../middleware/videoMiddleware.js';
import rateLimit from 'express-rate-limit';

const router = express.Router();

// Rate limiter for video uploads
const uploadLimiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 10, // limit each IP to 10 uploads per window
  message: 'Too many video uploads from this IP, please try again after 15 minutes'
});

/**
 * Cache Management Routes
 */
router.get('/cache/status', videoController.getCacheStatus);
router.post('/cache/clear', videoController.clearCache);

/**
 * Video Upload & Processing Routes
 */
router.post('/check-duplicate', verifyToken, videoController.checkDuplicate);
router.post('/upload', verifyToken, uploadLimiter, validateVideoData, upload.single('video'), videoController.uploadVideo);
router.post('/image', verifyToken, videoController.createImageFeedEntry);

/**
 * Video Retrieval Routes
 */
router.get('/', videoController.getFeed);
router.get('/user/:googleId', verifyToken, videoController.getUserVideos);
router.get('/:id', videoController.getVideoById);

/**
 * Video Interaction Routes
 */
router.post('/sync-watch-history', verifyToken, videoController.syncWatchHistory);
router.post('/:id/watch', passiveVerifyToken, videoController.trackWatch);
router.post('/:id/like', verifyToken, videoController.toggleLike);
router.delete('/:id/like', verifyToken, videoController.deleteLike);
router.post('/:id/increment-view', videoController.incrementView);

/**
 * Video Deletion Routes
 */
router.delete('/:id', verifyToken, videoController.deleteVideo);
router.post('/bulk-delete', verifyToken, videoController.bulkDeleteVideos);

/**
 * Utility & Cleanup Routes
 */
router.post('/cleanup-temp-hls', videoController.cleanupTempHLS);
router.post('/generate-signed-url', verifyToken, videoController.generateSignedUrl);
router.get('/cloudinary-config', videoController.getCloudinaryConfig);
router.post('/cleanup-orphaned', videoController.cleanupOrphaned);
router.post('/cleanup-broken-videos', videoController.cleanupBrokenVideos);
router.post('/sync-user-video-arrays', videoController.syncUserVideoArrays);

export default router;
