#!/usr/bin/env node

/**
 * CHECK LIKE REQUESTS SCRIPT
 * 
 * This script helps you check if like requests are reaching the backend.
 * It provides multiple methods to verify this.
 * 
 * Usage:
 *   node scripts/check-like-requests.js
 */

import dotenv from 'dotenv';
import mongoose from 'mongoose';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';
import Video from '../models/Video.js';
import fs from 'fs';

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
  bright: '\x1b[1m',
};

function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

function logSection(title) {
  console.log('\n' + '='.repeat(60));
  log(title, 'cyan');
  console.log('='.repeat(60));
}

async function checkLikeRequests() {
  logSection('🔍 LIKE REQUEST CHECKER');
  
  log('This script helps you verify if like requests are reaching the backend.\n', 'blue');

  // Method 1: Check recent video likes in database
  logSection('📊 METHOD 1: Check Database for Recent Likes');
  
  try {
    const mongoUri = process.env.MONGODB_URI || process.env.MONGO_URI;
    if (!mongoUri) {
      log('❌ MONGODB_URI not found', 'red');
    } else {
      log('🔌 Connecting to database...', 'blue');
      await mongoose.connect(mongoUri);
      log('✅ Connected to database', 'green');

      // Get videos with recent updates (last 5 minutes)
      const fiveMinutesAgo = new Date(Date.now() - 5 * 60 * 1000);
      
      const recentVideos = await Video.find({
        updatedAt: { $gte: fiveMinutesAgo }
      })
      .select('_id videoName likes likedBy updatedAt')
      .sort({ updatedAt: -1 })
      .limit(10)
      .lean();

      if (recentVideos.length > 0) {
        log(`\n✅ Found ${recentVideos.length} videos updated in last 5 minutes:`, 'green');
        recentVideos.forEach((video, index) => {
          log(`\n${index + 1}. Video: ${video.videoName || 'N/A'}`, 'cyan');
          log(`   ID: ${video._id}`, 'blue');
          log(`   Likes: ${video.likes || 0}`, 'blue');
          log(`   LikedBy Count: ${video.likedBy?.length || 0}`, 'blue');
          log(`   Updated: ${video.updatedAt}`, 'blue');
          
          if (video.likes !== (video.likedBy?.length || 0)) {
            log(`   ⚠️  WARNING: Count mismatch!`, 'yellow');
          }
        });
        log('\n💡 If you see videos updated recently, like requests ARE reaching the backend!', 'green');
      } else {
        log('⚠️  No videos updated in the last 5 minutes', 'yellow');
        log('💡 This could mean:', 'blue');
        log('   1. No like requests were made recently', 'yellow');
        log('   2. Like requests are not reaching the backend', 'yellow');
        log('   3. Database updates are not happening', 'yellow');
      }

      // Get a test video ID
      const testVideo = await Video.findOne({})
        .select('_id videoName')
        .lean();
      
      if (testVideo) {
        log(`\n📋 Test Video ID: ${testVideo._id}`, 'cyan');
        log(`   Video Name: ${testVideo.videoName || 'N/A'}`, 'cyan');
      }

      await mongoose.disconnect();
    }
  } catch (error) {
    log(`❌ Database error: ${error.message}`, 'red');
  }

  // Method 2: Check log files
  logSection('📄 METHOD 2: Check Backend Logs');
  
  const logFile = join(__dirname, '../logs/app.log');
  if (fs.existsSync(logFile)) {
    log(`✅ Log file found: ${logFile}`, 'green');
    
    try {
      const logContent = fs.readFileSync(logFile, 'utf8');
      const likeLogs = logContent
        .split('\n')
        .filter(line => line.includes('Like API'))
        .slice(-10); // Last 10 like-related logs
      
      if (likeLogs.length > 0) {
        log(`\n✅ Found ${likeLogs.length} recent like-related log entries:`, 'green');
        likeLogs.forEach((logLine, index) => {
          if (logLine.includes('Received request')) {
            log(`\n${index + 1}. 📥 ${logLine}`, 'green');
          } else if (logLine.includes('Successfully') || logLine.includes('✅')) {
            log(`${index + 1}. ✅ ${logLine}`, 'green');
          } else if (logLine.includes('Error') || logLine.includes('❌')) {
            log(`${index + 1}. ❌ ${logLine}`, 'red');
          } else {
            log(`${index + 1}. 🔍 ${logLine}`, 'cyan');
          }
        });
        log('\n💡 If you see "Received request" logs, like requests ARE reaching the backend!', 'green');
      } else {
        log('⚠️  No like-related logs found in log file', 'yellow');
        log('💡 Check your backend console directly for like requests', 'yellow');
      }
    } catch (error) {
      log(`❌ Error reading log file: ${error.message}`, 'red');
    }
  } else {
    log(`⚠️  Log file not found: ${logFile}`, 'yellow');
    log('💡 Check your backend console directly', 'yellow');
  }

  // Method 3: Instructions
  logSection('📋 METHOD 3: Real-Time Testing Instructions');
  
  log('To check if like requests are reaching the backend in real-time:', 'blue');
  log('\n1. Open your Flutter app', 'yellow');
  log('2. Click the like button on any video', 'yellow');
  log('3. Check your backend console/terminal for:', 'yellow');
  log('   🔍 Like API: Received request { googleId: "...", videoId: "..." }', 'cyan');
  log('   ✅ Like API: Successfully toggled like', 'green');
  log('\n4. Or run the monitor script:', 'yellow');
  log('   npm run monitor:likes', 'cyan');
  log('\n5. Or check Flutter logs for:', 'yellow');
  log('   🔍 VideoService: Like request URL: ...', 'cyan');
  log('   📡 VideoService: Like response status: 200', 'green');

  logSection('🧪 METHOD 4: Test with Script');
  
  log('To test the like endpoint directly:', 'blue');
  log('\n1. Get a video ID:', 'yellow');
  log('   npm run get:video:id', 'cyan');
  log('\n2. Get your JWT token from Flutter app logs', 'yellow');
  log('\n3. Run the test:', 'yellow');
  log('   npm run test:like <videoId> <jwtToken>', 'cyan');
  
  logSection('✅ SUMMARY');
  log('If you see:', 'blue');
  log('  ✅ "Received request" in backend logs → Requests ARE reaching backend', 'green');
  log('  ✅ Recent database updates → Requests ARE being processed', 'green');
  log('  ✅ Status 200 in Flutter logs → Requests ARE successful', 'green');
  log('\nIf you DON\'T see:', 'blue');
  log('  ❌ No "Received request" → Requests NOT reaching backend', 'red');
  log('  ❌ No database updates → Requests NOT being processed', 'red');
  log('  ❌ Error status codes → Check authentication/network', 'red');
  
  log('\n💡 TIP: Keep the monitor script running while testing:', 'blue');
  log('   npm run monitor:likes', 'cyan');
}

checkLikeRequests()
  .then(() => {
    log('\n✅ Check completed', 'green');
    process.exit(0);
  })
  .catch((error) => {
    log(`\n❌ Check failed: ${error.message}`, 'red');
    process.exit(1);
  });

