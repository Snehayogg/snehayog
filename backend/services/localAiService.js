import path from 'path';
import fs from 'fs';
import { exec } from 'child_process';
import { promisify } from 'util';
import wavefile from 'wavefile';
const { WaveFile } = wavefile;
import ffmpeg from 'fluent-ffmpeg';
import ffmpegStatic from 'ffmpeg-static';

ffmpeg.setFfmpegPath(ffmpegStatic);

const execAsync = promisify(exec);

class LocalAiService {
  constructor() {
    this.sttPipe = null;
    this.translatePipe = null;
    this.initialized = false;
  }

  async initialize() {
    if (this.initialized) return;

    try {
      const { pipeline, env } = await import('@xenova/transformers');

      // Cache models locally
      env.cacheDir = path.join(process.cwd(), '.cache', 'transformers');

      console.log('🤖 LocalAiService: Initializing local models...');

      // 1. Transcription (Whisper base — auto-detects language, no forced language)
      console.log('🎙️ Loading Whisper-base...');
      this.sttPipe = await pipeline('automatic-speech-recognition', 'Xenova/whisper-base', {
        task: 'transcribe',
        // NOTE: Do NOT set language here — forces model to always output that language
        // Language auto-detection happens at inference time via return_language: true
      });

      // 2. Translation (NLLB-200)
      console.log('🌐 Loading NLLB-200-distilled-600M...');
      this.translatePipe = await pipeline('translation', 'Xenova/nllb-200-distilled-600M');
    } catch (err) {
      console.error('❌ LocalAiService Initialization Error:', err.message);
      throw err;
    }

    this.initialized = true;
    console.log('✅ LocalAiService: Models loaded');
  }

  /**
   * Extract first N seconds of audio from a video for quick pre-check
   */
  async extractAudioClip(videoPath, durationSeconds = 30) {
    const tempDir = path.join(process.cwd(), 'temp');
    if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });
    const clipPath = path.join(tempDir, `clip_${Date.now()}.mp3`);

    return new Promise((resolve, reject) => {
      ffmpeg(videoPath)
        .toFormat('mp3')
        .outputOptions([`-t ${durationSeconds}`]) // Only first N seconds
        .on('end', () => resolve(clipPath))
        .on('error', (err) => reject(err))
        .save(clipPath);
    });
  }

  /**
   * Smart filter: check if video has enough speech to dub.
   * Returns { isSuitable: bool, wordCount: number, reason: string }
   */
  async checkSpeechContent(audioPath) {
    try {
      await this.initialize();
      const audioData = await this._decodeAudio(audioPath);
      const result = await this.sttPipe(audioData, {
        chunk_length_s: 30,
        stride_length_s: 5,
      });

      const text = (result.text || '').trim();
      const words = text.split(/\s+/).filter(w => w.length > 1);
      const wordCount = words.length;

      console.log(`🔍 Speech check: "${text.substring(0, 80)}..." (${wordCount} words)`);

      if (wordCount < 3) {
        return { isSuitable: false, wordCount, reason: 'music_or_no_speech', transcribedText: text };
      }

      return { isSuitable: true, wordCount, reason: 'speech_detected', transcribedText: text };
    } catch (err) {
      console.error('⚠️ Speech check error:', err.message);
      // Default to suitable if check fails — better to try than skip
      return { isSuitable: true, wordCount: 0, reason: 'check_failed' };
    }
  }

  async _decodeAudio(audioPath) {
    const tempDir = path.join(process.cwd(), 'temp');
    if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });
    const tempWavPath = path.join(tempDir, `stt_decode_${Date.now()}.wav`);

    // Convert to 16kHz Mono WAV (required by Whisper)
    await new Promise((resolve, reject) => {
      ffmpeg(audioPath)
        .toFormat('wav')
        .audioChannels(1)
        .audioFrequency(16000)
        .on('end', resolve)
        .on('error', reject)
        .save(tempWavPath);
    });

    const buffer = fs.readFileSync(tempWavPath);
    const wav = new WaveFile(buffer);
    wav.toBitDepth('32f');
    wav.toSampleRate(16000);
    const samples = wav.getSamples();

    if (fs.existsSync(tempWavPath)) fs.unlinkSync(tempWavPath);
    return samples;
  }

  /**
   * Transcribe full audio. Returns { text, language }
   */
  async transcribe(audioPath) {
    await this.initialize();
    console.log('🎙️ Transcribing locally with auto language detection...');

    const audioData = await this._decodeAudio(audioPath);
    const result = await this.sttPipe(audioData, {
      chunk_length_s: 30,
      stride_length_s: 5,
      return_timestamps: false,
      return_language: true, // Ask Whisper to tell us what language it detected
    });

    // Whisper returns detected language in result.language after proper config
    // Default to 'english' if not detected (safer — gives us a dub to hindi)
    const detectedLang = result.language || 'english';
    console.log(`🔍 Detected language: ${detectedLang}`);

    return {
      text: result.text || '',
      language: detectedLang,
    };
  }

  /**
   * Translate text using NLLB-200.
   * sourceLang: 'hindi' | 'hinglish'
   * targetLang: 'english' | 'hindi'
   */
  async translate(text, targetLang, sourceLang = 'hindi') {
    await this.initialize();

    const langMap = {
      hindi: 'hin_Deva',
      english: 'eng_Latn',
      hinglish: 'hin_Deva', // treat hinglish as hindi source
    };

    const srcCode = langMap[sourceLang] || 'hin_Deva';
    const tgtCode = langMap[targetLang] || 'eng_Latn';

    console.log(`🌐 Translating ${sourceLang} → ${targetLang}...`);
    const output = await this.translatePipe(text, {
      src_lang: srcCode,
      tgt_lang: tgtCode,
    });

    return output[0].translation_text;
  }

  /**
   * Text-to-Speech using gTTS (Google TTS via Python subprocess).
   * Falls back to Piper ONNX if available.
   * outputPath: path to save the output .mp3 file
   */
  async synthesize(text, targetLang, outputPath) {
    const pythonScriptPath = path.join(process.cwd(), 'scripts', 'gtts_synthesize.py');
    const gttsLang = targetLang === 'hindi' ? 'hi' : 'en';
    const mp3Path = outputPath.replace(/\.wav$/, '.mp3');

    console.log(`🎙️ Synthesizing "${text.substring(0, 30)}..." to ${mp3Path} using bridge`);

    try {
      // Step 1: gTTS via Bridge Script (using a temp file for the text)
      const textFilePath = path.join(process.cwd(), 'temp', `tts_input_${Date.now()}.txt`);
      if (!fs.existsSync(path.dirname(textFilePath))) fs.mkdirSync(path.dirname(textFilePath), { recursive: true });
      fs.writeFileSync(textFilePath, text, 'utf-8');

      console.log(`🎙️ Calling gTTS bridge via file: ${textFilePath}`);
      await execAsync(`python "${pythonScriptPath}" --file "${textFilePath}" --lang ${gttsLang} --output "${mp3Path}"`, { timeout: 60000 });

      // Cleanup text file
      if (fs.existsSync(textFilePath)) fs.unlinkSync(textFilePath);

      if (fs.existsSync(mp3Path) && fs.statSync(mp3Path).size > 0) {
        console.log(`✅ gTTS success: ${mp3Path}`);
        return mp3Path;
      }
    } catch (gttsErr) {
      console.warn('⚠️ gTTS bridge failed:', gttsErr.message);
    }

    // Strategy 2: Piper ONNX (local model, offline)
    try {
      const { OfflineTts } = await import('sherpa-onnx-node');
      const modelDir = path.join(process.cwd(), 'models', 'ai', 'tts');
      const modelFile = targetLang === 'hindi' ? 'hi-vits-piper.onnx' : 'en-vits-piper.onnx';
      const modelPath = path.join(modelDir, modelFile);
      const tokensPath = path.join(modelDir, 'tokens.txt');

      if (!fs.existsSync(modelPath)) {
        console.warn('⚠️ Piper model not found:', modelPath);
        return null;
      }

      const tts = new OfflineTts({
        model: { vits: { model: modelPath, tokens: tokensPath } },
      });
      const audio = tts.generate(text);
      audio.save(outputPath);
      console.log(`✅ Piper synthesized audio: ${outputPath}`);
      return outputPath;
    } catch (piperErr) {
      console.error('❌ Piper TTS also failed:', piperErr.message);
      return null;
    }
  }
}

export default new LocalAiService();
