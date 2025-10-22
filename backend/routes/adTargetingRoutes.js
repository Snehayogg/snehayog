import express from 'express';
import AdTargetingService from '../services/adTargetingService.js';

const router = express.Router();

/**
 * **GET TARGETED ADS FOR VIDEO**
 * Returns ads that match the video's category and interests
 */
router.post('/targeted', async (req, res) => {
  try {
    const {
      categories = [],
      interests = [],
      limit = 3,
      targetingType = 'both', // 'category', 'interest', 'both'
      adType = 'banner',
      useFallback = true
    } = req.body;

    console.log('🎯 Getting targeted ads:', {
      categories,
      interests,
      limit,
      targetingType,
      adType
    });

    let ads = [];

    switch (targetingType) {
      case 'category':
        ads = await AdTargetingService.getTargetedAdsByCategory(categories, {
          limit,
          adType
        });
        break;
      
      case 'interest':
        ads = await AdTargetingService.getTargetedAdsByInterests(interests, {
          limit,
          adType
        });
        break;
      
      case 'both':
      default:
        ads = await AdTargetingService.getTargetedAds({
          categories,
          interests,
          limit,
          adType
        });
        break;
    }

    // Use fallback if no targeted ads found
    if (ads.length === 0 && useFallback) {
      console.log('🔄 No targeted ads found, using fallback system');
      ads = await AdTargetingService.getFallbackAds({ limit, adType });
    }

    res.json({
      success: true,
      ads,
      targetingType,
      totalAds: ads.length,
      isFallback: ads.length > 0 && targetingType !== 'fallback'
    });

  } catch (error) {
    console.error('❌ Error getting targeted ads:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get targeted ads',
      message: error.message
    });
  }
});

/**
 * **GET TARGETED ADS FOR VIDEO**
 * Returns ads that match a specific video
 */
router.post('/targeted-for-video', async (req, res) => {
  try {
    const {
      videoData,
      limit = 3,
      useFallback = true,
      adType = 'banner'
    } = req.body;

    if (!videoData) {
      return res.status(400).json({
        success: false,
        error: 'Video data is required'
      });
    }

    console.log('🎯 Getting targeted ads for video:', videoData.id);

    const ads = await AdTargetingService.getTargetedAdsForVideo(videoData, {
      limit,
      useFallback,
      adType
    });

    // Get targeting insights
    const insights = AdTargetingService.getTargetingInsights(ads, videoData);

    res.json({
      success: true,
      ads,
      insights,
      totalAds: ads.length,
      isFallback: insights.fallbackAds > 0
    });

  } catch (error) {
    console.error('❌ Error getting targeted ads for video:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get targeted ads for video',
      message: error.message
    });
  }
});

/**
 * **GET FALLBACK ADS**
 * Returns any available ads when no targeted ads are found
 */
router.get('/fallback', async (req, res) => {
  try {
    const {
      limit = 5,
      adType = 'banner'
    } = req.query;

    console.log('🔄 Getting fallback ads:', { limit, adType });

    const ads = await AdTargetingService.getFallbackAds({
      limit: parseInt(limit),
      adType
    });

    res.json({
      success: true,
      ads,
      totalAds: ads.length,
      isFallback: true
    });

  } catch (error) {
    console.error('❌ Error getting fallback ads:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get fallback ads',
      message: error.message
    });
  }
});

/**
 * **GET TARGETING INSIGHTS**
 * Returns insights about ad-video matching
 */
router.post('/insights', async (req, res) => {
  try {
    const {
      ads,
      videoData
    } = req.body;

    if (!ads || !videoData) {
      return res.status(400).json({
        success: false,
        error: 'Ads and video data are required'
      });
    }

    const insights = AdTargetingService.getTargetingInsights(ads, videoData);

    res.json({
      success: true,
      insights
    });

  } catch (error) {
    console.error('❌ Error getting targeting insights:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get targeting insights',
      message: error.message
    });
  }
});

/**
 * **GET TARGETING CATEGORIES**
 * Returns available targeting categories
 */
router.get('/categories', (req, res) => {
  try {
    const categories = Object.keys(AdTargetingService.CATEGORY_MAPPING);
    
    res.json({
      success: true,
      categories,
      categoryMapping: AdTargetingService.CATEGORY_MAPPING
    });

  } catch (error) {
    console.error('❌ Error getting targeting categories:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get targeting categories',
      message: error.message
    });
  }
});

/**
 * **GET TARGETING INTERESTS**
 * Returns available targeting interests
 */
router.get('/interests', (req, res) => {
  try {
    const interests = Object.keys(AdTargetingService.INTEREST_KEYWORDS);
    
    res.json({
      success: true,
      interests,
      interestKeywords: AdTargetingService.INTEREST_KEYWORDS
    });

  } catch (error) {
    console.error('❌ Error getting targeting interests:', error);
    res.status(500).json({
      success: false,
      error: 'Failed to get targeting interests',
      message: error.message
    });
  }
});

export default router;
