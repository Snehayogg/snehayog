#!/usr/bin/env node

/**
 * GET TEST VIDEO ID SCRIPT
 * 
 * This script gets a video ID from the database for testing.
 * 
 * Usage:
 *   node scripts/get-test-video-id.js
 */

import dotenv from 'dotenv';
import mongoose from 'mongoose';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import Video from '../models/Video.js';

// Load environment variables
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
dotenv.config({ path: join(__dirname, '../.env') });

// Colors for console output
const colors = {
  reset: '\x1b[0m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m',
  red: '\x1b[31m',
};

function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

async function getTestVideoId() {
  try {
    // Connect to MongoDB
    const mongoUri = process.env.MONGODB_URI || process.env.MONGO_URI;
    if (!mongoUri) {
      log('❌ Error: MONGODB_URI or MONGO_URI not found in environment variables', 'red');
      process.exit(1);
    }

    log('🔌 Connecting to database...', 'blue');
    await mongoose.connect(mongoUri);
    log('✅ Connected to database', 'green');

    // Get first available video
    const video = await Video.findOne({})
      .select('_id videoName likes likedBy')
      .lean();

    if (!video) {
      log('❌ No videos found in database', 'red');
      await mongoose.disconnect();
      process.exit(1);
    }

    log('\n✅ Found video for testing:', 'green');
    log(`   Video ID: ${video._id}`, 'cyan');
    log(`   Video Name: ${video.videoName || 'N/A'}`, 'cyan');
    log(`   Current Likes: ${video.likes || 0}`, 'cyan');
    log(`   Liked By Count: ${video.likedBy?.length || 0}`, 'cyan');
    
    if (video.likes !== (video.likedBy?.length || 0)) {
      log(`   ⚠️  WARNING: Likes count doesn't match likedBy length!`, 'yellow');
    }

    log('\n📋 To test like endpoint, run:', 'blue');
    log(`   npm run test:like ${video._id} <your-jwt-token>`, 'yellow');
    log('\n💡 To get your JWT token:', 'blue');
    log('   1. Check Flutter app logs for "Token starts with: ..."', 'yellow');
    log('   2. Or check SharedPreferences in your app', 'yellow');
    log('   3. Or login to your app and check stored token', 'yellow');

    await mongoose.disconnect();
    
    // Return video ID for use in other scripts
    return video._id.toString();
  } catch (error) {
    log(`❌ Error: ${error.message}`, 'red');
    await mongoose.disconnect();
    process.exit(1);
  }
}

getTestVideoId()
  .then((videoId) => {
    process.exit(0);
  })
  .catch((error) => {
    log(`❌ Failed: ${error.message}`, 'red');
    process.exit(1);
  });

