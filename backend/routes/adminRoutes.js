import express from 'express';
import Feedback from '../models/Feedback.js';
import requireAdminDashboardKey from '../middleware/adminDashboardAuth.js';
import User from '../models/User.js';
import Video from '../models/Video.js';
import CreatorPayout from '../models/CreatorPayout.js';
import AdImpression from '../models/AdImpression.js';
import { AD_CONFIG } from '../constants/index.js';

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
            totalVideos: { $sum: 1 }
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
      const bankAccount = creator?.paymentDetails?.bankAccount || null;
      const paymentSummary = {
        preferredPaymentMethod: creator.preferredPaymentMethod || null,
        upiId,
        bank: bankAccount
          ? {
              accountNumber: bankAccount.accountNumber,
              ifscCode: bankAccount.ifscCode,
              bankName: bankAccount.bankName,
              accountHolderName: bankAccount.accountHolderName
            }
          : null
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
        lastPayoutAt: payouts.lastPayoutAt
      };
    });

    creatorSummaries.sort(
      (a, b) => (b.creatorRevenueINR || 0) - (a.creatorRevenueINR || 0)
    );

    res.json({
      success: true,
      count: creatorSummaries.length,
      creators: creatorSummaries
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
    // Get total videos count
    const totalVideos = await Video.countDocuments({});
    
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

export default router;