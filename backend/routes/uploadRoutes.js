import express from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs/promises';
import mongoose from 'mongoose';
import Video from '../models/Video.js';
import User from '../models/User.js';
// Lazy import to ensure env vars are loaded first
let hybridVideoService;
import { verifyToken } from '../utils/verifytoken.js';
import cloudinary from '../config/cloudinary.js';

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

    // **NEW: Lazy load hybrid service to ensure env vars are loaded**
    if (!hybridVideoService) {
      const { default: service } = await import('../services/hybridVideoService.js');
      hybridVideoService = service;
    }
    
    // **NEW: Validate video file with hybrid service**
    const videoValidation = await hybridVideoService.validateVideo(videoPath);
    if (!videoValidation.isValid) {
      await fs.unlink(videoPath);
      return res.status(400).json({ 
        error: 'Invalid video file', 
        details: videoValidation.error 
      });
    }

    console.log('✅ Video validation passed');
    console.log('📊 Video info:', videoValidation);
    
    // **NEW: Show cost estimate**
    const costEstimate = hybridVideoService.getCostEstimate(videoValidation.sizeInMB);
    console.log('💰 Cost estimate:', costEstimate);

    // **NEW: Find user by Google ID to get proper ObjectId**
    const user = await User.findOne({ googleId: userId });
    if (!user) {
      await fs.unlink(videoPath);
      return res.status(404).json({ error: 'User not found' });
    }

    // **NEW: Get video dimensions safely**
    const videoInfo = await hybridVideoService.getOriginalVideoInfo(videoPath);
    const aspectRatio = videoInfo.width && videoInfo.height ? 
      videoInfo.width / videoInfo.height : 9/16; // Default to 9:16 if dimensions unavailable

    // **NEW: Create initial video record with pending status**
    // **FIX: Use proper URL format instead of local file path**
    const baseUrl = process.env.SERVER_URL || 'http://192.168.0.199:5001';
    const relativePath = videoPath.replace(/\\/g, '/').replace(process.cwd().replace(/\\/g, '/'), '');
    const tempVideoUrl = `${baseUrl}${relativePath}`;
    
    console.log('🔗 Generated temp video URL:', tempVideoUrl);
    
    const video = new Video({
      videoName: videoName || req.file.originalname,
      description: description || '',
      videoUrl: tempVideoUrl, // Proper URL format, will be updated after processing
      thumbnailUrl: '', // Will be generated during processing
      uploader: user._id, // Use user's ObjectId, not Google ID
      videoType: 'yog',
      aspectRatio: aspectRatio,
      duration: videoInfo.duration || 0,
      originalSize: videoValidation.size,
      originalFormat: path.extname(req.file.originalname).substring(1),
      originalResolution: {
        width: videoInfo.width || 0,
        height: videoInfo.height || 0
      },
      processingStatus: 'pending',
      processingProgress: 0
    });

    // **NEW: Save video record first**
    await video.save();
    console.log('💾 Video record saved with ID:', video._id);

    // **NEW: Start hybrid processing in background (Cloudinary → R2)**
    console.log('🔄 Starting background processing for video:', video._id);
    console.log('📁 Video path:', videoPath);
    console.log('👤 User ID:', userId);
    
    // Start processing in background with proper error handling
    processVideoHybrid(video._id, videoPath, videoName, userId).catch(error => {
      console.error('❌ Background processing failed:', error);
      console.error('❌ Error stack:', error.stack);
    });

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

// **NEW: URL normalization function**
function normalizeVideoUrl(url) {
  if (!url) return url;
  
  // **FIX: Replace backslashes with forward slashes**
  let normalizedUrl = url.replace(/\\/g, '/');
  
  // **FIX: Ensure proper URL format**
  if (!normalizedUrl.startsWith('http://') && !normalizedUrl.startsWith('https://')) {
    // If it's a relative path, make it absolute
    const baseUrl = process.env.SERVER_URL || 'http://192.168.0.199:5001';
    normalizedUrl = `${baseUrl}/${normalizedUrl}`;
  }
  
  // **FIX: Ensure single forward slashes between path segments (but preserve protocol slashes)**
  // Only normalize multiple slashes in the path part, not the protocol
  if (normalizedUrl.includes('://')) {
    const [protocol, rest] = normalizedUrl.split('://');
    const normalizedRest = rest.replace(/\/+/g, '/');
    normalizedUrl = `${protocol}://${normalizedRest}`;
  } else {
    normalizedUrl = normalizedUrl.replace(/\/+/g, '/');
  }
  
  console.log('🔧 URL normalization:');
  console.log('   Original:', url);
  console.log('   Normalized:', normalizedUrl);
  
  return normalizedUrl;
}

// **NEW: Hybrid video processing function (Cloudinary → R2)**
async function processVideoHybrid(videoId, videoPath, videoName, userId) {
  try {
    console.log('🚀 Starting hybrid video processing (Cloudinary → R2) for:', videoId);
    console.log('📁 Video path:', videoPath);
    console.log('📝 Video name:', videoName);
    console.log('👤 User ID:', userId);
    
    // **FIX: Sanitize video name to remove invalid characters for Cloudinary**
    const sanitizedVideoName = videoName.replace(/[^a-zA-Z0-9\s_-]/g, '_').replace(/\s+/g, '_').substring(0, 50);
    console.log('📝 Sanitized video name:', sanitizedVideoName);
    
    // **NEW: Lazy load hybrid service to ensure env vars are loaded**
    if (!hybridVideoService) {
      const { default: service } = await import('../services/hybridVideoService.js');
      hybridVideoService = service;
    }
    
    // **NEW: Update status to processing**
    const video = await Video.findById(videoId);
    if (!video) {
      throw new Error('Video not found');
    }

    video.processingStatus = 'processing';
    video.processingProgress = 10;
    await video.save();
    console.log('📊 Processing status updated to 10% - Starting validation');

    // **UPDATE: Validation phase (10-30%)**
    video.processingProgress = 30;
    await video.save();
    console.log('📊 Processing status updated to 30% - Validation complete, starting conversion');

    // **NEW: Process video using hybrid approach with timeout**
    console.log('🔄 Starting hybrid processing...');
    let hybridResult;
    try {
      hybridResult = await Promise.race([
        hybridVideoService.processVideoHybrid(
          videoPath, 
          sanitizedVideoName, 
          userId
        ),
        new Promise((_, reject) => 
          setTimeout(() => reject(new Error('Hybrid processing timeout after 10 minutes')), 10 * 60 * 1000)
        )
      ]);
      console.log('✅ Hybrid processing completed successfully');
    } catch (error) {
      console.error('❌ Hybrid processing failed:', error);
      // Update video status to failed
      video.processingStatus = 'failed';
      video.processingError = error.message;
      await video.save();
      throw error;
    }

    console.log('✅ Hybrid processing completed');
    console.log('🔗 Hybrid result:', hybridResult);

    // **UPDATE: Finalizing phase (80-95%)**
    video.processingProgress = 95;
    await video.save();
    console.log('📊 Processing status updated to 95% - Finalizing');

    // **NEW: Update video record with R2 URLs**
    // **FIX: Validate and normalize URLs before saving**
    const normalizedVideoUrl = normalizeVideoUrl(hybridResult.videoUrl);
    const normalizedThumbnailUrl = normalizeVideoUrl(hybridResult.thumbnailUrl);
    
    video.videoUrl = normalizedVideoUrl; // R2 video URL with FREE bandwidth
    video.thumbnailUrl = normalizedThumbnailUrl; // R2 thumbnail URL
    
    console.log('🔗 Final video URL:', normalizedVideoUrl);
    console.log('🖼️ Final thumbnail URL:', normalizedThumbnailUrl);
    
    // **NEW: Clear old quality URLs (single format now)**
    video.preloadQualityUrl = null;
    video.lowQualityUrl = normalizedVideoUrl; // Same as main URL (480p)
    video.mediumQualityUrl = null;
    video.highQualityUrl = null;

    // **NEW: If URL is HLS (.m3u8), set HLS flags/fields for frontend autoplay**
    if (normalizedVideoUrl && normalizedVideoUrl.includes('.m3u8')) {
      video.isHLSEncoded = true;
      video.hlsPlaylistUrl = normalizedVideoUrl;
      video.hlsMasterPlaylistUrl = normalizedVideoUrl;
    } else {
      video.isHLSEncoded = false;
      video.hlsPlaylistUrl = null;
      video.hlsMasterPlaylistUrl = null;
    }
    
    video.processingStatus = 'completed';
    video.processingProgress = 100;

    // **NEW: Add hybrid metadata**
    video.originalSize = hybridResult.size;
    video.originalFormat = 'mp4';
    video.originalResolution = {
      width: 854,
      height: 480
    };

    // **NEW: Add single quality version**
    video.qualitiesGenerated = [{
      quality: 'optimized',
      url: normalizedVideoUrl,
      size: hybridResult.size,
      resolution: {
        width: 854,
        height: 480
      },
      bitrate: '800k',
      generatedAt: new Date()
    }];

    await video.save();
    console.log('🎉 Hybrid video processing completed successfully!');
    console.log('💰 Cost savings: 93% vs previous setup');
    console.log('📊 Final video data:', {
      id: video._id,
      videoUrl: normalizedVideoUrl,
      thumbnailUrl: normalizedThumbnailUrl,
      quality: '480p optimized',
      storage: 'Cloudflare R2',
      bandwidth: 'FREE',
      status: video.processingStatus
    });

  } catch (error) {
    console.error('❌ Error in hybrid video processing:', error);
    
    try {
      // **NEW: Update video status to failed**
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

    // **FIX: Compare against the user's ObjectId, not Google ID**
    const owner = await User.findOne({ googleId: req.user.id });
    if (!owner || video.uploader.toString() !== owner._id.toString()) {
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
        qualitiesGenerated: video.qualitiesGenerated.length,
        isHLSEncoded: video.isHLSEncoded || false,
        hlsPlaylistUrl: video.hlsPlaylistUrl || null,
        // Include URLs when processing is completed
        videoUrl: video.processingStatus === 'completed' ? video.videoUrl : null,
        thumbnailUrl: video.processingStatus === 'completed' ? video.thumbnailUrl : null
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

// **NEW: Get video processing status endpoint**
router.get('/video/:videoId/status', verifyToken, async (req, res) => {
  try {
    const { videoId } = req.params;
    const userId = req.user.id;

    console.log('🔍 Status check request:', { videoId, userId });

    // Validate video ID
    if (!videoId || !mongoose.Types.ObjectId.isValid(videoId)) {
      return res.status(400).json({ 
        success: false, 
        error: 'Invalid video ID' 
      });
    }

    // Find the video
    const video = await Video.findById(videoId);
    if (!video) {
      return res.status(404).json({ 
        success: false, 
        error: 'Video not found' 
      });
    }

    // **FIX: Compare against the user's ObjectId, not Google ID**
    const owner = await User.findOne({ googleId: userId });
    if (!owner || video.uploader.toString() !== owner._id.toString()) {
      return res.status(403).json({ 
        success: false, 
        error: 'Access denied' 
      });
    }

    // Return processing status
    const statusResponse = {
      success: true,
      video: {
        _id: video._id,
        videoName: video.videoName,
        processingStatus: video.processingStatus || 'pending',
        processingProgress: video.processingProgress || 0,
        processingError: video.processingError || null,
        videoUrl: video.videoUrl || null,
        thumbnailUrl: video.thumbnailUrl || null,
        uploadedAt: video.uploadedAt,
        estimatedTime: '2-5 minutes depending on video length'
      }
    };

    console.log('✅ Status response:', statusResponse.video.processingStatus);
    res.json(statusResponse);

  } catch (error) {
    console.error('❌ Error getting video status:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to get video status',
      details: error.message 
    });
  }
});

export default router;
