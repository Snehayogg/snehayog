import dotenv from 'dotenv';
import mongoose from 'mongoose';
import './models/index.js';
import Video from './models/Video.js';

dotenv.config();

async function main() {
  console.log('🔍 Debug /api/videos – simple query check');

  const mongoUri = process.env.MONGO_URI || process.env.MONGODB_URI;
  if (!mongoUri) {
    console.error('❌ No Mongo URI found in env (MONGO_URI or MONGODB_URI)');
    process.exit(1);
  }

  console.log('🔌 Connecting to MongoDB (URI hidden)...');
  try {
    await mongoose.connect(mongoUri, {
      useNewUrlParser: true,
      useUnifiedTopology: true,
      serverSelectionTimeoutMS: 30000,
      socketTimeoutMS: 45000,
      connectTimeoutMS: 30000,
    });
    console.log('✅ MongoDB connected');
  } catch (err) {
    console.error('❌ MongoDB connection failed:');
    console.error('   name   :', err.name);
    console.error('   message:', err.message);
    console.error('   stack  :', err.stack);
    process.exit(1);
  }

  const page = 1;
  const limit = 10;
  const videoType = 'yog'; // adjust if needed

  const pageNum = Math.max(1, parseInt(page, 10) || 1);
  const limitNum = Math.min(50, Math.max(1, parseInt(limit, 10) || 10));
  const skip = (pageNum - 1) * limitNum;

  const filter = {
    uploader: { $exists: true, $ne: null },
    videoUrl: {
      $exists: true,
      $ne: null,
      $ne: '',
      $not: /^uploads[\\\/]/,
      $regex: /^https?:\/\//
    },
    processingStatus: 'completed',
  };

  if (videoType) {
    const normalizedType = String(videoType).toLowerCase();
    const normalizedVideoType = normalizedType === 'vayug' ? 'vayu' : normalizedType;
    if (['yog', 'vayu'].includes(normalizedVideoType)) {
      filter.videoType = normalizedVideoType;
    }
  }

  console.log('🔍 Using filter:', JSON.stringify(filter, null, 2));
  console.log('🔍 page:', pageNum, 'limit:', limitNum, 'skip:', skip);

  try {
    console.log('🔍 Running Video.find + countDocuments...');
    const [videos, total] = await Promise.all([
      Video.find(filter)
        .populate('uploader', 'googleId name profileImageUrl')
        .sort({ createdAt: -1 })
        .skip(skip)
        .limit(limitNum)
        .lean(),
      Video.countDocuments(filter),
    ]);

    console.log('✅ Query succeeded');
    console.log('   total:', total);
    console.log('   videos.length:', videos.length);
    if (videos[0]) {
      console.log('   first video sample:', {
        _id: videos[0]._id,
        videoName: videos[0].videoName,
        videoUrl: videos[0].videoUrl,
        videoType: videos[0].videoType,
      });
    }
  } catch (err) {
    console.error('❌ ERROR in Video query:');
    console.error('   name   :', err.name);
    console.error('   message:', err.message);
    console.error('   stack  :', err.stack);
  } finally {
    await mongoose.disconnect();
    console.log('🔌 MongoDB disconnected');
    process.exit(0);
  }
}

main().catch((e) => {
  console.error('❌ Fatal error in debug script:', e);
  process.exit(1);
});

