import express from 'express';
import multer from 'multer';
import fs from 'fs';
import path from 'path';
import { verifyToken, passiveVerifyToken } from '../utils/verifytoken.js';
import * as dubbingController from '../controllers/video/dubbingController.js';

const router = express.Router();

// Specific multer config for audio
const audioStorage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = 'uploads/temp/audio/';
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    cb(null, `audio_${Date.now()}${path.extname(file.originalname)}`);
  }
});

const uploadAudio = multer({
  storage: audioStorage,
  limits: { fileSize: 50 * 1024 * 1024 } // 50MB for audio is plenty
});

/**
 * Dubbing & AI Routes
 */
router.post('/transcribe', passiveVerifyToken, uploadAudio.single('audio'), dubbingController.transcribeAudio);
router.post('/synthesize', passiveVerifyToken, dubbingController.synthesizeSpeech);
router.post('/translate', passiveVerifyToken, dubbingController.translateText);

export default router;
