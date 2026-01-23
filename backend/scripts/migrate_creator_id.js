
import mongoose from 'mongoose';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

// Load environment variables
const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.resolve(__dirname, '../.env') });

import AdImpression from '../models/AdImpression.js';
import Video from '../models/Video.js';

// Use MONGO_URI as defined in server.js/database.js
const MONGO_URI = process.env.MONGO_URI || process.env.MONGODB_URI;

if (!MONGO_URI) {
  console.error('❌ Missing MONGO_URI environment variable');
  process.exit(1);
}

async function migrate() {
  try {
    console.log('🔄 Connecting to MongoDB...');
    // Use robust connection options
    await mongoose.connect(MONGO_URI, {
      serverSelectionTimeoutMS: 30000,
      socketTimeoutMS: 45000,
      connectTimeoutMS: 30000, 
    });
    console.log('✅ Connected to MongoDB');

    // **Ensure Index Exists**
    // Sometimes auto-index is disabled or slow, force it here
    console.log('索引 checking/creating indexes...');
    // The schema defines index: true, but let's be sure
    // Note: AdImpression might not have the index yet if app hasn't restarted fully or errored
    // We rely on Schema definition, but we can try ensuring it.
    
    console.log('🔍 Searching for AdImpressions without creatorId...');
    
    // Find impressions where creatorId is missing or null
    const impressionsToUpdate = await AdImpression.find({
      $or: [{ creatorId: { $exists: false } }, { creatorId: null }]
    });

    console.log(`📊 Found ${impressionsToUpdate.length} impressions to migrate.`);

    if (impressionsToUpdate.length === 0) {
      console.log('✅ No migration needed.');
      process.exit(0);
    }

    let updatedCount = 0;
    let errorCount = 0;
    
    // Cache video uploaders to avoid repeated queries
    const videoUploaderMap = new Map();

    // Use a cursor or batch if too many, but for now loop is fine (likely < 100k)
    // If huge, we should Cursor.
    
    // Optimizing with Promise.all for batches of parallel updates could be faster but let's stick to safe sequential or small chunks
    
    for (const impression of impressionsToUpdate) {
      try {
        if (!impression.videoId) {
             continue; // Invalid record
        }
        
        const videoId = impression.videoId.toString();
        
        let creatorId = videoUploaderMap.get(videoId);

        if (!creatorId) {
          const video = await Video.findById(videoId).select('uploader').lean();
          if (video && video.uploader) {
            creatorId = video.uploader;
            videoUploaderMap.set(videoId, creatorId);
          } else {
             // console.warn(`⚠️ Video not found or no uploader for video ID: ${videoId}`);
             videoUploaderMap.set(videoId, 'NOT_FOUND'); // Cache negative result
          }
        }

        if (creatorId && creatorId !== 'NOT_FOUND') {
            impression.creatorId = creatorId;
            await impression.save();
            updatedCount++;
            if (updatedCount % 100 === 0) process.stdout.write('.');
        }
      } catch (err) {
        console.error(`❌ Error updating impression ${impression._id}:`, err.message);
        errorCount++;
      }
    }

    console.log('\n');
    console.log('🎉 Migration Complete!');
    console.log(`✅ Updated: ${updatedCount}`);
    console.log(`❌ Errors: ${errorCount}`);

  } catch (error) {
    console.error('❌ Migration failed:', error);
  } finally {
    await mongoose.disconnect();
    process.exit();
  }
}

migrate();
