/**
 * Migration Script: Fix Video Type Classification
 * 
 * This script updates all existing videos to use the new aspect-ratio-based classification:
 * - Landscape (AR > 1.0) → 'vayu' (long-form)
 * - Portrait (AR <= 1.0) → 'yog' (short-form)
 * 
 * Run this ONCE to update your existing video database
 */

import mongoose from 'mongoose';
import Video from '../models/Video.js';
import dotenv from 'dotenv';

dotenv.config();

async function migrateVideoTypes() {
  try {
    console.log('🚀 Starting Video Type Migration...');
    
    // Connect to MongoDB
    await mongoose.connect(process.env.MONGO_URI || 'mongodb://localhost:27017/vayu');
    console.log('✅ Connected to MongoDB');

    // Get all completed videos
    const allVideos = await Video.find({ processingStatus: 'completed' })
      .select('_id videoName videoType aspectRatio duration')
      .lean();

    console.log(`📊 Found ${allVideos.length} completed videos to process`);

    let updatedCount = 0;
    let unchangedCount = 0;
    let skippedCount = 0;
    let errors = [];

    for (const video of allVideos) {
      try {
        const oldType = video.videoType;
        const ar = video.aspectRatio || 0;
        
        // Skip videos without aspect ratio (can't classify)
        if (!ar || ar <= 0) {
          console.log(`⚠️ SKIP: ${video.videoName.substring(0, 40)} | No AR data`);
          skippedCount++;
          continue;
        }
        
        // Determine new type based on aspect ratio
        const newType = ar > 1.0 ? 'vayu' : 'yog';
        
        if (oldType !== newType) {
          // Update the video type
          await Video.updateOne(
            { _id: video._id },
            { $set: { videoType: newType } }
          );
          
          console.log(`🔄 ${video.videoName.substring(0, 40)} | AR: ${ar.toFixed(2)} | ${oldType} → ${newType}`);
          updatedCount++;
        } else {
          unchangedCount++;
        }
      } catch (err) {
        console.error(`❌ Error updating video ${video._id}:`, err.message);
        errors.push({ videoId: video._id, error: err.message });
      }
    }

    console.log('\n✅ Migration Complete!');
    console.log(`📊 Summary:`);
    console.log(`   - Total videos: ${allVideos.length}`);
    console.log(`   - Updated: ${updatedCount}`);
    console.log(`   - Unchanged: ${unchangedCount}`);
    console.log(`   - Skipped (no AR): ${skippedCount}`);
    console.log(`   - Errors: ${errors.length}`);

    if (errors.length > 0) {
      console.log('\n⚠️ Errors:');
      errors.forEach((e, i) => {
        console.log(`   ${i+1}. Video ${e.videoId}: ${e.error}`);
      });
    }

    // Close connection
    await mongoose.connection.close();
    console.log('\n✅ Database connection closed');
    
  } catch (error) {
    console.error('❌ Migration failed:', error.message);
    process.exit(1);
  }
}

// Run migration
migrateVideoTypes();
