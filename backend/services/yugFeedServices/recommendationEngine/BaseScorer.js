/**
 * FFmpeg-style Recommendation Engine: Base Scorer Interface
 * 
 * Each "Plugin" (Scorer) must extend this class and implement
 * the calculateScore method.
 */
class BaseScorer {
  constructor(name, weight = 1.0) {
    this.name = name;
    this.weight = weight;
  }

  /**
   * Calculate score for a video
   * @param {Object} video - Video document
   * @param {Object} context - User context (history, interests, etc.)
   * @returns {Promise<Number>} Score between 0 and 1 (usually)
   */
  async calculateScore(video, context) {
    throw new Error(`Method 'calculateScore' must be implemented by ${this.constructor.name}`);
  }

  /**
   * Get boost multiplier for this scorer
   * @returns {Number}
   */
  getWeight() {
    return this.weight;
  }

  /**
   * Get human-readable name
   * @returns {String}
   */
  getName() {
    return this.name;
  }
}

export default BaseScorer;
