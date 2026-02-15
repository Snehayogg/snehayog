import express from 'express';
import multer from 'multer';
import path from 'path';
import fs from 'fs/promises';
import fsSync from 'fs';
import crypto from 'crypto';
import mongoose from 'mongoose';
import Video from '../models/Video.js';
import User from '../models/User.js';
let hybridVideoService;
import { verifyToken } from '../utils/verifytoken.js';
import cloudflareR2Service from '../services/cloudflareR2Service.js';
import { uploadLimiter } from '../middleware/rateLimiter.js';
import AdmZip from 'adm-zip';
import Game from '../models/Game.js';

const router = express.Router();

// **NEW: Apply Upload Rate Limiter to all routes in this file**
router.use(uploadLimiter);
const RESUMABLE_CHUNK_SIZE_DEFAULT = 5 * 1024 * 1024; // 5MB
const RESUMABLE_UPLOAD_TTL_MS = 24 * 60 * 60 * 1000; // 24h
const resumableSessions = new Map();

function pruneExpiredResumableSessions() {
  const now = Date.now();
  for (const [sessionId, session] of resumableSessions.entries()) {
    if (now - session.updatedAt > RESUMABLE_UPLOAD_TTL_MS) {
      resumableSessions.delete(sessionId);
    }
  }
}

function buildResumableSessionKey(userId, fileFingerprint) {
  const seed = `${userId}:${fileFingerprint}`;
  return crypto.createHash('sha1').update(seed).digest('hex');
}

async function safeDeleteFile(filePath) {
  if (!filePath) return;
  try {
    await fs.unlink(filePath);
  } catch (_) {}
}

async function safeDeleteDir(dirPath) {
  if (!dirPath) return;
  try {
    await fs.rm(dirPath, { recursive: true, force: true });
  } catch (_) {}
}

/**
 * Calculate SHA256 hash of a file
 * @param {string} filePath - Path to the file
 * @returns {Promise<string>} - Hex string of the hash
 */
async function calculateFileHash(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('sha256');
    const stream = fsSync.createReadStream(filePath);

    stream.on('data', (data) => hash.update(data));
    stream.on('end', () => resolve(hash.digest('hex')));
    stream.on('error', (error) => reject(error));
  });
}

// **NEW: Configure multer for image uploads**
const imageStorage = multer.diskStorage({
  destination: async (req, file, cb) => {
    const uploadDir = path.join(process.cwd(), 'uploads', 'ads');
    try {
      await fs.mkdir(uploadDir, { recursive: true });
      cb(null, uploadDir);
    } catch (error) {
      cb(error);
    }
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    const ext = path.extname(file.originalname);
    cb(null, `ad-image-${uniqueSuffix}${ext}`);
  }
});

const imageUpload = multer({
  storage: imageStorage,
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB limit for ad images
    files: 1
  },
  fileFilter: (req, file, cb) => {
    const allowedMimeTypes = [
      'image/jpeg',
      'image/jpg',
      'image/png',
      'image/gif',
      'image/webp',
      'image/heic',
      'image/heif',
      'image/avif',
      'image/bmp',
      'image/tiff'
    ];

    if (allowedMimeTypes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Only image files are allowed'), false);
    }
  }
});

// **NEW: Configure multer for video uploads**
const storage = multer.diskStorage({
  destination: async (req, file, cb) => {
    // Determine upload directory based on field name
    let uploadDir;
    if (file.fieldname === 'game') {
      uploadDir = path.join(process.cwd(), 'uploads', 'temp', 'games');
    } else {
      uploadDir = path.join(process.cwd(), 'uploads', 'temp');
    }
    
    try {
      await fs.mkdir(uploadDir, { recursive: true });
      cb(null, uploadDir);
    } catch (error) {
      cb(error);
    }
  },
  filename: (req, file, cb) => {
    const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
    const ext = path.extname(file.originalname);
    const prefix = file.fieldname === 'game' ? 'game-zip-' : 'video-';
    cb(null, `${prefix}${uniqueSuffix}${ext}`);
  }
});

const upload = multer({
  storage: storage,
  limits: {
    fileSize: 300 * 1024 * 1024, // 300MB limit (Updated to match videoRoutes)
    files: 1
  },
  fileFilter: (req, file, cb) => {
    // **NEW: Allow only video files**
    const allowedMimeTypes = [
      'video/mp4',
      'video/mov',
      'video/avi',
      'video/mkv',
      'video/webm',
      'video/flv',
      // Allow ZIPs for games
      'application/zip',
      'application/x-zip-compressed',
      'multipart/x-zip'
    ];

    if (allowedMimeTypes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Only video files are allowed'), false);
    }
  }
});

const chunkUpload = multer({
  storage: storage,
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB per chunk
    files: 1
  }
});

// **NEW: Upload video with automatic quality processing**
router.post('/video', verifyToken, upload.single('video'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No video file uploaded' });
    }

    const { videoName, description, link } = req.body;
    const userId = req.user.id;
    const videoPath = req.file.path;

    console.log('🚀 Starting video upload process...');
    console.log('📁 File path:', videoPath);
    console.log('👤 User ID:', userId);

    // **NEW: Lazy load hybrid service to ensure env vars are loaded**
    if (!hybridVideoService) {
      const { default: service } = await import('../services/hybridVideoService.js');
      hybridVideoService = service;
    }

    // **NEW: Validate video file with hybrid service**
    const videoValidation = await hybridVideoService.validateVideo(videoPath);
    if (!videoValidation.isValid) {
      await fs.unlink(videoPath);
      return res.status(400).json({
        error: 'Invalid video file',
        details: videoValidation.error
      });
    }

    console.log('✅ Video validation passed');
    console.log('📊 Video info:', videoValidation);

    // **NEW: Show cost estimate**
    const costEstimate = hybridVideoService.getCostEstimate(videoValidation.sizeInMB);
    console.log('💰 Cost estimate:', costEstimate);

    // **NEW: Find user by Google ID to get proper ObjectId**
    const user = await User.findOne({ googleId: userId });
    if (!user) {
      await fs.unlink(videoPath);
      return res.status(404).json({ error: 'User not found' });
    }

    // **NEW: Calculate file hash for duplicate detection**
    console.log('🔍 Calculating video file hash for duplicate detection...');
    let videoHash;
    try {
      videoHash = await calculateFileHash(videoPath);
      console.log('✅ Video hash calculated:', videoHash.substring(0, 16) + '...');
    } catch (hashError) {
      console.error('❌ Error calculating file hash:', hashError);
      await fs.unlink(videoPath);
      return res.status(500).json({
        error: 'Failed to process video file',
        details: 'Error calculating file hash'
      });
    }

    // **NEW: Check for duplicate video (same user, same hash)**
    const existingVideo = await Video.findOne({
      uploader: user._id,
      videoHash: videoHash,
      processingStatus: { $ne: 'failed' } // Allow retry if previous attempt failed
    });

    if (existingVideo) {
      console.log('⚠️ Duplicate video detected:', {
        existingVideoId: existingVideo._id,
        existingVideoName: existingVideo.videoName,
        hash: videoHash.substring(0, 16) + '...'
      });

      // Clean up uploaded file
      await fs.unlink(videoPath);

      return res.status(409).json({
        error: 'Duplicate video detected',
        message: 'You have already uploaded this video',
        existingVideo: {
          id: existingVideo._id,
          videoName: existingVideo.videoName,
          uploadedAt: existingVideo.uploadedAt
        }
      });
    }

    // **NEW: Get video dimensions safely**
    const videoInfo = await hybridVideoService.getOriginalVideoInfo(videoPath);
    const aspectRatio = videoInfo.width && videoInfo.height ?
      videoInfo.width / videoInfo.height : 9 / 16; // Default to 9:16 if dimensions unavailable

    // **NEW: Create initial video record with pending status**
    // **FIX: Use proper URL format instead of local file path**
    const baseUrl = process.env.SERVER_URL || 'http://192.168.0.199:5001';
    const relativePath = videoPath.replace(/\\/g, '/').replace(process.cwd().replace(/\\/g, '/'), '');
    const tempVideoUrl = `${baseUrl}${relativePath}`;

    console.log('🔗 Generated temp video URL:', tempVideoUrl);

    const video = new Video({
      videoName: videoName || req.file.originalname,
      description: description || '',
      videoUrl: tempVideoUrl, // Proper URL format, will be updated after processing
      thumbnailUrl: '', // Will be generated during processing
      uploader: user._id, // Use user's ObjectId, not Google ID
      videoType: (videoInfo.duration && videoInfo.duration > 60) ? 'vayu' : 'yog',
      aspectRatio: aspectRatio,
      duration: videoInfo.duration || 0,
      originalSize: videoValidation.size,
      originalFormat: path.extname(req.file.originalname).substring(1),
      originalResolution: {
        width: videoInfo.width || 0,
        height: videoInfo.height || 0
      },
      processingStatus: 'pending',
      processingProgress: 0,
      link: link || '', // **FIX: Include link field from request body**
      videoHash: videoHash, // **NEW: Save hash for duplicate detection**
      seriesId: req.body.seriesId || null, // **NEW: Save series ID for connected episodes**
      episodeNumber: req.body.episodeNumber ? parseInt(req.body.episodeNumber) : 0 // **NEW: Save episode number**
    });

    // **NEW: Save video record first**
    await video.save();
    console.log('💾 Video record saved with ID:', video._id);

    // **NEW: Start hybrid processing in background (Cloudinary → R2)**
    console.log('🔄 Starting background processing for video:', video._id);
    console.log('📁 Video path:', videoPath);
    console.log('👤 User ID:', userId);

    // Start processing in background with proper error handling
    processVideoHybrid(video._id, videoPath, videoName, userId).catch(error => {
      console.error('❌ Background processing failed:', error);
      console.error('❌ Error stack:', error.stack);
    });

    // **NEW: Return immediate response with processing status**
    res.status(201).json({
      success: true,
      message: 'Video upload started successfully',
      video: {
        id: video._id,
        videoName: video.videoName,
        processingStatus: video.processingStatus,
        processingProgress: video.processingProgress,
        estimatedTime: '2-5 minutes depending on video length'
      }
    });

  } catch (error) {
    console.error('❌ Error in video upload:', error);

    // **NEW: Clean up uploaded file on error**
    if (req.file) {
      try {
        await fs.unlink(req.file.path);
      } catch (cleanupError) {
        console.warn('⚠️ Failed to cleanup file:', cleanupError);
      }
    }

    res.status(500).json({
      error: 'Video upload failed',
      details: error.message
    });
  }
});


// **NEW: Resumable Upload Init**
router.post('/video/resumable/init', verifyToken, async (req, res) => {
  try {
    pruneExpiredResumableSessions();

    const {
      fileName,
      fileSize,
      chunkSize,
      totalChunks,
      fileFingerprint,
      videoName,
      description,
      link,
      category,
      tags,
      videoType,
      seriesId,
      episodeNumber
    } = req.body || {};

    if (!fileName || !fileSize || !totalChunks || !fileFingerprint) {
      return res.status(400).json({ error: 'Missing resumable init fields' });
    }

    const userId = req.user.id;
    const normalizedChunkSize = Number(chunkSize) > 0 ? Number(chunkSize) : RESUMABLE_CHUNK_SIZE_DEFAULT;
    const normalizedTotalChunks = Number(totalChunks);
    const normalizedFileSize = Number(fileSize);

    if (!Number.isFinite(normalizedTotalChunks) || normalizedTotalChunks <= 0) {
      return res.status(400).json({ error: 'Invalid totalChunks value' });
    }

    const sessionId = buildResumableSessionKey(userId, fileFingerprint);
    const sessionRoot = path.join(process.cwd(), 'uploads', 'resumable', sessionId);
    const chunkDir = path.join(sessionRoot, 'chunks');

    let session = resumableSessions.get(sessionId);

    if (!session) {
      await fs.mkdir(chunkDir, { recursive: true });

      session = {
        sessionId,
        userId,
        fileName,
        fileSize: normalizedFileSize,
        chunkSize: normalizedChunkSize,
        totalChunks: normalizedTotalChunks,
        fileFingerprint,
        sessionRoot,
        chunkDir,
        receivedChunks: new Set(),
        metadata: {
          videoName,
          description,
          link,
          category,
          tags,
          videoType,
          seriesId,
          episodeNumber
        },
        createdAt: Date.now(),
        updatedAt: Date.now()
      };

      resumableSessions.set(sessionId, session);
    } else {
      session.updatedAt = Date.now();
      session.metadata = {
        ...session.metadata,
        videoName,
        description,
        link,
        category,
        tags,
        videoType,
        seriesId,
        episodeNumber
      };

      try {
        const chunkFiles = await fs.readdir(session.chunkDir);
        session.receivedChunks = new Set(
          chunkFiles
            .filter((name) => name.endsWith('.part'))
            .map((name) => Number(path.basename(name, '.part')))
            .filter((index) => Number.isFinite(index))
        );
      } catch (_) {}
    }

    const uploadedChunks = Array.from(session.receivedChunks).sort((a, b) => a - b);

    return res.json({
      success: true,
      sessionId,
      uploadedChunks,
      totalChunks: session.totalChunks,
      chunkSize: session.chunkSize
    });
  } catch (error) {
    console.error('? Resumable init failed:', error);
    return res.status(500).json({ error: 'Failed to initialize resumable upload' });
  }
});

// **NEW: Resumable Upload Chunk**
router.post('/video/resumable/:sessionId/chunk', verifyToken, chunkUpload.single('chunk'), async (req, res) => {
  try {
    const { sessionId } = req.params;
    const chunkIndex = Number(req.body?.chunkIndex);

    if (!req.file) {
      return res.status(400).json({ error: 'Chunk file is required' });
    }

    if (!Number.isFinite(chunkIndex) || chunkIndex < 0) {
      await safeDeleteFile(req.file.path);
      return res.status(400).json({ error: 'Invalid chunkIndex' });
    }

    const session = resumableSessions.get(sessionId);
    if (!session) {
      await safeDeleteFile(req.file.path);
      return res.status(404).json({ error: 'Resumable session not found or expired' });
    }

    if (session.userId !== req.user.id) {
      await safeDeleteFile(req.file.path);
      return res.status(403).json({ error: 'Not allowed for this resumable session' });
    }

    if (chunkIndex >= session.totalChunks) {
      await safeDeleteFile(req.file.path);
      return res.status(400).json({ error: 'chunkIndex out of range' });
    }

    await fs.mkdir(session.chunkDir, { recursive: true });

    const chunkPath = path.join(session.chunkDir, `${chunkIndex}.part`);

    if (fsSync.existsSync(chunkPath)) {
      await safeDeleteFile(req.file.path);
    } else {
      await fs.rename(req.file.path, chunkPath);
      session.receivedChunks.add(chunkIndex);
    }

    session.updatedAt = Date.now();

    return res.json({
      success: true,
      sessionId,
      chunkIndex,
      uploadedChunks: session.receivedChunks.size,
      totalChunks: session.totalChunks
    });
  } catch (error) {
    console.error('? Resumable chunk upload failed:', error);
    if (req.file?.path) {
      await safeDeleteFile(req.file.path);
    }
    return res.status(500).json({ error: 'Failed to upload chunk' });
  }
});

// **NEW: Resumable Upload Complete**
router.post('/video/resumable/:sessionId/complete', verifyToken, async (req, res) => {
  try {
    const { sessionId } = req.params;
    const session = resumableSessions.get(sessionId);

    if (!session) {
      return res.status(404).json({ error: 'Resumable session not found or expired' });
    }

    if (session.userId !== req.user.id) {
      return res.status(403).json({ error: 'Not allowed for this resumable session' });
    }

    const missingChunks = [];
    for (let index = 0; index < session.totalChunks; index++) {
      if (!fsSync.existsSync(path.join(session.chunkDir, `${index}.part`))) {
        missingChunks.push(index);
      }
    }

    if (missingChunks.length > 0) {
      return res.status(409).json({
        error: 'Cannot complete upload, missing chunks',
        missingChunks
      });
    }

    const fileExt = path.extname(session.fileName) || '.mp4';
    const assembledFilePath = path.join(process.cwd(), 'uploads', 'temp', `video-resumable-${Date.now()}-${Math.round(Math.random() * 1e9)}${fileExt}`);

    await fs.mkdir(path.dirname(assembledFilePath), { recursive: true });

    const writeStream = fsSync.createWriteStream(assembledFilePath);
    for (let index = 0; index < session.totalChunks; index++) {
      const partPath = path.join(session.chunkDir, `${index}.part`);
      await new Promise((resolve, reject) => {
        const readStream = fsSync.createReadStream(partPath);
        readStream.on('error', reject);
        readStream.on('end', resolve);
        readStream.pipe(writeStream, { end: false });
      });
    }

    await new Promise((resolve, reject) => {
      writeStream.on('error', reject);
      writeStream.end(resolve);
    });

    const uploadResponse = await createVideoFromUploadedFile({
      userId: req.user.id,
      filePath: assembledFilePath,
      originalName: session.fileName,
      metadata: session.metadata || {}
    });

    resumableSessions.delete(sessionId);
    await safeDeleteDir(session.sessionRoot);

    return res.status(201).json(uploadResponse);
  } catch (error) {
    console.error('? Resumable complete failed:', error);
    if (error?.statusCode && error?.payload) {
      return res.status(error.statusCode).json(error.payload);
    }
    return res.status(500).json({ error: 'Failed to finalize resumable upload', details: error.message });
  }
});

async function createVideoFromUploadedFile({ userId, filePath, originalName, metadata = {} }) {
  if (!hybridVideoService) {
    const { default: service } = await import('../services/hybridVideoService.js');
    hybridVideoService = service;
  }

  const videoValidation = await hybridVideoService.validateVideo(filePath);
  if (!videoValidation.isValid) {
    await safeDeleteFile(filePath);
    throw new Error(videoValidation.error || 'Invalid video file');
  }

  const user = await User.findOne({ googleId: userId });
  if (!user) {
    await safeDeleteFile(filePath);
    throw new Error('User not found');
  }

  const videoHash = await calculateFileHash(filePath);

  const existingVideo = await Video.findOne({
    uploader: user._id,
    videoHash: videoHash,
    processingStatus: { $ne: 'failed' }
  });

  if (existingVideo) {
    await safeDeleteFile(filePath);
    const duplicateErr = new Error('Duplicate video detected');
    duplicateErr.statusCode = 409;
    duplicateErr.payload = {
      error: 'Duplicate video detected',
      message: 'You have already uploaded this video',
      existingVideo: {
        id: existingVideo._id,
        videoName: existingVideo.videoName,
        uploadedAt: existingVideo.uploadedAt
      }
    };
    throw duplicateErr;
  }

  const videoInfo = await hybridVideoService.getOriginalVideoInfo(filePath);
  const aspectRatio = videoInfo.width && videoInfo.height ? videoInfo.width / videoInfo.height : 9 / 16;

  const baseUrl = process.env.SERVER_URL || 'http://192.168.0.199:5001';
  const relativePath = filePath.replace(/\\/g, '/').replace(process.cwd().replace(/\\/g, '/'), '');
  const tempVideoUrl = `${baseUrl}${relativePath}`;

  const finalVideoName = metadata.videoName || originalName;

  const video = new Video({
    videoName: finalVideoName,
    description: metadata.description || '',
    videoUrl: tempVideoUrl,
    thumbnailUrl: '',
    uploader: user._id,
    videoType: (videoInfo.duration && videoInfo.duration > 60) ? 'vayu' : 'yog',
    aspectRatio,
    duration: videoInfo.duration || 0,
    originalSize: videoValidation.size,
    originalFormat: path.extname(originalName).substring(1),
    originalResolution: {
      width: videoInfo.width || 0,
      height: videoInfo.height || 0
    },
    processingStatus: 'pending',
    processingProgress: 0,
    link: metadata.link || '',
    videoHash,
    seriesId: metadata.seriesId || null,
    episodeNumber: metadata.episodeNumber ? parseInt(metadata.episodeNumber) : 0
  });

  await video.save();

  processVideoHybrid(video._id, filePath, finalVideoName, userId).catch(error => {
    console.error('? Background processing failed:', error);
    console.error('? Error stack:', error.stack);
  });

  return {
    success: true,
    message: 'Video upload started successfully',
    video: {
      id: video._id,
      videoName: video.videoName,
      processingStatus: video.processingStatus,
      processingProgress: video.processingProgress,
      estimatedTime: '2-5 minutes depending on video length'
    }
  };
}
// **NEW: URL normalization function**
function normalizeVideoUrl(url) {
  if (!url) return url;

  // **FIX: Replace backslashes with forward slashes**
  let normalizedUrl = url.replace(/\\/g, '/');

  // **FIX: Ensure proper URL format**
  if (!normalizedUrl.startsWith('http://') && !normalizedUrl.startsWith('https://')) {
    // If it's a relative path, make it absolute
    const baseUrl = process.env.SERVER_URL || 'http://10.118.107.18:5001';
    normalizedUrl = `${baseUrl}/${normalizedUrl}`;
  }

  // **FIX: Ensure single forward slashes between path segments (but preserve protocol slashes)**
  // Only normalize multiple slashes in the path part, not the protocol
  if (normalizedUrl.includes('://')) {
    const [protocol, rest] = normalizedUrl.split('://');
    const normalizedRest = rest.replace(/\/+/g, '/');
    normalizedUrl = `${protocol}://${normalizedRest}`;
  } else {
    normalizedUrl = normalizedUrl.replace(/\/+/g, '/');
  }

  console.log('🔧 URL normalization:');
  console.log('   Original:', url);
  console.log('   Normalized:', normalizedUrl);

  return normalizedUrl;
}

// **NEW: Hybrid video processing function (Cloudinary → R2)**
async function processVideoHybrid(videoId, videoPath, videoName, userId) {
  try {
    console.log('🚀 Starting hybrid video processing (Cloudinary → R2) for:', videoId);
    console.log('📁 Video path:', videoPath);
    console.log('📝 Video name:', videoName);
    console.log('👤 User ID:', userId);

    // **FIX: Sanitize video name to remove invalid characters for Cloudinary**
    const sanitizedVideoName = videoName.replace(/[^a-zA-Z0-9\s_-]/g, '_').replace(/\s+/g, '_').substring(0, 50);
    console.log('📝 Sanitized video name:', sanitizedVideoName);

    // **NEW: Lazy load hybrid service to ensure env vars are loaded**
    if (!hybridVideoService) {
      const { default: service } = await import('../services/hybridVideoService.js');
      hybridVideoService = service;
    }

    // **NEW: Update status to processing**
    const video = await Video.findById(videoId);
    if (!video) {
      throw new Error('Video not found');
    }

    video.processingStatus = 'processing';
    video.processingProgress = 10;
    await video.save();
    console.log('📊 Processing status updated to 10% - Starting validation');

    // **UPDATE: Validation phase (10-30%)**
    video.processingProgress = 30;
    await video.save();
    console.log('📊 Processing status updated to 30% - Validation complete, starting conversion');

    // **NEW: Process video using hybrid approach with timeout**
    console.log('🔄 Starting hybrid processing...');
    let hybridResult;
    try {
      hybridResult = await Promise.race([
        hybridVideoService.processVideoHybrid(
          videoPath,
          sanitizedVideoName,
          userId
        ),
        new Promise((_, reject) =>
          setTimeout(() => reject(new Error('Hybrid processing timeout after 30 minutes')), 30 * 60 * 1000)
        )
      ]);
      console.log('✅ Hybrid processing completed successfully');
    } catch (error) {
      console.error('❌ Hybrid processing failed:', error);
      // Update video status to failed
      video.processingStatus = 'failed';
      video.processingError = error.message;
      await video.save();
      throw error;
    }

    console.log('✅ Hybrid processing completed');
    console.log('🔗 Hybrid result:', hybridResult);

    // **UPDATE: Finalizing phase (80-95%)**
    video.processingProgress = 95;
    await video.save();
    console.log('📊 Processing status updated to 95% - Finalizing');

    // **NEW: Update video record with R2 URLs**
    // **FIX: Validate and normalize URLs before saving**
    const normalizedVideoUrl = normalizeVideoUrl(hybridResult.videoUrl);
    const normalizedThumbnailUrl = normalizeVideoUrl(hybridResult.thumbnailUrl);

    video.videoUrl = normalizedVideoUrl; // R2 video URL with FREE bandwidth
    video.thumbnailUrl = normalizedThumbnailUrl; // R2 thumbnail URL

    console.log('🔗 Final video URL:', normalizedVideoUrl);
    console.log('🖼️ Final thumbnail URL:', normalizedThumbnailUrl);

    // **NEW: Clear old quality URLs (single format now)**
    video.preloadQualityUrl = null;
    video.lowQualityUrl = normalizedVideoUrl; // Same as main URL (480p)
    video.mediumQualityUrl = null;
    video.highQualityUrl = null;

    // **NEW: If URL is HLS (.m3u8), set HLS flags/fields for frontend autoplay**
    if (normalizedVideoUrl && normalizedVideoUrl.includes('.m3u8')) {
      video.isHLSEncoded = true;
      video.hlsPlaylistUrl = normalizedVideoUrl;
      video.hlsMasterPlaylistUrl = normalizedVideoUrl;
    } else {
      video.isHLSEncoded = false;
      video.hlsPlaylistUrl = null;
      video.hlsMasterPlaylistUrl = null;
    }

    video.processingStatus = 'completed';
    video.processingProgress = 100;

    // **NEW: Add hybrid metadata**
    video.originalSize = hybridResult.size;
    video.originalFormat = 'mp4';
    video.originalResolution = {
      width: 854,
      height: 480
    };

    // **NEW: Add single quality version**
    video.qualitiesGenerated = [{
      quality: 'optimized',
      url: normalizedVideoUrl,
      size: hybridResult.size,
      resolution: {
        width: 854,
        height: 480
      },
      bitrate: '550k',
      generatedAt: new Date()
    }];

    await video.save();
    console.log('🎉 Hybrid video processing completed successfully!');
    console.log('💰 Cost savings: 93% vs previous setup');
    console.log('📊 Final video data:', {
      id: video._id,
      videoUrl: normalizedVideoUrl,
      thumbnailUrl: normalizedThumbnailUrl,
      quality: '480p optimized',
      storage: 'Cloudflare R2',
      bandwidth: 'FREE',
      status: video.processingStatus
    });

  } catch (error) {
    console.error('❌ Error in hybrid video processing:', error);

    try {
      // **NEW: Update video status to failed**
      const video = await Video.findById(videoId);
      if (video) {
        video.processingStatus = 'failed';
        video.processingError = error.message;
        await video.save();
      }
    } catch (updateError) {
      console.error('❌ Failed to update video status:', updateError);
    }
  }
}

// **NEW: Get video processing status**
router.get('/video/:videoId/status', verifyToken, async (req, res) => {
  try {
    const video = await Video.findById(req.params.videoId);
    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    // **FIX: Compare against the user's ObjectId, not Google ID**
    const owner = await User.findOne({ googleId: req.user.id });
    if (!owner || video.uploader.toString() !== owner._id.toString()) {
      return res.status(403).json({ error: 'Access denied' });
    }

    res.json({
      success: true,
      video: {
        id: video._id,
        videoName: video.videoName,
        processingStatus: video.processingStatus,
        processingProgress: video.processingProgress,
        processingError: video.processingError,
        hasMultipleQualities: video.hasMultipleQualities,
        qualitiesGenerated: video.qualitiesGenerated.length,
        isHLSEncoded: video.isHLSEncoded || false,
        hlsPlaylistUrl: video.hlsPlaylistUrl || null,
        // Include URLs when processing is completed
        videoUrl: video.processingStatus === 'completed' ? video.videoUrl : null,
        thumbnailUrl: video.processingStatus === 'completed' ? video.thumbnailUrl : null
      }
    });

  } catch (error) {
    console.error('❌ Error getting video status:', error);
    res.status(500).json({
      error: 'Failed to get video status',
      details: error.message
    });
  }
});

// **NEW: Retry failed video processing**
router.post('/video/:videoId/retry', verifyToken, async (req, res) => {
  try {
    const video = await Video.findById(req.params.videoId);
    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    // **NEW: Check if user owns the video**
    if (video.uploader.toString() !== req.user.id) {
      return res.status(403).json({ error: 'Access denied' });
    }

    // **NEW: Check if video processing failed**
    if (video.processingStatus !== 'failed') {
      return res.status(400).json({
        error: 'Video is not in failed state'
      });
    }

    // **NEW: Reset processing status and retry**
    video.processingStatus = 'pending';
    video.processingProgress = 0;
    video.processingError = null;
    await video.save();

    // **NEW: Start processing again**
    const videoPath = video.videoUrl; // Use original path
    processVideoInBackground(video._id, videoPath, video.videoName, video.uploader);

    res.json({
      success: true,
      message: 'Video processing restarted',
      video: {
        id: video._id,
        processingStatus: video.processingStatus,
        processingProgress: video.processingProgress
      }
    });

  } catch (error) {
    console.error('❌ Error retrying video processing:', error);
    res.status(500).json({
      error: 'Failed to retry video processing',
      details: error.message
    });
  }
});

// **NEW: Get all user's videos with processing status**
router.get('/videos', verifyToken, async (req, res) => {
  try {
    const videos = await Video.find({ uploader: req.user.id })
      .sort({ uploadedAt: -1 })
      .select('videoName processingStatus processingProgress uploadedAt');

    res.json({
      success: true,
      videos: videos
    });

  } catch (error) {
    console.error('❌ Error getting user videos:', error);
    res.status(500).json({
      error: 'Failed to get videos',
      details: error.message
    });
  }
});

// **NEW: Upload image for ads (Cloudflare R2 instead of Cloudinary)**
router.post('/image', verifyToken, imageUpload.single('image'), async (req, res) => {
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No image file uploaded' });
    }

    const imagePath = req.file.path;
    const mimeType = req.file.mimetype || 'image/jpeg';
    const ext = path.extname(imagePath).toLowerCase();

    console.log('🖼️ Starting ad image upload to Cloudflare R2...');
    console.log('📁 File path:', imagePath);
    console.log('📊 File size:', (req.file.size / 1024 / 1024).toFixed(2), 'MB');
    console.log('📄 MIME type:', mimeType);

    try {
      // Determine uploader for directory structure
      const userId = req.user?.id || req.user?.googleId || 'anonymous';
      const fileName = path.basename(imagePath, ext);
      const key = `ads/images/${userId}/${fileName}${ext}`;

      const result = await cloudflareR2Service.uploadFileToR2(
        imagePath,
        key,
        mimeType
      );

      console.log('✅ Ad image uploaded to Cloudflare R2 successfully');
      console.log('🔗 Image URL:', result.url);
      console.log('🗝️ R2 Key:', result.key);

      // Clean up temp file
      await fs.unlink(imagePath);

      res.status(200).json({
        success: true,
        url: result.url,
        key: result.key,
        message: 'Image uploaded successfully',
      });
    } catch (r2Error) {
      console.error('❌ Cloudflare R2 upload failed:', r2Error);

      // Clean up temp file on error
      try {
        await fs.unlink(imagePath);
      } catch (unlinkError) {
        console.error('❌ Error cleaning up temp file:', unlinkError);
      }

      let userFriendlyError = 'Failed to upload image to cloud storage';
      const msg = r2Error.message || '';
      if (msg.includes('timeout')) {
        userFriendlyError =
          'Upload timeout. Please check your internet connection and try again.';
      } else if (msg.includes('file size') || msg.includes('too large')) {
        userFriendlyError =
          'Image file is too large. Please use an image smaller than 10MB.';
      } else if (msg.includes('Only image files are allowed')) {
        userFriendlyError =
          'Invalid image format. Please use JPG, PNG, GIF, or WebP.';
      }

      res.status(500).json({
        error: userFriendlyError,
        details: msg,
      });
    }
  } catch (error) {
    console.error('❌ Error in image upload route:', error);
    res.status(500).json({
      error: 'Image upload failed',
      details: error.message,
    });
  }
});

// **NEW: Game Upload Route**
// Uploads a ZIP file, extracts, validates index.html, and uploads to R2
router.post('/game', verifyToken, upload.single('game'), async (req, res) => {
  let extractDir = null;
  
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'No game ZIP file uploaded' });
    }

    const { title, description, orientation } = req.body;
    const userId = req.user.id;
    const zipPath = req.file.path;
    
    console.log('🎮 Starting Game Upload...');
    console.log('📁 ZIP Path:', zipPath);
    console.log('👤 Developer:', userId);

    // 1. Extract ZIP
    const zipName = path.basename(zipPath, path.extname(zipPath));
    extractDir = path.join(path.dirname(zipPath), zipName);
    
    try {
      const zip = new AdmZip(zipPath);
      zip.extractAllTo(extractDir, true);
      console.log('📦 Extracted to:', extractDir);
    } catch (zipError) {
      throw new Error(`Failed to extract ZIP: ${zipError.message}`);
    }

    // 2. Validate Structure (Must have index.html)
    // Recursive search for index.html
    async function findIndexHtml(dir) {
      const entries = await fs.readdir(dir, { withFileTypes: true });
      for (const entry of entries) {
        const fullPath = path.join(dir, entry.name);
        if (entry.isFile() && entry.name === 'index.html') {
          return fullPath;
        }
        if (entry.isDirectory()) {
          const found = await findIndexHtml(fullPath);
          if (found) return found;
        }
      }
      return null;
    }

    const indexHtmlPath = await findIndexHtml(extractDir);
    if (!indexHtmlPath) {
      throw new Error('Invalid Game: "index.html" not found in ZIP');
    }

    // Determine root folder (where index.html is)
    const gameRootDir = path.dirname(indexHtmlPath);
    console.log('🎯 Game Root found at:', gameRootDir);

    // 3. Upload to R2
    // We upload everything relative to gameRootDir
    
    // Create Game Record first to get ID
    const game = new Game({
      title: title || 'Untitled Game',
      description: description || '',
      thumbnailUrl: 'pending', // Will update after upload
      gameUrl: 'pending',
      developer: userId, // verifyToken populates req.user.id
      orientation: orientation || 'portrait',
      status: 'pending'
    });
    
    await game.save();
    
    // Recursive upload function
    let fileCount = 0;
    async function uploadDirToR2(currentDir, baseRelPath = '') {
      const entries = await fs.readdir(currentDir, { withFileTypes: true });
      
      for (const entry of entries) {
        const fullPath = path.join(currentDir, entry.name);
        const relPath = path.join(baseRelPath, entry.name).replace(/\\/g, '/');
        const r2Key = `games/${game._id}/${relPath}`;
        
        if (entry.isDirectory()) {
          await uploadDirToR2(fullPath, relPath);
        } else {
          // Upload file
          let contentType = 'application/octet-stream';
          if (entry.name.endsWith('.html')) contentType = 'text/html';
          else if (entry.name.endsWith('.js')) contentType = 'application/javascript';
          else if (entry.name.endsWith('.css')) contentType = 'text/css';
          else if (entry.name.endsWith('.json')) contentType = 'application/json';
          else if (entry.name.endsWith('.png')) contentType = 'image/png';
          else if (entry.name.endsWith('.jpg')) contentType = 'image/jpeg';
          
          await cloudflareR2Service.uploadFileToR2(fullPath, r2Key, contentType);
          fileCount++;
        }
      }
    }

    console.log('☁️ Uploading files to R2...');
    await uploadDirToR2(gameRootDir);
    console.log(`✅ Uploaded ${fileCount} files to R2`);

    // 4. Update Game Record
    const cdnBase = cloudflareR2Service.publicDomain 
      ? `https://${cloudflareR2Service.publicDomain}` 
      : `https://${cloudflareR2Service.bucketName}.${cloudflareR2Service.accountId}.r2.cloudflarestorage.com`;
      
    game.gameUrl = `${cdnBase}/games/${game._id}/index.html`;
    game.thumbnailUrl = `${cdnBase}/games/${game._id}/icon.png`; // Assumption: icon.png exists, or we use a default
    // TODO: Better thumbnail handling (allow separate upload or look for specific file)
    
    game.status = 'active'; // Auto-publish for now
    await game.save();

    // 5. Cleanup
    try {
      await fs.unlink(zipPath); // Delete ZIP
      await fs.rm(extractDir, { recursive: true, force: true }); // Delete extracted folder
    } catch (cleanupErr) {
      console.warn('⚠️ Cleanup warning:', cleanupErr.message);
    }

    res.status(201).json({
      success: true,
      message: 'Game uploaded successfully',
      game: {
        id: game._id,
        title: game.title,
        url: game.gameUrl
      }
    });

  } catch (error) {
    console.error('❌ Game Upload Error:', error);
    
    // Cleanup on error
    if (req.file) {
      try {
        await fs.unlink(req.file.path);
        if (extractDir) await fs.rm(extractDir, { recursive: true, force: true });
      } catch (e) { /* ignore */ }
    }

    res.status(500).json({
      error: 'Game upload failed',
      details: error.message
    });
  }
});

// **NEW: Get video processing status endpoint**
router.get('/video/:videoId/status', verifyToken, async (req, res) => {
  try {
    const { videoId } = req.params;
    const userId = req.user.id;

    console.log('🔍 Status check request:', { videoId, userId });

    // Validate video ID
    if (!videoId || !mongoose.Types.ObjectId.isValid(videoId)) {
      return res.status(400).json({
        success: false,
        error: 'Invalid video ID'
      });
    }

    // Find the video
    const video = await Video.findById(videoId);
    if (!video) {
      return res.status(404).json({
        success: false,
        error: 'Video not found'
      });
    }

    // **FIX: Compare against the user's ObjectId, not Google ID**
    const owner = await User.findOne({ googleId: userId });
    if (!owner || video.uploader.toString() !== owner._id.toString()) {
      return res.status(403).json({
        success: false,
        error: 'Access denied'
      });
    }

    // Return processing status
    const statusResponse = {
      success: true,
      video: {
        _id: video._id,
        videoName: video.videoName,
        processingStatus: video.processingStatus || 'pending',
        processingProgress: video.processingProgress || 0,
        processingError: video.processingError || null,
        videoUrl: video.videoUrl || null,
        thumbnailUrl: video.thumbnailUrl || null,
        uploadedAt: video.uploadedAt,
        estimatedTime: '2-5 minutes depending on video length'
      }
    };

    console.log('✅ Status response:', statusResponse.video.processingStatus);
    res.json(statusResponse);

  } catch (error) {
    console.error('❌ Error getting video status:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get video status',
      details: error.message
    });
  }
});

export default router;

