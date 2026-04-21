import '../../config/env.js';
import { Queue } from 'bullmq';

// Initializing Redis connection options from URL or individual parts
export let redisOptions = {
  host: process.env.REDISHOST || process.env.REDIS_HOST || 'localhost',
  port: process.env.REDISPORT || process.env.REDIS_PORT || 6379,
  password: process.env.REDISPASSWORD || process.env.REDIS_PASSWORD,
  maxRetriesPerRequest: null, // Required by BullMQ
  // Default to IPv4 for local, but Fly.io internal needs IPv6
  family: process.env.FLY_APP_NAME ? 6 : 4,
};

// **FIX: Prioritize REDIS_URL for internal Fly.io networking**
const redisUrl = process.env.REDIS_URL || process.env.REDIS_PUBLIC_URL;
if (redisUrl) {
  try {
    const parsedUrl = new URL(redisUrl);
    const isRedisSecure = redisUrl.startsWith('rediss://');
    
    // Determine if this is an internal Fly address (they don't support TLS on port 6379)
    const isInternalFly = parsedUrl.hostname.includes('.internal');

    redisOptions = {
      host: parsedUrl.hostname,
      port: parseInt(parsedUrl.port, 10),
      password: parsedUrl.password,
      username: parsedUrl.username,
      maxRetriesPerRequest: null,
      connectTimeout: 60000,   // 60s (Increased for Fly.io cold starts)
      commandTimeout: 30000,   // 30s
      keepAlive: 2000,        // Every 2s
      enableReadyCheck: false,
      // **CRITICAL: IPv6 (family 6) is ONLY mandatory for internal Fly.io networking**
      family: process.env.FLY_APP_NAME ? 6 : undefined, 
      retryStrategy: (times) => Math.min(times * 200, 5000),
      // **FIX: Explicitly disable TLS if using standard redis:// to prevent wrong version errors**
      tls: isRedisSecure ? { rejectUnauthorized: false } : false,
    };

    console.log(`📡 QueueService: Redis Configured → ${parsedUrl.hostname}:${parsedUrl.port}`);
    console.log(`🔒 Security: ${isRedisSecure ? 'TLS Enabled' : 'Plaintext (Internal)'} | 🌐 Network: IPv${redisOptions.family || 4}`);
    
    if (isRedisSecure && isInternalFly) {
      console.warn('⚠️ WARNING: Using rediss:// on an internal Fly address may cause SSL version errors.');
    }
  } catch (err) {
    console.error('❌ QueueService: URL Parse failed:', err.message);
  }
} else {
  console.log(`🔧 QueueService: Using individual env variables | 🌐 Network: IPv${redisOptions.family}`);
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
                    every: 12 * 60 * 60 * 1000 // Every 12 hours instead of 2
                },
                removeOnComplete: true,
                priority: 10 // Low priority (Videos are priority 1)
            });
            console.log('✅ QueueService: Rank calculation scheduled (every 12h)');
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
                removeOnFail: false,
                priority: 1 // High Priority
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
                removeOnFail: false,
                priority: 1 // High Priority
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
export { videoQueue };
