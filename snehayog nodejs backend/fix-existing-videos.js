import mongoose from 'mongoose';
import Video from './models/Video.js';
import config from './config.js';

// MongoDB connection
const connectDB = async () => {
  try {
    await mongoose.connect(config.database.uri, config.database.options);
    console.log('✅ Connected to MongoDB');
  } catch (error) {
    console.error('❌ MongoDB connection failed:', error);
    process.exit(1);
  }
};

// Fix existing videos
const fixExistingVideos = async () => {
  try {
    console.log('🔧 Starting to fix existing videos...');

    // Find all videos
    const videos = await Video.find({});
    console.log(`📹 Found ${videos.length} videos to process`);

    let fixedCount = 0;
    let hlsCount = 0;
    let mp4Count = 0;

    for (const video of videos) {
      let needsUpdate = false;
      let updateFields = {};

      // Check if video has HLS URLs
      const hasHlsMaster = video.hlsMasterPlaylistUrl && video.hlsMasterPlaylistUrl.trim() !== '';
      const hasHlsPlaylist = video.hlsPlaylistUrl && video.hlsPlaylistUrl.trim() !== '';
      const hasAnyHls = hasHlsMaster || hasHlsPlaylist;

      // Check if video URL is HLS
      const videoUrlIsHls = video.videoUrl && (
        video.videoUrl.includes('.m3u8') || 
        video.videoUrl.includes('hls') ||
        video.videoUrl.includes('playlist')
      );

      console.log(`🔍 Processing video: ${video.videoName}`);
      console.log(`   - Has HLS Master: ${hasHlsMaster}`);
      console.log(`   - Has HLS Playlist: ${hasHlsPlaylist}`);
      console.log(`   - Video URL is HLS: ${videoUrlIsHls}`);
      console.log(`   - Current isHLSEncoded: ${video.isHLSEncoded}`);

      // Determine if this should be marked as HLS encoded
      const shouldBeHls = hasAnyHls || videoUrlIsHls;

      if (shouldBeHls) {
        hlsCount++;
        if (video.isHLSEncoded !== true) {
          updateFields.isHLSEncoded = true;
          needsUpdate = true;
          console.log(`   ✅ Will mark as HLS encoded`);
        }

        // If video URL is not HLS but we have HLS URLs, update it
        if (!videoUrlIsHls && hasHlsMaster) {
          updateFields.videoUrl = video.hlsMasterPlaylistUrl;
          needsUpdate = true;
          console.log(`   🔄 Will update videoUrl to HLS master playlist`);
        } else if (!videoUrlIsHls && hasHlsPlaylist) {
          updateFields.videoUrl = video.hlsPlaylistUrl;
          needsUpdate = true;
          console.log(`   🔄 Will update videoUrl to HLS playlist`);
        }
      } else {
        mp4Count++;
        // This is an MP4 video
        if (video.isHLSEncoded !== false) {
          updateFields.isHLSEncoded = false;
          needsUpdate = true;
          console.log(`   ❌ Will mark as NOT HLS encoded (MP4)`);
        }
      }

      // Update the video if needed
      if (needsUpdate) {
        await Video.findByIdAndUpdate(video._id, updateFields);
        fixedCount++;
        console.log(`   ✅ Updated video: ${video.videoName}`);
      } else {
        console.log(`   ✓ Video already correctly configured`);
      }
    }

    console.log(`\n📊 Summary:`);
    console.log(`   - Total videos processed: ${videos.length}`);
    console.log(`   - Videos updated: ${fixedCount}`);
    console.log(`   - HLS videos: ${hlsCount}`);
    console.log(`   - MP4 videos: ${mp4Count}`);

    // Display some sample videos after update
    console.log(`\n🔍 Sample videos after update:`);
    const sampleVideos = await Video.find({}).limit(5);
    sampleVideos.forEach((video, index) => {
      console.log(`${index + 1}. ${video.videoName}`);
      console.log(`   - isHLSEncoded: ${video.isHLSEncoded}`);
      console.log(`   - videoUrl: ${video.videoUrl}`);
      console.log(`   - hlsMasterPlaylistUrl: ${video.hlsMasterPlaylistUrl || 'null'}`);
      console.log(`   - hlsPlaylistUrl: ${video.hlsPlaylistUrl || 'null'}`);
    });

  } catch (error) {
    console.error('❌ Error fixing videos:', error);
  }
};

// Main function
const main = async () => {
  await connectDB();
  await fixExistingVideos();
  
  console.log('✅ Script completed. You may need to restart your server.');
  process.exit(0);
};

// Run the script
main().catch(console.error);