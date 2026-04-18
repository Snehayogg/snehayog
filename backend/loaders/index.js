import expressLoader from './express.js';
import mongooseLoader from './mongoose.js';
import redisLoader from './redis.js';
import jobsLoader from './jobs.js';

export default async ({ expressApp }) => {
  // 1. Initial configuration (DB happens in background but we start the process)
  await mongooseLoader();
  console.log('✌️ DB Loaded');

  // 2. Redis connection
  await redisLoader();
  console.log('✌️ Redis Loaded');

  // 3. Express configuration
  await expressLoader({ app: expressApp });
  console.log('✌️ Express Loaded');

  // 4. Background jobs (Only if not in test mode)
  if (process.env.NODE_ENV !== 'test') {
    await jobsLoader();
    console.log('✌️ Jobs Loaded');
  }

  return expressApp;
};
