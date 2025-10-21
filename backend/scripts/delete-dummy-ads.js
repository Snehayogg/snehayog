import mongoose from 'mongoose';
import AdCreative from '../models/AdCreative.js';
import AdCampaign from '../models/AdCampaign.js';

// Connect to MongoDB
const connectDB = async () => {
  try {
    await mongoose.connect(process.env.MONGODB_URI || 'mongodb://localhost:27017/snehayog');
    console.log('✅ Connected to MongoDB');
  } catch (error) {
    console.error('❌ MongoDB connection error:', error);
    process.exit(1);
  }
};

// Delete all dummy/placeholder ads
const deleteDummyAds = async () => {
  try {
    console.log('🗑️ Starting to delete dummy ads...');
    
    // Find ads with dummy/placeholder content
    const dummyAds = await AdCreative.find({
      $or: [
        { 'callToAction.label': 'Learn More' },
        { 'callToAction.url': 'https://example.com' },
        { cloudinaryUrl: { $regex: /placeholder|dummy|test/i } },
        { title: { $regex: /ad image|advertiser|sponsored|dummy|test|placeholder/i } },
        { description: { $regex: /ad image|advertiser|sponsored|dummy|test|placeholder/i } }
      ]
    });

    console.log(`🔍 Found ${dummyAds.length} dummy ads to delete`);

    if (dummyAds.length > 0) {
      // Delete the ads
      const result = await AdCreative.deleteMany({
        _id: { $in: dummyAds.map(ad => ad._id) }
      });

      console.log(`✅ Deleted ${result.deletedCount} dummy ads`);

      // Also delete associated campaigns if they exist
      const campaignIds = dummyAds
        .map(ad => ad.campaignId)
        .filter(id => id !== null);

      if (campaignIds.length > 0) {
        const campaignResult = await AdCampaign.deleteMany({
          _id: { $in: campaignIds }
        });
        console.log(`✅ Deleted ${campaignResult.deletedCount} associated campaigns`);
      }
    } else {
      console.log('✅ No dummy ads found');
    }

    // Also delete any ads with empty or null cloudinaryUrl
    const emptyAds = await AdCreative.find({
      $or: [
        { cloudinaryUrl: { $exists: false } },
        { cloudinaryUrl: null },
        { cloudinaryUrl: '' }
      ]
    });

    if (emptyAds.length > 0) {
      const emptyResult = await AdCreative.deleteMany({
        _id: { $in: emptyAds.map(ad => ad._id) }
      });
      console.log(`✅ Deleted ${emptyResult.deletedCount} ads with empty URLs`);
    }

    console.log('🎉 Dummy ads cleanup completed!');
    
  } catch (error) {
    console.error('❌ Error deleting dummy ads:', error);
  }
};

// Main execution
const main = async () => {
  await connectDB();
  await deleteDummyAds();
  await mongoose.disconnect();
  console.log('✅ Disconnected from MongoDB');
  process.exit(0);
};

main();
