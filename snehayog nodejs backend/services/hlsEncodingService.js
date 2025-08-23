import ffmpeg from 'fluent-ffmpeg';
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

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
   * Convert video to HLS format
   * @param {string} inputPath - Path to input video file
   * @param {string} videoId - Unique video identifier
   * @param {Object} options - Encoding options
   * @returns {Promise<Object>} - HLS encoding result
   */
  async convertToHLS(inputPath, videoId, options = {}) {
    const {
      segmentDuration = 3, // Optimized segment duration: 2-4 seconds for fast startup
      quality = 'medium', // low, medium, high
      resolution = 'auto' // auto, 720p, 480p, 240p
    } = options;

    return new Promise((resolve, reject) => {
      const outputDir = path.join(this.hlsOutputDir, videoId);
      const playlistPath = path.join(outputDir, 'playlist.m3u8');
      
      // Create output directory
      if (!fs.existsSync(outputDir)) {
        fs.mkdirSync(outputDir, { recursive: true });
      }

      // Quality presets optimized for HLS streaming
      const qualityPresets = {
        low: { crf: 25, audioBitrate: '64k' },    // Lower quality, smaller file
        medium: { crf: 23, audioBitrate: '96k' }, // Balanced quality (recommended)
        high: { crf: 20, audioBitrate: '128k' }   // Higher quality, larger file
      };

      // Resolution presets - focused on mobile and web streaming
      const resolutionPresets = {
        '720p': { width: 1280, height: 720, bitrate: '1500k' },
        '480p': { width: 854, height: 480, bitrate: '800k' },
        '240p': { width: 426, height: 240, bitrate: '300k' }
      };

      // Auto-detect best resolution based on input video
      let selectedResolution = null;
      if (resolution === 'auto') {
        // Get input video dimensions and select appropriate resolution
        selectedResolution = this.getOptimalResolutionSync(inputPath, resolutionPresets);
      } else if (resolutionPresets[resolution]) {
        selectedResolution = resolutionPresets[resolution];
      }

      const selectedQuality = qualityPresets[quality] || qualityPresets.medium;

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
          '-maxrate', selectedResolution?.bitrate || '800k', // Bitrate constraint
          '-bufsize', `${parseInt(selectedResolution?.bitrate || '800k') * 2}k`, // Buffer size
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

      // Add resolution if specified
      if (selectedResolution) {
        command = command
          .size(`${selectedResolution.width}x${selectedResolution.height}`)
          .aspect('16:9');
      }

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
            playlistUrl: `/uploads/hls/${videoId}/playlist.m3u8`,
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
    const outputDir = path.join(this.hlsOutputDir, videoId);
    const masterPlaylistPath = path.join(outputDir, 'master.m3u8');
    
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }

    // Quality variants optimized for fast startup and efficient streaming
    // Segment duration: 2-4 seconds for fast startup
    // CRF ~23 for good quality, baseline profile for compatibility
    const variants = [
      { 
        name: '720p', 
        crf: 23, 
        width: 1280, 
        height: 720, 
        audioBitrate: '128k', 
        targetBitrate: '1500k',
        segmentDuration: 3 // 3 seconds for optimal startup
      },
      { 
        name: '480p', 
        crf: 23, 
        width: 854, 
        height: 480, 
        audioBitrate: '96k', 
        targetBitrate: '800k',
        segmentDuration: 3
      },
      { 
        name: '240p', 
        crf: 23, 
        width: 426, 
        height: 240, 
        audioBitrate: '64k', 
        targetBitrate: '300k',
        segmentDuration: 3
      }
    ];

    const promises = [];

    // Generate each quality variant
    for (const variant of variants) {
      const variantDir = path.join(outputDir, variant.name);
      if (!fs.existsSync(variantDir)) {
        fs.mkdirSync(variantDir, { recursive: true });
      }

      const promise = this.encodeVariant(inputPath, variantDir, variant, variant.segmentDuration);
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
        masterPlaylistUrl: `/uploads/hls/${videoId}/master.m3u8`,
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
  async encodeVariant(inputPath, outputDir, variant, segmentDuration) {
    return new Promise((resolve, reject) => {
      const playlistPath = path.join(outputDir, 'playlist.m3u8');
      
      ffmpeg(inputPath)
        .inputOptions(['-y', '-hide_banner', '-loglevel error'])
        .outputOptions([
          // Video codec settings - optimized for HLS streaming
          '-c:v', 'libx264',
          '-preset', 'fast',           // Fast encoding for production
          '-profile:v', 'baseline',    // Baseline profile for maximum compatibility
          '-level', '3.1',             // H.264 level for broad device support
          '-crf', variant.crf.toString(), // Constant Rate Factor ~23 for good quality
          '-maxrate', variant.targetBitrate, // Maximum bitrate constraint
          '-bufsize', `${parseInt(variant.targetBitrate) * 2}k`, // Buffer size for bitrate control
          '-sc_threshold', '0',        // Disable scene change detection for consistent quality
          '-g', '48',                  // GOP size for 3-second segments
          '-keyint_min', '48',         // Minimum keyframe interval
          '-force_key_frames', 'expr:gte(t,n_forced*3)', // Force keyframes every 3 seconds
          
          // Audio codec settings
          '-c:a', 'aac',
          '-b:a', variant.audioBitrate,
          '-ac', '2',                  // Stereo audio
          '-ar', '44100',              // 44.1kHz sample rate
          
          // HLS specific settings
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
        ])
        .size(`${variant.width}x${variant.height}`)
        .aspect('16:9')
        .output(playlistPath)
        .on('end', () => {
          const segments = fs.readdirSync(outputDir).filter(file => file.endsWith('.ts'));
          resolve({
            name: variant.name,
            playlistPath,
            playlistUrl: `/uploads/hls/${videoId}/${variant.name}/playlist.m3u8`,
            segments: segments.length,
            resolution: `${variant.width}x${variant.height}`,
            bitrate: variant.targetBitrate,
            segmentDuration: segmentDuration
          });
        })
        .on('error', reject)
        .run();
    });
  }

  /**
   * Generate master playlist for adaptive streaming
   */
  generateMasterPlaylist(variants, segmentDuration) {
    let playlist = '#EXTM3U\n';
    playlist += '#EXT-X-VERSION:3\n';
    playlist += `#EXT-X-TARGETDURATION:${segmentDuration}\n`;
    playlist += '#EXT-X-MEDIA-SEQUENCE:0\n\n';

    for (const variant of variants) {
      playlist += `#EXT-X-STREAM-INF:BANDWIDTH=${this.estimateBandwidth(variant)},RESOLUTION=${variant.resolution}\n`;
      playlist += `${variant.name}/playlist.m3u8\n`;
    }

    return playlist;
  }

  /**
   * Estimate bandwidth for a quality variant
   */
  estimateBandwidth(variant) {
    const baseBandwidth = {
      '720p': 1500000,  // 1.5 Mbps for 720p
      '480p': 800000,   // 800 Kbps for 480p
      '240p': 300000    // 300 Kbps for 240p
    };
    
    return baseBandwidth[variant.name] || 800000; // Default to 480p bitrate
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
    const outputDir = path.join(this.hlsOutputDir, videoId);
    if (fs.existsSync(outputDir)) {
      fs.rmSync(outputDir, { recursive: true, force: true });
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
    const {
      targetBitrate = 'auto', // auto, low, medium, high
      maxQuality = '1080p',   // Maximum quality to generate
      minQuality = '144p'     // Minimum quality to ensure
    } = options;

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

    console.log(`🎬 Generating network-aware HLS for ${videoId}: ${variants.map(v => v.name).join(', ')}`);

    return this.generateAdaptiveHLSWithVariants(inputPath, videoId, variants);
  }

  /**
   * Get all available quality variants
   * @returns {Array} - Array of quality variants
   */
  getQualityVariants() {
    return [
      { 
        name: '720p', 
        crf: 23, 
        width: 1280, 
        height: 720, 
        audioBitrate: '128k', 
        targetBitrate: '1500k',
        segmentDuration: 3
      },
      { 
        name: '480p', 
        crf: 23, 
        width: 854, 
        height: 480, 
        audioBitrate: '96k', 
        targetBitrate: '800k',
        segmentDuration: 3
      },
      { 
        name: '240p', 
        crf: 23, 
        width: 426, 
        height: 240, 
        audioBitrate: '64k', 
        targetBitrate: '300k',
        segmentDuration: 3
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
    const outputDir = path.join(this.hlsOutputDir, videoId);
    const masterPlaylistPath = path.join(outputDir, 'master.m3u8');
    
    if (!fs.existsSync(outputDir)) {
      fs.mkdirSync(outputDir, { recursive: true });
    }

    const segmentDuration = 6;
    const promises = [];

    // Generate each quality variant
    for (const variant of variants) {
      const variantDir = path.join(outputDir, variant.name);
      if (!fs.existsSync(variantDir)) {
        fs.mkdirSync(variantDir, { recursive: true });
      }

      const promise = this.encodeVariant(inputPath, variantDir, variant, segmentDuration);
      promises.push(promise);
    }

    try {
      const results = await Promise.all(promises);
      
      // Generate master playlist
      const masterPlaylist = this.generateMasterPlaylist(results, segmentDuration);
      fs.writeFileSync(masterPlaylistPath, masterPlaylist);

      return {
        success: true,
        masterPlaylistPath,
        masterPlaylistUrl: `/uploads/hls/${videoId}/master.m3u8`,
        variants: results,
        segmentDuration,
        qualityRange: `${variants[0].name} to ${variants[variants.length - 1].name}`
      };
    } catch (error) {
      throw new Error(`Adaptive HLS generation failed: ${error.message}`);
    }
  }
}

export default new HLSEncodingService();
