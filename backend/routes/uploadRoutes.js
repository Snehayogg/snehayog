import express from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs/promises';
import Video from '../models/Video.js';
import ffmpegVideoService from '../services/ffmpegVideoService.js';
import { verifyToken } from '../utils/verifytoken.js';
import cloudinary from '../config/cloudinary.js';
import cloudflareR2Service from '../services/cloudflareR2Service.js';

const router = express.Router();

// **NEW: Configure multer for image uploads**
const imageStorage = multer.diskStorage({
  destination: async (req, file, cb) => {
    const uploadDir = path.join(process.cwd(), 'uploads', 'ads');
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
    cb(null, `ad-image-${uniqueSuffix}${ext}`);
  }
});

const imageUpload = multer({
  storage: imageStorage,
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB limit for ad images
    files: 1
  },
  fileFilter: (req, file, cb) => {
    const allowedMimeTypes = [
      'image/jpeg',
      'image/jpg', 
      'image/png',
      'image/gif',
      'image/webp'
    ];
    
    if (allowedMimeTypes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Only image files are allowed'), false);
    }
  }
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
    fileSize: (parseInt(process.env.MAX_UPLOAD_MB || '500') * 1024 * 1024), // configurable, default 500MB
    files: 1
  },
  fileFilter: (req, file, cb) => {
    const videoType = req.body.videoType || 'yog';
    
    if (videoType === 'vayu') {
      // Allow image files for vayu type
      const allowedImageTypes = [
        'image/jpeg',
        'image/jpg',
        'image/png',
        'image/gif',
        'image/webp'
      ];
      
      if (allowedImageTypes.includes(file.mimetype)) {
        cb(null, true);
      } else {
        cb(new Error('Only image files are allowed for vayu type'), false);
      }
    } else {
      // Allow only video files for yog type
      const allowedVideoTypes = [
        'video/mp4',
        'video/mov',
        'video/avi',
        'video/mkv',
        'video/webm',
        'video/flv'
      ];
      
      if (allowedVideoTypes.includes(file.mimetype)) {
        cb(null, true);
      } else {
        cb(new Error('Only video files are allowed for yog type'), false);
      }
    }
  }
});

// **NEW: Upload video/image with automatic quality processing**
router.post('/video', verifyToken, upload.single('video'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No file uploaded' });
    }

    const { videoName, description, link, videoType = 'yog' } = req.body;
    const userId = req.user.id;
    const filePath = req.file.path;

    console.log('🚀 Starting upload process...');
    console.log('📁 File path:', filePath);
    console.log('👤 User ID:', userId);
    console.log('📋 Content type:', videoType);

    // **NEW: Handle different file types**
    let fileInfo = {};
    
    if (videoType === 'vayu') {
      // Handle image files
      try {
        // For images, we'll use basic file info
        const stats = await fs.stat(filePath);
        fileInfo = {
          width: 1920, // Default width for images
          height: 1080, // Default height for images
          duration: 0, // Images have no duration
          size: stats.size,
          format: path.extname(req.file.originalname).substring(1)
        };
        console.log('✅ Image validation passed');
        console.log('📊 Image info:', fileInfo);
      } catch (validationError) {
        await fs.unlink(filePath);
        return res.status(400).json({ 
          error: 'Invalid image file', 
          details: validationError.message 
        });
      }
    } else {
      // Handle video files
      try {
        const videoValidation = await ffmpegVideoService.getVideoInfo(filePath);
        fileInfo = videoValidation;
        console.log('✅ Video validation passed');
        console.log('📊 Video info:', videoValidation);
      } catch (validationError) {
        await fs.unlink(filePath);
        return res.status(400).json({ 
          error: 'Invalid video file', 
          details: validationError.message 
        });
      }
    }

    // **NEW: Show cost estimate**
    console.log('💰 Cost estimate: $0 (FFmpeg processing - no external costs)');

    // **NEW: Create initial video record with pending status**
    const video = new Video({
      videoName: videoName || req.file.originalname,
      description: description || '',
      videoUrl: filePath, // Temporary path, will be updated after processing
      thumbnailUrl: '', // Will be generated during processing
      uploader: userId,
      videoType: videoType,
      aspectRatio: fileInfo.width / fileInfo.height,
      duration: fileInfo.duration,
      originalSize: fileInfo.size,
      originalFormat: fileInfo.format,
      originalResolution: {
        width: fileInfo.width,
        height: fileInfo.height
      },
      processingStatus: 'pending',
      processingProgress: 0
    });

    // **NEW: Save video record first**
    await video.save();
    console.log('💾 Video record saved with ID:', video._id);

    // **OPTIMIZED: Respond immediately, process in background**
    video.processingStatus = 'processing';
    video.processingProgress = 0;
    await video.save();

    // Respond immediately to user
    res.status(201).json({
      success: true,
      message: 'Video uploaded successfully! Processing in background...',
      video: {
        id: video._id,
        videoName: video.videoName,
        videoUrl: '', // Will be populated after processing
        hlsPlaylistUrl: '',
        thumbnailUrl: '',
        processingStatus: 'processing',
        processingProgress: 0,
        isHLSEncoded: false
      }
    });

    // **BACKGROUND PROCESSING** - Don't await this
    console.log('🚀 Starting background processing...');
    (async () => {
      try {
        console.log('🚀 Starting background processing for:', video._id);
        const videoDoc = await Video.findById(video._id);
        if (!videoDoc) throw new Error('Video not found');

        videoDoc.processingStatus = 'processing';
        videoDoc.processingProgress = 5;
        await videoDoc.save();

        let result;
        if (videoType === 'vayu') {
          // Process image files
          console.log('📸 Processing image file...');
          const uploadResult = await cloudflareR2Service.uploadImage(
            filePath,
            `images/${userId}/${videoName || `media_${video._id}`}_${Date.now()}.${path.extname(filePath).substring(1)}`
          );
          result = {
            videoUrl: uploadResult.url,
            thumbnailUrl: uploadResult.url,
            hlsPlaylistUrl: uploadResult.url
          };
        } else {
          // Process video files using HLS processing
          console.log('🎬 Processing video file...');
          const hybridVideoService = (await import('../services/hybridVideoService.js')).default;
          const hlsResult = await hybridVideoService.processVideoToHLS(filePath, videoName || `media_${video._id}`, userId);
          result = {
            videoUrl: hlsResult.videoUrl,
            thumbnailUrl: hlsResult.thumbnailUrl,
            hlsPlaylistUrl: hlsResult.hlsPlaylistUrl
          };
        }

        videoDoc.videoUrl = result.videoUrl;
        videoDoc.thumbnailUrl = result.thumbnailUrl;
        videoDoc.hlsPlaylistUrl = result.hlsPlaylistUrl;
        videoDoc.processingStatus = 'completed';
        videoDoc.processingProgress = 100;
        videoDoc.isHLSEncoded = videoType !== 'vayu';
        await videoDoc.save();
        
        console.log('🎉 Background processing completed for:', video._id);
        try {
          await fs.unlink(filePath);
        } catch (cleanupError) {
          console.warn('⚠️ Failed to cleanup temp file:', cleanupError);
        }
      } catch (error) {
        console.error('❌ Background processing failed:', error);
        try {
          const videoDoc = await Video.findById(video._id);
          if (videoDoc) {
            videoDoc.processingStatus = 'failed';
            videoDoc.processingError = error.message;
            await videoDoc.save();
          }
        } catch (updateError) {
          console.error('❌ Failed to update video status:', updateError);
        }
      }
    })();

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

// **NEW: Get video processing status endpoint**
router.get('/video/:videoId/status', verifyToken, async (req, res) => {
  try {
    const { videoId } = req.params;
    const userId = req.user.id;

    console.log('📊 Getting processing status for video:', videoId);

    const video = await Video.findById(videoId);
    if (!video) {
      return res.status(404).json({ 
        success: false, 
        error: 'Video not found' 
      });
    }

    // Check if user owns this video
    if (video.uploader.toString() !== userId) {
      return res.status(403).json({ 
        success: false, 
        error: 'Access denied' 
      });
    }

    console.log('📊 Video status:', {
      id: video._id,
      status: video.processingStatus,
      progress: video.processingProgress,
      error: video.processingError
    });

    res.json({
      success: true,
      video: {
        id: video._id,
        processingStatus: video.processingStatus,
        processingProgress: video.processingProgress,
        processingError: video.processingError,
        videoUrl: video.videoUrl,
        thumbnailUrl: video.thumbnailUrl,
        hlsPlaylistUrl: video.hlsPlaylistUrl,
        isHLSEncoded: video.isHLSEncoded,
        hasMultipleQualities: false, // For now, we only generate one quality
        qualitiesGenerated: 1
      }
    });

  } catch (error) {
    console.error('❌ Error getting video status:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to get video status',
      details: error.message 
    });
  }
});

// **OPTIMIZED: Background media processing function**
async function processMediaInBackground(videoId, filePath, mediaName, userId, videoType) {
  try {
    console.log('🚀 Starting background media processing for:', videoId);
    console.time('Background Processing');
    
    const video = await Video.findById(videoId);
    if (!video) {
      throw new Error('Media not found');
    }

    // Update progress: Starting processing
    video.processingStatus = 'processing';
    video.processingProgress = 10;
    await video.save();
    console.log('✅ Updated video status to processing (10%)');
    
    let processingResult;
    
    if (videoType === 'vayu') {
      // Process image files
      console.log('📸 Processing image file...');
      
      // Update progress: Processing image
      video.processingProgress = 50;
      await video.save();
      console.log('✅ Updated progress to 50% (processing image)');
      
      processingResult = await processImageFile(filePath, mediaName, userId);
      
      // Update progress: Image processed
      video.processingProgress = 90;
      await video.save();
      console.log('✅ Updated progress to 90% (image processed)');
      
    } else {
      // Process video files
      console.log('🎥 Processing video file...');
      
      // Update progress: Processing video
      video.processingProgress = 25;
      await video.save();
      console.log('✅ Updated progress to 25% (processing video)');
      
      processingResult = await ffmpegVideoService.processVideo(
        filePath,
        mediaName,
        userId
      );
      
      // Update progress: Video processed
      video.processingProgress = 90;
      await video.save();
      console.log('✅ Updated progress to 90% (video processed)');
    }

    // Update with processed URLs
    video.videoUrl = processingResult.videoUrl;
    video.hlsPlaylistUrl = processingResult.videoUrl; // Use videoUrl as playlist for MP4
    video.thumbnailUrl = processingResult.thumbnailUrl;
    video.processingStatus = 'completed';
    video.processingProgress = 100;
    video.isHLSEncoded = false; // MP4, not HLS
    video.lowQualityUrl = processingResult.videoUrl;

    await video.save();
    console.log('✅ Final progress update: 100% (completed)');
    console.timeEnd('Background Processing');
    console.log('🎉 Background processing completed successfully!');

  } catch (error) {
    console.error('❌ Error in background processing:', error);
    try {
      const video = await Video.findById(videoId);
      if (video) {
        video.processingStatus = 'failed';
        video.processingError = error.message;
        await video.save();
      }
    } catch (updateError) {
      console.error('❌ Failed to update video status:', updateError);
    }
    throw error;
  }
}

// Pure HLS video processing function (FFmpeg → R2) - DEPRECATED
async function processVideoToHLS(videoId, videoPath, videoName, userId) {
  try {
    console.log('🚀 Starting Pure HLS processing (FFmpeg → R2) for:', videoId);
    
    const video = await Video.findById(videoId);
    if (!video) {
      throw new Error('Video not found');
    }

    video.processingStatus = 'processing';
    video.processingProgress = 10;
    await video.save();
    
    const hlsResult = await hybridVideoService.processVideoToHLS(
      videoPath,
      videoName,
      userId
    );

    // Update with HLS URLs
    video.videoUrl = hlsResult.videoUrl;
    video.hlsPlaylistUrl = hlsResult.hlsPlaylistUrl;
    video.thumbnailUrl = hlsResult.thumbnailUrl;
    video.processingStatus = 'completed';
    video.processingProgress = 100;
    video.isHLSEncoded = true;
    video.lowQualityUrl = hlsResult.videoUrl;

    await video.save();
    console.log('🎉 Pure HLS processing completed successfully!');

  } catch (error) {
    console.error('❌ Error in Pure HLS processing:', error);
    try {
      const video = await Video.findById(videoId);
      if (video) {
        video.processingStatus = 'failed';
        video.processingError = error.message;
        await video.save();
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
    processMediaInBackground(video._id, videoPath, video.videoName, video.uploader, 'yog');

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

// **NEW: Upload image for ads**
router.post('/image', verifyToken, imageUpload.single('image'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No image file uploaded' });
    }

    const imagePath = req.file.path;
    console.log('🖼️ Starting ad image upload to Cloudinary...');
    console.log('📁 File path:', imagePath);
    console.log('📊 File size:', (req.file.size / 1024 / 1024).toFixed(2), 'MB');

    try {
      // **ENHANCED: Check Cloudinary configuration first**
      const hasCloudinaryConfig = (process.env.CLOUDINARY_CLOUD_NAME || process.env.CLOUD_NAME) &&
                                  (process.env.CLOUDINARY_API_KEY || process.env.CLOUD_KEY) &&
                                  (process.env.CLOUDINARY_API_SECRET || process.env.CLOUD_SECRET);
      
      if (!hasCloudinaryConfig) {
        console.error('❌ Cloudinary configuration missing:');
        console.error('   CLOUDINARY_CLOUD_NAME:', !!process.env.CLOUDINARY_CLOUD_NAME);
        console.error('   CLOUDINARY_API_KEY:');
        console.error('   CLOUDINARY_API_SECRET:');
        console.error('   CLOUD_NAME:', !!process.env.CLOUD_NAME);
        console.error('   CLOUD_KEY:');
        console.error('   CLOUD_SECRET:');
        
        throw new Error('Cloudinary configuration is incomplete. Please check environment variables.');
      }

      console.log('☁️ Cloudinary config check passed, uploading image...');
      
      // Upload to Cloudinary
      const result = await cloudinary.uploader.upload(imagePath, {
        resource_type: 'image',
        folder: 'snehayog/ads/images',
        transformation: [
          { quality: 'auto:good' },
          { fetch_format: 'auto' }
        ],
        // **NEW: Add timeout and retry options**
        timeout: 30000, // 30 second timeout
      });

      console.log('✅ Ad image uploaded to Cloudinary successfully');
      console.log('🔗 Image URL:', result.secure_url);

      // Clean up temp file
      await fs.unlink(imagePath);

      res.status(200).json({
        success: true,
        url: result.secure_url,
        publicId: result.public_id,
        message: 'Image uploaded successfully'
      });

    } catch (cloudinaryError) {
      console.error('❌ Cloudinary upload failed:', cloudinaryError);
      console.error('❌ Error details:', JSON.stringify(cloudinaryError, null, 2));
      
      // **ENHANCED: Provide specific error messages based on error type**
      let userFriendlyError = 'Failed to upload image to cloud storage';
      
      if (cloudinaryError.message?.includes('Invalid API key')) {
        userFriendlyError = 'Cloud storage configuration error. Please contact support.';
      } else if (cloudinaryError.message?.includes('timeout')) {
        userFriendlyError = 'Upload timeout. Please check your internet connection and try again.';
      } else if (cloudinaryError.message?.includes('file size')) {
        userFriendlyError = 'Image file is too large. Please use an image smaller than 10MB.';
      } else if (cloudinaryError.message?.includes('format')) {
        userFriendlyError = 'Invalid image format. Please use JPG, PNG, or WebP.';
      }
      
      // Clean up temp file on error
      try {
        await fs.unlink(imagePath);
      } catch (unlinkError) {
        console.error('❌ Error cleaning up temp file:', unlinkError);
      }

      res.status(500).json({
        error: userFriendlyError,
        details: cloudinaryError.message,
        debug: {
          hasCloudName: !!process.env.CLOUDINARY_CLOUD_NAME,
          hasApiKey: !!process.env.CLOUDINARY_API_KEY,
          hasApiSecret: !!process.env.CLOUDINARY_API_SECRET,
        }
      });
    }

  } catch (error) {
    console.error('❌ Error in image upload route:', error);
    res.status(500).json({ 
      error: 'Image upload failed', 
      details: error.message 
    });
  }
});


export default router;
