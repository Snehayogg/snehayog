import mongoose from 'mongoose';

const gameSchema = new mongoose.Schema({
  title: {
    type: String,
    required: true,
    trim: true
  },
  description: {
    type: String,
    default: ''
  },
  thumbnailUrl: {
    type: String,
    required: true
  },
  gameUrl: { // URL to the index.html on CDN
    type: String,
    required: true
  },
  developer: {
    type: mongoose.Schema.Types.ObjectId,
    ref: 'User',
    required: true
  },
  // Technical Config
  orientation: {
    type: String,
    enum: ['portrait', 'landscape'],
    default: 'portrait'
  },
  entryPoint: {
    type: String,
    default: 'index.html'
  },
  version: {
    type: Number,
    default: 1
  },
  // Storefront Data
  status: {
    type: String,
    enum: ['pending', 'active', 'rejected'],
    default: 'active' // Auto-active for now (Zero Friction)
  },
  plays: {
    type: Number,
    default: 0
  },
  rating: {
    type: Number,
    default: 0
  },
  createdAt: {
    type: Date,
    default: Date.now
  }
});

const Game = mongoose.model('Game', gameSchema);
export default Game;
