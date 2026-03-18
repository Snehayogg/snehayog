import express from 'express';
import dubbingService from '../services/dubbingService.js';
import Video from '../models/Video.js';

const router = express.Router();

/**
 * POST /api/dubbing/request
 * User requests on-demand dubbing for a video.
 * - Returns cached URL instantly if already dubbed
 * - Returns not_suitable instantly if duration guards fail
 * - Otherwise starts background dubbing, returns taskId for polling
 */
router.post('/request', async (req, res) => {
  try {
    const { videoId, targetLanguage = 'english' } = req.body;
    const userId = req.user?.id || req.body.userId;

    if (!videoId) {
      return res.status(400).json({ error: 'videoId is required' });
    }

    const video = await Video.findById(videoId).select('dubbedUrls duration');
    if (!video) {
      return res.status(404).json({ error: 'Video not found' });
    }

    // ── Instant cache hit ────────────────────────────────────────────
    const cachedUrl = video.dubbedUrls?.get
      ? video.dubbedUrls.get(targetLanguage)
      : video.dubbedUrls?.[targetLanguage];

    if (cachedUrl) {
      return res.status(200).json({
        status: 'completed',
        fromCache: true,
        dubbedUrl: cachedUrl,
        message: 'Dubbed version already available',
      });
    }

    // ── Duration guards (fast, no CPU needed) ───────────────────────
    const durationSec = video.duration || 0;
    if (durationSec > 0 && durationSec < 5) {
      return res.status(200).json({ status: 'not_suitable', reason: 'too_short' });
    }
    if (durationSec > 600) {
      return res.status(200).json({ status: 'not_suitable', reason: 'too_long' });
    }

    // ── Start background dubbing ─────────────────────────────────────
    const { taskId } = await dubbingService.startSmartDub({ userId, videoId });

    return res.status(202).json({
      status: 'queued',
      taskId,
      message: 'Dubbing started. Poll /api/dubbing/status/:taskId for progress.',
    });

  } catch (error) {
    console.error('❌ Dubbing request error:', error);
    res.status(500).json({ error: 'Internal server error', details: error.message });
  }
});

/**
 * GET /api/dubbing/status/:taskId
 * Poll for dubbing progress.
 */
router.get('/status/:taskId', async (req, res) => {
  try {
    const { taskId } = req.params;
    const task = await dubbingService.getTaskStatus(taskId);

    if (!task) {
      return res.status(404).json({ error: 'Task not found' });
    }

    return res.status(200).json({
      taskId,
      status: task.status,           // starting | downloading | checking_content | extracting_audio | transcribing | translating | synthesizing | muxing | uploading | completed | not_suitable | failed
      progress: task.progress,       // 0–100
      dubbedUrl: task.dubbedUrl || null,
      fromCache: task.fromCache || false,
      reason: task.reason || null,   // for not_suitable
      error: task.error || null,     // for failed
    });

  } catch (error) {
    console.error('❌ Status check error:', error);
    res.status(500).json({ error: 'Internal server error' });
  }
});

/**
 * POST /api/dubbing/webhook  (kept for legacy RunPod compat — no longer primary path)
 */
router.post('/webhook', async (req, res) => {
  const { videoId, targetLanguage, status, url, webhookSecret } = req.body;
  const expectedSecret = process.env.DUBBING_WEBHOOK_SECRET || 'secret';

  if (webhookSecret !== expectedSecret) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  if (status === 'completed' && url) {
    const updateQuery = { [`dubbedUrls.${targetLanguage}`]: url };
    await Video.findByIdAndUpdate(videoId, { $set: updateQuery });
    return res.status(200).json({ message: 'OK' });
  }

  return res.status(400).json({ error: 'Invalid status' });
});

export default router;
