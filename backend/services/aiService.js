import axios from 'axios';
import fs from 'fs';
import mime from 'mime-types';
import { exec } from 'child_process';
import util from 'util';

const execPromise = util.promisify(exec);

class AIService {
  constructor() {
    this.hfToken = process.env.HF_TOKEN ? process.env.HF_TOKEN.trim() : null;
    
    // Model URLs (using the router endpoint which is more reliable)
    const base = 'https://router.huggingface.co/hf-inference/models';
    this.transcriptionModel = `${base}/openai/whisper-large-v3-turbo`;
    this.ttsHindiModel = `${base}/facebook/mms-tts-hin`;
    this.ttsEnglishModel = `${base}/facebook/mms-tts-eng`;
    this.translationModel = `${base}/facebook/mbart-large-50-many-to-many-mmt`;
  }

  /**
   * Translates text between languages
   */
  async translate(text, targetLang = 'hi_IN') {
    if (!this.hfToken) throw new Error('HF_TOKEN is missing');
    
    try {
      const response = await axios.post(this.translationModel, 
        { 
          inputs: text,
          parameters: { src_lang: "en_XX", tgt_lang: targetLang === 'hindi' ? "hi_IN" : "en_XX" }
        }, 
        {
          headers: { 'Authorization': `Bearer ${this.hfToken}` }
        }
      );
      return response.data[0]?.translation_text || text;
    } catch (error) {
      this._handleError(error, 'Translation');
      return text; // Fallback to original
    }
  }

  /**
   * Transcribes audio file using Whisper via Hugging Face
   * @param {string} audioPath - Path to the audio file
   * @returns {Promise<string>} - Transcribed text
   */
  async transcribe(audioPath) {
    if (!this.hfToken) throw new Error('HF_TOKEN is missing');

    try {
      const audioData = fs.readFileSync(audioPath);
      const mimeType = mime.lookup(audioPath) || 'audio/wav';
      
      console.log(`🎙️ [AI Service] Sending audio to Whisper (${audioData.length} bytes, type: ${mimeType})...`);
      
      const response = await axios.post(this.transcriptionModel, audioData, {
        headers: {
          'Authorization': `Bearer ${this.hfToken}`,
          'Content-Type': mimeType,
          'Accept': 'application/json'
        },
        timeout: 60000 // Transcription can take time
      });

      if (response.data && response.data.text) {
        console.log(`✅ [AI Service] Transcription success: "${response.data.text.substring(0, 50)}..."`);
        return response.data.text;
      }
      
      throw new Error('Transcription response format invalid');
    } catch (error) {
      this._handleError(error, 'Transcription');
      throw error;
    }
  }

  /**
   * Generates high-quality speech from text using Microsoft Edge TTS
   * @param {string} text - Text to synthesize
   * @param {string} language - 'hindi' or 'english'
   * @param {string} outputPath - Path to save the wav/mp3 file
   */
  async synthesize(text, language = 'hindi', outputPath) {
    const voice = language.toLowerCase() === 'hindi' ? 'hi-IN-SwaraNeural' : 'en-US-AriaNeural';

    try {
      console.log(`🔊 [AI Service] Synthesizing ${language} voice with Edge TTS (${voice}) for: "${text.substring(0, 30)}..."`);
      
      // Escape double quotes in text to prevent CLI injection issues
      const safeText = text.replace(/"/g, '\\"');
      
      const command = `edge-tts --text "${safeText}" --voice ${voice} --write-media "${outputPath}"`;
      
      await execPromise(command);
      
      console.log(`✅ [AI Service] Synthesis complete: ${outputPath}`);
      return outputPath;
    } catch (error) {
      console.error(`❌ [AI Service] Synthesis error:`, error.message);
      throw error;
    }
  }

  _handleError(error, context) {
    if (error.response?.status === 503) {
      console.warn(`⏳ [AI Service] ${context} model is loading on Hugging Face...`);
      throw new Error('MODEL_LOADING');
    }
    
    // SANITIZED LOGGING: Prevent token exposure in logs
    let errorMessage = error.message;
    if (error.response?.data) {
       // If data is a string (like HTML error), don't log the whole thing
       if (typeof error.response.data === 'string') {
          errorMessage = error.response.data.substring(0, 200).replace(/hf_[a-zA-Z0-9]+/g, 'hf_****');
       } else {
          errorMessage = JSON.stringify(error.response.data).replace(/hf_[a-zA-Z0-9]+/g, 'hf_****');
       }
    }
    
    console.error(`❌ [AI Service] ${context} error:`, errorMessage);
  }
}

export default new AIService();
