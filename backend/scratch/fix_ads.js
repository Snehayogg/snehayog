import mongoose from 'mongoose';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';


const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load environment variables from backend root
dotenv.config({ path: path.join(__dirname, '../.env') });

const MONGO_URI = process.env.MONGO_URI || 'mongodb://localhost:27017/vayu';

async function fixAds() {
  try {
    console.log('📡 Connecting to MongoDB...');
    await mongoose.connect(MONGO_URI);
    console.log('✅ Connected to MongoDB');

    // Get models
    const AdCampaign = mongoose.model('AdCampaign');
    const AdCreative = mongoose.model('AdCreative');
    const User = mongoose.model('User');

    // 1. Find or create an advertiser user
    let advertiser = await User.findOne({ role: 'admin' });
    if (!advertiser) {
      advertiser = await User.findOne({});
    }
    
    if (!advertiser) {
      console.log('❌ No user found to act as advertiser. Please create a user first.');
      process.exit(1);
    }

    console.log(`👤 Using advertiser: ${advertiser.name} (${advertiser._id})`);

    // 2. Create an active campaign if none exists
    let campaign = await AdCampaign.findOne({ status: 'active' });
    if (!campaign) {
      console.log('📝 Creating new active campaign...');
      campaign = new AdCampaign({
        name: 'Test Banner Campaign',
        advertiserUserId: advertiser._id,
        objective: 'awareness',
        status: 'active',
        startDate: new Date(),
        endDate: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000), // 30 days from now
        dailyBudget: 1000,
        totalBudget: 30000,
        bidType: 'CPM',
        cpmINR: 20,
        target: {
          locations: ['India'],
          interests: ['Yoga', 'Wellness']
        },
        pacing: 'smooth'
      });
      await campaign.save();
      console.log('✅ Campaign created');
    } else {
      console.log('✅ Found existing active campaign');
    }

    // 3. Create or Update a Banner Ad Creative
    // We search for existing banner ads to update them to 'active'
    console.log('🖼️ Cleaning up and creating banner ads...');
    
    // Update any existing banner ads to be active and valid
    const updateResult = await AdCreative.updateMany(
      { adType: 'banner' },
      { 
        $set: { 
          isActive: true, 
          reviewStatus: 'approved',
          status: 'active',
          aspectRatio: '16:9', // Ensure this is present
          'callToAction.label': 'Shop Now' // Ensure valid enum
        } 
      }
    );
    console.log(`✅ Updated ${updateResult.modifiedCount} existing banner ads to active.`);

    // Create a fresh one just in case
    const bannerAd = new AdCreative({
      campaignId: campaign._id,
      advertiserId: advertiser._id,
      title: 'Premium Yoga Mats',
      description: 'Get 20% off on your first purchase!',
      adType: 'banner',
      type: 'image',
      cloudinaryUrl: 'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?auto=format&fit=crop&w=800&q=80',
      thumbnail: 'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?auto=format&fit=crop&w=200&q=80',
      aspectRatio: '16:9', // MANDATORY
      isActive: true,
      reviewStatus: 'approved',
      status: 'active',
      callToAction: {
        label: 'Shop Now', // Must match enum in schema
        url: 'https://example.com/shop'
      },
      targetKeywords: ['yoga', 'mats', 'wellness'],
      impressions: 0,
      clicks: 0
    });

    await bannerAd.save();
    console.log('✅ Fresh banner ad created successfully');

    console.log('\n🚀 Success! Restart your app and check the Yug tab.');
    console.log('Note: If you still see the "SSL Handshake" error on image loading, it might be your device network.');
    
    process.exit(0);
  } catch (error) {
    console.error('❌ Error fixing ads:', error);
    process.exit(1);
  }
}

fixAds();
