import express from 'express';
import { asyncHandler } from '../../middleware/errorHandler.js';
import { validateAdData, validatePaymentData } from '../../middleware/errorHandler.js';
import adService from '../../services/adService.js';
import User from '../../models/User.js';
import { verifyToken } from '../../utils/verifytoken.js';

const router = express.Router();

// POST /ads/create-with-payment - Create ad with payment processing
router.post('/create-with-payment', validateAdData, asyncHandler(async (req, res) => {
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
      estimatedRevenue: estimatedRevenueINR,
      creatorRevenue: creatorRevenueINR
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

export default router;
