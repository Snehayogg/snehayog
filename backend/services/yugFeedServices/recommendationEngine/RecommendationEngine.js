/**
 * FFmpeg-style Recommendation Engine (The Orchestrator)
 * 
 * This engine acts like the "FFmpeg executable", taking "codecs" (Scorers)
 * and running them in a pipeline to produce the final recommendation feed.
 */
class RecommendationEngine {
  constructor() {
    this.scorers = [];
    this.postProcessors = [];
  }

  /**
   * Register a new scoring plugin
   * @param {BaseScorer} scorer 
   */
  use(scorer) {
    this.scorers.push(scorer);
    return this;
  }

  /**
   * Run the recommendation pipeline for a set of candidate videos
   * 
   * @param {Array} videos - Pool of candidate videos
   * @param {Object} context - User context, history, filters
   * @returns {Promise<Array>} Ranked and processed videos
   */
  async recommend(videos, context = {}) {
    if (!videos || videos.length === 0) return [];

    // 1. Scoring Phase (Parallel processing for each video)
    const scoredVideos = await Promise.all(videos.map(async (video) => {
      let finalScore = 0;
      const details = {};

      for (const scorer of this.scorers) {
        const score = await scorer.calculateScore(video, context);
        const weightedScore = score * scorer.getWeight();
        finalScore += weightedScore;
        details[scorer.getName()] = { raw: score, weighted: weightedScore };
      }

      return {
        ...video,
        finalScore: Math.max(finalScore, 0.01),
        scoreDetails: details
      };
    }));

    // 2. Sorting Phase
    let rankedVideos = scoredVideos.sort((a, b) => b.finalScore - a.finalScore);

    // 3. Post-Processing Phase (Filtering, Diversity, Blocking)
    for (const processor of this.postProcessors) {
      rankedVideos = await processor(rankedVideos, context);
    }

    return rankedVideos;
  }

  /**
   * Register a post-processing function (Diversity, Shuffling, etc.)
   * @param {Function} processor 
   */
  addPostProcessor(processor) {
    this.postProcessors.push(processor);
    return this;
  }

  /**
   * Weighted Shuffle (Algorithm: exponential/log-random weight selection)
   * 
   * @param {Array} videos - Candidates to shuffle
   * @param {number} count - Number of videos to return
   * @returns {Array} Shuffled subset of videos
   */
  _weightedShuffle(videos, count) {
    if (!videos || videos.length === 0) return [];
    
    // Create copy with randomized scores based on their original score
    const withRandomizedScores = videos.map(video => {
      const score = video.finalScore || 0.01;
      // Exponential distribution random value: -log(random) / score
      // A higher score will result in a smaller key on average, meaning it sorts to the front
      const key = -Math.log(Math.random()) / score;
      return { video, key };
    });
    
    // Sort ascending by key (which corresponds to highest score first, with random variance)
    withRandomizedScores.sort((a, b) => a.key - b.key);
    
    // Return the original video objects
    return withRandomizedScores.slice(0, count || videos.length).map(item => item.video);
  }
}

export default RecommendationEngine;
