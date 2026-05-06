import cloudflareR2Service from './cloudflareR2Service.js';
import hlsEncodingService from './hlsEncodingService.js';
import path from 'path';
import fs from 'fs';

class HybridVideoService {

  /**
   * Process video using Local FFmpeg → R2 (Storage + FREE Bandwidth)
   * 100% FREE transcoding!
   */
  async processVideoHybrid(videoId, videoPath, videoName, userId) {
    try {
      
      let absoluteVideoPath;
      let isRemoteFile = false;

      if (videoPath.startsWith('http')) {
        isRemoteFile = true;
        
        const tempDir = path.join(process.cwd(), 'temp');
        if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });
        
        const tempFileName = `raw_${userId}_${Date.now()}.mp4`;
        const tempFilePath = path.join(tempDir, tempFileName);

        const { default: axios } = await import('axios');
        const response = await axios({
            method: 'GET',
            url: videoPath,
            responseType: 'stream'
        });

        const writer = fs.createWriteStream(tempFilePath);
        response.data.pipe(writer);

        await new Promise((resolve, reject) => {
            writer.on('finish', resolve);
            writer.on('error', reject);
        });

        absoluteVideoPath = path.resolve(tempFilePath);
        console.log('✅ Remote video downloaded to:', absoluteVideoPath);

      } else {
          if (!fs.existsSync(videoPath)) {
            throw new Error(`Video file not found: ${videoPath}`);
          }
          absoluteVideoPath = path.resolve(videoPath);
      }
      
      const stats = fs.statSync(absoluteVideoPath);
      console.log('📊 Video file size:', stats.size, 'bytes');
      
        // **SAFE EARLY THUMBNAIL GENERATION**
        let r2ThumbnailUrl = '';
        const Video = (await import('../../models/Video.js')).default;
        const videoRecord = await Video.findById(videoId);

        if (videoRecord && videoRecord.thumbnailUrl && videoRecord.thumbnailUrl.startsWith('http')) {
          console.log('✅ Custom thumbnail already present, skipping generation.');
          r2ThumbnailUrl = videoRecord.thumbnailUrl;
        } else {
          try {
            console.log('📸 Generating thumbnail early for immediate display...');
            const thumbnailPath = await this.generateThumbnailWithFFmpeg(absoluteVideoPath, videoName, userId);
            if (thumbnailPath) {
              console.log('📤 Uploading early thumbnail to R2...');
              r2ThumbnailUrl = await this.uploadThumbnailImageToR2(thumbnailPath, videoName, userId);
              
              if (videoRecord) {
                videoRecord.thumbnailUrl = r2ThumbnailUrl;
                await videoRecord.save();
                console.log('💾 Early Video record updated with thumbnail');
              }

              if (fs.existsSync(thumbnailPath)) fs.unlinkSync(thumbnailPath);
            }
          } catch (thumbError) {
            console.warn('⚠️ Early thumbnail step failed:', thumbError.message);
          }
        }
      
      console.log('📊 Getting original video info...');
      const originalVideoInfo = await this.getOriginalVideoInfo(absoluteVideoPath);
      
      // **SMART BYPASS: Detect if video is already pre-optimized**
      const isPreOptimized = originalVideoInfo.height <= 480 && 
                            (originalVideoInfo.codec === 'h264' || originalVideoInfo.codec === 'h265' || originalVideoInfo.codec === 'hevc');

      let hlsResult;
      if (isPreOptimized) {
        console.log('🎯 THE LOOPHOLE: Video is already pre-optimized (480p)! Using STREAM COPY.');
        hlsResult = await hlsEncodingService.convertToHLS(absoluteVideoPath, `${videoName}_${Date.now()}`, {
          quality: 'medium',
          resolution: '480p',
          copyVideo: true, 
          copyAudio: false,
          originalVideoInfo: originalVideoInfo
        });
      } else {
        console.log('🎬 Processing with Local FFmpeg → HLS...');
        hlsResult = await hlsEncodingService.convertToHLS(absoluteVideoPath, `${videoName}_${Date.now()}`, {
          quality: 'medium',
          resolution: '480p',
          codec: 'h265', // H.265 for bandwidth efficiency
          originalVideoInfo: originalVideoInfo
        });
      }
      
      // Upload HLS results to R2
      console.log('📤 Uploading HLS directory to R2...');
      const r2HLSResult = await cloudflareR2Service.uploadHLSDirectoryToR2(
        hlsResult.outputDir, 
        videoName, 
        userId
      );

      // **NEW: Also upload a standard MP4 version for cross-posting (YouTube/Meta)**
      console.log('📤 Uploading canonical MP4 version to R2...');
      const mp4Key = `videos/${userId}/${videoName}_optimized_${Date.now()}.mp4`;
      const r2Mp4Result = await cloudflareR2Service.uploadFileToR2(absoluteVideoPath, mp4Key, 'video/mp4');

      // Cleanup temp files
      if (isRemoteFile) {
          await cloudflareR2Service.cleanupLocalFile(absoluteVideoPath);
      }

      // Cleanup HLS output dir
      if (fs.existsSync(hlsResult.outputDir)) {
          fs.rmSync(hlsResult.outputDir, { recursive: true, force: true });
      }
      
      return {
        success: true,
        videoUrl: r2HLSResult.playlistUrl,
        thumbnailUrl: r2ThumbnailUrl || '',
        canonicalMp4Url: r2Mp4Result.url,
        canonicalMp4Key: mp4Key,
        format: 'HLS (Adaptive Stream)',
        quality: `${originalVideoInfo.height}p (balanced)`,
        storage: 'Cloudflare R2',
        bandwidth: 'FREE Forever',
        size: stats.size, // Size from stats
        processing: 'Local FFmpeg (100% FREE)',
        duration: originalVideoInfo.duration,
        width: originalVideoInfo.width,
        height: originalVideoInfo.height,
        aspectRatio: originalVideoInfo.aspectRatio,
        originalVideoInfo: originalVideoInfo
      };
      
    } catch (error) {
      console.error('❌ Video processing error:', error);
      try {
        await cloudflareR2Service.cleanupTempDirectory();
        
        // **NEW: Cleanup HLS output dir on error if it was created**
        if (typeof hlsResult !== 'undefined' && hlsResult && hlsResult.outputDir && fs.existsSync(hlsResult.outputDir)) {
          fs.rmSync(hlsResult.outputDir, { recursive: true, force: true });
        }
        
        // **NEW: Cleanup local source file on error if it's a temp file**
        if (absoluteVideoPath && !isRemoteFile && absoluteVideoPath.includes('uploads')) {
          if (fs.existsSync(absoluteVideoPath)) fs.unlinkSync(absoluteVideoPath);
        }
      } catch (cleanupError) {
        console.warn('⚠️ Post-error cleanup failed:', cleanupError.message);
      }
      throw new Error(`Video processing failed: ${error.message}`);
    }
  }

  /**
   * Get original video information including aspect ratio
   */
  async getOriginalVideoInfo(videoPath) {
    try {
      // Lazy load the service to ensure dependencies are ready
      const { getVideoMetadata } = await import('../yugFeedServices/videoMetadataService.js');
      
      const metadata = await getVideoMetadata(videoPath);
      
      console.log('📊 Original video info (via videoMetadataService):', {
        width: metadata.width,
        height: metadata.height,
        duration: metadata.duration,
        aspectRatio: metadata.aspectRatio
      });

      return metadata;

    } catch (error) {
      console.log('⚠️ Error getting original video info, using fallback:', error.message);
      // Return fallback video info on any error
      return {
        width: 720,
        height: 1280,
        aspectRatio: 9/16,
        duration: 30,
        codec: 'unknown',
        format: 'mp4',
        isPortrait: true,
        isLandscape: false
      };
    }
  }

  /**
   * Validate video file before processing
   */
  async validateVideo(videoPath) {
    try {
      // Basic file existence check
      const fs = await import('fs');
      if (!fs.existsSync(videoPath)) {
        throw new Error('Video file not found');
      }

      // Check file size (max 700MB)
      const stats = fs.statSync(videoPath);
      const fileSizeInMB = stats.size / (1024 * 1024);
      
      if (fileSizeInMB > 700) {
        throw new Error('Video file too large (max 700MB)');
      }

      // Check file extension
      const allowedExtensions = ['.mp4', '.mov', '.avi', '.mkv', '.webm'];
      const fileExtension = path.extname(videoPath).toLowerCase();
      
      if (!allowedExtensions.includes(fileExtension)) {
        throw new Error(`Unsupported video format: ${fileExtension}`);
      }

      return {
        isValid: true,
        size: stats.size,
        sizeInMB: fileSizeInMB,
        format: fileExtension.substring(1),
        path: videoPath
      };
      
    } catch (error) {
      return {
        isValid: false,
        error: error.message
      };
    }
  }

  /**
   * Get processing cost estimate
   */
  getCostEstimate(videoSizeInMB, expectedViews = 1000) {
    const streamProcessingCost = 0; // FREE! Cloudflare Stream transcoding is free
    const hlsProcessingCost = 0; // FREE! Local FFmpeg processing
    const r2StorageCostPerGB = 0.015; // $0.015 per GB per month
    const r2BandwidthCost = 0; // FREE!
    
    const storageCostPerMonth = (videoSizeInMB / 1024) * r2StorageCostPerGB;
    const totalCostPerMonth = streamProcessingCost + storageCostPerMonth;
    
    return {
      processing: streamProcessingCost, // FREE with Stream!
      processingFallback: hlsProcessingCost, // FREE with local FFmpeg!
      storagePerMonth: storageCostPerMonth,
      bandwidth: r2BandwidthCost,
      totalPerMonth: totalCostPerMonth,
      savingsVsCurrent: '100%',
      currency: 'USD'
    };
  }

  /**
   * **NEW: Pure HLS Processing - 100% FREE!**
   * Upload → FFmpeg (Local, FREE) → HLS (.m3u8 + .ts) → R2 (FREE bandwidth)
   * Single quality (original or 1080p max)
   */
  async processVideoToHLS(videoPath, videoName, userId, options = {}) {
    const { onProgress = null, videoId: mongoVideoId = null } = options;
    
    try {
      console.log('🚀 Starting Pure HLS Processing (FFmpeg → R2)...');
      console.log('💰 Cost: $0 processing + $0.015/GB storage + $0 bandwidth = 100% FREE!');
      
      // Step 1: Validate video
      const validation = await this.validateVideo(videoPath);
      if (!validation.isValid) {
        throw new Error(`Video validation failed: ${validation.error}`);
      }
      
      // Step 2: Get original video info to preserve aspect ratio
      console.log('📊 Getting original video dimensions...');
      const originalVideoInfo = await this.getOriginalVideoInfo(videoPath);
      
      // **NEW STEP 3: Generate and Upload Thumbnail EARLY**
      // This ensures the user sees something immediately, even if HLS takes time
      console.log('📸 [Step 3/6] Generating thumbnail early...');
      let thumbnailUrl = '';
      try {
        const thumbnailPath = await this.generateThumbnailWithFFmpeg(videoPath, videoName, userId);
        if (thumbnailPath) {
          thumbnailUrl = await this.uploadThumbnailImageToR2(thumbnailPath, videoName, userId);
          console.log(`✅ Early Thumbnail uploaded: ${thumbnailUrl}`);
          
          // Update DB immediately if videoId provided
          if (mongoVideoId) {
             const Video = (await import('../../models/Video.js')).default;
             await Video.findByIdAndUpdate(mongoVideoId, { 
               thumbnailUrl,
               processingProgress: 20 
             });
          }
          
          if (fs.existsSync(thumbnailPath)) fs.unlinkSync(thumbnailPath);
        }
      } catch (thumbError) {
        console.warn('⚠️ Early thumbnail step failed (non-fatal):', thumbError.message);
      }

      // Step 4: Use LOCAL FFmpeg to create HLS segments
      console.log('🎬 [Step 4/6] Converting to HLS with FFmpeg (original aspect ratio)...');
      const videoId = `${videoName}_${Date.now()}`;
      
      const hlsResult = await hlsEncodingService.convertToHLS(
        videoPath,
        videoId,
        {
          quality: 'medium',
          codec: 'h265',
          originalVideoInfo: originalVideoInfo,
          onProgress: (percent) => {
            // Map 0-100% of encoding to 20-80% of total progress
            const mappedPercent = 20 + Math.round(percent * 0.6);
            if (onProgress) onProgress(mappedPercent);
          }
        }
      );
      
      // Step 5: Upload ALL HLS files to R2 (playlist + segments)
      console.log('📤 [Step 5/6] Uploading HLS directory to R2...');
      if (onProgress) onProgress(85);
      
      const r2HLSResult = await cloudflareR2Service.uploadHLSDirectoryToR2(
        hlsResult.outputDir,
        videoId,
        userId
      );
      
      // Step 6: Cleanup local files
      console.log('🧹 [Step 6/6] Cleaning up local files...');
      if (onProgress) onProgress(95);
      await this.cleanupLocalFiles(videoPath, hlsResult.outputDir, null);

      return {
        success: true,
        videoUrl: r2HLSResult.playlistUrl,
        thumbnailUrl: thumbnailUrl,
        format: 'HLS (HTTP Live Streaming)',
        segments: r2HLSResult.segments,
        totalFiles: r2HLSResult.totalFiles,
        storage: 'Cloudflare R2',
        bandwidth: 'FREE Forever',
        processing: 'Local FFmpeg (FREE)',
        hlsPlaylistUrl: r2HLSResult.playlistUrl,
        isHLSEncoded: true,
        duration: originalVideoInfo.duration || 0,
        aspectRatio: originalVideoInfo.aspectRatio,
        width: originalVideoInfo.width,
        height: originalVideoInfo.height,
        originalVideoInfo: originalVideoInfo
      };
      
    } catch (error) {
      console.error('❌ Pure HLS processing error:', error);
      
      // Cleanup on error
      try {
        await cloudflareR2Service.cleanupTempDirectory();
        if (typeof hlsResult !== 'undefined' && hlsResult && hlsResult.outputDir && fs.existsSync(hlsResult.outputDir)) {
           fs.rmSync(hlsResult.outputDir, { recursive: true, force: true });
        }
        if (videoPath && fs.existsSync(videoPath) && videoPath.includes('uploads')) {
           fs.unlinkSync(videoPath);
        }
      } catch (cleanupError) {
        console.warn('⚠️ Cleanup error:', cleanupError);
      }
      
      throw new Error(`Pure HLS processing failed: ${error.message}`);
    }
  }

  /**
   * Generate thumbnail using FFmpeg (FREE, local processing)
   */
  /**
   * Generate thumbnail using FFmpeg (FREE, local processing)
   * Uses ffmpeg-static for reliable execution
   */
  async generateThumbnailWithFFmpeg(videoPath, videoName, userId) {
    return new Promise(async (resolve, reject) => {
      try {
        // **FIX: Verify video file exists before generating thumbnail**
        const absoluteVideoPath = path.resolve(videoPath);
        const fs = await import('fs');
        if (!fs.existsSync(absoluteVideoPath)) {
          console.error(`❌ Video file not found for thumbnail generation: ${absoluteVideoPath}`);
          resolve(null);
          return;
        }
        
        console.log('📸 Starting thumbnail generation for video:', videoName);
        console.log(`   Video file: ${absoluteVideoPath}`);
        
        // **FIX: Robust FFmpeg Path Selection (Same as hlsEncodingService)**
        let ffmpegPath = null;
        try {
            const ffmpegStatic = (await import('ffmpeg-static')).default;
            ffmpegPath = ffmpegStatic;
            console.log('wrench HybridVideoService: Using static FFmpeg at:', ffmpegPath);
        } catch (e) {
            console.error('❌ HybridVideoService: Failed to load ffmpeg-static:', e);
            // Fallback to system ffmpeg if static fails
            ffmpegPath = 'ffmpeg';
        }

        const ffmpeg = (await import('fluent-ffmpeg')).default;
        if (ffmpegPath) ffmpeg.setFfmpegPath(ffmpegPath);
          
        const tempDir = path.join(process.cwd(), 'temp');
        if (!fs.existsSync(tempDir)) {
          fs.mkdirSync(tempDir, { recursive: true });
        }
          
        // **FIX: Use unique filename to avoid conflicts and SANITIZE**
        const uniqueId = `${userId}_${Date.now()}_${Math.random().toString(36).substring(7)}`;
        const sanitizedVideoName = cloudflareR2Service.sanitizeKey(videoName);
        const thumbnailPath = path.join(tempDir, `${sanitizedVideoName}_thumb_${uniqueId}.jpg`);
        const thumbnailFilename = path.basename(thumbnailPath);
        
        console.log(`🎬 FFmpeg taking screenshot of: ${absoluteVideoPath}`);

        ffmpeg(absoluteVideoPath)
          .screenshots({
            count: 1,
            timestamps: ['10%'], // Take thumbnail at 10% mark
            filename: thumbnailFilename,
            folder: tempDir,
            size: '640x?' // Better resolution for thumbnails
          })
          .on('end', () => {
            console.log(`✅ Thumbnail generated successfully at 10%: ${thumbnailPath}`);
            resolve(thumbnailPath);
          })
          .on('error', (err) => {
            console.error('❌ Thumbnail generation failed at 10%:', err.message);
            
            // **ROBUST FALLBACK: Try at 00:00:01 if percentage fails**
            console.log('🔄 Retrying thumbnail generation at 00:00:01...');
            ffmpeg(absoluteVideoPath)
              .screenshots({
                count: 1,
                timestamps: ['00:00:01'],
                filename: thumbnailFilename,
                folder: tempDir,
                size: '640x?'
              })
              .on('end', () => {
                console.log(`✅ Thumbnail generated (fallback 1s) at: ${thumbnailPath}`);
                resolve(thumbnailPath);
              })
              .on('error', (fallbackErr) => {
                console.error('❌ Thumbnail fallback also failed:', fallbackErr.message);
                resolve(null);
              });
          });
          
      } catch (error) {
        console.log('⚠️ Thumbnail generation error, skipping thumbnail:', error.message);
        resolve(null);
      }
    });
  }

  /**
   * Upload thumbnail image file to R2
   */
  async uploadThumbnailImageToR2(thumbnailPath, videoName, userId) {
    try {
      const sanitizedName = cloudflareR2Service.sanitizeKey(videoName);
      const key = `thumbnails/${userId}/${sanitizedName}_thumb_${Date.now()}.jpg`;
      
      const result = await cloudflareR2Service.uploadFileToR2(
        thumbnailPath,
        key,
        'image/jpeg'
      );
      
      return result.url;
      
    } catch (error) {
      console.error('❌ Error uploading thumbnail to R2:', error);
      throw error;
    }
  }

  /**
   * Clean up local files after processing
   */
  async cleanupLocalFiles(videoPath, hlsOutputDir, thumbnailPath) {
    try {
      // Delete original video file
      if (fs.existsSync(videoPath)) {
        fs.unlinkSync(videoPath);
        console.log('🧹 Cleaned up original video:', videoPath);
      }
      
      // Delete HLS output directory
      if (fs.existsSync(hlsOutputDir)) {
        fs.rmSync(hlsOutputDir, { recursive: true, force: true });
        console.log('🧹 Cleaned up HLS directory:', hlsOutputDir);
      }
      
      // Delete thumbnail file
      if (thumbnailPath && fs.existsSync(thumbnailPath)) {
        fs.unlinkSync(thumbnailPath);
        console.log('🧹 Cleaned up thumbnail:', thumbnailPath);
      }
      
      console.log('✅ Local cleanup completed');
      
    } catch (error) {
      console.warn('⚠️ Error during local cleanup:', error);
      // Don't throw error - cleanup is not critical
    }
  }
}

export default new HybridVideoService();
