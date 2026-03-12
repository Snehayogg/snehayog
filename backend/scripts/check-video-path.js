// Create: scripts/check-video-paths.js
import Video from '../models/Video.js';
import mongoose from 'mongoose';
import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';

dotenv.config();

async function checkVideoPaths() {
  await mongoose.connect(process.env.MONGO_URI);
  
  const videos = await Video.find({ processingStatus: 'completed' })
    .select('videoName link hlsMasterPlaylistUrl')
    .limit(10);
  
  console.log('Checking video file locations:\n');
  
  videos.forEach((v, i) => {
    console.log(`${i + 1}. "${v.videoName}"`);
    console.log(`   Link: ${v.link}`);
    console.log(`   HLS URL: ${v.hlsMasterPlaylistUrl}`);
    
    const possiblePaths = [
      v.link,
      path.join(process.cwd(), v.link?.replace(/^\//, '')),
      path.join(process.cwd(), 'uploads', 'videos', path.basename(v.link || '')),
    ];
    
    possiblePaths.forEach(p => {
      const exists = fs.existsSync(p);
      console.log(`   ${exists ? '✅' : '❌'} ${p}`);
    });
    console.log();
  });
  
  await mongoose.disconnect();
}

checkVideoPaths();