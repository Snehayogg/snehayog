import cloudflareR2Service from './cloudflareR2Service.js';
import cloudflareStreamService from './cloudflareStreamService.js';
import hlsEncodingService from './hlsEncodingService.js';
import path from 'path';
import fs from 'fs';

class HybridVideoService {
  constructor() {
    // HybridVideoService: Using Cloudflare Stream (FREE transcoding) with HLS fallback
    console.log('☁️ HybridVideoService: Initialized');
    console.log('   Primary: Cloudflare Stream (FREE transcoding)');
    console.log('   Fallback: Local FFmpeg HLS encoding');
  }

  /**
   * Hybrid Processing: Cloudflare Stream (FREE Transcoding) → R2 (Storage + FREE Bandwidth)
   * 100% FREE transcoding! Falls back to local FFmpeg HLS if Stream fails.
   */
  async processVideoHybrid(videoId, videoPath, videoName, userId) {
    try {
      console.log('🚀 Starting Hybrid Processing (Cloudflare Stream → R2)...');
      console.log('🆔 Video ID:', videoId);
      console.log('💰 FREE transcoding with Cloudflare Stream!');
      console.log('📁 Video path:', videoPath);
      console.log('📝 Video name:', videoName);
      console.log('👤 User ID:', userId);
      
      // **FIX: Verify video file exists and is accessible before processing**
      // **NEW: Handle Remote URLs (Direct Upload)**
      let absoluteVideoPath;
      let isRemoteFile = false;

      if (videoPath.startsWith('http')) {
        console.log('🌐 Remote video detected (Direct Upload). Downloading to local temp...');
        isRemoteFile = true;
        
        // Lazy load axios/fs if needed (already imported at top of file?)
        // Let's rely on cloudflareR2Service.downloadFromCloudinary which effectively downloads a URL
        // We can reuse that or create a simple download helper here. 
        // Actually, let's use a new helper to download ANY url.

        const tempDir = path.join(process.cwd(), 'temp');
        if (!fs.existsSync(tempDir)) fs.mkdirSync(tempDir, { recursive: true });
        
        const tempFileName = `raw_${userId}_${Date.now()}.mp4`;
        const tempFilePath = path.join(tempDir, tempFileName);

        // Download logic
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
      console.log('📊 Video file modified:', new Date(stats.mtime).toISOString());
      
      console.log('📁 Absolute video path:', absoluteVideoPath);

      // **SAFE EARLY THUMBNAIL GENERATION**
      // We generate the thumbnail before the slow encoding starts.
      let r2ThumbnailUrl = '';
      try {
        console.log('📸 Generating thumbnail early for immediate display...');
        const thumbnailPath = await this.generateThumbnailWithFFmpeg(absoluteVideoPath, videoName, userId);
        if (thumbnailPath) {
          console.log('📤 Uploading early thumbnail to R2...');
          r2ThumbnailUrl = await this.uploadThumbnailImageToR2(thumbnailPath, videoName, userId);
          console.log(`✅ Early thumbnail uploaded: ${r2ThumbnailUrl}`);
          
          // Safe Database Update: So users see the thumbnail immediately after refresh
          try {
            const Video = (await import('../models/Video.js')).default;
            // DIRECT UPDATE: Use videoId for 100% reliability
            const videoRecord = await Video.findById(videoId);
            if (videoRecord) {
              videoRecord.thumbnailUrl = r2ThumbnailUrl;
              await videoRecord.save();
              console.log('💾 Early Video record updated in DB with videoId:', videoId);
            } else {
              console.warn('⚠️ Could not find video record early with videoId:', videoId);
            }
          } catch (dbError) {
              console.warn('⚠️ Safe DB update failed (non-critical):', dbError.message);
          }

          // Cleanup local thumbnail
          if (fs.existsSync(thumbnailPath)) fs.unlinkSync(thumbnailPath);
        }
      } catch (thumbError) {
        console.warn('⚠️ Early thumbnail step failed (continuing to video processing):', thumbError.message);
      }
      
      let processingResult;
      
      // **SMART BYPASS: Detect if video is already pre-optimized by frontend**
      console.log('📊 Getting original video info to check for "The Loophole"...');
      const originalVideoInfo = await this.getOriginalVideoInfo(absoluteVideoPath);
      
      const isPreOptimized = originalVideoInfo.height <= 480 && 
                            (originalVideoInfo.codec === 'h264' || originalVideoInfo.codec === 'h265' || originalVideoInfo.codec === 'hevc');

      if (isPreOptimized) {
        console.log('🎯 THE LOOPHOLE FOUND: Video is already pre-optimized (480p)!');
        console.log('⚡ Bypassing Cloudflare Stream for INSTANT local packaging...');
        
        const videoId = `${videoName}_${Date.now()}`;
        const hlsResult = await hlsEncodingService.convertToHLS(absoluteVideoPath, videoId, {
          quality: 'medium',
          resolution: '480p',
          copyVideo: true, // INSTANT!
          copyAudio: false, // Re-encode audio to ensure AAC compatibility
          originalVideoInfo: originalVideoInfo
        });

        processingResult = {
          videoUrl: hlsResult.playlistUrl,
          thumbnailUrl: r2ThumbnailUrl || '',
          streamVideoId: null,
          duration: originalVideoInfo.duration || 0,
          size: originalVideoInfo.size || 0,
          format: 'HLS (Stream Copy)',
          originalVideoInfo: originalVideoInfo,
          aspectRatio: originalVideoInfo.aspectRatio,
          width: originalVideoInfo.width,
          height: originalVideoInfo.height,
          isPortrait: originalVideoInfo.aspectRatio < 1.0,
          outputDir: hlsResult.outputDir,
          localPath: null
        };
      } else {
        // Step 1: Process video to 480p using Cloudflare Stream (FREE transcoding!)
        console.log('☁️ Step 1: Processing with Cloudflare Stream (FREE transcoding)...');
        let streamVideoId = null;
        
        try {
          console.log('⏱️ Starting Cloudflare Stream processing at:', new Date().toISOString());
          processingResult = await this.processWithCloudflareStream(videoId, absoluteVideoPath, videoName, userId);
          streamVideoId = processingResult.streamVideoId;
        } catch (streamError) {
          console.error('❌ Cloudflare Stream processing failed:', streamError.message);
          console.log('🔄 Falling back to Pure HLS Processing (FFmpeg → R2)...');
          
          const hlsFallbackResult = await hlsEncodingService.convertToHLS(absoluteVideoPath, `${videoName}_${Date.now()}`, {
            quality: 'medium',
            resolution: '480p',
            codec: 'h265',
            originalVideoInfo: originalVideoInfo
          });
          
          processingResult = {
            videoUrl: hlsFallbackResult.playlistUrl,
            thumbnailUrl: r2ThumbnailUrl || hlsFallbackResult.thumbnailUrl || '',
            streamVideoId: null,
            duration: originalVideoInfo.duration || 0,
            size: hlsFallbackResult.size || 0,
            format: 'HLS',
            originalVideoInfo: originalVideoInfo,
            aspectRatio: originalVideoInfo.aspectRatio,
            width: originalVideoInfo.width,
            height: originalVideoInfo.height,
            isPortrait: originalVideoInfo.aspectRatio < 1.0,
            outputDir: hlsFallbackResult.outputDir,
            localPath: null
          };
        }
      }
      
      // Step 2: Handle video processing result based on processing method
      let r2VideoResult, localVideoPath; // r2ThumbnailUrl is now declared earlier
      
      if (processingResult.streamVideoId && processingResult.localPath) {
        // Cloudflare Stream processing was successful
        console.log('📥 Using processed video from Cloudflare Stream...');
        localVideoPath = processingResult.localPath;
        
        // Step 3: Upload 480p video to Cloudflare R2 (FREE bandwidth!)
        console.log('⏱️ Starting R2 video upload at:', new Date().toISOString());
        r2VideoResult = await cloudflareR2Service.uploadVideoToR2(
          localVideoPath, 
          videoName, 
          userId
        );
        console.log('✅ R2 video upload completed at:', new Date().toISOString());
        
        // Step 4: Get thumbnail from Stream and upload to R2 if we don't have one yet
        if (!r2ThumbnailUrl) {
          console.log('📸 Getting thumbnail from Cloudflare Stream...');
          const streamThumbnailUrl = await cloudflareStreamService.getThumbnailUrl(processingResult.streamVideoId);
          
          if (streamThumbnailUrl) {
            console.log('⏱️ Starting R2 thumbnail upload at:', new Date().toISOString());
            r2ThumbnailUrl = await cloudflareR2Service.uploadThumbnailToR2(
              streamThumbnailUrl, 
              videoName, 
              userId
            );
            console.log('✅ R2 thumbnail upload completed at:', new Date().toISOString());
          }
        }
      } else {
        // HLS processing fallback was used
        console.log('📥 Using HLS processing result directly...');
        
        // Upload HLS files to R2
        const hlsResult = await cloudflareR2Service.uploadHLSDirectoryToR2(
          processingResult.outputDir, 
          videoName, 
          userId
        );
        
        r2VideoResult = {
          url: hlsResult.playlistUrl,
          key: hlsResult.playlistKey,
          size: 0, // HLS size calculation would be complex
          format: 'hls'
        };
        
        localVideoPath = null; // No local file for HLS processing
      }
      
      // Step 5: **DELETE FROM CLOUDFLARE STREAM** to avoid storage costs!
      const finalStreamVideoId = processingResult.streamVideoId;
      if (finalStreamVideoId) {
        console.log('🗑️ Deleting video from Cloudflare Stream (no longer needed)...');
        try {
          await cloudflareStreamService.deleteVideo(finalStreamVideoId);
          console.log('✅ Video deleted from Cloudflare Stream successfully');
          console.log('💰 Cost saved: Stream storage charges avoided');
        } catch (deleteError) {
          console.warn('⚠️ Failed to delete video from Stream:', deleteError.message);
          console.warn('   Manual cleanup recommended to avoid storage costs');
        }
      }
      
      // Step 6: Cleanup temp files
      if (localVideoPath) {
        await cloudflareR2Service.cleanupLocalFile(localVideoPath);
      }
      // **FIX: Use absolute path for cleanup to ensure correct file is deleted**
      // If it was a remote file, we MUST delete the temp downloaded file.
      // If it was a local upload (legacy), uploadRoutes handles cleanup usually, 
      // but if we are here, we might want to clean it up depending on who owns it.
      // For now, let's strictly clean up if we created the temp file (remote flow).
      
      if (isRemoteFile) {
          await cloudflareR2Service.cleanupLocalFile(absoluteVideoPath);
          console.log('🧹 Cleaned up downloaded remote file:', absoluteVideoPath);
      } else {
         // Existing logic: cleanup if it was passed in? 
         // Usually uploadRoutes cleans up req.file.path. 
         // Let's leave legacy behavior mostly alone but safe.
         // await cloudflareR2Service.cleanupLocalFile(absoluteVideoPath);
      }
      
      console.log('🎉 Hybrid processing completed successfully!');
      console.log('📊 Cost breakdown:');
      console.log('   - Cloudflare Stream transcoding: $0 (FREE!)');
      console.log('   - Stream storage: $0 (deleted after transfer)');
      console.log('   - R2 storage: ~$0.015/GB/month');
      console.log('   - R2 bandwidth: $0 (FREE forever!)');
      console.log('   - Total: 100% FREE transcoding!');
      
      return {
        success: true,
        videoUrl: r2VideoResult.url,
        thumbnailUrl: r2ThumbnailUrl,
        format: finalStreamVideoId ? 'MP4 with Progressive Loading' : 'HLS (HTTP Live Streaming)',
        quality: originalVideoInfo ? `${originalVideoInfo.height}p (original preserved)` : 'original',
        storage: 'Cloudflare R2',
        bandwidth: 'FREE Forever',
        size: r2VideoResult.size,
        processing: finalStreamVideoId ? 'Cloudflare Stream → R2 Hybrid' : 'HLS → R2',
        costSavings: '100% FREE transcoding',
        // **NEW: Include original resolution in result**
        width: originalVideoInfo?.width,
        height: originalVideoInfo?.height,
        aspectRatio: originalVideoInfo?.aspectRatio,
        originalVideoInfo: originalVideoInfo
      };
      
    } catch (error) {
      console.error('❌ Hybrid processing error:', error);
      
      // Cleanup on error
      try {
        await cloudflareR2Service.cleanupTempDirectory();
      } catch (cleanupError) {
        console.warn('⚠️ Cleanup error:', cleanupError);
      }
      
      throw new Error(`Hybrid processing failed: ${error.message}`);
    }
  }

  /**
   * Process video to single 480p quality using Cloudflare Stream (FREE transcoding!)
   */
  async processWithCloudflareStream(videoId, videoPath, videoName, userId) {
    try {
      console.log('☁️ Processing video with Cloudflare Stream (FREE transcoding)...');
      
      // Upload to Stream and wait for transcoding
      const streamResult = await cloudflareStreamService.uploadAndTranscode(
        videoPath,
        videoName,
        userId
      );
      
      console.log('✅ Cloudflare Stream processing completed');
      console.log('🔗 Processed video ID:', streamResult.videoId);
      console.log('📊 Video processing summary:');
      console.log(`   - Dimensions: ${streamResult.width}x${streamResult.height}`);
      console.log(`   - Aspect ratio: ${streamResult.aspectRatio}`);
      console.log('   - Quality: 480p (auto-transcoded)');
      console.log('   - Cost: $0 (FREE transcoding!)');
      
      return {
        videoUrl: streamResult.videoUrl,
        thumbnailUrl: streamResult.thumbnailUrl || '',
        streamVideoId: streamResult.videoId,
        duration: streamResult.duration,
        size: streamResult.size,
        format: streamResult.format,
        originalVideoInfo: streamResult.originalVideoInfo,
        aspectRatio: streamResult.aspectRatio,
        width: streamResult.width,
        height: streamResult.height,
        isPortrait: streamResult.isPortrait,
        localPath: streamResult.localPath
      };
      
    } catch (error) {
      console.error('❌ Cloudflare Stream processing error:', error);
      throw new Error(`Cloudflare Stream processing failed: ${error.message}`);
    }
  }

  /**
   * Get original video information including aspect ratio
   */
  async getOriginalVideoInfo(videoPath) {
    try {
      // Lazy load the service to ensure dependencies are ready
      const { getVideoMetadata } = await import('./videoMetadataService.js');
      
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

      // Check file size (max 100MB for cost optimization)
      const stats = fs.statSync(videoPath);
      const fileSizeInMB = stats.size / (1024 * 1024);
      
      if (fileSizeInMB > 100) {
        throw new Error('Video file too large (max 100MB for cost optimization)');
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
   * Single 480p quality only for cost optimization
   */
  async processVideoToHLS(videoPath, videoName, userId) {
    try {
      console.log('🚀 Starting Pure HLS Processing (FFmpeg → R2)...');
      console.log('💰 Cost: $0 processing + $0.015/GB storage + $0 bandwidth = 100% FREE!');
      console.log('📹 Quality: Single 480p (no multiple qualities)');
      
      // Step 1: Validate video
      const validation = await this.validateVideo(videoPath);
      if (!validation.isValid) {
        throw new Error(`Video validation failed: ${validation.error}`);
      }
      
      // **FIX: Get original video info to preserve aspect ratio**
      console.log('📊 Getting original video dimensions...');
      const originalVideoInfo = await this.getOriginalVideoInfo(videoPath);
      console.log('📊 Original video info:', {
        width: originalVideoInfo.width,
        height: originalVideoInfo.height,
        aspectRatio: originalVideoInfo.aspectRatio
      });
      
      // Step 2: Use LOCAL FFmpeg to create HLS segments (preserves original aspect ratio)
      console.log('🎬 Converting to HLS with FFmpeg (preserving original aspect ratio)...');
      const videoId = `${videoName}_${Date.now()}`;
      const hlsResult = await hlsEncodingService.convertToHLS(
        videoPath,
        videoId,
        {
          quality: 'medium',    // 480p quality preset
          resolution: '480p',   // Max height 480p (aspect ratio preserved)
          segmentDuration: 3,   // 3-second segments for fast startup
          codec: 'h265',        // Enable H.265 for ~50% bandwidth savings
          originalVideoInfo: originalVideoInfo // Pass original info for aspect ratio preservation
        }
      );
      
      console.log('✅ HLS conversion completed:');
      console.log(`   Segments: ${hlsResult.segments}`);
      console.log(`   Playlist: ${hlsResult.playlistPath}`);
      console.log(`   Output Dir: ${hlsResult.outputDir}`);
      
      // Step 3: Upload ALL HLS files to R2 (playlist + segments)
      console.log('📤 Uploading HLS files to R2...');
      const r2HLSResult = await cloudflareR2Service.uploadHLSDirectoryToR2(
        hlsResult.outputDir,
        videoId,
        userId
      );
      
      console.log(`✅ Uploaded ${r2HLSResult.totalFiles} HLS files to R2`);
      console.log(`   Playlist URL: ${r2HLSResult.playlistUrl}`);
      console.log(`   Segments: ${r2HLSResult.segments}`);
      
      // Step 4: Generate thumbnail using FFmpeg (optional)
      console.log('📸 Generating thumbnail...');
      const thumbnailPath = await this.generateThumbnailWithFFmpeg(videoPath, videoName, userId);
      
      // Step 5: Upload thumbnail to R2 (if generated)
      let thumbnailUrl = '';
      if (thumbnailPath) {
        thumbnailUrl = await this.uploadThumbnailImageToR2(
          thumbnailPath,
          videoName,
          userId
        );
        console.log(`✅ Thumbnail uploaded: ${thumbnailUrl}`);
      } else {
        console.log('⚠️ No thumbnail generated, using default');
        thumbnailUrl = 'https://via.placeholder.com/320x180/000000/FFFFFF?text=Video+Thumbnail';
      }
      
      // Step 6: Cleanup local files
      console.log('🧹 Cleaning up local files...');
      await this.cleanupLocalFiles(videoPath, hlsResult.outputDir, thumbnailPath);
      
      console.log('🎉 Pure HLS processing completed successfully!');
      console.log('📊 Cost breakdown:');
      console.log('   - FFmpeg processing: $0 (local, FREE!)');
      console.log('   - R2 storage: ~$0.015/GB/month');
      console.log('   - R2 bandwidth: $0 (FREE forever!)');
      console.log('   - Total: 100% FREE processing!');
      
      return {
        success: true,
        videoUrl: r2HLSResult.playlistUrl,
        thumbnailUrl: thumbnailUrl,
        format: 'HLS (HTTP Live Streaming)',
        quality: '480p (max height, aspect ratio preserved)',
        segments: r2HLSResult.segments,
        totalFiles: r2HLSResult.totalFiles,
        storage: 'Cloudflare R2',
        bandwidth: 'FREE Forever',
        processing: 'Local FFmpeg (FREE)',
        costSavings: '100% vs any cloud processing',
        hlsPlaylistUrl: r2HLSResult.playlistUrl,
        isHLSEncoded: true,
        // **FIX: Include original video dimensions to preserve aspect ratio**
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
          
        // **FIX: Use unique filename to avoid conflicts**
        const uniqueId = `${userId}_${Date.now()}_${Math.random().toString(36).substring(7)}`;
        const thumbnailPath = path.join(tempDir, `${videoName}_thumb_${uniqueId}.jpg`);
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
      const key = `thumbnails/${userId}/${videoName}_thumb_${Date.now()}.jpg`;
      
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
