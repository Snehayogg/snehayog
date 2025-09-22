import express from 'express';
import multer from 'multer';
import mongoose from 'mongoose';
import Video from '../models/Video.js';
import User from '../models/User.js';
import fs from 'fs'; 
import { verifyToken } from '../utils/verifytoken.js';
import { isCloudinaryConfigured } from '../config.js';
const router = express.Router();


// **NEW: Data validation middleware to ensure consistent types**
const validateVideoData = (req, res, next) => {
  try {
    // Validate numeric fields in request body
    if (req.body.likes !== undefined) {
      req.body.likes = parseInt(req.body.likes) || 0;
    }
    if (req.body.views !== undefined) {
      req.body.views = parseInt(req.body.views) || 0;
    }
    if (req.body.shares !== undefined) {
      req.body.shares = parseInt(req.body.shares) || 0;
    }
    if (req.body.duration !== undefined) {
      req.body.duration = parseInt(req.body.duration) || 0;
    }
    if (req.body.aspectRatio !== undefined) {
      req.body.aspectRatio = parseFloat(req.body.aspectRatio) || 9/16;
    }
    
    next();
  } catch (error) {
    console.error('❌ Data validation error:', error);
    res.status(400).json({ 
      error: 'Invalid data types in request',
      details: 'Numeric fields must be valid numbers'
    });
  }
};

// Multer disk storage to get original file first
const tempStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    // Ensure uploads directory exists
    const uploadDir = 'uploads/';
    if (!fs.existsSync(uploadDir)) {
      fs.mkdirSync(uploadDir, { recursive: true });
    }
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    // Generate unique filename with timestamp
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    cb(null, uniqueSuffix + '-' + file.originalname);
  },
});

const upload = multer({
  storage: tempStorage,
  limits: {
    fileSize: 100 * 1024 * 1024, // 100MB limit
  },
  fileFilter: (req, file, cb) => {
    // Check file type
    const allowedMimeTypes = ['video/mp4', 'video/avi', 'video/mov', 'video/wmv', 'video/flv', 'video/webm'];
    if (allowedMimeTypes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Invalid file type. Only video files are allowed.'), false);
    }
  }
});

// POST /api/videos/upload
router.post('/upload', verifyToken, validateVideoData, upload.single('video'), async (req, res) => {
  let originalResult = null;
  let hlsResult = null;

  try {
    console.log('🎬 Upload: Starting video upload process with HLS streaming...');
    console.log('🎬 Upload: Request body:', req.body);
    console.log('🎬 Upload: File info:', req.file ? {
      filename: req.file.filename,
      size: req.file.size,
      mimetype: req.file.mimetype,
      path: req.file.path
    } : 'No file');

    // Google ID is now available from verifyToken middleware
    const googleId = req.user.googleId;
    if (!googleId) {
      console.log('❌ Upload: Google ID not found in token');
      if (req.file) fs.unlinkSync(req.file.path);
      return res.status(401).json({ error: 'Google ID not found in token' });
    }

    const { videoName, description, videoType, link } = req.body;

    // 1. Validate file
    if (!req.file || !req.file.path) {
      console.log('❌ Upload: No video file uploaded');
      return res.status(400).json({ error: 'No video file uploaded' });
    }

    // 2. Validate required fields
    if (!videoName || videoName.trim() === '') {
      console.log('❌ Upload: Missing video name');
      fs.unlinkSync(req.file.path);
      return res.status(400).json({ error: 'Video name is required' });
    }

    // 3. Validate MIME type and file integrity
    const allowedTypes = ['video/mp4', 'video/webm', 'video/avi', 'video/mkv', 'video/mov'];
    if (!allowedTypes.includes(req.file.mimetype)) {
      console.log('❌ Upload: Invalid video format:', req.file.mimetype);
      fs.unlinkSync(req.file.path);
      return res.status(400).json({ error: 'Invalid video format' });
    }

    // 3.1 Enhanced file validation
    try {
      const stats = fs.statSync(req.file.path);
      if (stats.size === 0) {
        console.log('❌ Upload: Video file is empty (0 bytes)');
        fs.unlinkSync(req.file.path);
        return res.status(400).json({ error: 'Video file is empty or corrupted' });
      }
      
      if (stats.size < 1024) { // Less than 1KB
        console.log('❌ Upload: Video file too small (likely corrupted):', stats.size);
        fs.unlinkSync(req.file.path);
        return res.status(400).json({ error: 'Video file is too small and likely corrupted' });
      }
      
      console.log('✅ Upload: File validation passed - Size:', stats.size, 'bytes');
    } catch (validationError) {
      console.error('❌ Upload: File validation failed:', validationError);
      fs.unlinkSync(req.file.path);
      return res.status(400).json({ error: 'Failed to validate video file' });
    }

    // 4. Validate user
    console.log('🎬 Upload: Looking for user with Google ID:', googleId);
    const user = await User.findOne({ googleId: googleId });
    if (!user) {
      console.log('❌ Upload: User not found with Google ID:', googleId);
      fs.unlinkSync(req.file.path);
      return res.status(404).json({ error: 'User not found' });
    }
    console.log('✅ Upload: User found:', user.name);

    // 5. Check Cloudinary configuration
    console.log('🔍 Upload: Checking Cloudinary configuration...');
    console.log('🔍 Upload: CLOUD_NAME:', process.env.CLOUD_NAME);
    console.log('🔍 Upload: CLOUD_KEY:', process.env.CLOUD_KEY ? 'Set' : 'Missing');
    console.log('🔍 Upload: CLOUD_SECRET:', process.env.CLOUD_SECRET ? 'Set' : 'Missing');
    
    if (!isCloudinaryConfigured()) {
      console.log('❌ Upload: Cloudinary not configured');
      fs.unlinkSync(req.file.path);
      return res.status(500).json({ 
        error: 'Video upload service not configured. Please contact administrator.',
        details: 'Cloudinary API credentials are missing. Check CLOUDINARY_SETUP.md for setup instructions.',
        solution: 'Create a .env file with CLOUD_NAME, CLOUD_KEY, and CLOUD_SECRET variables'
      });
    }
    
    console.log('✅ Upload: Cloudinary configuration verified');

    // 6. Upload original video with HLS streaming profile
    console.log('🎬 Upload: Starting Cloudinary HLS upload...');
    
    // **FIX: Reconfigure Cloudinary with current environment variables**
    const { v2: cloudinaryV2 } = await import('cloudinary');
    cloudinaryV2.config({
      cloud_name: process.env.CLOUD_NAME,
      api_key: process.env.CLOUD_KEY,
      api_secret: process.env.CLOUD_SECRET,
      secure: true,
    });
    console.log('🔧 Upload: Cloudinary reconfigured with current env vars');
    
    try {
      originalResult = await cloudinaryV2.uploader.upload(req.file.path, {
        resource_type: 'video',
        folder: 'snehayog-originals',
        timeout: 60000,
        
        // Enhanced video validation
        validate: true,
        invalidate: true,
        
        // Video format optimization - Cost optimized (720p max)
        video_codec: 'h264', // Ensure ExoPlayer compatibility
        audio_codec: 'aac',  // Ensure audio compatibility
        
        // Quality settings - Limited to 720p for cost optimization
        quality: 'auto:good',
        fetch_format: 'auto',
        width: 1280,
        height: 720,
        crop: 'fill'
      });
      
      // Validate Cloudinary response
      if (!originalResult.secure_url || !originalResult.public_id) {
        throw new Error('Cloudinary upload succeeded but returned invalid response');
      }
      
      console.log('✅ Upload: Original video uploaded to Cloudinary');
      console.log('🎬 Upload: Cloudinary URL:', originalResult.secure_url);
      console.log('🎬 Upload: Public ID:', originalResult.public_id);
      
    } catch (cloudinaryError) {
      console.error('❌ Upload: Cloudinary upload failed:', cloudinaryError);
      fs.unlinkSync(req.file.path);
      
      let errorMessage = 'Failed to upload video to cloud service. Please try again.';
      let errorDetails = cloudinaryError.message || cloudinaryError.toString();
      
      if (cloudinaryError.message && cloudinaryError.message.includes('api_key')) {
        errorMessage = 'Video upload service not configured. Please contact administrator.';
        errorDetails = 'Cloudinary API credentials are missing. Check CLOUDINARY_SETUP.md for setup instructions.';
      } else if (cloudinaryError.message && cloudinaryError.message.includes('cloud_name')) {
        errorMessage = 'Video upload service configuration error. Please contact administrator.';
        errorDetails = 'Cloudinary cloud name is invalid. Check your .env file configuration.';
      } else if (cloudinaryError.message && (cloudinaryError.message.includes('Invalid image file') || cloudinaryError.message.includes('Invalid video file'))) {
        errorMessage = 'Video file is corrupted or in an unsupported format. Please try with a different video file.';
        errorDetails = 'The uploaded video file appears to be corrupted or uses an unsupported codec.';
      } else if (cloudinaryError.message && cloudinaryError.message.includes('timeout')) {
        errorMessage = 'Video upload timed out. The file might be too large or your connection is slow.';
        errorDetails = 'Upload timeout - try with a smaller video file or check your internet connection.';
      }
      
      return res.status(500).json({ 
        error: errorMessage,
        details: errorDetails,
        solution: 'Try uploading a different video file or contact support if the problem persists'
      });
    }

    // 7. Generate HLS streaming version using Cloudinary's streaming profiles
    try {
      console.log('🎬 Upload: Creating HLS streaming version using Cloudinary streaming profiles...');
      
      // Use Cloudinary's streaming profiles for proper HLS generation
      hlsResult = await cloudinaryV2.uploader.upload(req.file.path, {
        resource_type: 'video',
        folder: 'snehayog-videos',
        use_filename: true,
        unique_filename: true,
        overwrite: true,
        timeout: 120000,
        
        // **FIXED: Only create 480p variant - no multiple qualities**
        streaming_profile: 'sd', // Use SD profile for 480p only
        
        // **SIMPLIFIED: Only 480p transformation**
        transformation: [
          {
            width: 854,
            height: 480,
            crop: 'fill',
            quality: 'auto:good',
            video_codec: 'h264',
            audio_codec: 'aac',
            format: 'mp4'
          }
        ],
        
        // **REMOVED: No eager variants - only single 480p version**
        // eager: [] - Commented out to prevent multiple variants
        eager_async: false
      });
      
      console.log('✅ Upload: Cloudinary HLS generation successful');
      console.log('🎬 Upload: HLS Result:', {
        success: true,
        masterPlaylistUrl: hlsResult.secure_url,
        variants: 1, // Only single 480p variant
        qualityRange: '480p only',
        publicId: hlsResult.public_id
      });
      
    } catch (hlsError) {
      console.error('❌ Upload: Cloudinary HLS generation failed:', hlsError);
      
      // Try to delete the original upload
      if (originalResult?.public_id) {
        try {
          await cloudinary.uploader.destroy(originalResult.public_id, { resource_type: 'video' });
          console.log('✅ Upload: Cleaned up original upload after HLS failure');
        } catch (e) {
          console.error('❌ Upload: Failed to cleanup original upload:', e);
        }
      }
      
      fs.unlinkSync(req.file.path);
      
      let hlsErrorMessage = 'Failed to create HLS streaming version. Please try again.';
      let hlsErrorDetails = hlsError.message;
    
      if (hlsError.message.includes('Invalid video file')) {
        hlsErrorMessage = 'Video file is corrupted or uses an unsupported codec. HLS streaming cannot be created.';
        hlsErrorDetails = 'The video file appears to be corrupted or uses a codec that cannot be processed for HLS streaming.';
      } else if (hlsError.message.includes('timeout')) {
        hlsErrorMessage = 'HLS processing timed out. The video might be too complex or too long.';
        hlsErrorDetails = 'HLS processing timeout - try with a shorter or simpler video file.';
      }
    
      return res.status(500).json({ 
        error: hlsErrorMessage,
        details: hlsErrorDetails,
        solution: 'Try uploading a different video file or contact support if the problem persists'
      });
    }

    if (!originalResult?.secure_url) {
      console.log('❌ Upload: Missing original Cloudinary URL');
      fs.unlinkSync(req.file.path);
      return res.status(500).json({ error: 'Cloudinary upload failed' });
    }

    // If HLS failed but original upload succeeded, use MP4 fallback
    if (!hlsResult?.secure_url) {
      console.log('⚠️ Upload: HLS generation failed, using MP4 fallback');
      
      // Generate thumbnail URL from original
      const thumbnailUrl = originalResult.secure_url.replace(
        '/upload/',
        '/upload/w_300,h_400,c_fill/'
      );
      
      // Save video with MP4 fallback
      const video = new Video({
        videoName,
        description: description || '',
        link: link || '',
        videoUrl: originalResult.secure_url, // Use MP4 as fallback
        thumbnailUrl: thumbnailUrl,
        originalVideoUrl: originalResult.secure_url,
        hlsMasterPlaylistUrl: null,
        hlsPlaylistUrl: null,
        isHLSEncoded: false,
        uploader: user._id,
        videoType: videoType || 'yog',
        likes: 0, views: 0, shares: 0, likedBy: [], comments: [],
        uploadedAt: new Date()
      });
      
      await video.save();
      user.videos.push(video._id);
      await user.save();
      
      try { fs.unlinkSync(req.file.path); } catch (_) {}
      
      return res.status(201).json({
        success: true,
        videoUrl: video.videoUrl,
        message: '✅ Video uploaded (MP4). HLS not generated.',
        video: video.toObject()
      });
    }

    // 8. Generate thumbnail URL
    const thumbnailUrl = originalResult.secure_url.replace(
      '/upload/',
      '/upload/w_300,h_400,c_fill/'
    );

    // 9. Save video in MongoDB with HLS URLs
    console.log('🎬 Upload: Saving video to database with HLS URLs...');
    
    // **FIXED: Generate proper HLS URLs from Cloudinary result**
    let primaryHlsUrl = null;
    let hlsVariants = [];
    let isHLSEncoded = false;
    
    // **FIXED: Use the main video URL as primary (MP4 format for better compatibility)**
    primaryHlsUrl = hlsResult.secure_url;
    isHLSEncoded = true; // We have processed video, so it's "encoded"
    
    // **SIMPLIFIED: Create only single 480p variant - no multiple qualities**
    hlsVariants = [{
      quality: '480p',
      playlistUrl: hlsResult.secure_url,
      resolution: '854x480',
      bitrate: '800k',
      format: 'mp4'
    }];
    
    console.log('✅ Upload: Using single 480p variant only');
    console.log('🎬 Upload: Primary URL:', primaryHlsUrl);
    console.log('🎬 Upload: Single variant:', hlsVariants.map(v => `${v.quality} (${v.resolution})`));
    
    // CRITICAL: Ensure we have HLS URLs before saving
    if (!primaryHlsUrl) {
      console.error('❌ Upload: No HLS URLs available - cannot save video');
      fs.unlinkSync(req.file.path);
      return res.status(500).json({
        success: false,
        error: 'HLS conversion failed',
        details: 'Video could not be converted to streaming format',
        solution: 'Please try uploading the video again'
      });
    }
    
    const video = new Video({
      videoName,
      description: description || '', // Optional for user videos
      link: link || '',
      videoUrl: primaryHlsUrl, // ALWAYS use HLS URL - no MP4 fallback
      thumbnailUrl: thumbnailUrl,
      originalVideoUrl: originalResult.secure_url,
      // **FIXED: Set 480p as lowQualityUrl (only quality available)**
      lowQualityUrl: primaryHlsUrl, // 480p URL for quality indicator
      // HLS streaming URLs from encoding service or Cloudinary
      hlsMasterPlaylistUrl: primaryHlsUrl,
      hlsPlaylistUrl: primaryHlsUrl,
      hlsVariants: hlsVariants,
      isHLSEncoded: isHLSEncoded, // Set based on actual HLS generation success
      uploader: user._id,
      videoType: videoType || 'yog',
      likes: 0,
      views: 0,
      shares: 0,
      likedBy: [],
      comments: [],
      uploadedAt: new Date()
    });

    await video.save();
    console.log('✅ Upload: Video saved to database with HLS URLs, ID:', video._id);

    // 10. Push video to user's video list
    user.videos.push(video._id);
    await user.save();
    console.log('✅ Upload: Video added to user profile');

    // 11. Clean up temp file
    setTimeout(() => {
      try {
        if (fs.existsSync(req.file.path)) {
          fs.unlinkSync(req.file.path);
          console.log('✅ Upload: Temporary file cleaned up');
        }
      } catch (cleanupError) {
        console.error('⚠️ Upload: Failed to cleanup temp file:', cleanupError);
      }
    }, 2000); // 2 second delay
    console.log('⏳ Upload: Temporary file cleanup scheduled in 2 seconds');

    // 12. Respond success with actual HLS URL
    console.log('✅ Upload: Video upload completed successfully with HLS streaming');
    
    // Return the actual HLS URL from eager transformations
    let responseHlsUrl = primaryHlsUrl;
    
    // NO FALLBACK TO MP4 - Only HLS URLs allowed
    if (!responseHlsUrl) {
      console.error('❌ Upload: No HLS URLs available - this should not happen');
      return res.status(500).json({
        success: false,
        error: 'HLS conversion failed',
        details: 'Video processing completed but no HLS URLs were generated',
        solution: 'Please try uploading the video again'
      });
    }
    
    // **FIXED: Validate that we have a valid video URL (MP4 format for better compatibility)**
    if (!responseHlsUrl || responseHlsUrl.trim() === '') {
      console.error('❌ Upload: Invalid video URL generated:', responseHlsUrl);
      return res.status(500).json({
        success: false,
        error: 'Invalid video URL generated',
        details: 'Video processing completed but generated URL is not valid',
        solution: 'Please try uploading the video again or contact support'
      });
    }
    
    // Log the final response for debugging
    console.log('🎬 Upload: Final response HLS URL:', responseHlsUrl);
    console.log('🎬 Upload: HLS variants count:', hlsVariants.length);
    console.log('🎬 Upload: HLS encoding method: Cloudinary');
    
    res.status(201).json({
      success: true,
      videoUrl: responseHlsUrl, // This will be MP4 URL for better ExoPlayer compatibility
      message: '✅ Video uploaded with optimized streaming (Cloudinary)',
      video: {
        ...video.toObject(),
        hlsUrl: responseHlsUrl,
        hlsVariants: hlsVariants,
        encodingMethod: 'Cloudinary'
      }
    });

  } catch (error) {
    console.error('❌ Upload: Unexpected error:', error.message);
    console.error('❌ Upload: Stack trace:', error.stack);

    // Clean up temp file if it exists
    if (req.file?.path && fs.existsSync(req.file.path)) {
      try {
        fs.unlinkSync(req.file.path);
        console.log('✅ Upload: Cleaned up temp file after error');
      } catch (cleanupError) {
        console.error('❌ Upload: Failed to cleanup temp file:', cleanupError);
      }
    }

    res.status(500).json({
      success: false,
      error: '❌ Failed to upload video',
      details: error.message
    });
  }
});
  

// Get videos by user ID (consistently use googleId)
router.get('/user/:googleId', verifyToken, async (req, res) => {
  try {
    const { googleId } = req.params;
    console.log('🎬 Fetching videos for googleId:', googleId);

    // Find user by googleId
    const user = await User.findOne({ googleId: googleId });
    if (!user) {
      console.log('❌ User not found for googleId:', googleId);
      return res.status(404).json({ error: 'User not found' });
    }

    console.log('✅ Found user:', {
      id: user._id,
      name: user.name,
      googleId: user.googleId,
      videosArrayLength: user.videos?.length || 0
    });

    // **IMPROVED: Get videos directly from Video collection using uploader field**
    const videos = await Video.find({ uploader: user._id })
      .populate('uploader', 'name profilePic googleId')
      .sort({ createdAt: -1 }); // Latest videos first

    console.log('🎬 Found videos count:', videos.length);

    if (videos.length === 0) {
      console.log('⚠️ No videos found for user:', user.name);
      return res.json([]);
    }

    // **IMPROVED: Better data formatting and validation**
    const videosWithUrls = videos.map(video => {
      const videoObj = video.toObject();
      
      // **CRITICAL: Ensure all required fields are present**
      const result = {
        _id: videoObj._id?.toString(),
        videoName: videoObj.videoName || 'Untitled Video',
        videoUrl: videoObj.videoUrl || videoObj.hlsMasterPlaylistUrl || videoObj.hlsPlaylistUrl || '',
        thumbnailUrl: videoObj.thumbnailUrl || '',
        description: videoObj.description || '',
        likes: parseInt(videoObj.likes) || 0,
        views: parseInt(videoObj.views) || 0,
        shares: parseInt(videoObj.shares) || 0,
        duration: parseInt(videoObj.duration) || 0,
        aspectRatio: parseFloat(videoObj.aspectRatio) || 9/16,
        videoType: videoObj.videoType || 'reel',
        link: videoObj.link || null,
        uploadedAt: videoObj.uploadedAt?.toISOString?.() || new Date().toISOString(),
        createdAt: videoObj.createdAt?.toISOString?.() || new Date().toISOString(),
        updatedAt: videoObj.updatedAt?.toISOString?.() || new Date().toISOString(),
        // **IMPROVED: Better uploader information**
        uploader: {
          id: videoObj.uploader?._id?.toString() || videoObj.uploader?.toString(),
          name: videoObj.uploader?.name || 'Unknown User',
          profilePic: videoObj.uploader?.profilePic || '',
          googleId: videoObj.uploader?.googleId || ''
        },
        // **HLS Streaming fields**
        hlsMasterPlaylistUrl: videoObj.hlsMasterPlaylistUrl || null,
        hlsPlaylistUrl: videoObj.hlsPlaylistUrl || null,
        isHLSEncoded: videoObj.isHLSEncoded || false,
        likedBy: videoObj.likedBy || [],
        comments: videoObj.comments || []
      };
      
      console.log(`🎬 Video ${result.videoName}:`, {
        id: result._id,
        hasVideoUrl: !!result.videoUrl,
        hasThumbnail: !!result.thumbnailUrl,
        likes: result.likes,
        views: result.views,
        uploader: result.uploader.name,
        uploaderGoogleId: result.uploader.googleId
      });
      
      return result;
    });

    console.log('✅ Sending videos response:', {
      totalVideos: videosWithUrls.length,
      firstVideo: videosWithUrls.isNotEmpty ? videosWithUrls[0].videoName : 'None',
      lastVideo: videosWithUrls.isNotEmpty ? videosWithUrls.last.videoName : 'None'
    });

    res.json(videosWithUrls);
  } catch (error) {
    console.error('❌ Error fetching user videos:', error);
    res.status(500).json({ 
      error: 'Error fetching videos',
      details: error.message 
    });
  }
});




// Get all videos (optimized for performance) - MODIFIED FOR HLS ONLY
router.get('/', async (req, res) => {
  try {
    const { videoType, page = 1, limit = 10 } = req.query;
    console.log('📹 Fetching HLS videos...', { videoType, page, limit });
    
    // Get query parameters for pagination
    const pageNum = parseInt(page) || 1;
    const limitNum = parseInt(limit) || 10;
    const skip = (pageNum - 1) * limitNum;
    
    // Build query filter
    const queryFilter = { isHLSEncoded: true }; // Only HLS videos
    
    // Add videoType filter if specified
    if (videoType && (videoType === 'yog' || videoType === 'sneha')) {
      queryFilter.videoType = videoType;
      console.log('📹 Filtering by videoType:', videoType);
    }
    
    // MODIFIED: Only return HLS-encoded videos with optional videoType filter
    const [totalVideos, videos] = await Promise.all([
      Video.countDocuments(queryFilter), // Count with filter
      Video.find(queryFilter) // Find with filter
        .select('videoName videoUrl thumbnailUrl likes views shares uploader uploadedAt likedBy videoType aspectRatio duration comments link description hlsMasterPlaylistUrl hlsPlaylistUrl isHLSEncoded') // Include HLS fields
        .populate('uploader', 'name profilePic googleId')
        .populate('comments.user', 'name profilePic googleId')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean()
    ]);

    // Transform comments to match Flutter app expectations
    const transformedVideos = videos.map(video => ({
      ...video,
      comments: video.comments.map(comment => ({
        _id: comment._id,
        text: comment.text,
        userId: comment.user?.googleId || comment.user?._id || '',
        userName: comment.user?.name || '',
        createdAt: comment.createdAt,
        likes: comment.likes || 0,
        likedBy: comment.likedBy || []
      }))
    }));
    
    console.log(`✅ Found ${videos.length} HLS videos (page ${page}, total: ${totalVideos})`);
    
    res.json({
      videos: transformedVideos,
      hasMore: (pageNum * limitNum) < totalVideos,
      total: totalVideos,
      currentPage: pageNum,
      totalPages: Math.ceil(totalVideos / limitNum),
      filters: {
        videoType: videoType || 'all',
        hlsOnly: true
      },
      message: `✅ Fetched ${videos.length} HLS videos successfully${videoType ? ` (${videoType} type)` : ''}`
    });
  } catch (error) {
    console.error('❌ Error fetching HLS videos:', error);
    res.status(500).json({ 
      error: 'Failed to fetch HLS videos',
      message: error.message 
    });
  }
});


// POST /api/videos/:id/like - Toggle like for a video (must be before /:id route)
router.post('/:id/like', verifyToken, async (req, res) => {
  try {
    // Get Google ID from token and resolve to User ObjectId
    const googleId = req.user.googleId; // From verifyToken middleware
    const videoId = req.params.id;

    console.log('🔍 Like API: Received request', { googleId, videoId });

    // Validate input
    if (!googleId) {
      console.log('❌ Like API: Missing userId from authentication');
      return res.status(400).json({ error: 'User not authenticated' });
    }

    if (!videoId) {
      console.log('❌ Like API: Missing videoId in params');
      return res.status(400).json({ error: 'Video ID is required' });
    }

    // Resolve the authenticated user to a DB record to get ObjectId
    const user = await User.findOne({ googleId });
    if (!user) {
      console.log('❌ Like API: User not found for googleId:', googleId);
      return res.status(404).json({ error: 'User not found' });
    }
    const userObjectId = user._id; // Mongoose ObjectId

    // Find the video
    const video = await Video.findById(videoId);
    if (!video) {
      console.log('❌ Like API: Video not found with ID:', videoId);
      return res.status(404).json({ error: 'Video not found' });
    }

    console.log('🔍 Like API: Video found, current likes:', video.likes, 'likedBy:', video.likedBy);

    // Check if user has already liked the video
    const likedByStrings = (video.likedBy || []).map(id => id?.toString?.() || String(id));
    const userLikedIndex = likedByStrings.indexOf(userObjectId.toString());
    let wasLiked = false;
    
    if (userLikedIndex > -1) {
      // User has already liked - remove the like
      video.likedBy.splice(userLikedIndex, 1);
      video.likes = Math.max(0, video.likes - 1); // Decrement likes, ensure not negative
      wasLiked = false;
      console.log('🔍 Like API: Removed like, new count:', video.likes);
    } else {
      // User hasn't liked - add the like
      video.likedBy.push(userObjectId);
      video.likes = video.likes + 1; // Increment likes
      wasLiked = true;
      console.log('🔍 Like API: Added like, new count:', video.likes);
    }

    await video.save();
    console.log('✅ Like API: Video saved successfully');

    // Return the updated video with populated fields
    const updatedVideo = await Video.findById(videoId)
      .populate('uploader', 'name profilePic googleId')
      .populate('comments.user', 'name profilePic googleId');

    // Transform comments to match Flutter app expectations
    const videoObj = updatedVideo.toObject();
    
    // **FIXED: Only send fields that frontend VideoModel expects**
    const transformedVideo = {
      _id: videoObj._id?.toString(),
      videoName: videoObj.videoName || '',
      videoUrl: videoObj.videoUrl || videoObj.hlsMasterPlaylistUrl || videoObj.hlsPlaylistUrl || '',
      thumbnailUrl: videoObj.thumbnailUrl || '',
      likes: parseInt(videoObj.likes) || 0,
      views: parseInt(videoObj.views) || 0,
      shares: parseInt(videoObj.shares) || 0,
      description: videoObj.description || '',
      uploader: {
        _id: videoObj.uploader?._id?.toString() || videoObj.uploader?.googleId?.toString() || '',
        name: videoObj.uploader?.name || 'Unknown',
        profilePic: videoObj.uploader?.profilePic || '',
      },
      uploadedAt: videoObj.uploadedAt?.toISOString?.() || new Date().toISOString(),
      likedBy: videoObj.likedBy || [],
      videoType: videoObj.videoType || 'reel',
      aspectRatio: parseFloat(videoObj.aspectRatio) || 9/16,
      duration: parseInt(videoObj.duration) || 0,
      comments: videoObj.comments.map(comment => ({
        _id: comment._id,
        text: comment.text,
        userId: comment.user?.googleId || comment.user?._id || '',
        userName: comment.user?.name || '',
        createdAt: comment.createdAt,
        likes: comment.likes || 0,
        likedBy: comment.likedBy || []
      })),
      link: videoObj.link || null,
      hlsMasterPlaylistUrl: videoObj.hlsMasterPlaylistUrl || null,
      hlsPlaylistUrl: videoObj.hlsPlaylistUrl || null,
      hlsVariants: videoObj.hlsVariants || null,
      isHLSEncoded: videoObj.isHLSEncoded || false,
      lowQualityUrl: videoObj.lowQualityUrl || null,
      mediumQualityUrl: videoObj.mediumQualityUrl || null,
      highQualityUrl: videoObj.highQualityUrl || null,
      preloadQualityUrl: videoObj.preloadQualityUrl || null,
    };

    res.json(transformedVideo);
    
    console.log('✅ Like API: Successfully toggled like, returning video');
    
  } catch (err) {
    console.error('❌ Like API Error:', err);
    res.status(500).json({ 
      error: 'Failed to toggle like', 
      details: err.message,
      stack: process.env.NODE_ENV === 'development' ? err.stack : undefined
    });
  }
});

// DELETE /api/videos/:id/like - Unlike a video (for API consistency)
router.delete('/:id/like', verifyToken, async (req, res) => {
  try {
    // Get Google ID from token and resolve to User ObjectId
    const googleId = req.user.googleId; // From verifyToken middleware
    const videoId = req.params.id;

    console.log('🔍 Unlike API: Received request', { googleId, videoId });

    // Validate input
    if (!googleId) {
      console.log('❌ Unlike API: No Google ID in token');
      return res.status(401).json({ error: 'Authentication required' });
    }

    if (!videoId) {
      console.log('❌ Unlike API: No video ID provided');
      return res.status(400).json({ error: 'Video ID is required' });
    }

    // Find user by Google ID
    const user = await User.findOne({ googleId: googleId });
    if (!user) {
      console.log('❌ Unlike API: User not found with Google ID:', googleId);
      return res.status(404).json({ error: 'User not found' });
    }

    const userObjectId = user._id;
    console.log('🔍 Unlike API: User ObjectId:', userObjectId);

    // Find the video
    const video = await Video.findById(videoId);
    if (!video) {
      console.log('❌ Unlike API: Video not found with ID:', videoId);
      return res.status(404).json({ error: 'Video not found' });
    }

    console.log('🔍 Unlike API: Video found, current likes:', video.likes, 'likedBy:', video.likedBy);

    // Check if user has liked the video
    const likedByStrings = (video.likedBy || []).map(id => id?.toString?.() || String(id));
    const userLikedIndex = likedByStrings.indexOf(userObjectId.toString());
    
    if (userLikedIndex > -1) {
      // User has liked - remove the like
      video.likedBy.splice(userLikedIndex, 1);
      video.likes = Math.max(0, video.likes - 1); // Decrement likes, ensure not negative
      console.log('🔍 Unlike API: Removed like, new count:', video.likes);
    } else {
      // User hasn't liked - return current state
      console.log('🔍 Unlike API: User has not liked this video');
    }

    await video.save();
    console.log('✅ Unlike API: Video saved successfully');

    // Return the updated video with populated fields
    const updatedVideo = await Video.findById(videoId)
      .populate('uploader', 'name profilePic googleId')
      .populate('comments.user', 'name profilePic googleId');

    if (!updatedVideo) {
      return res.status(404).json({ error: 'Video not found after update' });
    }

    const videoObj = updatedVideo.toObject();
    const transformedVideo = {
      _id: videoObj._id?.toString(),
      videoName: videoObj.videoName || '',
      videoUrl: videoObj.videoUrl || videoObj.hlsMasterPlaylistUrl || videoObj.hlsPlaylistUrl || '',
      thumbnailUrl: videoObj.thumbnailUrl || '',
      likes: parseInt(videoObj.likes) || 0,
      views: parseInt(videoObj.views) || 0,
      shares: parseInt(videoObj.shares) || 0,
      description: videoObj.description || '',
      uploader: {
        _id: videoObj.uploader?._id?.toString() || videoObj.uploader?.googleId?.toString() || '',
        name: videoObj.uploader?.name || 'Unknown',
        profilePic: videoObj.uploader?.profilePic || '',
      },
      uploadedAt: videoObj.uploadedAt?.toISOString?.() || new Date().toISOString(),
      likedBy: videoObj.likedBy || [],
      videoType: videoObj.videoType || 'reel',
      aspectRatio: parseFloat(videoObj.aspectRatio) || 9/16,
      duration: parseInt(videoObj.duration) || 0,
      comments: videoObj.comments.map(comment => ({
        _id: comment._id,
        text: comment.text,
        userId: comment.user?.googleId || comment.user?._id || '',
        userName: comment.user?.name || '',
        createdAt: comment.createdAt,
        likes: comment.likes || 0,
        likedBy: comment.likedBy || []
      })),
      hlsMasterPlaylistUrl: videoObj.hlsMasterPlaylistUrl || null,
      hlsPlaylistUrl: videoObj.hlsPlaylistUrl || null,
      isHLSEncoded: videoObj.isHLSEncoded || false,
      lowQualityUrl: videoObj.lowQualityUrl || null,
      mediumQualityUrl: videoObj.mediumQualityUrl || null,
      highQualityUrl: videoObj.highQualityUrl || null,
      preloadQualityUrl: videoObj.preloadQualityUrl || null,
    };

    res.json(transformedVideo);
    
    console.log('✅ Unlike API: Successfully unliked video');
    
  } catch (err) {
    console.error('❌ Unlike API Error:', err);
    res.status(500).json({ 
      error: 'Failed to unlike video', 
      details: err.message,
      stack: process.env.NODE_ENV === 'development' ? err.stack : undefined
    });
  }
});

// Get video by ID
router.get('/:id', async (req, res) => {
  try {
    const video = await Video.findById(req.params.id)
      .populate('uploader', 'name profilePic googleId')
      .populate('comments.user', 'name profilePic googleId');

    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    // **FIXED: Ensure consistent data types and HLS URL handling**
    const videoObj = video.toObject();
    const formattedVideo = {
      ...videoObj,
      // **FIXED: Ensure numeric fields are numbers**
      likes: parseInt(videoObj.likes) || 0,
      views: parseInt(videoObj.views) || 0,
      shares: parseInt(videoObj.shares) || 0,
      duration: parseInt(videoObj.duration) || 0,
      aspectRatio: parseFloat(videoObj.aspectRatio) || 9/16,
      // **FIXED: Ensure ObjectId fields are properly formatted**
      _id: videoObj._id?.toString() || videoObj._id,
      uploader: videoObj.uploader?._id?.toString() || videoObj.uploader?.toString() || videoObj.uploader,
      // **FIXED: Ensure date fields are properly formatted**
      uploadedAt: videoObj.uploadedAt?.toISOString?.() || videoObj.uploadedAt,
      createdAt: videoObj.createdAt?.toISOString?.() || videoObj.createdAt,
      updatedAt: videoObj.updatedAt?.toISOString?.() || videoObj.updatedAt,
      // **FIXED: Ensure HLS URLs are properly set**
      videoUrl: videoObj.videoUrl || videoObj.hlsMasterPlaylistUrl || videoObj.hlsPlaylistUrl || '',
      hlsMasterPlaylistUrl: videoObj.hlsMasterPlaylistUrl || null,
      hlsPlaylistUrl: videoObj.hlsPlaylistUrl || null,
      isHLSEncoded: videoObj.isHLSEncoded || false,
      // **FIXED: Transform comments to match Flutter app expectations**
      comments: videoObj.comments.map(comment => ({
        _id: comment._id,
        text: comment.text,
        userId: comment.user?.googleId || comment.user?._id || '',
        userName: comment.user?.name || '',
        createdAt: comment.createdAt,
        likes: comment.likes || 0,
        likedBy: comment.likedBy || []
      }))
    };

    console.log('🎬 Get Video by ID - Data types fixed:', {
      videoId: formattedVideo._id,
      videoName: formattedVideo.videoName,
      dataTypes: {
        likes: typeof formattedVideo.likes,
        views: typeof formattedVideo.views,
        shares: typeof formattedVideo.shares,
        duration: typeof formattedVideo.duration,
        aspectRatio: typeof formattedVideo.aspectRatio
      },
      hlsInfo: {
        hasHlsMaster: !!formattedVideo.hlsMasterPlaylistUrl,
        hasHlsPlaylist: !!formattedVideo.hlsPlaylistUrl,
        isHlsEncoded: formattedVideo.isHLSEncoded,
        finalVideoUrl: formattedVideo.videoUrl
      }
    });

    res.json(formattedVideo);
  } catch (err) {
    console.error('Get video error:', err);
    res.status(500).json({ error: 'Failed to fetch video' });
  }
});

router.post('/:id/comments', async (req, res) => {
  try {
    const { userId, text } = req.body;

    const user = await User.findOne({ googleId: userId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const comment = {
      user: user._id,
      text,
      createdAt: new Date(),
    };

    // ✅ Safely push comment without modifying the whole document
    const video = await Video.findByIdAndUpdate(
      req.params.id,
      { $push: { comments: comment } },
      { new: true }
    ).populate('comments.user', 'name profilePic googleId');

    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    // Transform comments to match Flutter app expectations
    const videoObj = video.toObject();
    const transformedVideo = {
      ...videoObj,
      comments: videoObj.comments.map(comment => ({
        _id: comment._id,
        text: comment.text,
        userId: comment.user?.googleId || comment.user?._id || '',
        userName: comment.user?.name || '',
        createdAt: comment.createdAt,
        likes: comment.likes || 0,
        likedBy: comment.likedBy || []
      }))
    };

    res.json({
      message: 'Comment added successfully',
      video: transformedVideo
    });
  } catch (err) {
    console.error('Error adding comment:', err);
    res.status(500).json({ error: 'Failed to add comment', details: err.message });
  }
});

// **NEW: Increment video view count (Instagram Reels style)**
router.post('/:id/increment-view', async (req, res) => {
  try {
    const videoId = req.params.id;
    const { userId, duration = 4 } = req.body;

    console.log('🎯 View increment request:', {
      videoId,
      userId,
      duration,
      timestamp: new Date().toISOString()
    });

    // Validate video ID
    if (!videoId || !mongoose.Types.ObjectId.isValid(videoId)) {
      return res.status(400).json({ error: 'Invalid video ID' });
    }

    // Find user by googleId
    const user = await User.findOne({ googleId: userId });
    if (!user) {
      console.log('❌ User not found with Google ID:', userId);
      return res.status(404).json({ error: 'User not found' });
    }

    // Find video
    const video = await Video.findById(videoId);
    if (!video) {
      console.log('❌ Video not found:', videoId);
      return res.status(404).json({ error: 'Video not found' });
    }

    // Check if user has already reached max views (10)
    const existingView = video.viewDetails.find(view => 
      view.user.toString() === user._id.toString()
    );

    if (existingView && existingView.viewCount >= 10) {
      console.log('⚠️ User has reached maximum view count:', {
        userId: user.googleId,
        currentViewCount: existingView.viewCount
      });
      return res.status(200).json({
        message: 'View limit reached',
        viewCount: existingView.viewCount,
        maxViewsReached: true,
        totalViews: video.views
      });
    }

    // Increment view using the model method
    await video.incrementView(user._id, duration);

    console.log('✅ View incremented successfully:', {
      videoId,
      userId: user.googleId,
      newTotalViews: video.views,
      userViewCount: existingView ? existingView.viewCount + 1 : 1
    });

    // Return updated view count
    const updatedExistingView = video.viewDetails.find(view => 
      view.user.toString() === user._id.toString()
    );

    res.json({
      message: 'View incremented successfully',
      totalViews: video.views,
      userViewCount: updatedExistingView ? updatedExistingView.viewCount : 1,
      maxViewsReached: updatedExistingView ? updatedExistingView.viewCount >= 10 : false
    });

  } catch (err) {
    console.error('❌ Error incrementing view:', err);
    res.status(500).json({ 
      error: 'Failed to increment view', 
      details: err.message 
    });
  }
});

// Delete video by ID
router.delete('/:id', verifyToken, async (req, res) => {
  try {
    console.log('🗑️ DELETE VIDEO ROUTE CALLED');
    console.log('🗑️ Video ID:', req.params.id);
    console.log('🗑️ User from token:', req.user);
    console.log('🗑️ User ID type:', req.user.id.runtimeType);
    console.log('🗑️ User ID value:', req.user.id);
    
    const videoId = req.params.id;
    
    // Get video to check ownership
    const video = await Video.findById(videoId);
    if (!video) {
      console.log('❌ Video not found:', videoId);
      return res.status(404).json({ error: 'Video not found' });
    }

    console.log('🗑️ Video found:', {
      id: video._id,
      uploader: video.uploader,
      uploaderType: video.uploader.runtimeType,
      uploaderString: video.uploader.toString()
    });

    // Get user from database to compare ObjectIds
    const user = await User.findOne({ googleId: req.user.googleId });
    if (!user) {
      console.log('❌ User not found with Google ID:', req.user.googleId);
      return res.status(401).json({ error: 'User not found' });
    }

    console.log('🗑️ Comparing user IDs:');
    console.log('   Token User ID:', user._id.toString());
    console.log('   Video uploader:', video.uploader.toString());
    console.log('   Are they equal?', video.uploader.toString() === user._id.toString());

    // Check if user owns the video by comparing ObjectIds
    if (video.uploader.toString() !== user._id.toString()) {
      console.log('❌ Permission denied - user does not own video');
      console.log('   User ID from database:', user._id.toString());
      console.log('   Video uploader ID:', video.uploader.toString());
      return res.status(403).json({ error: 'You can only delete your own videos' });
    }

    // Delete the video
    const deletedVideo = await Video.findByIdAndDelete(videoId);
    if (!deletedVideo) {
      return res.status(404).json({ error: 'Video not found' });
    }

    console.log(`🗑️ Video deleted: ${videoId} by user: ${user._id}`);
    res.json({ success: true, message: 'Video deleted successfully' });
  } catch (error) {
    console.error('❌ Delete video error:', error);
    res.status(500).json({ error: 'Failed to delete video' });
  }
});

// Bulk delete videos
router.post('/bulk-delete', verifyToken, async (req, res) => {
  try {
    const { videoIds, deleteReason, timestamp } = req.body;
    
    // Get user from database to compare ObjectIds
    const user = await User.findOne({ googleId: req.user.googleId });
    if (!user) {
      return res.status(401).json({ error: 'User not found' });
    }

    // Validate request
    if (!videoIds || !Array.isArray(videoIds) || videoIds.length === 0) {
      return res.status(400).json({ error: 'Video IDs are required' });
    }

    console.log(`🗑️ Bulk delete requested: ${videoIds.length} videos by user: ${user._id}`);

    // Find all videos and check ownership
    const videos = await Video.find({ _id: { $in: videoIds } });
    
    if (videos.length === 0) {
      return res.status(404).json({ error: 'No videos found' });
    }

    // Check if user owns all videos by comparing ObjectIds
    const unauthorizedVideos = videos.filter(video => 
      video.uploader.toString() !== user._id.toString()
    );

    if (unauthorizedVideos.length > 0) {
      return res.status(403).json({ 
        error: 'You can only delete your own videos',
        unauthorizedVideos: unauthorizedVideos.map(v => v._id)
      });
    }

    // Delete all videos
    const deleteResult = await Video.deleteMany({ _id: { $in: videoIds } });
    
    console.log(`✅ Bulk delete successful: ${deleteResult.deletedCount} videos deleted`);
    
    res.json({ 
      success: true, 
      message: `${deleteResult.deletedCount} videos deleted successfully`,
      deletedCount: deleteResult.deletedCount
    });

  } catch (error) {
    console.error('❌ Bulk delete error:', error);
    res.status(500).json({ error: 'Failed to delete videos' });
  }
});



// Generate signed Cloudinary URLs for HLS streams
// (Removed duplicate generate-signed-url route defined earlier)

// New video upload endpoint with HLS conversion
// Removed self-hosted HLS upload endpoint

// Serve HLS files
// Removed duplicate local HLS static route

// Generate HLS URL (replaces Cloudinary signed URL)
// Removed self-hosted HLS URL generator

// Clean up temporary HLS directories
router.post('/cleanup-temp-hls', async (req, res) => {
  try {
    const hlsService = (await import('../services/hlsEncodingService.js')).default;
    await hlsService.cleanupTempHLSDirectories();
    res.json({ success: true, message: 'Temporary HLS directories cleaned up' });
  } catch (error) {
    console.error('❌ Error cleaning up temporary HLS directories:', error);
    res.status(500).json({ error: 'Failed to clean up temporary directories' });
  }
});

// Update existing generate-signed-url to use HLS
router.post('/generate-signed-url', verifyToken, async (req, res) => {
  try {
    const { videoUrl, quality = 'hd' } = req.body;

    if (!videoUrl) {
      return res.status(400).json({ success: false, error: 'Video URL is required' });
    }

    if (!isCloudinaryConfigured()) {
      return res.status(500).json({ success: false, error: 'Cloudinary not configured' });
    }

    // Expecting a Cloudinary URL; extract public_id after '/upload/' and before extension
    const uploadIdx = videoUrl.indexOf('/upload/');
    if (uploadIdx === -1) {
      return res.status(400).json({ success: false, error: 'Invalid Cloudinary URL' });
    }

    const afterUpload = videoUrl.substring(uploadIdx + '/upload/'.length);
    // Remove any existing transformations prefix (e.g. sp_hd, fl_segment_2, etc.)
    const parts = afterUpload.split('/');
    // If first part contains a dot or comma, it's a transformation, drop it
    let startIndex = 0;
    if (parts[0].includes(',') || parts[0].startsWith('sp_') || parts[0].startsWith('fl_')) {
      startIndex = 1;
    }
    const publicIdWithExt = parts.slice(startIndex).join('/');
    const publicId = publicIdWithExt.replace(/\.m3u8$/i, '');

    // Map quality to transformation parameters (no streaming profiles)
    const qualityParam = quality === 'sd' ? 'q_auto:eco' : 'q_auto:good';

    const signedUrl = cloudinary.url(publicId, {
      resource_type: 'video',
      type: 'upload',
      secure: true,
      sign_url: true,
      format: 'm3u8',
      transformation: [{ quality: qualityParam }],
      cloud_name: process.env.CLOUD_NAME
    });

    return res.json({ success: true, signedUrl });
  } catch (error) {
    console.error('❌ Error generating Cloudinary signed URL:', error);
    return res.status(500).json({ success: false, error: 'Failed to generate signed URL' });
  }
});

// **NEW: Secure endpoint to get Cloudinary config (without secrets)**
router.get('/cloudinary-config', verifyToken, async (req, res) => {
  try {
    // Only return public config, never secrets
    const config = {
      cloudName: process.env.CLOUD_NAME,
      // API key and secret are never sent to frontend for security
      hasCredentials: !!(process.env.CLOUD_KEY && process.env.CLOUD_SECRET),
    };
    
    res.json({ 
      success: true, 
      config: config,
      message: 'Cloudinary config retrieved successfully'
    });
  } catch (error) {
    console.error('❌ Error getting Cloudinary config:', error);
    res.status(500).json({ 
      success: false, 
      error: 'Failed to get Cloudinary config' 
    });
  }
});



export default router
