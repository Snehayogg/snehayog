import express from 'express';
import multer from 'multer';
import Video from '../models/Video.js';
import User from '../models/User.js';
import cloudinary from '../config/cloudinary.js';
import config, { isCloudinaryConfigured } from '../config.js';
import fs from 'fs'; // To delete temp file after upload
import hlsEncodingService from '../services/hlsEncodingService.js';
import path from 'path'; // For serving HLS files
import { setHLSHeaders } from '../config/hlsConfig.js';
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
router.post('/upload', upload.single('video'), async (req, res) => {
  let originalResult = null;
  let compressedResult = null;

  try {
    console.log('🎬 Upload: Starting video upload process...');
    console.log('🎬 Upload: Request body:', req.body);
    console.log('🎬 Upload: File info:', req.file ? {
      filename: req.file.filename,
      size: req.file.size,
      mimetype: req.file.mimetype,
      path: req.file.path
    } : 'No file');

    const { googleId, videoName, description, videoType, link } = req.body;

    // 1. Validate file
    if (!req.file || !req.file.path) {
      console.log('❌ Upload: No video file uploaded');
      return res.status(400).json({ error: 'No video file uploaded' });
    }

    // 2. Validate required fields
    if (!googleId) {
      console.log('❌ Upload: Missing googleId');
      fs.unlinkSync(req.file.path);
      return res.status(400).json({ error: 'googleId is required' });
    }

    if (!videoName || videoName.trim() === '') {
      console.log('❌ Upload: Missing video name');
      fs.unlinkSync(req.file.path);
      return res.status(400).json({ error: 'Video name is required' });
    }

    // 3. Validate MIME type
    const allowedTypes = ['video/mp4', 'video/webm', 'video/avi', 'video/mkv', 'video/mov'];
    if (!allowedTypes.includes(req.file.mimetype)) {
      console.log('❌ Upload: Invalid video format:', req.file.mimetype);
      fs.unlinkSync(req.file.path);
      return res.status(400).json({ error: 'Invalid video format' });
    }

    // 4. Validate user
    console.log('🎬 Upload: Looking for user with googleId:', googleId);
    const user = await User.findOne({ googleId });
    if (!user) {
      console.log('❌ Upload: User not found with googleId:', googleId);
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

    // 6. Upload original video
    console.log('🎬 Upload: Starting Cloudinary upload...');
    try {
      originalResult = await cloudinary.uploader.upload(req.file.path, {
        resource_type: 'video',
        folder: 'snehayog-originals',
        timeout: 60000
      });
      console.log('✅ Upload: Original video uploaded to Cloudinary');
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
      }
      
      return res.status(500).json({ 
        error: errorMessage,
        details: errorDetails,
        solution: 'Create a .env file with proper Cloudinary credentials and restart the server'
      });
    }

    // 7. Upload compressed video
    try {
      compressedResult = await cloudinary.uploader.upload(req.file.path, {
        resource_type: 'video',
        folder: 'snehayog-videos',
        transformation: [
          { quality: 'auto:good' },
          { fetch_format: 'auto' },
        ],
        timeout: 60000
      });
      console.log('✅ Upload: Compressed video uploaded to Cloudinary');
    } catch (cloudinaryError) {
      console.error('❌ Upload: Compressed video upload failed:', cloudinaryError);
      // Try to delete the original upload
      if (originalResult?.public_id) {
        try {
          await cloudinary.uploader.destroy(originalResult.public_id, { resource_type: 'video' });
        } catch (e) {
          console.error('❌ Upload: Failed to cleanup original upload:', e);
        }
      }
      fs.unlinkSync(req.file.path);
      return res.status(500).json({ 
        error: 'Failed to process video. Please try again.' 
      });
    }

    if (!originalResult?.secure_url || !compressedResult?.secure_url) {
      console.log('❌ Upload: Missing Cloudinary URLs');
      fs.unlinkSync(req.file.path);
      return res.status(500).json({ error: 'Cloudinary upload failed' });
    }

    // 8. Generate thumbnail URL
    const thumbnailUrl = compressedResult.secure_url.replace(
      '/upload/',
      '/upload/w_300,h_400,c_fill/'
    );

    // 9. Save video in MongoDB
    console.log('🎬 Upload: Saving video to database...');
    const video = new Video({
      videoName,
      description: description || '',
      link: link || '',
      videoUrl: compressedResult.secure_url,
      thumbnailUrl: thumbnailUrl,
      originalVideoUrl: originalResult.secure_url,
      // HLS streaming URLs (will be updated later if encoding succeeds)
      hlsMasterPlaylistUrl: null,
      hlsPlaylistUrl: null,
      hlsVariants: [],
      isHLSEncoded: false,
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
    console.log('✅ Upload: Video saved to database with ID:', video._id);

    // 11. Push video to user's video list
    user.videos.push(video._id);
    await user.save();
    console.log('✅ Upload: Video added to user profile');

    // 12. Start HLS encoding BEFORE cleanup
    const videoId = video._id.toString();
    try {
      // Check if HLS encoding service is available
      const isFFmpegAvailable = await hlsEncodingService.checkFFmpegInstallation();
      if (!isFFmpegAvailable) {
        console.log('⚠️ Upload: FFmpeg not available, skipping HLS encoding for:', videoName);
        // Mark video as not HLS encoded
        await Video.findByIdAndUpdate(
          videoId,
          { isHLSEncoded: false },
          { new: true }
        );
      } else {
        console.log('🎬 Upload: Starting HLS encoding for video:', videoName);
        
        // Use the already imported service instead of dynamic import
        hlsEncodingService.generateAdaptiveHLS(req.file.path, videoId)
          .then(async (hlsResult) => {
            console.log('✅ Upload: HLS encoding completed for', videoName, ':', hlsResult);
            try {
              const updatedVideo = await Video.findByIdAndUpdate(
                videoId,
                {
                  hlsMasterPlaylistUrl: hlsResult?.masterPlaylistUrl || null,
                  hlsPlaylistUrl: hlsResult?.variants?.[0]?.playlistUrl || null,
                  hlsVariants: hlsResult?.variants || [],
                  isHLSEncoded: true
                },
                { new: true }
              );
              console.log('✅ Upload: Video updated with HLS URLs');
            } catch (updateError) {
              console.error('❌ Upload: Failed to update video with HLS URLs:', updateError);
            }
          })
          .catch((hlsError) => {
            console.error('❌ Upload: HLS encoding failed for', videoName, ':', hlsError);
            // Don't fail the upload - HLS is optional but we'll retry
            _retryHLSEncoding(videoId, req.file.path, videoName);
          });
      }
    } catch (hlsError) {
      console.error('❌ Upload: HLS encoding service not available:', hlsError);
      // Continue with upload - HLS is optional
    }

    // 13. Clean up temp file AFTER HLS encoding is started
    // Add a small delay to ensure HLS encoding has started
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

    // 14. Respond success
    console.log('✅ Upload: Video upload completed successfully');
    res.status(201).json({
      message: '✅ Video uploaded & saved successfully',
      video
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
      error: '❌ Failed to upload video',
      details: error.message
    });
  }
});

// Add this function after the upload route

// Retry HLS encoding if it fails initially
async function _retryHLSEncoding(videoId, videoPath, videoName) {
  try {
    console.log('🔄 Upload: Retrying HLS encoding for video:', videoName);
    
    // Check if the local file still exists before retrying
    if (!videoPath || !fs.existsSync(videoPath)) {
      console.log('⚠️ Upload: Local file no longer available for HLS retry, skipping...');
      // Mark video as HLS encoding failed since we can't retry
      await Video.findByIdAndUpdate(
        videoId,
        { isHLSEncoded: false },
        { new: true }
      );
      return;
    }
    
    // Wait a bit before retry
    await new Promise(resolve => setTimeout(resolve, 5000));
    
    const hlsResult = await hlsEncodingService.generateAdaptiveHLS(videoPath, videoId);
    console.log('✅ Upload: HLS encoding retry successful for', videoName);
    
    // Update video with HLS URLs
    await Video.findByIdAndUpdate(
      videoId,
      {
        hlsMasterPlaylistUrl: hlsResult?.masterPlaylistUrl || null,
        hlsPlaylistUrl: hlsResult?.variants?.[0]?.playlistUrl || null,
        hlsVariants: hlsResult?.variants || [],
        isHLSEncoded: true
      },
      { new: true }
    );
    console.log('✅ Upload: Video updated with HLS URLs after retry');
  } catch (retryError) {
    console.error('❌ Upload: HLS encoding retry failed for', videoName, ':', retryError);
    // Mark video as HLS encoding failed but don't delete it
    await Video.findByIdAndUpdate(
      videoId,
      { isHLSEncoded: false },
      { new: true }
    );
  }
}
// Note: Video streaming is now handled by Cloudinary directly
// No need for local streaming endpoint as Cloudinary provides optimized video delivery
// Add this test endpoint to help debug HLS issues

// Test HLS configuration
router.get('/upload/test-hls', async (req, res) => {
  try {
    console.log('🧪 HLS Test: Configuration check requested');
    
    const configStatus = {
      ffmpeg: false,
      hlsService: true,
      uploads: {
        directory: 'uploads/',
        exists: false,
        writable: false
      }
    };

    // Check FFmpeg installation
    try {
      const isFFmpegWorking = await hlsEncodingService.checkFFmpegInstallation();
      configStatus.ffmpeg = isFFmpegWorking;
    } catch (error) {
      configStatus.ffmpeg = false;
    }

    // Check uploads directory
    try {
      const fs = await import('fs');
      const path = await import('path');
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
      message: 'HLS Configuration Test',
      timestamp: new Date().toISOString(),
      status: configStatus,
      recommendations: []
    });

    // Add recommendations based on status
    if (!configStatus.ffmpeg) {
      console.log('❌ HLS Test: FFmpeg not working - HLS encoding will fail');
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
        .select('videoName videoUrl thumbnailUrl likes views shares description uploader uploadedAt likedBy videoType aspectRatio duration comments link')
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
router.delete('/:id', async (req, res) => {
  try {
    const videoId = req.params.id;
    const deletedVideo = await Video.findByIdAndDelete(videoId);
    if (!deletedVideo) {
      return res.status(404).json({ error: 'Video not found' });
    }
    res.json({ success: true, message: 'Video deleted successfully' });
  } catch (error) {
    res.status(500).json({ error: 'Failed to delete video' });
  }
});


export default router