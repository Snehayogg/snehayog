import express from 'express';
import multer from 'multer';
import cloudinary, { 
  STREAMING_PROFILES, 
  HLS_CONFIG, 
  getHLSStreamingUrl, 
  getMasterPlaylistUrl, 
  getVideoThumbnailUrl 
} from '../config/cloudinary.js';
import fs from 'fs';
import { verifyToken } from '../utils/verifytoken.js';

const router = express.Router();

// Multer configuration for media uploads
const upload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => {
      const uploadDir = 'uploads/temp/';
      if (!fs.existsSync(uploadDir)) {
        fs.mkdirSync(uploadDir, { recursive: true });
      }
      cb(null, uploadDir);
    },
    filename: (req, file, cb) => {
      const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
      cb(null, uniqueSuffix + '-' + file.originalname);
    },
  }),
  limits: {
    fileSize: 100 * 1024 * 1024, // 100MB limit for video files (increased for high quality)
  },
  fileFilter: (req, file, cb) => {
    console.log('🔍 Upload: File filter check:', {
      originalname: file.originalname,
      mimetype: file.mimetype,
      size: file.size
    });
    
    // **NEW: Enhanced MIME type detection**
    const allowedMimeTypes = [
      'image/jpeg', 'image/png', 'image/gif', 'image/webp',
      'video/mp4', 'video/webm', 'video/avi', 'video/mov', 'video/mkv'
    ];
    
    // **NEW: Check if MIME type is in allowed list**
    if (allowedMimeTypes.includes(file.mimetype)) {
      console.log('✅ Upload: File type accepted:', file.mimetype);
      cb(null, true);
    } else {
      // **NEW: Try to detect MIME type from file extension as fallback**
      const fileName = file.originalname.toLowerCase();
      let detectedMimeType = null;
      
      if (fileName.endsWith('.jpg') || fileName.endsWith('.jpeg')) {
        detectedMimeType = 'image/jpeg';
      } else if (fileName.endsWith('.png')) {
        detectedMimeType = 'image/png';
      } else if (fileName.endsWith('.gif')) {
        detectedMimeType = 'image/gif';
      } else if (fileName.endsWith('.webp')) {
        detectedMimeType = 'image/webp';
      } else if (fileName.endsWith('.mp4')) {
        detectedMimeType = 'video/mp4';
      } else if (fileName.endsWith('.webm')) {
        detectedMimeType = 'video/webm';
      } else if (fileName.endsWith('.avi')) {
        detectedMimeType = 'video/avi';
      } else if (fileName.endsWith('.mov')) {
        detectedMimeType = 'video/mov';
      } else if (fileName.endsWith('.mkv')) {
        detectedMimeType = 'video/mkv';
      }
      
      if (detectedMimeType) {
        console.log('⚠️ Upload: MIME type mismatch, but file extension suggests: $detectedMimeType');
        console.log('⚠️ Upload: Original MIME type was: ${file.mimetype}');
        console.log('⚠️ Upload: Accepting file based on extension');
        cb(null, true);
      } else {
        console.log('❌ Upload: File type rejected:', file.mimetype);
        console.log('❌ Upload: Allowed types:', allowedMimeTypes);
        cb(new Error(`Invalid file type: ${file.mimetype}. Only images (JPEG, PNG, GIF, WebP) and videos (MP4, WebM, AVI, MOV, MKV) are allowed.`), false);
      }
    }
  }
});

// POST /api/upload/image - Upload image to Cloudinary
router.post('/image', verifyToken, upload.single('image'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No image file uploaded' });
    }

    console.log('📸 Upload: Starting image upload to Cloudinary...');
    console.log('📸 Upload: File:', req.file.originalname, 'Size:', req.file.size);
    console.log('📸 Upload: MIME type:', req.file.mimetype);

    // **NEW: Additional file validation**
    if (!req.file.mimetype.startsWith('image/')) {
      return res.status(400).json({ 
        error: 'Invalid file type',
        details: `File must be an image, got: ${req.file.mimetype}`,
        allowedTypes: ['image/jpeg', 'image/png', 'image/gif', 'image/webp']
      });
    }

    // Upload to Cloudinary
    const result = await cloudinary.uploader.upload(req.file.path, {
      resource_type: 'image',
      folder: req.body.folder || 'snehayog/ads/images',
      transformation: [
        { quality: 'auto:good' },
        { fetch_format: 'auto' }
      ]
    });

    // Clean up temp file
    if (fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
      console.log('✅ Upload: Temporary file cleaned up');
    }

    console.log('✅ Upload: Image uploaded successfully to Cloudinary');
    console.log('📸 Upload: Cloudinary URL:', result.secure_url);

    res.json({
      success: true,
      url: result.secure_url,
      public_id: result.public_id,
      width: result.width,
      height: result.height,
      format: result.format,
      size: result.bytes
    });

  } catch (error) {
    console.error('❌ Upload: Image upload error:', error);
    
    // Clean up temp file if it exists
    if (req.file?.path && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }
    
    res.status(500).json({ 
      error: 'Failed to upload image',
      details: error.message 
    });
  }
}, (error, req, res, next) => {
  // **NEW: Handle multer errors specifically**
  console.error('❌ Upload: Multer error:', error);
  
  if (error instanceof multer.MulterError) {
    if (error.code === 'LIMIT_FILE_SIZE') {
      return res.status(400).json({ 
        error: 'File too large',
        details: 'File size exceeds the 100MB limit'
      });
    }
  }
  
  if (error.message.includes('Invalid file type')) {
    return res.status(400).json({ 
      error: 'Invalid file type',
      details: error.message,
      allowedTypes: ['image/jpeg', 'image/png', 'image/gif', 'image/webp', 'video/mp4', 'video/webm', 'video/avi', 'video/mov', 'video/mkv']
    });
  }
  
  res.status(400).json({ 
    error: 'File upload error',
    details: error.message 
  });
});

// POST /api/upload/video - Upload video to Cloudinary with custom streaming profiles
router.post('/video', verifyToken, upload.single('video'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No video file uploaded' });
    }

    console.log('🎬 Upload: Starting video upload to Cloudinary...');
    console.log('🎬 Upload: File:', req.file.originalname, 'Size:', req.file.size);

    // Determine streaming profile based on request or auto-detect
    const profileName = req.body.profile || 'portrait_reels';
    const streamingProfile = STREAMING_PROFILES[profileName.toUpperCase()] || STREAMING_PROFILES.PORTRAIT_REELS;
    
    console.log('🎬 Upload: Using streaming profile:', profileName);

    // Upload to Cloudinary with custom streaming profile
    const result = await cloudinary.uploader.upload(req.file.path, {
      resource_type: 'video',
      folder: req.body.folder || 'snehayog/ads/videos',
      
      // HLS streaming configuration - Fixed for Cloudinary compatibility
      eager: [
        {
          streaming_profile: 'hd',
          format: 'm3u8'
        },
        {
          streaming_profile: 'sd',
          format: 'm3u8'
        }
      ],
      
      eager_async: true,
      eager_notification_url: req.body.notification_url,
      
      // Video optimization settings
      overwrite: true,
      invalidate: true,
      
      // Metadata for better organization
      context: {
        profile: profileName,
        segment_duration: HLS_CONFIG.segment_duration,
        keyframe_interval: HLS_CONFIG.keyframe_interval,
        abr_enabled: HLS_CONFIG.abr_enabled
      }
    });

    // Clean up temp file
    if (fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
      console.log('✅ Upload: Temporary file cleaned up');
    }

    console.log('✅ Upload: Video uploaded successfully to Cloudinary');
    console.log('🎬 Upload: Cloudinary URL:', result.secure_url);
    console.log('🎬 Upload: Public ID:', result.public_id);

    // Generate HLS streaming URLs
    const hlsUrls = {
      master_playlist: getMasterPlaylistUrl(result.public_id, profileName),
      hls_stream: getHLSStreamingUrl(result.public_id, profileName),
      thumbnail: getVideoThumbnailUrl(result.public_id, 400, 600)
    };

    // Get individual quality URLs for fallback - Fixed for Cloudinary compatibility
    const qualityUrls = [
      {
        quality: '1080x1920',
        bitrate: '3.5m',
        url: `https://res.cloudinary.com/${process.env.CLOUD_NAME}/video/upload/sp_hd/${result.public_id}.m3u8`
      },
      {
        quality: '720x1280',
        bitrate: '1.8m',
        url: `https://res.cloudinary.com/${process.env.CLOUD_NAME}/video/upload/sp_sd/${result.public_id}.m3u8`
      }
    ];

    res.json({
      success: true,
      url: result.secure_url,
      public_id: result.public_id,
      width: result.width,
      height: result.height,
      format: result.format,
      duration: result.duration,
      size: result.bytes,
      thumbnail_url: result.thumbnail_url,
      
      // HLS streaming information
      streaming_profile: profileName,
      hls_urls: hlsUrls,
      quality_urls: qualityUrls,
      
      // Streaming configuration
      segment_duration: HLS_CONFIG.segment_duration,
      keyframe_interval: HLS_CONFIG.keyframe_interval,
      abr_enabled: HLS_CONFIG.abr_enabled,
      
      // Eager transformations (if completed)
      eager: result.eager || [],
      
      // Additional metadata
      context: result.context,
      created_at: result.created_at
    });

  } catch (error) {
    console.error('❌ Upload: Video upload error:', error);
    
    // Clean up temp file if it exists
    if (req.file?.path && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }
    
    res.status(500).json({ 
      error: 'Failed to upload video',
      details: error.message 
    });
  }
});

// POST /api/upload/video-hls - Upload video with HLS streaming profile
router.post('/video-hls', verifyToken, upload.single('video'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No video file uploaded' });
    }

    console.log('🎬 Upload: Starting HLS video upload to Cloudinary...');
    console.log('🎬 Upload: File:', req.file.originalname, 'Size:', req.file.size);

    // Force portrait reels profile for HLS
    const profileName = 'portrait_reels';
    const streamingProfile = STREAMING_PROFILES.PORTRAIT_REELS;
    
    console.log('🎬 Upload: Using HLS streaming profile:', profileName);

    // Upload with HLS-specific transformations
    const result = await cloudinary.uploader.upload(req.file.path, {
      resource_type: 'video',
      folder: req.body.folder || 'snehayog/ads/videos/hls',
      
      // HLS format with eager transformations - Fixed for Cloudinary compatibility
      eager: [
        {
          streaming_profile: 'hd',
          format: 'm3u8'
        },
        {
          streaming_profile: 'sd',
          format: 'm3u8'
        }
      ],
      
      eager_async: true,
      eager_notification_url: req.body.notification_url,
      
      // Video optimization
      overwrite: true,
      invalidate: true,
      
      // Metadata
      context: {
        profile: 'hls_portrait_reels',
        segment_duration: 2,
        keyframe_interval: 60,
        abr_enabled: true,
        aspect_ratio: '9:16',
        optimized_for: 'mobile_scrolling'
      }
    });

    // Clean up temp file
    if (fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
      console.log('✅ Upload: Temporary file cleaned up');
    }

    console.log('✅ Upload: HLS video uploaded successfully to Cloudinary');
    console.log('🎬 Upload: Public ID:', result.public_id);

    // Generate HLS URLs
    const hlsUrls = {
      master_playlist: getMasterPlaylistUrl(result.public_id, 'portrait_reels'),
      hls_stream: getHLSStreamingUrl(result.public_id, 'portrait_reels'),
      thumbnail: getVideoThumbnailUrl(result.public_id, 400, 600)
    };

    res.json({
      success: true,
      public_id: result.public_id,
      hls_urls: hlsUrls,
      
      // Streaming configuration
      segment_duration: 2,
      keyframe_interval: 60,
      abr_enabled: true,
      aspect_ratio: '9:16',
      
      // Quality levels
      quality_levels: [
        { resolution: '1080x1920', bitrate: '3.5m', profile: 'hd' },
        { resolution: '720x1280', bitrate: '1.8m', profile: 'hd' },
        { resolution: '480x854', bitrate: '0.9m', profile: 'sd' },
        { resolution: '360x640', bitrate: '0.6m', profile: 'sd' }
      ],
      
      // Eager transformations
      eager: result.eager || [],
      
      // Metadata
      context: result.context,
      created_at: result.created_at
    });

  } catch (error) {
    console.error('❌ Upload: HLS video upload error:', error);
    
    // Clean up temp file if it exists
    if (req.file?.path && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }
    
    res.status(500).json({ 
      error: 'Failed to upload HLS video',
      details: error.message 
    });
  }
});

// GET /api/upload/video-streaming-urls - Get streaming URLs for existing video
router.get('/video-streaming-urls/:publicId', verifyToken, async (req, res) => {
  try {
    const { publicId } = req.params;
    const profileName = req.query.profile || 'portrait_reels';

    console.log('🎬 Streaming: Getting URLs for video:', publicId);
    console.log('🎬 Streaming: Profile:', profileName);

    // Generate streaming URLs
    const streamingUrls = {
      master_playlist: getMasterPlaylistUrl(publicId, profileName),
      hls_stream: getHLSStreamingUrl(publicId, profileName),
      thumbnail: getVideoThumbnailUrl(publicId, 400, 600),
      original: `https://res.cloudinary.com/${process.env.CLOUD_NAME}/video/upload/${publicId}.mp4`
    };

    res.json({
      success: true,
      public_id: publicId,
      profile: profileName,
      streaming_urls: streamingUrls,
      configuration: {
        segment_duration: HLS_CONFIG.segment_duration,
        keyframe_interval: HLS_CONFIG.keyframe_interval,
        abr_enabled: HLS_CONFIG.abr_enabled
      }
    });

  } catch (error) {
    console.error('❌ Streaming: Error getting streaming URLs:', error);
    res.status(500).json({ 
      error: 'Failed to get streaming URLs',
      details: error.message 
    });
  }
});

// DELETE /api/upload/delete - Delete media from Cloudinary
router.delete('/delete', verifyToken, async (req, res) => {
  try {
    const { public_id, resource_type } = req.body;

    if (!public_id || !resource_type) {
      return res.status(400).json({ 
        error: 'Missing required fields: public_id and resource_type' 
      });
    }

    console.log('🗑️ Upload: Deleting media from Cloudinary...');
    console.log('🗑️ Upload: Public ID:', public_id, 'Type:', resource_type);

    // Delete from Cloudinary
    const result = await cloudinary.uploader.destroy(public_id, { 
      resource_type: resource_type 
    });

    console.log('✅ Upload: Media deleted successfully from Cloudinary');

    res.json({
      success: true,
      message: 'Media deleted successfully',
      result: result
    });

  } catch (error) {
    console.error('❌ Upload: Media deletion error:', error);
    res.status(500).json({ 
      error: 'Failed to delete media',
      details: error.message 
    });
  }
});

export default router;
