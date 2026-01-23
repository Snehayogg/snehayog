import ffmpeg from 'fluent-ffmpeg';
import ffmpegPath from 'ffmpeg-static';
import ffprobePath from 'ffprobe-static';
import fs from 'fs';

// Configure fluent-ffmpeg to use static binaries
// This ensures we use the project-local binaries instead of relying on system installation
if (ffmpegPath) {
  ffmpeg.setFfmpegPath(ffmpegPath);
} else {
  console.warn('⚠️ ffmpeg-static did not return a path. FFmpeg might not work if not in system PATH.');
}

if (ffprobePath && ffprobePath.path) {
  ffmpeg.setFfprobePath(ffprobePath.path);
} else {
  console.warn('⚠️ ffprobe-static did not return a path. Metadata extraction might fail.');
}

console.log('🎥 VideoMetadataService: Initialized');
console.log('   FFmpeg binary:', ffmpegPath || 'System default');
console.log('   FFprobe binary:', ffprobePath?.path || 'System default');

/**
 * Get metadata for a video file using ffprobe
 * @param {string} filePath - Absolute path to the video file
 * @returns {Promise<Object>} - Video metadata (width, height, duration, etc.)
 */
export const getVideoMetadata = (filePath) => {
  return new Promise((resolve, reject) => {
    // 1. Basic validation
    if (!filePath) {
      return reject(new Error('File path is required'));
    }

    if (!fs.existsSync(filePath)) {
      return reject(new Error(`File not found: ${filePath}`));
    }

    // 2. Run ffprobe
    ffmpeg.ffprobe(filePath, (err, metadata) => {
      if (err) {
        console.error(`❌ FFprobe error for ${filePath}:`, err.message);
        return reject(new Error(`Failed to read video metadata: ${err.message}`));
      }

      try {
        // 3. Extract relevant video stream
        const videoStream = metadata.streams.find(s => s.codec_type === 'video');
        
        if (!videoStream) {
          return reject(new Error('No video stream found in the file'));
        }

        // 4. Parse values safely
        const width = parseInt(videoStream.width, 10) || 0;
        const height = parseInt(videoStream.height, 10) || 0;
        const duration = parseFloat(metadata.format.duration) || parseFloat(videoStream.duration) || 0;
        const size = parseInt(metadata.format.size, 10) || 0;
        
        // Calculate aspect ratio
        let aspectRatio = 9/16; // Default
        if (width > 0 && height > 0) {
          aspectRatio = width / height;
        }

        const result = {
          width,
          height,
          duration,
          size, 
          aspectRatio,
          codec: videoStream.codec_name || 'unknown',
          format: metadata.format.format_name || 'unknown',
          isPortrait: aspectRatio < 1.0,
          isLandscape: aspectRatio >= 1.0,
          // Include raw metadata if needed for advanced debugging
          // raw: metadata 
        };

        // console.log('📊 Extracted Metadata:', JSON.stringify(result, null, 2));
        resolve(result);

      } catch (parseError) {
        console.error('❌ Metadata parsing error:', parseError);
        reject(new Error('Failed to parse video metadata'));
      }
    });
  });
};

export default {
  getVideoMetadata
};
