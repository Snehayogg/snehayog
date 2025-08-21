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

    const campaign = new AdCampaign({
      name,
      advertiserUserId: req.user.id, // Will be set by auth middleware
      objective,
      startDate: start,
      endDate: end,
      dailyBudget,
      totalBudget,
      bidType: bidType || 'CPM',
      cpmINR: cpmINR || 30,
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
      platformRevenue
    } = req.body;

    // Validate required fields
    if (!title || !description || !adType || !budget || !uploaderId) {
      return res.status(400).json({ error: 'Missing required fields' });
    }

    // Validate budget
    if (budget < 100) {
      return res.status(400).json({ error: 'Budget must be at least ₹100' });
    }

    // Create ad creative
    const adCreative = new AdCreative({
      title,
      description,
      imageUrl,
      videoUrl,
      link,
      adType,
      uploaderId,
      uploaderName,
      uploaderProfilePic,
      targetAudience: targetAudience || 'all',
      targetKeywords: targetKeywords || [],
      estimatedImpressions: estimatedImpressions || Math.floor(budget / 30 * 1000), // Based on ₹30 CPM
      fixedCpm: fixedCpm || 30,
      creatorRevenue: creatorRevenue || budget * 0.80,
      platformRevenue: platformRevenue || budget * 0.20,
      status: 'draft'
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
      message: 'Ad created successfully. Payment required to activate.',
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
    const { userId, platform, location } = req.query;

    // Get active ads that match targeting criteria
    const activeAds = await AdCreative.find({
      status: 'active',
      $or: [
        { targetAudience: 'all' },
        { targetAudience: { $in: [userId, platform, location] } }
      ]
    }).limit(10);

    // Update impression count
    for (const ad of activeAds) {
      ad.impressions = (ad.impressions || 0) + 1;
      await ad.save();
    }

    res.json({
      ads: activeAds,
      count: activeAds.length
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

    // **NEW: Fixed CPM calculation for India market**
    const fixedCpm = 30.0; // ₹30 fixed CPM (Cost Per Mille)
    const estimatedRevenueINR = (totalViews / 1000) * fixedCpm;
    const creatorRevenueINR = estimatedRevenueINR * 0.80; // 80% to creator

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

    // Calculate monthly revenue
    const currentMonthViews = currentMonthVideos.reduce((sum, v) => sum + (v.views || 0), 0);
    const lastMonthViews = lastMonthVideos.reduce((sum, v) => sum + (v.views || 0), 0);
    
    const currentMonthRevenue = (currentMonthViews / 1000) * fixedCpm;
    const lastMonthRevenue = (lastMonthViews / 1000) * fixedCpm;
    
    const currentMonthCreatorRevenue = currentMonthRevenue * 0.80;
    const lastMonthCreatorRevenue = lastMonthRevenue * 0.80;

    const response = {
      // **NEW: Match Flutter app expected structure**
      totalRevenue: Math.round(creatorRevenueINR * 100) / 100,
      thisMonth: Math.round(currentMonthCreatorRevenue * 100) / 100,
      lastMonth: Math.round(lastMonthCreatorRevenue * 100) / 100,
      adRevenue: Math.round(estimatedRevenueINR * 100) / 100,
      platformFee: Math.round(estimatedRevenueINR * 0.20 * 100) / 100,
      netRevenue: Math.round(creatorRevenueINR * 100) / 100,
      
      // **NEW: Additional data for enhanced UI**
      totalViews: totalViews,
      totalLikes: totalLikes,
      totalShares: totalShares,
      totalPaidOut: Math.round(totalPaidOut * 100) / 100,
      pendingPayouts: Math.round(pendingPayouts * 100) / 100,
      availableForPayout: Math.round((creatorRevenueINR - totalPaidOut) * 100) / 100,
      
      // **NEW: Video statistics**
      videoStats: {
        total: userVideos.length,
        shorts: userVideos.filter(v => v.videoType === 'short').length,
        longForm: userVideos.filter(v => v.videoType === 'long').length
      },
      
      // **NEW: Payment history in expected format**
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
      estimatedRevenue: response.revenue.estimatedRevenueINR,
      creatorRevenue: response.revenue.creatorRevenueINR
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

// **NEW: Get user's ads**
router.get('/user/:userId', verifyToken, async (req, res) => {
  try {
    const { userId } = req.params;
    
    // Verify the user is requesting their own ads
    if (req.user.id !== userId) {
      return res.status(403).json({ error: 'Access denied' });
    }

    // Get user's ad campaigns
    const campaigns = await AdCampaign.find({ advertiserUserId: userId })
      .populate('creative')
      .populate('advertiserUserId', 'name profilePic')
      .sort({ createdAt: -1 });

    // Convert campaigns to the format expected by AdModel
    const ads = campaigns.map(campaign => ({
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
      uploaderId: campaign.advertiserUserId?._id?.toString() || campaign.advertiserUserId?.toString() || '',
      uploaderName: campaign.advertiserUserId?.name || '',
      uploaderProfilePic: campaign.advertiserUserId?.profilePic || ''
    }));

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

    // Verify ownership
    if (campaign.advertiserUserId.toString() !== req.user.id) {
      return res.status(403).json({ error: 'Access denied' });
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

    // Verify ownership
    if (campaign.advertiserUserId.toString() !== req.user.id) {
      return res.status(403).json({ error: 'Access denied' });
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
