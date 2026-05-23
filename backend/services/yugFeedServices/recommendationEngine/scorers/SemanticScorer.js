import BaseScorer from '../BaseScorer.js';

/**
 * Semantic Scorer (The "Interest Match" Codec)
 * 
 * Implements:
 * - Cosine Similarity between User Interest Vector and Video Embedding
 */
class SemanticScorer extends BaseScorer {
  constructor(weight = 1.0) {
    super('SemanticScorer', weight);
  }

  async calculateScore(video, context) {
    const { userVector } = context;
    const { vectorEmbedding } = video;

    if (!userVector || !vectorEmbedding || userVector.length !== vectorEmbedding.length) {
      return 0;
    }

    return this._calculateCosineSimilarity(userVector, vectorEmbedding);
  }

  _calculateCosineSimilarity(a, b) {
    let dotProduct = 0;
    let normA = 0;
    let normB = 0;
    for (let i = 0; i < a.length; i++) {
        dotProduct += a[i] * b[i];
        normA += a[i] * a[i];
        normB += b[i] * b[i];
    }
    if (normA === 0 || normB === 0) return 0;
    return dotProduct / (Math.sqrt(normA) * Math.sqrt(normB));
  }
}

export default SemanticScorer;
