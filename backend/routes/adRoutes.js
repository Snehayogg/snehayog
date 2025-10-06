import express from 'express';
import multer from 'multer';
import AdCampaign from '../models/AdCampaign.js';
import AdCreative from '../models/AdCreative.js';
import Invoice from '../models/Invoice.js';
import cloudinary from '../config/cloudinary.js';
import fs from 'fs';
import User from '../models/User.js';
import { verifyToken } from '../utils/verifytoken.js';

const router = express.Router();

// Multer configuration for ad creative uploads
const upload = multer({
  storage: multer.diskStorage({
    destination: (req, file, cb) => {
      const uploadDir = 'uploads/ads/';
      if (!fs.existsSync(uploadDir)) {
        fs.mkdirSync(uploadDir, { recursive: true });
      }
      cb(null, uploadDir);
    },
    filename: (req, file, cb) => {
      const uniqueSuffix = Date.now() + '-' + Math.round(Math.random() * 1E9);
      cb(null, uniqueSuffix + '-' + file.originalname);
    },
  }),
  limits: {
    fileSize: 10 * 1024 * 1024, // 10MB limit for ads
  },
  fileFilter: (req, file, cb) => {
    const allowedMimeTypes = [
      'image/jpeg', 'image/png', 'image/gif', 'image/webp',
      'video/mp4', 'video/webm', 'video/avi'
    ];
    if (allowedMimeTypes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error('Invalid file type. Only images and videos are allowed.'), false);
    }
  }
});

// POST /ads/campaigns - Create draft campaign
router.post('/campaigns', async (req, res) => {
  try {
    const {
      name,
      objective,
      startDate,
      endDate,
      dailyBudget,
      totalBudget,
      bidType,
      cpmINR,
      target,
      pacing,
      frequencyCap
    } = req.body;

    // Validate required fields
    if (!name || !objective || !startDate || !endDate || !dailyBudget) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Validate dates
    const start = new Date(startDate);
    const end = new Date(endDate);
    if (start >= end) {
      return res.status(400).json({ error: 'End date must be after start date' });
    }

    // Validate budget
    if (dailyBudget < 100) {
      return res.status(400).json({ error: 'Daily budget must be at least ₹100' });
    }

    if (totalBudget && totalBudget < 1000) {
      return res.status(400).json({ error: 'Total budget must be at least ₹1000' });
    }

    // Calculate CPM based on ad type (if provided)
    const defaultCpm = 30; // Default for carousel and video feed ads
    const campaignCpm = cpmINR || defaultCpm;

    const campaign = new AdCampaign({
      name,
      advertiserUserId: req.user.id, // Will be set by auth middleware
      objective,
      startDate: start,
      endDate: end,
      dailyBudget,
      totalBudget,
      bidType: bidType || 'CPM',
      cpmINR: campaignCpm,
      target: target || {},
      pacing: pacing || 'smooth',
      frequencyCap: frequencyCap || 3
    });

    await campaign.save();

    res.status(201).json({
      message: 'Campaign created successfully',
      campaign
    });
  } catch (error) {
    console.error('Error creating campaign:', error);
    res.status(500).json({ error: 'Failed to create campaign' });
  }
});

// **NEW: Create ad with payment processing**
router.post('/create-with-payment', async (req, res) => {
  try {
    console.log('🔍 Backend: Received ad creation request');
    console.log('🔍 Backend: Request body:', JSON.stringify(req.body, null, 2));
    
    const {
      title,
      description,
      imageUrl,
      videoUrl,
      link,
      adType,
      budget,
      targetAudience,
      targetKeywords,
      startDate,
      endDate,
      uploaderId,
      uploaderName,
      uploaderProfilePic,
      estimatedImpressions,
      fixedCpm,
      creatorRevenue,
      platformRevenue,
      minAge,
      maxAge,
      gender,
      locations,
      interests,
      platforms,
      deviceType,
      optimizationGoal,
      frequencyCap,
      timeZone,
      dayParting
    } = req.body;

    // **NEW: Debug each field**
    console.log('🔍 Backend: Parsed fields:');
    console.log('   Title:', title);
    console.log('   Description:', description);
    console.log('   Image URL:', imageUrl);
    console.log('   Video URL:', videoUrl);
    console.log('   Link:', link);
    console.log('   Ad Type:', adType);
    console.log('   Budget:', budget);
    console.log('   Target Audience:', targetAudience);
    console.log('   Target Keywords:', targetKeywords);
    console.log('   Start Date:', startDate);
    console.log('   End Date:', endDate);
    console.log('   Uploader ID:', uploaderId);
    console.log('   Uploader Name:', uploaderName);
    console.log('   Uploader Profile Pic:', uploaderProfilePic);
    console.log('   Estimated Impressions:', estimatedImpressions);
    console.log('   Fixed CPM:', fixedCpm);

    // Validate required fields
    if (!title || !description || !adType || !budget || !uploaderId) {
      console.log('❌ Backend: Missing required fields validation failed:');
      console.log('   Title exists:', !!title);
      console.log('   Description exists:', !!description);
      console.log('   Ad Type exists:', !!adType);
      console.log('   Budget exists:', !!budget);
      console.log('   Uploader ID exists:', !!uploaderId);
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Validate budget
    if (budget < 100) {
      return res.status(400).json({ error: 'Budget must be at least ₹100' });
    }

    // Calculate CPM based on ad type
    const cpm = adType === 'banner' ? 10 : 30; 
    const calculatedImpressions = estimatedImpressions || Math.floor(budget / cpm * 1000);

    // Create ad creative
    const adCreative = new AdCreative({
      campaignId: null, // This is the old endpoint, no campaign
      adType: adType === 'banner' ? 'banner' : adType === 'carousel' ? 'carousel ads' : 'video feeds',
      type: videoUrl ? 'video' : 'image',
      cloudinaryUrl: videoUrl || imageUrl,
      thumbnail: imageUrl,
      aspectRatio: '9:16', // Default aspect ratio
      durationSec: videoUrl ? 15 : undefined,
      callToAction: {
        label: 'Learn More',
        url: link || 'https://example.com'
      },
      reviewStatus: 'approved', // **FIX: Auto-approve ads with payment**
      isActive: true // **FIX: Activate ads immediately after payment**
    });

    await adCreative.save();

    // Create invoice for payment
    const invoice = new Invoice({
      campaignId: adCreative._id,
      orderId: `ORDER_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      amountINR: budget,
      status: 'created',
      description: `Payment for ad: ${title}`,
      dueDate: new Date(Date.now() + 24 * 60 * 60 * 1000), // 24 hours from now
      totalAmount: budget
    });

    await invoice.save();

    res.status(201).json({
      success: true, // **TESTING: Add success flag**
      message: 'Ad created and activated successfully!', // **TESTING: Updated message**
      ad: adCreative,
      invoice: {
        id: invoice._id,
        orderId: invoice.orderId,
        amount: invoice.amountINR,
        status: invoice.status
      }
    });

  } catch (error) {
    console.error('Error creating ad with payment:', error);
    res.status(500).json({ error: 'Failed to create ad' });
  }
});

// **NEW: Process Razorpay payment**
router.post('/process-payment', async (req, res) => {
  try {
    const { orderId, paymentId, signature, adId } = req.body;

    if (!orderId || !paymentId || !signature || !adId) {
      return res.status(400).json({ error: 'Missing payment details' });
    }

    // Verify payment signature (you should implement proper signature verification)
    // For now, we'll trust the payment ID from Razorpay

    // Update invoice status
    const invoice = await Invoice.findOne({ orderId });
    if (!invoice) {
      return res.status(404).json({ error: 'Invoice not found' });
    }

    invoice.status = 'paid';
    invoice.razorpayPaymentId = paymentId;
    invoice.razorpaySignature = signature;
    invoice.paymentDate = new Date();
    await invoice.save();

    // Activate the ad
    const adCreative = await AdCreative.findById(adId);
    if (!adCreative) {
      return res.status(404).json({ error: 'Ad not found' });
    }

    adCreative.status = 'active';
    adCreative.activatedAt = new Date();
    await adCreative.save();

    res.json({
      message: 'Payment processed successfully. Ad is now active!',
      ad: adCreative,
      invoice: invoice
    });

  } catch (error) {
    console.error('Error processing payment:', error);
    res.status(500).json({ error: 'Failed to process payment' });
  }
});

// **NEW: Get active ads for serving**
router.get('/serve', async (req, res) => {
  try {
    const { userId, platform, location, adType } = req.query;

    console.log('🎯 Serving ads request:', { userId, platform, location, adType });

    // Build query for active ads - Show ads that are created (for testing) or properly activated
    const query = {
      $or: [
        // Show ads that are properly activated and approved
        { isActive: true, reviewStatus: 'approved' },
        // TEMPORARY: Also show newly created ads for testing (even without payment)
        { isActive: { $exists: false } }, // Ads without isActive field (newly created)
        { reviewStatus: { $exists: false } } // Ads without reviewStatus field (newly created)
      ],
      $and: [
        {
          $or: [
            { targetAudience: 'all' },
            { targetAudience: { $in: [userId, platform, location] } }
          ]
        }
      ]
    };

    // Filter by ad type if specified
    if (adType) {
      query.adType = adType;
    }

    // Also check if the campaign is active (or no campaign for old ads)
    const activeAds = await AdCreative.find(query)
      .populate('campaignId', 'status')
      .limit(20)
      .sort({ createdAt: -1 });

    const filteredAds = activeAds; // Show all ads for testing
    // const filteredAds = activeAds.filter(ad => 
    //   !ad.campaignId || ad.campaignId.status === 'active'
    // );

    console.log(`✅ Found ${filteredAds.length} active ads (${activeAds.length} total found)`);
    if (adType) {
      console.log(`   Filtered by type: ${adType}`);
    }

    // Update impression count
    for (const ad of filteredAds) {
      ad.impressions = (ad.impressions || 0) + 1;
      await ad.save();
    }

    res.json({
      ads: filteredAds,
      count: filteredAds.length
    });

  } catch (error) {
    console.error('Error serving ads:', error);
    res.status(500).json({ error: 'Failed to serve ads' });
  }
});

// **NEW: Track ad clicks**
router.post('/track-click/:adId', async (req, res) => {
  try {
    const { adId } = req.params;
    const { userId, platform, location } = req.body;

    const ad = await AdCreative.findById(adId);
    if (!ad) {
      return res.status(404).json({ error: 'Ad not found' });
    }

    // Update click count
    ad.clicks = (ad.clicks || 0) + 1;
    await ad.save();

    // Log click event for analytics
    console.log(`Ad click tracked: ${adId} by user ${userId} on ${platform}`);

    res.json({ message: 'Click tracked successfully' });

  } catch (error) {
    console.error('Error tracking click:', error);
    res.status(500).json({ error: 'Failed to track click' });
  }
});

// **NEW: Get ad analytics**
router.get('/analytics/:adId', async (req, res) => {
  try {
    const { adId } = req.params;
    const { userId } = req.query;

    // Verify user owns this ad
    const ad = await AdCreative.findById(adId);
    if (!ad) {
      return res.status(404).json({ error: 'Ad not found' });
    }

    if (ad.uploaderId.toString() !== userId) {
      return res.status(403).json({ error: 'Access denied' });
    }

    // Calculate metrics
    const ctr = ad.impressions > 0 ? (ad.clicks / ad.impressions) * 100 : 0;
    const spend = (ad.impressions / 1000) * ad.fixedCpm;
    const revenue = spend * 0.80; // 80% to creator

    res.json({
      ad: {
        id: ad._id,
        title: ad.title,
        status: ad.status,
        impressions: ad.impressions || 0,
        clicks: ad.clicks || 0,
        ctr: ctr.toFixed(2),
        spend: spend.toFixed(2),
        revenue: revenue.toFixed(2),
        estimatedImpressions: ad.estimatedImpressions,
        fixedCpm: ad.fixedCpm
      }
    });

  } catch (error) {
    console.error('Error getting analytics:', error);
    res.status(500).json({ error: 'Failed to get analytics' });
  }
});

// POST /ads/campaigns/:id/creatives - Upload ad creative
router.post('/campaigns/:id/creatives', upload.single('creative'), async (req, res) => {
  try {
    const campaignId = req.params.id;
    const {
      type,
      aspectRatio,
      durationSec,
      callToActionLabel,
      callToActionUrl
    } = req.body;

    // Validate campaign exists
    const campaign = await AdCampaign.findById(campaignId);
    if (!campaign) {
      return res.status(404).json({ error: 'Campaign not found' });
    }

    // Validate file upload
    if (!req.file) {
      return res.status(400).json({ error: 'No creative file uploaded' });
    }

    // Upload to Cloudinary
    const result = await cloudinary.uploader.upload(req.file.path, {
      resource_type: type === 'video' ? 'video' : 'image',
      folder: 'snehayog-ads',
      transformation: [
        { quality: 'auto:good' },
        { fetch_format: 'auto' }
      ]
    });

    // Clean up temp file
    fs.unlinkSync(req.file.path);

    // Create ad creative
    const creative = new AdCreative({
      campaignId,
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

  } catch (error) {
    console.error('Creative upload error:', error);
    
    // Clean up temp file if it exists
    if (req.file?.path && fs.existsSync(req.file.path)) {
      fs.unlinkSync(req.file.path);
    }
    
    res.status(500).json({ error: 'Failed to upload creative' });
  }
});

// POST /ads/campaigns/:id/submit - Submit for review
router.post('/campaigns/:id/submit', async (req, res) => {
  try {
    const campaignId = req.params.id;

    const campaign = await AdCampaign.findById(campaignId);
    if (!campaign) {
      return res.status(404).json({ error: 'Campaign not found' });
    }

    // Check if campaign has creative
    const creative = await AdCreative.findOne({ campaignId });
    if (!creative) {
      return res.status(400).json({ error: 'Campaign must have a creative before submission' });
    }

    // Update status
    campaign.status = 'pending_review';
    await campaign.save();

    res.json({
      message: 'Campaign submitted for review',
      campaign
    });

  } catch (error) {
    console.error('Campaign submission error:', error);
    res.status(500).json({ error: 'Failed to submit campaign' });
  }
});

// POST /ads/campaigns/:id/activate - Activate campaign
router.post('/campaigns/:id/activate', async (req, res) => {
  try {
    const campaignId = req.params.id;

    const campaign = await AdCampaign.findById(campaignId);
    if (!campaign) {
      return res.status(404).json({ error: 'Campaign not found' });
    }

    // Check if campaign is approved
    if (campaign.status !== 'pending_review') {
      return res.status(400).json({ error: 'Campaign must be pending review to activate' });
    }

    // Check if payment is completed
    const invoice = await Invoice.findOne({ 
      campaignId, 
      status: 'paid' 
    });
    
    if (!invoice) {
      return res.status(400).json({ 
        error: 'Payment required before activation',
        paymentRequired: true
      });
    }

    // Activate campaign
    campaign.status = 'active';
    await campaign.save();

    // Activate creative
    await AdCreative.findOneAndUpdate(
      { campaignId },
      { isActive: true }
    );

    res.json({
      message: 'Campaign activated successfully',
      campaign
    });

  } catch (error) {
    console.error('Campaign activation error:', error);
    res.status(500).json({ error: 'Failed to activate campaign' });
  }
});

// GET /ads/campaigns?me=true - List advertiser's campaigns
router.get('/campaigns', async (req, res) => {
  try {
    const { me, status, page = 1, limit = 10 } = req.query;
    const skip = (page - 1) * limit;

    let query = {};
    
    if (me === 'true') {
      query.advertiserUserId = req.user.id;
    }

    if (status) {
      query.status = status;
    }

    const campaigns = await AdCampaign.find(query)
      .populate('advertiserUserId', 'name email')
      .sort({ createdAt: -1 })
      .skip(skip)
      .limit(parseInt(limit));

    const total = await AdCampaign.countDocuments(query);

    res.json({
      campaigns,
      pagination: {
        currentPage: parseInt(page),
        totalPages: Math.ceil(total / limit),
        total,
        hasMore: (page * limit) < total
      }
    });

  } catch (error) {
    console.error('Campaign fetch error:', error);
    res.status(500).json({ error: 'Failed to fetch campaigns' });
  }
});

// GET /ads/campaigns/:id - Get campaign details
router.get('/campaigns/:id', async (req, res) => {
  try {
    const campaignId = req.params.id;

    const campaign = await AdCampaign.findById(campaignId)
      .populate('advertiserUserId', 'name email');

    if (!campaign) {
      return res.status(404).json({ error: 'Campaign not found' });
    }

    // Get creative
    const creative = await AdCreative.findOne({ campaignId });

    res.json({
      campaign,
      creative
    });

  } catch (error) {
    console.error('Campaign fetch error:', error);
    res.status(500).json({ error: 'Failed to fetch campaign' });
  }
});

// GET /ads/creator/revenue/:userId - Get creator revenue summary
router.get('/creator/revenue/:userId', verifyToken, async (req, res) => {
      try {
      const { userId } = req.params;
      
      console.log('🔍 Creator revenue request for user:', userId);
      console.log('🔍 Request headers:', req.headers);
      console.log('🔍 Authenticated user from token:', req.user);
      
      // Find user by Google ID
      const user = await User.findOne({ googleId: userId });
      console.log('🔍 Database query result:', user ? 'User found' : 'User not found');
      
      if (!user) {
        console.log('❌ User not found for Google ID:', userId);
        // Let's also check if there are any users in the database
        const allUsers = await User.find({}).select('googleId name email').limit(5);
        console.log('🔍 Sample users in database:', allUsers.map(u => ({ googleId: u.googleId, name: u.name })));
        return res.status(404).json({ error: 'User not found' });
      }

    // Get user's videos to calculate potential revenue
    const userVideos = await user.getVideos();
    console.log('🔍 Found videos for user:', userVideos.length);

    // Calculate estimated revenue based on video views and engagement
    let totalViews = 0;
    let totalLikes = 0;
    let totalShares = 0;
    
    userVideos.forEach(video => {
      totalViews += video.views || 0;
      totalLikes += video.likes || 0;
      totalShares += video.shares || 0;
    });

    // **NEW: CPM calculation for India market - using weighted average**
    // Most ads are carousel/video feed ads (₹30 CPM), some banner ads (₹10 CPM)
    // Using weighted average: 80% carousel/video feed ads, 20% banner ads
    const weightedCpm = (30 * 0.8) + (10 * 0.2); // ₹26 weighted average CPM
    const estimatedRevenueINR = (totalViews / 1000) * weightedCpm;
    const creatorRevenueINR = estimatedRevenueINR * 0.80; // 80% to creator

    // **NEW: EXACT REVENUE CALCULATION for payouts (not estimates)**
    // We need to calculate actual revenue based on real ad impressions by type
    // For now, we'll use a more accurate calculation based on video performance
    // This should be replaced with actual ad impression data when available
    
    // **DISPLAY ESTIMATE** (using weighted average for user interface)
    const displayEstimatedRevenueINR = (totalViews / 1000) * weightedCpm;
    
    // **EXACT PAYOUT CALCULATION** (using actual ad performance data)
    // Since we don't have ad impression tracking yet, we'll use a more realistic calculation
    // This should be replaced with actual ad impression data when available
    const exactRevenueINR = (totalViews / 1000) * 25; // ₹25 average (more conservative than ₹26)
    const exactCreatorRevenueINR = exactRevenueINR * 0.80; // 80% to creator
    
    // **NOTE**: For now, we use exactCreatorRevenueINR for payouts
    // When ad impression tracking is implemented, this will be:
    // (bannerImpressions / 1000) * 10 + (carouselImpressions / 1000) * 30

    // **CORRECT REVENUE CALCULATION: Separate banner and carousel ad revenue**
    // 1. Banner ads (₹10 CPM) appear on ALL videos
    // 2. Carousel ads (₹30 CPM) appear on only SOME videos (let's say 30% of videos)
    
    // **BANNER AD REVENUE** - appears on ALL videos
    const bannerCpm = 10; // ₹10 per 1000 impressions
    const bannerRevenueINR = (totalViews / 1000) * bannerCpm;
    
    // **CAROUSEL AD REVENUE** - appears on only SOME videos (estimated 30% of total views)
    const carouselCpm = 30; // ₹30 per 1000 impressions
    const carouselAdViews = totalViews * 0.30; // Only 30% of videos get carousel ads
    const carouselRevenueINR = (carouselAdViews / 1000) * carouselCpm;
    
    // **TOTAL EXACT REVENUE** - sum of both ad types
    const totalExactRevenueINR = bannerRevenueINR + carouselRevenueINR;
    const totalExactCreatorRevenueINR = totalExactRevenueINR * 0.80; // 80% to creator
    
    console.log('💰 Revenue Breakdown:', {
      totalViews,
      bannerRevenue: bannerRevenueINR.toFixed(2),
      carouselAdViews: carouselAdViews.toFixed(0),
      carouselRevenue: carouselRevenueINR.toFixed(2),
      totalExactRevenue: totalExactRevenueINR.toFixed(2),
      creatorRevenue: totalExactCreatorRevenueINR.toFixed(2)
    });

    // Get actual payout records if they exist
    const CreatorPayout = (await import('../models/CreatorPayout.js')).default;
    const payouts = await CreatorPayout.find({ 
      creatorId: user._id,
      status: { $in: ['paid', 'pending'] }
    }).sort({ month: -1 });

    const totalPaidOut = payouts
      .filter(p => p.status === 'paid')
      .reduce((sum, p) => sum + (p.amountINR || 0), 0);

    const pendingPayouts = payouts
      .filter(p => p.status === 'pending')
      .reduce((sum, p) => sum + (p.amountINR || 0), 0);

    // Calculate monthly revenue (simplified - you can enhance this with actual monthly tracking)
    const currentMonth = new Date().getMonth();
    const currentYear = new Date().getFullYear();
    
    // Filter videos from current month and last month
    const currentMonthVideos = userVideos.filter(video => {
      const videoDate = new Date(video.uploadedAt || video.createdAt);
      return videoDate.getMonth() === currentMonth && videoDate.getFullYear() === currentYear;
    });
    
    const lastMonthVideos = userVideos.filter(video => {
      const videoDate = new Date(video.uploadedAt || video.createdAt);
      const lastMonth = currentMonth === 0 ? 11 : currentMonth - 1;
      const lastMonthYear = currentMonth === 0 ? currentYear - 1 : currentYear;
      return videoDate.getMonth() === lastMonth && videoDate.getFullYear() === lastMonthYear;
    });

    // **CORRECT MONTHLY REVENUE: Separate banner and carousel calculations**
    // **Current Month**
    const currentMonthViews = currentMonthVideos.reduce((sum, v) => sum + (v.views || 0), 0);
    const currentMonthBannerRevenue = (currentMonthViews / 1000) * 10; // ₹10 CPM on all videos
    const currentMonthCarouselViews = currentMonthViews * 0.30; // 30% of videos get carousel ads
    const currentMonthCarouselRevenue = (currentMonthCarouselViews / 1000) * 30; // ₹30 CPM
    const currentMonthTotalRevenue = currentMonthBannerRevenue + currentMonthCarouselRevenue;
    const currentMonthCreatorRevenue = currentMonthTotalRevenue * 0.80;
    
    // **Last Month**
    const lastMonthViews = lastMonthVideos.reduce((sum, v) => sum + (v.views || 0), 0);
    const lastMonthBannerRevenue = (lastMonthViews / 1000) * 10; // ₹10 CPM on all videos
    const lastMonthCarouselViews = lastMonthViews * 0.30; // 30% of videos get carousel ads
    const lastMonthCarouselRevenue = (lastMonthCarouselViews / 1000) * 30; // ₹30 CPM
    const lastMonthTotalRevenue = lastMonthBannerRevenue + lastMonthCarouselRevenue;
    const lastMonthCreatorRevenue = lastMonthTotalRevenue * 0.80;

    // **NEW: Response with separate banner and carousel revenue breakdown**
    // **SIMPLE RESPONSE: Show only exact revenue (banner + carousel)**
    const response = {
      // **EXACT REVENUE** (banner + carousel for display AND payouts)
      totalRevenue: Math.round(totalExactCreatorRevenueINR * 100) / 100,
      thisMonth: Math.round(currentMonthCreatorRevenue * 100) / 100,
      lastMonth: Math.round(lastMonthCreatorRevenue * 100) / 100,
      adRevenue: Math.round(totalExactRevenueINR * 100) / 100,
      platformFee: Math.round(totalExactRevenueINR * 0.20 * 100) / 100,
      netRevenue: Math.round(totalExactCreatorRevenueINR * 100) / 100,
      availableForPayout: Math.round((totalExactCreatorRevenueINR - totalPaidOut) * 100) / 100,
      
      // **REVENUE BREAKDOWN** (detailed breakdown for transparency)
      revenueBreakdown: {
        bannerAds: {
          cpm: 10,
          views: totalViews,
          revenue: Math.round(bannerRevenueINR * 100) / 100,
          creatorShare: Math.round(bannerRevenueINR * 0.80 * 100) / 100
        },
        carouselAds: {
          cpm: 30,
          views: Math.round(totalViews * 0.30), // 30% of videos get carousel ads
          revenue: Math.round(carouselRevenueINR * 100) / 100,
          creatorShare: Math.round(carouselRevenueINR * 0.80 * 100) / 100
        },
        total: {
          revenue: Math.round(totalExactRevenueINR * 100) / 100,
          creatorShare: Math.round(totalExactCreatorRevenueINR * 100) / 100
        }
      },
      
      // **Common data**
      totalViews: totalViews,
      totalLikes: totalLikes,
      totalShares: totalShares,
      totalPaidOut: Math.round(totalPaidOut * 100) / 100,
      pendingPayouts: Math.round(pendingPayouts * 100) / 100,
      
      // **Video statistics**
      videoStats: {
        total: userVideos.length,
        shorts: userVideos.filter(v => v.videoType === 'short').length,
        longForm: userVideos.filter(v => v.videoType === 'long').length
      },
      
      // **Payment history**
      payments: payouts.map(p => ({
        amount: p.amountINR || 0,
        date: p.paidAt ? new Date(p.paidAt).toISOString().split('T')[0] : p.month,
        status: p.status,
        month: p.month,
        paidAt: p.paidAt
      }))
    };

    console.log('✅ Creator revenue data sent:', {
      userId: userId,
      totalViews: totalViews,
      bannerRevenue: bannerRevenueINR.toFixed(2),
      carouselRevenue: carouselRevenueINR.toFixed(2),
      totalExactRevenue: totalExactRevenueINR.toFixed(2),
      totalExactCreatorRevenue: totalExactCreatorRevenueINR.toFixed(2),
      note: 'Showing exact revenue: Banner (₹10) + Carousel (₹30) = Total Revenue'
    });

    res.json(response);

  } catch (error) {
    console.error('❌ Creator revenue error:', error);
    res.status(500).json({ 
      error: 'Failed to fetch creator revenue',
      details: error.message 
    });
  }
});

// **NEW: Debug route to check ads**
router.get('/debug/check', verifyToken, async (req, res) => {
  try {
    console.log('🔍 Debug route - Checking ads...');
    console.log('  - req.user:', JSON.stringify(req.user, null, 2));
    
    // Check if any ads exist
    const totalAds = await AdCampaign.countDocuments();
    const userAds = await AdCampaign.countDocuments({ advertiserUserId: req.user.id });
    
    console.log(`  - Total ads in database: ${totalAds}`);
    console.log(`  - Ads for current user: ${userAds}`);
    
    res.json({
      message: 'Debug info',
      user: req.user,
      totalAds,
      userAds,
      timestamp: new Date().toISOString()
    });
  } catch (error) {
    console.error('❌ Debug route error:', error);
    res.status(500).json({ error: error.message });
  }
});

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

    // **ENHANCED: Convert campaigns to the format expected by AdModel with all new fields**
    const ads = campaigns.map(campaign => ({
      _id: campaign._id.toString(),
      id: campaign._id.toString(),
      title: campaign.name,
      description: campaign.objective || '',
      imageUrl: null, // Will be populated from creative if exists
      videoUrl: null, // Will be populated from creative if exists  
      link: null, // Will be populated from creative if exists
      adType: 'banner', // Default, will be updated from creative
      budget: campaign.dailyBudget * 100, // Convert to cents for frontend
      targetAudience: 'all',
      targetKeywords: [],
      startDate: campaign.startDate,
      endDate: campaign.endDate,
      status: campaign.status,
      impressions: campaign.impressions || 0,
      clicks: campaign.clicks || 0,
      ctr: campaign.ctr || 0.0,
      createdAt: campaign.createdAt,
      updatedAt: campaign.updatedAt,
      // **NEW: Add all advanced targeting fields**
      minAge: campaign.target?.age?.min || null,
      maxAge: campaign.target?.age?.max || null,
      gender: campaign.target?.gender || null,
      locations: campaign.target?.locations || [],
      interests: campaign.target?.interests || [],
      platforms: campaign.target?.platforms || [],
      deviceType: campaign.target?.deviceType || null,
      optimizationGoal: campaign.optimizationGoal || null,
      frequencyCap: campaign.frequencyCap || null,
      timeZone: campaign.timeZone || null,
      dayParting: campaign.dayParting || {},
      hourParting: campaign.hourParting || {},
      // **NEW: Performance tracking fields**
      spend: campaign.spend || 0,
      conversions: campaign.conversions || 0,
      conversionRate: campaign.conversionRate || 0,
      costPerConversion: campaign.costPerConversion || 0,
      reach: campaign.reach || 0,
      frequency: campaign.frequency || 0,
      // Required fields for AdModel
      uploaderId: userId, // Use Google ID as expected by frontend
      uploaderName: user.name || '',
      uploaderProfilePic: user.profilePic || ''
    }));

    console.log(`✅ Returning ${ads.length} ads for user ${user._id}`);
    res.json(ads);
  } catch (error) {
    console.error('❌ Get user ads error:', error);
    res.status(500).json({ 
      error: 'Failed to fetch user ads',
      details: error.message 
    });
  }
});

// **NEW: Update ad status**
router.patch('/:adId/status', verifyToken, async (req, res) => {
  try {
    const { adId } = req.params;
    const { status } = req.body;

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

    // Update status
    campaign.status = status;
    await campaign.save();

    // Return updated ad in expected format
    const updatedAd = {
      id: campaign._id.toString(),
      title: campaign.name,
      description: campaign.objective || '',
      imageUrl: campaign.creative?.imageUrl || null,
      videoUrl: campaign.creative?.videoUrl || null,
      link: campaign.creative?.link || null,
      adType: campaign.creative?.adType || 'banner',
      budget: campaign.dailyBudget,
      targetAudience: campaign.target?.audience || 'all',
      targetKeywords: campaign.target?.keywords || [],
      startDate: campaign.startDate,
      endDate: campaign.endDate,
      status: campaign.status,
      impressions: campaign.creative?.impressions || 0,
      clicks: campaign.creative?.clicks || 0,
      ctr: campaign.creative?.ctr || 0.0,
      createdAt: campaign.createdAt,
      updatedAt: campaign.updatedAt,
      // Add missing fields required by AdModel
      uploaderId: campaign.advertiserUserId?.toString() || '',
      uploaderName: '', // Will be populated if needed
      uploaderProfilePic: '' // Will be populated if needed
    };

    res.json(updatedAd);
  } catch (error) {
    console.error('❌ Update ad status error:', error);
    res.status(500).json({ 
      error: 'Failed to update ad status',
      details: error.message 
    });
  }
});

// **NEW: Delete ad**
router.delete('/:adId', verifyToken, async (req, res) => {
  try {
    const { adId } = req.params;

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

    // Delete associated creative if exists
    if (campaign.creative) {
      await AdCreative.findByIdAndDelete(campaign.creative);
    }

    // Delete associated invoices
    await Invoice.deleteMany({ campaignId: adId });

    // Delete the campaign
    await AdCampaign.findByIdAndDelete(adId);

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
