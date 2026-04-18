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
  const { videoId, rawVideoKey, videoName, userId, crossPostPlatforms, thumbnailKey } = job.data;
  const tempDir = path.join(process.cwd(), 'temp_raw_downloads');
  if (!fs.existsSync(tempDir)) {
      fs.mkdirSync(tempDir, { recursive: true });
  }
  const localRawPath = path.join(tempDir, `${videoId}_raw${path.extname(rawVideoKey) || '.mp4'}`);

  try {
    // 1. Initial Status Update
    await Video.findByIdAndUpdate(videoId, { 
        processingStatus: 'processing',
        processingProgress: 10 
    });

    // 2. Download from R2 (unless it's already a local path from fallback upload)
    if (rawVideoKey.startsWith('http')) {
        console.log('👷 Worker: Downloading raw video from URL:', rawVideoKey);
        // Handle axios download if needed, or assume cloudflareR2Service handles URLs
        // For simplicity, let's assume rawVideoKey is usually an R2 Key
        await cloudflareR2Service.downloadFile(rawVideoKey, localRawPath);
    } else {
        console.log('👷 Worker: Downloading raw video from R2 Key:', rawVideoKey);
        await cloudflareR2Service.downloadFile(rawVideoKey, localRawPath);
    }
    
    await Video.findByIdAndUpdate(videoId, { processingProgress: 30 });

    // 3. Process Video to HLS
    // Note: processVideoToHLS handles FFmpeg encoding and R2 upload of segments
    const hlsResult = await hybridVideoService.processVideoToHLS(
        localRawPath,
        videoName,
        userId
    );

    // 4. Update Video Record with Results
    const video = await Video.findById(videoId);
    if (video) {
        video.videoUrl = hlsResult.videoUrl;
        video.hlsPlaylistUrl = hlsResult.hlsPlaylistUrl;
        
        // Use custom thumbnail if provided, otherwise use generated one
        if (thumbnailKey) {
            video.thumbnailUrl = cloudflareR2Service.getPublicUrl(thumbnailKey);
        } else {
            video.thumbnailUrl = hlsResult.thumbnailUrl;
        }

        video.processingStatus = 'completed';
        video.processingProgress = 100;
        video.isHLSEncoded = true;
        video.lowQualityUrl = hlsResult.videoUrl;
        
        if (hlsResult.aspectRatio) video.aspectRatio = hlsResult.aspectRatio;
        if (hlsResult.width) video.originalResolution = { width: hlsResult.width, height: hlsResult.height };
        if (hlsResult.duration) video.duration = hlsResult.duration;

        // **SOURCE OF TRUTH: Always update videoType based on aspect ratio**
        if (hlsResult.aspectRatio) {
            video.videoType = hlsResult.aspectRatio > 1.0 ? 'vayu' : 'yog';
        }

        // Initialize Recommendation Score
        video.finalScore = recommendationService.calculateFinalScore({
            totalWatchTime: 0,
            duration: video.duration,
            likes: 0,
            shares: 0,
            views: 0,
            uploadedAt: video.createdAt
        });
        
        await video.save();
        console.log(`✅ Worker: Video ${videoId} processed and saved.`);

        // 5. Trigger Social Cross-Posting if requested
        if (crossPostPlatforms && Array.isArray(crossPostPlatforms) && crossPostPlatforms.length > 0) {
            console.log(`📡 Worker: Triggering cross-posting for ${videoId}`);
            for (const platform of crossPostPlatforms) {
                try {
                    await addSocialJob(platform, {
                        videoId: video._id.toString(),
                        userId: userId,
                        title: videoName,
                        description: video.description,
                        tags: video.tags
                    });
                } catch (err) {
                    console.error(`❌ Worker: Failed to add ${platform} job:`, err.message);
                }
            }
        }

        // 6. Local Moderation (AI Scan)
        try {
            const moderationResult = await moderationService.moderateVideo(localRawPath);
            const updatedVideo = await Video.findById(videoId);
            if (updatedVideo) {
                updatedVideo.moderationResult = {
                    isFlagged: moderationResult.isFlagged,
                    confidence: moderationResult.confidence,
                    label: moderationResult.label,
                    processedAt: new Date(),
                    provider: 'local-transformers'
                };
                if (moderationResult.isFlagged) {
                    console.log(`🚩 Worker: Video ${videoId} FLAGGED by AI.`);
                    updatedVideo.processingStatus = 'flagged';
                }
                await updatedVideo.save();
            }
        } catch (modError) {
            console.error('⚠️ Worker: Local moderation failed:', modError.message);
        }

        // 7. Cache Invalidation
        try {
            const user = await User.findById(userId);
            if (user && user.googleId) {
                await invalidateCache([
                    'user:feed:*',
                    VideoCacheKeys.feed('all'),
                    VideoCacheKeys.user(user.googleId),
                    VideoCacheKeys.all()
                ]);
                console.log('🧹 Worker: Cache invalidated for user feed.');
            }
        } catch (cacheError) {
            console.error('❌ Worker: Cache invalidation failed:', cacheError);
        }
    }

    // 8. Cleanup
    // Delete raw video from R2 (optional, depends on policy)
    // await cloudflareR2Service.deleteFile(rawVideoKey); 
    
    // Always cleanup local temp file
    if (fs.existsSync(localRawPath)) {
        fs.unlinkSync(localRawPath);
        console.log('🧹 Worker: Cleaned up local temp file.');
    }

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
        console.log('🔄 Worker: Syncing user counts...');
        return { status: 'done' };
        
      case 'cleanup-orphaned':
        console.log('🧹 Worker: Cleaning up orphaned R2 files...');
        return { status: 'done' };
        
      case 'recalculate-ranks':
        console.log('🏆 Worker: Recalculating global creator ranks...');
        await recommendationService._calculateAndCacheRanks();
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
  concurrency: 1 // CRITICAL: Only 1 job at a time on 1GB Fly.io machine
});

videoWorker.on('completed', (job) => {
  console.log(`✅ Job ${job.id} completed!`);
});

videoWorker.on('failed', (job, err) => {
  console.log(`❌ Job ${job.id} failed: ${err.message}`);
});

console.log('👷 Video Worker Started and Listening for jobs...');
