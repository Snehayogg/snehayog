/**
 * Test Script: Video Rotation Detection
 * 
 * This script tests the rotation detection logic in videoMetadataService
 * Run: node scripts/test-rotation-detection.js <path-to-video-file>
 */

import ffmpeg from 'fluent-ffmpeg';
import ffmpegPath from 'ffmpeg-static';
import ffprobePath from 'ffprobe-static';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Configure ffmpeg
if (ffmpegPath) {
  ffmpeg.setFfmpegPath(ffmpegPath);
}
if (ffprobePath && ffprobePath.path) {
  ffmpeg.setFfprobePath(ffprobePath.path);
}

async function testRotationDetection(videoPath) {
  console.log('🎬 Testing Rotation Detection\n');
  console.log('Video:', videoPath);
  console.log('─'.repeat(60));

  // Validate file exists
  if (!fs.existsSync(videoPath)) {
    console.error(`❌ File not found: ${videoPath}`);
    process.exit(1);
  }

  try {
    // Get metadata using ffprobe
    const metadata = await new Promise((resolve, reject) => {
      ffmpeg.ffprobe(videoPath, (err, data) => {
        if (err) reject(err);
        else resolve(data);
      });
    });

    const videoStream = metadata.streams.find(s => s.codec_type === 'video');
    
    if (!videoStream) {
      console.error('❌ No video stream found');
      process.exit(1);
    }

    // Extract raw dimensions
    const rawWidth = parseInt(videoStream.width, 10) || 0;
    const rawHeight = parseInt(videoStream.height, 10) || 0;

    console.log('\n📊 RAW DIMENSIONS (from ffprobe):');
    console.log(`   Width:  ${rawWidth}px`);
    console.log(`   Height: ${rawHeight}px`);
    console.log(`   Raw AR: ${(rawWidth / rawHeight).toFixed(4)}`);

    // Detect rotation
    let rotation = 0;
    
    // Check tags (legacy format)
    if (videoStream.tags?.rotate) {
      rotation = parseInt(videoStream.tags.rotate, 10);
      console.log(`\n🏷️  Rotation in tags.rotate: ${rotation}°`);
    }

    // Check side_data_list (modern format - iOS)
    if (videoStream.side_data_list && videoStream.side_data_list.length > 0) {
      console.log('\n📦 Side Data List:');
      videoStream.side_data_list.forEach((sd, idx) => {
        console.log(`   [${idx}] Type: ${sd.side_data_type}`);
        if (sd.rotation) {
          console.log(`       Rotation: ${sd.rotation}°`);
        }
      });

      const sideData = videoStream.side_data_list.find(sd => sd.side_data_type === 'Display Matrix');
      if (sideData && sideData.rotation) {
        rotation = parseInt(sideData.rotation, 10);
        console.log(`\n✅ Using Display Matrix rotation: ${rotation}°`);
      }
    }

    if (rotation === 0) {
      console.log('\n⚪ No rotation metadata detected');
    }

    // Apply rotation correction
    let correctedWidth = rawWidth;
    let correctedHeight = rawHeight;

    if (Math.abs(rotation) === 90 || Math.abs(rotation) === 270) {
      console.log(`\n🔄 ROTATION DETECTED: ${rotation}°`);
      console.log(`   Swapping dimensions: ${rawWidth}x${rawHeight} → ${correctedHeight}x${correctedWidth}`);
      [correctedWidth, correctedHeight] = [correctedHeight, correctedWidth];
    }

    // Calculate corrected aspect ratio
    const correctedAR = correctedWidth / correctedHeight;

    console.log('\n✅ CORRECTED DIMENSIONS:');
    console.log(`   Width:  ${correctedWidth}px`);
    console.log(`   Height: ${correctedHeight}px`);
    console.log(`   Corrected AR: ${correctedAR.toFixed(4)}`);

    // Determine video type
    const videoType = correctedAR > 1.0 ? 'vayu' : 'yog';
    const orientation = correctedAR > 1.0 ? 'Landscape/Horizontal' : 'Portrait/Vertical';

    console.log('\n📋 CLASSIFICATION:');
    console.log(`   Orientation: ${orientation}`);
    console.log(`   Video Type: '${videoType}'`);
    console.log(`   Tab: ${videoType === 'vayu' ? 'Vayu (Long-form)' : 'Yog (Short-form/Reels)'}`);

    console.log('\n' + '─'.repeat(60));
    console.log('✅ Test completed successfully!\n');

  } catch (error) {
    console.error('\n❌ Error:', error.message);
    process.exit(1);
  }
}

// Main execution
const videoPath = process.argv[2];

if (!videoPath) {
  console.log('Usage: node test-rotation-detection.js <path-to-video-file>');
  console.log('\nExample:');
  console.log('  node scripts/test-rotation-detection.js ./uploads/videos/test.mp4\n');
  process.exit(1);
}

testRotationDetection(videoPath);
