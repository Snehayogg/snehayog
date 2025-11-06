import express from 'express';
import { asyncHandler } from '../../middleware/errorHandler.js';
import adService from '../../services/adService.js';

const router = express.Router();

// GET /ads/serve - Get active ads for serving with targeting
router.get('/serve', asyncHandler(async (req, res) => {
  const { userId, platform, location, videoCategory, videoTags, videoKeywords } = req.query;
  
  // Parse comma-separated tags and keywords
  const parsedTags = videoTags ? videoTags.split(',').map(t => t.trim()) : [];
  const parsedKeywords = videoKeywords ? videoKeywords.split(',').map(k => k.trim()) : [];
  
  console.log('🎯 Ad Serve Request:', {
    videoCategory,
    videoTags: parsedTags,
    videoKeywords: parsedKeywords
  });
  
  const activeAds = await adService.getActiveAds({ 
    userId, 
    platform, 
    location,
    videoCategory,
    videoTags: parsedTags,
    videoKeywords: parsedKeywords
  });
  
  res.json({
    ads: activeAds,
    count: activeAds.length,
    targeting: {
      videoCategory,
      videoTags: parsedTags,
      videoKeywords: parsedKeywords
    }
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
  try {
    const { adId } = req.params;
    const { userId } = req.query;
    
    console.log('📊 Analytics Route: Request for ad:', adId, 'userId:', userId);
    
    if (!adId) {
      return res.status(400).json({ error: 'Ad ID is required' });
    }
    
    const result = await adService.getAdAnalytics(adId, userId);
    
    if (result.error) {
      return res.status(404).json(result);
    }
    
    res.json(result);
  } catch (error) {
    console.error('❌ Analytics Route Error:', error);
    res.status(500).json({ 
      error: error.message || 'Failed to get ad analytics',
      details: error.message 
    });
  }
}));

export default router;
