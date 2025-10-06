import express from 'express';
import { asyncHandler } from '../../middleware/errorHandler.js';
import { adUpload, cleanupTempFile } from '../../config/upload.js';
import AdCreative from '../../models/AdCreative.js';
import AdCampaign from '../../models/AdCampaign.js';
import User from '../../models/User.js';
import cloudinary from '../../config/cloudinary.js';
import { verifyToken } from '../../utils/verifytoken.js';
import { broadcastAdUpdate } from './realtimeRoutes.js';

const router = express.Router();

// POST /ads/campaigns/:id/creatives - Upload ad creative
router.post('/campaigns/:id/creatives', adUpload.single('creative'), asyncHandler(async (req, res) => {
  const campaignId = req.params.id;
  const {
    adType,
    type,
    aspectRatio,
    durationSec,
    callToActionLabel,
    callToActionUrl
  } = req.body;

  // Validate campaign exists
  const campaign = await AdCampaign.findById(campaignId);
  if (!campaign) {
    cleanupTempFile(req.file?.path);
    return res.status(404).json({ error: 'Campaign not found' });
  }

  // Validate adType
  if (!adType || !['banner', 'carousel ads', 'video feeds'].includes(adType)) {
    cleanupTempFile(req.file?.path);
    return res.status(400).json({ 
      error: 'Invalid adType. Must be one of: banner, carousel ads, video feeds' 
    });
  }

  // Validate file upload
  if (!req.file) {
    return res.status(400).json({ error: 'No creative file uploaded' });
  }

  // Validate media type based on adType
  if (adType === 'banner' && type !== 'image') {
    cleanupTempFile(req.file?.path);
    return res.status(400).json({ 
      error: 'Banner ads can only use images' 
    });
  }

  // Validate required fields based on adType
  if (!type || !['image', 'video'].includes(type)) {
    cleanupTempFile(req.file?.path);
    return res.status(400).json({ 
      error: 'Invalid media type. Must be image or video' 
    });
  }

  // Validate duration for video ads
  if (type === 'video' && (!durationSec || durationSec < 1 || durationSec > 60)) {
    cleanupTempFile(req.file?.path);
    return res.status(400).json({ 
      error: 'Video ads require duration between 1-60 seconds' 
    });
  }

  try {
    // Upload to Cloudinary
    const result = await cloudinary.uploader.upload(req.file.path, {
      resource_type: type === 'video' ? 'video' : 'image',
      folder: 'snehayog-ads',
      transformation: [
        { quality: 'auto:good' },
        { fetch_format: 'auto' }
      ]
    });

    // Create ad creative
    const creative = new AdCreative({
      campaignId,
      adType,
      type,
      cloudinaryUrl: result.secure_url,
      thumbnail: type === 'video' ? result.thumbnail_url : result.secure_url,
      aspectRatio,
      durationSec: type === 'video' ? durationSec : undefined,
      callToAction: {
        label: callToActionLabel,
        url: callToActionUrl
      }
    });

    await creative.save();

    res.status(201).json({
      message: 'Ad creative uploaded successfully',
      creative
    });

    // Broadcast new ad to realtime clients (non-blocking)
    try {
      broadcastAdUpdate({ updateType: 'created', adData: { id: creative._id.toString(), adType, type } });
    } catch (e) {
      console.error('Realtime broadcast error:', e);
    }

  } catch (error) {
    console.error('Creative upload error:', error);
    throw error;
  } finally {
    // Clean up temp file
    cleanupTempFile(req.file?.path);
  }
}));

// GET /ads/creatives - Get ad creatives with optional filtering
router.get('/', asyncHandler(async (req, res) => {
  const { adType, type, campaignId, status } = req.query;
  
  // Build filter object
  const filter = {};
  
  if (adType) {
    filter.adType = adType;
  }
  
  if (type) {
    filter.type = type;
  }
  
  if (campaignId) {
    filter.campaignId = campaignId;
  }
  
  if (status) {
    filter.reviewStatus = status;
  }

  const creatives = await AdCreative.find(filter)
    .populate('campaignId', 'name status')
    .sort({ createdAt: -1 });

  res.json({
    message: 'Ad creatives retrieved successfully',
    count: creatives.length,
    creatives
  });
}));

// GET /ads/creatives/types - Get available ad types and their media type restrictions
router.get('/types', asyncHandler(async (req, res) => {
  const adTypes = [
    {
      type: 'banner',
      name: 'Banner Ads',
      description: 'Static image ads displayed at the top or bottom of screens',
      allowedMediaTypes: ['image'],
      restrictions: 'Only images allowed',
      useCase: 'Brand awareness, promotions, announcements'
    },
    {
      type: 'carousel ads',
      name: 'Carousel Ads',
      description: 'Multiple images or videos that users can swipe through',
      allowedMediaTypes: ['image', 'video'],
      restrictions: 'Both images and videos allowed',
      useCase: 'Product showcases, story-based content, multiple offerings'
    },
    {
      type: 'video feeds',
      name: 'Video Feed Ads',
      description: 'Video ads that appear between video content (like Instagram reels)',
      allowedMediaTypes: ['image', 'video'],
      restrictions: 'Both images and videos allowed',
      useCase: 'Engaging video content, product demos, brand stories'
    }
  ];

  res.json({
    message: 'Available ad types and their specifications',
    adTypes
  });
}));

// **NEW: Carousel Ad Endpoints**

// GET /ads/carousel - Get all active carousel ads
router.get('/carousel', asyncHandler(async (req, res) => {
  try {
    console.log('🎯 Fetching carousel ads...');
    
    // Find all active carousel ads
    const carouselCreatives = await AdCreative.find({
      adType: 'carousel ads',
      isActive: true,
      reviewStatus: 'approved'
    }).populate('campaignId', 'name advertiserUserId status');
    
    console.log(`🎯 Found ${carouselCreatives.length} active carousel ads`);
    
    // Transform to carousel ad format
    const carouselAds = [];
    
    for (const creative of carouselCreatives) {
      try {
        // Get advertiser info
        const advertiser = await User.findById(creative.campaignId.advertiserUserId);
        
        // Create carousel ad object
        const carouselAd = {
          id: creative._id,
          campaignId: creative.campaignId._id,
          advertiserName: advertiser?.name || 'Unknown Advertiser',
          advertiserProfilePic: advertiser?.profilePic || '',
          slides: [{
            id: creative._id,
            mediaUrl: creative.cloudinaryUrl,
            thumbnailUrl: creative.thumbnail,
            mediaType: creative.type,
            durationSec: creative.durationSec,
            aspectRatio: creative.aspectRatio,
          }],
          callToActionLabel: creative.callToAction?.label || 'Learn More',
          callToActionUrl: creative.callToAction?.url || '',
          isActive: creative.isActive,
          createdAt: creative.createdAt,
          impressions: creative.impressions,
          clicks: creative.clicks,
        };
        
        carouselAds.push(carouselAd);
      } catch (error) {
        console.error(`❌ Error processing carousel ad ${creative._id}:`, error);
        continue;
      }
    }
    
    console.log(`✅ Successfully processed ${carouselAds.length} carousel ads`);
    
    res.json(carouselAds);
    
  } catch (error) {
    console.error('❌ Error fetching carousel ads:', error);
    res.status(500).json({ 
      error: 'Failed to fetch carousel ads',
      message: error.message 
    });
  }
}));

// GET /ads/carousel/:id - Get specific carousel ad
router.get('/carousel/:id', asyncHandler(async (req, res) => {
  try {
    const { id } = req.params;
    console.log('🎯 Fetching carousel ad:', id);
    
    const creative = await AdCreative.findById(id)
      .populate('campaignId', 'name advertiserUserId status');
    
    if (!creative) {
      return res.status(404).json({ error: 'Carousel ad not found' });
    }
    
    if (creative.adType !== 'carousel ads') {
      return res.status(400).json({ error: 'Not a carousel ad' });
    }
    
    // Get advertiser info
    const advertiser = await User.findById(creative.campaignId.advertiserUserId);
    
    const carouselAd = {
      id: creative._id,
      campaignId: creative.campaignId._id,
      advertiserName: advertiser?.name || 'Unknown Advertiser',
      advertiserProfilePic: advertiser?.profilePic || '',
      slides: [{
        id: creative._id,
        mediaUrl: creative.cloudinaryUrl,
        thumbnailUrl: creative.thumbnail,
        mediaType: creative.type,
        durationSec: creative.durationSec,
        aspectRatio: creative.aspectRatio,
      }],
      callToActionLabel: creative.callToAction?.label || 'Learn More',
      callToActionUrl: creative.callToAction?.url || '',
      isActive: creative.isActive,
      createdAt: creative.createdAt,
      impressions: creative.impressions,
      clicks: creative.clicks,
    };
    
    res.json(carouselAd);
    
  } catch (error) {
    console.error('❌ Error fetching carousel ad:', error);
    res.status(500).json({ 
      error: 'Failed to fetch carousel ad',
      message: error.message 
    });
  }
}));

// POST /ads/carousel/:id/impression - Track carousel ad impression
router.post('/carousel/:id/impression', asyncHandler(async (req, res) => {
  try {
    const { id } = req.params;
    console.log('📊 Tracking impression for carousel ad:', id);
    
    const creative = await AdCreative.findById(id);
    if (!creative) {
      return res.status(404).json({ error: 'Carousel ad not found' });
    }
    
    // Increment impression count
    creative.impressions = (creative.impressions || 0) + 1;
    await creative.save();
    
    console.log(`✅ Impression tracked for carousel ad ${id}. New count: ${creative.impressions}`);
    
    res.json({ 
      message: 'Impression tracked successfully',
      impressions: creative.impressions 
    });
    
  } catch (error) {
    console.error('❌ Error tracking impression:', error);
    res.status(500).json({ 
      error: 'Failed to track impression',
      message: error.message 
    });
  }
}));

// POST /ads/carousel/:id/click - Track carousel ad click
router.post('/carousel/:id/click', asyncHandler(async (req, res) => {
  try {
    const { id } = req.params;
    console.log('🖱️ Tracking click for carousel ad:', id);
    
    const creative = await AdCreative.findById(id);
    if (!creative) {
      return res.status(404).json({ error: 'Carousel ad not found' });
    }
    
    // Increment click count
    creative.clicks = (creative.clicks || 0) + 1;
    await creative.save();
    
    console.log(`✅ Click tracked for carousel ad ${id}. New count: ${creative.clicks}`);
    
    res.json({ 
      message: 'Click tracked successfully',
      clicks: creative.clicks 
    });
    
  } catch (error) {
    console.error('❌ Error tracking click:', error);
    res.status(500).json({ 
      error: 'Failed to track click',
      message: error.message 
    });
  }
}));

// **NEW: Get active ads for serving**
router.get('/serve', asyncHandler(async (req, res) => {
  try {
    const { userId, platform, location, adType } = req.query;

    console.log('🎯 Serving ads request:', { userId, platform, location, adType });

    // Build query for active ads
    const query = {
      isActive: true
    };

    // Filter by ad type if specified
    if (adType) {
      query.adType = adType;
    }

    const activeAds = await AdCreative.find(query)
      .populate({
        path: 'campaignId',
        select: 'name objective status target',
        match: { status: 'active' } // Only get ads from active campaigns
      })
      .limit(20)
      .sort({ createdAt: -1 });

    // Filter out ads where campaign is null (due to match condition)
    const validAds = activeAds.filter(ad => ad.campaignId !== null);
    
    console.log(`✅ Found ${validAds.length} active ads (${activeAds.length} total, ${activeAds.length - validAds.length} filtered out)`);
    if (adType) {
      console.log(`   Filtered by type: ${adType}`);
    }

    // Transform ads to frontend format
    const transformedAds = validAds.map(ad => {
      const campaign = ad.campaignId;
      return {
        _id: ad._id.toString(),
        id: ad._id.toString(),
        title: campaign.name || 'Ad',
        description: campaign.objective || '',
        imageUrl: ad.mediaUrl || '',
        adType: ad.adType,
        campaignId: campaign._id.toString(),
        advertiserName: campaign.name || 'Advertiser',
        advertiserProfilePic: '',
        callToActionLabel: ad.callToActionLabel || 'Learn More',
        callToActionUrl: ad.callToActionUrl || '#',
        target: campaign.target || {},
        createdAt: ad.createdAt,
        updatedAt: ad.updatedAt
      };
    });

    res.json({
      success: true,
      ads: transformedAds,
      count: transformedAds.length
    });

  } catch (error) {
    console.error('Error serving ads:', error);
    res.status(500).json({ error: 'Failed to serve ads' });
  }
}));

// **NEW: Update ad status**
router.patch('/:adId/status', verifyToken, asyncHandler(async (req, res) => {
  try {
    const { adId } = req.params;
    const { status } = req.body;

    console.log(`🎯 Updating ad status: ${adId} -> ${status}`);

    if (!status) {
      return res.status(400).json({ error: 'Status is required' });
    }

    // Validate status
    const validStatuses = ['draft', 'pending_review', 'active', 'paused', 'completed', 'rejected'];
    if (!validStatuses.includes(status)) {
      return res.status(400).json({ error: 'Invalid status' });
    }

    // Find the campaign
    const campaign = await AdCampaign.findById(adId);
    if (!campaign) {
      return res.status(404).json({ error: 'Ad campaign not found' });
    }

    // **FIXED: Verify ownership using proper user lookup**
    const user = await User.findOne({ googleId: req.user.googleId });
    if (!user || campaign.advertiserUserId.toString() !== user._id.toString()) {
      return res.status(403).json({ error: 'Access denied - not your ad' });
    }

    // Update campaign status
    campaign.status = status;
    campaign.updatedAt = new Date();

    // If activating, set isActive to true and set start date
    if (status === 'active') {
      campaign.isActive = true;
      campaign.startDate = new Date();
    } else {
      campaign.isActive = false;
    }

    await campaign.save();

    console.log(`✅ Successfully updated ad ${adId} status to ${status}`);

    res.json({
      success: true,
      message: 'Ad status updated successfully',
      ad: {
        id: campaign._id,
        name: campaign.name,
        status: campaign.status,
        isActive: campaign.isActive,
        startDate: campaign.startDate,
        updatedAt: campaign.updatedAt
      }
    });
  } catch (error) {
    console.error('❌ Error updating ad status:', error);
    res.status(500).json({ 
      error: 'Failed to update ad status',
      message: error.message 
    });
  }
}));

export default router;
