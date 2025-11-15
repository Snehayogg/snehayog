import axios from 'axios';
import fs from 'fs';
import path from 'path';
import FormData from 'form-data';

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

      // Step 1: Upload video to Stream
      const uploadResult = await this.uploadVideo(videoPath, videoName, userId);
      console.log('✅ Video uploaded to Stream');
      console.log('   Video ID:', uploadResult.videoId);
      
      // Step 2: Wait for transcoding to complete
      console.log('⏳ Waiting for transcoding to complete...');
      const transcodedVideo = await this.waitForTranscoding(uploadResult.videoId);
      console.log('✅ Transcoding completed');
      
      // Step 3: Get video info
      const videoInfo = await this.getVideoInfo(uploadResult.videoId);
      
      // Step 4: Download the transcoded video (480p quality)
      console.log('📥 Downloading transcoded video from Stream...');
      const downloadedPath = await this.downloadTranscodedVideo(
        transcodedVideo.videoId,
        videoName,
        userId
      );
      
      return {
        videoId: transcodedVideo.videoId,
        videoUrl: transcodedVideo.playbackUrl, // HLS playback URL
        downloadUrl: transcodedVideo.downloadUrl, // Direct download URL
        localPath: downloadedPath,
        duration: videoInfo.duration || 0,
        size: videoInfo.size || 0,
        format: 'mp4',
        width: videoInfo.width || 480,
        height: videoInfo.height || 854,
        aspectRatio: videoInfo.width && videoInfo.height ? 
          videoInfo.width / videoInfo.height : 9/16,
        isPortrait: videoInfo.width && videoInfo.height ? 
          (videoInfo.width / videoInfo.height) < 1.0 : true,
        originalVideoInfo: {
          width: videoInfo.width || 480,
          height: videoInfo.height || 854,
          aspectRatio: videoInfo.width && videoInfo.height ? 
            videoInfo.width / videoInfo.height : 9/16,
          duration: videoInfo.duration || 0
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

