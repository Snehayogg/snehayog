import express from 'express';
import AdCreative from '../../models/AdCreative.js';
import { verifyToken } from '../../utils/verifytoken.js';

const router = express.Router();

// POST /ads/impressions/banner - Track banner ad impression
router.post('/impressions/banner', async (req, res) => {
  try {
    const { videoId, adId, userId } = req.body;

    console.log('📊 Tracking banner ad impression:');
    console.log('   Video ID:', videoId);
    console.log('   Ad ID:', adId);
    console.log('   User ID:', userId);

    if (!adId) {
      return res.status(400).json({ error: 'Ad ID is required' });
    }

    // Find the creative and increment impression count
    const creative = await AdCreative.findById(adId);
    if (!creative) {
      console.error('❌ Ad creative not found:', adId);
      return res.status(404).json({ error: 'Ad not found' });
    }

    // Increment impressions
    creative.impressions = (creative.impressions || 0) + 1;
    await creative.save();

    console.log(`✅ Banner ad impression tracked. Ad: ${adId}, New count: ${creative.impressions}`);

    res.status(200).json({ 
      success: true,
      message: 'Banner ad impression tracked successfully',
      impressions: creative.impressions
    });
  } catch (error) {
    console.error('❌ Error tracking banner ad impression:', error);
    res.status(500).json({ 
      error: 'Failed to track banner ad impression',
      message: error.message 
    });
  }
});

// POST /ads/impressions/carousel - Track carousel ad impression
router.post('/impressions/carousel', async (req, res) => {
  try {
    const { videoId, adId, userId, scrollPosition } = req.body;

    console.log('📊 Tracking carousel ad impression:');
    console.log('   Video ID:', videoId);
    console.log('   Ad ID:', adId);
    console.log('   User ID:', userId);
    console.log('   Scroll Position:', scrollPosition);

    if (!adId) {
      return res.status(400).json({ error: 'Ad ID is required' });
    }

    // Find the creative and increment impression count
    const creative = await AdCreative.findById(adId);
    if (!creative) {
      console.error('❌ Ad creative not found:', adId);
      return res.status(404).json({ error: 'Ad not found' });
    }

    // Increment impressions
    creative.impressions = (creative.impressions || 0) + 1;
    await creative.save();

    console.log(`✅ Carousel ad impression tracked. Ad: ${adId}, New count: ${creative.impressions}`);

    res.status(200).json({ 
      success: true,
      message: 'Carousel ad impression tracked successfully',
      impressions: creative.impressions
    });
  } catch (error) {
    console.error('❌ Error tracking carousel ad impression:', error);
    res.status(500).json({ 
      error: 'Failed to track carousel ad impression',
      message: error.message 
    });
  }
});

// GET /ads/impressions/video/:videoId/banner - Get banner impressions for a video
router.get('/impressions/video/:videoId/banner', async (req, res) => {
  try {
    const { videoId } = req.params;

    // Get total impressions for all banner ads shown on this video
    const ads = await AdCreative.find({ adType: 'banner', isActive: true });
    const totalImpressions = ads.reduce((sum, ad) => sum + (ad.impressions || 0), 0);

    res.status(200).json({ count: totalImpressions });
  } catch (error) {
    console.error('❌ Error getting banner impressions:', error);
    res.status(500).json({ 
      error: 'Failed to get banner impressions',
      message: error.message 
    });
  }
});

// GET /ads/impressions/video/:videoId/carousel - Get carousel impressions for a video
router.get('/impressions/video/:videoId/carousel', async (req, res) => {
  try {
    const { videoId } = req.params;

    // Get total impressions for all carousel ads shown on this video
    const ads = await AdCreative.find({ adType: 'carousel', isActive: true });
    const totalImpressions = ads.reduce((sum, ad) => sum + (ad.impressions || 0), 0);

    res.status(200).json({ count: totalImpressions });
  } catch (error) {
    console.error('❌ Error getting carousel impressions:', error);
    res.status(500).json({ 
      error: 'Failed to get carousel impressions',
      message: error.message 
    });
  }
});

export default router;

