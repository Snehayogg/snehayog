import express from 'express';
import { asyncHandler } from '../../middleware/errorHandler.js';
import { validatePaymentData } from '../../middleware/errorHandler.js';
import adService from '../../services/adService.js';
import User from '../../models/User.js';
import { verifyToken } from '../../utils/verifytoken.js';

const router = express.Router();

// POST /ads/create-with-payment - Create ad with payment processing
router.post('/create-with-payment', asyncHandler(async (req, res) => {
  const result = await adService.createAdWithPayment(req.body);
  
  res.status(201).json({
    message: 'Ad created successfully. Payment required to activate.',
    ...result
  });
}));

// POST /ads/process-payment - Process Razorpay payment
router.post('/process-payment', validatePaymentData, asyncHandler(async (req, res) => {
  const result = await adService.processPayment(req.body);
  
  res.json({
    message: 'Payment processed successfully. Ad is now active!',
    ...result
  });
}));

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

    // Get user's videos to calculate potential revenue
    const userVideos = await user.getVideos();
    console.log('🔍 Found videos for user:', userVideos.length);

    // Get video IDs for querying ad impressions
    const videoIds = userVideos.map(video => video._id);

    // **FIXED: Use ACTUAL ad impressions from AdImpression collection (realtime)**
    const AdImpression = (await import('../../models/AdImpression.js')).default;
    
    // Count actual banner ad impressions for user's videos
    const bannerImpressions = await AdImpression.countDocuments({
      videoId: { $in: videoIds },
      adType: 'banner',
      impressionType: 'view'
    });

    // Count actual carousel ad impressions for user's videos
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
    const CreatorPayout = (await import('../../models/CreatorPayout.js')).default;
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

    // Calculate monthly revenue
    const currentMonth = new Date().getMonth();
    const currentYear = new Date().getFullYear();
    const lastMonth = currentMonth === 0 ? 11 : currentMonth - 1;
    const lastMonthYear = currentMonth === 0 ? currentYear - 1 : currentYear;
    
    // **FIXED: Count impressions for ALL videos in current month (not just videos uploaded this month)**
    // This ensures earnings from older videos that get views in current month are included
    
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

export default router;
