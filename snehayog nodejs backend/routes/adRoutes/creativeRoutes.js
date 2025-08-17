import express from 'express';
import { asyncHandler } from '../../middleware/errorHandler.js';
import { adUpload, cleanupTempFile } from '../../config/upload.js';
import AdCreative from '../../models/AdCreative.js';
import AdCampaign from '../../models/AdCampaign.js';
import cloudinary from '../../config/cloudinary.js';

const router = express.Router();

// POST /ads/campaigns/:id/creatives - Upload ad creative
router.post('/campaigns/:id/creatives', adUpload.single('creative'), asyncHandler(async (req, res) => {
  const campaignId = req.params.id;
  const {
    type,
    aspectRatio,
    durationSec,
    callToActionLabel,
    callToActionUrl
  } = req.body;

  // Validate campaign exists
  const campaign = await AdCampaign.findById(campaignId);
  if (!campaign) {
    cleanupTempFile(req.file?.path);
    return res.status(404).json({ error: 'Campaign not found' });
  }

  // Validate file upload
  if (!req.file) {
    return res.status(400).json({ error: 'No creative file uploaded' });
  }

  try {
    // Upload to Cloudinary
    const result = await cloudinary.uploader.upload(req.file.path, {
      resource_type: type === 'video' ? 'video' : 'image',
      folder: 'snehayog-ads',
      transformation: [
        { quality: 'auto:good' },
        { fetch_format: 'auto' }
      ]
    });

    // Create ad creative
    const creative = new AdCreative({
      campaignId,
      type,
      cloudinaryUrl: result.secure_url,
      thumbnail: type === 'video' ? result.thumbnail_url : result.secure_url,
      aspectRatio,
      durationSec: type === 'video' ? durationSec : undefined,
      callToAction: {
        label: callToActionLabel,
        url: callToActionUrl
      }
    });

    await creative.save();

    res.status(201).json({
      message: 'Ad creative uploaded successfully',
      creative
    });

  } catch (error) {
    console.error('Creative upload error:', error);
    throw error;
  } finally {
    // Clean up temp file
    cleanupTempFile(req.file?.path);
  }
}));

export default router;
