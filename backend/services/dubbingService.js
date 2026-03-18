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
import Video from '../models/Video.js';

ffmpeg.setFfmpegPath(ffmpegStatic);
ffmpeg.setFfprobePath(ffprobeStatic.path);

class DubbingService {
  constructor() {
    this.tasks = new Map();
  }

  /**
   * Start the Smart Dub process.
   * Returns { taskId } immediately while processing in background.
   */
  async startSmartDub({ userId, videoId }) {
    const taskId = `task_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;

    this.tasks.set(taskId, {
      status: 'starting',
      progress: 0,
      userId,
      videoId,
      startTime: new Date(),
    });

    // Fire-and-forget background processing
    this._processDubbing(taskId, videoId).catch(err => {
      console.error(`❌ Task ${taskId} failed:`, err);
      const current = this.tasks.get(taskId) || {};
      this.tasks.set(taskId, { ...current, status: 'failed', error: err.message });
    });

    return { taskId };
  }

  async _processDubbing(taskId, videoId) {
    let localVideoPath = null;
    let isTempFile = false;
    let audioPath = null;
    let clipPath = null;
    let dubbedAudioPath = null;
    let finalVideoPath = null;

    try {
      // ── 1. Load Video from DB ────────────────────────────────
      this._updateTask(taskId, 'fetching_video', 5);
      const video = await Video.findById(videoId);
      if (!video) throw new Error('Video not found in database');

      let targetLang = 'english'; // Default target for initial cache check
      
      // ── 2. Cache Check ───────────────────────────────────────
      if (video.dubbedUrls && video.dubbedUrls.get && (video.dubbedUrls.get('english') || video.dubbedUrls.get('hindi'))) {
        const cachedUrl = video.dubbedUrls.get('english') || video.dubbedUrls.get('hindi');
        console.log(`🚀 Cache hit for ${videoId}: ${cachedUrl}`);
        this._updateTask(taskId, 'completed', 100, { dubbedUrl: cachedUrl, fromCache: true });
        return;
      }

      // ── 3. Duration Guard ────────────────────────────────────
      const durationSec = video.duration || 0;
      if (durationSec > 0 && durationSec < 5) {
        this._updateTask(taskId, 'not_suitable', 100, { reason: 'too_short' });
        return;
      }
      if (durationSec > 600) {
        this._updateTask(taskId, 'not_suitable', 100, { reason: 'too_long' });
        return;
      }

      // ── 4. Resolve Video Path ────────────────────────────────
      this._updateTask(taskId, 'downloading', 10);
      const videoUrl = video.videoUrl;

      if (videoUrl.includes('.m3u8')) {
        // HLS — feed directly to FFmpeg
        localVideoPath = videoUrl;
      } else if (videoUrl.startsWith('http')) {
        const tempDir = path.join(process.cwd(), 'temp');
        if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });
        localVideoPath = path.join(tempDir, `dub_src_${Date.now()}.mp4`);
        const response = await axios({ method: 'get', url: videoUrl, responseType: 'stream' });
        await pipeline(response.data, fs.createWriteStream(localVideoPath));
        isTempFile = true;
        console.log(`✅ Downloaded to: ${localVideoPath}`);
      } else {
        localVideoPath = videoUrl;
      }

      // ── 5. Smart Filter: 30-second speech pre-check ─────────
      this._updateTask(taskId, 'checking_content', 18);
      clipPath = await localAiService.extractAudioClip(localVideoPath, 30);
      const speechCheck = await localAiService.checkSpeechContent(clipPath);

      if (!speechCheck.isSuitable) {
        console.log(`🚫 Video ${videoId} skipped: ${speechCheck.reason} (${speechCheck.wordCount} words in 30s)`);
        this._updateTask(taskId, 'not_suitable', 100, { reason: speechCheck.reason, wordCount: speechCheck.wordCount });
        return;
      }

      console.log(`✅ Speech detected (${speechCheck.wordCount} words in 30s) — proceeding`);

      // ── 6. Extract Full Audio ────────────────────────────────
      this._updateTask(taskId, 'extracting_audio', 25);
      audioPath = await this._extractAudio(localVideoPath);

      // ── 7. Transcribe Full Audio ─────────────────────────────
      this._updateTask(taskId, 'transcribing', 40);
      const transcription = await localAiService.transcribe(audioPath);
      
      // **NEW: Directional Dubbing Logic**
      // If detected as English -> Dub to Hindi. 
      // If detected as Hindi/Other -> Dub to English.
      let sourceLang = transcription.language || 'hindi';
      targetLang = 'english';
      
      if (sourceLang.toLowerCase().includes('eng')) {
        sourceLang = 'english';
        targetLang = 'hindi';
      } else {
        sourceLang = 'hindi';
        targetLang = 'english';
      }
      
      console.log(`🎙️ Transcribed (${sourceLang}) -> Target (${targetLang}): "${transcription.text.substring(0, 80)}..."`);

      if (!transcription.text || transcription.text.trim().length < 5) {
        this._updateTask(taskId, 'not_suitable', 100, { reason: 'no_transcribable_speech' });
        return;
      }

      // ── 8. Translate ─────────────────────────────────────────
      this._updateTask(taskId, 'translating', 58);
      console.log(`🌐 Translating ${sourceLang} → ${targetLang}...`);
      const translatedText = await localAiService.translate(transcription.text, targetLang, sourceLang);
      console.log(`🌐 Translated: "${translatedText.substring(0, 80)}..."`);

      // ── 9. Synthesize Voice ──────────────────────────────────
      this._updateTask(taskId, 'synthesizing', 72);
      const localOutputPath = path.join(process.cwd(), 'temp', `dubbed_${Date.now()}.mp3`);
      dubbedAudioPath = await localAiService.synthesize(translatedText, targetLang, localOutputPath);
      if (!dubbedAudioPath) throw new Error('TTS failed — gTTS and Piper both unavailable');

      // ── 10. Mux Video + New Audio ────────────────────────────
      this._updateTask(taskId, 'muxing', 85);
      finalVideoPath = await this._mux(localVideoPath, dubbedAudioPath);

      // ── 11. Upload to R2 + Persist ───────────────────────────
      this._updateTask(taskId, 'uploading', 93);
      let publicUrl = finalVideoPath;

      try {
        const fileName = `dubbed/${video.uploader}/dubbed_${videoId}_${targetLang}.mp4`;
        const uploadResult = await cloudflareR2Service.uploadFileToR2(finalVideoPath, fileName, 'video/mp4');
        publicUrl = uploadResult.url;

        // Save to dubbedUrls map — shared cache for all users
        if (!video.dubbedUrls) video.dubbedUrls = new Map();
        video.dubbedUrls.set(targetLang, publicUrl);
        await video.save();
        console.log(`✅ Dubbed video cached for ${videoId} [${targetLang}]: ${publicUrl}`);
        console.log(`💾 Database record updated successfully for video ${videoId}`);
      } catch (uploadErr) {
        console.error('⚠️ R2 upload failed, returning local path:', uploadErr.message);
      }

      // ── 12. Done ─────────────────────────────────────────────
      this._updateTask(taskId, 'completed', 100, { dubbedUrl: publicUrl });
      console.log(`✅ Dubbing complete for task ${taskId}`);

    } finally {
      // Cleanup temp files
      for (const p of [clipPath, audioPath, dubbedAudioPath, finalVideoPath]) {
        try { if (p && fs.existsSync(p)) fs.unlinkSync(p); } catch (_) {}
      }
      if (isTempFile && localVideoPath) {
        try { if (fs.existsSync(localVideoPath)) fs.unlinkSync(localVideoPath); } catch (_) {}
      }
    }
  }

  _updateTask(taskId, status, progress, extra = {}) {
    const current = this.tasks.get(taskId) || {};
    this.tasks.set(taskId, { ...current, status, progress, updatedAt: new Date(), ...extra });
  }

  async getTaskStatus(taskId) {
    return this.tasks.get(taskId) || null;
  }

  // ── Helpers ───────────────────────────────────────────────────

  async _extractAudio(videoPath) {
    const tempDir = path.join(process.cwd(), 'temp');
    if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });
    const audioPath = path.join(tempDir, `extracted_${Date.now()}.mp3`);

    return new Promise((resolve, reject) => {
      const isUrl = typeof videoPath === 'string' && videoPath.startsWith('http');
      const command = ffmpeg(videoPath)
        .noVideo();

      if (isUrl) {
        command.inputOptions([
          '-reconnect 1',
          '-reconnect_at_eof 1',
          '-reconnect_streamed 1',
          '-reconnect_delay_max 2'
        ]);
      }

      command
        .toFormat('mp3')
        .on('end', () => resolve(audioPath))
        .on('error', (err, stdout, stderr) => {
          console.error('❌ FFmpeg audio extraction error:', stderr);
          reject(err);
        })
        .save(audioPath);
    });
  }

  async _mux(videoPath, audioPath) {
    const tempDir = path.join(process.cwd(), 'temp');
    if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });
    const outputPath = path.join(tempDir, `final_dubbed_${Date.now()}.mp4`);

    return new Promise((resolve, reject) => {
      const isUrl = typeof videoPath === 'string' && videoPath.startsWith('http');
      const command = ffmpeg(videoPath);

      if (isUrl) {
        command.inputOptions([
          '-reconnect 1',
          '-reconnect_at_eof 1',
          '-reconnect_streamed 1',
          '-reconnect_delay_max 2'
        ]);
      }

      // Add the second input AFTER setting options for the first one
      command.input(audioPath);

      command
        .outputOptions(['-c:v copy', '-map 0:v:0', '-map 1:a:0', '-shortest'])
        .on('end', () => resolve(outputPath))
        .on('error', (err, stdout, stderr) => {
          console.error('❌ FFmpeg muxing error:', stderr);
          reject(err);
        })
        .save(outputPath);
    });
  }
}

export default new DubbingService();
