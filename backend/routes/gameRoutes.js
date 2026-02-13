import express from 'express';
import Game from '../models/Game.js';
import GameStorage from '../models/GameStorage.js';
import { verifyToken, passiveVerifyToken } from '../utils/verifytoken.js';

const router = express.Router();

// 1. GET /api/games - Game Feed (Discovery)
router.get('/', passiveVerifyToken, async (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const skip = (page - 1) * limit;

    const games = await Game.find({ status: 'active' })
      .sort({ plays: -1, rating: -1 }) // Popular first
      .skip(skip)
      .limit(limit)
      .populate('developer', 'name avatar') // Show developer info
      .lean();

    res.json({
      success: true,
      games,
      page,
      hasMore: games.length === limit
    });
  } catch (error) {
    console.error('❌ Error fetching games:', error);
    res.status(500).json({ error: 'Failed to fetch games' });
  }
});

// 2. GET /api/games/:id - Game Details
router.get('/:id', async (req, res) => {
  try {
    const game = await Game.findById(req.params.id).populate('developer', 'name');
    if (!game) return res.status(404).json({ error: 'Game not found' });
    
    // Increment plays (simple counter)
    // In production, use Redis to debounce this
    await Game.findByIdAndUpdate(req.params.id, { $inc: { plays: 1 } });

    res.json({ success: true, game });
  } catch (error) {
    res.status(500).json({ error: 'Error fetching game details' });
  }
});

// ==========================================
// ☁️ CLOUD SAVE: "OPEN BOX" STORAGE API
// ==========================================

// 3. GET /api/games/:id/storage - Load User's Save Data
router.get('/:id/storage', verifyToken, async (req, res) => {
  try {
    const userId = req.user.id;
    const gameId = req.params.id;

    const storage = await GameStorage.findOne({ userId, gameId }).lean();

    res.json({
      success: true,
      data: storage ? storage.data : null // Return null if no save exists
    });
  } catch (error) {
    console.error('❌ Error loading game data:', error);
    res.status(500).json({ error: 'Failed to load game data' });
  }
});

// 4. POST /api/games/:id/storage - Save User's Data (Upsert)
router.post('/:id/storage', verifyToken, async (req, res) => {
  try {
    const userId = req.user.id;
    const gameId = req.params.id;
    const { data, score } = req.body; // 'data' can be ANY JSON

    if (!data && score === undefined) {
      return res.status(400).json({ error: 'No data provided to save' });
    }

    // Upsert: Create if not exists, Update if exists
    const update = {};
    if (data) update.data = data;
    if (score !== undefined) update.score = score;
    update.updatedAt = new Date();

    const result = await GameStorage.findOneAndUpdate(
      { userId, gameId },
      update,
      { new: true, upsert: true, setDefaultsOnInsert: true }
    );

    res.json({
      success: true,
      message: 'Game data saved',
      // Don't echo back data to save bandwidth, just confirm success
    });

  } catch (error) {
    console.error('❌ Error saving game data:', error);
    res.status(500).json({ error: 'Failed to save game data' });
  }
});

// 5. GET /api/games/:id/leaderboard - Optional Leaderboard
router.get('/:id/leaderboard', async (req, res) => {
  try {
    const gameId = req.params.id;
    const limit = parseInt(req.query.limit) || 10;

    const leaderboard = await GameStorage.find({ gameId, score: { $gt: 0 } })
      .sort({ score: -1 }) // Highest score first
      .limit(limit)
      .populate('userId', 'name avatar') // Show user info
      .select('score userId')
      .lean();

    res.json({
      success: true,
      leaderboard
    });
  } catch (error) {
    res.status(500).json({ error: 'Failed to fetch leaderboard' });
  }
});

export default router;
