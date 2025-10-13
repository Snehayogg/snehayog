import mongoose from 'mongoose';
import Video from '../models/Video.js';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

// Get the directory name in ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load .env from backend root directory
dotenv.config({ path: path.join(__dirname, '..', '.env') });

async function analyzeVideos() {
  try {
    console.log('🔍 Connecting to database...');
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected to database');

    console.log('\n📊 Analyzing videos in database...\n');

    // Get all videos
    const allVideos = await Video.find({}).select('videoName videoUrl thumbnailUrl uploadedAt uploader');
    
    console.log(`📹 Total videos found: ${allVideos.length}\n`);

    // Separate videos by URL type
    const cloudinaryVideos = [];
    const r2Videos = [];
    const localVideos = [];
    const otherVideos = [];

    for (const video of allVideos) {
      if (video.videoUrl.includes('cloudinary.com')) {
        cloudinaryVideos.push(video);
      } else if (video.videoUrl.includes('r2.dev') || video.videoUrl.includes('cloudflare')) {
        r2Videos.push(video);
      } else if (video.videoUrl.includes('uploads') || video.videoUrl.includes('temp')) {
        localVideos.push(video);
      } else {
        otherVideos.push(video);
      }
    }

    // Print summary
    console.log('═══════════════════════════════════════════════════════');
    console.log('📊 VIDEO URL DISTRIBUTION');
    console.log('═══════════════════════════════════════════════════════\n');
    
    console.log(`✅ Cloudflare R2 URLs:  ${r2Videos.length} videos`);
    console.log(`⚠️  Cloudinary URLs:     ${cloudinaryVideos.length} videos (need migration)`);
    console.log(`❌ Local file paths:     ${localVideos.length} videos (processing failed)`);
    console.log(`❓ Other URLs:           ${otherVideos.length} videos\n`);

    // Show Cloudinary videos details
    if (cloudinaryVideos.length > 0) {
      console.log('═══════════════════════════════════════════════════════');
      console.log('⚠️  VIDEOS WITH CLOUDINARY URLS (Need Migration)');
      console.log('═══════════════════════════════════════════════════════\n');
      
      cloudinaryVideos.forEach((video, index) => {
        console.log(`${index + 1}. ${video.videoName}`);
        console.log(`   ID: ${video._id}`);
        console.log(`   URL: ${video.videoUrl.substring(0, 80)}...`);
        console.log(`   Uploaded: ${video.uploadedAt.toLocaleDateString()}`);
        console.log('');
      });
    }

    // Show local file path videos (failed processing)
    if (localVideos.length > 0) {
      console.log('═══════════════════════════════════════════════════════');
      console.log('❌ VIDEOS WITH LOCAL FILE PATHS (Processing Failed)');
      console.log('═══════════════════════════════════════════════════════\n');
      
      localVideos.forEach((video, index) => {
        console.log(`${index + 1}. ${video.videoName}`);
        console.log(`   ID: ${video._id}`);
        console.log(`   URL: ${video.videoUrl}`);
        console.log(`   Uploaded: ${video.uploadedAt.toLocaleDateString()}`);
        console.log('');
      });

      console.log('⚠️  These videos have processing status issues. They should be re-uploaded.');
    }

    // Recommendations
    console.log('\n═══════════════════════════════════════════════════════');
    console.log('💡 RECOMMENDATIONS');
    console.log('═══════════════════════════════════════════════════════\n');

    if (cloudinaryVideos.length > 0) {
      console.log(`📌 You have ${cloudinaryVideos.length} videos with Cloudinary URLs.`);
      console.log('   These videos will work fine but cost more in bandwidth.');
      console.log('');
      console.log('   OPTIONS:');
      console.log('   1. Keep them on Cloudinary (easier, but costs ~$0.04/GB bandwidth)');
      console.log('   2. Migrate to R2 (saves 93% on costs, but requires re-downloading & re-uploading)');
      console.log('   3. Leave old videos on Cloudinary, new videos use R2 (hybrid approach)');
      console.log('');
    }

    if (localVideos.length > 0) {
      console.log(`📌 You have ${localVideos.length} videos with local file paths.`);
      console.log('   These videos failed processing and need to be re-uploaded.');
      console.log('');
    }

    console.log('═══════════════════════════════════════════════════════\n');

    // Ask if user wants to delete failed videos
    if (localVideos.length > 0) {
      console.log('⚠️  CLEANUP OPTION:');
      console.log('   To delete failed videos from database, run:');
      console.log('   node scripts/migrateCloudinaryToR2.js --delete-failed');
      console.log('');
    }

    // Close connection
    await mongoose.connection.close();
    console.log('✅ Analysis complete. Database connection closed.');

  } catch (error) {
    console.error('❌ Error analyzing videos:', error);
    process.exit(1);
  }
}

/**
 * Delete videos with local file paths (failed processing)
 */
async function deleteFailedVideos() {
  try {
    console.log('🔍 Connecting to database...');
    await mongoose.connect(process.env.MONGODB_URI);
    console.log('✅ Connected to database');

    console.log('\n🗑️  Finding videos with local file paths...\n');

    // Find videos with local file paths
    const failedVideos = await Video.find({
      $or: [
        { videoUrl: { $regex: /uploads/i } },
        { videoUrl: { $regex: /temp/i } },
        { videoUrl: { $regex: /^(?!http)/i } } // URLs not starting with http
      ]
    });

    console.log(`Found ${failedVideos.length} videos with local file paths.\n`);

    if (failedVideos.length === 0) {
      console.log('✅ No failed videos to delete.');
      await mongoose.connection.close();
      return;
    }

    // List videos to be deleted
    console.log('Following videos will be DELETED:');
    console.log('═══════════════════════════════════════════════════════\n');
    
    failedVideos.forEach((video, index) => {
      console.log(`${index + 1}. ${video.videoName}`);
      console.log(`   ID: ${video._id}`);
      console.log(`   URL: ${video.videoUrl}`);
      console.log('');
    });

    // Delete videos
    const result = await Video.deleteMany({
      _id: { $in: failedVideos.map(v => v._id) }
    });

    console.log(`\n✅ Deleted ${result.deletedCount} failed videos from database.\n`);

    // Close connection
    await mongoose.connection.close();
    console.log('✅ Cleanup complete. Database connection closed.');

  } catch (error) {
    console.error('❌ Error deleting failed videos:', error);
    process.exit(1);
  }
}

// Main execution
const args = process.argv.slice(2);

if (args.includes('--delete-failed')) {
  console.log('⚠️  WARNING: This will DELETE videos from database!');
  console.log('   Starting deletion in 3 seconds... (Press Ctrl+C to cancel)\n');
  
  setTimeout(() => {
    deleteFailedVideos();
  }, 3000);
} else {
  analyzeVideos();
}

