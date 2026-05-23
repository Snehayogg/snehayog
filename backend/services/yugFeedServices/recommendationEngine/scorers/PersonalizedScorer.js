import BaseScorer from '../BaseScorer.js';

/**
 * Personalized Scorer (The "Contextual" Codec)
 * 
 * Implements:
 * - Language Match
 * - Regional Relevance
 * - Creator Affinity (If following)
 */
class PersonalizedScorer extends BaseScorer {
  constructor(weight = 0.5) {
    super('PersonalizedScorer', weight);
  }

  async calculateScore(video, context) {
    const { user } = context;
    if (!user || user === 'anon') return 0;

    let boost = 0;

    // 1. Language Match
    if (video.language && user.preferredLanguages && user.preferredLanguages.length > 0) {
      const isPreferred = user.preferredLanguages.some(lang => 
        lang.toLowerCase() === video.language.toLowerCase()
      );
      if (isPreferred) boost += 0.3;
    }

    // 2. Region Match
    if (video.detectedRegion && user.location && user.location.state) {
      const videoRegion = video.detectedRegion.toLowerCase();
      const userState = (user.location.state || '').toLowerCase();
      
      if (videoRegion.includes(userState) || userState.includes(videoRegion)) {
        boost += 0.15;
      }
    }

    return boost;
  }
}

export default PersonalizedScorer;
