/**
 * Emergency Revert Script - Restore Original Video Types
 * 
 * This script REVERTS the incorrect classification from the faulty migration.
 */

import mongoose from 'mongoose';
import Video from '../models/Video.js';
import dotenv from 'dotenv';

dotenv.config();

async function revertIncorrectMigration() {
  try {
    console.log('🚨 Starting Emergency Revert of Incorrect Video Classification...\n');
    
    console.log('Connecting to MongoDB...');
    await mongoose.connect(process.env.MONGO_URI || 'mongodb://localhost:27017/vayu');
    console.log('✅ Connected to MongoDB\n');

    // Find videos that were likely misclassified as 'vayu' with landscape AR
    // Looking for common mobile video resolutions that might be rotated
    const suspectVideos = await Video.find({
      processingStatus: 'completed',
      videoType: 'vayu',
      aspectRatio: { $gte: 1.5, $lte: 1.8 } // Typical "widescreen" ratio range
    })
    .select('_id videoName videoType aspectRatio originalResolution')
    .limit(1000);

    console.log(`📊 Found ${suspectVideos.length} potentially misclassified videos\n`);

    if (suspectVideos.length === 0) {
      console.log('✅ No suspect videos found. Database might already be correct!');
      await mongoose.disconnect();
      return;
    }

    let revertedCount = 0;
    let errorCount = 0;

    for (let i = 0; i < suspectVideos.length; i++) {
      const video = suspectVideos[i];
      const progress = ((i + 1) / suspectVideos.length * 100).toFixed(1);
      
      process.stdout.write(`\r🔄 Reverting [${i + 1}/${suspectVideos.length}] (${progress}%)...`);

      try {
        const width = video.originalResolution?.width || 0;
        const height = video.originalResolution?.height || 0;
        
        // Check if this is a misclassified vertical video
        // Common patterns: stored dimensions swapped (looks landscape but should be portrait)
        const commonLandscapeResolutions = [
          { w: 1920, h: 1080 }, // Full HD
          { w: 1280, h: 720 },  // HD
          { w: 3840, h: 2160 }, // 4K
          { w: 854, h: 480 },   // SD (very common!)
          { w: 640, h: 360 },   // Low quality
          { w: 426, h: 240 }    // Very low quality
        ];
        
        const isLikelyMisclassified = commonLandscapeResolutions.some(res => 
          width === res.w && height === res.h
        ) && video.aspectRatio > 1.5;

        if (!isLikelyMisclassified) continue;

        // Calculate correct AR (swap dimensions back)
        const correctedAR = height / width;
        
        // For vertical videos, AR will be < 1.0 → 'yog'
        await Video.updateOne(
          { _id: video._id },
          { 
            $set: { 
              videoType: 'yog',
              aspectRatio: correctedAR,
              revertedFromBadMigration: true,
              revertedAt: new Date()
            }
          }
        );

        revertedCount++;
        console.log(`\n   ✅ Reverted: "${video.videoName}"`);
        console.log(`      vayu → yog | AR: ${video.aspectRatio.toFixed(2)} → ${correctedAR.toFixed(2)}`);

      } catch (error) {
        errorCount++;
        console.error(`\n   ❌ Error: ${error.message}`);
      }
    }

    console.log('\n\n' + '='.repeat(60));
    console.log('📊 REVERT SUMMARY');
    console.log('='.repeat(60));
    console.log(`Videos Reverted:  ${revertedCount}`);
    console.log(`Errors:           ${errorCount}`);
    console.log('='.repeat(60));
    console.log('\n✅ Revert completed!\n');
    
    console.log('\n📊 Checking final statistics...');
    const vayuCount = await Video.countDocuments({ videoType: 'vayu', processingStatus: 'completed' });
    const yogCount = await Video.countDocuments({ videoType: 'yog', processingStatus: 'completed' });
    console.log(`   Vayu videos (landscape): ${vayuCount}`);
    console.log(`   Yog videos (portrait): ${yogCount}`);
    console.log('\n');
    
    await mongoose.disconnect();
    console.log('Disconnected from MongoDB');
    
  } catch (error) {
    console.error('\n❌ Revert failed:', error);
    process.exit(1);
  }
}

revertIncorrectMigration();