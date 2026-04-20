import '../../config/env.js';
import { Queue } from 'bullmq';

// Initializing Redis connection options from URL or individual parts
let redisOptions = {
  host: process.env.REDISHOST || process.env.REDIS_HOST || 'localhost',
  port: process.env.REDISPORT || process.env.REDIS_PORT || 6379,
  password: process.env.REDISPASSWORD || process.env.REDIS_PASSWORD,
  maxRetriesPerRequest: null, // Required by BullMQ
};

// **FIX: Parse REDIS_PUBLIC_URL if available**
const redisUrl = process.env.REDIS_PUBLIC_URL || process.env.REDIS_URL;
if (redisUrl) {
  try {
    // Force rediss:// for TLS if not already present
    const secureUrl = redisUrl.startsWith('redis://') ? redisUrl.replace('redis://', 'rediss://') : redisUrl;
    const parsedUrl = new URL(secureUrl);
    
    redisOptions = {
      host: parsedUrl.hostname,
      port: parseInt(parsedUrl.port, 10),
      password: parsedUrl.password,
      username: parsedUrl.username,
      maxRetriesPerRequest: null,
      connectTimeout: 10000, // 10s to connect
      commandTimeout: 5000,  // 5s to execute command (don't hang!)
      keepAlive: 1000,      // Send keep-alive every 1s
      enableReadyCheck: false, // Skip ready check for faster proxy handshake
      retryStrategy: (times) => {
        const delay = Math.min(times * 50, 2000);
        return delay;
      },
      // **RE-ENABLED: TLS for public access**
      tls: (parsedUrl.protocol === 'rediss:') ? {
        rejectUnauthorized: false
      } : undefined,
    };
    console.log('✅ QueueService: Connected to Redis');
  } catch (err) {
    console.error('❌ QueueService: Error parsing REDIS_URL:', err.message);
  }
} else {
  console.log(`🔧 QueueService: Configured using individual environment variables`);
}

// Create the video processing queue
const videoQueue = new Queue('video-processing', {
  connection: redisOptions
});


class FeedQueueService {
    constructor() {
        // **FIX: Skip automatic scheduling in test mode**
        if (process.env.NODE_ENV !== 'test') {
            this.addRankCalculationJob(); 
        }
    }

    /**
     * **NEW: Close the queue connection (for Clean Teardown)**
     */
    async close() {
        try {
            await videoQueue.close();
        } catch (error) {
            // Silently fail if already closed
        }
    }

    /**
     * **NEW: Add rank calculation job to the queue**
     * This is a repeatable job that runs every 2 hours to prevent
     * API thundering herd on cache misses.
     */
    async addRankCalculationJob() {
        try {
            await videoQueue.add('recalculate-ranks', {}, {
                repeat: {
                    every: 2 * 60 * 60 * 1000
                },
                removeOnComplete: true
            });
            console.log('✅ QueueService: Rank calculation scheduled');
        } catch (error) {
            console.error('❌ QueueService: Failed to schedule rank calculation:', error);
        }
    }

    /**
     * Add a video processing job to the queue
     * @param {Object} data - Job data
     * @param {string} data.videoId - Video ID
     * @param {string} data.rawVideoKey - R2 key for the raw video
     * @param {string} data.videoName - Video name
     * @param {string} data.userId - User ID
     */
    async addVideoJob(data) {
        try {
            console.log('📥 QueueService: Adding video job to queue:', data.videoId);
            await videoQueue.add('process-video', data, {
                attempts: 3,
                backoff: { type: 'exponential', delay: 5000 },
                removeOnComplete: true,
                removeOnFail: false
            });
            console.log('✅ QueueService: Job added successfully');
            return true;
        } catch (error) {
            console.error('❌ QueueService: Failed to add job:', error);
            throw error;
        }
    }

    /**
     * Add a clip generation job to the queue
     * @param {Object} data - { originalVideoId, startTime, duration, userId, videoName }
     */
    async addClipJob(data) {
        try {
            console.log('📥 QueueService: Adding clip job for video:', data.originalVideoId);
            await videoQueue.add('generate-clip', data, {
                attempts: 2,
                backoff: { type: 'exponential', delay: 10000 },
                removeOnComplete: true,
                removeOnFail: false
            });
            return true;
        } catch (error) {
            console.error('❌ QueueService: Failed to add clip job:', error);
            throw error;
        }
    }

    
    // Legacy FanOut method (stub or move existing logic here if needed)
    async fanOutToFollowers(userId, videoId, videoType) {
        // Implementation can stay as is if it's already working directly via DB
        // Or we can move it to a background job too later.
        // For now, let's focus on video processing.
        console.log('fanOutToFollowers placeholder called');
        return 0;
    }
}

export default new FeedQueueService();
export { videoQueue, redisOptions };
