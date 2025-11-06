import express from 'express';
import Report from '../models/Report.js';
// **FIX: Removed non-existent authMiddleware import**

const router = express.Router();

// Submit a report (auth optional; will attach userId if token present)
router.post('/', async (req, res) => {
  try {
    const { targetType, targetId, reason, details } = req.body || {};

    if (!targetType || !targetId || !reason) {
      return res.status(400).json({ success: false, error: 'Missing required fields' });
    }

    const report = new Report({
      targetType: String(targetType).toLowerCase(),
      targetId: String(targetId),
      reason: String(reason).toLowerCase(),
      details: details ? String(details) : undefined,
      userId: req.user?.id || req.user?.googleId || null,
      userAgent: req.get('User-Agent') || '',
      ipAddress: req.ip || req.connection?.remoteAddress || '',
    });

    await report.save();

    res.status(201).json({ success: true, message: 'Report submitted', reportId: report._id });
  } catch (error) {
    console.error('❌ Error submitting report:', error);
    res.status(500).json({ success: false, error: 'Failed to submit report' });
  }
});

// Optional: List reports for admin (basic, can be expanded later)
router.get('/', async (req, res) => {
  try {
    const { status, targetType, limit = 100 } = req.query;
    const query = {};
    if (status) query.status = status;
    if (targetType) query.targetType = String(targetType).toLowerCase();
    const items = await Report.find(query).sort({ createdAt: -1 }).limit(Math.min(parseInt(limit) || 100, 500));
    res.json({ success: true, count: items.length, reports: items });
  } catch (error) {
    console.error('❌ Error fetching reports:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch reports' });
  }
});

export default router;


