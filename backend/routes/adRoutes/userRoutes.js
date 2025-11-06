import express from 'express';
import AdCampaign from '../../models/AdCampaign.js';
import AdCreative from '../../models/AdCreative.js';
import Invoice from '../../models/Invoice.js';
import User from '../../models/User.js';
import { verifyToken } from '../../utils/verifytoken.js';

const router = express.Router();

// **FIXED: Get user's ads with proper authentication and user lookup**
router.get('/user/:userId', verifyToken, async (req, res) => {
  try {
    const { userId } = req.params;
    
    console.log('🔍 Get user ads - Debug info:');
    console.log('  - URL userId:', userId);
    console.log('  - req.user:', JSON.stringify(req.user, null, 2));
    
    // **NEW: Find user by Google ID to get MongoDB ObjectId**
    const user = await User.findOne({ googleId: userId });
    if (!user) {
      console.log('❌ User not found with Google ID:', userId);
      return res.status(404).json({ 
        error: 'User not found',
        debug: { requestedGoogleId: userId }
      });
    }
    
    console.log('✅ Found user:', user._id, 'for Google ID:', userId);
    
    // **FIXED: Use MongoDB ObjectId for database query**
    const campaigns = await AdCampaign.find({ advertiserUserId: user._id })
      .sort({ createdAt: -1 });

    console.log(`🔍 Found ${campaigns.length} campaigns for user ${user._id}`);

    // **FIXED: Handle case when no ads are found**
    if (campaigns.length === 0) {
      console.log(`ℹ️ No ads found for user ${user._id} - returning empty array`);
      return res.json([]);
    }

    // **ENHANCED: Get creatives for each campaign and merge data**
    const adsWithCreatives = await Promise.all(
      campaigns.map(async (campaign) => {
        // Find creative for this campaign
        const creative = await AdCreative.findOne({ campaignId: campaign._id });
        
        // Use creative data if available, otherwise use campaign defaults
        const impressions = creative?.impressions || campaign.impressions || 0;
        const clicks = creative?.clicks || campaign.clicks || 0;
        const imageUrl = creative?.cloudinaryUrl || creative?.thumbnail || null;
        const adType = creative?.adType || 'banner';
        const link = creative?.callToAction?.url || null;
        
        return {
          _id: campaign._id.toString(),
          id: campaign._id.toString(),
          creativeId: creative?._id?.toString() || null, // **NEW: Include creative ID for analytics**
          title: creative?.title || campaign.name,
          description: creative?.description || campaign.objective || '',
          imageUrl: imageUrl,
          videoUrl: creative?.type === 'video' ? creative.cloudinaryUrl : null,
          link: link,
          adType: adType,
          budget: campaign.dailyBudget * 100, // Convert to cents for frontend
          totalBudget: campaign.totalBudget * 100, // Convert to cents for frontend
          spend: campaign.spend ? Math.round(campaign.spend * 100) : 0, // Convert to cents
          impressions: impressions, // **FIX: Use creative impressions if available**
          clicks: clicks, // **FIX: Use creative clicks if available**
          status: campaign.status,
          startDate: campaign.startDate ? campaign.startDate.toISOString() : null,
          endDate: campaign.endDate ? campaign.endDate.toISOString() : null,
          createdAt: campaign.createdAt.toISOString(),
          updatedAt: campaign.updatedAt.toISOString(),
      
      // **NEW: Additional fields for enhanced ad management**
      campaignId: campaign._id.toString(),
      campaignName: campaign.name,
      objective: campaign.objective,
      dailyBudget: campaign.dailyBudget,
      bidAmount: campaign.bidAmount || 0,
      
      // **NEW: Targeting information**
      targeting: {
        ageMin: campaign.target?.age?.min || 18,
        ageMax: campaign.target?.age?.max || 65,
        gender: campaign.target?.gender || 'all',
        locations: campaign.target?.locations || [],
        interests: campaign.target?.interests || [],
        platforms: campaign.target?.platforms || [],
        deviceType: campaign.target?.deviceType || 'all'
      },
      
      // **NEW: Performance metrics**
      metrics: {
        ctr: impressions > 0 ? 
          ((clicks || 0) / impressions * 100).toFixed(2) : '0.00',
        cpc: clicks > 0 ? 
          ((campaign.spend || 0) / clicks).toFixed(2) : '0.00',
        cpm: impressions > 0 ? 
          ((campaign.spend || 0) / impressions * 1000).toFixed(2) : '0.00'
      }
        };
      })
    );

    console.log(`✅ Returning ${adsWithCreatives.length} formatted ads for user ${user._id}`);
    res.json(adsWithCreatives);

  } catch (error) {
    console.error('❌ Error fetching user ads:', error);
    res.status(500).json({ 
      error: 'Failed to fetch user ads',
      details: error.message 
    });
  }
});

// **NEW: Delete ad campaign**
router.delete('/:adId', verifyToken, async (req, res) => {
  try {
    const { adId } = req.params;
    
    console.log('🗑️ Delete ad request - Debug info:');
    console.log('  - adId:', adId);
    console.log('  - req.user:', JSON.stringify(req.user, null, 2));

    // Find the campaign
    const campaign = await AdCampaign.findById(adId);
    if (!campaign) {
      console.log('❌ Campaign not found:', adId);
      return res.status(404).json({ error: 'Ad campaign not found' });
    }

    console.log('✅ Found campaign:', campaign._id, 'advertiser:', campaign.advertiserUserId);

    // **FIXED: Verify ownership using proper user lookup**
    const user = await User.findOne({ googleId: req.user.googleId });
    if (!user) {
      console.log('❌ User not found with Google ID:', req.user.googleId);
      return res.status(404).json({ error: 'User not found' });
    }

    console.log('✅ Found user:', user._id, 'for Google ID:', req.user.googleId);

    if (campaign.advertiserUserId.toString() !== user._id.toString()) {
      console.log('❌ Access denied - Campaign owner:', campaign.advertiserUserId, 'User:', user._id);
      return res.status(403).json({ error: 'Access denied - not your ad' });
    }

    console.log('✅ Ownership verified, proceeding with deletion');

    // Delete associated creative if exists
    if (campaign.creative) {
      console.log('🗑️ Deleting associated creative:', campaign.creative);
      await AdCreative.findByIdAndDelete(campaign.creative);
    }

    // Delete associated invoices
    console.log('🗑️ Deleting associated invoices for campaign:', adId);
    await Invoice.deleteMany({ campaignId: adId });

    // Delete the campaign
    console.log('🗑️ Deleting campaign:', adId);
    await AdCampaign.findByIdAndDelete(adId);

    console.log('✅ Ad campaign deleted successfully:', adId);

    res.json({ 
      success: true, 
      message: 'Ad campaign deleted successfully' 
    });
  } catch (error) {
    console.error('❌ Delete ad error:', error);
    res.status(500).json({ 
      error: 'Failed to delete ad',
      details: error.message 
    });
  }
});

export default router;
