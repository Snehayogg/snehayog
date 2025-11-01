import { v2 as cloudinary } from 'cloudinary';

// Configure Cloudinary for video processing and ad image uploads
cloudinary.config({
  cloud_name: process.env.CLOUDINARY_CLOUD_NAME || process.env.CLOUD_NAME,
  api_key: process.env.CLOUDINARY_API_KEY || process.env.CLOUD_KEY,
  api_secret: process.env.CLOUDINARY_API_SECRET || process.env.CLOUD_SECRET,
  secure: true
});

// **ENHANCED: Validate configuration on startup**
const config = cloudinary.config();
if (!config.cloud_name || !config.api_key || !config.api_secret) {
  console.error('❌ Cloudinary configuration incomplete:');
  console.error('   cloud_name:', !!config.cloud_name);
  console.error('   api_key:', !!config.api_key);
  console.error('   api_secret:', !!config.api_secret);
  console.error('💡 Please set CLOUDINARY_* or CLOUD_* environment variables');
} else {
  console.log('✅ Cloudinary configuration validated successfully');
}

console.log('☁️ Cloudinary configured for video processing only');
console.log('📦 Storage: Cloudflare R2, CDN: cdn.snehayog.site');

export default cloudinary;
