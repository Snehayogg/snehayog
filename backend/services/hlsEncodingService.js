import ffmpeg from 'fluent-ffmpeg';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import { spawnSync } from 'child_process';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// **FIX: Robust FFmpeg Path Selection**
// 1. Try system-installed FFmpeg (from Nixpacks/apt)
// 2. Fallback to static binaries (npm packages)

let ffmpegPath = null;
let ffprobePath = null;

try {
  // Check system FFmpeg
  const systemFfmpeg = spawnSync('which', ['ffmpeg']);
  if (systemFfmpeg.status === 0 && systemFfmpeg.stdout.toString().trim()) {
      ffmpegPath = systemFfmpeg.stdout.toString().trim();
      console.log('🔧 HLSEncodingService: Found system FFmpeg at:', ffmpegPath);
  }

  // Check system FFprobe
  const systemFfprobe = spawnSync('which', ['ffprobe']);
  if (systemFfprobe.status === 0 && systemFfprobe.stdout.toString().trim()) {
      ffprobePath = systemFfprobe.stdout.toString().trim();
      console.log('🔧 HLSEncodingService: Found system FFprobe at:', ffprobePath);
  }
} catch (e) {
  console.log('⚠️ HLSEncodingService: Failed to check system paths:', e.message);
}

// Fallback to static if system not found
if (!ffmpegPath) {
  try {
      const ffmpegStatic = (await import('ffmpeg-static')).default;
      ffmpegPath = ffmpegStatic;
      console.log('🔧 HLSEncodingService: Using static FFmpeg at:', ffmpegPath);
  } catch (e) {
      console.error('❌ HLSEncodingService: Failed to load ffmpeg-static:', e);
  }
}

if (!ffprobePath) {
  try {
      const ffprobeStatic = (await import('ffprobe-static')).default;
      ffprobePath = ffprobeStatic.path;
      console.log('🔧 HLSEncodingService: Using static FFprobe at:', ffprobePath);
  } catch (e) {
       console.error('❌ HLSEncodingService: Failed to load ffprobe-static:', e);
  }
}

// Set paths
if (ffmpegPath) ffmpeg.setFfmpegPath(ffmpegPath);
if (ffprobePath) ffmpeg.setFfprobePath(ffprobePath);

console.log('🔧 HLSEncodingService: Final Configuration');
console.log('   FFmpeg:', ffmpegPath || '❌ NOT FOUND');
console.log('   FFprobe:', ffprobePath || '❌ NOT FOUND');


class HLSEncodingService {
  constructor() {
    // Ensure HLS output directory exists
    this.hlsOutputDir = path.join(__dirname, '../uploads/hls');
    this.ensureHLSDirectory();
    
    // Check FFmpeg installation
    this.checkFFmpegInstallation().then(isInstalled => {
      if (!isInstalled) {
        console.warn('⚠️ FFmpeg not found. HLS encoding will not work.');
        console.warn('   Please install FFmpeg: https://ffmpeg.org/download.html');
      }
    });
  }

  ensureHLSDirectory() {
    if (!fs.existsSync(this.hlsOutputDir)) {
      fs.mkdirSync(this.hlsOutputDir, { recursive: true });
    }
  }

  /**
   * Convert video to HLS format (SINGLE 480p quality only)
   * @param {string} inputPath - Path to input video file
   * @param {string} videoId - Unique video identifier
   * @param {Object} options - Encoding options
   * @param {number} options.segmentDuration - Segment duration in seconds (default: 3)
   * @param {string} options.quality - Quality preset: low, medium, high (default: medium)
   * @param {string} options.resolution - Resolution (only 480p supported, default: 480p)
   * @returns {Promise<Object>} - HLS encoding result
   */
  async convertToHLS(inputPath, videoId, options = {}) {
    const {
      segmentDuration = 3, // Optimized segment duration: 3 seconds for fast startup
      quality = 'medium', // low, medium, high (medium = 480p optimal)
      resolution = '480p' // Fixed to 480p for cost optimization (single quality only)
    } = options;

    return new Promise((resolve, reject) => {
      // **FIXED: Use proper video ID instead of temporary names**
      const cleanVideoId = videoId.replace(/[^a-zA-Z0-9_-]/g, '_');
      const outputDir = path.join(this.hlsOutputDir, cleanVideoId);
      const playlistPath = path.join(outputDir, 'playlist.m3u8');
      
      // Create output directory
      if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
      }

      // Quality presets optimized for HLS streaming (480p only)
      const qualityPresets = {
        low: { crf: 28, audioBitrate: '48k' },    // Lower quality, smaller file
        medium: { crf: 26, audioBitrate: '64k' }, // Balanced for mobile data (approx 480p)
        high: { crf: 23, audioBitrate: '128k' }   // Higher quality
      };

      // **FIX: Use original resolution instead of fixed 480p**
      // Calculate bitrate based on original resolution for better quality
      const originalVideoInfo = options.originalVideoInfo;
      let selectedResolution;
      let targetBitrate = '800k'; // Default bitrate
      
      if (originalVideoInfo && originalVideoInfo.width && originalVideoInfo.height) {
        const originalWidth = originalVideoInfo.width;
        const originalHeight = originalVideoInfo.height;
        
        // Calculate bitrate based on resolution (higher resolution = higher bitrate)
        if (originalHeight > 1080) {
          targetBitrate = '3000k'; // 1080p+ (Reduced from 5000k)
        } else if (originalHeight > 720) {
          targetBitrate = '1500k'; // 720p-1080p (Reduced from 3000k)
        } else if (originalHeight > 480) {
          targetBitrate = '900k'; // 480p-720p (Reduced from 1500k)
        } else {
          targetBitrate = '550k'; // Below 480p (Targeting ~3MB per minute)
        }
        
        selectedResolution = {
          width: originalWidth,
          height: originalHeight,
          bitrate: targetBitrate
        };
      } else {
        // Fallback to 480p if original info not available
        targetBitrate = '800k';
        selectedResolution = { width: 854, height: 480, bitrate: targetBitrate };
      }
      
      const selectedQuality = qualityPresets[quality] || qualityPresets.medium;
      
      console.log('🎬 HLS Encoding Configuration:');
      console.log(`   Quality: ${quality} (CRF: ${selectedQuality.crf})`);
      console.log(`   Resolution: ${selectedResolution.width}x${selectedResolution.height} (original preserved)`);
      console.log(`   Bitrate: ${selectedResolution.bitrate}`);
      console.log(`   Segment Duration: ${segmentDuration}s`);

      let command = ffmpeg(inputPath)
        .inputOptions([
          '-y', // Overwrite output files
          '-hide_banner',
          '-loglevel error'
        ])
        .outputOptions([
          // Video codec settings - optimized for HLS
          '-c:v', 'libx264',
          '-preset', 'fast',           // Fast encoding for production
          '-profile:v', 'baseline',    // Baseline profile for maximum compatibility
          '-level', '3.1',             // H.264 level for broad device support
          '-crf', selectedQuality.crf.toString(),
          '-maxrate', targetBitrate, // Bitrate constraint based on resolution
          '-bufsize', `${parseInt(targetBitrate) * 2}k`, // Buffer size (2x bitrate)
          '-sc_threshold', '0',        // Disable scene change detection
          '-g', '48',                  // GOP size for 3-second segments
          '-keyint_min', '48',         // Minimum keyframe interval
          '-force_key_frames', 'expr:gte(t,n_forced*3)', // Force keyframes every 3 seconds
          
          // Audio codec settings
          '-c:a', 'aac',
          '-b:a', selectedQuality.audioBitrate,
          '-ac', '2',                  // Stereo audio
          '-ar', '44100',              // 44.1kHz sample rate
          
          // HLS specific settings - optimized for fast startup
          '-f', 'hls',
          '-hls_time', segmentDuration.toString(),
          '-hls_list_size', '0',       // Keep all segments
          '-hls_segment_filename', path.join(outputDir, 'segment_%03d.ts'),
          '-hls_playlist_type', 'vod', // Video on demand
          '-hls_flags', 'independent_segments+delete_segments', // Better segment management
          '-hls_segment_type', 'mpegts', // MPEG-TS segments for compatibility
          
          // Additional optimizations
          '-movflags', '+faststart',   // Optimize for streaming
          '-pix_fmt', 'yuv420p'       // Pixel format for maximum compatibility
        ]);

      // **FIX: Preserve original resolution - encode at original dimensions**
      // Only scale down if video is extremely large (optional optimization for very large files)
      // For most videos, keep original resolution (1080x1920, etc.)
      const originalVideoInfoForScaling = options.originalVideoInfo;
      
      if (originalVideoInfoForScaling && originalVideoInfoForScaling.width && originalVideoInfoForScaling.height) {
        const originalWidth = originalVideoInfoForScaling.width;
        const originalHeight = originalVideoInfoForScaling.height;
        
        console.log(`📐 Original video dimensions: ${originalWidth}x${originalHeight}`);
        
        // Only scale down if video is larger than 1080p (optional optimization)
        // This preserves original resolution for most videos (1080x1920, 720x1280, etc.)
        if (originalHeight > 1080) {
          console.log(`📐 Video is larger than 1080p, scaling down to 1080p while preserving aspect ratio`);
          command = command
            .videoFilters(`scale=-2:1080:force_original_aspect_ratio=decrease`);
        } else {
          console.log(`📐 Preserving original resolution: ${originalWidth}x${originalHeight}`);
          // No scaling - encode at original resolution
          // FFmpeg will encode at original dimensions automatically
        }
      } else {
        // Fallback: If original info not available, use original video dimensions
        console.log(`📐 Original video info not available, encoding at original resolution`);
        // No scaling filter - FFmpeg will use original dimensions
      }
      
      // **REMOVED: .size() call that was forcing fixed dimensions**
      // We don't set .size() to allow FFmpeg to maintain the original resolution

      // Add output
      command = command.output(playlistPath);

      // Handle progress
      command.on('progress', (progress) => {
        console.log(`HLS Encoding Progress for ${videoId}: ${progress.percent}% done`);
      });

      // Handle completion
      command.on('end', () => {
        console.log(`HLS encoding completed for ${videoId}`);
        
        // Read playlist content to verify and validate
        try {
          const playlistContent = fs.readFileSync(playlistPath, 'utf8');
          const segments = fs.readdirSync(outputDir).filter(file => file.endsWith('.ts'));
          
          // Validate playlist content
          if (!playlistContent.includes('#EXTM3U')) {
            throw new Error('Invalid HLS playlist format - missing #EXTM3U header');
          }
          
          if (segments.length === 0) {
            throw new Error('No video segments found in HLS output');
          }
          
          console.log(`✅ HLS validation passed for ${videoId}: ${segments.length} segments, playlist size: ${playlistContent.length} bytes`);
          
          resolve({
            success: true,
            playlistPath,
            playlistUrl: `/uploads/hls/${cleanVideoId}/playlist.m3u8`,
            segments: segments.length,
            outputDir,
            segmentDuration,
            quality,
            resolution: selectedResolution || 'auto'
          });
        } catch (error) {
          reject(new Error(`Failed to read HLS output: ${error.message}`));
        }
      });

      // Handle errors
      command.on('error', (error) => {
        console.error(`HLS encoding error for ${videoId}:`, error);
        reject(new Error(`HLS encoding failed: ${error.message}`));
      });

      // Start encoding
      command.run();
    });
  }

  // Add this method to the HLSEncodingService class

async checkFFmpegInstallation() {
  return new Promise((resolve) => {
    ffmpeg.getAvailableCodecs((err, codecs) => {
      if (err) {
        console.error('❌ FFmpeg not properly installed:', err.message);
        resolve(false);
      } else {
        console.log('✅ FFmpeg is properly installed and working');
        resolve(true);
      }
    });
  });
}



  /**
   * Generate multiple quality variants for adaptive streaming
   * @param {string} inputPath - Path to input video file
   * @param {string} videoId - Unique video identifier
   * @returns {Promise<Object>} - Multi-quality HLS result
   */
  async generateAdaptiveHLS(inputPath, videoId) {
    // **FIXED: Use proper video ID instead of temporary names**
    const cleanVideoId = videoId.replace(/[^a-zA-Z0-9_-]/g, '_');
    const outputDir = path.join(this.hlsOutputDir, cleanVideoId);
    const masterPlaylistPath = path.join(outputDir, 'master.m3u8');
    
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }

    // Quality variants optimized for INSTANT loading and fast startup
    // Segment duration: 2 seconds for fastest possible startup
    // CRF ~20 for better quality, ultrafast preset for speed
    // **UPDATED: 9:16 aspect ratio for reels-style full screen videos**
    const variants = [
      { 
        name: '720p', 
        crf: 24, 
        width: 720, 
        height: 1280, // 9:16 aspect ratio
        audioBitrate: '96k', 
        targetBitrate: '1200k',
        segmentDuration: 2 // 2 seconds for instant startup
      },
      { 
        name: '480p', 
        crf: 26, 
        width: 480, 
        height: 854, // 9:16 aspect ratio
        audioBitrate: '64k', 
        targetBitrate: '550k',
        segmentDuration: 2
      },
      { 
        name: '360p', 
        crf: 28, 
        width: 360, 
        height: 640, // 9:16 aspect ratio
        audioBitrate: '48k', 
        targetBitrate: '350k',
        segmentDuration: 2
      },
      { 
        name: '240p', 
        crf: 30, 
        width: 240, 
        height: 426, // 9:16 aspect ratio
        audioBitrate: '32k', 
        targetBitrate: '150k',
        segmentDuration: 2
      }
    ];

    const promises = [];

    // Generate each quality variant
    for (const variant of variants) {
      const variantDir = path.join(outputDir, variant.name);
      if (!fs.existsSync(variantDir)) {
        fs.mkdirSync(variantDir, { recursive: true });
      }

      const promise = this.encodeVariant(inputPath, variantDir, variant, variant.segmentDuration, videoId);
      promises.push(promise);
    }

    try {
      const results = await Promise.all(promises);
      
      // Generate master playlist
      const masterPlaylist = this.generateMasterPlaylist(results, variants[0].segmentDuration);
      fs.writeFileSync(masterPlaylistPath, masterPlaylist);

      return {
        success: true,
        masterPlaylistPath,
        masterPlaylistUrl: `/uploads/hls/${cleanVideoId}/master.m3u8`,
        variants: results,
        segmentDuration: variants[0].segmentDuration,
        qualityRange: `${variants[0].name} to ${variants[variants.length - 1].name}`
      };
    } catch (error) {
      throw new Error(`Adaptive HLS generation failed: ${error.message}`);
    }
  }

  /**
   * Encode a single quality variant
   */
  async encodeVariant(inputPath, outputDir, variant, segmentDuration, videoId) {
    return new Promise((resolve, reject) => {
      const playlistPath = path.join(outputDir, 'playlist.m3u8');
      // **FIXED: Use proper video ID instead of temporary names**
      const cleanVideoId = videoId.replace(/[^a-zA-Z0-9_-]/g, '_');
      
      console.log(`🎬 Encoding variant ${variant.name} for video ${videoId}`);
      console.log(`📁 Input: ${inputPath}`);
      console.log(`📁 Output: ${playlistPath}`);
      console.log(`⚙️ Settings: ${variant.width}x${variant.height}, ${variant.targetBitrate}`);
      
      ffmpeg(inputPath)
        .inputOptions(['-y', '-hide_banner', '-loglevel error'])
        .outputOptions([
          // Video codec settings - simplified for reliability
          '-c:v', 'libx264',
          '-preset', 'fast',           // Fast preset for better compatibility
          '-profile:v', 'baseline',    // Baseline profile for maximum compatibility
          '-level', '3.0',             // H.264 level for broad device support
          '-crf', variant.crf.toString(),
          '-maxrate', variant.targetBitrate,
          '-bufsize', `${parseInt(variant.targetBitrate) * 2}k`,
          
          // Audio codec settings
          '-c:a', 'aac',
          '-b:a', variant.audioBitrate,
          '-ac', '2',
          '-ar', '44100',
          
          '-f', 'hls',
          '-hls_time', segmentDuration.toString(),
          '-hls_list_size', '0',
          '-hls_segment_filename', path.join(outputDir, 'segment_%03d.ts'),
          '-hls_playlist_type', 'vod',
          '-hls_flags', 'independent_segments',
          '-hls_segment_type', 'mpegts',
          
          // Basic optimizations
          '-pix_fmt', 'yuv420p'
        ])
        // Respect original aspect; pad if required to target dimensions
        .videoFilters(`scale='min(${variant.width},iw)':-2:force_original_aspect_ratio=decrease,pad=${variant.width}:${variant.height}:(ow-iw)/2:(oh-ih)/2:black`)
        .size(`${variant.width}x${variant.height}`)
        .output(playlistPath)
        .on('start', (commandLine) => {
          console.log(`🚀 FFmpeg command: ${commandLine}`);
        })
        .on('progress', (progress) => {
          console.log(`📊 ${variant.name} encoding progress: ${progress.percent}%`);
        })
        .on('end', () => {
          console.log(`✅ ${variant.name} encoding completed`);
          try {
            const segments = fs.readdirSync(outputDir).filter(file => file.endsWith('.ts'));
            resolve({
              name: variant.name,
              playlistPath,
              playlistUrl: `/uploads/hls/${cleanVideoId}/${variant.name}/playlist.m3u8`,
              segments: segments.length,
              resolution: `${variant.width}x${variant.height}`,
              bitrate: variant.targetBitrate,
              segmentDuration: segmentDuration
            });
          } catch (error) {
            reject(new Error(`Failed to read output directory: ${error.message}`));
          }
        })
        .on('error', (error) => {
          console.error(`❌ ${variant.name} encoding failed:`, error);
          reject(new Error(`FFmpeg encoding failed: ${error.message}`));
        })
        .run();
    });
  }

  /**
   * Generate master playlist for adaptive streaming
   */
  generateMasterPlaylist(variants, segmentDuration) {
    let playlist = '#EXTM3U\n';
    playlist += '#EXT-X-VERSION:6\n';
    playlist += `#EXT-X-TARGETDURATION:${segmentDuration}\n\n`;

    // Sort variants by bandwidth (lowest first for better compatibility)
    const sortedVariants = variants.sort((a, b) => this.estimateBandwidth(a) - this.estimateBandwidth(b));

    for (const variant of sortedVariants) {
      const bandwidth = this.estimateBandwidth(variant);
      const resolution = variant.resolution;
      const codecs = 'avc1.42e01e,mp4a.40.2'; // H.264 Baseline + AAC
      
      playlist += `#EXT-X-STREAM-INF:BANDWIDTH=${bandwidth},RESOLUTION=${resolution},CODECS="${codecs}"\n`;
      playlist += `${variant.name}/playlist.m3u8\n`;
    }

    return playlist;
  }

  /**
   * Estimate bandwidth for a quality variant
   */
  estimateBandwidth(variant) {
    const baseBandwidth = {
      '720p': 1200000,  // 1.2 Mbps for 720p
      '480p': 550000,   // 550 Kbps for 480p (Mobile optimized)
      '360p': 350000,   // 350 Kbps for 360p
      '240p': 150000    // 150 Kbps for 240p
    };
    
    return baseBandwidth[variant.name] || 1000000; // Default to 480p bitrate
  }

  /**
   * Get optimal resolution based on input video dimensions
   * @param {string} inputPath - Path to input video file
   * @param {Object} resolutionPresets - Available resolution presets
   * @returns {Object} - Selected resolution preset
   */
  getOptimalResolutionSync(inputPath, resolutionPresets) {
    try {
      // For now, return a balanced resolution (720p) as default
      // In a production environment, you'd use ffprobe to get actual video dimensions
      return resolutionPresets['720p'] || resolutionPresets['480p'];
    } catch (error) {
      console.warn('Could not determine optimal resolution, using 480p as fallback');
      return resolutionPresets['480p'] || resolutionPresets['360p'];
    }
  }

  /**
   * Clean up HLS files for a video
   */
  async cleanupHLS(videoId) {
    const cleanVideoId = videoId.replace(/[^a-zA-Z0-9_-]/g, '_');
    const outputDir = path.join(this.hlsOutputDir, cleanVideoId);
    if (fs.existsSync(outputDir)) {
      fs.rmSync(outputDir, { recursive: true, force: true });
    }
  }

  /**
   * Clean up old temporary HLS directories
   */
  async cleanupTempHLSDirectories() {
    try {
      const files = fs.readdirSync(this.hlsOutputDir);
      const tempDirs = files.filter(file => file.startsWith('temp_'));
      
      console.log(`🧹 Found ${tempDirs.length} temporary HLS directories to clean up`);
      
      for (const tempDir of tempDirs) {
        const tempPath = path.join(this.hlsOutputDir, tempDir);
        try {
          fs.rmSync(tempPath, { recursive: true, force: true });
          console.log(`✅ Cleaned up temporary directory: ${tempDir}`);
        } catch (error) {
          console.error(`❌ Failed to clean up ${tempDir}:`, error);
        }
      }
    } catch (error) {
      console.error('❌ Error cleaning up temporary HLS directories:', error);
    }
  }

  /**
   * Get HLS info for a video
   */
  getHLSInfo(videoId) {
    const outputDir = path.join(this.hlsOutputDir, videoId);
    if (!fs.existsSync(outputDir)) {
      return null;
    }

    try {
      const files = fs.readdirSync(outputDir, { recursive: true });
      const playlists = files.filter(file => file.endsWith('.m3u8'));
      const segments = files.filter(file => file.endsWith('.ts'));
      
      return {
        videoId,
        outputDir,
        playlists,
        totalSegments: segments.length,
        hasMasterPlaylist: files.includes('master.m3u8'),
        hasSinglePlaylist: files.includes('playlist.m3u8')
      };
    } catch (error) {
      console.error(`Error getting HLS info for ${videoId}:`, error);
      return null;
    }
  }

  /**
   * Generate network-aware adaptive HLS with quality selection
   * @param {string} inputPath - Path to input video file
   * @param {string} videoId - Unique video identifier
   * @param {Object} options - Options for quality selection
   * @returns {Promise<Object>} - Adaptive HLS result
   */
  async generateNetworkAwareHLS(inputPath, videoId, options = {}) {
    try {
      const {
        targetBitrate = 'auto', // auto, low, medium, high
        maxQuality = '1080p',   // Maximum quality to generate
        minQuality = '144p'     // Minimum quality to ensure
      } = options;

      console.log(`🎬 Starting network-aware HLS generation for ${videoId}`);
      console.log(`📁 Input path: ${inputPath}`);
      console.log(`⚙️ Options:`, options);

      // Check if input file exists
      if (!fs.existsSync(inputPath)) {
        throw new Error(`Input file does not exist: ${inputPath}`);
      }

      // Quality tiers based on network conditions
      const qualityTiers = {
        low: ['144p', '240p', '360p'],           // Slow internet (2G/3G)
        medium: ['360p', '480p', '720p'],        // Average internet (4G)
        high: ['480p', '720p', '1080p'],         // Fast internet (4G+/5G)
        ultra: ['720p', '1080p', '1440p', '4k']  // Very fast internet (5G/Fiber)
      };

      // Auto-detect based on common network patterns
      let selectedTier = targetBitrate;
      if (targetBitrate === 'auto') {
        // Default to medium for better compatibility
        selectedTier = 'medium';
      }

      const selectedQualities = qualityTiers[selectedTier] || qualityTiers.medium;
      
      // Filter variants based on selected qualities
      const variants = this.getQualityVariants().filter(variant => 
        selectedQualities.includes(variant.name) &&
        this.isQualityInRange(variant.name, minQuality, maxQuality)
      );

      if (variants.length === 0) {
        throw new Error('No quality variants selected for encoding');
      }

      console.log(`🎬 Generating network-aware HLS for ${videoId}: ${variants.map(v => v.name).join(', ')}`);

      return await this.generateAdaptiveHLSWithVariants(inputPath, videoId, variants);
    } catch (error) {
      console.error(`❌ Network-aware HLS generation failed for ${videoId}:`, error);
      throw new Error(`HLS generation failed: ${error.message}`);
    }
  }

  /**
   * Get all available quality variants
   * @returns {Array} - Array of quality variants
   */
  getQualityVariants() {
    return [
      { 
        name: '720p', 
        crf: 24, 
        width: 720, 
        height: 1280, // 9:16 aspect ratio
        audioBitrate: '96k', 
        targetBitrate: '1200k',
        segmentDuration: 2
      },
      { 
        name: '480p', 
        crf: 26, 
        width: 480, 
        height: 854, // 9:16 aspect ratio
        audioBitrate: '64k', 
        targetBitrate: '550k',
        segmentDuration: 2
      },
      { 
        name: '360p', 
        crf: 28, 
        width: 360, 
        height: 640, // 9:16 aspect ratio
        audioBitrate: '48k', 
        targetBitrate: '350k',
        segmentDuration: 2
      },
      { 
        name: '240p', 
        crf: 30, 
        width: 240, 
        height: 426, // 9:16 aspect ratio
        audioBitrate: '32k', 
        targetBitrate: '150k',
        segmentDuration: 2
      }
    ];
  }

  /**
   * Check if quality is within specified range
   * @param {string} quality - Quality name
   * @param {string} minQuality - Minimum quality
   * @param {string} maxQuality - Maximum quality
   * @returns {boolean} - True if quality is in range
   */
  isQualityInRange(quality, minQuality, maxQuality) {
    const qualityOrder = ['144p', '240p', '360p', '480p', '720p', '1080p', '1440p', '4k'];
    const qualityIndex = qualityOrder.indexOf(quality);
    const minIndex = qualityOrder.indexOf(minQuality);
    const maxIndex = qualityOrder.indexOf(maxQuality);
    
    return qualityIndex >= minIndex && qualityIndex <= maxIndex;
  }

  /**
   * Generate adaptive HLS with custom variants
   * @param {string} inputPath - Path to input video file
   * @param {string} videoId - Unique video identifier
   * @param {Array} variants - Array of quality variants
   * @returns {Promise<Object>} - Adaptive HLS result
   */
  async generateAdaptiveHLSWithVariants(inputPath, videoId, variants) {
    try {
      // **FIXED: Use proper video ID instead of temporary names**
      const cleanVideoId = videoId.replace(/[^a-zA-Z0-9_-]/g, '_');
      const outputDir = path.join(this.hlsOutputDir, cleanVideoId);
      const masterPlaylistPath = path.join(outputDir, 'master.m3u8');
      
      console.log(`🎬 Creating output directory: ${outputDir}`);
      if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
      }

      const segmentDuration = 6;
      const promises = [];

      console.log(`🎬 Starting encoding of ${variants.length} variants`);

      // Generate each quality variant
      for (const variant of variants) {
        const variantDir = path.join(outputDir, variant.name);
        if (!fs.existsSync(variantDir)) {
          fs.mkdirSync(variantDir, { recursive: true });
        }

        console.log(`🎬 Starting encoding for ${variant.name}`);
        const promise = this.encodeVariant(inputPath, variantDir, variant, segmentDuration, videoId);
        promises.push(promise);
      }

      console.log(`🎬 Waiting for all variants to complete...`);
      const results = await Promise.all(promises);
      
      console.log(`✅ All variants completed, generating master playlist`);
      
      // Generate master playlist
      const masterPlaylist = this.generateMasterPlaylist(results, segmentDuration);
      fs.writeFileSync(masterPlaylistPath, masterPlaylist);

      console.log(`✅ Master playlist created: ${masterPlaylistPath}`);

      return {
        success: true,
        masterPlaylistPath,
        masterPlaylistUrl: `/uploads/hls/${cleanVideoId}/master.m3u8`,
        variants: results,
        segmentDuration,
        qualityRange: `${variants[0].name} to ${variants[variants.length - 1].name}`
      };
    } catch (error) {
      console.error(`❌ Adaptive HLS generation failed:`, error);
      throw new Error(`Adaptive HLS generation failed: ${error.message}`);
    }
  }
}

export default new HLSEncodingService();
