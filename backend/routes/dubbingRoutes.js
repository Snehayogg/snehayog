import express from 'express';
import queueService from '../services/queueService.js';
import Video from '../models/Video.js';

const router = express.Router();

// Route to request a dub
router.post('/request', async (req, res) => {
  try {
    // In production, use token verification middleware
    const { videoId, targetLanguage } = req.body;
    
    if (!videoId || !targetLanguage) {
      return res.status(400).json({ error: 'videoId and targetLanguage are required' });
    }

    const video = await Video.findById(videoId);
    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    // Check if dub already exists
    if (video.dubbedUrls && video.dubbedUrls.has(targetLanguage)) {
      return res.status(200).json({ 
        message: 'Dub already exists', 
        url: video.dubbedUrls.get(targetLanguage) 
      });
    }

    // Queue the job
    await queueService.addDubbingJob({ videoId, targetLanguage });

    return res.status(202).json({ message: 'Dubbing request queued successfully' });
  } catch (error) {
    console.error('❌ Error requesting dub:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// Webhook endpoint to receive completion status from Python Worker
router.post('/webhook', async (req, res) => {
  try {
    const { videoId, targetLanguage, status, url, error, webhookSecret } = req.body;

    // Optional: Validate webhook secret
    const expectedSecret = process.env.DUBBING_WEBHOOK_SECRET || 'secret';
    if (webhookSecret !== expectedSecret) {
      return res.status(401).json({ error: 'Unauthorized webhook request' });
    }

    if (status === 'completed' && url) {
      console.log(`🎯 Webhook received SUCCESS for video ${videoId} (${targetLanguage})!`);
      
      const updateQuery = {};
      updateQuery[`dubbedUrls.${targetLanguage}`] = url;
      
      await Video.findByIdAndUpdate(videoId, { $set: updateQuery });
      
      return res.status(200).json({ message: 'Database updated successfully' });
    } else if (status === 'failed') {
      console.error(`❌ Webhook received ERROR for video ${videoId}:`, error);
      // In advanced implementation, save error to Video model
      return res.status(200).json({ message: 'Error logged' });
    }

    return res.status(400).json({ error: 'Invalid status format' });
  } catch (err) {
    console.error('❌ Webhook processing error:', err);
    res.status(500).json({ error: 'Internal server error' });
  }
});

export default router;
