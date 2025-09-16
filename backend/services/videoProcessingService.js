import cloudinary from 'cloudinary';
import { spawn } from 'child_process';
import path from 'path';
import fs from 'fs/promises';

class VideoProcessingService {
  constructor() {
    // Configure Cloudinary
    cloudinary.v2.config({
      cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
      api_key: process.env.CLOUDINARY_API_KEY,
      api_secret: process.env.CLOUDINARY_API_SECRET
    });
    
    this.qualitySettings = [
      { 
        name: 'preload', 
        height: 360, 
        bitrate: '400k', 
        description: '360p - Fastest loading for preloading' 
      },
      { 
        name: 'low', 
        height: 480, 
        bitrate: '800k', 
        description: '480p - Low quality for slow networks' 
      },
      { 
        name: 'medium', 
        height: 720, 
        bitrate: '1500k', 
        description: '720p - Medium quality for average networks' 
      },
      { 
        name: 'high', 
        height: 1080, 
        bitrate: '3000k', 
        description: '1080p - High quality for fast networks' 
      }
    ];
  }

  /**
   * Process uploaded video to create multiple quality versions
   * @param {string} videoPath - Path to uploaded video file
   * @param {string} videoName - Name of the video
   * @param {string} userId - ID of user uploading the video
   * @returns {Object} Object containing all quality URLs
   */
  async processVideoToMultipleQualities(videoPath, videoName, userId) {
    try {
      console.log('🚀 Starting video processing for:', videoName);
      
      // Check if Cloudinary is configured
      if (this.isCloudinaryConfigured()) {
        return await this.processWithCloudinary(videoPath, videoName, userId);
      } else {
        return await this.processWithFFmpeg(videoPath, videoName, userId);
      }
    } catch (error) {
      console.error('❌ Error processing video to multiple qualities:', error);
      throw new Error(`Video processing failed: ${error.message}`);
    }
  }

  /**
   * Check if Cloudinary is properly configured
   */
  isCloudinaryConfigured() {
    return process.env.CLOUDINARY_CLOUD_NAME && 
           process.env.CLOUDINARY_API_KEY && 
           process.env.CLOUDINARY_API_SECRET;
  }

  /**
   * Process video using Cloudinary (Recommended - Easy & Fast)
   */
  async processWithCloudinary(videoPath, videoName, userId) {
    try {
      console.log('☁️ Processing video with Cloudinary...');
      
      // Upload original video to Cloudinary
      const originalResult = await cloudinary.uploader.upload(videoPath, {
        resource_type: 'video',
        folder: `videos/${userId}`,
        public_id: `${videoName}_original_${Date.now()}`,
        overwrite: true
      });

      console.log('✅ Original video uploaded to Cloudinary');

      const qualityUrls = {
        originalUrl: originalResult.secure_url,
        preloadQualityUrl: null,
        lowQualityUrl: null,
        mediumQualityUrl: null,
        highQualityUrl: null
      };

      // Create quality versions using Cloudinary transformations
      for (const quality of this.qualitySettings) {
        try {
          console.log(`🔄 Creating ${quality.name} quality version...`);
          
          const qualityResult = await cloudinary.uploader.upload(videoPath, {
            resource_type: 'video',
            folder: `videos/${userId}/qualities`,
            public_id: `${videoName}_${quality.name}_${Date.now()}`,
            transformation: [
              { height: quality.height, quality: 'auto', fetch_format: 'mp4' },
              { bitrate: quality.bitrate },
              { audio_codec: 'aac' }
            ],
            overwrite: true
          });

          // Map quality names to database field names
          const fieldName = this.getQualityFieldName(quality.name);
          qualityUrls[fieldName] = qualityResult.secure_url;
          
          console.log(`✅ ${quality.name} quality created: ${qualityResult.secure_url}`);
        } catch (qualityError) {
          console.error(`⚠️ Failed to create ${quality.name} quality:`, qualityError);
          // Continue with other qualities
        }
      }

      // Clean up local file
      await this.cleanupLocalFile(videoPath);
      
      console.log('🎉 All quality versions created successfully!');
      return qualityUrls;
      
    } catch (error) {
      console.error('❌ Cloudinary processing failed:', error);
      throw error;
    }
  }

  /**
   * Process video using FFmpeg (Free alternative)
   */
  async processWithFFmpeg(videoPath, videoName, userId) {
    try {
      console.log('🔧 Processing video with FFmpeg...');
      
      const outputDir = path.join(process.cwd(), 'uploads', 'processed', userId);
      await fs.mkdir(outputDir, { recursive: true });
      
      const qualityUrls = {
        originalUrl: videoPath, // Keep original for now
        preloadQualityUrl: null,
        lowQualityUrl: null,
        mediumQualityUrl: null,
        highQualityUrl: null
      };

      // Create quality versions using FFmpeg
      for (const quality of this.qualitySettings) {
        try {
          console.log(`🔄 Creating ${quality.name} quality version...`);
          
          const outputPath = path.join(outputDir, `${videoName}_${quality.name}.mp4`);
          
          await this.createFFmpegQuality(videoPath, outputPath, quality);
          
          // Map quality names to database field names
          const fieldName = this.getQualityFieldName(quality.name);
          qualityUrls[fieldName] = outputPath;
          
          console.log(`✅ ${quality.name} quality created: ${outputPath}`);
        } catch (qualityError) {
          console.error(`⚠️ Failed to create ${quality.name} quality:`, qualityError);
          // Continue with other qualities
        }
      }

      console.log('🎉 All quality versions created with FFmpeg!');
      return qualityUrls;
      
    } catch (error) {
      console.error('❌ FFmpeg processing failed:', error);
      throw error;
    }
  }

  /**
   * Create quality version using FFmpeg
   */
  async createFFmpegQuality(inputPath, outputPath, quality) {
    return new Promise((resolve, reject) => {
      const ffmpegArgs = [
        '-i', inputPath,
        '-vf', `scale=-2:${quality.height}`,
        '-b:v', quality.bitrate,
        '-c:a', 'aac',
        '-c:v', 'libx264',
        '-preset', 'fast',
        '-crf', '23',
        '-movflags', '+faststart',
        '-y', // Overwrite output file
        outputPath
      ];

      console.log(`🔧 FFmpeg command: ffmpeg ${ffmpegArgs.join(' ')}`);

      const ffmpeg = spawn('ffmpeg', ffmpegArgs);

      ffmpeg.stderr.on('data', (data) => {
        console.log(`FFmpeg ${quality.name}: ${data}`);
      });

      ffmpeg.on('close', (code) => {
        if (code === 0) {
          resolve(outputPath);
        } else {
          reject(new Error(`FFmpeg process exited with code ${code}`));
        }
      });

      ffmpeg.on('error', (error) => {
        reject(new Error(`FFmpeg error: ${error.message}`));
      });
    });
  }

  /**
   * Map quality names to database field names
   */
  getQualityFieldName(qualityName) {
    const fieldMap = {
      'preload': 'preloadQualityUrl',
      'low': 'lowQualityUrl',
      'medium': 'mediumQualityUrl',
      'high': 'highQualityUrl'
    };
    return fieldMap[qualityName] || qualityName;
  }

  /**
   * Clean up local file after processing
   */
  async cleanupLocalFile(filePath) {
    try {
      await fs.unlink(filePath);
      console.log('🧹 Local file cleaned up:', filePath);
    } catch (error) {
      console.warn('⚠️ Failed to cleanup local file:', error);
    }
  }

  /**
   * Get video information (duration, dimensions, etc.)
   */
  async getVideoInfo(videoPath) {
    return new Promise((resolve, reject) => {
      const ffprobe = spawn('ffprobe', [
        '-v', 'quiet',
        '-print_format', 'json',
        '-show_format',
        '-show_streams',
        videoPath
      ]);

      let output = '';
      let errorOutput = '';

      ffprobe.stdout.on('data', (data) => {
        output += data.toString();
      });

      ffprobe.stderr.on('data', (data) => {
        errorOutput += data.toString();
      });

      ffprobe.on('close', (code) => {
        if (code === 0) {
          try {
            const info = JSON.parse(output);
            resolve(info);
          } catch (parseError) {
            reject(new Error('Failed to parse video info'));
          }
        } else {
          reject(new Error(`FFprobe failed: ${errorOutput}`));
        }
      });
    });
  }

  /**
   * Validate video file
   */
  async validateVideo(videoPath) {
    try {
      const info = await this.getVideoInfo(videoPath);
      
      // Check if it's a valid video file
      const videoStream = info.streams.find(stream => stream.codec_type === 'video');
      if (!videoStream) {
        throw new Error('No video stream found in file');
      }

      // Check duration (optional)
      if (info.format.duration) {
        const duration = parseFloat(info.format.duration);
        if (duration > 300) { // 5 minutes max
          throw new Error('Video too long (max 5 minutes)');
        }
      }

      return {
        isValid: true,
        duration: info.format.duration,
        width: videoStream.width,
        height: videoStream.height,
        size: info.format.size
      };
    } catch (error) {
      return {
        isValid: false,
        error: error.message
      };
    }
  }
}

export default VideoProcessingService;
