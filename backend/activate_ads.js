import mongoose from 'mongoose';
import AdCreative from './models/AdCreative.js';

async function activateExistingAds() {
  try {
    // Use Railway MongoDB connection string
    const mongoUri = process.env.MONGODB_URI || 'mongodb://localhost:27017/snehayog';
    await mongoose.connect(mongoUri);
    console.log('Connected to MongoDB');
    
    // Find all ads that are not active
    const inactiveAds = await AdCreative.find({
      $or: [
        { isActive: { $ne: true } },
        { reviewStatus: { $ne: 'approved' } }
      ]
    });
    
    console.log(`Found ${inactiveAds.length} inactive ads`);
    
    // Activate all ads
    for (const ad of inactiveAds) {
      ad.isActive = true;
      ad.reviewStatus = 'approved';
      await ad.save();
      console.log(`Activated ad: ${ad._id} (${ad.adType})`);
    }
    
    console.log('All ads activated successfully!');
    process.exit(0);
  } catch (error) {
    console.error('Error:', error);
    process.exit(1);
  }
}

activateExistingAds();
