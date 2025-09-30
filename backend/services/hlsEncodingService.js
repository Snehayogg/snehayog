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
      // **FIXED: Use proper video ID instead of temporary names**
      const cleanVideoId = videoId.replace(/[^a-zA-Z0-9_-]/g, '_');
      const outputDir = path.join(this.hlsOutputDir, cleanVideoId);
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
        '480p': { width: 854, height: 480, bitrate: '800k' },
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
          .videoFilters(`scale='min(${selectedResolution.width},iw)':-2:force_original_aspect_ratio=decrease,pad=${selectedResolution.width}:${selectedResolution.height}:(ow-iw)/2:(oh-ih)/2:black`)
          .size(`${selectedResolution.width}x${selectedResolution.height}`);
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
        crf: 20, 
        width: 720, 
        height: 1280, // 9:16 aspect ratio
        audioBitrate: '128k', 
        targetBitrate: '2000k',
        segmentDuration: 2 // 2 seconds for instant startup
      },
      { 
        name: '480p', 
        crf: 20, 
        width: 480, 
        height: 854, // 9:16 aspect ratio
        audioBitrate: '96k', 
        targetBitrate: '1000k',
        segmentDuration: 2
      },
      { 
        name: '360p', 
        crf: 20, 
        width: 360, 
        height: 640, // 9:16 aspect ratio
        audioBitrate: '64k', 
        targetBitrate: '500k',
        segmentDuration: 2
      },
      { 
        name: '240p', 
        crf: 20, 
        width: 240, 
        height: 426, // 9:16 aspect ratio
        audioBitrate: '48k', 
        targetBitrate: '200k',
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
      '720p': 2000000,  // 2.0 Mbps for 720p (increased for better quality)
      '480p': 1000000,  // 1.0 Mbps for 480p (increased for better quality)
      '360p': 500000,   // 500 Kbps for 360p (new quality level)
      '240p': 200000    // 200 Kbps for 240p (optimized for slow connections)
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
        crf: 20, 
        width: 720, 
        height: 1280, // 9:16 aspect ratio
        audioBitrate: '128k', 
        targetBitrate: '2000k',
        segmentDuration: 2
      },
      { 
        name: '480p', 
        crf: 20, 
        width: 480, 
        height: 854, // 9:16 aspect ratio
        audioBitrate: '96k', 
        targetBitrate: '1000k',
        segmentDuration: 2
      },
      { 
        name: '360p', 
        crf: 20, 
        width: 360, 
        height: 640, // 9:16 aspect ratio
        audioBitrate: '64k', 
        targetBitrate: '500k',
        segmentDuration: 2
      },
      { 
        name: '240p', 
        crf: 20, 
        width: 240, 
        height: 426, // 9:16 aspect ratio
        audioBitrate: '48k', 
        targetBitrate: '200k',
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
