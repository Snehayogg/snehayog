import RecommendationEngine from './RecommendationEngine.js';
import QualityScorer from './scorers/QualityScorer.js';
import TimeScorer from './scorers/TimeScorer.js';
import SemanticScorer from './scorers/SemanticScorer.js';
import PersonalizedScorer from './scorers/PersonalizedScorer.js';

/**
 * Standard Recommendation Pipeline
 * 
 * Configures the engine with default "codecs" (Scorers)
 */
const engine = new RecommendationEngine();

// Register Scorers with their respective weights
engine.use(new QualityScorer(1.0));    // Core quality metrics
engine.use(new TimeScorer(1.2));       // Recency & Freshness
engine.use(new SemanticScorer(0.8));   // AI Personalization
engine.use(new PersonalizedScorer(0.5)); // Language & Regional Match

/**
 * Add Diversity Post-Processor
 * Ensures no creator appears too often
 */
engine.addPostProcessor(async (videos, context) => {
  const { minCreatorSpacing = 3 } = context;
  if (!videos || videos.length === 0) return [];

  let remaining = [...videos];
  const ordered = [];
  const creatorLastPositions = new Map();
  let position = 0;

  while (remaining.length > 0) {
    const candidates = remaining.filter(video => {
      const creatorId = video.uploader?._id?.toString() || video.uploader?.toString() || 'unknown';
      const lastPos = creatorLastPositions.get(creatorId);
      return lastPos === undefined || (position - lastPos - 1) >= minCreatorSpacing;
    });

    const selected = candidates.length > 0 ? candidates[0] : remaining[0];
    ordered.push(selected);
    
    const creatorId = selected.uploader?._id?.toString() || selected.uploader?.toString() || 'unknown';
    creatorLastPositions.set(creatorId, position);
    
    remaining = remaining.filter(v => v._id !== selected._id);
    position++;
  }

  return ordered;
});

export default engine;
