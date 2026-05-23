import { IAdTargeter } from '../IAdTargeter.js';
import aiSemanticService from '../../../yugFeedServices/aiSemanticService.js';

/**
 * **AISemanticTargeter**
 * Pluggable targeter that uses Gemini-powered embeddings or local MiniLM models 
 * to score semantic similarity between ad titles/descriptions and video metadata.
 */
export class AISemanticTargeter extends IAdTargeter {
  /**
   * Evaluate semantic similarity
   * @param {Object} ad Ad creative with populated campaignId
   * @param {Object} context Context details of the target video
   * @returns {Object} { scoreModifier: number, reason: string }
   */
  async evaluate(ad, context = {}) {
    try {
      const videoText = `${context.videoName || context.title || ''} ${context.description || ''}`.trim();
      const adText = `${ad.title || ''} ${ad.description || ''}`.trim();

      if (!videoText || !adText) {
        return { scoreModifier: 0, reason: 'missing_semantic_text' };
      }

      // Initialize the AI service if needed
      await aiSemanticService.initialize();

      // Retrieve embeddings for video content and ad copy
      const videoEmbedding = await aiSemanticService.getEmbedding(videoText);
      const adEmbedding = await aiSemanticService.getEmbedding(adText);

      if (!videoEmbedding || !adEmbedding) {
        return { scoreModifier: 0, reason: 'embedding_failed' };
      }

      // Calculate cosine similarity
      const similarity = aiSemanticService.cosineSimilarity(videoEmbedding, adEmbedding);

      // We apply the exact 0.15 threshold currently used in Vayu
      if (similarity > 0.15) {
        // Map 0.15 - 1.00 similarity to a powerful score modifier (e.g. up to +200)
        const scoreModifier = Math.round(similarity * 200);
        return {
          scoreModifier,
          reason: `ai_semantic_match:${similarity.toFixed(3)}`
        };
      }

      return { scoreModifier: 0, reason: `low_semantic_relevance:${similarity.toFixed(3)}` };
    } catch (err) {
      console.warn('⚠️ AISemanticTargeter evaluation failed, skipping:', err.message);
      return { scoreModifier: 0, reason: 'ai_error' };
    }
  }
}
