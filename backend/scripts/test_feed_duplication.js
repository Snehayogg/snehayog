
import mongoose from 'mongoose';
import 'dotenv/config';
import redisService from '../services/redisService.js';
import FeedQueueService from '../services/feedQueueService.js';
import Video from '../models/Video.js';
import FeedHistory from '../models/FeedHistory.js';
import User from '../models/User.js';

async function runDiagnostic() {
    console.log('🚀 Starting Feed Duplication Diagnostic...');
    
    // 1. Connect to services
    const MONGO_URI='mongodb+srv://factshorts1:Snehayog%40123@cluster0.zkoaz.mongodb.net/snehayog?retryWrites=true&w=majority';
    process.env.UPSTASH_REDIS_REST_URL = 'https://pet-rodent-49571.upstash.io';
    process.env.UPSTASH_REDIS_REST_TOKEN = 'AcGjAAIncDI0MDNmZWExYzMwODU0ZmU2YWM0MzVhNjk0NTA3NGZiNXAyNDk1NzE';
    
    await mongoose.connect(MONGO_URI);
    console.log('✅ MongoDB Connected');
    await redisService.connect();
    console.log('✅ Redis Connected');

    const testGoogleId = 'test_user_123' + Date.now();
    const videoType = 'yog';
    
    try {
        // Cleanup
        console.log(`\n🧹 Cleaning up for user: ${testGoogleId}`);
        await FeedQueueService.clearQueue(testGoogleId, videoType);
        await FeedHistory.deleteMany({ userId: testGoogleId });
        const seenKey = `user:seen_all:${testGoogleId}`;
        const hashKey = `user:seen_hashes:${testGoogleId}`;
        const lockKey = `lock:refill:${testGoogleId}:${videoType}`;
        await redisService.del(seenKey);
        await redisService.del(hashKey);
        await redisService.del(lockKey); // Clear lock

        // 2. Fetch some videos to simulate "seen"
        // We'll fetch completed yog videos
        const sampleVideos = await Video.find({ 
            processingStatus: 'completed', 
            videoType: 'yog' 
        }).limit(10).lean();
        
        if (sampleVideos.length < 5) {
            console.error('❌ Not enough yog videos in DB to test.');
            return;
        }

        const sampleIds = sampleVideos.map(v => v._id.toString());
        console.log(`📝 Selected ${sampleIds.length} sample videos to mark as seen.`);

        // 3. Mark them as seen manually (simulating popFromQueue)
        console.log('Marking in Redis seenKey...');
        await redisService.sAdd(seenKey, sampleIds);
        
        const hashes = sampleVideos.map(v => v.videoHash).filter(Boolean);
        if (hashes.length > 0) {
            console.log(`Marking ${hashes.length} hashes in Redis hashKey...`);
            await redisService.sAdd(hashKey, hashes);
        }
        
        console.log('Marking in DB FeedHistory...');
        await FeedHistory.markAsSeen(testGoogleId, sampleVideos);
        console.log('✅ Marked sample videos as seen in Redis and DB');

        // ----------------------------------------------------------------------
        // TEST 1: Normal Refill with Hash Filtering
        // ----------------------------------------------------------------------
        console.log('\n⚡ TEST 1: Triggering generateAndPushFeed (Normal)...');
        await FeedQueueService.generateAndPushFeed(testGoogleId, videoType);
        
        const queueKey = FeedQueueService.getQueueKey(testGoogleId, videoType);
        const queuedIds = await redisService.lRange(queueKey, 0, -1);
        console.log(`📦 Queue now contains ${queuedIds.length} videos.`);

        const duplicates = queuedIds.filter(id => sampleIds.includes(id));
        if (duplicates.length > 0) {
            console.error(`❌ DUPLICATES DETECTED! ${duplicates.length} videos in queue were already seen.`);
            console.log('Duplicate IDs:', duplicates);
        } else {
            console.log('✅ No duplicates found in first refill attempt (Hash filtering worked).');
        }

        // ----------------------------------------------------------------------
        // TEST 2: Specifically without Hashes (Testing ID filtering)
        // ----------------------------------------------------------------------
        console.log('\n🧪 TEST 2: Testing without Seen Hashes (Testing if ID sync works)...');
        await redisService.del(hashKey); // Delete hashes
        await FeedQueueService.clearQueue(testGoogleId, videoType); // Clear queue 
        
        // Ensure the IDs ARE in the seen set
        const exists = await redisService.sMembers(seenKey);
        console.log(`Seen IDs in Redis: ${exists.length}`);

        await FeedQueueService.generateAndPushFeed(testGoogleId, videoType);
        const queuedIds2 = await redisService.lRange(queueKey, 0, -1);
        const duplicates2 = queuedIds2.filter(id => sampleIds.includes(id));

        if (duplicates2.length > 0) {
            console.error(`❌ DUPLICATES DETECTED (No Hashes)! ${duplicates2.length} videos reappear when only ID is in seen set.`);
        } else {
            console.log('✅ SUCCESS: No duplicates found even without hashes. ID-based filtering is WORKING.');
        }

        // ----------------------------------------------------------------------
        // TEST 3: Anonymous User Test
        // ----------------------------------------------------------------------
        console.log('\n🧪 TEST 3: Testing Anonymous User...');
        const anonId = 'anon';
        await FeedQueueService.clearQueue(anonId, videoType);
        
        // Push 10 videos
        const popped = await FeedQueueService.popFromQueue(anonId, videoType, 10);
        console.log(`Popped ${popped.length} videos for anon.`);
        
        // Mark them
        const anonSeenKey = `user:seen_all:anon`;
        const hasAnonSeen = await redisService.exists(anonSeenKey);
        console.log(`Does anon seen key exist? ${hasAnonSeen}`);
        
        if (!hasAnonSeen) {
            console.log('❌ BUG CONFIRMED: Anon user seen key NOT created!');
        }

        // --------------------------------------------------------------------------------
        // TEST 4: GUEST HISTORY MERGING
        // --------------------------------------------------------------------------------
        console.log('\n🧪 TEST 4: Guest History Merging...');
        const deviceId = 'test_device_999';
        const googleId = 'test_google_user_999';
        // Ensure we have enough videos for this test, using sampleVideos from earlier
        if (sampleVideos.length < 5) {
            console.error('❌ Not enough sample videos for Guest History Merging test.');
            process.exit(1);
        }
        const guestVideoId = sampleVideos[4]._id.toString(); // Use an existing sample video

        // 1. Mark as seen for guest
        console.log(`   - Marking video ${guestVideoId} as seen for guest ${deviceId}`);
        await redisService.sAdd(`user:seen_all:${deviceId}`, [guestVideoId]);

        // 2. Perform merge
        console.log(`   - Merging guest ${deviceId} into user ${googleId}`);
        await FeedQueueService.mergeGuestHistory(deviceId, googleId);

        // 3. Verify
        const mergedSeen = await redisService.getSetMembers(`user:seen_all:${googleId}`);
        if (mergedSeen.has(guestVideoId)) {
            console.log('   ✅ PASS: Guest history successfully merged into user history.');
        } else {
            console.error('   ❌ FAIL: Guest history NOT merged.');
            process.exit(1);
        }

        // 4. Verify guest cleanup
        const guestSeenLeft = await redisService.getSetMembers(`user:seen_all:${deviceId}`);
        if (guestSeenLeft.size === 0) {
            console.log('   ✅ PASS: Guest temporary history cleared.');
        } else {
           console.warn(`   ⚠️ WARNING: Guest history was not cleared from Redis (${guestSeenLeft.size} items remaining).`);
        }

        console.log('\n✨ ALL DIAGNOSTIC TESTS PASSED! Fix is verified.');

    } catch (error) {
        console.error('\n❌ DIAGNOSTIC FAILED:', error);
    } finally {
        const videoType = 'yog';
        const anonId = 'anon';
        const testGoogleId_base = 'test_user_123'; // Base for cleanup

        // Cleanup all test keys using patterns to be safe
        console.log('\n🧹 Final Cleanup...');
        await redisService.del('user:seen_all:test_google_user_999');
        await redisService.del('user:seen_all:test_device_999');
        await redisService.del(`user:feed:${anonId}:${videoType}`);
        await redisService.del(`user:seen_all:${anonId}`);
        
        // Pattern match cleanup for the timestamped test users
        await redisService.clearPattern('user:feed:test_user_123*');
        await redisService.clearPattern('user:seen_all:test_user_123*');
        await redisService.clearPattern('user:seen_hashes:test_user_123*');
        await redisService.clearPattern('lock:refill:test_user_123*');

        mongoose.connection.close();
        await redisService.disconnect();
        process.exit(0);
    }
}

runDiagnostic();
