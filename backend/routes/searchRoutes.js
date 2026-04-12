import express from 'express';
import Video from '../models/Video.js';
import User from '../models/User.js';

const router = express.Router();

// GET /api/search/videos?q=...&limit=20
router.get('/videos', async (req, res) => {
  try {
    const q = (req.query.q || '').toString().trim();
    const limit = Math.min(parseInt(req.query.limit || '20', 10), 50);

    if (!q) {
      return res.json({ videos: [] });
    }

    console.log(`🔍 Atlas Compound Search: Querying videos for "${q}"`);

    // **NEW: COMPOUND SEARCH STRATEGY**
    // combines Exact Match (Weight 5), Fuzzy Match (Weight 2), and Tags (Weight 1)
    const videos = await Video.aggregate([
      {
        $search: {
          index: 'default',
          compound: {
            should: [
              // 1. Exact or Partial Match on Video Name (Highest Priority)
              // This acts like the old regex search but smarter
              {
                text: {
                  query: q,
                  path: 'videoName',
                  score: { boost: { value: 5 } }
                }
              },
              // 2. Fuzzy Match on Video Name (Typo Tolerance)
              {
                text: {
                  query: q,
                  path: 'videoName',
                  fuzzy: { maxEdits: 1, prefixLength: 1 },
                  score: { boost: { value: 2 } }
                }
              },
              // 3. Search in Tags
              {
                text: {
                  query: q,
                  path: 'tags',
                  score: { boost: { value: 1 } }
                }
              }
            ],
            // **OPTIONAL: Minimum should match. We keep it at 1 so any match counts.**
            minimumShouldMatch: 1
          }
        }
      },
      { $limit: limit },
      // Populate uploader
      {
        $lookup: {
          from: 'users',
          localField: 'uploader',
          foreignField: '_id',
          as: 'uploader'
        }
      },
      { $unwind: '$uploader' },
      // Project final fields for frontend
      {
        $project: {
          score: { $meta: 'searchScore' },
          videoName: 1,
          videoUrl: 1,
          thumbnailUrl: 1,
          uploader: { _id: 1, googleId: 1, name: 1, profilePic: 1 },
          videoType: 1,
          duration: 1,
          uploadedAt: 1,
          views: 1,
          likes: 1,
          category: 1,
          tags: 1,
          videoHash: 1,
          hlsPlaylistUrl: 1,
          hlsMasterPlaylistUrl: 1,
          seriesId: 1,
          episodeNumber: 1
        }
      }
    ]);

    const normalized = videos.map(v => ({
      ...v,
      id: v._id.toString()
    }));

    return res.json({ videos: normalized });
    
  } catch (err) {
    console.error('❌ Atlas Search Error (videos):', err);
    // Legacy Regex Fallback
    const fallback = await Video.find({
      videoName: { $regex: q, $options: 'i' }
    })
    .limit(limit)
    .populate('uploader', 'googleId name profilePic')
    .sort({ uploadedAt: -1 })
    .lean();
    
    return res.json({ videos: fallback });
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

    const creators = await User.aggregate([
      {
        $search: {
          index: 'default',
          compound: {
            should: [
              {
                text: {
                  query: q,
                  path: 'name',
                  score: { boost: { value: 3 } }
                }
              },
              {
                text: {
                  query: q,
                  path: 'name',
                  fuzzy: { maxEdits: 1 }
                }
              }
            ]
          }
        }
      },
      { $limit: limit },
      {
        $project: {
          score: { $meta: 'searchScore' },
          _id: 1,
          googleId: 1,
          name: 1,
          profilePic: 1,
          bio: 1,
          followers: 1,
          createdAt: 1
        }
      }
    ]);

    const normalized = creators.map((u) => ({
      ...u,
      id: u.googleId || u._id.toString(),
      _id: u._id,
      followersCount: Array.isArray(u.followers) ? u.followers.length : 0,
    }));

    return res.json({ creators: normalized });
    
  } catch (err) {
    console.error('❌ Atlas Search Error (creators):', err);
    const fallback = await User.find({
      name: { $regex: q, $options: 'i' }
    })
    .limit(limit)
    .lean();
    return res.json({ creators: fallback.map(u => ({...u, id: u.googleId || u._id.toString()})) });
  }
});

export default router;


