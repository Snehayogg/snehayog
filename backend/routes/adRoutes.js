import express from 'express';
import multer from 'multer';
import AdCampaign from '../models/AdCampaign.js';
import AdCreative from '../models/AdCreative.js';
import Video from '../models/Video.js';
import Invoice from '../models/Invoice.js';
import cloudinary from '../config/cloudinary.js';
import fs from 'fs';
import User from '../models/User.js';
import { verifyToken } from '../utils/verifytoken.js';
import adService from '../services/adService.js';
import adTargetingRoutes from './adTargetingRoutes.js';
import adCommentRoutes from './adCommentRoutes.js';
import adCleanupService from '../services/adCleanupService.js';

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
    fileSize: 50 * 1024 * 1024, // 50MB limit for ads
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

    if (totalBudget && totalBudget < 500) {
      return res.status(400).json({ error: 'Total budget must be at least ₹500' });
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
    } = req.body;

    // Validate required fields
    if (!title || !description || !adType || !budget || !uploaderId) {
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
      adType: adType === 'banner' ? 'banner' : adType === 'carousel' ? 'carousel' : 'video feed ad',
      type: videoUrl ? 'video' : 'image',
      cloudinaryUrl: videoUrl || imageUrl,
      thumbnail: imageUrl,
      aspectRatio: '9:16', // Default aspect ratio
      durationSec: videoUrl ? 15 : undefined,
      callToAction: {
        label: 'Learn More',
        url: link
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
      success: true,
      message: 'Ad created and activated successfully!',
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

    // Ensure all activation fields are consistent
    adCreative.status = 'active';
    adCreative.isActive = true;
    adCreative.reviewStatus = 'approved';
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

// **NEW: Track ad clicks**
router.post('/track-click/:adId', async (req, res) => {
  try {
    const { adId } = req.params;
    const { userId, platform } = req.body;

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

    // Activate creative consistently
    await AdCreative.findOneAndUpdate(
      { campaignId },
      { $set: { isActive: true, reviewStatus: 'approved' } }
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
      
      // console.log('🔍 Creator revenue request for user:', userId);
      // console.log('🔍 Request headers:', req.headers);
      // console.log('🔍 Authenticated user from token:', req.user);
      
      // Find user by Google ID
      const user = await User.findOne({ googleId: userId });
      // console.log('🔍 Database query result:', user ? 'User found' : 'User not found');
      
      if (!user) {
        console.log('❌ User not found for Google ID:', userId);
        // Let's also check if there are any users in the database
        const allUsers = await User.find({}).select('googleId name email').limit(5);
        console.log('🔍 Sample users in database:', allUsers.map(u => ({ googleId: u.googleId, name: u.name })));
        return res.status(404).json({ error: 'User not found' });
      }

    // **FIXED: Use direct Video query instead of user.getVideos() to ensure all videos are found**
    // This fixes issues where user.videos array might be out of sync
    const userVideos = await Video.find({ uploader: user._id });
    console.log('🔍 Found videos for user (Direct Query):', userVideos.length);

    // Get video IDs for querying ad impressions
    const videoIds = userVideos.map(video => video._id);

    // **FIXED: Use ACTUAL ad impressions from AdImpression collection (realtime)**
    const AdImpression = (await import('../models/AdImpression.js')).default;
    
    // Count actual banner ad impressions for user's videos
    // **FIX: Use simple count (no isViewed check) to match Admin Dashboard logic**
    const bannerImpressions = await AdImpression.countDocuments({
      videoId: { $in: videoIds },
      adType: 'banner',
      impressionType: 'view'
    });

    // Count actual carousel ad impressions for user's videos
    // **FIX: Use simple count (no isViewed check) to match Admin Dashboard logic**
    const carouselImpressions = await AdImpression.countDocuments({
      videoId: { $in: videoIds },
      adType: 'carousel',
      impressionType: 'view'
    });

    /*
    console.log('📊 Actual Ad Impressions:', {
      bannerImpressions,
      carouselImpressions,
      totalImpressions: bannerImpressions + carouselImpressions
    });
    */

    // Calculate video statistics (for display purposes only)
    let totalViews = 0;
    let totalLikes = 0;
    let totalShares = 0;
    
    userVideos.forEach(video => {
      totalViews += video.views || 0;
      totalLikes += video.likes || 0;
      totalShares += video.shares || 0;
    });

    // **REVENUE CALCULATION: Based on ACTUAL ad impressions (realtime)**
    // Banner ads: ₹10 CPM (₹10 per 1000 impressions)
    const bannerCpm = 10;
    const bannerRevenueINR = (bannerImpressions / 1000) * bannerCpm;
    
    // Carousel ads: ₹30 CPM (₹30 per 1000 impressions)
    const carouselCpm = 30;
    const carouselRevenueINR = (carouselImpressions / 1000) * carouselCpm;
    
    // **TOTAL EXACT REVENUE** - sum of both ad types (based on actual impressions)
    const totalExactRevenueINR = bannerRevenueINR + carouselRevenueINR;
    const totalExactCreatorRevenueINR = totalExactRevenueINR * 0.80; // 80% to creator
    
    /*
    console.log('💰 Revenue Breakdown (Based on Actual Ad Impressions):', {
      bannerImpressions,
      carouselImpressions,
      totalImpressions: bannerImpressions + carouselImpressions,
      bannerRevenue: bannerRevenueINR.toFixed(2),
      carouselRevenue: carouselRevenueINR.toFixed(2),
      totalExactRevenue: totalExactRevenueINR.toFixed(2),
      creatorRevenue: totalExactCreatorRevenueINR.toFixed(2),
      note: 'Revenue calculated from actual ad impressions (realtime)'
    });
    */

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
    
    // **FIXED: Count impressions for ALL videos in current month (not just videos uploaded this month)**
    // This ensures earnings from older videos that get views in current month are included
    const lastMonth = currentMonth === 0 ? 11 : currentMonth - 1;
    const lastMonthYear = currentMonth === 0 ? currentYear - 1 : currentYear;
    
    // **Current Month** - Count actual impressions for ALL videos (regardless of upload date)
    // Filter by timestamp only - this counts impressions that happened in current month
    const currentMonthBannerImpressions = await AdImpression.countDocuments({
      videoId: { $in: videoIds }, // Use ALL video IDs, not just current month videos
      adType: 'banner',
      impressionType: 'view',
      timestamp: {
        $gte: new Date(currentYear, currentMonth, 1),
        $lt: new Date(currentYear, currentMonth + 1, 1)
      }
    });
    
    const currentMonthCarouselImpressions = await AdImpression.countDocuments({
      videoId: { $in: videoIds }, // Use ALL video IDs, not just current month videos
      adType: 'carousel',
      impressionType: 'view',
      timestamp: {
        $gte: new Date(currentYear, currentMonth, 1),
        $lt: new Date(currentYear, currentMonth + 1, 1)
      }
    });
    
    const currentMonthBannerRevenue = (currentMonthBannerImpressions / 1000) * 10; // ₹10 CPM
    const currentMonthCarouselRevenue = (currentMonthCarouselImpressions / 1000) * 30; // ₹30 CPM
    const currentMonthTotalRevenue = currentMonthBannerRevenue + currentMonthCarouselRevenue;
    const currentMonthCreatorRevenue = currentMonthTotalRevenue * 0.80;
    
    /*
    console.log('💰 Current Month Revenue Calculation:', {
      totalVideos: videoIds.length,
      currentMonthBannerImpressions,
      currentMonthCarouselImpressions,
      currentMonthBannerRevenue: currentMonthBannerRevenue.toFixed(2),
      currentMonthCarouselRevenue: currentMonthCarouselRevenue.toFixed(2),
      currentMonthCreatorRevenue: currentMonthCreatorRevenue.toFixed(2),
      note: 'Counting impressions for ALL videos in current month (not just videos uploaded this month)'
    });
    */
    
    // **Last Month** - Count actual impressions for ALL videos (regardless of upload date)
    const lastMonthBannerImpressions = await AdImpression.countDocuments({
      videoId: { $in: videoIds }, // Use ALL video IDs, not just last month videos
      adType: 'banner',
      impressionType: 'view',
      timestamp: {
        $gte: new Date(lastMonthYear, lastMonth, 1),
        $lt: new Date(lastMonthYear, lastMonth + 1, 1)
      }
    });
    
    const lastMonthCarouselImpressions = await AdImpression.countDocuments({
      videoId: { $in: videoIds }, // Use ALL video IDs, not just last month videos
      adType: 'carousel',
      impressionType: 'view',
      timestamp: {
        $gte: new Date(lastMonthYear, lastMonth, 1),
        $lt: new Date(lastMonthYear, lastMonth + 1, 1)
      }
    });
    
    const lastMonthBannerRevenue = (lastMonthBannerImpressions / 1000) * 10; // ₹10 CPM
    const lastMonthCarouselRevenue = (lastMonthCarouselImpressions / 1000) * 30; // ₹30 CPM
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
      
      // **REVENUE BREAKDOWN** (detailed breakdown based on actual ad impressions)
      revenueBreakdown: {
        bannerAds: {
          cpm: 10,
          impressions: bannerImpressions, // Actual ad impressions (realtime)
          revenue: Math.round(bannerRevenueINR * 100) / 100,
          creatorShare: Math.round(bannerRevenueINR * 0.80 * 100) / 100
        },
        carouselAds: {
          cpm: 30,
          impressions: carouselImpressions, // Actual ad impressions (realtime)
          revenue: Math.round(carouselRevenueINR * 100) / 100,
          creatorShare: Math.round(carouselRevenueINR * 0.80 * 100) / 100
        },
        total: {
          impressions: bannerImpressions + carouselImpressions, // Total ad impressions
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

    /*
    console.log('✅ Creator revenue data sent (Based on Actual Ad Impressions):', {
      userId: userId,
      bannerImpressions,
      carouselImpressions,
      totalImpressions: bannerImpressions + carouselImpressions,
      bannerRevenue: bannerRevenueINR.toFixed(2),
      carouselRevenue: carouselRevenueINR.toFixed(2),
      totalExactRevenue: totalExactRevenueINR.toFixed(2),
      totalExactCreatorRevenue: totalExactCreatorRevenueINR.toFixed(2),
      note: 'Revenue calculated from actual ad impressions (realtime) - Banner (₹10 CPM) + Carousel (₹30 CPM)'
    });
    */

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
    
    // **NEW: Return one row per creative so multiple creatives under a campaign are visible**
    const campaigns = await AdCampaign.find({ advertiserUserId: user._id })
      .sort({ createdAt: -1 });

    const campaignIds = campaigns.map(c => c._id);
    // **FIXED: Filter out failed ads - only return successful ads**
    const creatives = await AdCreative.find({ 
      campaignId: { $in: campaignIds },
      reviewStatus: { $ne: 'rejected' }, // Exclude rejected ads
      cloudinaryUrl: { $exists: true, $ne: null }, // Must have media URL
      $or: [
        { adType: 'banner', title: { $exists: true, $ne: null } }, // Banner ads must have title
        { adType: 'carousel', slides: { $exists: true, $not: { $size: 0 } } }, // Carousel must have slides
        { adType: 'video feed ad' } // Video feed ads just need cloudinaryUrl
      ]
    })
      .sort({ createdAt: -1 });

    console.log(`🔍 Found ${campaigns.length} campaigns and ${creatives.length} creatives for user ${user._id}`);

    if (creatives.length === 0) {
      console.log(`ℹ️ No creatives found for user ${user._id} - returning empty array`);
      return res.json([]);
    }

    // Build AdModel-shaped entries from creatives (banner, carousel, video feeds)
    const ads = creatives.map(creative => {
      const parentCampaign = campaigns.find(c => c._id.toString() === creative.campaignId.toString());
      return {
        _id: creative._id.toString(),
        id: creative._id.toString(),
        title: parentCampaign?.name || 'Untitled Ad',
        description: parentCampaign?.objective || '',
        imageUrl: creative.adType === 'carousel ads' ? (creative.slides?.[0]?.thumbnail || creative.slides?.[0]?.mediaUrl || null) : (creative.thumbnail || creative.cloudinaryUrl || null),
        videoUrl: creative.type === 'video' ? creative.cloudinaryUrl : null,
        link: (creative.callToAction && creative.callToAction.url) ? creative.callToAction.url : null,
        adType: creative.adType,
        budget: (parentCampaign?.dailyBudget || 0) * 100, // cents for frontend
        targetAudience: 'all',
        targetKeywords: [],
        startDate: parentCampaign?.startDate,
        endDate: parentCampaign?.endDate,
        status: parentCampaign?.status || (creative.isActive ? 'active' : 'draft'),
        impressions: creative.impressions || 0,
        clicks: creative.clicks || 0,
        ctr: creative.ctr || 0.0,
        createdAt: creative.createdAt,
        updatedAt: creative.updatedAt,
        // Targeting copied from campaign if exists
        minAge: parentCampaign?.target?.age?.min || null,
        maxAge: parentCampaign?.target?.age?.max || null,
        gender: parentCampaign?.target?.gender || null,
        locations: parentCampaign?.target?.locations || [],
        interests: parentCampaign?.target?.interests || [],
        platforms: parentCampaign?.target?.platforms || [],
        deviceType: parentCampaign?.target?.deviceType || null,
        optimizationGoal: parentCampaign?.optimizationGoal || null,
        frequencyCap: parentCampaign?.frequencyCap || null,
        timeZone: parentCampaign?.timeZone || null,
        dayParting: parentCampaign?.dayParting || {},
        hourParting: parentCampaign?.hourParting || {},
        // Required fields for AdModel
        uploaderId: userId,
        uploaderName: user.name || '',
        uploaderProfilePic: user.profilePic || ''
      };
    });

    console.log(`✅ Returning ${ads.length} ads (creatives) for user ${user._id}`);
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

// **NEW: Get active ads for serving**
router.get('/serve', async (req, res) => {
  try {
    const { adType } = req.query;
    
    // Build query for active campaigns
    const campaignQuery = {
      status: 'active',
      startDate: { $lte: new Date() },
      endDate: { $gte: new Date() }
    };
    
    // Find active campaigns, sorted by creation date (newest first)
    const campaigns = await AdCampaign.find(campaignQuery)
      .sort({ createdAt: -1 }) // **FIX: Sort by newest first to show latest ads**
      .limit(50); // **FIX: Increase limit to ensure all active ads are included**
    
    // **FIX: Get campaign IDs and query creatives separately (since AdCampaign doesn't have creative field)**
    const campaignIds = campaigns.map(c => c._id);
    
    console.log('🔍 /api/ads/serve - Debug:');
    console.log('   Found campaigns:', campaigns.length);
    console.log('   Campaign IDs:', campaignIds.map(id => id.toString()));
    
    // **DEBUG: First check ALL creatives (without filters) to see what's available**
    const allCreatives = await AdCreative.find({ 
      campaignId: { $in: campaignIds } 
    }).sort({ createdAt: -1 });
    
    console.log('   Total creatives found (no filters):', allCreatives.length);
    allCreatives.forEach((creative, idx) => {
      console.log(`   Creative ${idx}:`, {
        id: creative._id,
        campaignId: creative.campaignId,
        adType: creative.adType,
        title: creative.title,
        isActive: creative.isActive,
        reviewStatus: creative.reviewStatus,
        cloudinaryUrl: creative.cloudinaryUrl ? 'exists' : 'missing'
      });
    });
    
    // Build creative query
    // **FIX: Include 'pending' status for existing ads that haven't been approved yet**
    // This allows ads that were created before auto-approve was added to still show
    const creativeQuery = {
      campaignId: { $in: campaignIds },
      isActive: true,
      reviewStatus: { $in: ['approved', 'auto-approved', 'pending'] }
    };
    
    // Filter by adType if specified
    if (adType) {
      creativeQuery.adType = adType;
      console.log('   Filtering by adType:', adType);
    }
    
    console.log('   Creative query:', JSON.stringify(creativeQuery, null, 2));
    
    // Find creatives for these campaigns
    const creatives = await AdCreative.find(creativeQuery)
      .sort({ createdAt: -1 });
    
    console.log('   Creatives matching filters:', creatives.length);
    
    // **FIX: Create a map of campaignId -> creative for quick lookup**
    const creativeMap = new Map();
    creatives.forEach(creative => {
      // Handle both ObjectId and string formats
      const campaignId = creative.campaignId ? creative.campaignId.toString() : null;
      if (campaignId && !creativeMap.has(campaignId)) {
        creativeMap.set(campaignId, creative);
      }
    });
    
    // **FIX: Match campaigns with creatives**
    const validCampaigns = campaigns
      .map(campaign => {
        const campaignIdStr = campaign._id.toString();
        const creative = creativeMap.get(campaignIdStr);
        if (!creative) {
          console.log('⚠️ Campaign missing creative:', {
            campaignId: campaignIdStr,
            campaignName: campaign.name,
            campaignStatus: campaign.status,
            availableCreativeIds: Array.from(creativeMap.keys())
          });
          return null;
        }
        return { campaign, creative };
      })
      .filter(item => item !== null);
    
    // Convert to ad format for frontend
    const ads = validCampaigns.map(({ campaign, creative }) => {
      // **DEBUG: Log banner ad details**
      if (creative.adType === 'banner') {
        console.log('🔍 Banner Ad Debug:');
        console.log('   Campaign ID:', campaign._id);
        console.log('   Creative ID:', creative._id);
        console.log('   Title:', creative.title);
        console.log('   CloudinaryUrl:', creative.cloudinaryUrl);
        console.log('   CallToAction:', creative.callToAction);
        console.log('   CallToAction URL:', creative.callToAction?.url);
        console.log('   IsActive:', creative.isActive);
        console.log('   ReviewStatus:', creative.reviewStatus);
      }
      
      return {
        id: campaign._id.toString(),
        campaignId: campaign._id.toString(),
        adType: creative.adType,
        title: creative.title || campaign.name,
        description: creative.description || '',
        imageUrl: creative.cloudinaryUrl || (creative.slides && creative.slides.length > 0 ? creative.slides[0].mediaUrl : null),
        videoUrl: creative.type === 'video' ? (creative.cloudinaryUrl || (creative.slides && creative.slides.length > 0 ? creative.slides[0].mediaUrl : null)) : null,
        link: creative.callToAction?.url || '',
        callToAction: creative.callToAction,
        slides: creative.slides || [],
        advertiserName: campaign.name,
        isActive: true,
        impressions: creative.impressions || 0,
        clicks: creative.clicks || 0,
        createdAt: campaign.createdAt
      };
    });
    
    // **DEBUG: Log final response**
    console.log('🔍 Final ads response:');
    console.log('   Total ads:', ads.length);
    ads.forEach((ad, index) => {
      console.log(`   Ad ${index}:`, {
        id: ad.id,
        adType: ad.adType,
        title: ad.title,
        imageUrl: ad.imageUrl,
        link: ad.link,
        callToAction: ad.callToAction
      });
    });
    
    res.json(ads);
  } catch (error) {
    console.error('❌ Error serving ads:', error);
    res.status(500).json({ error: 'Failed to serve ads' });
  }
});

// **NEW: Auto-approve all pending active ads (for existing ads)**
router.post('/auto-approve-pending', async (req, res) => {
  try {
    console.log('🔄 Auto-approving pending ads...');
    
    // Find all active campaigns
    const campaigns = await AdCampaign.find({
      status: 'active',
      startDate: { $lte: new Date() },
      endDate: { $gte: new Date() }
    });
    
    const campaignIds = campaigns.map(c => c._id);
    
    // Update all pending creatives to approved and activate them
    const result = await AdCreative.updateMany(
      {
        campaignId: { $in: campaignIds },
        reviewStatus: 'pending',
        isActive: false
      },
      {
        $set: {
          reviewStatus: 'approved',
          isActive: true,
          activatedAt: new Date()
        }
      }
    );
    
    console.log(`✅ Auto-approved ${result.modifiedCount} pending ads`);
    
    res.json({
      success: true,
      message: `Auto-approved ${result.modifiedCount} pending ads`,
      modifiedCount: result.modifiedCount
    });
  } catch (error) {
    console.error('❌ Error auto-approving pending ads:', error);
    res.status(500).json({ error: 'Failed to auto-approve pending ads' });
  }
});

// **NEW: Get carousel ads specifically**
router.get('/carousel', async (req, res) => {
  try {
    // Find active carousel campaigns
    const campaigns = await AdCampaign.find({
      status: 'active',
      startDate: { $lte: new Date() },
      endDate: { $gte: new Date() }
    })
    .populate({
      path: 'creative',
      match: { adType: 'carousel' }
    })
    .limit(10);
    
    // Filter out campaigns without carousel creatives
    const validCampaigns = campaigns.filter(campaign => 
      campaign.creative && campaign.creative.adType === 'carousel'
    );
    
    // Convert to carousel ad format
    const carouselAds = validCampaigns.map(campaign => {
      const creative = campaign.creative;
      return {
        id: creative._id,
        campaignId: campaign._id,
        adType: 'carousel',
        title: creative.title || campaign.name,
        description: creative.description || '',
        slides: creative.slides || [],
        callToAction: creative.callToAction,
        advertiserName: campaign.name,
        isActive: true,
        impressions: creative.impressions || 0,
        clicks: creative.clicks || 0,
        createdAt: campaign.createdAt
      };
    });
    
    res.json(carouselAds);
  } catch (error) {
    console.error('❌ Error fetching carousel ads:', error);
    res.status(500).json({ error: 'Failed to fetch carousel ads' });
  }
});

// **NEW: Track ad impression**
router.post('/:adId/impression', async (req, res) => {
  try {
    const { adId } = req.params;
    
    // Find the creative and increment impression count
    await AdCreative.findByIdAndUpdate(adId, {
      $inc: { impressions: 1 }
    });
    
    res.json({ success: true });
  } catch (error) {
    console.error('❌ Error tracking impression:', error);
    res.status(500).json({ error: 'Failed to track impression' });
  }
});

// **NEW: Track ad click**
router.post('/:adId/click', async (req, res) => {
  try {
    const { adId } = req.params;
    
    // Find the creative and increment click count
    await AdCreative.findByIdAndUpdate(adId, {
      $inc: { clicks: 1 }
    });
    
    res.json({ success: true });
  } catch (error) {
    console.error('❌ Error tracking click:', error);
    res.status(500).json({ error: 'Failed to track click' });
  }
});

// **TARGETING ROUTES**
router.use('/targeting', adTargetingRoutes);

// **AD COMMENTS ROUTES**
router.use('/comments', adCommentRoutes);

// **NEW: Cleanup expired ads (manual trigger)**
router.post('/cleanup/expired', async (req, res) => {
  try {
    console.log('🧹 Manual cleanup triggered');
    const result = await adCleanupService.runCleanup();
    res.json({
      success: true,
      message: 'Cleanup completed successfully',
      result
    });
  } catch (error) {
    console.error('❌ Error in manual cleanup:', error);
    res.status(500).json({ error: 'Failed to cleanup expired ads' });
  }
});

// **NEW: Endpoint to get ad views for a specific video and ad type (for mobile calculation)**
router.get('/views/video/:videoId/:adType', verifyToken, async (req, res) => {
  try {
    const { videoId, adType } = req.params;
    const { month, year } = req.query;

    // **FIX: Use simple count (no isViewed check) to match Admin Dashboard logic**
    // This ensures consistency between mobile and admin dashboard
    const query = {
      videoId: videoId,
      adType: adType, // 'banner' or 'carousel'
      impressionType: 'view'
    };

    // Add date filtering if month/year provided
    if (month && year) {
      const monthInt = parseInt(month); // 1-12
      const yearInt = parseInt(year);
      
      // Mobile sends 1-indexed month, JS Date uses 0-indexed
      const startDate = new Date(yearInt, monthInt - 1, 1);
      const endDate = new Date(yearInt, monthInt, 1);
      
      query.timestamp = {
        $gte: startDate,
        $lt: endDate
      };
    }

    // Dynamic import to avoid circular dependencies if any
    const AdImpression = (await import('../models/AdImpression.js')).default;
    const count = await AdImpression.countDocuments(query);

    console.log(`👁️ /views/video: ${adType} views for ${videoId} (${month ? month + '/' + year : 'all time'}): ${count}`);
    
    res.json({
      success: true,
      count: count,
      videoId,
      adType,
      period: month ? `${month}/${year}` : 'all_time'
    });
  } catch (error) {
    console.error('❌ Error fetching ad views:', error);
    res.status(500).json({ error: 'Failed to fetch ad views' });
  }
});

export default router;
