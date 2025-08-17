import express from 'express';
import { asyncHandler } from '../../middleware/errorHandler.js';
import adService from '../../services/adService.js';

const router = express.Router();

// GET /ads/serve - Get active ads for serving
router.get('/serve', asyncHandler(async (req, res) => {
  const { userId, platform, location } = req.query;
  
  const activeAds = await adService.getActiveAds({ userId, platform, location });
  
  res.json({
    ads: activeAds,
    count: activeAds.length
  });
}));

// POST /ads/track-click/:adId - Track ad clicks
router.post('/track-click/:adId', asyncHandler(async (req, res) => {
  const { adId } = req.params;
  const { userId, platform, location } = req.body;
  
  const result = await adService.trackAdClick(adId, { userId, platform, location });
  
  res.json(result);
}));

// GET /ads/analytics/:adId - Get ad analytics
router.get('/analytics/:adId', asyncHandler(async (req, res) => {
  const { adId } = req.params;
  const { userId } = req.query;
  
  const result = await adService.getAdAnalytics(adId, userId);
  
  res.json(result);
}));

export default router;
