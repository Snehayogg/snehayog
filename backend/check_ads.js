import mongoose from 'mongoose';
import AdCreative from './models/AdCreative.js';
import AdCampaign from './models/AdCampaign.js';

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

const checkAds = async () => {
  try {
    await connectDB();
    
    console.log('\n🔍 Checking Ad Creatives...');
    const adCreatives = await AdCreative.find({}).populate('campaignId', 'status name');
    console.log(`Found ${adCreatives.length} ad creatives:`);
    
    adCreatives.forEach((ad, index) => {
      console.log(`\n${index + 1}. Ad ID: ${ad._id}`);
      console.log(`   Title: ${ad.title}`);
      console.log(`   Ad Type: ${ad.adType}`);
      console.log(`   isActive: ${ad.isActive}`);
      console.log(`   reviewStatus: ${ad.reviewStatus}`);
      console.log(`   Campaign Status: ${ad.campaignId ? ad.campaignId.status : 'No campaign'}`);
      console.log(`   Created: ${ad.createdAt}`);
    });
    
    console.log('\n🔍 Checking Ad Campaigns...');
    const campaigns = await AdCampaign.find({});
    console.log(`Found ${campaigns.length} campaigns:`);
    
    campaigns.forEach((campaign, index) => {
      console.log(`\n${index + 1}. Campaign ID: ${campaign._id}`);
      console.log(`   Name: ${campaign.name}`);
      console.log(`   Status: ${campaign.status}`);
      console.log(`   Budget: ${campaign.dailyBudget}`);
      console.log(`   Created: ${campaign.createdAt}`);
    });
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Error checking ads:', error);
    process.exit(1);
  }
};

checkAds();
