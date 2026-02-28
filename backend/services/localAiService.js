import path from 'path';
import fs from 'fs';
import wavefile from 'wavefile';
const { WaveFile } = wavefile;
import ffmpeg from 'fluent-ffmpeg';
import ffmpegStatic from 'ffmpeg-static';

ffmpeg.setFfmpegPath(ffmpegStatic);

class LocalAiService {
  constructor() {
    this.sttPipe = null;
    this.translatePipe = null;
    this.ttsEngine = null;
    this.initialized = false;
  }

  async initialize() {
    if (this.initialized) return;
    
    try {
      const { pipeline, env } = await import('@xenova/transformers');
      
      // Configure to cache in local project dir to avoid shared cache issues
      env.cacheDir = path.join(process.cwd(), '.cache', 'transformers');
      
      console.log('🤖 LocalAiService: Initializing local models...');
      
      // 1. Transcription (Whisper)
      console.log('🎙️ Loading Whisper-tiny...');
      this.sttPipe = await pipeline('automatic-speech-recognition', 'Xenova/whisper-tiny');

      // 2. Translation (NLLB-200)
      console.log('🌐 Loading NLLB-200-distilled-600M...');
      this.translatePipe = await pipeline('translation', 'Xenova/nllb-200-distilled-600M');
    } catch (err) {
      console.error('❌ LocalAiService Initialization Error:', err.message);
      throw err;
    }

    this.initialized = true;
    console.log('✅ LocalAiService: Models loaded successfully');
  }

  async _decodeAudio(audioPath) {
    const tempWavPath = path.join(process.cwd(), 'temp', `stt_decode_${Date.now()}.wav`);
    
    // Use FFmpeg to convert to 16kHz Mono WAV
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
    
    wav.toBitDepth('32f'); // Convert to float32
    wav.toSampleRate(16000); // Ensure 16kHz
    
    const samples = wav.getSamples();
    
    // Cleanup
    if (fs.existsSync(tempWavPath)) fs.unlinkSync(tempWavPath);
    
    return samples;
  }

  async transcribe(audioPath) {
    await this.initialize();
    
    console.log('🎙️ Transcribing locally...');
    
    // Decode audio to Float32Array (required by transformers in Node)
    const audioData = await this._decodeAudio(audioPath);
    
    const result = await this.sttPipe(audioData, {
      chunk_length_s: 30,
      stride_length_s: 5,
    });
    
    return {
      text: result.text,
      language: 'hindi' 
    };
  }

  async translate(text, targetLang) {
    await this.initialize();
    
    // NLLB Language Codes: hin_Deva (Hindi), eng_Latn (English)
    const targetCode = targetLang === 'hindi' ? 'hin_Deva' : 'eng_Latn';
    
    console.log(`🌐 Translating to ${targetLang}...`);
    const output = await this.translatePipe(text, {
      src_lang: 'hin_Deva', // Assuming source is Hindi/Hinglish for Snehayog
      tgt_lang: targetCode,
    });

    return output[0].translation_text;
  }

  async synthesize(text, targetLang, outputPath) {
    // For TTS, we'll use sherpa-onnx (already installed)
    // This requires a separate binary or complex JS binding.
    // Simplifying: If sherpa-onnx is not fully configured, we'll log a warning.
    
    try {
        const { OfflineTts } = await import('sherpa-onnx-node');
        
        // Configuration for Sherpa-ONNX Piper
        // Note: Models must be downloaded to backend/models/ai/tts/
        const modelPath = path.join(process.cwd(), 'models', 'ai', 'tts', 'hi-vits-piper.onnx');
        const tokensPath = path.join(process.cwd(), 'models', 'ai', 'tts', 'tokens.txt');
        
        if (!fs.existsSync(modelPath)) {
            console.warn('⚠️ TTS model not found locally. Placeholder audio fallback is disabled.');
            return null; 
        }

        const tts = new OfflineTts({
            model: {
                vits: {
                    model: modelPath,
                    tokens: tokensPath,
                },
            },
        });

        const audio = tts.generate(text);
        audio.save(outputPath);
        return outputPath;

    } catch (err) {
        console.error('❌ Local TTS Error:', err.message);
        return null;
    }
  }
}

export default new LocalAiService();
