import fs from 'fs';
import path from 'path';
import axios from 'axios';
import { promisify } from 'util';
import stream from 'stream';

const pipeline = promisify(stream.pipeline);

const MODELS_DIR = path.join(process.cwd(), 'models', 'ai');

const MODELS = [
  // Whisper Tiny (STT) - ~150MB
  {
    name: 'encoder_model.onnx',
    url: 'https://huggingface.co/openai/whisper-tiny/resolve/main/onnx/encoder_model.onnx',
    dir: 'whisper'
  },
  // Sherpa-ONNX / Piper Hindi Voice (TTS)
  {
    name: 'hi-vits-piper.onnx',
    url: 'https://huggingface.co/v3io/piper-voices/resolve/main/hi/hi_IN/casper/low/hi_IN-casper-low.onnx',
    dir: 'tts'
  },
  {
    name: 'tokens.txt',
    url: 'https://huggingface.co/v3io/piper-voices/resolve/main/hi/hi_IN/casper/low/hi_IN-casper-low.onnx.json', // We actually need the json for some or tokens.txt
    dir: 'tts'
  }
];

async function downloadModel(model) {
  const targetDir = path.join(MODELS_DIR, model.dir);
  if (!fs.existsSync(targetDir)) fs.mkdirSync(targetDir, { recursive: true });

  const targetPath = path.join(targetDir, model.name);
  if (fs.existsSync(targetPath)) {
    console.log(`✅ Model ${model.name} already exists.`);
    return;
  }

  console.log(`📥 Downloading ${model.name}...`);
  const response = await axios({
    method: 'get',
    url: model.url,
    responseType: 'stream'
  });

  await pipeline(response.data, fs.createWriteStream(targetPath));
  console.log(`✅ Downloaded ${model.name}`);
}

async function main() {
  console.log('🚀 Starting Model Download...');
  for (const model of MODELS) {
    try {
      await downloadModel(model);
    } catch (err) {
      console.error(`❌ Failed to download ${model.name}:`, err.message);
    }
  }
  console.log('🎉 Model download sequence complete.');
}

main();
