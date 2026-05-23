import mongoose from 'mongoose';
import Video from '../models/Video.js';
import dotenv from 'dotenv';
dotenv.config();

async function check() {
  await mongoose.connect(process.env.MONGO_URI);
  const videos = await Video.find({}).sort({ uploadedAt: -1 }).limit(10).select('videoName processingStatus uploadedAt').lean();
  console.log('Last 10 Videos:', JSON.stringify(videos, null, 2));
  process.exit(0);
}

check();
