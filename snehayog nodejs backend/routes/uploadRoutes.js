import express from 'express';
import multer from 'multer';
import cloudinary from '../config/cloudinary.js';
import fs from 'fs';
import { verifyToken } from '../utils/verifytoken.js';

const router = express.Router();

// Multer configuration for media uploads
const upload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => {
      const uploadDir = 'uploads/temp/';
      if (!fs.existsSync(uploadDir)) {
        fs.mkdirSync(uploadDir, { recursive: true });
      }
      cb(null, uploadDir);
    },
    filename: (req, file, cb) => {
      const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
      cb(null, uniqueSuffix + '-' + file.originalname);
    },
  }),
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB limit for media files
  },
  fileFilter: (req, file, cb) => {
    const allowedMimeTypes = [
      'image/jpeg', 'image/png', 'image/gif', 'image/webp',
      'video/mp4', 'video/webm', 'video/avi', 'video/mov'
    ];
    if (allowedMimeTypes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Invalid file type. Only images and videos are allowed.'), false);
    }
  }
});

// POST /api/upload/image - Upload image to Cloudinary
router.post('/image', verifyToken, upload.single('image'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No image file uploaded' });
    }

    console.log('📸 Upload: Starting image upload to Cloudinary...');
    console.log('📸 Upload: File:', req.file.originalname, 'Size:', req.file.size);

    // Upload to Cloudinary
    const result = await cloudinary.uploader.upload(req.file.path, {
      resource_type: 'image',
      folder: req.body.folder || 'snehayog/ads/images',
      transformation: [
        { quality: 'auto:good' },
        { fetch_format: 'auto' }
      ]
    });

    // Clean up temp file
    if (fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
      console.log('✅ Upload: Temporary file cleaned up');
    }

    console.log('✅ Upload: Image uploaded successfully to Cloudinary');
    console.log('📸 Upload: Cloudinary URL:', result.secure_url);

    res.json({
      success: true,
      url: result.secure_url,
      public_id: result.public_id,
      width: result.width,
      height: result.height,
      format: result.format,
      size: result.bytes
    });

  } catch (error) {
    console.error('❌ Upload: Image upload error:', error);
    
    // Clean up temp file if it exists
    if (req.file?.path && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }
    
    res.status(500).json({ 
      error: 'Failed to upload image',
      details: error.message 
    });
  }
});

// POST /api/upload/video - Upload video to Cloudinary
router.post('/video', verifyToken, upload.single('video'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No video file uploaded' });
    }

    console.log('🎬 Upload: Starting video upload to Cloudinary...');
    console.log('🎬 Upload: File:', req.file.originalname, 'Size:', req.file.size);

    // Upload to Cloudinary
    const result = await cloudinary.uploader.upload(req.file.path, {
      resource_type: 'video',
      folder: req.body.folder || 'snehayog/ads/videos',
      transformation: [
        { quality: 'auto:good' },
        { fetch_format: 'auto' }
      ]
    });

    // Clean up temp file
    if (fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
      console.log('✅ Upload: Temporary file cleaned up');
    }

    console.log('✅ Upload: Video uploaded successfully to Cloudinary');
    console.log('🎬 Upload: Cloudinary URL:', result.secure_url);

    res.json({
      success: true,
      url: result.secure_url,
      public_id: result.public_id,
      width: result.width,
      height: result.height,
      format: result.format,
      duration: result.duration,
      size: result.bytes,
      thumbnail_url: result.thumbnail_url
    });

  } catch (error) {
    console.error('❌ Upload: Video upload error:', error);
    
    // Clean up temp file if it exists
    if (req.file?.path && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }
    
    res.status(500).json({ 
      error: 'Failed to upload video',
      details: error.message 
    });
  }
});

// DELETE /api/upload/delete - Delete media from Cloudinary
router.delete('/delete', verifyToken, async (req, res) => {
  try {
    const { public_id, resource_type } = req.body;

    if (!public_id || !resource_type) {
      return res.status(400).json({ 
        error: 'Missing required fields: public_id and resource_type' 
      });
    }

    console.log('🗑️ Upload: Deleting media from Cloudinary...');
    console.log('🗑️ Upload: Public ID:', public_id, 'Type:', resource_type);

    // Delete from Cloudinary
    const result = await cloudinary.uploader.destroy(public_id, { 
      resource_type: resource_type 
    });

    console.log('✅ Upload: Media deleted successfully from Cloudinary');

    res.json({
      success: true,
      message: 'Media deleted successfully',
      result: result
    });

  } catch (error) {
    console.error('❌ Upload: Media deletion error:', error);
    res.status(500).json({ 
      error: 'Failed to delete media',
      details: error.message 
    });
  }
});

export default router;
