import express from 'express';
import mongoose from 'mongoose';
import AdCreative from '../../models/AdCreative.js';
import AdImpression from '../../models/AdImpression.js';
import User from '../../models/User.js';

const router = express.Router();
const DAILY_VIEW_FREQUENCY_CAP = 3;

// **FIXED: Helper function to normalize userId (Google ID to MongoDB ObjectId)**
async function normalizeUserId(userId) {
  if (!userId) return null;
  
  // If it's already a valid MongoDB ObjectId, return it as ObjectId
  if (mongoose.isValidObjectId(userId)) {
    return new mongoose.Types.ObjectId(userId);
  }
  
  // Otherwise, try to find user by Google ID and return MongoDB ObjectId
  try {
    const user = await User.findOne({ googleId: userId });
    if (user) {
      return user._id; // Return ObjectId directly
    }
  } catch (error) {
    console.error('⚠️ Error looking up user by Google ID:', error);
  }
  
  // If user not found, return null (will be stored as anonymous)
  return null;
}

// POST /ads/impressions/banner - Track banner ad impression
router.post('/impressions/banner', async (req, res) => {
  try {
    const { videoId, adId, userId } = req.body;
    // **FIXED: Normalize userId (Google ID to MongoDB ObjectId)**
    const normalizedUserId = await normalizeUserId(userId);
    if (userId && !normalizedUserId) {
      console.warn(
        '⚠️ User not found for Google ID, storing as anonymous:',
        userId
      );
    }

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
        userId: normalizedUserId,
        timestamp: { $gte: oneHourAgo }
      });

      if (!existingImpression) {
        // Create new impression record
        await AdImpression.create({
          videoId: videoId,
          adId: adId,
          userId: normalizedUserId,
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
    // **FIXED: Normalize userId (Google ID to MongoDB ObjectId)**
    const normalizedUserId = await normalizeUserId(userId);
    if (userId && !normalizedUserId) {
      console.warn(
        '⚠️ User not found for Google ID, storing as anonymous:',
        userId
      );
    }

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
        userId: normalizedUserId,
        timestamp: { $gte: oneHourAgo }
      });

      if (!existingImpression) {
        // Create new impression record
        await AdImpression.create({
          videoId: videoId,
          adId: adId,
          userId: normalizedUserId,
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
    // **FIXED: Normalize userId (Google ID to MongoDB ObjectId)**
    const normalizedUserId = await normalizeUserId(userId);
    if (userId && !normalizedUserId) {
      console.warn(
        '⚠️ User not found for Google ID, storing as anonymous:',
        userId
      );
    }

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

    let dailyViewCount = 0;
    if (normalizedUserId) {
      const startOfDay = new Date();
      startOfDay.setHours(0, 0, 0, 0);
      dailyViewCount = await AdImpression.countDocuments({
        videoId: videoId,
        adId: adId,
        userId: normalizedUserId,
        adType: 'banner',
        isViewed: true,
        timestamp: { $gte: startOfDay }
      });

      if (dailyViewCount >= DAILY_VIEW_FREQUENCY_CAP) {
        return res.status(200).json({
          success: false,
          message: 'Daily ad view cap reached for this user',
          dailyViews: dailyViewCount,
          frequencyCap: DAILY_VIEW_FREQUENCY_CAP
        });
      }
    }

    // Find existing impression record and mark it as viewed
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
    
    const impression = await AdImpression.findOne({
      videoId: videoId,
      adId: adId,
      userId: normalizedUserId,
      timestamp: { $gte: oneHourAgo },
      isViewed: false // Only update if not already viewed
    });

    if (impression) {
      // Update existing impression to mark as viewed
      impression.isViewed = true;
      impression.viewDuration = viewDuration;
       impression.viewCount = Math.min(
        (impression.viewCount || 0) + 1,
        DAILY_VIEW_FREQUENCY_CAP
      );
      impression.frequencyCap = impression.frequencyCap || DAILY_VIEW_FREQUENCY_CAP;
      await impression.save();
      console.log(`✅ Banner ad VIEW tracked: Video ${videoId}, Ad ${adId}, Duration: ${viewDuration}s`);
    } else {
      // Create new viewed impression record
      await AdImpression.create({
        videoId: videoId,
        adId: adId,
        userId: normalizedUserId,
        adType: 'banner',
        impressionType: 'view',
        isViewed: true,
        viewDuration: viewDuration,
        viewCount: 1,
        frequencyCap: DAILY_VIEW_FREQUENCY_CAP,
        timestamp: new Date()
      });
      console.log(`✅ New banner ad VIEW created: Video ${videoId}, Ad ${adId}, Duration: ${viewDuration}s`);
    }

    res.status(200).json({ 
      success: true,
      message: 'Banner ad view tracked successfully',
      viewDuration: viewDuration,
      dailyViews: normalizedUserId ? dailyViewCount + 1 : undefined,
      frequencyCap: normalizedUserId ? DAILY_VIEW_FREQUENCY_CAP : undefined
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
    // **FIXED: Normalize userId (Google ID to MongoDB ObjectId)**
    const normalizedUserId = await normalizeUserId(userId);
    if (userId && !normalizedUserId) {
      console.warn(
        '⚠️ User not found for Google ID, storing as anonymous:',
        userId
      );
    }

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

    let dailyViewCount = 0;
    if (normalizedUserId) {
      const startOfDay = new Date();
      startOfDay.setHours(0, 0, 0, 0);
      dailyViewCount = await AdImpression.countDocuments({
        videoId: videoId,
        adId: adId,
        userId: normalizedUserId,
        adType: 'carousel',
        isViewed: true,
        timestamp: { $gte: startOfDay }
      });

      if (dailyViewCount >= DAILY_VIEW_FREQUENCY_CAP) {
        return res.status(200).json({
          success: false,
          message: 'Daily ad view cap reached for this user',
          dailyViews: dailyViewCount,
          frequencyCap: DAILY_VIEW_FREQUENCY_CAP
        });
      }
    }

    // Find existing impression record and mark it as viewed
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000);
    
    const impression = await AdImpression.findOne({
      videoId: videoId,
      adId: adId,
      userId: normalizedUserId,
      timestamp: { $gte: oneHourAgo },
      isViewed: false
    });

    if (impression) {
      impression.isViewed = true;
      impression.viewDuration = viewDuration;
      impression.viewCount = Math.min(
        (impression.viewCount || 0) + 1,
        DAILY_VIEW_FREQUENCY_CAP
      );
      impression.frequencyCap = impression.frequencyCap || DAILY_VIEW_FREQUENCY_CAP;
      await impression.save();
      console.log(`✅ Carousel ad VIEW tracked: Video ${videoId}, Ad ${adId}, Duration: ${viewDuration}s`);
    } else {
      await AdImpression.create({
        videoId: videoId,
        adId: adId,
        userId: normalizedUserId,
        adType: 'carousel',
        impressionType: 'scroll_view',
        isViewed: true,
        viewDuration: viewDuration,
        viewCount: 1,
        frequencyCap: DAILY_VIEW_FREQUENCY_CAP,
        timestamp: new Date()
      });
      console.log(`✅ New carousel ad VIEW created: Video ${videoId}, Ad ${adId}, Duration: ${viewDuration}s`);
    }

    res.status(200).json({ 
      success: true,
      message: 'Carousel ad view tracked successfully',
      viewDuration: viewDuration,
      dailyViews: normalizedUserId ? dailyViewCount + 1 : undefined,
      frequencyCap: normalizedUserId ? DAILY_VIEW_FREQUENCY_CAP : undefined
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
    const { month, year } = req.query; // Optional month/year filtering

    console.log(`👁️ Getting banner ad VIEWS (for revenue) for video: ${videoId}`);

    // Build query with optional month filtering
    const query = {
      videoId: videoId,
      adType: 'banner',
      isViewed: true
    };

    // **NEW: Add month filtering if month and year provided**
    if (month && year) {
      const monthNum = parseInt(month);
      const yearNum = parseInt(year);
      const startDate = new Date(yearNum, monthNum, 1);
      const endDate = new Date(yearNum, monthNum + 1, 1);
      query.timestamp = {
        $gte: startDate,
        $lt: endDate
      };
      console.log(`📅 Filtering banner views for month ${month}/${year}`);
    }

    // **FIXED: Count only VIEWS (isViewed = true), not impressions**
    const viewCount = await AdImpression.countDocuments(query);

    console.log(`✅ Banner VIEWS for video ${videoId}: ${viewCount}${month && year ? ` (Month: ${month}/${year})` : ' (All-time)'}`);

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
    const { month, year } = req.query; // Optional month/year filtering

    console.log(`👁️ Getting carousel ad VIEWS (for revenue) for video: ${videoId}`);

    // Build query with optional month filtering
    const query = {
      videoId: videoId,
      adType: 'carousel',
      isViewed: true
    };

    // **NEW: Add month filtering if month and year provided**
    if (month && year) {
      const monthNum = parseInt(month);
      const yearNum = parseInt(year);
      const startDate = new Date(yearNum, monthNum, 1);
      const endDate = new Date(yearNum, monthNum + 1, 1);
      query.timestamp = {
        $gte: startDate,
        $lt: endDate
      };
      console.log(`📅 Filtering carousel views for month ${month}/${year}`);
    }

    // **FIXED: Count only VIEWS (isViewed = true), not impressions**
    const viewCount = await AdImpression.countDocuments(query);

    console.log(`✅ Carousel VIEWS for video ${videoId}: ${viewCount}${month && year ? ` (Month: ${month}/${year})` : ' (All-time)'}`);

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

