import express from 'express';
import mongoose from 'mongoose';
import Feedback from '../models/Feedback.js';
import requireAdminDashboardKey from '../middleware/adminDashboardAuth.js';
import User from '../models/User.js';
import Video from '../models/Video.js';
import CreatorPayout from '../models/CreatorPayout.js';
import AdImpression from '../models/AdImpression.js';
import { AD_CONFIG } from '../constants/index.js';
import RecommendationService from '../services/recommendationService.js';

const router = express.Router();






// Admin feedback endpoints
router.get('/feedback', requireAdminDashboardKey, async (req, res) => {
  try {
    const {
      limit = 50,
      rating,
      search,
      sort = 'desc',
      unread,
      replied
    } = req.query;

    const query = {};

    if (rating) {
      const parsedRating = parseInt(rating, 10);
      if (!Number.isNaN(parsedRating)) {
        query.rating = parsedRating;
      }
    }

    if (unread === 'true') {
      query.isRead = false;
    } else if (unread === 'false') {
      query.isRead = true;
    }

    if (replied === 'true') {
      query.isReplied = true;
    } else if (replied === 'false') {
      query.isReplied = false;
    }

    if (search && search.trim()) {
      const regex = new RegExp(search.trim(), 'i');
      query.$or = [
        { comments: regex },
        { userEmail: regex },
        { adminReply: regex }
      ];
    }

    const sortOrder = sort === 'asc' ? 1 : -1;
    const normalizedLimit = Math.min(Math.max(parseInt(limit, 10) || 50, 1), 200);

    const feedback = await Feedback.find(query)
      .sort({ createdAt: sortOrder })
      .limit(normalizedLimit)
      .lean();

    res.json({
      success: true,
      count: feedback.length,
      feedback
    });
  } catch (error) {
    console.error('❌ Error loading feedback:', error);
    res.status(500).json({ success: false, error: 'Failed to load feedback' });
  }
});

router.get('/feedback/stats', requireAdminDashboardKey, async (req, res) => {
  try {
    const stats = await Feedback.getStats();
    res.json({ success: true, stats });
  } catch (error) {
    console.error('❌ Error loading feedback stats:', error);
    res.status(500).json({ success: false, error: 'Failed to load feedback stats' });
  }
});

router.get('/feedback/:id', requireAdminDashboardKey, async (req, res) => {
  try {
    const feedback = await Feedback.findById(req.params.id).lean();
    if (!feedback) {
      return res.status(404).json({ success: false, error: 'Feedback not found' });
    }
    res.json(feedback);
  } catch (error) {
    console.error('❌ Error loading feedback detail:', error);
    res.status(500).json({ success: false, error: 'Failed to load feedback detail' });
  }
});

router.put('/feedback/:id/read', requireAdminDashboardKey, async (req, res) => {
  try {
    const feedback = await Feedback.findById(req.params.id);
    if (!feedback) {
      return res.status(404).json({ success: false, error: 'Feedback not found' });
    }

    if (!feedback.isRead) {
      feedback.isRead = true;
      feedback.readAt = new Date();
      await feedback.save();
    }

    res.json({ success: true, message: 'Feedback marked as read' });
  } catch (error) {
    console.error('❌ Error marking feedback as read:', error);
    res.status(500).json({ success: false, error: 'Failed to mark feedback as read' });
  }
});

router.post('/feedback/:id/reply', requireAdminDashboardKey, async (req, res) => {
  try {
    const { reply } = req.body;
    if (!reply || !reply.trim()) {
      return res.status(400).json({ success: false, error: 'Reply is required' });
    }

    const feedback = await Feedback.findById(req.params.id);
    if (!feedback) {
      return res.status(404).json({ success: false, error: 'Feedback not found' });
    }

    feedback.adminReply = reply.trim();
    feedback.isReplied = true;
    feedback.repliedAt = new Date();
    await feedback.save();

    res.json({ success: true, message: 'Reply recorded successfully' });
  } catch (error) {
    console.error('❌ Error replying to feedback:', error);
    res.status(500).json({ success: false, error: 'Failed to reply to feedback' });
  }
});

router.get('/feedback/export', requireAdminDashboardKey, async (req, res) => {
  try {
    const feedback = await Feedback.find().sort({ createdAt: -1 }).lean();

    const headers = [
      'id',
      'rating',
      'comments',
      'userEmail',
      'userId',
      'isRead',
      'readAt',
      'isReplied',
      'adminReply',
      'repliedAt',
      'createdAt',
      'updatedAt'
    ];

    const escapeCsv = (value) => {
      if (value === null || value === undefined) return '';
      const stringValue = String(value).replace(/"/g, '""');
      if (/[",\n]/.test(stringValue)) {
        return `"${stringValue}"`;
      }
      return stringValue;
    };

    const rows = feedback.map((item) => [
      item._id,
      item.rating,
      item.comments || '',
      item.userEmail,
      item.userId || '',
      item.isRead,
      item.readAt ? item.readAt.toISOString() : '',
      item.isReplied,
      item.adminReply || '',
      item.repliedAt ? item.repliedAt.toISOString() : '',
      item.createdAt ? item.createdAt.toISOString() : '',
      item.updatedAt ? item.updatedAt.toISOString() : ''
    ]);

    const csvContent = [
      headers.join(','),
      ...rows.map((row) => row.map(escapeCsv).join(','))
    ].join('\n');

    res.setHeader(
      'Content-Disposition',
      `attachment; filename="feedback-export-${new Date().toISOString().split('T')[0]}.csv"`
    );
    res.setHeader('Content-Type', 'text/csv');
    res.send(csvContent);
  } catch (error) {
    console.error('❌ Error exporting feedback:', error);
    res.status(500).json({ success: false, error: 'Failed to export feedback' });
  }
});

router.get('/creators', requireAdminDashboardKey, async (req, res) => {
  try {
    const [creators, videoStats, adStats, payoutStats, earningsStats] = await Promise.all([
      User.find({}, 'name email preferredPaymentMethod paymentDetails country payoutCount createdAt googleId').lean(),
      Video.aggregate([
        {
          $group: {
            _id: '$uploader',
            totalViews: { $sum: '$views' },
            totalVideos: {
              $sum: {
                $cond: [{ $eq: ['$processingStatus', 'completed'] }, 1, 0]
              }
            }
          }
        }
      ]),
      AdImpression.aggregate([
        {
          $group: {
            _id: '$videoId',
            totalAdViews: {
              $sum: {
                $cond: [
                  { $gt: ['$viewCount', 0] },
                  '$viewCount',
                  { $cond: ['$isViewed', 1, 0] }
                ]
              }
            },
            totalAdImpressions: { $sum: 1 }
          }
        },
        {
          $lookup: {
            from: 'videos',
            localField: '_id',
            foreignField: '_id',
            as: 'video'
          }
        },
        { $unwind: '$video' },
        {
          $group: {
            _id: '$video.uploader',
            totalAdViews: { $sum: '$totalAdViews' },
            totalAdImpressions: { $sum: '$totalAdImpressions' }
          }
        }
      ]),
      CreatorPayout.aggregate([
        {
          $group: {
            _id: '$creatorId',
            totalEarningsINR: { $sum: '$payableINR' },
            pendingEarningsINR: {
              $sum: {
                $cond: [{ $eq: ['$status', 'pending'] }, '$payableINR', 0]
              }
            },
            processingEarningsINR: {
              $sum: {
                $cond: [{ $eq: ['$status', 'processing'] }, '$payableINR', 0]
              }
            },
            paidEarningsINR: {
              $sum: {
                $cond: [{ $eq: ['$status', 'paid'] }, '$payableINR', 0]
              }
            },
            eligiblePendingINR: {
              $sum: {
                $cond: [
                  {
                    $and: [
                      { $eq: ['$status', 'pending'] },
                      '$isEligibleForPayout'
                    ]
                  },
                  '$payableINR',
                  0
                ]
              }
            },
            lastPayoutAt: { $max: '$paymentDate' }
          }
        }
      ]),
      AdImpression.aggregate([
        { $match: { isViewed: true } },
        {
          $lookup: {
            from: 'videos',
            localField: 'videoId',
            foreignField: '_id',
            as: 'video'
          }
        },
        { $unwind: '$video' },
        {
          $group: {
            _id: { creator: '$video.uploader', adType: '$adType' },
            viewSum: {
              $sum: {
                $cond: [
                  { $gt: ['$viewCount', 0] },
                  '$viewCount',
                  1
                ]
              }
            }
          }
        },
        {
          $group: {
            _id: '$_id.creator',
            bannerViews: {
              $sum: {
                $cond: [
                  { $eq: ['$_id.adType', 'banner'] },
                  '$viewSum',
                  0
                ]
              }
            },
            carouselViews: {
              $sum: {
                $cond: [
                  { $eq: ['$_id.adType', 'carousel'] },
                  '$viewSum',
                  0
                ]
              }
            },
            totalAdViews: { $sum: '$viewSum' }
          }
        }
      ])
    ]);

    const videoMap = new Map();
    videoStats.forEach((stat) => {
      videoMap.set(String(stat._id), {
        totalViews: stat.totalViews || 0,
        totalVideos: stat.totalVideos || 0
      });
    });

    const adMap = new Map();
    adStats.forEach((stat) => {
      adMap.set(String(stat._id), {
        totalAdViews: stat.totalAdViews || 0,
        totalAdImpressions: stat.totalAdImpressions || 0
      });
    });

    const payoutMap = new Map();
    payoutStats.forEach((stat) => {
      payoutMap.set(String(stat._id), {
        totalEarningsINR: stat.totalEarningsINR || 0,
        pendingEarningsINR: stat.pendingEarningsINR || 0,
        processingEarningsINR: stat.processingEarningsINR || 0,
        paidEarningsINR: stat.paidEarningsINR || 0,
        eligiblePendingINR: stat.eligiblePendingINR || 0,
        lastPayoutAt: stat.lastPayoutAt || null
      });
    });

    const bannerCpm = AD_CONFIG?.BANNER_CPM ?? 10;
    const carouselCpm = AD_CONFIG?.DEFAULT_CPM ?? 30;
    const creatorShare = AD_CONFIG?.CREATOR_REVENUE_SHARE ?? 0.8;
    const platformShare = AD_CONFIG?.PLATFORM_REVENUE_SHARE ?? 0.2;

    const earningsMap = new Map();
    earningsStats.forEach((stat) => {
      const totalViews = stat.totalAdViews || 0;
      const bannerViews = stat.bannerViews || 0;
      const carouselViews = stat.carouselViews || 0;
      const bannerRevenue = (bannerViews / 1000) * bannerCpm;
      const carouselRevenue = (carouselViews / 1000) * carouselCpm;
      const grossRevenueINR = bannerRevenue + carouselRevenue;
      const creatorRevenueINR = grossRevenueINR * creatorShare;
      const platformRevenueINR = grossRevenueINR * platformShare;

      earningsMap.set(String(stat._id), {
        totalAdViews: totalViews,
        bannerViews,
        carouselViews,
        grossRevenueINR,
        creatorRevenueINR,
        platformRevenueINR
      });
    });

    const creatorSummaries = creators.map((creator) => {
      const id = String(creator._id);
      const videos = videoMap.get(id) || { totalViews: 0, totalVideos: 0 };
      const ads = adMap.get(id) || {
        totalAdViews: 0,
        totalAdImpressions: 0
      };
      const payouts = payoutMap.get(id) || {
        totalEarningsINR: 0,
        pendingEarningsINR: 0,
        processingEarningsINR: 0,
        paidEarningsINR: 0,
        eligiblePendingINR: 0,
        lastPayoutAt: null
      };

      const upiId = creator?.paymentDetails?.upiId || null;
      const paymentSummary = {
        preferredPaymentMethod: creator.preferredPaymentMethod || null,
        upiId,
        paypalEmail: creator?.paymentDetails?.paypalEmail || null,
        stripeAccountId: creator?.paymentDetails?.stripeAccountId || null,
        wiseEmail: creator?.paymentDetails?.wiseEmail || null
      };

      const earnings = earningsMap.get(id) || {
        totalAdViews: ads.totalAdViews || 0,
        bannerViews: 0,
        carouselViews: 0,
        grossRevenueINR: 0,
        creatorRevenueINR: 0,
        platformRevenueINR: 0
      };

      const creatorRevenueINR =
        earnings.creatorRevenueINR && earnings.creatorRevenueINR > 0
          ? earnings.creatorRevenueINR
          : payouts.totalEarningsINR || 0;


      return {
        id,
        googleId: creator.googleId,
        name: creator.name,
        email: creator.email,
        country: creator.country || 'IN',
        totalVideos: videos.totalVideos,
        totalViews: videos.totalViews,
        totalAdViews: earnings.totalAdViews,
        bannerAdViews: earnings.bannerViews,
        carouselAdViews: earnings.carouselViews,
        totalAdImpressions: ads.totalAdImpressions,
        grossRevenueINR: earnings.grossRevenueINR,
        creatorRevenueINR,
        platformRevenueINR: earnings.platformRevenueINR,
        reportedPayoutINR: payouts.totalEarningsINR,
        totalEarningsINR: creatorRevenueINR,
        pendingEarningsINR: payouts.pendingEarningsINR,
        processingEarningsINR: payouts.processingEarningsINR,
        paidEarningsINR: payouts.paidEarningsINR,
        eligiblePendingINR: payouts.eligiblePendingINR,
        payoutCount: creator.payoutCount || 0,
        paymentDetails: paymentSummary,
        createdAt: creator.createdAt,
        lastPayoutAt: payouts.lastPayoutAt,
        // **NEW: Include videos for frontend revenue calculation**
        videos: [] // Will be populated separately if needed (empty for now to save bandwidth)
      };
    });

    // Removed filter to show all creators regardless of video count
    const creatorsWithVideos = creatorSummaries;

    creatorsWithVideos.sort(
      (a, b) => (b.creatorRevenueINR || 0) - (a.creatorRevenueINR || 0)
    );

    res.json({
      success: true,
      count: creatorsWithVideos.length,
      creators: creatorsWithVideos
    });
  } catch (error) {
    console.error('❌ Error loading creator summaries:', error);
    res
      .status(500)
      .json({ success: false, error: 'Failed to load creator data' });
  }
});

// ✅ Route to get platform-wide statistics
router.get('/stats', requireAdminDashboardKey, async (req, res) => {
  try {
    // Get total videos count (completed only)
    const totalVideos = await Video.countDocuments({ processingStatus: 'completed' });

    // **NEW: Get daily upload count (videos uploaded today)**
    const today = new Date();
    today.setHours(0, 0, 0, 0);
    const tomorrow = new Date(today);
    tomorrow.setDate(tomorrow.getDate() + 1);

    const dailyUploadCount = await Video.countDocuments({
      createdAt: {
        $gte: today,
        $lt: tomorrow
      },
      processingStatus: 'completed'
    });

    // Calculate total earnings across all creators
    // Get all creators and their earnings
    const creators = await User.find({}).select('_id').lean();
    const creatorIds = creators.map(c => c._id);

    // Get all videos for all creators
    const allVideos = await Video.find({ uploader: { $in: creatorIds } }).select('_id').lean();
    const allVideoIds = allVideos.map(v => v._id);

    // Calculate total ad impressions and earnings
    const bannerImpressions = await AdImpression.countDocuments({
      videoId: { $in: allVideoIds },
      adType: 'banner',
      impressionType: 'view'
    });

    const carouselImpressions = await AdImpression.countDocuments({
      videoId: { $in: allVideoIds },
      adType: 'carousel',
      impressionType: 'view'
    });

    // Calculate revenue (same logic as revenue API)
    const bannerCpm = AD_CONFIG?.BANNER_CPM ?? 10; // ₹10 per 1000 impressions
    const carouselCpm = AD_CONFIG?.DEFAULT_CPM ?? 30; // ₹30 per 1000 impressions
    const creatorShare = AD_CONFIG?.CREATOR_REVENUE_SHARE ?? 0.8; // 80% to creator

    const bannerRevenueINR = (bannerImpressions / 1000) * bannerCpm;
    const carouselRevenueINR = (carouselImpressions / 1000) * carouselCpm;
    const totalGrossRevenueINR = bannerRevenueINR + carouselRevenueINR;
    const totalCreatorEarningsINR = totalGrossRevenueINR * creatorShare;

    res.json({
      success: true,
      totalVideos,
      dailyUploadCount, // **NEW: Daily upload count**
      totalCreatorEarningsINR: Math.round(totalCreatorEarningsINR * 100) / 100,
      totalGrossRevenueINR: Math.round(totalGrossRevenueINR * 100) / 100,
      bannerImpressions,
      carouselImpressions,
      totalAdImpressions: bannerImpressions + carouselImpressions
    });
  } catch (error) {
    console.error('❌ Error loading platform stats:', error);
    res.status(500).json({ success: false, error: 'Failed to load platform stats' });
  }
});

// **NEW: Admin endpoint to get monthly earnings for all creators**
router.get('/creators/monthly-earnings', requireAdminDashboardKey, async (req, res) => {
  try {
    const { month, year } = req.query; // **NEW: Support filtering by month/year**

    const creators = await User.find({}).select('_id googleId name email').lean();
    const creatorIds = creators.map(c => c._id);

    // Get all videos for all creators
    const allVideos = await Video.find({ uploader: { $in: creatorIds } }).select('_id uploader').lean();

    // Group videos by creator
    const videosByCreator = new Map();
    allVideos.forEach(video => {
      const creatorId = String(video.uploader);
      if (!videosByCreator.has(creatorId)) {
        videosByCreator.set(creatorId, []);
      }
      videosByCreator.get(creatorId).push(video._id);
    });

    // Calculate current month and last month (or requested month)
    const now = new Date();
    // Use requested date or default to current
    const targetMonth = month !== undefined ? parseInt(month) : now.getMonth();
    const targetYear = year !== undefined ? parseInt(year) : now.getFullYear();

    console.log(`📊 Admin Fetch Monthly Earnings: Request Month=${month}, Year=${year}`);
    console.log(`📊 Parsed Target: Month=${targetMonth}, Year=${targetYear}`);

    // Calculate Last Month (relative to target)
    const lastMonth = targetMonth === 0 ? 11 : targetMonth - 1;
    const lastMonthYear = targetMonth === 0 ? targetYear - 1 : targetYear;

    // Use UTC dates to match database timestamp storage (avoid TZ shifts)
    const currentMonthStart = new Date(Date.UTC(targetYear, targetMonth, 1));
    const currentMonthEnd = new Date(Date.UTC(targetYear, targetMonth + 1, 1));
    const lastMonthStart = new Date(Date.UTC(lastMonthYear, lastMonth, 1));
    const lastMonthEnd = new Date(Date.UTC(lastMonthYear, lastMonth + 1, 1));

    console.log(`📊 Date Range: Current [${currentMonthStart.toISOString()} - ${currentMonthEnd.toISOString()}]`);

    const bannerCpm = AD_CONFIG?.BANNER_CPM ?? 10;
    const carouselCpm = AD_CONFIG?.DEFAULT_CPM ?? 30;
    const creatorShare = AD_CONFIG?.CREATOR_REVENUE_SHARE ?? 0.8;

    // Calculate monthly earnings for each creator
    const monthlyEarnings = await Promise.all(
      creators.map(async (creator) => {
        const creatorId = String(creator._id);
        const videoIds = videosByCreator.get(creatorId) || [];

        if (videoIds.length === 0) {
          return {
            creatorId: creatorId,
            googleId: creator.googleId,
            name: creator.name,
            email: creator.email,
            thisMonth: 0,
            lastMonth: 0,
            currentMonthGrossRevenue: 0,
            currentMonthTotalAdViews: 0,
            currentMonthTotalViews: 0,
            lastMonthBannerViews: 0,
            lastMonthCarouselViews: 0,
            lastMonthTotalAdViews: 0,
            lastMonthGrossRevenue: 0,
            videosUploaded: 0 // **NEW: 0 videos**
          };
        }

        // Convert videoIds to ObjectIds if they're strings
        const videoObjectIds = videoIds.map(id => {
          if (typeof id === 'string') {
            return new mongoose.Types.ObjectId(id);
          }
          return id;
        });

        // Current month impressions
        const currentMonthBanner = await AdImpression.countDocuments({
          videoId: { $in: videoObjectIds },
          adType: 'banner',
          impressionType: 'view',
          timestamp: { $gte: currentMonthStart, $lt: currentMonthEnd }
        });

        const currentMonthCarousel = await AdImpression.countDocuments({
          videoId: { $in: videoObjectIds },
          adType: 'carousel',
          impressionType: 'view',
          timestamp: { $gte: currentMonthStart, $lt: currentMonthEnd }
        });

        // Last month impressions
        const lastMonthBanner = await AdImpression.countDocuments({
          videoId: { $in: videoObjectIds },
          adType: 'banner',
          impressionType: 'view',
          timestamp: { $gte: lastMonthStart, $lt: lastMonthEnd }
        });

        const lastMonthCarousel = await AdImpression.countDocuments({
          videoId: { $in: videoObjectIds },
          adType: 'carousel',
          impressionType: 'view',
          timestamp: { $gte: lastMonthStart, $lt: lastMonthEnd }
        });

        // Calculate revenue
        const currentMonthBannerRevenue = (currentMonthBanner / 1000) * bannerCpm;
        const currentMonthCarouselRevenue = (currentMonthCarousel / 1000) * carouselCpm;
        const currentMonthGrossRevenue = currentMonthBannerRevenue + currentMonthCarouselRevenue;
        const currentMonthTotal = currentMonthGrossRevenue * creatorShare;

        const lastMonthBannerRevenue = (lastMonthBanner / 1000) * bannerCpm;
        const lastMonthCarouselRevenue = (lastMonthCarousel / 1000) * carouselCpm;
        const lastMonthGrossRevenue = lastMonthBannerRevenue + lastMonthCarouselRevenue;
        const lastMonthTotal = lastMonthGrossRevenue * creatorShare;

        // Calculate current month video views from viewDetails using aggregation
        const viewStats = await Video.aggregate([
          {
            $match: {
              _id: { $in: videoObjectIds }
            }
          },
          {
            $unwind: {
              path: '$viewDetails',
              preserveNullAndEmptyArrays: true
            }
          },
          {
            $match: {
              'viewDetails.lastViewedAt': {
                $gte: currentMonthStart,
                $lt: currentMonthEnd
              }
            }
          },
          {
            $group: {
              _id: null,
              totalViews: {
                $sum: {
                  $ifNull: ['$viewDetails.viewCount', 1]
                }
              }
            }
          }
        ]);

        const currentMonthTotalViews = viewStats.length > 0 ? (viewStats[0].totalViews || 0) : 0;

        // **NEW: Count videos uploaded in the target month**
        const videosUploaded = await Video.countDocuments({
          uploader: creator._id,
          createdAt: { $gte: currentMonthStart, $lt: currentMonthEnd },
          processingStatus: 'completed'
        });

        return {
          creatorId: creatorId,
          googleId: creator.googleId,
          name: creator.name,
          email: creator.email,
          thisMonth: Math.round(currentMonthTotal * 100) / 100,
          lastMonth: Math.round(lastMonthTotal * 100) / 100,
          currentMonthGrossRevenue: Math.round(currentMonthGrossRevenue * 100) / 100,
          lastMonthGrossRevenue: Math.round(lastMonthGrossRevenue * 100) / 100,
          currentMonthBannerViews: currentMonthBanner,
          currentMonthCarouselViews: currentMonthCarousel,
          currentMonthTotalAdViews: currentMonthBanner + currentMonthCarousel,
          currentMonthTotalViews: currentMonthTotalViews,
          lastMonthBannerViews: lastMonthBanner,
          lastMonthCarouselViews: lastMonthCarousel,
          lastMonthTotalAdViews: lastMonthBanner + lastMonthCarousel,
          videosUploaded: videosUploaded // **NEW: Include monthly video upload count**
        };
      })
    );

    // Sort by current month earnings (descending)
    monthlyEarnings.sort((a, b) => b.thisMonth - a.thisMonth);

    // Calculate totals
    const totalThisMonth = monthlyEarnings.reduce((sum, c) => sum + c.thisMonth, 0);
    const totalLastMonth = monthlyEarnings.reduce((sum, c) => sum + c.lastMonth, 0);

    res.json({
      success: true,
      currentMonth: `${targetYear}-${String(targetMonth + 1).padStart(2, '0')}`,
      lastMonth: `${lastMonthYear}-${String(lastMonth + 1).padStart(2, '0')}`,
      totalThisMonth: Math.round(totalThisMonth * 100) / 100,
      totalLastMonth: Math.round(totalLastMonth * 100) / 100,
      creators: monthlyEarnings
    });
  } catch (error) {
    console.error('❌ Error loading monthly earnings:', error);
    res.status(500).json({ success: false, error: 'Failed to load monthly earnings' });
  }
});

// **NEW: Admin endpoint to get ad impressions for a specific creator (for frontend calculation)**
router.get('/creators/:creatorId/ad-impressions', requireAdminDashboardKey, async (req, res) => {
  try {
    const { creatorId } = req.params;
    const { month, year } = req.query;

    // Find creator by googleId
    const creator = await User.findOne({ googleId: creatorId }).select('_id').lean();
    if (!creator) {
      return res.status(404).json({
        success: false,
        error: 'Creator not found',
        bannerViews: 0,
        carouselViews: 0
      });
    }

    // Get creator's videos
    const videos = await Video.find({ uploader: creator._id }).select('_id').lean();
    const videoIds = videos.map(v => v._id);

    if (videoIds.length === 0) {
      return res.json({
        success: true,
        bannerViews: 0,
        carouselViews: 0,
        month: parseInt(month),
        year: parseInt(year)
      });
    }

    // Parse month and year
    const monthNum = parseInt(month);
    const yearNum = parseInt(year);

    // Calculate month start and end dates
    const monthStart = new Date(yearNum, monthNum, 1);
    const monthEnd = new Date(yearNum, monthNum + 1, 1);

    // Count banner ad impressions for the specified month
    const bannerViews = await AdImpression.countDocuments({
      videoId: { $in: videoIds },
      adType: 'banner',
      impressionType: 'view',
      isViewed: true, // **FIX: Only count verified views**
      timestamp: {
        $gte: monthStart,
        $lt: monthEnd
      }
    });

    // Count carousel ad impressions for the specified month
    const carouselViews = await AdImpression.countDocuments({
      videoId: { $in: videoIds },
      adType: 'carousel',
      impressionType: 'view',
      isViewed: true, // **FIX: Only count verified views**
      timestamp: {
        $gte: monthStart,
        $lt: monthEnd
      }
    });

    res.json({
      success: true,
      creatorId,
      month: monthNum,
      year: yearNum,
      bannerViews,
      carouselViews,
      totalAdViews: bannerViews + carouselViews
    });
  } catch (error) {
    console.error('❌ Error fetching creator ad impressions:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to fetch ad impressions',
      bannerViews: 0,
      carouselViews: 0
    });
  }
});

// **NEW: Admin endpoint to get all videos with search/filter**

router.get('/videos', requireAdminDashboardKey, async (req, res) => {
  try {
    const { search, limit = 50, skip = 0 } = req.query;
    const query = {};

    if (search && search.trim()) {
      const searchRegex = new RegExp(search.trim(), 'i');
      query.$or = [
        { videoName: searchRegex },
        { description: searchRegex }
      ];
    }

    const videos = await Video.find(query)
      .populate('uploader', 'name email googleId')
      .sort({ createdAt: -1 })
      .limit(parseInt(limit))
      .skip(parseInt(skip))
      .lean();

    const totalCount = await Video.countDocuments(query);

    res.json({
      success: true,
      videos: videos.map(v => ({
        _id: v._id,
        videoName: v.videoName,
        description: v.description,
        views: v.views || 0,
        likes: v.likes || 0,
        createdAt: v.createdAt,
        uploader: v.uploader ? {
          name: v.uploader.name,
          email: v.uploader.email,
          googleId: v.uploader.googleId
        } : null,
        videoUrl: v.videoUrl,
        thumbnailUrl: v.thumbnailUrl
      })),
      totalCount,
      limit: parseInt(limit),
      skip: parseInt(skip)
    });
  } catch (error) {
    console.error('❌ Error loading videos:', error);
    res.status(500).json({ success: false, error: 'Failed to load videos' });
  }
});

// **NEW: Admin endpoint to delete any video**
router.delete('/videos/:videoId', requireAdminDashboardKey, async (req, res) => {
  try {
    const { videoId } = req.params;

    const video = await Video.findById(videoId);
    if (!video) {
      return res.status(404).json({ success: false, error: 'Video not found' });
    }

    // Remove video from user's videos array
    if (video.uploader) {
      await User.findByIdAndUpdate(video.uploader, {
        $pull: { videos: videoId }
      });
    }

    // Delete the video
    await Video.findByIdAndDelete(videoId);

    console.log(`✅ Admin deleted video: ${videoId} - ${video.videoName}`);

    res.json({
      success: true,
      message: 'Video deleted successfully',
      deletedVideo: {
        id: videoId,
        name: video.videoName
      }
    });
  } catch (error) {
    console.error('❌ Error deleting video:', error);
    res.status(500).json({ success: false, error: 'Failed to delete video' });
  }
});

// **NEW: Admin endpoint to manually trigger recommendation score recalculation**
router.post('/recalculate-scores', requireAdminDashboardKey, async (req, res) => {
  try {
    const { onlyOutdated = false, maxAgeMinutes = 15, limit = null } = req.body;

    console.log('🔄 Admin triggered score recalculation:', {
      onlyOutdated,
      maxAgeMinutes,
      limit
    });

    const stats = await RecommendationService.recalculateAllScores({
      batchSize: 100,
      onlyOutdated: onlyOutdated === true,
      maxAgeMinutes: parseInt(maxAgeMinutes) || 15,
      limit: limit ? parseInt(limit) : null
    });

    res.json({
      success: true,
      message: 'Score recalculation completed',
      stats
    });
  } catch (error) {
    console.error('❌ Error in admin score recalculation:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to recalculate scores',
      message: error.message
    });
  }
});

export default router;