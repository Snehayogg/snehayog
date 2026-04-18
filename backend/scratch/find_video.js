import mongoose from 'mongoose';
import Video from '../models/Video.js';
import dotenv from 'dotenv';
dotenv.config();

async function check() {
  await mongoose.connect(process.env.MONGO_URI);
  const id = '69de58b0ca9b0dbe2b4d95b5'; // From screenshot
  const video = await Video.findById(id);
  console.log('Video found:', video ? video.videoName : 'NOT FOUND');
  process.exit(0);
}

check();
