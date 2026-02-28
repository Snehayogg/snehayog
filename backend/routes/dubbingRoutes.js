import express from 'express';
import multer from 'multer';
import dubbingService from '../services/dubbingService.js';
import cloudflareR2Service from '../services/cloudflareR2Service.js';
import Video from '../models/Video.js';
import { verifyToken } from '../utils/verifytoken.js';
import { invalidateCache } from '../middleware/cacheMiddleware.js';

const router = express.Router();
const upload = multer({ dest: 'temp/' });

/**
 * @route   POST /api/dubbing/process
 * @desc    Start the "Smart Dub" process for a video
 * @access  Private
 */
router.post('/process', verifyToken, upload.single('video'), async (req, res) => {
  try {
    const { videoId } = req.body;
    const userId = req.user.id;
    
    // If a new video file is provided, it's a gallery upload for dubbing
    // If only videoId is provided, it's an existing video in the system
    const result = await dubbingService.startSmartDub({
      userId,
      videoId,
      videoFile: req.file
    });

    res.status(202).json({
      success: true,
      message: 'Dubbing process started in background',
      taskId: result.taskId
    });
  } catch (error) {
    console.error('❌ Dubbing Route Error:', error);
    res.status(500).json({ success: false, message: error.message });
  }
});

/**
 * @route   GET /api/dubbing/status/:taskId
 * @desc    Check the status of a dubbing task
 * @access  Private
 */
/**
 * @route   POST /api/dubbing/upload
 * @desc    Upload a finished dubbed video from client (Crowdsourced Dubbing)
 * @access  Private
 */
router.post('/upload', verifyToken, upload.single('video'), async (req, res) => {
  try {
    const { videoId, language } = req.body;
    const userId = req.user.id;
    
    if (!req.file) {
      return res.status(400).json({ success: false, message: 'No video file provided' });
    }
    
    if (!videoId || !language) {
      return res.status(400).json({ success: false, message: 'videoId and language are required' });
    }

    console.log(`📥 Receiving dubbed video for [${videoId}] in [${language}]...`);

    // 1. Upload to R2
    const fileName = `dubbed_${videoId}_${language}`;
    // uploadVideoToR2 expects (filePath, fileName, userId)
    const uploadResult = await cloudflareR2Service.uploadVideoToR2(req.body.tempPath || req.file.path, fileName, userId);
    
    // 2. Update Video model
    const video = await Video.findById(videoId);
    if (!video) {
      await cloudflareR2Service.cleanupLocalFile(req.file.path);
      return res.status(404).json({ success: false, message: 'Video not found' });
    }
    
    // Use the Map's set method
    if (!video.dubbedUrls) video.dubbedUrls = new Map();
    video.dubbedUrls.set(language, uploadResult.url);
    await video.save();
    await invalidateCache([
      'videos:feed:*',
      'videos:unwatched:ids:*',
      `video:data:${videoId}`,
      `video:${videoId}`,
    ]);
    
    // 3. Cleanup temp file
    await cloudflareR2Service.cleanupLocalFile(req.file.path);
    
    console.log(`✅ Dubbed video cached globally: ${uploadResult.url}`);

    res.json({
      success: true,
      message: 'Dubbed video uploaded and cached successfully',
      url: uploadResult.url
    });
    
  } catch (error) {
    console.error('❌ Dubbed Upload Error:', error);
    if (req.file) await cloudflareR2Service.cleanupLocalFile(req.file.path).catch(() => {});
    res.status(500).json({ success: false, message: error.message });
  }
});

router.get('/status/:taskId', verifyToken, async (req, res) => {
  try {
    const { taskId } = req.params;
    const status = await dubbingService.getTaskStatus(taskId);
    res.json({ success: true, ...status });
  } catch (error) {
    res.status(404).json({ success: false, message: 'Task not found' });
  }
});

export default router;
