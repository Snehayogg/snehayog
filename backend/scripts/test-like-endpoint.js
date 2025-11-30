#!/usr/bin/env node

/**
 * LIKE ENDPOINT TEST SCRIPT
 * 
 * This script tests the like endpoint to verify:
 * 1. If requests are reaching the backend
 * 2. If authentication is working
 * 3. If the database is being updated correctly
 * 
 * Usage:
 *   node scripts/test-like-endpoint.js <videoId> <jwtToken>
 * 
 * Example:
 *   node scripts/test-like-endpoint.js 507f1f77bcf86cd799439011 eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
 */

import dotenv from 'dotenv';
import axios from 'axios';
import { fileURLToPath } from 'url';
import { dirname, join } from 'path';

// Load environment variables
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);
dotenv.config({ path: join(__dirname, '../.env') });

// Configuration
const BASE_URL = process.env.BACKEND_URL || process.env.RAILWAY_PUBLIC_DOMAIN || 'http://localhost:5001';
const API_URL = `${BASE_URL}/api/videos`;

// Colors for console output
const colors = {
  reset: '\x1b[0m',
  bright: '\x1b[1m',
  red: '\x1b[31m',
  green: '\x1b[32m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  cyan: '\x1b[36m',
};

function log(message, color = 'reset') {
  console.log(`${colors[color]}${message}${colors.reset}`);
}

function logSection(title) {
  console.log('\n' + '='.repeat(60));
  log(title, 'cyan');
  console.log('='.repeat(60));
}

async function testLikeEndpoint(videoId, jwtToken) {
  logSection('🧪 LIKE ENDPOINT TEST SCRIPT');
  
  log(`📍 Base URL: ${BASE_URL}`, 'blue');
  log(`📍 API Endpoint: ${API_URL}/${videoId}/like`, 'blue');
  log(`📍 Video ID: ${videoId}`, 'blue');
  log(`📍 Token: ${jwtToken ? jwtToken.substring(0, 20) + '...' : 'NOT PROVIDED'}`, 'blue');
  
  if (!videoId) {
    log('❌ Error: Video ID is required', 'red');
    log('Usage: node scripts/test-like-endpoint.js <videoId> <jwtToken>', 'yellow');
    process.exit(1);
  }

  if (!jwtToken) {
    log('⚠️  Warning: No JWT token provided. Request will likely fail with 401', 'yellow');
    log('Usage: node scripts/test-like-endpoint.js <videoId> <jwtToken>', 'yellow');
  }

  const endpoint = `${API_URL}/${videoId}/like`;
  
  logSection('📤 STEP 1: Sending LIKE Request');
  log(`POST ${endpoint}`, 'bright');
  
  try {
    const startTime = Date.now();
    
    const response = await axios.post(
      endpoint,
      {},
      {
        headers: {
          'Authorization': `Bearer ${jwtToken || ''}`,
          'Content-Type': 'application/json',
        },
        timeout: 15000,
        validateStatus: () => true, // Don't throw on any status
      }
    );
    
    const duration = Date.now() - startTime;
    
    logSection('📥 STEP 2: Response Received');
    log(`Status Code: ${response.status}`, response.status === 200 ? 'green' : 'red');
    log(`Response Time: ${duration}ms`, 'blue');
    log(`Response Headers:`, 'blue');
    console.log(JSON.stringify(response.headers, null, 2));
    
    logSection('📄 STEP 3: Response Body');
    if (response.data) {
      try {
        const data = response.data;
        log('✅ Response parsed successfully', 'green');
        console.log('\nResponse Data:');
        console.log(JSON.stringify(data, null, 2));
        
        // Extract key information
        if (data._id) {
          log(`\n📊 Video ID: ${data._id}`, 'cyan');
        }
        if (data.likes !== undefined) {
          log(`📊 Likes Count: ${data.likes}`, 'cyan');
        }
        if (data.likedBy && Array.isArray(data.likedBy)) {
          log(`📊 Liked By Count: ${data.likedBy.length}`, 'cyan');
          
          // Check if counts match
          if (data.likes !== data.likedBy.length) {
            log(`⚠️  WARNING: Likes count (${data.likes}) doesn't match likedBy length (${data.likedBy.length})!`, 'yellow');
          } else {
            log(`✅ Likes count matches likedBy length`, 'green');
          }
        }
        if (data.videoName) {
          log(`📊 Video Name: ${data.videoName}`, 'cyan');
        }
      } catch (e) {
        log(`❌ Error parsing response: ${e.message}`, 'red');
        log(`Raw response: ${response.data}`, 'yellow');
      }
    } else {
      log('⚠️  No response body', 'yellow');
    }
    
    // Analyze response
    logSection('🔍 STEP 4: Analysis');
    
    if (response.status === 200) {
      log('✅ SUCCESS: Like request was processed successfully!', 'green');
      log('✅ The backend received and processed your like request', 'green');
      
      if (response.data && response.data.likes !== undefined) {
        log(`✅ Database was updated. New likes count: ${response.data.likes}`, 'green');
      }
    } else if (response.status === 401 || response.status === 403) {
      log('❌ AUTHENTICATION ERROR: Invalid or missing token', 'red');
      log('💡 Solution: Get a valid JWT token from your app', 'yellow');
    } else if (response.status === 404) {
      log('❌ NOT FOUND: Video or user not found', 'red');
      log(`💡 Check if video ID "${videoId}" exists in the database`, 'yellow');
    } else if (response.status === 400) {
      log('❌ BAD REQUEST: Invalid request parameters', 'red');
      if (response.data && response.data.error) {
        log(`Error: ${response.data.error}`, 'yellow');
      }
    } else if (response.status === 500) {
      log('❌ SERVER ERROR: Backend encountered an error', 'red');
      if (response.data && response.data.error) {
        log(`Error: ${response.data.error}`, 'yellow');
      }
      if (response.data && response.data.stack) {
        log(`Stack trace: ${response.data.stack}`, 'yellow');
      }
    } else {
      log(`❌ UNEXPECTED STATUS: ${response.status}`, 'red');
    }
    
    // Network connectivity check
    if (response.status === 0 || !response.status) {
      log('❌ NETWORK ERROR: Could not reach the backend', 'red');
      log(`💡 Check if backend is running at: ${BASE_URL}`, 'yellow');
      log(`💡 Check your network connection`, 'yellow');
    }
    
  } catch (error) {
    logSection('❌ ERROR OCCURRED');
    
    if (error.code === 'ECONNREFUSED') {
      log('❌ CONNECTION REFUSED: Backend is not running or not accessible', 'red');
      log(`💡 Check if backend is running at: ${BASE_URL}`, 'yellow');
    } else if (error.code === 'ETIMEDOUT') {
      log('❌ TIMEOUT: Request took too long', 'red');
      log('💡 Backend might be slow or unresponsive', 'yellow');
    } else if (error.code === 'ENOTFOUND') {
      log('❌ DNS ERROR: Could not resolve backend URL', 'red');
      log(`💡 Check if ${BASE_URL} is correct`, 'yellow');
    } else if (error.response) {
      log(`❌ HTTP ERROR: ${error.response.status}`, 'red');
      log(`Response: ${JSON.stringify(error.response.data, null, 2)}`, 'yellow');
    } else {
      log(`❌ ERROR: ${error.message}`, 'red');
      log(`Stack: ${error.stack}`, 'yellow');
    }
  }
  
  logSection('📋 TEST SUMMARY');
  log('To test from your Flutter app:', 'cyan');
  log('1. Check Flutter logs for "VideoService: Like request URL"', 'yellow');
  log('2. Check Flutter logs for "VideoService: Like response status"', 'yellow');
  log('3. Check backend logs for "Like API: Received request"', 'yellow');
  log('4. Run this script with the same videoId and token', 'yellow');
  log('\nTo monitor backend logs in real-time:', 'cyan');
  log('Run: tail -f logs/app.log (or check your backend console)', 'yellow');
}

// Get command line arguments
const args = process.argv.slice(2);
const videoId = args[0];
const jwtToken = args[1];

// Run the test
testLikeEndpoint(videoId, jwtToken)
  .then(() => {
    log('\n✅ Test completed', 'green');
    process.exit(0);
  })
  .catch((error) => {
    log(`\n❌ Test failed: ${error.message}`, 'red');
    process.exit(1);
  });

