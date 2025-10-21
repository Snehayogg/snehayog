import { spawn } from 'child_process';
import path from 'path';
import fs from 'fs/promises';

class VideoProcessingService {
  constructor() {
    console.warn('⚠️ VideoProcessingService is DEPRECATED - Use hybridVideoService.js for cost-optimized processing');
  }

  async processVideoToMultipleQualities(videoPath, videoName, userId) {
    console.warn('⚠️ DEPRECATED: processVideoToMultipleQualities() - Use hybridVideoService.processVideoHybrid() instead');
    throw new Error('This method is deprecated. Use hybridVideoService for cost-optimized processing.');
  }

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

      ffprobe.on('error', (error) => {
        console.log('⚠️ FFprobe not available, using fallback video info');
        console.log('⚠️ Error details:', error.message);
        // Return fallback video info when ffprobe is not available
        resolve({
          format: { duration: 30, size: 0 },
          streams: [{
            codec_type: 'video',
            width: 720,
            height: 1280,
            codec_name: 'unknown'
          }]
        });
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
          console.log('⚠️ FFprobe failed, using fallback video info');
          console.log('⚠️ Error output:', errorOutput);
          // Return fallback video info when ffprobe fails
          resolve({
            format: { duration: 30, size: 0 },
            streams: [{
              codec_type: 'video',
              width: 720,
              height: 1280,
              codec_name: 'unknown'
            }]
          });
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
