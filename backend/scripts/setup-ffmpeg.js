import { spawn } from 'child_process';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

console.log('🔧 Setting up FFmpeg for video processing...');

// Check if FFmpeg is installed
function checkFFmpeg() {
  return new Promise((resolve) => {
    const ffmpeg = spawn('ffmpeg', ['-version']);
    
    ffmpeg.on('close', (code) => {
      if (code === 0) {
        console.log('✅ FFmpeg is already installed');
        resolve(true);
      } else {
        console.log('❌ FFmpeg not found');
        resolve(false);
      }
    });
    
    ffmpeg.on('error', () => {
      console.log('❌ FFmpeg not found');
      resolve(false);
    });
  });
}

// Check if ffprobe is installed
function checkFFprobe() {
  return new Promise((resolve) => {
    const ffprobe = spawn('ffprobe', ['-version']);
    
    ffprobe.on('close', (code) => {
      if (code === 0) {
        console.log('✅ FFprobe is already installed');
        resolve(true);
      } else {
        console.log('❌ FFprobe not found');
        resolve(false);
      }
    });
    
    ffprobe.on('error', () => {
      console.log('❌ FFprobe not found');
      resolve(false);
    });
  });
}

// Create necessary directories
function createDirectories() {
  const directories = [
    path.join(__dirname, '../uploads/processed'),
    path.join(__dirname, '../uploads/hls'),
    path.join(__dirname, '../uploads/temp')
  ];
  
  directories.forEach(dir => {
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
      console.log(`📁 Created directory: ${dir}`);
    } else {
      console.log(`📁 Directory exists: ${dir}`);
    }
  });
}

// Main setup function
async function setup() {
  console.log('🚀 Starting FFmpeg setup...');
  
  // Check FFmpeg installation
  const ffmpegInstalled = await checkFFmpeg();
  const ffprobeInstalled = await checkFFprobe();
  
  if (!ffmpegInstalled || !ffprobeInstalled) {
    console.log('\n❌ FFmpeg installation required!');
    console.log('\n📋 Installation instructions:');
    console.log('\n🪟 Windows:');
    console.log('   1. Download FFmpeg from: https://ffmpeg.org/download.html');
    console.log('   2. Extract to C:\\ffmpeg');
    console.log('   3. Add C:\\ffmpeg\\bin to PATH environment variable');
    console.log('   4. Restart terminal and run: ffmpeg -version');
    
    console.log('\n🐧 Linux (Ubuntu/Debian):');
    console.log('   sudo apt update');
    console.log('   sudo apt install ffmpeg');
    
    console.log('\n🍎 macOS:');
    console.log('   brew install ffmpeg');
    
    console.log('\n🔗 Alternative: Use package manager');
    console.log('   npm install -g ffmpeg-static');
    
    process.exit(1);
  }
  
  // Create directories
  createDirectories();
  
  console.log('\n✅ FFmpeg setup completed successfully!');
  console.log('🎬 Video processing is now ready');
  console.log('💰 Cost savings: 100% (no external processing costs)');
}

// Run setup
setup().catch(error => {
  console.error('❌ Setup failed:', error);
  process.exit(1);
});
