import { Worker } from 'bullmq';
import mongoose from 'mongoose';
import Video from '../models/Video.js';
import dotenv from 'dotenv';
import { redisOptions } from '../services/queueService.js';
import axios from 'axios';

dotenv.config();

const connectDB = async () => {
  try {
    await mongoose.connect(process.env.MONGO_URI);
    console.log('📦 Dubbing Worker MongoDB Connected');
  } catch (error) {
    console.error('❌ Dubbing Worker MongoDB Connection Error:', error);
    process.exit(1);
  }
};

connectDB();

const dubbingWorker = new Worker('video-dubbing', async (job) => {
  const { videoId, targetLanguage } = job.data;
  try {
    const video = await Video.findById(videoId);
    if (!video) throw new Error('Video not found');
    
    // original video URL from where the python worker can download it
    const sourceVideoUrl = video.videoUrl;

    const pythonApiUrl = process.env.PYTHON_DUBBING_API_URL || 'http://localhost:8000/dubbing/start';
    const webhookUrl = `${process.env.WEBHOOK_BASE_URL || 'https://api.vayu.com'}/api/dubbing/webhook`;

    console.log(`🚀 Sending dubbing request to Python API for video ${videoId} -> ${targetLanguage}`);
    
    // In production, this call triggers the Serverless Python function
    const response = await axios.post(pythonApiUrl, {
      videoId: videoId,
      videoUrl: sourceVideoUrl,
      targetLanguage: targetLanguage,
      webhookUrl: webhookUrl,
      webhookSecret: process.env.DUBBING_WEBHOOK_SECRET || 'secret'
    });

    console.log(`✅ Dubbing job dispatched to Python API: ${response.data.jobId}`);
    return { status: 'dispatched', jobId: response.data.jobId };
  } catch (error) {
    console.error(`❌ Dubbing Worker Error for ${videoId}:`, error.message);
    throw error;
  }
}, {
  connection: redisOptions,
  concurrency: 2
});

dubbingWorker.on('completed', (job) => {
  console.log(`✅ Dubbing Job ${job.id} process dispatched!`);
});

dubbingWorker.on('failed', (job, err) => {
  console.log(`❌ Dubbing Job ${job.id} failed: ${err.message}`);
});

console.log('👷 Dubbing Worker Started and Listening for jobs...');
