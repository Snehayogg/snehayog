import { S3Client, PutObjectCommand, DeleteObjectCommand } from '@aws-sdk/client-s3';
import axios from 'axios';
import fs from 'fs';
import path from 'path';

class CloudflareR2Service {
  constructor() {
    this.accountId = process.env.CLOUDFLARE_ACCOUNT_ID;
    this.bucketName = process.env.CLOUDFLARE_R2_BUCKET_NAME;
    
    // **NEW: Support custom domain (cdn.snehayog.com) for public URLs**
    this.publicDomain = process.env.CLOUDFLARE_R2_PUBLIC_DOMAIN || null;
    
    console.log('🔧 Cloudflare R2 Service Configuration:');
    console.log('   Account ID:', this.accountId ? '✓ Set' : '✗ Missing');
    console.log('   Bucket Name:', this.bucketName ? '✓ Set' : '✗ Missing');
    console.log('   Custom Domain:', this.publicDomain ? `✓ ${this.publicDomain}` : '⚠ Using direct R2 URLs');
    
    // S3-compatible client for Cloudflare R2
    this.s3Client = new S3Client({
      region: 'auto',
      endpoint: `https://${this.accountId}.r2.cloudflarestorage.com`,
      credentials: {
        accessKeyId: process.env.CLOUDFLARE_R2_ACCESS_KEY_ID,
        secretAccessKey: process.env.CLOUDFLARE_R2_SECRET_ACCESS_KEY,
      },
    });
  }

  /**
   * Get public URL for an R2 object key
   * Uses custom domain (cdn.snehayog.site) if configured, otherwise direct R2 URL
   */
  getPublicUrl(key) {
    // **FIX: Normalize key path to use forward slashes**
    const normalizedKey = key.replace(/\\/g, '/');
    
    if (this.publicDomain) {
      // Use custom domain with HTTPS
      const cleanDomain = this.publicDomain.replace(/^https?:\/\//, '').replace(/\/$/, '');
      const url = `https://${cleanDomain}/${normalizedKey}`;
      console.log('🔗 Generated custom domain URL:', url);
      return url;
    }

    // Fallback to direct R2 URL if custom domain not set
    const directR2Url = `https://${this.bucketName}.${this.accountId}.r2.cloudflarestorage.com/${normalizedKey}`;
    console.log('🔗 Generated direct R2 URL (fallback):', directR2Url);
    return directR2Url;
  }

  /**
   * Download video from Cloudinary URL
   */
  async downloadFromCloudinary(cloudinaryUrl, fileName) {
    try {
      console.log('📥 Downloading processed video from Cloudinary...');
      
      const tempDir = path.join(process.cwd(), 'temp');
      if (!fs.existsSync(tempDir)) {
        fs.mkdirSync(tempDir, { recursive: true });
      }
      
      // Sanitize fileName to remove invalid characters for Windows
      const sanitizedFileName = fileName.replace(/[<>:"/\\|?*]/g, '_').replace(/:/g, '-');
      const localPath = path.join(tempDir, `${sanitizedFileName}_480p.mp4`);
      
      console.log('📥 Starting download from:', cloudinaryUrl);
      const response = await axios({
        method: 'GET',
        url: cloudinaryUrl,
        responseType: 'stream',
        timeout: 5 * 60 * 1000 // 5 minutes timeout
      });
      
      const writer = fs.createWriteStream(localPath);
      response.data.pipe(writer);
      
      return new Promise((resolve, reject) => {
        // Set up timeout for the download
        const timeout = setTimeout(() => {
          writer.destroy();
          reject(new Error('Download timeout after 5 minutes'));
        }, 5 * 60 * 1000);
        
        writer.on('finish', () => {
          clearTimeout(timeout);
          console.log('✅ Video downloaded from Cloudinary');
          resolve(localPath);
        });
        writer.on('error', (error) => {
          clearTimeout(timeout);
          reject(error);
        });
      });
      
    } catch (error) {
      console.error('❌ Error downloading from Cloudinary:', error);
      throw error;
    }
  }

  /**
   * Upload video file to Cloudflare R2 (S3-compatible)
   * Returns custom domain URL (cdn.snehayog.com) if configured
   */
  async uploadVideoToR2(filePath, fileName, userId) {
    try {
      console.log('📤 Uploading video to Cloudflare R2 (S3-compatible)...');
      
      const fileContent = fs.readFileSync(filePath);
      const key = `videos/${userId}/${fileName}_480p_${Date.now()}.mp4`;
      
      const command = new PutObjectCommand({
        Bucket: this.bucketName,
        Key: key,
        Body: fileContent,
        ContentType: 'video/mp4',
        CacheControl: 'public, max-age=31536000', // 1 year cache
        Metadata: {
          'video-quality': '480p',
          'processed-by': 'cloudinary-hybrid',
          'uploaded-by': userId,
          'upload-date': new Date().toISOString()
        }
      });
  
      await this.s3Client.send(command);
      
      // **USE CUSTOM DOMAIN** (cdn.snehayog.com) for public URL
      const publicUrl = this.getPublicUrl(key);
      console.log('✅ Video uploaded to R2');
      console.log('   Key:', key);
      console.log('   Public URL:', publicUrl);
      console.log('   🎉 FREE bandwidth delivery via Cloudflare R2!');
      
      return {
        url: publicUrl,
        key: key,
        size: fileContent.length,
        format: 'mp4',
        quality: '480p'
      };
      
    } catch (error) {
      console.error('❌ Error uploading to R2:', error);
      throw error;
    }
  }

  /**
   * Upload thumbnail to R2 (S3-compatible)
   * Returns custom domain URL (cdn.snehayog.com) if configured
   */
  async uploadThumbnailToR2(thumbnailUrl, fileName, userId) {
    try {
      console.log('📤 Uploading thumbnail to R2 (S3-compatible)...');
      
      // Download thumbnail from Cloudinary
      const downloadResponse = await axios({
        method: 'GET',
        url: thumbnailUrl,
        responseType: 'arraybuffer'
      });
      
      const key = `thumbnails/${userId}/${fileName}_thumb_${Date.now()}.jpg`;
      
      const command = new PutObjectCommand({
        Bucket: this.bucketName,
        Key: key,
        Body: Buffer.from(downloadResponse.data),
        ContentType: 'image/jpeg',
        CacheControl: 'public, max-age=31536000', // 1 year cache
        Metadata: {
          'thumbnail-for': fileName,
          'uploaded-by': userId,
          'upload-date': new Date().toISOString()
        }
      });

      await this.s3Client.send(command);
      
      // **USE CUSTOM DOMAIN** (cdn.snehayog.com) for public URL
      const publicUrl = this.getPublicUrl(key);
      console.log('✅ Thumbnail uploaded to R2');
      console.log('   Key:', key);
      console.log('   Public URL:', publicUrl);
      
      return publicUrl;
      
    } catch (error) {
      console.error('❌ Error uploading thumbnail to R2:', error);
      throw error;
    }
  }

  /**
   * Delete video from R2 (S3-compatible)
   */
  async deleteVideoFromR2(key) {
    try {
      const command = new DeleteObjectCommand({
        Bucket: this.bucketName,
        Key: key
      });

      await this.s3Client.send(command);
      console.log('🗑️ Video deleted from R2:', key);
      return true;
      
    } catch (error) {
      console.error('❌ Error deleting from R2:', error);
      return false;
    }
  }

  /**
   * Clean up local temp files
   */
  async cleanupLocalFile(filePath) {
    try {
      if (fs.existsSync(filePath)) {
        fs.unlinkSync(filePath);
        console.log('🧹 Temp file cleaned up:', filePath);
      }
    } catch (error) {
      console.warn('⚠️ Failed to cleanup temp file:', error);
    }
  }

  /**
   * Clean up temp directory
   */
  async cleanupTempDirectory() {
    try {
      const tempDir = path.join(process.cwd(), 'temp');
      if (fs.existsSync(tempDir)) {
        const files = fs.readdirSync(tempDir);
        for (const file of files) {
          fs.unlinkSync(path.join(tempDir, file));
        }
        console.log('🧹 Temp directory cleaned up');
      }
    } catch (error) {
      console.warn('⚠️ Failed to cleanup temp directory:', error);
    }
  }

  /**
   * Upload generic file to R2 (for HLS segments, playlists, etc.)
   * Returns custom domain URL (cdn.snehayog.com) if configured
   */
  async uploadFileToR2(filePath, key, contentType = 'application/octet-stream') {
    try {
      console.log(`📤 Uploading file to R2: ${key}`);
      
      const fileContent = fs.readFileSync(filePath);
      
      const command = new PutObjectCommand({
        Bucket: this.bucketName,
        Key: key,
        Body: fileContent,
        ContentType: contentType,
        CacheControl: 'public, max-age=31536000', // 1 year cache
      });
  
      await this.s3Client.send(command);
      
      // **USE CUSTOM DOMAIN** (cdn.snehayog.com) for public URL
      const publicUrl = this.getPublicUrl(key);
      console.log(`✅ File uploaded to R2: ${key}`);
      
      return {
        url: publicUrl,
        key: key,
        size: fileContent.length,
      };
      
    } catch (error) {
      console.error('❌ Error uploading file to R2:', error);
      throw error;
    }
  }

  /**
   * Upload entire HLS directory to R2 (playlist + segments)
   * Returns the master playlist URL
   */
  async uploadHLSDirectoryToR2(hlsDir, videoName, userId) {
    try {
      console.log('📤 Uploading HLS directory to R2...');
      console.log('   Directory:', hlsDir);
      console.log('   Video:', videoName);
      
      const files = fs.readdirSync(hlsDir);
      const uploadPromises = [];
      let playlistKey = null;
      
      for (const file of files) {
        const filePath = path.join(hlsDir, file);
        const key = `hls/${userId}/${videoName}/${file}`;
        
        if (file.endsWith('.m3u8')) {
          // Upload playlist file
          console.log(`   📝 Uploading playlist: ${file}`);
          uploadPromises.push(
            this.uploadFileToR2(filePath, key, 'application/x-mpegURL')
          );
          playlistKey = key;
        } else if (file.endsWith('.ts')) {
          // Upload segment file
          console.log(`   🎬 Uploading segment: ${file}`);
          uploadPromises.push(
            this.uploadFileToR2(filePath, key, 'video/mp2t')
          );
        }
      }
      
      await Promise.all(uploadPromises);
      
      console.log(`✅ Uploaded ${files.length} HLS files to R2`);
      console.log('   🎉 FREE bandwidth delivery via Cloudflare R2!');
      
      if (!playlistKey) {
        throw new Error('No playlist file found in HLS directory');
      }
      
      return {
        playlistUrl: this.getPublicUrl(playlistKey),
        playlistKey: playlistKey,
        totalFiles: files.length,
        segments: files.filter(f => f.endsWith('.ts')).length,
      };
      
    } catch (error) {
      console.error('❌ Error uploading HLS directory to R2:', error);
      throw error;
    }
  }
}

export default new CloudflareR2Service();
