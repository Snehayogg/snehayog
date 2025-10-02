import mongoose from 'mongoose';
import fs from 'fs';
import path from 'path';
import hybridVideoService from '../services/hybridVideoService.js';
import cloudflareR2Service from '../services/cloudflareR2Service.js';

// Database connection
const connectDB = async () => {
  try {
    await mongoose.connect(process.env.MONGODB_URI || process.env.MONGO_URI);
    console.log('✅ Connected to MongoDB');
  } catch (error) {
    console.error('❌ MongoDB connection error:', error);
    process.exit(1);
  }
};

// Test the hybrid video processing
const testHybridProcessing = async () => {
  try {
    console.log('🧪 Testing Hybrid Video Processing...');
    console.log('💰 Expected: 93% cost savings vs current setup');
    
    // Create a test video file (you can replace this with an actual video)
    const testVideoPath = path.join(process.cwd(), 'test-video.mp4');
    
    // Check if test video exists
    if (!fs.existsSync(testVideoPath)) {
      console.log('❌ Test video not found. Please place a test video at:', testVideoPath);
      console.log('💡 You can use any MP4 video file for testing');
      return;
    }
    
    console.log('📁 Test video found:', testVideoPath);
    
    // Test hybrid processing
    const result = await hybridVideoService.processVideoHybrid(
      testVideoPath,
      'test-video-hybrid',
      'test-user-id'
    );
    
    console.log('🎉 Hybrid processing test completed!');
    console.log('📊 Results:');
    console.log('   - Video URL:', result.videoUrl);
    console.log('   - Thumbnail URL:', result.thumbnailUrl);
    console.log('   - Format:', result.format);
    console.log('   - Quality:', result.quality);
    console.log('   - Storage:', result.storage);
    console.log('   - Bandwidth:', result.bandwidth);
    console.log('   - Cost Savings:', result.costSavings);
    console.log('   - HLS Encoded:', result.hlsEncoded);
    
    // Test R2 service
    console.log('\n🧪 Testing R2 Service...');
    const r2Test = await cloudflareR2Service.testConnection();
    console.log('R2 Connection Test:', r2Test);
    
  } catch (error) {
    console.error('❌ Test failed:', error);
  }
};

// Test cost estimation
const testCostEstimation = () => {
  console.log('\n💰 Cost Estimation Test:');
  
  const estimates = [
    { size: 50, views: 1000 },   // 50MB video, 1000 views
    { size: 100, views: 5000 },  // 100MB video, 5000 views
    { size: 200, views: 10000 }, // 200MB video, 10000 views
  ];
  
  estimates.forEach(({ size, views }) => {
    const cost = hybridVideoService.getCostEstimate(size, views);
    console.log(`\n📊 ${size}MB video, ${views} views:`);
    console.log(`   - Processing: $${cost.processing}`);
    console.log(`   - Storage/month: $${cost.storagePerMonth.toFixed(4)}`);
    console.log(`   - Bandwidth: $${cost.bandwidth} (FREE!)`);
    console.log(`   - Total/month: $${cost.totalPerMonth.toFixed(4)}`);
    console.log(`   - Savings: ${cost.savingsVsCurrent}`);
  });
};

// Main test function
const runTests = async () => {
  try {
    await connectDB();
    await testHybridProcessing();
    testCostEstimation();
    
    console.log('\n✅ All tests completed!');
    console.log('\n🚀 Next steps:');
    console.log('1. Set up cdn.snehayog.site in Cloudflare');
    console.log('2. Add CLOUDFLARE_R2_PUBLIC_DOMAIN to your .env');
    console.log('3. Test video upload through your app');
    console.log('4. Monitor cost savings in Cloudflare dashboard');
    
  } catch (error) {
    console.error('❌ Test suite failed:', error);
  } finally {
    process.exit(0);
  }
};

// Run tests
runTests();
