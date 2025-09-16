import express from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs/promises';
import Video from '../models/Video.js';
import VideoProcessingService from '../services/videoProcessingService.js';
import { verifyToken } from '../utils/verifytoken.js';

const router = express.Router();

// **NEW: Initialize video processing service**
const videoProcessingService = new VideoProcessingService();

// **NEW: Test endpoint to verify system is working**
router.get('/test', (req, res) => {
  res.json({
    success: true,
    message: 'Upload routes are working!',
    timestamp: new Date().toISOString(),
    videoProcessingService: 'Initialized',
    cloudinaryConfigured: videoProcessingService.isCloudinaryConfigured()
  });
});

// **NEW: Configure multer for video uploads**
const storage = multer.diskStorage({
  destination: async (req, file, cb) => {
    const uploadDir = path.join(process.cwd(), 'uploads', 'temp');
    try {
      await fs.mkdir(uploadDir, { recursive: true });
      cb(null, uploadDir);
    } catch (error) {
      cb(error);
    }
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    const ext = path.extname(file.originalname);
    cb(null, `video-${uniqueSuffix}${ext}`);
  }
});

const upload = multer({
  storage: storage,
  limits: {
    fileSize: 100 * 1024 * 1024, // 100MB limit
    files: 1
  },
  fileFilter: (req, file, cb) => {
    // **NEW: Allow only video files**
    const allowedMimeTypes = [
      'video/mp4',
      'video/mov',
      'video/avi',
      'video/mkv',
      'video/webm',
      'video/flv'
    ];
    
    if (allowedMimeTypes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Only video files are allowed'), false);
    }
  }
});

// **NEW: Upload video with automatic quality processing**
router.post('/video', verifyToken, upload.single('video'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No video file uploaded' });
    }

    const { videoName, description, link } = req.body;
    const userId = req.user.id;
    const videoPath = req.file.path;

    console.log('🚀 Starting video upload process...');
    console.log('📁 File path:', videoPath);
    console.log('👤 User ID:', userId);

    // **NEW: Validate video file**
    const videoValidation = await videoProcessingService.validateVideo(videoPath);
    if (!videoValidation.isValid) {
      await fs.unlink(videoPath);
      return res.status(400).json({ 
        error: 'Invalid video file', 
        details: videoValidation.error 
      });
    }

    console.log('✅ Video validation passed');
    console.log('📊 Video info:', videoValidation);

    // **NEW: Create initial video record with pending status**
    const video = new Video({
      videoName: videoName || req.file.originalname,
      description: description || '',
      videoUrl: videoPath, // Temporary path, will be updated after processing
      thumbnailUrl: '', // Will be generated during processing
      uploader: userId,
      videoType: 'yog',
      aspectRatio: videoValidation.width / videoValidation.height,
      duration: videoValidation.duration,
      originalSize: videoValidation.size,
      originalFormat: path.extname(req.file.originalname).substring(1),
      originalResolution: {
        width: videoValidation.width,
        height: videoValidation.height
      },
      processingStatus: 'pending',
      processingProgress: 0
    });

    // **NEW: Save video record first**
    await video.save();
    console.log('💾 Video record saved with ID:', video._id);

    // **NEW: Start quality processing in background**
    processVideoInBackground(video._id, videoPath, videoName, userId);

    // **NEW: Return immediate response with processing status**
    res.status(201).json({
      success: true,
      message: 'Video upload started successfully',
      video: {
        id: video._id,
        videoName: video.videoName,
        processingStatus: video.processingStatus,
        processingProgress: video.processingProgress,
        estimatedTime: '2-5 minutes depending on video length'
      }
    });

  } catch (error) {
    console.error('❌ Error in video upload:', error);
    
    // **NEW: Clean up uploaded file on error**
    if (req.file) {
      try {
        await fs.unlink(req.file.path);
      } catch (cleanupError) {
        console.warn('⚠️ Failed to cleanup file:', cleanupError);
      }
    }

    res.status(500).json({ 
      error: 'Video upload failed', 
      details: error.message 
    });
  }
});

// **NEW: Background video processing function**
async function processVideoInBackground(videoId, videoPath, videoName, userId) {
  try {
    console.log('🔄 Starting background video processing for:', videoId);
    
    // **NEW: Update status to processing**
    const video = await Video.findById(videoId);
    if (!video) {
      throw new Error('Video not found');
    }

    await video.updateProcessingStatus('processing', 10);
    console.log('📊 Processing status updated to 10%');

    // **NEW: Process video to multiple qualities**
    const qualityUrls = await videoProcessingService.processVideoToMultipleQualities(
      videoPath, 
      videoName, 
      userId
    );

    console.log('✅ Quality processing completed');
    console.log('🔗 Quality URLs:', qualityUrls);

    // **NEW: Update video record with quality URLs**
    video.videoUrl = qualityUrls.originalUrl;
    video.preloadQualityUrl = qualityUrls.preloadQualityUrl;
    video.lowQualityUrl = qualityUrls.lowQualityUrl;
    video.mediumQualityUrl = qualityUrls.mediumQualityUrl;
    video.highQualityUrl = qualityUrls.highQualityUrl;
    video.processingStatus = 'completed';
    video.processingProgress = 100;

    // **NEW: Add quality metadata**
    for (const [quality, url] of Object.entries(qualityUrls)) {
      if (url && quality !== 'originalUrl') {
        const qualityName = quality.replace('QualityUrl', '');
        await video.addQualityVersion(qualityName, url, {
          size: 0, // Will be updated if needed
          resolution: {},
          bitrate: ''
        });
      }
    }

    await video.save();
    console.log('🎉 Video processing completed successfully!');
    console.log('📊 Final video data:', {
      id: video._id,
      qualities: video.qualitiesGenerated.length,
      status: video.processingStatus
    });

  } catch (error) {
    console.error('❌ Error in background video processing:', error);
    
    try {
      // **NEW: Update video status to failed**
      const video = await Video.findById(videoId);
      if (video) {
        await video.updateProcessingStatus('failed', null, error.message);
      }
    } catch (updateError) {
      console.error('❌ Failed to update video status:', updateError);
    }
  }
}

// **NEW: Get video processing status**
router.get('/video/:videoId/status', verifyToken, async (req, res) => {
  try {
    const video = await Video.findById(req.params.videoId);
    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    // **NEW: Check if user owns the video**
    if (video.uploader.toString() !== req.user.id) {
      return res.status(403).json({ error: 'Access denied' });
    }

    res.json({
      success: true,
      video: {
        id: video._id,
        videoName: video.videoName,
        processingStatus: video.processingStatus,
        processingProgress: video.processingProgress,
        processingError: video.processingError,
        hasMultipleQualities: video.hasMultipleQualities,
        qualitiesGenerated: video.qualitiesGenerated.length
      }
    });

  } catch (error) {
    console.error('❌ Error getting video status:', error);
    res.status(500).json({ 
      error: 'Failed to get video status', 
      details: error.message 
    });
  }
});

// **NEW: Retry failed video processing**
router.post('/video/:videoId/retry', verifyToken, async (req, res) => {
  try {
    const video = await Video.findById(req.params.videoId);
    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    // **NEW: Check if user owns the video**
    if (video.uploader.toString() !== req.user.id) {
      return res.status(403).json({ error: 'Access denied' });
    }

    // **NEW: Check if video processing failed**
    if (video.processingStatus !== 'failed') {
      return res.status(400).json({ 
        error: 'Video is not in failed state' 
      });
    }

    // **NEW: Reset processing status and retry**
    video.processingStatus = 'pending';
    video.processingProgress = 0;
    video.processingError = null;
    await video.save();

    // **NEW: Start processing again**
    const videoPath = video.videoUrl; // Use original path
    processVideoInBackground(video._id, videoPath, video.videoName, video.uploader);

    res.json({
      success: true,
      message: 'Video processing restarted',
      video: {
        id: video._id,
        processingStatus: video.processingStatus,
        processingProgress: video.processingProgress
      }
    });

  } catch (error) {
    console.error('❌ Error retrying video processing:', error);
    res.status(500).json({ 
      error: 'Failed to retry video processing', 
      details: error.message 
    });
  }
});

// **NEW: Get all user's videos with processing status**
router.get('/videos', verifyToken, async (req, res) => {
  try {
    const videos = await Video.find({ uploader: req.user.id })
      .sort({ uploadedAt: -1 })
      .select('videoName processingStatus processingProgress uploadedAt');

    res.json({
      success: true,
      videos: videos
    });

  } catch (error) {
    console.error('❌ Error getting user videos:', error);
    res.status(500).json({ 
      error: 'Failed to get videos', 
      details: error.message 
    });
  }
});

export default router;
