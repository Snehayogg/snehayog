import express from 'express';
import Game from '../models/Game.js';
import User from '../models/User.js';
import GameStorage from '../models/GameStorage.js';
import { verifyToken, passiveVerifyToken } from '../utils/verifytoken.js';

const router = express.Router();

// 0. GET /api/games/developer - Get games for authenticated developer
router.get('/developer', verifyToken, async (req, res) => {
  try {
    const userId = req.user.id;
    
    // Find developer user object first
    const developer = await User.findOne({ googleId: userId });
    if (!developer) return res.status(404).json({ error: 'Developer not found' });

    const games = await Game.find({ 
      developer: developer._id,
      title: { $not: /test|verification/i } // Exclude test content
    })
      .sort({ createdAt: -1 })
      .lean();

    res.json({
      success: true,
      games
    });
  } catch (error) {
    console.error('❌ Error fetching developer games:', error);
    res.status(500).json({ error: 'Failed to fetch developer games' });
  }
});

// 1. GET /api/games - Game Feed (Discovery)
router.get('/', passiveVerifyToken, async (req, res) => {
  try {
    const page = parseInt(req.query.page) || 1;
    const limit = parseInt(req.query.limit) || 20;
    const skip = (page - 1) * limit;

    // Filter out test content at DB level
    const games = await Game.find({ 
      status: 'active',
      title: { $not: /test|verification/i } // Case-insensitive exclusion
    })
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

// 2.5 POST /api/games/:id/publish - Publish a pending game
router.post('/:id/publish', verifyToken, async (req, res) => {
  try {
    const gameId = req.params.id;
    const userId = req.user.id;

    // Find developer user object
    const developer = await User.findOne({ googleId: userId });
    if (!developer) return res.status(404).json({ error: 'Developer not found' });

    const game = await Game.findById(gameId);
    if (!game) return res.status(404).json({ error: 'Game not found' });

    // Verify ownership
    if (game.developer.toString() !== developer._id.toString()) {
      return res.status(403).json({ error: 'Access denied: You do not own this game' });
    }

    // Publish game
    game.status = 'active';
    await game.save();

    res.json({
      success: true,
      message: 'Game published successfully',
      game
    });
  } catch (error) {
    console.error('❌ Error publishing game:', error);
    res.status(500).json({ error: 'Failed to publish game' });
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

// 4.5 POST /api/games/:id/analytics - Update Game Analytics (Plays & Time Spent)
router.post('/:id/analytics', verifyToken, async (req, res) => {
  try {
    const gameId = req.params.id;
    const { timeSpent } = req.body; // timeSpent in seconds

    const update = { $inc: { plays: 1 } };
    if (timeSpent && typeof timeSpent === 'number') {
      update.$inc.totalTimeSpent = timeSpent;
    }

    const game = await Game.findByIdAndUpdate(
      gameId,
      update,
      { new: true }
    );

    if (!game) return res.status(404).json({ error: 'Game not found' });

    res.json({
      success: true,
      message: 'Analytics updated',
      plays: game.plays,
      totalTimeSpent: game.totalTimeSpent
    });
  } catch (error) {
    console.error('❌ Error updating game analytics:', error);
    res.status(500).json({ error: 'Failed to update analytics' });
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
