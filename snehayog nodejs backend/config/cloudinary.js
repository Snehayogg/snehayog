// config/cloudinary.js
import dotenv from 'dotenv';
dotenv.config();
import { v2 as cloudinary } from 'cloudinary';

// Check if Cloudinary environment variables are set
const cloudName = process.env.CLOUD_NAME;
const apiKey = process.env.CLOUD_KEY;
const apiSecret = process.env.CLOUD_SECRET;

if (!cloudName || !apiKey || !apiSecret) {
  console.warn('⚠️ Cloudinary environment variables not set:');
  console.warn('   CLOUD_NAME:', cloudName ? 'Set' : 'Missing');
  console.warn('   CLOUD_KEY:', apiKey ? 'Set' : 'Missing');
  console.warn('   CLOUD_SECRET:', apiSecret ? 'Set' : 'Missing');
  console.warn('   Please set these environment variables to use Cloudinary uploads');
  console.warn('   You can create a .env file in the backend directory with:');
  console.warn('   CLOUD_NAME=your_cloudinary_cloud_name');
  console.warn('   CLOUD_KEY=your_cloudinary_api_key');
  console.warn('   CLOUD_SECRET=your_cloudinary_api_secret');
} else {
  console.log('✅ Cloudinary environment variables loaded');
}

cloudinary.config({
  cloud_name: cloudName,
  api_key: apiKey ,
  api_secret: apiSecret ,
  secure: true,
});

export default cloudinary;
