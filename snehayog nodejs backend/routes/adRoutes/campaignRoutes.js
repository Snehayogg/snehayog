import express from 'express';
import { asyncHandler } from '../../middleware/errorHandler.js';
import { validateCampaignData, validatePagination } from '../../middleware/validation.js';
import AdCampaign from '../../models/AdCampaign.js';
import AdCreative from '../../models/AdCreative.js';
import Invoice from '../../models/Invoice.js';

const router = express.Router();

// POST /ads/campaigns - Create draft campaign
router.post('/', validateCampaignData, asyncHandler(async (req, res) => {
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

  const campaign = new AdCampaign({
    name,
    advertiserUserId: req.user.id,
    objective,
    startDate: new Date(startDate),
    endDate: new Date(endDate),
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
}));

// GET /ads/campaigns - List campaigns with pagination
router.get('/', validatePagination, asyncHandler(async (req, res) => {
  const { me, status } = req.query;
  const { page, limit } = req.pagination;
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
    .limit(limit);

  const total = await AdCampaign.countDocuments(query);

  res.json({
    campaigns,
    pagination: {
      currentPage: page,
      totalPages: Math.ceil(total / limit),
      total,
      hasMore: (page * limit) < total
    }
  });
}));

// GET /ads/campaigns/:id - Get campaign details
router.get('/:id', asyncHandler(async (req, res) => {
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
}));

// POST /ads/campaigns/:id/submit - Submit for review
router.post('/:id/submit', asyncHandler(async (req, res) => {
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
}));

// POST /ads/campaigns/:id/activate - Activate campaign
router.post('/:id/activate', asyncHandler(async (req, res) => {
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
}));

export default router;
