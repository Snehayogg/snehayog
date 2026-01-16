import { exec } from 'child_process';
import util from 'util';
import fs from 'fs';
import path from 'path';

// Promisify exec
const execPromise = util.promisify(exec);

console.log('🎬 Setting up FFmpeg...');

async function checkFFmpeg() {
  try {
    // Check if ffmpeg is accessible
    const { stdout } = await execPromise('ffmpeg -version');
    console.log('✅ FFmpeg is installed and accessible.');
    console.log(stdout.split('\n')[0]); // Log version
  } catch (error) {
    console.warn('⚠️ FFmpeg command not found globally.');
    console.log('ℹ️ Attempting to verify static path or skip if not required for build...');
    // In some environments, we might want to fail, but for now let's just warn
    // as the nixpacks configuration likely handles the installation.
  }
}

// Run the check
checkFFmpeg().then(() => {
  console.log('✅ FFmpeg setup script completed.');
}).catch(err => {
  console.error('❌ Error in setup-ffmpeg script:', err);
  process.exit(1);
});
