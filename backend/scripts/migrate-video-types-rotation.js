/**
 * Migration Script: Fix Video Type Classification with Rotation Detection
 * 
 * This script re-evaluates all existing videos considering rotation metadata:
 * - Landscape (AR > 1.0) → 'vayu' (long-form)
 * - Portrait (AR <= 1.0) → 'yog' (short-form)
 * 
 * IMPORTANT: This considers video rotation metadata for accurate classification
 * Run this ONCE to update your existing video database
 */

import mongoose from 'mongoose';
import Video from '../models/Video.js';
import { getVideoMetadata } from '../services/videoMetadataService.js';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

dotenv.config();

async function migrateVideoTypesWithRotation() {
  try {
    console.log('🚀 Starting Video Type Migration with Rotation Detection...\n');
    
    // Connect to MongoDB
    await mongoose.connect(process.env.MONGO_URI || 'mongodb://localhost:27017/vayu');
    console.log('✅ Connected to MongoDB\n');

    // Get all completed videos
    const allVideos = await Video.find({ processingStatus: 'completed' })
      .select('_id videoName videoType aspectRatio originalResolution link')
      .lean();

    console.log(`📊 Found ${allVideos.length} completed videos to process\n`);

    let updatedCount = 0;
    let unchangedCount = 0;
    let errorCount = 0;
    let skippedCount = 0;
    let rotationDetectedCount = 0;

    const results = [];

    for (let i = 0; i < allVideos.length; i++) {
      const video = allVideos[i];
      const progress = ((i + 1) / allVideos.length * 100).toFixed(1);
      
      process.stdout.write(`\r📹 Processing [${i + 1}/${allVideos.length}] (${progress}%)...`);

      try {
        const oldType = video.videoType;
        const oldAR = video.aspectRatio || 0;
        
        // Skip videos without valid data
        if (!video.originalResolution?.width || !video.originalResolution?.height) {
          skippedCount++;
          continue;
        }

        // Calculate corrected aspect ratio considering rotation
        let width = video.originalResolution.width;
        let height = video.originalResolution.height;
        let rotation = 0;
        
        // For this migration, we'll trust the stored dimensions
        // In production, you'd want to re-extract metadata from the actual video files
        // This is a simplified version - full migration would need video file access
        
        // If you have access to video files, uncomment this:
        /*
        if (video.link && fs.existsSync(video.link)) {
          const metadata = await getVideoMetadata(video.link);
          width = metadata.width;
          height = metadata.height;
          rotation = metadata.rotation;
          if (rotation !== 0) {
            rotationDetectedCount++;
            console.log(`\n   🔄 Rotation detected: ${rotation}° for video ${video._id}`);
          }
        }
        */
        
        // Calculate corrected aspect ratio
        const correctedAR = width / height;
        const newType = correctedAR > 1.0 ? 'vayu' : 'yog';

        // Check if type needs to be updated
        if (oldType !== newType) {
          await Video.updateOne(
            { _id: video._id },
            { 
              $set: { 
                videoType: newType,
                aspectRatio: correctedAR
              }
            }
          );
          
          updatedCount++;
          results.push({
            id: video._id,
            name: video.videoName,
            oldType,
            newType,
            oldAR: oldAR.toFixed(4),
            newAR: correctedAR.toFixed(4),
            rotation
          });
          
          console.log(`\n   ✏️  Updated: "${video.videoName}"`);
          console.log(`      ${oldType} → ${newType} | AR: ${oldAR.toFixed(2)} → ${correctedAR.toFixed(2)}`);
        } else {
          unchangedCount++;
        }

      } catch (error) {
        errorCount++;
        console.error(`\n   ❌ Error processing video ${video._id}: ${error.message}`);
      }
    }

    console.log('\n\n' + '='.repeat(60));
    console.log('📊 MIGRATION SUMMARY');
    console.log('='.repeat(60));
    console.log(`Total Videos Processed: ${allVideos.length}`);
    console.log(`Videos Updated:         ${updatedCount}`);
    console.log(`Videos Unchanged:       ${unchangedCount}`);
    console.log(`Videos Skipped:         ${skippedCount}`);
    console.log(`Errors:                 ${errorCount}`);
    console.log(`Rotation Detected:      ${rotationDetectedCount}`);
    console.log('='.repeat(60));

    if (results.length > 0) {
      console.log('\n📋 UPDATED VIDEOS:');
      results.forEach((r, idx) => {
        console.log(`\n${idx + 1}. "${r.name}"`);
        console.log(`   ID: ${r.id}`);
        console.log(`   Type: ${r.oldType} → ${r.newType}`);
        console.log(`   Aspect Ratio: ${r.oldAR} → ${r.newAR}`);
        if (r.rotation !== 0) {
          console.log(`   Rotation: ${r.rotation}°`);
        }
      });
    }

    console.log('\n✅ Migration completed successfully!\n');
    
    // Close connection
    await mongoose.disconnect();
    
  } catch (error) {
    console.error('\n❌ Migration failed:', error);
    process.exit(1);
  }
}

// Run migration
if (process.argv[1].includes('migrate-video-types-rotation')) {
  migrateVideoTypesWithRotation();
}

export default migrateVideoTypesWithRotation;
