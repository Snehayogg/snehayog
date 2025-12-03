import express from 'express';
import Video from '../models/Video.js';
import User from '../models/User.js';

const router = express.Router();

// **HELPER: Escape special regex characters to prevent errors**
function escapeRegex(str) {
  return str.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

// GET /api/search/videos?q=...&limit=20
router.get('/videos', async (req, res) => {
  try {
    const q = (req.query.q || '').toString().trim();
    const limit = Math.min(parseInt(req.query.limit || '20', 10), 50);

    if (!q) {
      return res.json({ videos: [] });
    }

    // **FIX: Escape special regex characters for safe searching**
    const escapedQuery = escapeRegex(q);
    // eslint-disable-next-line no-console
    console.log(`🔍 searchRoutes: Searching videos with query="${q}" (escaped="${escapedQuery}")`);

    const videos = await Video.find({
      videoName: { $regex: escapedQuery, $options: 'i' },
    })
      .sort({ uploadedAt: -1 })
      .limit(limit)
      .lean();

    // eslint-disable-next-line no-console
    console.log(`✅ searchRoutes: Found ${videos.length} videos for query="${q}"`);

    return res.json({ videos });
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('❌ searchRoutes: Error searching videos', err);
    return res.status(500).json({ error: 'Failed to search videos' });
  }
});

// GET /api/search/creators?q=...&limit=20
router.get('/creators', async (req, res) => {
  try {
    const q = (req.query.q || '').toString().trim();
    const limit = Math.min(parseInt(req.query.limit || '20', 10), 50);

    if (!q) {
      return res.json({ creators: [] });
    }

    // **FIX: Escape special regex characters for safe searching**
    const escapedQuery = escapeRegex(q);
    // eslint-disable-next-line no-console
    console.log(`🔍 searchRoutes: Searching creators with query="${q}" (escaped="${escapedQuery}")`);

    const creators = await User.find({
      name: { $regex: escapedQuery, $options: 'i' },
    })
      .select('googleId name email profilePic followers createdAt')
      .sort({ 'followers.length': -1 })
      .limit(limit)
      .lean();

    // Normalize follower count field for frontend convenience
    const normalized = creators.map((u) => ({
      ...u,
      followersCount: Array.isArray(u.followers) ? u.followers.length : 0,
    }));

    // eslint-disable-next-line no-console
    console.log(`✅ searchRoutes: Found ${normalized.length} creators for query="${q}"`);

    return res.json({ creators: normalized });
  } catch (err) {
    // eslint-disable-next-line no-console
    console.error('❌ searchRoutes: Error searching creators', err);
    return res.status(500).json({ error: 'Failed to search creators' });
  }
});

export default router;


