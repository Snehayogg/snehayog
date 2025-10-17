import ffmpeg from 'fluent-ffmpeg';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import cloudflareR2Service from './cloudflareR2Service.js';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

class FFmpegVideoService {
  constructor() {
    // Ensure output directory exists
    this.outputDir = path.join(__dirname, '../uploads/processed');
    this.ensureOutputDirectory();
    
    // Check FFmpeg installation
    this.checkFFmpegInstallation().then(isInstalled => {
      if (!isInstalled) {
        console.warn('⚠️ FFmpeg not found. Video processing will not work.');
        console.warn('   Please install FFmpeg: https://ffmpeg.org/download.html');
      } else {
        console.log('✅ FFmpeg found and ready for video processing');
      }
    });
  }

  ensureOutputDirectory() {
    if (!fs.existsSync(this.outputDir)) {
      fs.mkdirSync(this.outputDir, { recursive: true });
    }
  }

  /**
   * Check if FFmpeg is installed
   */
  async checkFFmpegInstallation() {
    return new Promise((resolve) => {
      ffmpeg.getAvailableFormats((err, formats) => {
        resolve(!err && formats);
      });
    });
  }

  /**
   * Process video to 480p MP4 with thumbnail generation
   * @param {string} inputPath - Path to input video file
   * @param {string} videoName - Video name for output files
   * @param {string} userId - User ID for folder organization
   * @returns {Promise<Object>} - Processing result
   */
  async processVideo(inputPath, videoName, userId) {
    try {
      console.log('🚀 Starting FFmpeg video processing...');
      console.log('📁 Input:', inputPath);
      console.log('📝 Video name:', videoName);
      console.time('FFmpeg Processing');

      // Get video info first
      const videoInfo = await this.getVideoInfo(inputPath);
      console.log('📊 Video info:', videoInfo);

      // Generate output paths
      const cleanVideoName = videoName.replace(/[^a-zA-Z0-9_-]/g, '_');
      const outputVideoPath = path.join(this.outputDir, `${cleanVideoName}_480p.mp4`);
      const thumbnailPath = path.join(this.outputDir, `${cleanVideoName}_thumb.jpg`);

      // Process video to 480p MP4
      const videoResult = await this.encodeVideo(inputPath, outputVideoPath, videoInfo);
      
      // Generate thumbnail
      const thumbnailResult = await this.generateThumbnail(inputPath, thumbnailPath);

      // Upload to R2 (with fallback for missing configuration)
      let r2VideoResult, r2ThumbnailResult;
      
      try {
        console.log('☁️ Uploading processed video to R2...');
        r2VideoResult = await cloudflareR2Service.uploadVideoToR2(
          outputVideoPath,
          videoName,
          userId
        );

        console.log('🖼️ Uploading thumbnail to R2...');
        r2ThumbnailResult = await cloudflareR2Service.uploadThumbnailToR2(
          thumbnailPath,
          videoName,
          userId
        );
      } catch (r2Error) {
        console.warn('⚠️ R2 upload failed, using local files:', r2Error.message);
        
        // Fallback to local file URLs for development
        const baseUrl = process.env.BASE_URL || 'http://localhost:5001';
        r2VideoResult = {
          url: `${baseUrl}/uploads/processed/${path.basename(outputVideoPath)}`
        };
        r2ThumbnailResult = `${baseUrl}/uploads/processed/${path.basename(thumbnailPath)}`;
        
        console.log('📁 Using local file URLs for development');
        console.log('   Video URL:', r2VideoResult.url);
        console.log('   Thumbnail URL:', r2ThumbnailResult);
      }

      // Cleanup local files (only if uploaded to R2 successfully)
      if (r2VideoResult && r2VideoResult.url && !r2VideoResult.url.includes('/uploads/processed/')) {
        await this.cleanupLocalFile(outputVideoPath);
        await this.cleanupLocalFile(thumbnailPath);
        console.log('🗑️ Cleaned up local processed files');
      } else {
        console.log('📁 Keeping local files for development');
      }

      console.timeEnd('FFmpeg Processing');
      console.log('🎉 FFmpeg processing completed successfully!');

      return {
        success: true,
        videoUrl: r2VideoResult.url,
        thumbnailUrl: r2ThumbnailResult,
        format: 'MP4',
        quality: '480p',
        storage: 'Cloudflare R2',
        bandwidth: 'FREE Forever',
        size: videoResult.size,
        duration: videoResult.duration,
        processing: 'FFmpeg → R2',
        costSavings: '100% (No Cloudinary costs)'
      };

    } catch (error) {
      console.error('❌ FFmpeg processing error:', error);
      throw new Error(`FFmpeg processing failed: ${error.message}`);
    }
  }

  /**
   * Encode video to 480p MP4
   */
  async encodeVideo(inputPath, outputPath, videoInfo) {
    return new Promise((resolve, reject) => {
      console.log('🎬 Encoding video to 480p MP4...');

      ffmpeg(inputPath)
        .inputOptions(['-y', '-hide_banner', '-loglevel error'])
        .outputOptions([
          // Video codec settings - optimized for speed
          '-c:v', 'libx264',
          '-preset', 'ultrafast',      // Ultrafast preset for speed
          '-profile:v', 'baseline',    // Baseline profile for maximum compatibility
          '-level', '3.0',             // H.264 level for broad device support
          '-crf', '23',                // Good quality
          '-maxrate', '600k',          // Reduced bitrate for faster processing
          '-bufsize', '1200k',         // Buffer size
          
          // Audio codec settings
          '-c:a', 'aac',
          '-b:a', '96k',               // Audio bitrate
          '-ac', '2',                  // Stereo
          '-ar', '44100',              // Sample rate
          
          // Additional optimizations
          '-movflags', '+faststart',   // Optimize for streaming
          '-pix_fmt', 'yuv420p'       // Pixel format for compatibility
        ])
        .videoFilters(`scale='min(854,iw)':'min(480,ih)':force_original_aspect_ratio=decrease`)
        .size('854x480')
        .output(outputPath)
        .on('start', (commandLine) => {
          console.log('🚀 FFmpeg command:', commandLine);
        })
        .on('progress', (progress) => {
          console.log(`📊 Video encoding progress: ${progress.percent}%`);
        })
        .on('end', () => {
          console.log('✅ Video encoding completed');
          const stats = fs.statSync(outputPath);
          resolve({
            size: stats.size,
            duration: videoInfo.duration
          });
        })
        .on('error', (error) => {
          console.error('❌ Video encoding failed:', error);
          reject(error);
        })
        .run();
    });
  }

  /**
   * Generate thumbnail from video
   */
  async generateThumbnail(inputPath, outputPath) {
    return new Promise((resolve, reject) => {
      console.log('🖼️ Generating thumbnail...');

      ffmpeg(inputPath)
        .inputOptions(['-y', '-hide_banner', '-loglevel error'])
        .outputOptions([
          '-vframes', '1',             // Extract only 1 frame
          '-q:v', '2',                 // High quality thumbnail
          '-f', 'image2'               // Output format
        ])
        .videoFilters('scale=320:180:force_original_aspect_ratio=decrease,pad=320:180:(ow-iw)/2:(oh-ih)/2:black')
        .output(outputPath)
        .on('start', (commandLine) => {
          console.log('🚀 Thumbnail command:', commandLine);
        })
        .on('end', () => {
          console.log('✅ Thumbnail generation completed');
          resolve(outputPath);
        })
        .on('error', (error) => {
          console.error('❌ Thumbnail generation failed:', error);
          reject(error);
        })
        .run();
    });
  }

  /**
   * Get video information using ffprobe
   */
  async getVideoInfo(inputPath) {
    return new Promise((resolve, reject) => {
      ffmpeg.ffprobe(inputPath, (err, metadata) => {
        if (err) {
          reject(err);
          return;
        }

        const videoStream = metadata.streams.find(stream => stream.codec_type === 'video');
        if (!videoStream) {
          reject(new Error('No video stream found'));
          return;
        }

        resolve({
          duration: metadata.format.duration,
          width: videoStream.width,
          height: videoStream.height,
          aspectRatio: videoStream.width / videoStream.height,
          size: metadata.format.size,
          bitrate: metadata.format.bit_rate
        });
      });
    });
  }

  /**
   * Clean up local file
   */
  async cleanupLocalFile(filePath) {
    try {
      if (fs.existsSync(filePath)) {
        await fs.promises.unlink(filePath);
        console.log('🧹 Local file cleaned up:', filePath);
      }
    } catch (error) {
      console.warn('⚠️ Failed to cleanup local file:', error);
    }
  }
}

export default new FFmpegVideoService();
