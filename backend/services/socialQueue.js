import { Queue } from 'bullmq';
import { redisOptions } from './yugFeedServices/queueService.js';

// **Social Media Publishing Queue**
// Handles background uploads to YouTube, Instagram, etc.
// Logic: Each platform upload is a separate job to allow independent retries.
export const socialPublishingQueue = new Queue('social-publishing', {
  connection: redisOptions,
  defaultJobOptions: {
    attempts: 3,
    backoff: {
      type: 'exponential',
      delay: 5000, // 5 seconds initial delay
    },
    removeOnComplete: true,
    removeOnFail: false,
  },
});

/**
 * Add a cross-posting job to the queue
 * @param {string} platform - 'youtube', 'instagram', 'facebook', 'linkedin'
 * @param {Object} data - { videoId, userId, title, description, tags, etc }
 */
export const addSocialJob = async (platform, data) => {
  try {
    const jobName = `publish-${platform}`;
    const job = await socialPublishingQueue.add(jobName, {
      platform,
      ...data
    });
    console.log(`📡 SocialQueue: Added ${platform} job (${job.id}) for video ${data.videoId}`);
    return job;
  } catch (error) {
    console.error(`❌ SocialQueue Error adding ${platform} job:`, error);
    throw error;
  }
};

export default socialPublishingQueue;
