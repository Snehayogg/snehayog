import { pipeline } from '@xenova/transformers';
import ffmpeg from 'fluent-ffmpeg';
import ffmpegStatic from 'ffmpeg-static';
import path from 'path';
import fs from 'fs';

// Use native crypto if available for session IDs
import nodeCrypto from 'crypto';

ffmpeg.setFfmpegPath(ffmpegStatic);

class LocalModerationService {
  constructor() {
    this.modelName = 'Xenova/nsfw_image_detection';
    this.classifier = null;
    this.tempDir = path.join(process.cwd(), 'uploads', 'temp', 'moderation');
    
    // Ensure temp directory exists
    if (!fs.existsSync(this.tempDir)) {
      fs.mkdirSync(this.tempDir, { recursive: true });
    }
  }

  /**
   * Lazy load the classifier to avoid heavy startup and save memory if not used
   */
  async getClassifier() {
    if (!this.classifier) {
      console.log('🧠 [Moderation] Loading NSFW detection model (Transformers.js)...');
      try {
        this.classifier = await pipeline('image-classification', this.modelName);
        console.log('✅ [Moderation] NSFW Model loaded successfully.');
      } catch (error) {
        console.error('❌ [Moderation] Failed to load NSFW model:', error);
        throw error;
      }
    }
    return this.classifier;
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
      console.log(`🛡️ [Moderation] Starting scan for: ${path.basename(videoPath)}`);
      
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

      const classifier = await this.getClassifier();
      let highestNsfwScore = 0;
      let worstLabel = 'normal';

      // 2. Classify each frame sequentially to manage CPU usage
      for (const frame of frames) {
        const results = await classifier(frame);
        
        // Typical labels for this model: 'nsfw', 'normal'
        // OR granular: 'porn', 'hentai', 'sexy', 'drawings', 'neutral'
        const nsfwCategories = ['nsfw', 'porn', 'hentai', 'sexy'];
        
        for (const res of results) {
          if (nsfwCategories.includes(res.label.toLowerCase())) {
            if (res.score > highestNsfwScore) {
              highestNsfwScore = res.score;
              worstLabel = res.label;
            }
          }
        }

        // Cleanup frame immediately to keep disk usage low
        if (fs.existsSync(frame)) fs.unlinkSync(frame);
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
      // Fail open: We don't want to block videos if the AI service fails temporarily,
      // but we should log it for manual review.
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
      const absoluteVideoPath = path.resolve(videoPath);

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
