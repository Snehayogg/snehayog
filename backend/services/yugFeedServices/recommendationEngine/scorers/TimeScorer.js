import BaseScorer from '../BaseScorer.js';

/**
 * Time Scorer (The "Recency/Temporal" Codec)
 * 
 * Implements:
 * - Freshness Boost (First 120 hours)
 * - Recency Decay (Long-term)
 * - Exploration Boost (First 24 hours)
 */
class TimeScorer extends BaseScorer {
  constructor(weight = 1.0) {
    super('TimeScorer', weight);
  }

  async calculateScore(video, context) {
    const uploadedAt = video.uploadedAt || video.createdAt;
    if (!uploadedAt) return 0.5; // Default neutral boost

    const now = new Date();
    const uploadDate = new Date(uploadedAt);
    const ageInHours = (now - uploadDate) / (1000 * 60 * 60);
    const ageInDays = ageInHours / 24;

    const freshnessBoost = this._calculateFreshnessBoost(ageInHours);
    const explorationBoost = this._calculateExplorationBoost(ageInHours);
    const recencyMultiplier = this._calculateRecencyMultiplier(ageInDays);

    // Final temporal weight
    return (freshnessBoost + explorationBoost) * recencyMultiplier;
  }

  _calculateFreshnessBoost(ageInHours) {
    const WINDOW = 120;
    if (ageInHours < 0) return 3.0;
    if (ageInHours > WINDOW) return 0;
    return 3.0 * (1 - (ageInHours / WINDOW));
  }

  _calculateExplorationBoost(ageInHours) {
    if (ageInHours >= 0 && ageInHours < 24) {
      return 0.5 * (1 - (ageInHours / 24));
    }
    return 0;
  }

  _calculateRecencyMultiplier(ageInDays) {
    const multiplier = 0.1 + (0.9 / (1 + ageInDays * 0.1));
    return Math.max(multiplier, 0.1);
  }
}

export default TimeScorer;
