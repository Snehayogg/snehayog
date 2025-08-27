// Test script for ad type functionality
// Run with: node test_ad_types.js

import mongoose from 'mongoose';
import AdCreative from './models/AdCreative.js';

// Test data
const testCreatives = [
  {
    campaignId: new mongoose.Types.ObjectId(), // Mock campaign ID
    adType: 'banner',
    type: 'image',
    cloudinaryUrl: 'https://example.com/banner.jpg',
    thumbnail: 'https://example.com/banner.jpg',
    aspectRatio: '16:9',
    callToAction: {
      label: 'Shop Now',
      url: 'https://example.com/shop'
    }
  },
  {
    campaignId: new mongoose.Types.ObjectId(), // Mock campaign ID
    adType: 'carousel ads',
    type: 'video',
    cloudinaryUrl: 'https://example.com/carousel.mp4',
    thumbnail: 'https://example.com/carousel-thumb.jpg',
    aspectRatio: '9:16',
    durationSec: 30,
    callToAction: {
      label: 'Learn More',
      url: 'https://example.com/learn'
    }
  },
  {
    campaignId: new mongoose.Types.ObjectId(), // Mock campaign ID
    adType: 'video feeds',
    type: 'image',
    cloudinaryUrl: 'https://example.com/videofeed.jpg',
    thumbnail: 'https://example.com/videofeed.jpg',
    aspectRatio: '1:1',
    callToAction: {
      label: 'Download',
      url: 'https://example.com/download'
    }
  }
];

// Test validation
async function testValidation() {
  console.log('🧪 Testing ad type validation...\n');

  for (const creativeData of testCreatives) {
    try {
      const creative = new AdCreative(creativeData);
      await creative.save();
      console.log(`✅ ${creativeData.adType} - ${creativeData.type}: Validation passed`);
    } catch (error) {
      console.log(`❌ ${creativeData.adType} - ${creativeData.type}: ${error.message}`);
    }
  }

  // Test invalid combinations
  console.log('\n🧪 Testing invalid combinations...\n');

  const invalidCreative = new AdCreative({
    campaignId: new mongoose.Types.ObjectId(),
    adType: 'banner',
    type: 'video', // This should fail for banner ads
    cloudinaryUrl: 'https://example.com/banner.mp4',
    thumbnail: 'https://example.com/banner-thumb.jpg',
    aspectRatio: '16:9',
    durationSec: 30,
    callToAction: {
      label: 'Shop Now',
      url: 'https://example.com/shop'
    }
  });

  try {
    await invalidCreative.save();
    console.log('❌ Banner ad with video: Should have failed but passed');
  } catch (error) {
    console.log('✅ Banner ad with video: Correctly rejected -', error.message);
  }
}

// Test ad type filtering
async function testFiltering() {
  console.log('\n🧪 Testing ad type filtering...\n');

  try {
    // Test finding banner ads
    const bannerAds = await AdCreative.find({ adType: 'banner' });
    console.log(`✅ Found ${bannerAds.length} banner ads`);

    // Test finding carousel ads
    const carouselAds = await AdCreative.find({ adType: 'carousel ads' });
    console.log(`✅ Found ${carouselAds.length} carousel ads`);

    // Test finding video feed ads
    const videoFeedAds = await AdCreative.find({ adType: 'video feeds' });
    console.log(`✅ Found ${videoFeedAds.length} video feed ads`);

    // Test finding all video content
    const videoAds = await AdCreative.find({ type: 'video' });
    console.log(`✅ Found ${videoAds.length} video ads`);

    // Test finding all image content
    const imageAds = await AdCreative.find({ type: 'image' });
    console.log(`✅ Found ${imageAds.length} image ads`);

  } catch (error) {
    console.log('❌ Filtering test failed:', error.message);
  }
}

// Main test function
async function runTests() {
  try {
    // Connect to MongoDB (you'll need to set up connection)
    // await mongoose.connect('your_mongodb_connection_string');
    
    console.log('🚀 Starting ad type validation tests...\n');
    
    await testValidation();
    await testFiltering();
    
    console.log('\n🎉 All tests completed!');
    
  } catch (error) {
    console.error('❌ Test execution failed:', error);
  } finally {
    // Close connection
    // await mongoose.connection.close();
  }
}

// Run tests if this file is executed directly
if (import.meta.url === `file://${process.argv[1]}`) {
  runTests();
}

export { testValidation, testFiltering };
