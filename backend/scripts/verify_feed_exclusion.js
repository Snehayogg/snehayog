import mongoose from 'mongoose';
import Video from '../models/Video.js';
import User from '../models/User.js';
import FeedHistory from '../models/FeedHistory.js';
import FeedQueueService from '../services/feedQueueService.js';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

// Fix __dirname for ES modules
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load env vars
dotenv.config({ path: path.join(__dirname, '../.env') });

const verifyFeedExclusion = async () => {
    console.log('🧪 Starting Verification Test: Feed Exclusion...');

    if (!process.env.MONGO_URI) {
        console.error('❌ MONGO_URI not found in .env');
        process.exit(1);
    }

    try {
        await mongoose.connect(process.env.MONGO_URI);
        console.log('✅ Connected to MongoDB');

        // 1. Setup Test User
        const TEST_USER_ID = 'test_verification_user_' + Date.now();
        console.log(`👤 Using Test User ID: ${TEST_USER_ID}`);

        // 2. Fetch a candidate video to "watch"
        const candidateVideo = await Video.findOne({ processingStatus: 'completed', duration: { $lte: 60 } })
            .sort({ createdAt: -1 }); // Get a recent one as that's what the feed fetches

        if (!candidateVideo) {
            console.error('❌ No candidate videos found to test with.');
            process.exit(1);
        }

        console.log(`📺 Selected Video to Watch: ${candidateVideo._id} (Hash: ${candidateVideo.videoHash || 'None'})`);

        // 3. Mark as Seen (Simulate Watching)
        await FeedHistory.create({
            userId: TEST_USER_ID,
            videoId: candidateVideo._id,
            videoHash: candidateVideo.videoHash,
            seenAt: new Date()
        });
        console.log('✅ Marked video as SEEN in FeedHistory');

        // 4. Generate Feed
        // We bypass the queue checks and directly call the generator logic to see what it would produce
        // Note: We need to access generateAndPushFeed logic. Since it pushes to Redis, we can check the logs or result.
        // Better: We can rely on the fact that generateAndPushFeed returns the count of pushed videos.
        // But to verify *what* was pushed, we might need to inspect the logs or Mock Redis.
        // Let's rely on the exclusion logic. We can call generateAndPushFeed and then pop from queue.

        console.log('🔄 Generating Feed...');
        const count = await FeedQueueService.generateAndPushFeed(TEST_USER_ID, 'yog');
        console.log(`📥 Generated ${count} videos in queue.`);

        // 5. Verify Exclusion
        // Pop the videos back
        const feedVideos = await FeedQueueService.popFromQueue(TEST_USER_ID, 'yog', 50);
        
        const feedIds = feedVideos.map(v => v._id.toString());
        console.log(`📦 Retrieved ${feedIds.length} videos from feed.`);

        const isExcluded = !feedIds.includes(candidateVideo._id.toString());
        
        console.log('-'.repeat(50));
        if (isExcluded) {
            console.log(`✅ PASS: Watched Video ${candidateVideo._id} is NOT in the new feed.`);
        } else {
            console.error(`❌ FAIL: Watched Video ${candidateVideo._id} WAS FOUND in the new feed!`);
        }
        
        // Also check hash exclusion if applicable
        if (candidateVideo.videoHash) {
             const hashMatch = feedVideos.find(v => v.videoHash === candidateVideo.videoHash);
             if (!hashMatch) {
                 console.log(`✅ PASS: No video with Hash ${candidateVideo.videoHash} found in feed.`);
             } else {
                 console.error(`❌ FAIL: Found duplicates with Hash ${candidateVideo.videoHash} (ID: ${hashMatch._id})`);
             }
        }
        console.log('-'.repeat(50));

        // Cleanup
        await FeedHistory.deleteMany({ userId: TEST_USER_ID });
        // Clean Redis key if possible, but we don't have direct redis client here easily unless exported.
        // FeedQueueService manages it. We can leave it, random test keys expire eventually or don't hurt.
        console.log('🧹 Cleanup: Removed test history.');

    } catch (error) {
        console.error('❌ Test Failed with Error:', error);
    } finally {
        await mongoose.disconnect();
        process.exit(0);
    }
};

verifyFeedExclusion();
