class CloudflareR2Service {
    constructor() {
      this.accountId = process.env.CLOUDFLARE_ACCOUNT_ID;
      this.bucketName = process.env.CLOUDFLARE_R2_BUCKET_NAME;
      this.publicDomain = process.env.CLOUDFLARE_R2_PUBLIC_DOMAIN || 'cdn.snehayog.site';
      
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
   * Download video from Cloudinary URL
   */
  async downloadFromCloudinary(cloudinaryUrl, fileName) {
    try {
      console.log('📥 Downloading processed video from Cloudinary...');
      
      const tempDir = path.join(process.cwd(), 'temp');
      if (!fs.existsSync(tempDir)) {
        fs.mkdirSync(tempDir, { recursive: true });
      }
      
      const localPath = path.join(tempDir, `${fileName}_480p.mp4`);
      
      const response = await axios({
        method: 'GET',
        url: cloudinaryUrl,
        responseType: 'stream'
      });
      
      const writer = fs.createWriteStream(localPath);
      response.data.pipe(writer);
      
      return new Promise((resolve, reject) => {
        writer.on('finish', () => {
          console.log('✅ Video downloaded from Cloudinary');
          resolve(localPath);
        });
        writer.on('error', reject);
      });
      
    } catch (error) {
      console.error('❌ Error downloading from Cloudinary:', error);
      throw error;
    }
  }

  /**
   * Upload video file to Cloudflare R2 using pure Cloudflare API
   */
  async uploadVideoToR2(filePath, fileName, userId) {
    try {
      console.log('📤 Uploading video to Cloudflare R2 (S3-compatible)...');
      
      const fileContent = fs.readFileSync(filePath);
      const key = `videos/${userId}/${fileName}_480p.mp4`;
      
      const command = new PutObjectCommand({
        Bucket: this.bucketName,
        Key: key,
        Body: fileContent,
        ContentType: 'video/mp4',
        CacheControl: 'public, max-age=31536000',
        Metadata: {
          'video-quality': '480p',
          'processed-by': 'cloudinary-hybrid',
          'uploaded-by': userId,
          'upload-date': new Date().toISOString()
        }
      });
  
      await this.s3Client.send(command);
      
      const publicUrl = `https://${this.publicDomain}/${key}`;
      console.log('✅ Video uploaded to R2:', publicUrl);
      
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
   * Upload thumbnail to R2 using pure Cloudflare API
   */
  async uploadThumbnailToR2(thumbnailUrl, fileName, userId) {
    try {
      console.log('📤 Uploading thumbnail to R2 (Cloudflare API)...');
      
      // Download thumbnail from Cloudinary
      const downloadResponse = await axios({
        method: 'GET',
        url: thumbnailUrl,
        responseType: 'arraybuffer'
      });
      
      const key = `thumbnails/${userId}/${fileName}_thumb.jpg`;
      
      // Upload to R2 using Cloudflare API
      const uploadResponse = await axios.put(`${this.apiUrl}/${key}`, downloadResponse.data, {
        headers: {
          'Authorization': `Bearer ${this.apiToken}`,
          'Content-Type': 'image/jpeg',
          'Cache-Control': 'public, max-age=31536000', // 1 year cache
          'X-Custom-Metadata-thumbnail-for': fileName,
          'X-Custom-Metadata-uploaded-by': userId
        }
      });

      if (uploadResponse.status === 200) {
        // Use custom domain for better performance and branding
        const publicUrl = `https://${this.publicDomain}/${key}`;
        console.log('✅ Thumbnail uploaded to R2 (Custom Domain):', publicUrl);
        return publicUrl;
      } else {
        throw new Error(`Thumbnail upload failed with status: ${uploadResponse.status}`);
      }
      
    } catch (error) {
      console.error('❌ Error uploading thumbnail to R2 (Cloudflare API):', error);
      throw error;
    }
  }

  /**
   * Delete video from R2 using pure Cloudflare API
   */
  async deleteVideoFromR2(key) {
    try {
      const response = await axios.delete(`${this.apiUrl}/${key}`, {
        headers: {
          'Authorization': `Bearer ${this.apiToken}`
        }
      });

      if (response.status === 200 || response.status === 204) {
        console.log('🗑️ Video deleted from R2 (Cloudflare API):', key);
        return true;
      } else {
        throw new Error(`Delete failed with status: ${response.status}`);
      }
      
    } catch (error) {
      console.error('❌ Error deleting from R2 (Cloudflare API):', error);
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
}

export default new CloudflareR2Service();
