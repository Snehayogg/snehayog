/**
 * Diagnostic Script - Check Video Classification Status
 */

import mongoose from 'mongoose';
import Video from '../models/Video.js';
import dotenv from 'dotenv';

dotenv.config();

async function diagnoseVideoClassification() {
  try {
    console.log('🔍 Diagnosing Video Classification...\n');
    
    await mongoose.connect(process.env.MONGO_URI);
    console.log('✅ Connected to MongoDB\n');

    // Get sample of vayu videos
    const vayuSample = await Video.find({ videoType: 'vayu', processingStatus: 'completed' })
      .select('videoName aspectRatio originalResolution')
      .limit(10);

    console.log('📋 SAMPLE VAYU VIDEOS (should be landscape):');
    console.log('─'.repeat(80));
    vayuSample.forEach((v, i) => {
      console.log(`${i + 1}. "${v.videoName}"`);
      console.log(`   AR: ${v.aspectRatio?.toFixed(4)} | Resolution: ${v.originalResolution?.width}x${v.originalResolution?.height}`);
      console.log(`   Is Landscape? ${(v.aspectRatio > 1.0 ? '✅ Yes' : '❌ No (should be yog!)')}`);
      console.log();
    });

    // Get all yog videos
    const yogVideos = await Video.find({ videoType: 'yog', processingStatus: 'completed' })
      .select('videoName aspectRatio originalResolution')
      .limit(10);

    console.log('\n📋 YOG VIDEOS (should be portrait):');
    console.log('─'.repeat(80));
    if (yogVideos.length === 0) {
      console.log('⚠️  NO YOG VIDEOS FOUND! This is the problem.');
    } else {
      yogVideos.forEach((v, i) => {
        console.log(`${i + 1}. "${v.videoName}"`);
        console.log(`   AR: ${v.aspectRatio?.toFixed(4)} | Resolution: ${v.originalResolution?.width}x${v.originalResolution?.height}`);
      });
    }

    // Statistics
    console.log('\n\n📊 CLASSIFICATION STATISTICS:');
    console.log('='.repeat(80));
    
    const totalVideos = await Video.countDocuments({ processingStatus: 'completed' });
    const vayuCount = await Video.countDocuments({ videoType: 'vayu', processingStatus: 'completed' });
    const yogCount = await Video.countDocuments({ videoType: 'yog', processingStatus: 'completed' });
    
    console.log(`Total Videos: ${totalVideos}`);
    console.log(`Vayu (landscape): ${vayuCount} (${(vayuCount/totalVideos*100).toFixed(1)}%)`);
    console.log(`Yog (portrait): ${yogCount} (${(yogCount/totalVideos*100).toFixed(1)}%)`);

    // Check aspect ratio distribution
    const arDistribution = await Video.aggregate([
      { $match: { processingStatus: 'completed' } },
      {
        $group: {
          _id: {
            $cond: [
              { $gte: ['$aspectRatio', 1.0] },
              'AR >= 1.0 (should be vayu)',
              'AR < 1.0 (should be yog)'
            ]
          },
          count: { $sum: 1 },
          avgAR: { $avg: '$aspectRatio' }
        }
      }
    ]);

    console.log('\n📐 ASPECT RATIO DISTRIBUTION:');
    console.log('─'.repeat(80));
    arDistribution.forEach(dist => {
      console.log(`${dist._id}: ${dist.count} videos (avg AR: ${dist.avgAR?.toFixed(3)})`);
    });

    // Find suspect videos (high AR but might be vertical with rotation)
    const suspectCount = await Video.countDocuments({
      processingStatus: 'completed',
      videoType: 'vayu',
      aspectRatio: { $gte: 1.5 },
      $or: [
        { 'originalResolution.width': 1920, 'originalResolution.height': 1080 },
        { 'originalResolution.width': 1280, 'originalResolution.height': 720 },
        { 'originalResolution.width': 3840, 'originalResolution.height': 2160 }
      ]
    });

    console.log(`\n🔍 SUSPECT MISCLASSIFIED VIDEOS: ${suspectCount}`);
    console.log('   (These have landscape resolution but might be vertical with rotation metadata)');

    await mongoose.disconnect();
    
  } catch (error) {
    console.error('\n❌ Error:', error);
    process.exit(1);
  }
}

diagnoseVideoClassification();
