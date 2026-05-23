import BaseScorer from '../BaseScorer.js';

/**
 * Quality Scorer (The "Base Video Quality" Codec)
 * 
 * Implements:
 * - Watch Score (AUR + Raw Capped)
 * - Engagement Score (Wilson Score for Likes/Comments)
 * - Share Score
 */
class QualityScorer extends BaseScorer {
  constructor(weight = 1.0) {
    super('QualityScorer', weight);
  }

  async calculateScore(video, context) {
    const {
      totalWatchTime = 0,
      duration = 0,
      likes = 0,
      comments = [],
      shares = 0,
      views = 0,
      skipCount = 0
    } = video;

    const watchScore = this._calculateWatchScore(totalWatchTime, duration, views);
    const engagementScore = this._calculateEngagementScore(likes, comments.length, views);
    const shareScore = this._calculateShareScore(shares, views);
    const skipPenalty = this._calculateSkipPenalty(skipCount, views);

    // Weighted combination
    const baseScore = (0.6 * watchScore + 0.2 * engagementScore + 0.2 * shareScore) - skipPenalty;
    
    return Math.max(baseScore, 0);
  }

  _calculateWatchScore(totalWatchTime, videoDuration, totalViews) {
    if (!videoDuration || videoDuration <= 0 || !totalViews || totalViews <= 0) return 0;
    const avgWatchTime = totalWatchTime / totalViews;
    const completionScore = avgWatchTime / videoDuration;
    const rawWatchScore = Math.min(avgWatchTime, 15) / 15;
    return Math.min(Math.max(0.5 * completionScore + 0.5 * rawWatchScore, 0), 1);
  }

  _calculateEngagementScore(positive, totalComments, totalViews) {
    if (!totalViews || totalViews <= 0) return 0;
    
    const smoothPos = (positive + totalComments) + 0.5;
    const smoothTotal = totalViews + 5;
    const p = smoothPos / smoothTotal;
    const z = 1.96; 
    
    return (p + (z * z) / (2 * smoothTotal) - z * Math.sqrt((p * (1 - p) + (z * z) / (4 * smoothTotal)) / smoothTotal)) / (1 + (z * z) / smoothTotal);
  }

  _calculateShareScore(totalShares, totalViews) {
    if (!totalViews || totalViews <= 0) return 0;
    return Math.min((totalShares / totalViews) / 0.1, 1);
  }

  _calculateSkipPenalty(skipCount, views) {
    const skipRate = views > 0 ? (skipCount / views) : 0;
    return Math.max(0, skipRate * 2.0);
  }
}

export default QualityScorer;
