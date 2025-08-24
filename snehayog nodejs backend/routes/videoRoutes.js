import express from 'express';
import multer from 'multer';
import Video from '../models/Video.js';
import User from '../models/User.js';
import cloudinary from '../config/cloudinary.js';
import config, { isCloudinaryConfigured } from '../config.js';
import fs from 'fs'; // To delete temp file after upload
import path from 'path'; // For serving HLS files
import { setHLSHeaders } from '../config/hlsConfig.js';
import { verifyToken } from '../utils/verifytoken.js';
const router = express.Router();

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
router.post('/upload', verifyToken, upload.single('video'), async (req, res) => {
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
    if (!isCloudinaryConfigured()) {
      console.log('❌ Upload: Cloudinary not configured');
      fs.unlinkSync(req.file.path);
      return res.status(500).json({ 
        error: 'Video upload service not configured. Please contact administrator.',
        details: 'Cloudinary API credentials are missing. Check CLOUDINARY_SETUP.md for setup instructions.',
        solution: 'Create a .env file with CLOUD_NAME, CLOUD_KEY, and CLOUD_SECRET variables'
      });
    }

    // 6. Upload original video with HLS streaming profile
    console.log('🎬 Upload: Starting Cloudinary HLS upload...');
    try {
      originalResult = await cloudinary.uploader.upload(req.file.path, {
        resource_type: 'video',
        folder: 'snehayog-originals',
        timeout: 60000,
        
        // Enhanced video validation
        validate: true,
        invalidate: true,
        
        // Video format optimization
        video_codec: 'h264', // Ensure ExoPlayer compatibility
        audio_codec: 'aac',  // Ensure audio compatibility
        
        // Quality settings
        quality: 'auto:good',
        fetch_format: 'auto'
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
      let errorDetails = cloudinaryError.message;
      
      if (cloudinaryError.message.includes('api_key')) {
        errorMessage = 'Video upload service not configured. Please contact administrator.';
        errorDetails = 'Cloudinary API credentials are missing. Check CLOUDINARY_SETUP.md for setup instructions.';
      } else if (cloudinaryError.message.includes('cloud_name')) {
        errorMessage = 'Video upload service configuration error. Please contact administrator.';
        errorDetails = 'Cloudinary cloud name is invalid. Check your .env file configuration.';
      } else if (cloudinaryError.message.includes('Invalid image file') || cloudinaryError.message.includes('Invalid video file')) {
        errorMessage = 'Video file is corrupted or in an unsupported format. Please try with a different video file.';
        errorDetails = 'The uploaded video file appears to be corrupted or uses an unsupported codec.';
      } else if (cloudinaryError.message.includes('timeout')) {
        errorMessage = 'Video upload timed out. The file might be too large or your connection is slow.';
        errorDetails = 'Upload timeout - try with a smaller video file or check your internet connection.';
      }
      
      return res.status(500).json({ 
        error: errorMessage,
        details: errorDetails,
        solution: 'Try uploading a different video file or contact support if the problem persists'
      });
    }

    // 7. Upload HLS streaming version with 2-second segments
    try {
      console.log('🎬 Upload: Creating HLS streaming version...');
      
      // Upload with HLS eager transformations to generate actual .m3u8 files
      hlsResult = await cloudinary.uploader.upload(req.file.path, {
        resource_type: 'video',
        folder: 'snehayog-videos',
        
        // HLS streaming transformations - Cloudinary compatible only
        eager: [
          {
            // HD quality HLS stream - Cloudinary compatible
            streaming_profile: 'hd',
            format: 'm3u8'
          },
          {
            // SD quality HLS stream - Cloudinary compatible
            streaming_profile: 'sd',
            format: 'm3u8'
          }
        ],
        
        eager_async: false, // Wait for transformations to complete
        eager_notification_url: req.body.notification_url,
        
        // Additional HLS settings
        overwrite: true,
        invalidate: true,
        
        // Enhanced validation
        validate: true,
        
        timeout: 180000 // 3 minutes for HLS processing
      });
      
      console.log('✅ Upload: HLS streaming version created with eager transformations');
      console.log('🎬 Upload: HLS Result:', hlsResult);
      
      // Validate HLS result
      if (!hlsResult.eager || hlsResult.eager.length === 0) {
        console.error('❌ Upload: No eager transformations found in HLS result');
        throw new Error('HLS transformations failed - no .m3u8 files generated');
      }
      
      // Verify that we have actual .m3u8 files
      const m3u8Transformations = hlsResult.eager.filter(t => t.format === 'm3u8');
      if (m3u8Transformations.length === 0) {
        console.error('❌ Upload: No .m3u8 files generated');
        throw new Error('HLS conversion failed - no .m3u8 files created');
      }
      
      console.log('✅ Upload: HLS .m3u8 files generated successfully');
      console.log('🎬 Upload: M3U8 transformations found:', m3u8Transformations.length);
      
      m3u8Transformations.forEach((transformation, index) => {
        console.log(`🎬 Upload: M3U8 Transformation ${index + 1}:`, {
          format: transformation.format,
          url: transformation.secure_url,
          width: transformation.width,
          height: transformation.height,
          status: transformation.status || 'unknown',
          isM3U8: transformation.format === 'm3u8'
        });
      });
      
    } catch (cloudinaryError) {
      console.error('❌ Upload: HLS streaming creation failed:', cloudinaryError);
      
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
      let hlsErrorDetails = cloudinaryError.message;
      
      if (cloudinaryError.message.includes('Invalid video file')) {
        hlsErrorMessage = 'Video file is corrupted or uses an unsupported codec. HLS streaming cannot be created.';
        hlsErrorDetails = 'The video file appears to be corrupted or uses a codec that Cloudinary cannot process for HLS streaming.';
      } else if (cloudinaryError.message.includes('timeout')) {
        hlsErrorMessage = 'HLS processing timed out. The video might be too complex or too long.';
        hlsErrorDetails = 'HLS processing timeout - try with a shorter or simpler video file.';
      } else if (cloudinaryError.message.includes('no .m3u8 files')) {
        hlsErrorMessage = 'HLS conversion failed. The video could not be converted to streaming format.';
        hlsErrorDetails = 'Cloudinary failed to generate .m3u8 files for HLS streaming.';
      }
      
      return res.status(500).json({ 
        error: hlsErrorMessage,
        details: hlsErrorDetails,
        solution: 'Try uploading a different video file or contact support if the problem persists'
      });
    }

    if (!originalResult?.secure_url || !hlsResult?.secure_url) {
      console.log('❌ Upload: Missing Cloudinary URLs');
      fs.unlinkSync(req.file.path);
      return res.status(500).json({ error: 'Cloudinary upload failed' });
    }

    // 8. Generate thumbnail URL
    const thumbnailUrl = hlsResult.secure_url.replace(
      '/upload/',
      '/upload/w_300,h_400,c_fill/'
    );

    // 9. Save video in MongoDB with HLS URLs
    console.log('🎬 Upload: Saving video to database with HLS URLs...');
    
    // Get HLS URLs from eager transformations
    const hlsUrls = hlsResult.eager?.filter(t => t.format === 'm3u8') || [];
    const primaryHlsUrl = hlsUrls.length > 0 ? hlsUrls[0].secure_url : null;
    
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
    
    // Generate multiple HLS URLs with different streaming profiles
    const cloudName = process.env.CLOUD_NAME;
    const publicId = originalResult.public_id;
    
    // Create proper HLS URLs using Cloudinary streaming profiles
    const hlsUrls = {
      master: `https://res.cloudinary.com/${cloudName}/video/upload/sp_auto/${publicId}.m3u8`,
      hd: `https://res.cloudinary.com/${cloudName}/video/upload/sp_hd/${publicId}.m3u8`,
      sd: `https://res.cloudinary.com/${cloudName}/video/upload/sp_sd/${publicId}.m3u8`,
      auto: `https://res.cloudinary.com/${cloudName}/video/upload/f_m3u8,q_auto/${publicId}.m3u8`
    };
    
    // Use the auto-adaptive streaming URL as primary
    const bestHlsUrl = hlsUrls.auto;
    
    console.log('🎬 Upload: Generated HLS URLs:', hlsUrls);
    console.log('🎬 Upload: Primary HLS URL:', bestHlsUrl);
    
    const video = new Video({
      videoName,
      description: description || '', // Optional for user videos
      link: link || '',
      videoUrl: bestHlsUrl, // Use auto-adaptive HLS URL
      thumbnailUrl: thumbnailUrl,
      originalVideoUrl: originalResult.secure_url,
      // HLS streaming URLs with proper format
      hlsMasterPlaylistUrl: hlsUrls.master,
      hlsPlaylistUrl: bestHlsUrl,
      hlsVariants: [
        {
          quality: 'auto',
          playlistUrl: hlsUrls.auto,
          resolution: 'adaptive',
          bitrate: 'auto',
          format: 'm3u8'
        },
        {
          quality: 'hd',
          playlistUrl: hlsUrls.hd,
          resolution: '720p',
          bitrate: '2.5m',
          format: 'm3u8'
        },
        {
          quality: 'sd',
          playlistUrl: hlsUrls.sd,
          resolution: '480p',
          bitrate: '1.5m',
          format: 'm3u8'
        }
      ],
      isHLSEncoded: true, // Force HLS encoded
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
    
    // Use the best HLS URL we already generated
    responseHlsUrl = bestHlsUrl;
    
    // Final validation: Ensure we have a valid HLS URL
    if (!responseHlsUrl || responseHlsUrl.trim() === '' || !responseHlsUrl.includes('.m3u8')) {
      console.error('❌ Upload: Invalid HLS URL generated:', responseHlsUrl);
      return res.status(500).json({
        success: false,
        error: 'Invalid HLS URL generated',
        details: 'Video processing completed but generated URL is not valid HLS format',
        solution: 'Please try uploading the video again or contact support'
      });
    }
    
    // Log the final response for debugging
    console.log('🎬 Upload: Final response HLS URL:', responseHlsUrl);
    console.log('🎬 Upload: Generated HLS URLs:', Object.keys(hlsUrls));
    console.log('🎬 Upload: Video ID:', video._id);
    
    res.status(201).json({
      success: true,
      videoUrl: responseHlsUrl, // This will ALWAYS be HLS URL
      message: '✅ Video uploaded & HLS streaming enabled successfully',
      video: {
        ...video.toObject(),
        hlsUrl: responseHlsUrl,
        // Add all HLS URLs for different quality levels
        hlsUrls: hlsUrls,
        // Include HLS variants from video object
        hlsVariants: video.hlsVariants
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

// Note: Video streaming is now handled by Cloudinary directly with HLS streaming profiles
// No need for local HLS encoding as Cloudinary provides optimized HLS streaming with 2-second segments
// Add this test endpoint to help debug HLS issues

// Test HLS configuration
router.get('/upload/test-hls', async (req, res) => {
  try {
    console.log('🧪 HLS Test: Cloudinary HLS streaming configuration check requested');
    
    const configStatus = {
      cloudinary: false,
      cloudName: process.env.CLOUD_NAME || 'Not configured',
      apiKey: process.env.CLOUD_KEY ? 'Configured' : 'Not configured',
      apiSecret: process.env.CLOUD_SECRET ? 'Configured' : 'Not configured',
      uploads: {
        directory: 'uploads/',
        exists: false,
        writable: false
      }
    };

    // Check Cloudinary configuration
    if (process.env.CLOUD_NAME && process.env.CLOUD_KEY && process.env.CLOUD_SECRET) {
      configStatus.cloudinary = true;
    }

    // Check uploads directory
    try {
      const uploadsDir = path.join(process.cwd(), 'uploads');
      
      configStatus.uploads.exists = fs.existsSync(uploadsDir);
      if (configStatus.uploads.exists) {
        // Check if directory is writable
        try {
          const testFile = path.join(uploadsDir, 'test-write.tmp');
          fs.writeFileSync(testFile, 'test');
          fs.unlinkSync(testFile);
          configStatus.uploads.writable = true;
        } catch (writeError) {
          configStatus.uploads.writable = false;
        }
      }
    } catch (error) {
      configStatus.uploads.exists = false;
      configStatus.uploads.writable = false;
    }

    res.json({
      message: 'Cloudinary HLS Streaming Configuration Test',
      timestamp: new Date().toISOString(),
      status: configStatus,
      recommendations: [],
      hlsFeatures: {
        streamingProfile: 'sp_hd (High Definition)',
        segmentDuration: '2 seconds (fl_segment_2)',
        format: 'HLS (.m3u8)',
        adaptiveBitrate: 'Enabled',
        cdn: 'Cloudinary Global CDN'
      }
    });

    // Add recommendations based on status
    if (!configStatus.cloudinary) {
      console.log('❌ HLS Test: Cloudinary not configured - HLS streaming will fail');
    }
    if (!configStatus.uploads.exists) {
      console.log('❌ HLS Test: Uploads directory missing');
    }
    if (!configStatus.uploads.writable) {
      console.log('❌ HLS Test: Uploads directory not writable');
    }

  } catch (error) {
    console.error('❌ HLS Test Error:', error);
    res.status(500).json({
      error: 'HLS test failed',
      details: error.message
    });
  }
});
// HLS Streaming endpoint
router.get('/hls/:videoId/:filename', (req, res) => {
  const { videoId, filename } = req.params;
  const filePath = path.join(__dirname, `../uploads/hls/${videoId}/${filename}`);
  
  // Check if file exists
  if (!fs.existsSync(filePath)) {
    return res.status(404).json({ error: 'HLS file not found' });
  }
  
  // Set proper headers using configuration
  setHLSHeaders(res, filename);
  
  // Handle range requests for video segments
  if (filename.endsWith('.ts')) {
    const stat = fs.statSync(filePath);
    const fileSize = stat.size;
    const range = req.headers.range;
    
    if (range) {
      const parts = range.replace(/bytes=/, "").split("-");
      const start = parseInt(parts[0], 10);
      const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;
      const chunksize = (end - start) + 1;
      
      res.status(206);
      res.setHeader('Content-Range', `bytes ${start}-${end}/${fileSize}`);
      res.setHeader('Content-Length', chunksize);
      
      const stream = fs.createReadStream(filePath, { start, end });
      stream.pipe(res);
    } else {
      res.setHeader('Content-Length', fileSize);
      const stream = fs.createReadStream(filePath);
      stream.pipe(res);
    }
  } else {
    // For playlist files, send the entire file
    res.sendFile(filePath);
  }
});

// Get videos by user ID
router.get('/user/:googleId', async (req, res) => {
  try {
    console.log('Fetching videos for user:', req.params.googleId);

    const user = await User.findOne({ googleId: req.params.googleId });
    if (!user) {
      console.log('User not found');
      return res.status(404).json({ error: 'User not found' });
    }

    console.log('Found user:', {
      id: user._id,
      name: user.name,
      googleId: user.googleId
    });

    // Get user's videos using the new method
    const videos = await user.getVideos();
    console.log('Found videos:', videos.length);

    // Cloudinary URLs are already full URLs, no need to construct them
    const videosWithUrls = videos.map(video => ({
      ...video.toObject(),
      videoUrl: video.videoUrl || '',
      originalVideoUrl: video.originalVideoUrl || '',
      thumbnailUrl: video.thumbnailUrl || ''
    }));

    res.json(videosWithUrls);
  } catch (error) {
    console.error('Error fetching user videos:', error);
    res.status(500).json({ error: 'Error fetching videos' });
  }
});

// Debug endpoint to check video-user relationships
router.get('/debug/user/:googleId', async (req, res) => {
  try {
    const user = await User.findOne({ googleId: req.params.googleId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const videos = await user.getVideos();
    res.json({
      user: {
        id: user._id,
        name: user.name,
        googleId: user.googleId,
        videoCount: videos.length,
        link: videos.link,
      },
      videos: videos.map(video => ({
        id: video._id,
        name: video.videoName,
        url: video.videoUrl
      }))
    });
  } catch (error) {
    console.error('Debug endpoint error:', error);
    res.status(500).json({ error: 'Error in debug endpoint' });
  }
});

// Endpoint to refresh user profile pictures (for existing users)
router.post('/refresh-profile-pics', async (req, res) => {
  try {
    console.log('🔄 Refreshing user profile pictures...');
    
    // This would typically require admin authentication
    // For now, we'll just log the request
    console.log('⚠️ Profile picture refresh requested (admin only in production)');
    
    const users = await User.find({}).select('name profilePic googleId');
    const usersWithoutPics = users.filter(user => !user.profilePic || user.profilePic.trim() === '');
    
    console.log(`🔄 Found ${usersWithoutPics.length} users without profile pictures`);
    
    if (usersWithoutPics.length > 0) {
      console.log('🔄 Users without profile pictures:');
      usersWithoutPics.forEach(user => {
        console.log(`  - ${user.name} (${user.googleId})`);
      });
      
      console.log('🔄 Note: Users will need to sign in again to get their profile pictures updated');
    }
    
    res.json({
      message: 'Profile picture refresh initiated',
      totalUsers: users.length,
      usersWithoutPics: usersWithoutPics.length,
      note: 'Users need to sign in again to get profile pictures updated'
    });
  } catch (error) {
    console.error('❌ Refresh profile pics error:', error);
    res.status(500).json({ error: 'Error refreshing profile pictures' });
  }
});

// Debug endpoint to check and update user profile pictures
router.get('/debug/profile-pics', async (req, res) => {
  try {
    console.log('🔍 Debug: Checking user profile pictures...');
    
    const users = await User.find({}).select('name profilePic googleId');
    console.log(`🔍 Found ${users.length} users`);
    
    const usersWithoutPics = users.filter(user => !user.profilePic || user.profilePic.trim() === '');
    console.log(`🔍 Users without profile pics: ${usersWithoutPics.length}`);
    
    usersWithoutPics.forEach(user => {
      console.log(`  - ${user.name} (${user.googleId}): No profile pic`);
    });
    
    res.json({
      message: 'Profile picture debug info',
      totalUsers: users.length,
      usersWithoutPics: usersWithoutPics.length,
      users: users.map(user => ({
        name: user.name,
        googleId: user.googleId,
        hasProfilePic: !!(user.profilePic && user.profilePic.trim() !== ''),
        profilePic: user.profilePic || 'None'
      }))
    });
  } catch (error) {
    console.error('❌ Debug profile pics error:', error);
    res.status(500).json({ error: 'Error in debug endpoint' });
  }
});

// Get all videos (optimized for performance)
router.get('/', async (req, res) => {
  try {
    console.log('📹 Fetching videos...');
    
    // Get query parameters for pagination
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 10;
    const skip = (page - 1) * limit;
    
    // Use Promise.all to run queries in parallel for better performance
    const [totalVideos, videos] = await Promise.all([
      Video.countDocuments(),
      Video.find()
        .select('videoName videoUrl thumbnailUrl likes views shares uploader uploadedAt likedBy videoType aspectRatio duration comments link description')
        .populate('uploader', 'name profilePic googleId')
        .populate('comments.user', 'name profilePic')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limit)
        .lean() // Use lean() for better performance (returns plain objects)
    ]);
    
    // Debug: Log uploader data for first few videos
    console.log('🔍 Videos route: Checking uploader data...');
    videos.slice(0, 3).forEach((video, index) => {
      console.log(`🔍 Video ${index + 1}:`);
      console.log(`  - ID: ${video._id}`);
      console.log(`  - Name: ${video.videoName}`);
      console.log(`  - Uploader: ${JSON.stringify(video.uploader)}`);
      if (video.uploader && video.uploader.profilePic) {
        console.log(`  - Profile Pic URL: ${video.uploader.profilePic}`);
        console.log(`  - Profile Pic type: ${typeof video.uploader.profilePic}`);
      } else {
        console.log(`  - No profile pic found`);
      }
    });
    
    console.log(`✅ Found ${videos.length} videos (page ${page}, total: ${totalVideos}) in ${Date.now()}ms`);
    
    // Add caching headers for better performance
    res.set({
      'Cache-Control': 'public, max-age=30', // Cache for 30 seconds
      'ETag': `videos-${page}-${limit}-${totalVideos}`,
      'Last-Modified': new Date().toUTCString()
    });
    
    // Return in the format the Flutter app expects
    res.json({
      videos: videos,
      hasMore: (page * limit) < totalVideos,
      total: totalVideos,
      currentPage: page,
      totalPages: Math.ceil(totalVideos / limit)
    });
  } catch (error) {
    console.error('❌ Error fetching videos:', error);
    res.status(500).json({ 
      error: 'Failed to fetch videos',
      message: error.message 
    });
  }
});

// Debug endpoint to get all videos without pagination
router.get('/debug/all', async (req, res) => {
  try {
    console.log('🔍 Debug: Fetching all videos without pagination...');
    
    const videos = await Video.find()
      .populate('uploader', 'name profilePic googleId')
      .populate('comments.user', 'name profilePic')
      .sort({ createdAt: -1 });
    
    console.log(`🔍 Debug: Found ${videos.length} total videos`);
    
    res.json({
      message: 'All videos (debug endpoint)',
      count: videos.length,
      videos: videos
    });
  } catch (error) {
    console.error('❌ Debug endpoint error:', error);
    res.status(500).json({ error: 'Error in debug endpoint' });
  }
});

// Debug endpoint to test video URLs and HLS streaming
router.get('/debug/test-urls/:videoId?', async (req, res) => {
  try {
    console.log('🧪 Debug: Testing video URLs and HLS streaming...');
    
    const { videoId } = req.params;
    let videos = [];
    
    if (videoId) {
      const video = await Video.findById(videoId);
      if (video) {
        videos = [video];
      }
    } else {
      // Get latest 5 videos for testing
      videos = await Video.find()
        .sort({ createdAt: -1 })
        .limit(5);
    }
    
    if (videos.length === 0) {
      return res.json({
        message: 'No videos found for testing',
        videoId: videoId || 'all'
      });
    }
    
    const testResults = [];
    
    for (const video of videos) {
      console.log(`🧪 Testing video: ${video.videoName} (${video._id})`);
      
      const testResult = {
        videoId: video._id,
        videoName: video.videoName,
        uploadedAt: video.uploadedAt,
        urls: {
          main: video.videoUrl,
          hls_master: video.hlsMasterPlaylistUrl,
          hls_playlist: video.hlsPlaylistUrl,
          original: video.originalVideoUrl,
          thumbnail: video.thumbnailUrl
        },
        hlsVariants: video.hlsVariants || [],
        isHLSEncoded: video.isHLSEncoded,
        tests: {
          hasMainUrl: !!(video.videoUrl && video.videoUrl.trim() !== ''),
          hasHlsUrls: !!(video.hlsPlaylistUrl || video.hlsMasterPlaylistUrl),
          mainUrlIsHls: video.videoUrl?.includes('.m3u8') || false,
          hasCloudinaryUrl: video.videoUrl?.includes('cloudinary.com') || false,
          hasValidHlsFormat: false
        }
      };
      
      // Test URL formats
      if (video.videoUrl) {
        try {
          const url = new URL(video.videoUrl);
          testResult.tests.hasValidFormat = true;
          testResult.tests.hasValidHlsFormat = url.pathname.includes('.m3u8');
        } catch (e) {
          testResult.tests.hasValidFormat = false;
          testResult.tests.formatError = e.message;
        }
      }
      
      // Generate test HLS URLs if needed
      if (video.originalVideoUrl && video.originalVideoUrl.includes('cloudinary.com')) {
        const publicIdMatch = video.originalVideoUrl.match(/\/upload\/(?:v\d+\/)?(.+)\.\w+$/);
        if (publicIdMatch) {
          const publicId = publicIdMatch[1];
          const cloudName = process.env.CLOUD_NAME;
          
          testResult.generatedHlsUrls = {
            auto: `https://res.cloudinary.com/${cloudName}/video/upload/f_m3u8,q_auto/${publicId}.m3u8`,
            hd: `https://res.cloudinary.com/${cloudName}/video/upload/sp_hd/${publicId}.m3u8`,
            sd: `https://res.cloudinary.com/${cloudName}/video/upload/sp_sd/${publicId}.m3u8`
          };
        }
      }
      
      testResults.push(testResult);
    }
    
    res.json({
      message: 'Video URL testing results',
      timestamp: new Date().toISOString(),
      cloudinaryConfigured: !!(process.env.CLOUD_NAME && process.env.CLOUD_KEY && process.env.CLOUD_SECRET),
      testCount: testResults.length,
      results: testResults,
      recommendations: [
        'All videos should have HLS URLs (.m3u8 format)',
        'Main videoUrl should be an HLS URL for best compatibility',
        'Cloudinary URLs should use proper streaming profiles',
        'Check that HLS URLs are accessible and valid'
      ]
    });
    
  } catch (error) {
    console.error('❌ Debug URL test error:', error);
    res.status(500).json({ 
      error: 'Failed to test video URLs',
      details: error.message
    });
  }
});

// POST /api/videos/:id/like - Toggle like for a video (must be before /:id route)
router.post('/:id/like', async (req, res) => {
  try {
    const { userId } = req.body;
    const videoId = req.params.id;

    console.log('🔍 Like API: Received request', { userId, videoId });

    // Validate input
    if (!userId) {
      console.log('❌ Like API: Missing userId in request body');
      return res.status(400).json({ error: 'userId is required' });
    }

    if (!videoId) {
      console.log('❌ Like API: Missing videoId in params');
      return res.status(400).json({ error: 'videoId is required' });
    }

    // Find or create user
    let user = await User.findOne({ googleId: userId });
    if (!user) {
      console.log('🔍 Like API: User not found, creating new user with googleId:', userId);
      // Create user if they don't exist
      user = new User({
        googleId: userId,
        name: 'User', // Will be updated later
        email: '', // Will be updated later
        following: [],
        followers: []
      });
      await user.save();
      console.log('✅ Like API: Created new user with ID:', user._id);
    }

    // Find the video
    const video = await Video.findById(videoId);
    if (!video) {
      console.log('❌ Like API: Video not found with ID:', videoId);
      return res.status(404).json({ error: 'Video not found' });
    }

    console.log('🔍 Like API: Video found, current likes:', video.likes, 'likedBy:', video.likedBy);

    // Check if user has already liked the video
    const userLikedIndex = video.likedBy.indexOf(userId);
    let wasLiked = false;
    
    if (userLikedIndex > -1) {
      // User has already liked - remove the like
      video.likedBy.splice(userLikedIndex, 1);
      video.likes = Math.max(0, video.likes - 1); // Decrement likes, ensure not negative
      wasLiked = false;
      console.log('🔍 Like API: Removed like, new count:', video.likes);
    } else {
      // User hasn't liked - add the like
      video.likedBy.push(userId);
      video.likes = video.likes + 1; // Increment likes
      wasLiked = true;
      console.log('🔍 Like API: Added like, new count:', video.likes);
    }

    await video.save();
    console.log('✅ Like API: Video saved successfully');

    // Return the updated video with populated fields
    const updatedVideo = await Video.findById(videoId)
      .populate('uploader', 'name profilePic googleId')
      .populate('comments.user', 'name profilePic');

    res.json({
      ...updatedVideo.toObject(),
      likeAction: wasLiked ? 'added' : 'removed',
      newLikeCount: video.likes
    });
    
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

// Get video by ID
router.get('/:id', async (req, res) => {
  try {
    const video = await Video.findById(req.params.id)
      .populate('uploader', 'name profilePic googleId')
      .populate('comments.user', 'name profilePic');

    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    res.json(video);
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
    ).populate('comments.user', 'name profilePic');

    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    res.json(video.comments);
  } catch (err) {
    console.error('Error adding comment:', err);
    res.status(500).json({ error: 'Failed to add comment', details: err.message });
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


export default router