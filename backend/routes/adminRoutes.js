import express from 'express';
import AdCreative from '../models/AdCreative.js';
import AdCampaign from '../models/AdCampaign.js';

const router = express.Router();

// **NEW: Remove test carousel ads**
router.delete('/cleanup-test-carousel-ads', async (req, res) => {
  try {
    console.log('🗑️ Starting to delete test carousel ads...');
    
    // Find test carousel ads
    const testCarouselAds = await AdCreative.find({
      adType: 'carousel',
      $or: [
        { 'callToAction.label': 'Learn More' },
        { 'callToAction.url': 'https://example.com' },
        { advertiserName: { $regex: /test|dummy|placeholder/i } },
        { title: { $regex: /test|dummy|placeholder/i } },
        { description: { $regex: /test|dummy|placeholder/i } }
      ]
    });

    console.log(`🔍 Found ${testCarouselAds.length} test carousel ads to delete`);

    let deletedCount = 0;
    let deletedCampaigns = 0;

    if (testCarouselAds.length > 0) {
      // Show what we're about to delete
      console.log('📋 Test carousel ads to be deleted:');
      testCarouselAds.forEach((ad, index) => {
        console.log(`   ${index + 1}. ${ad.title || 'No title'} - ${ad.slides?.length || 0} slides`);
      });

      // Delete the ads
      const result = await AdCreative.deleteMany({
        _id: { $in: testCarouselAds.map(ad => ad._id) }
      });

      deletedCount = result.deletedCount;
      console.log(`✅ Deleted ${deletedCount} test carousel ads`);

      // Also delete associated campaigns if they exist
      const campaignIds = testCarouselAds
        .map(ad => ad.campaignId)
        .filter(id => id !== null);

      if (campaignIds.length > 0) {
        const campaignResult = await AdCampaign.deleteMany({
          _id: { $in: campaignIds }
        });
        deletedCampaigns = campaignResult.deletedCount;
        console.log(`✅ Deleted ${deletedCampaigns} associated campaigns`);
      }
    }

    console.log('🎉 Test carousel ads cleanup completed!');
    
    res.json({
      success: true,
      message: 'Test carousel ads cleanup completed',
      deletedAds: deletedCount,
      deletedCampaigns: deletedCampaigns,
      totalDeleted: deletedCount
    });
    
  } catch (error) {
    console.error('❌ Error deleting test carousel ads:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete test carousel ads',
      message: error.message
    });
  }
});

// Delete all dummy/placeholder ads
router.delete('/cleanup-dummy-ads', async (req, res) => {
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

    let deletedCount = 0;
    let deletedCampaigns = 0;

    if (dummyAds.length > 0) {
      // Show what we're about to delete
      console.log('📋 Dummy ads to be deleted:');
      dummyAds.forEach((ad, index) => {
        console.log(`   ${index + 1}. ${ad.title || 'No title'} - ${ad.callToAction?.label || 'No CTA'}`);
      });

      // Delete the ads
      const result = await AdCreative.deleteMany({
        _id: { $in: dummyAds.map(ad => ad._id) }
      });

      deletedCount = result.deletedCount;
      console.log(`✅ Deleted ${deletedCount} dummy ads`);

      // Also delete associated campaigns if they exist
      const campaignIds = dummyAds
        .map(ad => ad.campaignId)
        .filter(id => id !== null);

      if (campaignIds.length > 0) {
        const campaignResult = await AdCampaign.deleteMany({
          _id: { $in: campaignIds }
        });
        deletedCampaigns = campaignResult.deletedCount;
        console.log(`✅ Deleted ${deletedCampaigns} associated campaigns`);
      }
    }

    // Also delete any ads with empty or null cloudinaryUrl
    const emptyAds = await AdCreative.find({
      $or: [
        { cloudinaryUrl: { $exists: false } },
        { cloudinaryUrl: null },
        { cloudinaryUrl: '' }
      ]
    });

    let deletedEmptyAds = 0;
    if (emptyAds.length > 0) {
      console.log(`🔍 Found ${emptyAds.length} ads with empty URLs to delete`);
      const emptyResult = await AdCreative.deleteMany({
        _id: { $in: emptyAds.map(ad => ad._id) }
      });
      deletedEmptyAds = emptyResult.deletedCount;
      console.log(`✅ Deleted ${deletedEmptyAds} ads with empty URLs`);
    }

    console.log('🎉 Dummy ads cleanup completed!');
    
    res.json({
      success: true,
      message: 'Dummy ads cleanup completed',
      deletedAds: deletedCount,
      deletedCampaigns: deletedCampaigns,
      deletedEmptyAds: deletedEmptyAds,
      totalDeleted: deletedCount + deletedEmptyAds
    });
    
  } catch (error) {
    console.error('❌ Error deleting dummy ads:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to delete dummy ads',
      message: error.message
    });
  }
});

export default router;