import mongoose from 'mongoose';
import cloudflareR2Service from '../services/cloudflareR2Service.js';
import axios from 'axios';
import fs from 'fs';
import path from 'path';

// Database connection
const connectDB = async () => {
  try {
    await mongoose.connect(process.env.MONGODB_URI || process.env.MONGO_URI);
    console.log('✅ Connected to MongoDB');
  } catch (error) {
    console.error('❌ MongoDB connection error:', error);
    process.exit(1);
  }
};

// Video model (simplified)
const VideoSchema = new mongoose.Schema({
  videoName: String,
  videoUrl: String,
  thumbnailUrl: String,
  lowQualityUrl: String,
  uploader: {
    id: String,
    name: String,
    profilePic: String
  },
  createdAt: { type: Date, default: Date.now }
});

const Video = mongoose.model('Video', VideoSchema);

// Migration function
const migrateVideosToR2 = async () => {
  try {
    console.log('🚀 Starting migration from Cloudinary to R2...');
    
    // Get all videos
    const videos = await Video.find({});
    console.log(`📊 Found ${videos.length} videos to migrate`);
    
    let migrated = 0;
    let failed = 0;
    
    for (const video of videos) {
      try {
        console.log(`\n🔄 Migrating video: ${video.videoName}`);
        
        // Skip if already using R2
        if (video.videoUrl && video.videoUrl.includes('cdn.snehayog.site')) {
          console.log('⏭️  Already using R2, skipping...');
          continue;
        }
        
        // Download video from Cloudinary
        const tempVideoPath = await downloadFromCloudinary(video.videoUrl, video._id.toString());
        
        // Upload to R2
        const r2VideoResult = await cloudflareR2Service.uploadVideoToR2(
          tempVideoPath,
          video.videoName,
          video.uploader.id
        );
        
        // Download and upload thumbnail
        const r2ThumbnailUrl = await cloudflareR2Service.uploadThumbnailToR2(
          video.thumbnailUrl,
          video.videoName,
          video.uploader.id
        );
        
        // Update video in database
        await Video.findByIdAndUpdate(video._id, {
          videoUrl: r2VideoResult.url,
          thumbnailUrl: r2ThumbnailUrl,
          lowQualityUrl: r2VideoResult.url // Same URL for 480p
        });
        
        // Cleanup temp file
        await cloudflareR2Service.cleanupLocalFile(tempVideoPath);
        
        migrated++;
        console.log(`✅ Migrated: ${video.videoName}`);
        
      } catch (error) {
        failed++;
        console.error(`❌ Failed to migrate ${video.videoName}:`, error.message);
      }
    }
    
    console.log(`\n🎉 Migration completed!`);
    console.log(`✅ Successfully migrated: ${migrated} videos`);
    console.log(`❌ Failed: ${failed} videos`);
    
  } catch (error) {
    console.error('❌ Migration error:', error);
  }
};

// Helper function to download from Cloudinary
const downloadFromCloudinary = async (cloudinaryUrl, videoId) => {
  const tempDir = path.join(process.cwd(), 'temp');
  if (!fs.existsSync(tempDir)) {
    fs.mkdirSync(tempDir, { recursive: true });
  }
  
  const localPath = path.join(tempDir, `${videoId}_migration.mp4`);
  
  const response = await axios({
    method: 'GET',
    url: cloudinaryUrl,
    responseType: 'stream'
  });
  
  const writer = fs.createWriteStream(localPath);
  response.data.pipe(writer);
  
  return new Promise((resolve, reject) => {
    writer.on('finish', () => resolve(localPath));
    writer.on('error', reject);
  });
};

// Main execution
const main = async () => {
  await connectDB();
  await migrateVideosToR2();
  process.exit(0);
};

// Run migration
main().catch(console.error);
