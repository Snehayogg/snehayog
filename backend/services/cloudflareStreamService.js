import axios from 'axios';
import fs from 'fs';
import path from 'path';
import FormData from 'form-data';
import { spawn } from 'child_process';

class CloudflareStreamService {
  constructor() {
    this.accountId = process.env.CLOUDFLARE_ACCOUNT_ID;
    this.apiToken = process.env.CLOUDFLARE_STREAM_API_TOKEN;
    this.apiUrl = `https://api.cloudflare.com/client/v4/accounts/${this.accountId}/stream`;
    
    console.log('🔧 Cloudflare Stream Service Configuration:');
    console.log('   Account ID:', this.accountId ? '✅ Set' : '❌ Missing');
    console.log('   API Token:', this.apiToken ? '✅ Set' : '❌ Missing');
    
    if (!this.accountId || !this.apiToken) {
      console.warn('⚠️ Cloudflare Stream credentials missing. Stream processing will fail.');
    }
  }

  /**
   * Upload video to Cloudflare Stream and wait for transcoding
   * Returns the processed video URL and metadata
   */
  async uploadAndTranscode(videoPath, videoName, userId) {
    try {
      console.log('📤 Uploading video to Cloudflare Stream...');
      console.log('   Video path:', videoPath);
      console.log('   Video name:', videoName);
      
      if (!this.accountId || !this.apiToken) {
        throw new Error('Cloudflare Stream credentials not configured');
      }

      // **FIX: Get original video info BEFORE uploading to Stream**
      // This ensures we preserve original dimensions even if Stream returns different values
      console.log('📊 Getting original video dimensions before processing...');
      const originalVideoInfo = await this.getOriginalVideoInfo(videoPath);
      console.log('📊 Original video info:', {
        width: originalVideoInfo.width,
        height: originalVideoInfo.height,
        aspectRatio: originalVideoInfo.aspectRatio
      });

      // Step 1: Upload video to Stream
      const uploadResult = await this.uploadVideo(videoPath, videoName, userId);
      console.log('✅ Video uploaded to Stream');
      console.log('   Video ID:', uploadResult.videoId);
      
      // Step 2: Wait for transcoding to complete
      console.log('⏳ Waiting for transcoding to complete...');
      const transcodedVideo = await this.waitForTranscoding(uploadResult.videoId);
      console.log('✅ Transcoding completed');
      
      // Step 3: Get video info from Stream
      const videoInfo = await this.getVideoInfo(uploadResult.videoId);
      
      // Step 4: Download the transcoded video
      console.log('📥 Downloading transcoded video from Stream...');
      const downloadedPath = await this.downloadTranscodedVideo(
        transcodedVideo.videoId,
        videoName,
        userId
      );
      
      // **FIX: Use original video dimensions instead of Stream's transcoded dimensions**
      // Stream may transcode to different resolution, but we want to preserve original
      const finalWidth = originalVideoInfo.width || videoInfo.width || 480;
      const finalHeight = originalVideoInfo.height || videoInfo.height || 854;
      const finalAspectRatio = originalVideoInfo.aspectRatio || 
        (finalWidth && finalHeight ? finalWidth / finalHeight : 9/16);
      
      console.log('📐 Final video dimensions (preserved from original):', {
        width: finalWidth,
        height: finalHeight,
        aspectRatio: finalAspectRatio
      });
      
      return {
        videoId: transcodedVideo.videoId,
        videoUrl: transcodedVideo.playbackUrl, // HLS playback URL
        downloadUrl: transcodedVideo.downloadUrl, // Direct download URL
        localPath: downloadedPath,
        duration: originalVideoInfo.duration || videoInfo.duration || 0,
        size: videoInfo.size || 0,
        format: 'mp4',
        width: finalWidth,
        height: finalHeight,
        aspectRatio: finalAspectRatio,
        isPortrait: finalAspectRatio < 1.0,
        originalVideoInfo: {
          width: finalWidth,
          height: finalHeight,
          aspectRatio: finalAspectRatio,
          duration: originalVideoInfo.duration || videoInfo.duration || 0
        }
      };
      
    } catch (error) {
      console.error('❌ Cloudflare Stream processing error:', error);
      throw new Error(`Cloudflare Stream processing failed: ${error.message}`);
    }
  }

  /**
   * Upload video file to Cloudflare Stream
   */
  async uploadVideo(videoPath, videoName, userId) {
    try {
      if (!fs.existsSync(videoPath)) {
        throw new Error(`Video file not found: ${videoPath}`);
      }

      const formData = new FormData();
      formData.append('file', fs.createReadStream(videoPath));
      
      // Optional: Add metadata
      formData.append('meta', JSON.stringify({
        name: videoName,
        userId: userId,
        uploadedAt: new Date().toISOString()
      }));

      const response = await axios.post(
        `${this.apiUrl}`,
        formData,
        {
          headers: {
            'Authorization': `Bearer ${this.apiToken}`,
            ...formData.getHeaders()
          },
          maxContentLength: Infinity,
          maxBodyLength: Infinity,
          timeout: 10 * 60 * 1000 // 10 minutes timeout
        }
      );

      if (response.data && response.data.result) {
        return {
          videoId: response.data.result.uid,
          status: response.data.result.status,
          created: response.data.result.created
        };
      }

      throw new Error('Invalid response from Cloudflare Stream API');
      
    } catch (error) {
      console.error('❌ Error uploading to Cloudflare Stream:', error.response?.data || error.message);
      throw error;
    }
  }

  /**
   * Wait for video transcoding to complete
   */
  async waitForTranscoding(videoId, maxWaitTime = 10 * 60 * 1000) {
    const startTime = Date.now();
    const pollInterval = 5000; // Check every 5 seconds
    
    while (Date.now() - startTime < maxWaitTime) {
      const videoInfo = await this.getVideoInfo(videoId);
      
      if (videoInfo.status === 'ready') {
        return {
          videoId: videoId,
          playbackUrl: videoInfo.playback?.hls || videoInfo.playback?.dash || '',
          downloadUrl: videoInfo.downloadUrl || '',
          status: videoInfo.status
        };
      }
      
      if (videoInfo.status === 'error') {
        throw new Error(`Video transcoding failed: ${videoInfo.error || 'Unknown error'}`);
      }
      
      // Status is 'pending' or 'downloading' or 'queued' or 'encoding'
      console.log(`   Status: ${videoInfo.status}, waiting...`);
      await new Promise(resolve => setTimeout(resolve, pollInterval));
    }
    
    throw new Error('Transcoding timeout: Video did not complete within 10 minutes');
  }

  /**
   * Get video information from Cloudflare Stream
   */
  async getVideoInfo(videoId) {
    try {
      const response = await axios.get(
        `${this.apiUrl}/${videoId}`,
        {
          headers: {
            'Authorization': `Bearer ${this.apiToken}`
          }
        }
      );

      if (response.data && response.data.result) {
        const result = response.data.result;
        return {
          videoId: result.uid,
          status: result.status?.state || 'unknown',
          duration: result.duration || 0,
          size: result.size || 0,
          width: result.input?.width || result.meta?.width || 480,
          height: result.input?.height || result.meta?.height || 854,
          playback: result.playback || {},
          downloadUrl: result.downloadUrl || '',
          error: result.status?.error || null
        };
      }

      throw new Error('Invalid response from Cloudflare Stream API');
      
    } catch (error) {
      console.error('❌ Error getting video info:', error.response?.data || error.message);
      throw error;
    }
  }

  /**
   * Download transcoded video from Cloudflare Stream
   * Downloads the 480p version for cost optimization
   */
  async downloadTranscodedVideo(videoId, videoName, userId) {
    try {
      // Get video info to get download URL
      const videoInfo = await this.getVideoInfo(videoId);
      
      if (!videoInfo.downloadUrl) {
        // If no direct download URL, use the HLS playlist and extract segments
        // For simplicity, we'll use the playback URL and download the first segment
        console.log('⚠️ No direct download URL, using playback URL');
        return null; // Will need to handle HLS differently
      }

      const tempDir = path.join(process.cwd(), 'temp');
      if (!fs.existsSync(tempDir)) {
        fs.mkdirSync(tempDir, { recursive: true });
      }

      const sanitizedFileName = videoName.replace(/[<>:"/\\|?*]/g, '_').replace(/:/g, '-');
      const localPath = path.join(tempDir, `${sanitizedFileName}_480p_${Date.now()}.mp4`);

      console.log('📥 Downloading from:', videoInfo.downloadUrl);
      
      const response = await axios({
        method: 'GET',
        url: videoInfo.downloadUrl,
        responseType: 'stream',
        timeout: 10 * 60 * 1000 // 10 minutes
      });

      const writer = fs.createWriteStream(localPath);
      response.data.pipe(writer);

      return new Promise((resolve, reject) => {
        const timeout = setTimeout(() => {
          writer.destroy();
          reject(new Error('Download timeout after 10 minutes'));
        }, 10 * 60 * 1000);

        writer.on('finish', () => {
          clearTimeout(timeout);
          console.log('✅ Video downloaded from Stream');
          resolve(localPath);
        });

        writer.on('error', (error) => {
          clearTimeout(timeout);
          reject(error);
        });
      });
      
    } catch (error) {
      console.error('❌ Error downloading video from Stream:', error);
      throw error;
    }
  }

  /**
   * Delete video from Cloudflare Stream
   */
  async deleteVideo(videoId) {
    try {
      await axios.delete(
        `${this.apiUrl}/${videoId}`,
        {
          headers: {
            'Authorization': `Bearer ${this.apiToken}`
          }
        }
      );
      
      console.log('✅ Video deleted from Cloudflare Stream:', videoId);
      return true;
      
    } catch (error) {
      console.warn('⚠️ Failed to delete video from Stream:', error.response?.data || error.message);
      return false;
    }
  }

  /**
   * Get original video information from video file using ffprobe
   * This preserves original dimensions before Stream processing
   */
  async getOriginalVideoInfo(videoPath) {
    try {
      return new Promise((resolve, reject) => {
        // Check if ffprobe is available first
        const ffprobeCheck = spawn('ffprobe', ['-version']);
        
        ffprobeCheck.on('error', (error) => {
          console.log('⚠️ FFprobe not available, using fallback video info');
          resolve({
            width: 1080,
            height: 1920,
            aspectRatio: 9/16,
            duration: 0,
            codec: 'unknown',
            format: 'mp4'
          });
        });
        
        ffprobeCheck.on('close', (code) => {
          if (code !== 0) {
            console.log('⚠️ FFprobe not working, using fallback video info');
            resolve({
              width: 1080,
              height: 1920,
              aspectRatio: 9/16,
              duration: 0,
              codec: 'unknown',
              format: 'mp4'
            });
            return;
          }
          
          // FFprobe is available, proceed with normal detection
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
            if (code !== 0) {
              console.log('⚠️ FFprobe failed, using fallback video info');
              resolve({
                width: 1080,
                height: 1920,
                aspectRatio: 9/16,
                duration: 0,
                codec: 'unknown',
                format: 'mp4'
              });
              return;
            }

            try {
              const info = JSON.parse(output);
              const videoStream = info.streams.find(stream => stream.codec_type === 'video');
              
              if (!videoStream) {
                console.log('⚠️ No video stream found, using fallback video info');
                resolve({
                  width: 1080,
                  height: 1920,
                  aspectRatio: 9/16,
                  duration: 0,
                  codec: 'unknown',
                  format: 'mp4'
                });
                return;
              }

              const width = parseInt(videoStream.width);
              const height = parseInt(videoStream.height);
              const aspectRatio = width / height;
              
              console.log('📊 Original video dimensions:', { width, height, aspectRatio });
              
              resolve({
                width,
                height,
                aspectRatio,
                duration: parseFloat(info.format.duration) || 0,
                size: parseInt(info.format.size) || 0,
                isPortrait: aspectRatio < 1.0,
                isLandscape: aspectRatio >= 1.0
              });
            } catch (parseError) {
              console.log('⚠️ Failed to parse video info, using fallback');
              resolve({
                width: 1080,
                height: 1920,
                aspectRatio: 9/16,
                duration: 0,
                codec: 'unknown',
                format: 'mp4'
              });
            }
          });
        });
      });
    } catch (error) {
      console.log('⚠️ Error getting original video info, using fallback:', error.message);
      return {
        width: 1080,
        height: 1920,
        aspectRatio: 9/16,
        duration: 0,
        codec: 'unknown',
        format: 'mp4'
      };
    }
  }

  /**
   * Generate thumbnail from Stream video
   * Cloudflare Stream provides thumbnail URLs automatically
   */
  async getThumbnailUrl(videoId) {
    try {
      const videoInfo = await this.getVideoInfo(videoId);
      
      // Cloudflare Stream provides thumbnail URL in the response
      if (videoInfo.thumbnail) {
        return videoInfo.thumbnail;
      }
      
      // Fallback: construct thumbnail URL
      return `https://customer-${this.accountId}.cloudflarestream.com/${videoId}/thumbnails/thumbnail.jpg`;
      
    } catch (error) {
      console.warn('⚠️ Failed to get thumbnail URL:', error.message);
      return null;
    }
  }
}

export default new CloudflareStreamService();

