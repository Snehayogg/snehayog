import redisService from '../services/redisService.js';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
dotenv.config({ path: path.join(__dirname, '../.env') });

async function clearQueues() {
  console.log('🧹 Connecting to Redis...');
  
  const connected = await redisService.connect();
  
  if (!connected) {
    console.error('❌ Redis not connected!');
    process.exit(1);
  }

  try {
    console.log('🧹 finding user feed keys...');
    
    // Scan for all feed keys (Vayu and Yog)
    // Pattern: user:feed:*:*  (e.g., user:feed:123:vayu, user:feed:123:yog)
    console.log('🧹 Clearing user:feed:* ...');
    const count = await redisService.clearPattern('user:feed:*');
    
    if (count > 0) {
        console.log(`✅ Deleted ${count} feed queues. They will auto-regenerate on next user request.`);
    } else {
        console.log('ℹ️ No feed queues found to delete.');
    }

  } catch (err) {
    console.error('❌ Error clearing queues:', err);
  } finally {
    console.log('👋 Done.');
    process.exit(0);
  }
}

clearQueues();
