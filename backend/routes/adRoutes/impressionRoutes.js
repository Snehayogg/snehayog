import express from 'express';
import AdCreative from '../../models/AdCreative.js';
import AdImpression from '../../models/AdImpression.js';
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

    if (!videoId) {
      return res.status(400).json({ error: 'Video ID is required' });
    }

    // Find the creative and increment impression count (for global tracking)
    const creative = await AdCreative.findById(adId);
    if (!creative) {
      console.error('❌ Ad creative not found:', adId);
      return res.status(404).json({ error: 'Ad not found' });
    }

    // **FIXED: Track video-specific impression in AdImpression collection**
    try {
      // Prevent duplicate impressions from same user within 1 hour
      const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
      
      const existingImpression = await AdImpression.findOne({
        videoId: videoId,
        adId: adId,
        userId: userId || null,
        timestamp: { $gte: oneHourAgo }
      });

      if (!existingImpression) {
        // Create new impression record
        await AdImpression.create({
          videoId: videoId,
          adId: adId,
          userId: userId || null,
          adType: 'banner',
          impressionType: 'view',
          timestamp: new Date()
        });
        console.log(`✅ Video-specific banner impression tracked: Video ${videoId}, Ad ${adId}`);
      } else {
        console.log(`⚠️ Duplicate impression prevented: Video ${videoId}, Ad ${adId}`);
      }
    } catch (impressionError) {
      // Log error but don't fail the request
      console.error('⚠️ Error creating impression record:', impressionError);
    }

    // Increment global impressions count (for backward compatibility)
    creative.impressions = (creative.impressions || 0) + 1;
    await creative.save();

    console.log(`✅ Banner ad impression tracked. Ad: ${adId}, Global count: ${creative.impressions}`);

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

    if (!videoId) {
      return res.status(400).json({ error: 'Video ID is required' });
    }

    // Find the creative and increment impression count (for global tracking)
    const creative = await AdCreative.findById(adId);
    if (!creative) {
      console.error('❌ Ad creative not found:', adId);
      return res.status(404).json({ error: 'Ad not found' });
    }

    // **FIXED: Track video-specific impression in AdImpression collection**
    try {
      // Prevent duplicate impressions from same user within 1 hour
      const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
      
      const existingImpression = await AdImpression.findOne({
        videoId: videoId,
        adId: adId,
        userId: userId || null,
        timestamp: { $gte: oneHourAgo }
      });

      if (!existingImpression) {
        // Create new impression record
        await AdImpression.create({
          videoId: videoId,
          adId: adId,
          userId: userId || null,
          adType: 'carousel',
          impressionType: 'scroll_view',
          timestamp: new Date()
        });
        console.log(`✅ Video-specific carousel impression tracked: Video ${videoId}, Ad ${adId}`);
      } else {
        console.log(`⚠️ Duplicate impression prevented: Video ${videoId}, Ad ${adId}`);
      }
    } catch (impressionError) {
      // Log error but don't fail the request
      console.error('⚠️ Error creating impression record:', impressionError);
    }

    // Increment global impressions count (for backward compatibility)
    creative.impressions = (creative.impressions || 0) + 1;
    await creative.save();

    console.log(`✅ Carousel ad impression tracked. Ad: ${adId}, Global count: ${creative.impressions}`);

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

    console.log(`📊 Getting banner impressions for video: ${videoId}`);

    // **FIXED: Count impressions specific to this video**
    const count = await AdImpression.countDocuments({
      videoId: videoId,
      adType: 'banner'
    });

    console.log(`✅ Banner impressions for video ${videoId}: ${count}`);

    res.status(200).json({ count: count });
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

    console.log(`📊 Getting carousel impressions for video: ${videoId}`);

    // **FIXED: Count impressions specific to this video**
    const count = await AdImpression.countDocuments({
      videoId: videoId,
      adType: 'carousel'
    });

    console.log(`✅ Carousel impressions for video ${videoId}: ${count}`);

    res.status(200).json({ count: count });
  } catch (error) {
    console.error('❌ Error getting carousel impressions:', error);
    res.status(500).json({ 
      error: 'Failed to get carousel impressions',
      message: error.message 
    });
  }
});

// **NEW: POST /ads/impressions/banner/view - Track banner ad view (minimum 2-3 seconds)**
router.post('/impressions/banner/view', async (req, res) => {
  try {
    const { videoId, adId, userId, viewDuration } = req.body;

    console.log('👁️ Tracking banner ad VIEW (minimum duration):');
    console.log('   Video ID:', videoId);
    console.log('   Ad ID:', adId);
    console.log('   User ID:', userId);
    console.log('   View Duration:', viewDuration);

    if (!adId || !videoId) {
      return res.status(400).json({ error: 'Ad ID and Video ID are required' });
    }

    // Minimum view duration: 2 seconds
    const minViewDuration = 2.0;
    if (!viewDuration || viewDuration < minViewDuration) {
      return res.status(400).json({ 
        error: `View duration must be at least ${minViewDuration} seconds`,
        viewDuration: viewDuration 
      });
    }

    // Find existing impression record and mark it as viewed
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
    
    const impression = await AdImpression.findOne({
      videoId: videoId,
      adId: adId,
      userId: userId || null,
      timestamp: { $gte: oneHourAgo },
      isViewed: false // Only update if not already viewed
    });

    if (impression) {
      // Update existing impression to mark as viewed
      impression.isViewed = true;
      impression.viewDuration = viewDuration;
      await impression.save();
      console.log(`✅ Banner ad VIEW tracked: Video ${videoId}, Ad ${adId}, Duration: ${viewDuration}s`);
    } else {
      // Create new viewed impression record
      await AdImpression.create({
        videoId: videoId,
        adId: adId,
        userId: userId || null,
        adType: 'banner',
        impressionType: 'view',
        isViewed: true,
        viewDuration: viewDuration,
        timestamp: new Date()
      });
      console.log(`✅ New banner ad VIEW created: Video ${videoId}, Ad ${adId}, Duration: ${viewDuration}s`);
    }

    res.status(200).json({ 
      success: true,
      message: 'Banner ad view tracked successfully',
      viewDuration: viewDuration
    });
  } catch (error) {
    console.error('❌ Error tracking banner ad view:', error);
    res.status(500).json({ 
      error: 'Failed to track banner ad view',
      message: error.message 
    });
  }
});

// **NEW: POST /ads/impressions/carousel/view - Track carousel ad view (minimum 2-3 seconds)**
router.post('/impressions/carousel/view', async (req, res) => {
  try {
    const { videoId, adId, userId, viewDuration } = req.body;

    console.log('👁️ Tracking carousel ad VIEW (minimum duration):');
    console.log('   Video ID:', videoId);
    console.log('   Ad ID:', adId);
    console.log('   User ID:', userId);
    console.log('   View Duration:', viewDuration);

    if (!adId || !videoId) {
      return res.status(400).json({ error: 'Ad ID and Video ID are required' });
    }

    // Minimum view duration: 2 seconds
    const minViewDuration = 2.0;
    if (!viewDuration || viewDuration < minViewDuration) {
      return res.status(400).json({ 
        error: `View duration must be at least ${minViewDuration} seconds`,
        viewDuration: viewDuration 
      });
    }

    // Find existing impression record and mark it as viewed
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
    
    const impression = await AdImpression.findOne({
      videoId: videoId,
      adId: adId,
      userId: userId || null,
      timestamp: { $gte: oneHourAgo },
      isViewed: false
    });

    if (impression) {
      impression.isViewed = true;
      impression.viewDuration = viewDuration;
      await impression.save();
      console.log(`✅ Carousel ad VIEW tracked: Video ${videoId}, Ad ${adId}, Duration: ${viewDuration}s`);
    } else {
      await AdImpression.create({
        videoId: videoId,
        adId: adId,
        userId: userId || null,
        adType: 'carousel',
        impressionType: 'scroll_view',
        isViewed: true,
        viewDuration: viewDuration,
        timestamp: new Date()
      });
      console.log(`✅ New carousel ad VIEW created: Video ${videoId}, Ad ${adId}, Duration: ${viewDuration}s`);
    }

    res.status(200).json({ 
      success: true,
      message: 'Carousel ad view tracked successfully',
      viewDuration: viewDuration
    });
  } catch (error) {
    console.error('❌ Error tracking carousel ad view:', error);
    res.status(500).json({ 
      error: 'Failed to track carousel ad view',
      message: error.message 
    });
  }
});

// **NEW: GET /ads/views/video/:videoId/banner - Get banner ad VIEWS (not impressions) for revenue**
router.get('/views/video/:videoId/banner', async (req, res) => {
  try {
    const { videoId } = req.params;

    console.log(`👁️ Getting banner ad VIEWS (for revenue) for video: ${videoId}`);

    // **FIXED: Count only VIEWS (isViewed = true), not impressions**
    const viewCount = await AdImpression.countDocuments({
      videoId: videoId,
      adType: 'banner',
      isViewed: true
    });

    console.log(`✅ Banner VIEWS for video ${videoId}: ${viewCount}`);

    res.status(200).json({ count: viewCount });
  } catch (error) {
    console.error('❌ Error getting banner ad views:', error);
    res.status(500).json({ 
      error: 'Failed to get banner ad views',
      message: error.message 
    });
  }
});

// **NEW: GET /ads/views/video/:videoId/carousel - Get carousel ad VIEWS (not impressions) for revenue**
router.get('/views/video/:videoId/carousel', async (req, res) => {
  try {
    const { videoId } = req.params;

    console.log(`👁️ Getting carousel ad VIEWS (for revenue) for video: ${videoId}`);

    // **FIXED: Count only VIEWS (isViewed = true), not impressions**
    const viewCount = await AdImpression.countDocuments({
      videoId: videoId,
      adType: 'carousel',
      isViewed: true
    });

    console.log(`✅ Carousel VIEWS for video ${videoId}: ${viewCount}`);

    res.status(200).json({ count: viewCount });
  } catch (error) {
    console.error('❌ Error getting carousel ad views:', error);
    res.status(500).json({ 
      error: 'Failed to get carousel ad views',
      message: error.message 
    });
  }
});

export default router;

