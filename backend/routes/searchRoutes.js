import express from 'express';
import MongoSearchProvider from '../services/searchServices/MongoSearchProvider.js';

const router = express.Router();

// **PLUG-AND-PLAY ARCHITECTURE (FFmpeg Style)**
// By default, we use MongoSearchProvider. But any other provider implementing
// ISearchProvider (e.g. ElasticSearchProvider, MockSearchProvider) can be swapped in.
let activeSearchProvider = new MongoSearchProvider();

/**
 * Configure the active search provider (Dynamic Swap / Codec injection).
 * Useful for tests or swapping search engines (e.g., Elasticsearch, Algolia).
 * @param {ISearchProvider} provider
 */
export function setSearchProvider(provider) {
  activeSearchProvider = provider;
  console.log(`🔌 Search Provider swapped to: ${provider.constructor.name}`);
}

/**
 * Get the currently active search provider.
 * @returns {ISearchProvider}
 */
export function getSearchProvider() {
  return activeSearchProvider;
}

// GET /api/search/videos?q=...&limit=20
router.get('/videos', async (req, res) => {
  try {
    const q = (req.query.q || '').toString().trim();
    const limit = Math.min(parseInt(req.query.limit || '20', 10), 50);

    if (!q) {
      return res.json({ videos: [] });
    }

    const videos = await activeSearchProvider.searchVideos(q, limit);
    return res.json({ videos });

  } catch (err) {
    console.error('❌ Router Search Error (videos):', err);
    return res.status(500).json({ videos: [], error: 'Search failed' });
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

    const creators = await activeSearchProvider.searchCreators(q, limit);
    return res.json({ creators });

  } catch (err) {
    console.error('❌ Router Search Error (creators):', err);
    return res.status(500).json({ creators: [], error: 'Search failed' });
  }
});

export default router;
