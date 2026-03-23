import { Worker } from 'bullmq';
import mongoose from 'mongoose';
import Video from '../models/Video.js';
import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';
import hybridVideoService from '../services/uploadServices/hybridVideoService.js';
import cloudflareR2Service from '../services/uploadServices/cloudflareR2Service.js';
import queueService from '../services/yugFeedServices/queueService.js';
import { redisOptions } from '../services/yugFeedServices/queueService.js'; // Updated path for redisOptions
import User from '../models/User.js';
import redisService from '../services/caching/redisService.js';
import { invalidateCache, VideoCacheKeys } from '../middleware/cacheMiddleware.js';
import recommendationService from '../services/yugFeedServices/recommendationService.js';
import moderationService from '../services/uploadServices/localModerationService.js';

dotenv.config();

// Connect to MongoDB (Worker needs its own connection)
const connectDB = async () => {
  try {
    await mongoose.connect(process.env.MONGO_URI);
    console.log('📦 Worker MongoDB Connected');
    
    // Connect to Redis for cache invalidation
    await redisService.connect();
    console.log('📦 Worker Redis Connected');
  } catch (error) {
    console.error('❌ Worker MongoDB Connection Error:', error);
    process.exit(1);
  }
};

connectDB();

async function handleVideoProcessing(job) {
  const { videoId, rawVideoKey, videoName, userId } = job.data;
  const tempDir = path.join(process.cwd(), 'temp_raw_downloads');
  if (!fs.existsSync(tempDir)) {
      fs.mkdirSync(tempDir, { recursive: true });
  }
  const localRawPath = path.join(tempDir, `${videoId}_raw${path.extname(rawVideoKey) || '.mp4'}`);

  try {
    await Video.findByIdAndUpdate(videoId, { 
        processingStatus: 'processing',
        processingProgress: 10 
    });

    await cloudflareR2Service.downloadFile(rawVideoKey, localRawPath);
    await Video.findByIdAndUpdate(videoId, { processingProgress: 30 });

    const hlsResult = await hybridVideoService.processVideoToHLS(
        localRawPath,
        videoName,
        userId
    );

    const video = await Video.findById(videoId);
    if (video) {
        video.videoUrl = hlsResult.videoUrl;
        video.hlsPlaylistUrl = hlsResult.hlsPlaylistUrl;
        video.thumbnailUrl = hlsResult.thumbnailUrl;
        video.processingStatus = 'completed';
        video.processingProgress = 100;
        video.isHLSEncoded = true;
        video.lowQualityUrl = hlsResult.videoUrl;
        
        if (hlsResult.aspectRatio) video.aspectRatio = hlsResult.aspectRatio;
        if (hlsResult.width) video.originalResolution = { width: hlsResult.width, height: hlsResult.height };
        
        if (hlsResult.duration) {
            video.duration = hlsResult.duration;
        }

        // **SOURCE OF TRUTH: Always update videoType and aspectRatio based on actual processed result**
        if (hlsResult.aspectRatio) {
            video.aspectRatio = hlsResult.aspectRatio;
            video.videoType = hlsResult.aspectRatio > 1.0 ? 'vayu' : 'yog';
            console.log(`👷 Worker: Updated metadata for ${videoId}: AR=${video.aspectRatio}, Type=${video.videoType}`);
        }

        video.finalScore = RecommendationService.calculateFinalScore({
            totalWatchTime: 0,
            duration: video.duration,
            likes: 0,
            comments: 0,
            shares: 0,
            views: 0,
            uploadedAt: video.createdAt
        });
        
        await video.save();

        try {
            const moderationResult = await localModerationService.moderateVideo(localRawPath);
            const updatedVideo = await Video.findById(videoId);
            if (updatedVideo) {
                updatedVideo.moderationResult = {
                    isFlagged: moderationResult.isFlagged,
                    confidence: moderationResult.confidence,
                    label: moderationResult.label,
                    processedAt: new Date(),
                    provider: 'local-transformers'
                };
                if (moderationResult.isFlagged) updatedVideo.processingStatus = 'flagged';
                await updatedVideo.save();
            }
        } catch (modError) {
            console.error('⚠️ Worker: Local moderation failed:', modError.message);
        }

        try {
            const user = await User.findById(userId);
            if (user && user.googleId) {
                if (redisService.getConnectionStatus()) {
                    await invalidateCache([
                        'user:feed:*',
                        VideoCacheKeys.feed('all'),
                        VideoCacheKeys.user(user.googleId),
                        VideoCacheKeys.all()
                    ]);
                }
            }
        } catch (cacheError) {
            console.error('❌ Worker: Cache invalidation failed:', cacheError);
        }
    }

    await cloudflareR2Service.deleteFile(rawVideoKey);
    if (fs.existsSync(localRawPath)) fs.unlinkSync(localRawPath);

    return { status: 'completed', videoId };

  } catch (error) {
    console.error(`❌ Worker Error for ${videoId}:`, error);
    if (fs.existsSync(localRawPath)) fs.unlinkSync(localRawPath);
    await Video.findByIdAndUpdate(videoId, { 
        processingStatus: 'failed',
        processingError: error.message 
    });
    throw error;
  }
}

// **OPTIMIZED: Multi-Job Type Dispatcher**
const videoWorker = new Worker('video-processing', async (job) => {
  
  try {
    switch (job.name) {
      case 'process-video':
        return await handleVideoProcessing(job);
        
      case 'sync-counts':
        // JOB: Verify follower/following/saved counts for a user
        console.log('🔄 Worker: Syncing user counts...');
        // Implementation logic here...
        return { status: 'done' };
        
      case 'cleanup-orphaned':
        // JOB: Cleanup R2 files for deleted videos
        console.log('🧹 Worker: Cleaning up orphaned R2 files...');
        // Implementation logic here...
        return { status: 'done' };
        
      case 'recalculate-ranks':
        // JOB: Recalculate global creator ranks (scheduled every 2h)
        console.log('🏆 Worker: Recalculating global creator ranks...');
        await RecommendationService._calculateAndCacheRanks();
        console.log('✅ Worker: Ranks updated successfully');
        return { status: 'completed' };
        
      default:
        console.warn(`⚠️ Worker: Unknown job type ${job.name}`);
        return { status: 'ignored' };
    }
  } catch (error) {
    console.error(`❌ Worker Job ${job.id} failed:`, error);
    throw error;
  }
}, {
  connection: redisOptions,
  concurrency: 5 // Increased concurrency for higher throughput
});

videoWorker.on('completed', (job) => {
  console.log(`✅ Job ${job.id} completed!`);
});

videoWorker.on('failed', (job, err) => {
  console.log(`❌ Job ${job.id} failed: ${err.message}`);
});

console.log('👷 Video Worker Started and Listening for jobs...');
