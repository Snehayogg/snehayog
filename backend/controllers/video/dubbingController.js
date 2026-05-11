import AIService from '../../services/aiService.js';
import fs from 'fs';
import path from 'path';

export const transcribeAudio = async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No audio file uploaded' });
    }

    const audioPath = req.file.path;
    
    try {
      const transcript = await AIService.transcribe(audioPath);
      
      // Clean up uploaded file
      fs.unlinkSync(audioPath);
      
      return res.json({ 
        success: true, 
        transcript: transcript 
      });
    } catch (aiError) {
      // Clean up on error too
      if (fs.existsSync(audioPath)) fs.unlinkSync(audioPath);
      
      if (aiError.message === 'MODEL_LOADING') {
        return res.status(503).json({ 
          error: 'AI model is still loading, please try again in a few seconds',
          code: 'MODEL_LOADING'
        });
      }
      throw aiError;
    }
  } catch (error) {
    console.error('❌ [Dubbing Controller] Transcription error:', error);
    res.status(500).json({ error: 'Transcription failed', details: error.message });
  }
};

export const synthesizeSpeech = async (req, res) => {
  try {
    const { text, language } = req.body;
    
    if (!text) {
      return res.status(400).json({ error: 'Text is required for synthesis' });
    }

    const tempDir = path.join(process.cwd(), 'uploads', 'temp', 'tts');
    if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });

    const outputPath = path.join(tempDir, `tts_${Date.now()}.wav`);
    
    try {
      await AIService.synthesize(text, language || 'hindi', outputPath);
      
      // Send the file and then delete it
      res.sendFile(outputPath, (err) => {
        if (fs.existsSync(outputPath)) fs.unlinkSync(outputPath);
        if (err) {
          console.error('❌ [Dubbing Controller] Error sending file:', err);
        }
      });
    } catch (aiError) {
      if (fs.existsSync(outputPath)) fs.unlinkSync(outputPath);
      
      if (aiError.message === 'MODEL_LOADING') {
        return res.status(503).json({ 
          error: 'AI model is still loading, please try again in a few seconds',
          code: 'MODEL_LOADING'
        });
      }
      throw aiError;
    }
  } catch (error) {
    console.error('❌ [Dubbing Controller] Synthesis error:', error);
    res.status(500).json({ error: 'Speech synthesis failed', details: error.message });
  }
};

export const translateText = async (req, res) => {
  try {
    const { text, targetLang } = req.body;
    if (!text) return res.status(400).json({ error: 'Text is required' });

    const translatedText = await AIService.translate(text, targetLang || 'hindi');
    res.json({ success: true, translatedText });
  } catch (error) {
    console.error('❌ [Dubbing Controller] Translation error:', error);
    res.status(500).json({ error: 'Translation failed', details: error.message });
  }
};
