import { Queue } from 'bullmq';
import Redis from 'ioredis';
import dotenv from 'dotenv';

dotenv.config();

// Initializing Redis connection options
const redisOptions = {
  host: process.env.REDIS_HOST,
  port: process.env.REDIS_PORT,
  password: process.env.REDIS_PASSWORD,
  maxRetriesPerRequest: null, // Required by BullMQ
};

// Create the video processing queue
const videoQueue = new Queue('video-processing', {
  connection: redisOptions
});

class FeedQueueService {
    constructor() {
        console.log('🔄 FeedQueueService: Initialized (with actual Queue support)');
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
                attempts: 3, // Retry 3 times on failure
                backoff: {
                    type: 'exponential',
                    delay: 5000 // Start retry after 5s, then 10s, 20s...
                },
                removeOnComplete: true, // Keep queue clean
                removeOnFail: false // Keep failed jobs for inspection
            });
            console.log('✅ QueueService: Job added successfully');
            return true;
        } catch (error) {
            console.error('❌ QueueService: Failed to add job:', error);
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
