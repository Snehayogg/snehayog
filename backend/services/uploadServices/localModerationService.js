import axios from 'axios';
import ffmpeg from 'fluent-ffmpeg';
import ffmpegStatic from 'ffmpeg-static';
import path from 'path';
import fs from 'fs';

// Use native crypto if available for session IDs
import nodeCrypto from 'crypto';

ffmpeg.setFfmpegPath(ffmpegStatic);

class LocalModerationService {
  constructor() {
    this.modelUrl = 'https://router.huggingface.co/hf-inference/models/Falconsai/nsfw_image_detection';
    this.hfToken = process.env.HF_TOKEN;
    this.tempDir = path.join(process.cwd(), 'uploads', 'temp', 'moderation');
    
    // Ensure temp directory exists
    if (!fs.existsSync(this.tempDir)) {
      fs.mkdirSync(this.tempDir, { recursive: true });
    }
  }

  /**
   * Classifies an image via Hugging Face Inference API
   * @param {string} imagePath 
   * @returns {Promise<Array>}
   */
  async classifyImage(imagePath) {
    if (!this.hfToken) {
      throw new Error('HF_TOKEN is not configured in .env');
    }

    const token = this.hfToken.trim();

    try {
      const imageBuffer = fs.readFileSync(imagePath);
      const response = await axios.post(this.modelUrl, imageBuffer, {
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/octet-stream',
          'Accept': 'application/json',
        },
        timeout: 20000, // Increase timeout
      });

      return response.data;
    } catch (error) {
      if (error.response?.status === 503) {
        console.warn(`⏳ [Moderation] Model is loading... ${error.response.data?.estimated_time || ''}s`);
        // We could implement a retry here, but for now we'll let the upper layer handle it or return empty
        throw new Error('MODERATION_MODEL_LOADING');
      }
      
      console.error(`❌ [Moderation] HF API Error for ${path.basename(imagePath)}:`, 
        error.response?.status, 
        typeof error.response?.data === 'string' ? error.response.data.substring(0, 100) : error.response?.data
      );
      throw error;
    }
  }

  /**
   * Moderates a video by sampling frames and detecting prohibited content.
   * @param {string} videoPath Local path to the processed video
   * @param {number} frameCount Number of frames to extract (default: 5)
   * @returns {Promise<{isFlagged: boolean, confidence: number, label: string}>}
   */
  async moderateVideo(videoPath, frameCount = 5) {
    let sessionDir = null;
    try {
      console.log(`🛡️ [Moderation] Starting scan for: ${path.basename(videoPath)} (using HF API)`);
      
      const sessionId = nodeCrypto.randomUUID ? nodeCrypto.randomUUID() : `mod_${Date.now()}`;
      sessionDir = path.join(this.tempDir, sessionId);
      
      if (!fs.existsSync(sessionDir)) {
        fs.mkdirSync(sessionDir, { recursive: true });
      }

      // 1. Extract frames from the video
      const frames = await this.extractFrames(videoPath, sessionDir, frameCount);
      if (frames.length === 0) {
        throw new Error('No frames could be extracted for moderation');
      }

      let highestNsfwScore = 0;
      let worstLabel = 'normal';

      // 2. Classify each frame sequentially
      for (const frame of frames) {
        try {
          const results = await this.classifyImage(frame);
          
          // Falconsai/nsfw_image_detection returns labels like 'nsfw' and 'normal'
          // We look for 'nsfw' or other prohibited categories
          const nsfwCategories = ['nsfw', 'porn', 'hentai', 'sexy'];
          
          for (const res of results) {
            if (nsfwCategories.includes(res.label.toLowerCase())) {
              if (res.score > highestNsfwScore) {
                highestNsfwScore = res.score;
                worstLabel = res.label;
              }
            }
          }
        } catch (err) {
          console.warn(`⚠️ [Moderation] Skipping frame ${path.basename(frame)} due to API error.`);
        } finally {
          // Cleanup frame immediately to keep disk usage low
          if (fs.existsSync(frame)) fs.unlinkSync(frame);
        }
      }

      const isFlagged = highestNsfwScore > 0.85; // Strict threshold
      
      console.log(`🛡️ [Moderation] Scan Complete: ${isFlagged ? '🚩 FLAGGED' : '✅ PASSED'}`);
      console.log(`   - Max NSFW Score: ${highestNsfwScore.toFixed(4)}`);
      console.log(`   - Category: ${worstLabel}`);

      return {
        isFlagged,
        confidence: highestNsfwScore,
        label: worstLabel,
        timestamp: new Date()
      };

    } catch (error) {
      console.error('❌ [Moderation] Error during moderation processing:', error);
      return {
        isFlagged: false,
        error: error.message,
        status: 'error'
      };
    } finally {
      // Cleanup session directory
      if (sessionDir && fs.existsSync(sessionDir)) {
        try {
          fs.rmSync(sessionDir, { recursive: true, force: true });
        } catch (err) {
          console.warn('⚠️ [Moderation] Failed to cleanup session dir:', err.message);
        }
      }
    }
  }

  /**
   * Extracts static frames from video using FFmpeg
   */
  async extractFrames(videoPath, outputDir, count) {
    return new Promise((resolve, reject) => {
      const frames = [];
      const absoluteVideoPath = videoPath.startsWith('http') ? videoPath : path.resolve(videoPath);
      
      if (videoPath.startsWith('http')) {
        console.log('🌐 [Moderation] Processing remote video URL:', absoluteVideoPath);
      }

      ffmpeg(absoluteVideoPath)
        .screenshots({
          count: count,
          folder: outputDir,
          filename: 'frame-%i.jpg',
          size: '320x?' // Downscale for significantly faster AI inference
        })
        .on('filenames', (filenames) => {
          filenames.forEach(f => frames.push(path.join(outputDir, f)));
        })
        .on('end', () => {
          console.log(`📸 [Moderation] Extracted ${frames.length} frames for analysis.`);
          resolve(frames);
        })
        .on('error', (err) => {
          console.error('❌ [Moderation] FFmpeg frame extraction failed:', err.message);
          reject(err);
        });
    });
  }
}

export default new LocalModerationService();
