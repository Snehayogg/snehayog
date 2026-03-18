import mongoose from 'mongoose';
import Video from './models/Video.js';
import dotenv from 'dotenv';

dotenv.config();

async function findVideo() {
  await mongoose.connect(process.env.MONGO_URI);
  console.log('Connected to DB');

  const videos = await Video.find({ videoUrl: /Peaky/ }).select('videoUrl videoName');
  console.log('Found videos:', videos.length);
  videos.forEach(v => {
    console.log(`- ID: ${v._id}, Name: ${v.videoName}, URL: ${v.videoUrl}`);
  });

  await mongoose.disconnect();
}

findVideo();
