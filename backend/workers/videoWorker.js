import '../config/env.js';
import { Worker } from 'bullmq';
import mongoose from 'mongoose';
import Video from '../models/Video.js';
import fs from 'fs';
import path from 'path';
import hybridVideoService from '../services/uploadServices/hybridVideoService.js';
import cloudflareR2Service from '../services/uploadServices/cloudflareR2Service.js';
import queueService from '../services/yugFeedServices/queueService.js';
import eventBus from '../utils/eventBus.js';
import { redisOptions } from '../services/yugFeedServices/queueService.js'; 
import User from '../models/User.js';
import redisService from '../services/caching/redisService.js';
import { invalidateCache, VideoCacheKeys } from '../middleware/cacheMiddleware.js';
import recommendationService from '../services/yugFeedServices/recommendationService.js';
import moderationService from '../services/uploadServices/localModerationService.js';
import videoClippingService from '../services/uploadServices/videoClippingService.js';
import * as notificationService from '../services/notificationServices/notificationService.js';

// Connect to MongoDB & Redis (If not already connected)
const initializeWorkerConnections = async () => {
  try {
    if (mongoose.connection.readyState !== 1) {
      await mongoose.connect(process.env.MONGO_URI);
      console.log('📦 Worker MongoDB Connected');
    }
    
    // Connect to Redis for cache invalidation
    if (!redisService.getConnectionStatus || !redisService.getConnectionStatus()) {
      await redisService.connect();
      console.log('📦 Worker Redis Connected');
    }
  } catch (error) {
    console.error('❌ Worker Connection Error:', error);
    // Don't exit if it's integrated, just log
    if (!process.env.FLY_APP_NAME) process.exit(1);
  }
};

initializeWorkerConnections();

async function handleVideoProcessing(job) {
  const { videoId, rawVideoKey, videoName, userId, crossPostPlatforms, thumbnailKey } = job.data;
  const tempDir = path.join(process.cwd(), 'temp_raw_downloads');
  if (!fs.existsSync(tempDir)) {
      fs.mkdirSync(tempDir, { recursive: true });
  }
  const localRawPath = path.join(tempDir, `${videoId}_raw${path.extname(rawVideoKey) || '.mp4'}`);

  try {
    // 1. Initial Status Update
    console.log(`👷 Worker: Starting job for video ${videoId}`);
    await Video.findByIdAndUpdate(videoId, { 
        processingStatus: 'processing',
        processingProgress: 5 
    });

    // 2. Download from R2
    console.log(`👷 Worker: [Step 1/4] Downloading source from ${rawVideoKey.startsWith('http') ? 'URL' : 'R2'}...`);
    await cloudflareR2Service.downloadFile(rawVideoKey, localRawPath);
    
    await Video.findByIdAndUpdate(videoId, { processingProgress: 15 });

    // 3. Process Video to HLS (with real-time progress)
    console.log(`👷 Worker: [Step 2/4] Processing HLS encoding for ${videoId}...`);
    const hlsResult = await hybridVideoService.processVideoToHLS(
        localRawPath,
        videoName,
        userId,
        {
          videoId: videoId, // Pass ID for early thumbnail update
          onProgress: async (percent) => {
            // Throttled progress update to database
            if (percent % 5 === 0) {
              await Video.findByIdAndUpdate(videoId, { processingProgress: percent });
            }
          }
        }
      );

    // 4. Update Video Record with Final Results
    console.log(`👷 Worker: [Step 3/4] Finalizing video record for ${videoId}...`);
    const video = await Video.findById(videoId);
    if (video) {
        video.videoUrl = hlsResult.videoUrl;
        video.hlsPlaylistUrl = hlsResult.hlsPlaylistUrl;
        
        // Use custom thumbnail if provided, otherwise use generated one
        if (thumbnailKey) {
            video.thumbnailUrl = cloudflareR2Service.getPublicUrl(thumbnailKey);
        } else {
            // Already updated early in processVideoToHLS, but ensure it's set
            video.thumbnailUrl = hlsResult.thumbnailUrl || video.thumbnailUrl;
        }

        video.processingStatus = 'completed';
        video.processingProgress = 100;
        video.isHLSEncoded = true;
        video.lowQualityUrl = hlsResult.videoUrl;
        
        if (hlsResult.aspectRatio) video.aspectRatio = hlsResult.aspectRatio;
        if (hlsResult.width) video.originalResolution = { width: hlsResult.width, height: hlsResult.height };
        if (hlsResult.duration) video.duration = hlsResult.duration;

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
        console.log(`✅ Worker: Video ${videoId} processing completed.`);

        // 5. Trigger Social Cross-Posting
        if (crossPostPlatforms && Array.isArray(crossPostPlatforms) && crossPostPlatforms.length > 0) {
            console.log(`📡 Worker: [Step 4/4] Triggering cross-posting for ${videoId}...`);
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

        // 6. Local Moderation (Async)
        moderationService.moderateVideo(localRawPath).then(async (moderationResult) => {
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
        }).catch(modError => {
            console.error('⚠️ Worker: Local moderation failed:', modError.message);
        });

        // 7. Cache Invalidation
        try {
            const user = await User.findOne({ googleId: userId });
            if (user && user.googleId) {
                await invalidateCache([
                    'user:feed:*',
                    VideoCacheKeys.feed('all'),
                    VideoCacheKeys.user(user.googleId),
                    VideoCacheKeys.all()
                ]);
                console.log('🧹 Worker: Cache invalidated.');
            }
        } catch (cacheError) {
            console.error('❌ Worker: Cache invalidation failed:', cacheError.message);
        }
    }

    // 8. Cleanup
    if (rawVideoKey && video && video.isHLSEncoded) {
        try {
            console.log(`🧹 Worker: Deleting original source to save costs: ${rawVideoKey}`);
            await cloudflareR2Service.deleteVideoFromR2(rawVideoKey);
        } catch (e) {
            console.warn('⚠️ Worker: Failed to delete source (non-fatal):', e.message);
        }
    }

    if (fs.existsSync(localRawPath)) {
        fs.unlinkSync(localRawPath);
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

/**
 * Handle generating a vertical clip from a long video
 */
async function handleClipGeneration(data) {
  const { 
    originalVideoId, 
    sourceKey, 
    startTime, 
    duration, 
    userId, 
    videoName,
    isEphemeral = false, 
    targetVideoId 
  } = data;

  const tempDir = path.join(process.cwd(), 'temp_raw_downloads');
  if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });

  const clipId = targetVideoId ? new mongoose.Types.ObjectId(targetVideoId) : new mongoose.Types.ObjectId();
  const localRawPath = path.join(tempDir, `${clipId}_source.mp4`);
  const localClipPath = path.join(tempDir, `${clipId}_clip.mp4`);
  let finalSourceKey = sourceKey;

  try {
    let originalVideo = null;

    if (originalVideoId) {
      originalVideo = await Video.findById(originalVideoId);
      if (originalVideo) {
        finalSourceKey = originalVideo.canonicalMp4Key || originalVideo.rawVideoKey;
      }
    }

    if (!finalSourceKey) throw new Error('No source video key found');
    
    // **ULTRA-FAST OPTIMIZATION: Use streaming instead of full download**
    const sourceUrl = cloudflareR2Service.getPublicUrl(finalSourceKey);
    console.log(`🌐 Streaming source for clipping from URL: ${sourceUrl}`);

    // 2. Generate Blurry Vertical Clip
    await videoClippingService.generateBlurryVerticalClip(sourceUrl, localClipPath, {
        startTime,
        duration
    });

    // 3. Upload Clip to R2
    const clipKey = `videos/${userId}/clips/${clipId}.mp4`;
    const uploadResult = await cloudflareR2Service.uploadFileToR2(localClipPath, clipKey, 'video/mp4');

    // 4. Update or Create Video Record
    let clipVideo;
    if (targetVideoId) {
      clipVideo = await Video.findById(targetVideoId);
    }

    const videoData = {
      videoName: videoName || (originalVideo ? `${originalVideo.videoName} (Clip)` : 'My Clip'),
      uploader: userId,
      videoType: 'yog',
      mediaType: 'video',
      videoUrl: uploadResult.url,
      thumbnailUrl: uploadResult.url, 
      processingStatus: 'completed',
      processingProgress: 100,
      aspectRatio: 9/16,
      duration: duration,
      isHLSEncoded: false,
      uploadedAt: new Date()
    };

    if (clipVideo) {
      Object.assign(clipVideo, videoData);
      await clipVideo.save();
    } else {
      clipVideo = new Video({
        _id: clipId,
        ...videoData
      });
      await clipVideo.save();
    }

    // 5. Cleanup local files
    if (fs.existsSync(localRawPath)) fs.unlinkSync(localRawPath);
    if (fs.existsSync(localClipPath)) fs.unlinkSync(localClipPath);

    // **CRITICAL: Cleanup R2 Source to save costs**
    if (isEphemeral && finalSourceKey) {
      try {
        console.log(`🧹 Cleaning up R2 source for ephemeral clipping: ${finalSourceKey}`);
        await cloudflareR2Service.deleteVideoFromR2(finalSourceKey);
      } catch (e) {
        console.warn('⚠️ Failed to cleanup R2 source:', e.message);
      }
    }

    console.log(`✅ Clip ${clipId} generated and saved! URL: ${uploadResult.url}`);
    
    // **PUSH NOTIFICATION: Notify user's mobile device**
    try {
        const user = await User.findById(userId);
        if (user && user.googleId) {
            await notificationService.sendNotificationToUser(user.googleId, {
                title: "Shorts Generator ✨",
                body: "Your shorts is ready tap to download 🥳",
                data: {
                    type: "clipping_complete",
                    jobId: clipId.toString(),
                    videoUrl: uploadResult.url
                }
            });
        }
    } catch (pushErr) {
        console.warn('⚠️ Failed to send completion push notification:', pushErr.message);
    }

    return { status: 'completed', clipId: clipId.toString(), url: uploadResult.url };

  } catch (error) {
    console.error('❌ Clip generation failed:', error);
    if (fs.existsSync(localRawPath)) fs.unlinkSync(localRawPath);
    if (fs.existsSync(localClipPath)) fs.unlinkSync(localClipPath);
    
    const failedJobId = targetVideoId || clipId;

    if (failedJobId) {
       await Video.findByIdAndUpdate(failedJobId, { 
         processingStatus: 'failed',
         processingError: error.message 
       });

       // **PUSH NOTIFICATION: Notify user of failure**
       try {
           const user = await User.findById(userId);
           if (user && user.googleId) {
               await notificationService.sendNotificationToUser(user.googleId, {
                   title: "Magician Error ❌",
                   body: "Failed to generate your short. Please try again.",
                   data: { type: "clipping_failed", jobId: failedJobId.toString() }
               });
           }
       } catch (pushErr) {}

       // **SSE NOTIFICATION: Notify EventBus of failure**
       eventBus.emit('clipping-status', {
           jobId: failedJobId.toString(),
           status: 'failed',
           error: error.message
       });
    }
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

      case 'generate-clip':
        console.log('🎬 Worker: Generating vertical clip...');
        return await handleClipGeneration(job.data);
        
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
