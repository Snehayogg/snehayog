import axios from 'axios';
import { promisify } from 'util';
import stream from 'stream';
const pipeline = promisify(stream.pipeline);
import fs from 'fs';
import path from 'path';
import ffmpeg from 'fluent-ffmpeg';
import localAiService from './localAiService.js';
import cloudflareR2Service from './cloudflareR2Service.js';
import ffmpegStatic from 'ffmpeg-static';
import ffprobeStatic from 'ffprobe-static';

ffmpeg.setFfmpegPath(ffmpegStatic);
ffmpeg.setFfprobePath(ffprobeStatic.path);

class DubbingService {
  constructor() {
    this.tasks = new Map();
  }

  /**
   * Start the Smart Dub process
   */
  async startSmartDub({ userId, videoId, videoFile }) {
    const taskId = `task_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
    
    // Initial task state
    this.tasks.set(taskId, {
      status: 'starting',
      progress: 0,
      userId,
      videoId,
      startTime: new Date()
    });

    // Start background processing
    this._processDubbing(taskId, videoId, videoFile).catch(err => {
      console.error(`❌ Task ${taskId} failed:`, err);
      this.tasks.set(taskId, { ...this.tasks.get(taskId), status: 'failed', error: err.message });
    });

    return { taskId };
  }

  /**
   * Internal Background Processing
   */
  async _processDubbing(taskId, videoId, videoFile) {
    const task = this.tasks.get(taskId);
    let localVideoPath = videoFile?.path;
    let isTempFile = false;
    
    try {
      // 1. Resolve Video Path
      if (!localVideoPath) {
        if (!videoId) throw new Error('No video file or videoId provided');
        
        this._updateTask(taskId, 'fetching_video', 5);
        const Video = (await import('../models/Video.js')).default;
        const video = await Video.findById(videoId);
        if (!video) throw new Error('Video not found in database');
        
        // **CACHE CHECK**: If video is already dubbed, skip processing
        // Note: For now we default to Hindi -> English/Hinglish
        // In a real scenario, we might check a specific requested language
        const potentialTarget = 'english'; // Default assumption for cache check
        if (video.dubbedUrls && video.dubbedUrls.get(potentialTarget)) {
           const cachedUrl = video.dubbedUrls.get(potentialTarget);
           console.log(`🚀 Found cached dubbed version for ${videoId}: ${cachedUrl}`);
           this._updateTask(taskId, 'completed', 100, { finalVideoPath: cachedUrl });
           return;
        }

        const videoUrl = video.videoUrl;
        
        // **FIX: If video is HLS (m3u8), do NOT download it manually.**
        // FFmpeg handles m3u8 URLs directly and can mux from them.
        if (videoUrl.includes('.m3u8')) {
          localVideoPath = videoUrl;
          console.log(`🌐 Using remote HLS playlist directly: ${localVideoPath}`);
        } else if (videoUrl.startsWith('http')) {
          this._updateTask(taskId, 'downloading', 10);
          const tempDir = path.join(process.cwd(), 'temp');
          if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });
          
          localVideoPath = path.join(tempDir, `dub_src_${Date.now()}_${path.basename(videoUrl)}`);
          // Ensure we don't double extension or use m3u8
          if (!localVideoPath.toLowerCase().endsWith('.mp4')) {
             localVideoPath += '.mp4';
          }
          
          const response = await axios({
            method: 'get',
            url: videoUrl,
            responseType: 'stream'
          });
          
          await pipeline(response.data, fs.createWriteStream(localVideoPath));
          isTempFile = true;
          console.log(`✅ Downloaded remote video to: ${localVideoPath}`);
        } else {
          localVideoPath = videoUrl;
        }
      }

      // 1. Extract Audio
      this._updateTask(taskId, 'extracting_audio', 15);
      const audioPath = await this._extractAudio(localVideoPath);

      // 2. Transcribe & Detect Language (LOCAL)
      this._updateTask(taskId, 'transcribing', 35);
      const transcription = await localAiService.transcribe(audioPath);
      
      const sourceLang = transcription.language || 'hindi';

      // 3. Smart Target Selection
      const targetLang = sourceLang.toLowerCase() === 'hindi' ? 'english' : 'hinglish';
      
      // 4. Translate (LOCAL)
      this._updateTask(taskId, 'translating', 55);
      translatedText = await localAiService.translate(transcription.text, targetLang);

      // 5. Synthesize Voice (LOCAL/SHERPA)
      this._updateTask(taskId, 'synthesizing', 75);
      const localOutputPath = path.join(process.cwd(), 'temp', `local_dubbed_${Date.now()}.wav`);
      dubbedAudioPath = await localAiService.synthesize(translatedText, targetLang, localOutputPath);
      if (!dubbedAudioPath) {
        throw new Error('Local TTS failed to generate audio');
      }

      // 6. Muxing (Merge Video + New Audio)
      this._updateTask(taskId, 'muxing', 90);
      const finalVideoPath = await this._mux(localVideoPath, dubbedAudioPath);

      // **UPLOADS & CACHING**: Upload to R2 and save to DB
      this._updateTask(taskId, 'uploading', 95);
      let publicUrl = finalVideoPath;
      
      try {
        const Video = (await import('../models/Video.js')).default;
        const video = await Video.findById(videoId);
        
        if (video) {
          const fileName = `dubbed_${videoId}_${targetLang}`;
          const uploadResult = await cloudflareR2Service.uploadFileToR2(
            finalVideoPath, 
            `dubbed/${video.uploader}/${fileName}.mp4`,
            'video/mp4'
          );
          
          publicUrl = uploadResult.url;
          
          // Save to dubbedUrls map
          if (!video.dubbedUrls) video.dubbedUrls = new Map();
          video.dubbedUrls.set(targetLang, publicUrl);
          await video.save();
          console.log(`✅ Dubbed video persisted for ${videoId} in ${targetLang}: ${publicUrl}`);
        }
      } catch (uploadErr) {
        console.error('⚠️ Failed to persist dubbed video:', uploadErr.message);
        // We still return the local path as a fallback for the current task
      }
      
      // 7. Cleanup & Done
      this._updateTask(taskId, 'completed', 100, { finalVideoPath: publicUrl });
      
      // Cleanup
      if (fs.existsSync(audioPath)) fs.unlinkSync(audioPath);
      if (fs.existsSync(dubbedAudioPath)) fs.unlinkSync(dubbedAudioPath);
      if (isTempFile && fs.existsSync(localVideoPath)) fs.unlinkSync(localVideoPath);

      console.log(`✅ Dubbing complete for task ${taskId}: ${finalVideoPath}`);

    } catch (error) {
      // Cleanup on error
      if (isTempFile && localVideoPath && fs.existsSync(localVideoPath)) {
        try { fs.unlinkSync(localVideoPath); } catch (_) {}
      }
      throw error;
    }
  }

  _updateTask(taskId, status, progress, extra = {}) {
    const current = this.tasks.get(taskId);
    this.tasks.set(taskId, { ...current, status, progress, ...extra });
  }

  async getTaskStatus(taskId) {
    return this.tasks.get(taskId);
  }

  // --- Helper Methods (Stubs/Placeholders) ---

  async _extractAudio(videoPath) {
    const tempDir = path.join(process.cwd(), 'temp');
    if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });
    
    const audioPath = path.join(tempDir, `extracted_${Date.now()}.mp3`);
    
    return new Promise((resolve, reject) => {
      ffmpeg(videoPath)
        .toFormat('mp3')
        .on('end', () => resolve(audioPath))
        .on('error', (err) => {
          console.error('❌ Audio extraction failed:', err);
          reject(err);
        })
        .save(audioPath);
    });
  }

  // --- Helper Methods ---

  async _mux(videoPath, audioPath) {
    const tempDir = path.join(process.cwd(), 'temp');
    if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });
    
    // We want to generate a unique filename for the output
    const timestamp = Date.now();
    const outputPath = path.join(tempDir, `final_dubbed_${timestamp}.mp4`);
    
    return new Promise((resolve, reject) => {
      ffmpeg(videoPath)
        .input(audioPath)
        .outputOptions('-c:v copy')
        .outputOptions('-map 0:v:0')
        .outputOptions('-map 1:a:0')
        .on('end', () => resolve(outputPath))
        .on('error', (err) => {
          console.error('❌ Muxing failed:', err);
          reject(err);
        })
        .save(outputPath);
    });
  }
}

import FormData from 'form-data';
export default new DubbingService();
