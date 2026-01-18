import mongoose from 'mongoose';
import Video from '../models/Video.js';
import User from '../models/User.js';
import FeedHistory from '../models/FeedHistory.js';
import WatchHistory from '../models/WatchHistory.js';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

// Fix __dirname for ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load env vars
dotenv.config({ path: path.join(__dirname, '../.env') });

const verifyHistoryRecording = async () => {
    console.log('🧪 Starting Verification Test: History Recording persistence...');

    if (!process.env.MONGO_URI) {
        console.error('❌ MONGO_URI not found in .env');
        process.exit(1);
    }

    try {
        await mongoose.connect(process.env.MONGO_URI);
        console.log('✅ Connected to MongoDB');

        // 1. Setup Data
        const TEST_USER_ID = 'test_history_user_' + Date.now();
        const candidateVideo = await Video.findOne({ processingStatus: 'completed' });

        if (!candidateVideo) {
            console.error('❌ No candidate videos found.');
            process.exit(1);
        }

        console.log(`👤 Test User: ${TEST_USER_ID}`);
        console.log(`📺 Test Video: ${candidateVideo._id} (Hash: ${candidateVideo.videoHash || 'None'})`);

        // 2. Test FeedHistory.markAsSeen
        console.log('🔄 Calling FeedHistory.markAsSeen()...');
        await FeedHistory.markAsSeen(TEST_USER_ID, [{ _id: candidateVideo._id, videoHash: candidateVideo.videoHash }]);
        
        // 3. Test WatchHistory.trackWatch
        console.log('🔄 Calling WatchHistory.trackWatch()...');
        await WatchHistory.trackWatch(TEST_USER_ID, candidateVideo._id, {
            duration: 10,
            completed: false,
            isAuthenticated: false
        });

        // 4. VERIFY DATABASE PERSISTENCE
        console.log('🔍 Querying Database for records...');

        const feedRecord = await FeedHistory.findOne({ userId: TEST_USER_ID, videoId: candidateVideo._id });
        const watchRecord = await WatchHistory.findOne({ userId: TEST_USER_ID, videoId: candidateVideo._id });

        console.log('-'.repeat(50));
        
        let passFeed = false;
        if (feedRecord) {
            console.log(`✅ PASS: FeedHistory record FOUND.`);
            console.log(`   - ID: ${feedRecord._id}`);
            console.log(`   - SeenAt: ${feedRecord.seenAt}`);
            console.log(`   - VideoHash: ${feedRecord.videoHash || 'MISSING'}`);
            if(candidateVideo.videoHash && feedRecord.videoHash === candidateVideo.videoHash) {
                console.log(`   - Hash Match: YES`);
            }
            passFeed = true;
        } else {
             console.error(`❌ FAIL: FeedHistory record NOT found!`);
        }

        let passWatch = false;
        if (watchRecord) {
            console.log(`✅ PASS: WatchHistory record FOUND.`);
            console.log(`   - ID: ${watchRecord._id}`);
            console.log(`   - WatchedAt: ${watchRecord.watchedAt}`);
            console.log(`   - WatchCount: ${watchRecord.watchCount}`);
            passWatch = true;
        } else {
             console.error(`❌ FAIL: WatchHistory record NOT found!`);
        }

        console.log('-'.repeat(50));

        // Cleanup
        await FeedHistory.deleteMany({ userId: TEST_USER_ID });
        await WatchHistory.deleteMany({ userId: TEST_USER_ID });
        console.log('🧹 Cleanup: Removed test history.');

        if (passFeed && passWatch) {
            console.log('🎉 SUCCESS: History recording is working correctly.');
        } else {
            console.error('💥 FAILURE: History recording is broken.');
            process.exit(1);
        }

    } catch (error) {
        console.error('❌ Test Failed with Error:', error);
        process.exit(1);
    } finally {
        await mongoose.disconnect();
        process.exit(0);
    }
};

verifyHistoryRecording();
