import mongoose from 'mongoose';

const gameStorageSchema = new mongoose.Schema({
  userId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  gameId: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'Game',
    required: true
  },
  // The 'Open Box' - Flexible Data Storage
  data: {
    type: mongoose.Schema.Types.Mixed,
    default: {}
  },
  // Optional: For Leaderboards
  score: {
    type: Number,
    default: 0,
    index: true // Indexed for fast leaderboard queries
  },
  updatedAt: {
    type: Date,
    default: Date.now
  }
});

// Compound index to ensure one save slot per user per game
gameStorageSchema.index({ userId: 1, gameId: 1 }, { unique: true });

const GameStorage = mongoose.model('GameStorage', gameStorageSchema);
export default GameStorage;
