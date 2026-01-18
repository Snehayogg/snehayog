
import mongoose from 'mongoose';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import FeedHistory from '../models/FeedHistory.js'; 

// Setup environment
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.resolve(__dirname, '../.env') });

const checkHistory = async () => {
  try {
    // 1. Connect to DB
    if (!process.env.MONGO_URI) {
      throw new Error('MONGO_URI is undefined in .env');
    }
    await mongoose.connect(process.env.MONGO_URI);
    console.log('✅ Connected to MongoDB');

    // 2. Configuration
    const userId = '105992171843910879786'; 
    
    // Videos from verification logs
    const videosToCheck = [
      { id: '692e9cc5f8da9c3ecb162fe7', note: 'Batch 1' },
      { id: '69184003601f8e3dcae834e2', note: 'Batch 1' },
      { id: '695a86ecc9fd4a66cc0a9f51', note: 'Batch 1' },
      { id: '695a0ebac9fd4a66cc040578', note: 'Batch 2' }, // Seen Jan 6
      { id: '691c1fadb9b2a47960b79063', note: 'Batch 2' }  // Seen Jan 16 (Recent!)
    ];

    console.log(`🔍 Checking ${videosToCheck.length} served videos for User: ${userId}`);

    // 3. Fetch "Last 300" (The flawed logic)
    const last300Docs = await FeedHistory.find({ userId })
        .sort({ seenAt: -1 })
        .limit(300) // ❗ The limit user asked about
        .select('videoId seenAt associatedHash')
        .lean();
    
    // Create Set for Last 300
    const last300Set = new Set(last300Docs.map(d => d.videoId.toString()));

    // 4. Fetch "Total" History Count
    const totalCount = await FeedHistory.countDocuments({ userId });
    console.log(`📊 Total History: ${totalCount}`);
    console.log(`📉 Filter Limit: 300`);
    console.log('════════════════════════════════════════════');
    
    let missedCount = 0;
    
    // 5. Check Each Video
    for (const v of videosToCheck) {
        // Check in Last 300
        const isInLast300 = last300Set.has(v.id);
        
        // Check in Full History (DB Query)
        const fullEntry = await FeedHistory.findOne({ userId, videoId: v.id });
        const isInFull = !!fullEntry;
        
        console.log(`🎥 Video: ${v.id}`);
        console.log(`   - In Last 300?  ${isInLast300 ? '✅ YES (Filtered out)' : '❌ NO (Slip through)'}`);
        console.log(`   - In Full DB?   ${isInFull ? '✅ YES' : '❌ NO'}`);
        
        if (isInFull && !isInLast300) {
            console.log(`   ⚠️ RESULT: FAILED. Video is seen (Date: ${fullEntry.seenAt.toISOString().split('T')[0]}), but older than 300.`);
            missedCount++;
        } else if (isInLast300) {
            console.log(`   ✅ RESULT: CAUGHT. Video is recent enough.`);
        } else {
             console.log(`   ℹ️ RESULT: FRESH (Truly new)`);
        }
        console.log('---');
    }
    
    console.log('════════════════════════════════════════════');
    console.log('CONCLUSION:');
    if (missedCount > 0) {
        console.log(`🚨 CRITICAL: ${missedCount} duplicate videos slipped through because they were outside the Last 300.`);
        console.log('👉 RECOMMENDATION: Remove the .limit() to filter against FULL history.');
    } else {
        console.log('✅ All duplicates were caught by the 300 limit (unlikely given your report).');
    }

  } catch (error) {
    console.error('❌ Error:', error);
  } finally {
    await mongoose.disconnect();
    console.log('🔌 Disconnected');
    process.exit();
  }
};

checkHistory();
