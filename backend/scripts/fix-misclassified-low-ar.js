/**
 * Fix Misclassified Videos with Low Aspect Ratio
 * 
 * This fixes videos that were wrongly classified by the previous bad migration.
 * Specifically targets videos with:
 * - videoType: 'vayu' (should be 'yog')
 * - aspectRatio < 1.0 (vertical/portrait)
 * - Common mobile resolutions stored incorrectly
 */

import mongoose from 'mongoose';
import Video from '../models/Video.js';
import dotenv from 'dotenv';

dotenv.config();

async function fixMisclassifiedLowARVideos() {
  try {
    console.log('🔧 Starting Fix for Misclassified Low AR Videos...\n');
    
    await mongoose.connect(process.env.MONGO_URI);
    console.log('✅ Connected to MongoDB\n');

    // Find videos with vayu type but AR < 1.0 (these are wrongly classified)
    const misclassifiedVideos = await Video.find({
      processingStatus: 'completed',
      videoType: 'vayu',
      aspectRatio: { $lt: 1.0 } // Should be 'yog'!
    })
    .select('_id videoName videoType aspectRatio originalResolution')
    .limit(2000);

    console.log(`📊 Found ${misclassifiedVideos.length} misclassified videos\n`);

    if (misclassifiedVideos.length === 0) {
      console.log('✅ No misclassified videos found!');
      await mongoose.disconnect();
      return;
    }

    let fixedCount = 0;
    let errorCount = 0;

    for (let i = 0; i < misclassifiedVideos.length; i++) {
      const video = misclassifiedVideos[i];
      const progress = ((i + 1) / misclassifiedVideos.length * 100).toFixed(1);
      
      process.stdout.write(`\r🔧 Fixing [${i + 1}/${misclassifiedVideos.length}] (${progress}%)...`);

      try {
        const width = video.originalResolution?.width || 0;
        const height = video.originalResolution?.height || 0;
        
        // Calculate correct AR
        const correctAR = (width > 0 && height > 0) ? width / height : video.aspectRatio;
        
        // Determine correct type based on AR
        const correctType = correctAR > 1.0 ? 'vayu' : 'yog';
        
        // Since we're filtering AR < 1.0, these should all be 'yog'
        if (correctType === 'yog') {
          await Video.updateOne(
            { _id: video._id },
            { 
              $set: { 
                videoType: 'yog',
                aspectRatio: correctAR,
                fixedFromBadMigration: true,
                fixedAt: new Date()
              }
            }
          );

          fixedCount++;
          
          if (fixedCount <= 20) { // Show first 20 for verification
            console.log(`\n   ✅ Fixed: "${video.videoName}"`);
            console.log(`      ${video.videoType} → yog | AR: ${video.aspectRatio.toFixed(4)} → ${correctAR.toFixed(4)}`);
            console.log(`      Resolution: ${width}x${height}`);
          }
        }

      } catch (error) {
        errorCount++;
        console.error(`\n   ❌ Error: ${error.message}`);
      }
    }

    console.log('\n\n' + '='.repeat(60));
    console.log('📊 FIX SUMMARY');
    console.log('='.repeat(60));
    console.log(`Total Checked:    ${misclassifiedVideos.length}`);
    console.log(`Videos Fixed:     ${fixedCount}`);
    console.log(`Errors:           ${errorCount}`);
    console.log('='.repeat(60));

    // Final statistics
    console.log('\n📊 FINAL DATABASE STATUS:');
    const vayuCount = await Video.countDocuments({ videoType: 'vayu', processingStatus: 'completed' });
    const yogCount = await Video.countDocuments({ videoType: 'yog', processingStatus: 'completed' });
    console.log(`   Vayu (landscape): ${vayuCount}`);
    console.log(`   Yog (portrait):   ${yogCount}`);
    console.log('\n✅ Fix completed!\n');
    
    await mongoose.disconnect();
    
  } catch (error) {
    console.error('\n❌ Fix failed:', error);
    process.exit(1);
  }
}

fixMisclassifiedLowARVideos();
