#!/usr/bin/env node

/**
 * FFmpeg Setup Script for Railway Deployment
 * This script ensures FFmpeg is available for video processing
 */

import { exec } from 'child_process';
import { promisify } from 'util';
import fs from 'fs';
import path from 'path';

const execAsync = promisify(exec);

console.log('🔧 FFmpeg Setup Script Starting...');

async function checkFFmpeg() {
  try {
    const { stdout } = await execAsync('ffmpeg -version');
    console.log('✅ FFmpeg is already installed');
    console.log('📋 FFmpeg version info:');
    console.log(stdout.split('\n')[0]); // First line contains version
    return true;
  } catch (error) {
    console.log('❌ FFmpeg not found:', error.message);
    return false;
  }
}

async function installFFmpeg() {
  console.log('📦 Attempting to install FFmpeg...');
  
  try {
    // Try different package managers based on the system
    console.log('🔍 Checking system package manager...');
    
    // Check if we're on Ubuntu/Debian
    try {
      await execAsync('which apt-get');
      console.log('🐧 Detected Ubuntu/Debian system');
      console.log('📦 Installing FFmpeg via apt-get...');
      await execAsync('apt-get update && apt-get install -y ffmpeg');
      console.log('✅ FFmpeg installed successfully via apt-get');
      return true;
    } catch (aptError) {
      console.log('❌ apt-get not available:', aptError.message);
    }

    // Check if we're on Alpine (Railway often uses Alpine)
    try {
      await execAsync('which apk');
      console.log('🏔️ Detected Alpine system');
      console.log('📦 Installing FFmpeg via apk...');
      await execAsync('apk add --no-cache ffmpeg');
      console.log('✅ FFmpeg installed successfully via apk');
      return true;
    } catch (apkError) {
      console.log('❌ apk not available:', apkError.message);
    }

    // Check if we're on CentOS/RHEL
    try {
      await execAsync('which yum');
      console.log('🎩 Detected CentOS/RHEL system');
      console.log('📦 Installing FFmpeg via yum...');
      await execAsync('yum install -y ffmpeg');
      console.log('✅ FFmpeg installed successfully via yum');
      return true;
    } catch (yumError) {
      console.log('❌ yum not available:', yumError.message);
    }

    console.log('❌ No suitable package manager found');
    return false;
  } catch (error) {
    console.error('❌ Error installing FFmpeg:', error.message);
    return false;
  }
}

async function verifyFFmpeg() {
  console.log('🔍 Verifying FFmpeg installation...');
  
  try {
    const { stdout } = await execAsync('ffmpeg -version');
    console.log('✅ FFmpeg verification successful');
    console.log('📋 FFmpeg details:');
    const lines = stdout.split('\n');
    lines.slice(0, 3).forEach(line => {
      if (line.trim()) console.log('   ', line.trim());
    });
    
    // Test basic FFmpeg functionality
    console.log('🧪 Testing FFmpeg functionality...');
    await execAsync('ffmpeg -f lavfi -i testsrc=duration=1:size=320x240:rate=1 -t 1 /tmp/test.mp4');
    console.log('✅ FFmpeg functionality test passed');
    
    // Clean up test file
    try {
      fs.unlinkSync('/tmp/test.mp4');
    } catch (cleanupError) {
      // Ignore cleanup errors
    }
    
    return true;
  } catch (error) {
    console.error('❌ FFmpeg verification failed:', error.message);
    return false;
  }
}

async function main() {
  console.log('🚀 Starting FFmpeg setup process...');
  
  // Check if FFmpeg is already installed
  const isInstalled = await checkFFmpeg();
  
  if (isInstalled) {
    console.log('✅ FFmpeg setup complete - already installed');
    process.exit(0);
  }
  
  // Try to install FFmpeg
  const installSuccess = await installFFmpeg();
  
  if (!installSuccess) {
    console.error('❌ FFmpeg installation failed');
    console.log('💡 Manual installation may be required');
    console.log('📖 Please ensure FFmpeg is available in your deployment environment');
    process.exit(1);
  }
  
  // Verify the installation
  const verifySuccess = await verifyFFmpeg();
  
  if (verifySuccess) {
    console.log('🎉 FFmpeg setup completed successfully!');
    console.log('✅ Video processing should now work properly');
    process.exit(0);
  } else {
    console.error('❌ FFmpeg setup failed verification');
    process.exit(1);
  }
}

// Run the setup
main().catch(error => {
  console.error('💥 FFmpeg setup script crashed:', error);
  process.exit(1);
});
