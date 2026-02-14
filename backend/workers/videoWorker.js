import { Worker } from 'bullmq';
import mongoose from 'mongoose';
import Video from '../models/Video.js';
import hybridVideoService from '../services/hybridVideoService.js';
import cloudflareR2Service from '../services/cloudflareR2Service.js';
import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';
import { redisOptions } from '../services/queueService.js';
import User from '../models/User.js';
import redisService from '../services/redisService.js';
import { invalidateCache, VideoCacheKeys } from '../middleware/cacheMiddleware.js';
import RecommendationService from '../services/recommendationService.js';

dotenv.config();

// Connect to MongoDB (Worker needs its own connection)
const connectDB = async () => {
  try {
    await mongoose.connect(process.env.MONGODB_URI);
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

const videoWorker = new Worker('video-processing', async (job) => {
  console.log(`👷 Worker: Processing job ${job.id} for video ${job.data.videoId}`);
  const { videoId, rawVideoKey, videoName, userId } = job.data;
  
  // Create a local temp path for downloading the raw video
  const tempDir = path.join(process.cwd(), 'temp_raw_downloads');
  if (!fs.existsSync(tempDir)) {
      fs.mkdirSync(tempDir, { recursive: true });
  }
  
  // Use a unique name for the local temp file
  const localRawPath = path.join(tempDir, `${videoId}_raw${path.extname(rawVideoKey) || '.mp4'}`);

  try {
    // 1. Update status to Processing
    await Video.findByIdAndUpdate(videoId, { 
        processingStatus: 'processing',
        processingProgress: 10 
    });

    // 2. Download Raw Video from R2
    console.log(`⬇️ Worker: Downloading raw video from R2 key: ${rawVideoKey}`);
    
    // We need a method in cloudflareR2Service to download file to disk
    // If not exists, we'll assume we can use the "upload" stream logic in reverse or just use getObject
    // For now, let's implement a quick download helper here if R2 service doesn't have one exposed
    // But better to use the service if possible. Checking service first...
    // Assuming we added download support or will add it.
    // For this plan, let's assume rawVideoKey IS available via public URL or signed URL?
    // Actually, R2 private buckets need S3 `getObject`.
    
    // Let's rely on `cloudflareR2Service` having a download method. 
    // If it doesn't, we will add it.
    await cloudflareR2Service.downloadFile(rawVideoKey, localRawPath);
    console.log('✅ Worker: Download complete');

    // 3. Process Video (Using existing Hybrid/HLS Service)
    // We pass the LOCAL path we just downloaded
    console.log('🎬 Worker: Starting FFmpeg encoding...');
    await Video.findByIdAndUpdate(videoId, { processingProgress: 30 });

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
        video.thumbnailUrl = hlsResult.thumbnailUrl;
        video.processingStatus = 'completed';
        video.processingProgress = 100;
        video.isHLSEncoded = true;
        video.lowQualityUrl = hlsResult.videoUrl;
        
        if (hlsResult.aspectRatio) video.aspectRatio = hlsResult.aspectRatio;
        if (hlsResult.width) video.originalResolution = { width: hlsResult.width, height: hlsResult.height };
        
        // **NEW: Update duration and videoType based on real data**
        if (hlsResult.duration) {
            video.duration = hlsResult.duration;
            // Harmonize type: Yug < 120s, Vayu >= 120s
            video.videoType = hlsResult.duration > 120 ? 'vayu' : 'yog';
        }

        // **NEW: Initialize Recommendation Score (with Discovery Bonus)**
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

        console.log('✅ Worker: Video record updated');

        // 4.1 Invalidate Cache (CRITICAL for updating user profile immediately)
        try {
            const user = await User.findById(userId);
            if (user && user.googleId) {
                if (redisService.getConnectionStatus()) {
                    await invalidateCache([
                        'user:feed:*', // Clear all personalized feed queues
                        VideoCacheKeys.feed('all'), // Clear general feed
                        VideoCacheKeys.user(user.googleId), // Clear user profile videos
                        VideoCacheKeys.all() // Clear all videos (safety)
                    ]);
                    console.log(`🧹 Worker: Cache invalidated for user ${user.googleId}`);
                }
            }
        } catch (cacheError) {
            console.error('❌ Worker: Cache invalidation failed:', cacheError);
        }
    }

    // 5. Cleanup Raw File from R2 (Cost Saving)
    console.log(`🧹 Worker: Deleting raw file from R2...`);
    await cloudflareR2Service.deleteFile(rawVideoKey);
    console.log('✅ Worker: Raw file deleted from R2');

    // 6. Cleanup Local Temp File
    if (fs.existsSync(localRawPath)) {
        fs.unlinkSync(localRawPath);
    }

    return { status: 'completed', videoId };

  } catch (error) {
    console.error(`❌ Worker Error for ${videoId}:`, error);
    
    // Cleanup Local Temp File on Error too
    if (fs.existsSync(localRawPath)) {
        fs.unlinkSync(localRawPath);
    }

    // Update DB to Failed
    await Video.findByIdAndUpdate(videoId, { 
        processingStatus: 'failed',
        processingError: error.message 
    });
    
    throw error;
  }
}, {
  connection: redisOptions,
  concurrency: 2 // Optimized to process more videos simultaneously
});

videoWorker.on('completed', (job) => {
  console.log(`✅ Job ${job.id} completed!`);
});

videoWorker.on('failed', (job, err) => {
  console.log(`❌ Job ${job.id} failed: ${err.message}`);
});

console.log('👷 Video Worker Started and Listening for jobs...');
