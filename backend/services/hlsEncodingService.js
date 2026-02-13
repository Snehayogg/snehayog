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
  const systemFfmpeg = spawnSync('which', ['ffmpeg']);
  if (systemFfmpeg.status === 0 && systemFfmpeg.stdout.toString().trim()) {
    ffmpegPath = systemFfmpeg.stdout.toString().trim();
  }
  const systemFfprobe = spawnSync('which', ['ffprobe']);
  if (systemFfprobe.status === 0 && systemFfprobe.stdout.toString().trim()) {
    ffprobePath = systemFfprobe.stdout.toString().trim();
  }
} catch (e) {
  console.warn('[HLS] FFmpeg path check failed:', e.message);
}

if (!ffmpegPath) {
  try {
    ffmpegPath = (await import('ffmpeg-static')).default;
  } catch (e) {
    console.error('[HLS] FFmpeg not found. HLS encoding will fail.');
  }
}
if (!ffprobePath) {
  try {
    ffprobePath = (await import('ffprobe-static')).default.path;
  } catch (e) {
    console.error('[HLS] FFprobe not found.');
  }
}

if (ffmpegPath) ffmpeg.setFfmpegPath(ffmpegPath);
if (ffprobePath) ffmpeg.setFfprobePath(ffprobePath);


class HLSEncodingService {
  constructor() {
    // Ensure HLS output directory exists
    this.hlsOutputDir = path.join(__dirname, '../uploads/hls');
    this.ensureHLSDirectory();
    
    this.checkFFmpegInstallation().then(isInstalled => {
      if (!isInstalled) console.warn('[HLS] FFmpeg not available. Encoding will fail.');
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
   * @param {string} options.codec - Video codec: 'h264' or 'h265' (default: 'h264'). H.265 gives ~50% smaller files at same quality.
   * @returns {Promise<Object>} - HLS encoding result
   */
  async convertToHLS(inputPath, videoId, options = {}) {
    const {
      segmentDuration = 3, // Optimized segment duration: 3 seconds for fast startup
      quality = 'medium', // low, medium, high (medium = 480p optimal)
      resolution = '480p', // Fixed to 480p for cost optimization (single quality only)
      codec = 'h265' // 'h264' or 'h265' - H.265 for ~50% bandwidth savings
    } = options;

    // Resolve actual codec (fallback to h264 if h265 requested but unavailable)
    let actualCodec = codec;
    if (codec === 'h265') {
      const hasH265 = await this.checkLibx265Available();
      if (!hasH265) {
        console.warn(`[HLS] ${videoId} | WARNING | H.265 requested but libx265 not available. Falling back to H.264.`);
        actualCodec = 'h264';
      } else {
        console.log(`[HLS] ${videoId} | INFO | H.265 (HEVC) encoding confirmed.`);
      }
    }

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
        medium: { crf: 28, audioBitrate: '48k' }, // Updated to match new standard (was 64k)
        high: { crf: 23, audioBitrate: '128k' }   // Higher quality
      };

      // **FIX: Use original resolution instead of fixed 480p**
      // Calculate bitrate based on original resolution for better quality
      const originalVideoInfo = options.originalVideoInfo;
      let selectedResolution;
      let targetBitrate = '400k'; // Default bitrate (Updated for 500kbps target)
      
      if (originalVideoInfo && originalVideoInfo.width && originalVideoInfo.height) {
        const originalWidth = originalVideoInfo.width;
        const originalHeight = originalVideoInfo.height;
        
        // Calculate bitrate based on resolution (higher resolution = higher bitrate)
        if (originalHeight > 1080) {
          targetBitrate = '2500k'; // 1080p+ (Reduced)
        } else if (originalHeight > 720) {
          targetBitrate = '1200k'; // 720p-1080p (Reduced)
        } else if (originalHeight > 480) {
          targetBitrate = '600k'; // 480p-720p (Reduced for efficiency)
        } else {
          targetBitrate = '400k'; // Below 480p (Targeting ~2MB per minute)
        }
        
        selectedResolution = {
          width: originalWidth,
          height: originalHeight,
          bitrate: targetBitrate
        };
      } else {
        // Fallback to 480p if original info not available
        targetBitrate = '400k';
        selectedResolution = { width: 854, height: 480, bitrate: targetBitrate };
      }
      
      const selectedQuality = qualityPresets[quality] || qualityPresets.medium;
      
      const codecName = actualCodec === 'h265' ? 'H.265 (HEVC)' : 'H.264 (AVC)';
      console.log(`[HLS] ${videoId} | START | codec=${codecName} resolution=${selectedResolution.width}x${selectedResolution.height} bitrate=${targetBitrate} segments=${segmentDuration}s`);

      // Build video codec options based on actual codec
      const isH265 = actualCodec === 'h265';
      const videoOptions = isH265
        ? [
            // H.265/HEVC - ~50% smaller files at same quality (ideal for 500kbps)
            '-c:v', 'libx265',
            '-tag:v', 'hvc1',          // hvc1 tag for Safari/Apple compatibility
            '-preset', 'fast',         // fast = good balance of speed vs compression
            '-crf', selectedQuality.crf.toString(),
            '-maxrate', targetBitrate,
            '-bufsize', `${parseInt(targetBitrate) * 2}k`,
            // x265 GOP: keyframe every 2s for HLS segment alignment (60 frames @ 30fps)
            '-x265-params', 'keyint=60:min-keyint=60:scenecut=0',
            '-pix_fmt', 'yuv420p'     // 8-bit Main profile for broad device support
          ]
        : [
            // H.264 - maximum compatibility
            '-c:v', 'libx264',
            '-preset', 'fast',
            '-profile:v', 'high',
            '-level', '3.1',
            '-crf', selectedQuality.crf.toString(),
            '-maxrate', targetBitrate,
            '-bufsize', `${parseInt(targetBitrate) * 2}k`,
            '-sc_threshold', '0',
            '-g', '60',
            '-keyint_min', '48',
            '-force_key_frames', 'expr:gte(t,n_forced*2)',
            '-pix_fmt', 'yuv420p'
          ];

      const commonOptions = [
        // Audio codec settings (same for both)
        '-c:a', 'aac',
        '-b:a', selectedQuality.audioBitrate,
        '-ac', '2',
        '-ar', '44100',
        '-af', 'acompressor=ratio=4:attack=200:release=1000:threshold=-12dB',
        // HLS settings
        '-f', 'hls',
        '-hls_time', segmentDuration.toString(),
        '-hls_list_size', '0',
        '-hls_segment_filename', path.join(outputDir, 'segment_%03d.ts'),
        '-hls_playlist_type', 'vod',
        '-hls_flags', 'independent_segments+delete_segments',
        '-hls_segment_type', 'mpegts',
        '-movflags', '+faststart'
      ];

      let command = ffmpeg(inputPath)
        .inputOptions(['-y', '-hide_banner', '-loglevel error'])
        .outputOptions([...videoOptions, ...commonOptions]);

      // **FIX: Preserve original resolution - encode at original dimensions**
      // Only scale down if video is extremely large (optional optimization for very large files)
      // For most videos, keep original resolution (1080x1920, etc.)
      const originalVideoInfoForScaling = options.originalVideoInfo;
      
      if (originalVideoInfoForScaling && originalVideoInfoForScaling.width && originalVideoInfoForScaling.height) {
        const { width: origW, height: origH } = originalVideoInfoForScaling;
        if (origH > 1080) {
          command = command.videoFilters(`scale=-2:1080:force_original_aspect_ratio=decrease`);
        }
      }
      
      // **REMOVED: .size() call that was forcing fixed dimensions**
      // We don't set .size() to allow FFmpeg to maintain the original resolution

      // Add output
      command = command.output(playlistPath);

      let lastProgressLog = 0;
      command.on('progress', (progress) => {
        const pct = Math.floor(parseFloat(progress.percent) || 0);
        if (pct >= lastProgressLog + 25 || pct >= 99) {
          lastProgressLog = pct;
          console.log(`[HLS] ${videoId} | PROGRESS | ${pct}%`);
        }
      });

      command.on('end', () => {
        try {
          const playlistContent = fs.readFileSync(playlistPath, 'utf8');
          const segments = fs.readdirSync(outputDir).filter(file => file.endsWith('.ts'));
          
          if (!playlistContent.includes('#EXTM3U')) {
            throw new Error('Invalid HLS playlist format - missing #EXTM3U header');
          }
          if (segments.length === 0) {
            throw new Error('No video segments found in HLS output');
          }
          
          const codecName = actualCodec === 'h265' ? 'H.265 (HEVC)' : 'H.264 (AVC)';
          console.log(`[HLS] ${videoId} | DONE | codec=${codecName} segments=${segments.length} playlist=/uploads/hls/${cleanVideoId}/playlist.m3u8`);
          
          resolve({
            success: true,
            playlistPath,
            playlistUrl: `/uploads/hls/${cleanVideoId}/playlist.m3u8`,
            segments: segments.length,
            outputDir,
            segmentDuration,
            quality,
            resolution: selectedResolution || 'auto',
            codec: actualCodec
          });
        } catch (error) {
          reject(new Error(`Failed to read HLS output: ${error.message}`));
        }
      });

      command.on('error', (error) => {
        console.error(`[HLS] ${videoId} | ERROR | ${error.message}`);
        reject(new Error(`HLS encoding failed: ${error.message}`));
      });

      // Start encoding
      command.run();
    });
  }

  // Add this method to the HLSEncodingService class

  async checkFFmpegInstallation() {
    return new Promise((resolve) => {
      ffmpeg.getAvailableCodecs((err) => {
        if (err) {
          console.error('[HLS] FFmpeg check failed:', err.message);
          resolve(false);
        } else resolve(true);
      });
    });
  }

  /**
   * Check if libx265 (H.265/HEVC) encoder is available in FFmpeg
   * @returns {Promise<boolean>}
   */
  async checkLibx265Available() {
    return new Promise((resolve) => {
      ffmpeg.getAvailableEncoders((err, encoders) => {
        if (err) {
          resolve(false);
          return;
        }
        const hasLibx265 = encoders && encoders['libx265'];
        if (!hasLibx265) {
          console.warn('[HLS] H.265 (libx265) not available. Use codec: h264 or install FFmpeg with --enable-libx265');
        }
        resolve(!!hasLibx265);
      });
    });
  }



  /**
   * Generate multiple quality variants for adaptive streaming
   * @param {string} inputPath - Path to input video file
   * @param {string} videoId - Unique video identifier
   * @param {Object} options - Options including codec: 'h264' | 'h265'
   * @returns {Promise<Object>} - Multi-quality HLS result
   */
  async generateAdaptiveHLS(inputPath, videoId, options = {}) {
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

    let codec = options.codec || 'h264';
    if (codec === 'h265') {
      const hasH265 = await this.checkLibx265Available();
      if (!hasH265) {
        console.warn('[HLS] H.265 requested but libx265 not available. Falling back to H.264.');
        codec = 'h264';
      }
    }
    const promises = [];

    // Generate each quality variant
    for (const variant of variants) {
      const variantDir = path.join(outputDir, variant.name);
      if (!fs.existsSync(variantDir)) {
        fs.mkdirSync(variantDir, { recursive: true });
      }

      const promise = this.encodeVariant(inputPath, variantDir, variant, variant.segmentDuration, videoId, { codec });
      promises.push(promise);
    }

    try {
      console.log(`[HLS] ${videoId} | adaptive START | codec=${codec} [720p,480p,360p,240p]`);
      const results = await Promise.all(promises);
      const masterPlaylist = this.generateMasterPlaylist(results, variants[0].segmentDuration, codec);
      fs.writeFileSync(masterPlaylistPath, masterPlaylist);
      const totalSegments = results.reduce((sum, r) => sum + (r.segments || 0), 0);
      console.log(`[HLS] ${videoId} | adaptive DONE | codec=${codec} variants=${results.length} segments=${totalSegments}`);

      return {
        success: true,
        masterPlaylistPath,
        masterPlaylistUrl: `/uploads/hls/${cleanVideoId}/master.m3u8`,
        variants: results,
        segmentDuration: variants[0].segmentDuration,
        qualityRange: `${variants[0].name} to ${variants[variants.length - 1].name}`
      };
    } catch (error) {
      console.error(`[HLS] ${videoId} | adaptive ERROR | ${error.message}`);
      throw new Error(`Adaptive HLS generation failed: ${error.message}`);
    }
  }

  /**
   * Encode a single quality variant
   * @param {Object} variantOptions - Optional { codec: 'h264' | 'h265' }
   */
  async encodeVariant(inputPath, outputDir, variant, segmentDuration, videoId, variantOptions = {}) {
    return new Promise((resolve, reject) => {
      const playlistPath = path.join(outputDir, 'playlist.m3u8');
      const cleanVideoId = videoId.replace(/[^a-zA-Z0-9_-]/g, '_');
      const codec = variantOptions.codec || 'h264';
      const isH265 = codec === 'h265';
      
      console.log(`[HLS] ${videoId} | variant ${variant.name} | START | ${codec.toUpperCase()} ${variant.width}x${variant.height}`);
      
      let lastVariantProgress = 0;
      const videoOpts = isH265
        ? ['-c:v', 'libx265', '-tag:v', 'hvc1', '-preset', 'fast', '-crf', variant.crf.toString(),
           '-maxrate', variant.targetBitrate, '-bufsize', `${parseInt(variant.targetBitrate) * 2}k`,
           '-x265-params', 'keyint=60:min-keyint=60:scenecut=0', '-pix_fmt', 'yuv420p']
        : ['-c:v', 'libx264', '-preset', 'fast', '-profile:v', 'baseline', '-level', '3.0',
           '-crf', variant.crf.toString(), '-maxrate', variant.targetBitrate,
           '-bufsize', `${parseInt(variant.targetBitrate) * 2}k`, '-pix_fmt', 'yuv420p'];
      
      ffmpeg(inputPath)
        .inputOptions(['-y', '-hide_banner', '-loglevel error'])
        .outputOptions([
          ...videoOpts,
          '-c:a', 'aac', '-b:a', variant.audioBitrate, '-ac', '2', '-ar', '44100',
          '-f', 'hls', '-hls_time', segmentDuration.toString(), '-hls_list_size', '0',
          '-hls_segment_filename', path.join(outputDir, 'segment_%03d.ts'),
          '-hls_playlist_type', 'vod', '-hls_flags', 'independent_segments',
          '-hls_segment_type', 'mpegts'
        ])
        // Respect original aspect; pad if required to target dimensions
        .videoFilters(`scale='min(${variant.width},iw)':-2:force_original_aspect_ratio=decrease,pad=${variant.width}:${variant.height}:(ow-iw)/2:(oh-ih)/2:black`)
        .size(`${variant.width}x${variant.height}`)
        .output(playlistPath)
        .on('progress', (progress) => {
          const pct = Math.floor(parseFloat(progress.percent) || 0);
          if (pct >= lastVariantProgress + 50 || pct >= 99) {
            lastVariantProgress = pct;
            console.log(`[HLS] ${videoId} | variant ${variant.name} | ${pct}%`);
          }
        })
        .on('end', () => {
          try {
            const segments = fs.readdirSync(outputDir).filter(file => file.endsWith('.ts'));
            console.log(`[HLS] ${videoId} | variant ${variant.name} | DONE | segments=${segments.length}`);
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
          console.error(`[HLS] ${videoId} | variant ${variant.name} | ERROR | ${error.message}`);
          reject(new Error(`FFmpeg encoding failed: ${error.message}`));
        })
        .run();
    });
  }

  /**
   * Generate master playlist for adaptive streaming
   * @param {string} codec - 'h264' or 'h265' for CODECS attribute
   */
  generateMasterPlaylist(variants, segmentDuration, codec = 'h264') {
    let playlist = '#EXTM3U\n';
    playlist += '#EXT-X-VERSION:6\n';
    playlist += `#EXT-X-TARGETDURATION:${segmentDuration}\n\n`;

    const sortedVariants = variants.sort((a, b) => this.estimateBandwidth(a) - this.estimateBandwidth(b));
    // H.264: avc1.42e01e | H.265: hvc1.1.6.L93.B0 (Main profile, Level 3.1)
    const codecsStr = codec === 'h265'
      ? 'hvc1.1.6.L93.B0,mp4a.40.2'
      : 'avc1.42e01e,mp4a.40.2';

    for (const variant of sortedVariants) {
      const bandwidth = this.estimateBandwidth(variant);
      const resolution = variant.resolution;
      playlist += `#EXT-X-STREAM-INF:BANDWIDTH=${bandwidth},RESOLUTION=${resolution},CODECS="${codecsStr}"\n`;
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
      console.warn('[HLS] getOptimalResolution failed, using 480p');
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
      let cleaned = 0;
      for (const tempDir of tempDirs) {
        try {
          fs.rmSync(path.join(this.hlsOutputDir, tempDir), { recursive: true, force: true });
          cleaned++;
        } catch (error) {
          console.error(`[HLS] cleanup failed ${tempDir}:`, error.message);
        }
      }
      if (cleaned > 0) console.log(`[HLS] cleanup | removed ${cleaned} temp dirs`);
    } catch (error) {
      console.error('[HLS] cleanup error:', error.message);
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
      console.error(`[HLS] getInfo ${videoId}:`, error.message);
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
        minQuality = '144p',    // Minimum quality to ensure
        codec = 'h264'          // 'h264' or 'h265' for video codec
      } = options;

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

      console.log(`[HLS] ${videoId} | adaptive START | codec=${codec} qualities=${variants.map(v => v.name).join(',')}`);
      return await this.generateAdaptiveHLSWithVariants(inputPath, videoId, variants, { codec });
    } catch (error) {
      console.error(`[HLS] ${videoId} | adaptive ERROR | ${error.message}`);
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
   * @param {Object} options - Options including codec: 'h264' | 'h265'
   * @returns {Promise<Object>} - Adaptive HLS result
   */
  async generateAdaptiveHLSWithVariants(inputPath, videoId, variants, options = {}) {
    try {
      const cleanVideoId = videoId.replace(/[^a-zA-Z0-9_-]/g, '_');
      const outputDir = path.join(this.hlsOutputDir, cleanVideoId);
      const masterPlaylistPath = path.join(outputDir, 'master.m3u8');
      let codec = options.codec || 'h264';
      if (codec === 'h265') {
        const hasH265 = await this.checkLibx265Available();
        if (!hasH265) {
          console.warn('[HLS] H.265 requested but libx265 not available. Falling back to H.264.');
          codec = 'h264';
        }
      }
      
      if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
      }

      const segmentDuration = 6;
      const promises = [];
      const variantNames = variants.map(v => v.name).join(',');
      console.log(`[HLS] ${videoId} | adaptive variants START | codec=${codec.toUpperCase()} [${variantNames}]`);

      for (const variant of variants) {
        const variantDir = path.join(outputDir, variant.name);
        if (!fs.existsSync(variantDir)) {
          fs.mkdirSync(variantDir, { recursive: true });
        }
        const promise = this.encodeVariant(inputPath, variantDir, variant, segmentDuration, videoId, { codec });
        promises.push(promise);
      }

      const results = await Promise.all(promises);
      const masterPlaylist = this.generateMasterPlaylist(results, segmentDuration, codec);
      fs.writeFileSync(masterPlaylistPath, masterPlaylist);

      const totalSegments = results.reduce((sum, r) => sum + (r.segments || 0), 0);
      console.log(`[HLS] ${videoId} | adaptive DONE | codec=${codec.toUpperCase()} variants=${results.length} segments=${totalSegments} playlist=/uploads/hls/${cleanVideoId}/master.m3u8`);

      return {
        success: true,
        masterPlaylistPath,
        masterPlaylistUrl: `/uploads/hls/${cleanVideoId}/master.m3u8`,
        variants: results,
        segmentDuration,
        qualityRange: `${variants[0].name} to ${variants[variants.length - 1].name}`
      };
    } catch (error) {
      console.error(`[HLS] ${videoId} | adaptive variants ERROR | ${error.message}`);
      throw new Error(`Adaptive HLS generation failed: ${error.message}`);
    }
  }
}

export default new HLSEncodingService();
