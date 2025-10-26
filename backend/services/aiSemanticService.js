import { pipeline } from '@xenova/transformers';

/**
 * **AI SEMANTIC SERVICE**
 * Free open-source AI service for semantic ad-video matching
 * Uses @xenova/transformers (local, no API costs)
 */
class AISemanticService {
  constructor() {
    this.model = null;
    this.cache = new Map(); // Cache for embeddings to speed up
    this.initialized = false;
  }

  /**
   * Initialize AI model (lazy loading)
   * Model downloads automatically on first use (~200MB)
   * UPDATED: Now supports multilingual (Hindi + 100+ languages)
   */
  async initialize() {
    if (this.initialized && this.model) return;
    
    try {
      console.log('🤖 AISemanticService: Loading multilingual AI model...');
      this.model = await pipeline(
        'feature-extraction',
        'Xenova/paraphrase-multilingual-MiniLM-L12-v2' // Multilingual 384-dimensional model (Hindi + 100+ languages)
      );
      this.initialized = true;
      console.log('✅ AISemanticService: AI model loaded successfully');
    } catch (error) {
      console.error('❌ AISemanticService: Failed to load AI model:', error);
      this.model = null;
      this.initialized = false;
    }
  }

  /**
   * Get embedding for text (cached for performance)
   */
  async getEmbedding(text) {
    if (!this.model) {
      await this.initialize();
      if (!this.model) return null; // Return null if initialization failed
    }
    
    // Check cache first
    const cacheKey = text.toLowerCase().trim();
    if (this.cache.has(cacheKey)) {
      return this.cache.get(cacheKey);
    }
    
    try {
      // Get embedding from model
      const output = await this.model(text, { 
        pooling: 'mean', 
        normalize: true 
      });
      const embedding = Array.from(output.data);
      
      // Cache for 1 hour
      this.cache.set(cacheKey, embedding);
      setTimeout(() => this.cache.delete(cacheKey), 3600000);
      
      return embedding;
    } catch (error) {
      console.error('❌ Error getting embedding:', error);
      return null;
    }
  }

  /**
   * Calculate cosine similarity between two embeddings
   */
  cosineSimilarity(a, b) {
    if (!a || !b || a.length !== b.length) return 0;
    
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

  /**
   * Match ads semantically to video content
   * Returns top matching ads based on semantic similarity
   */
  async matchSemantically(videoContent, ads) {
    try {
      // Initialize model if not already done
      await this.initialize();
      
      if (!this.model) {
        console.log('⚠️ AISemanticService: Model not available, returning empty array');
        return [];
      }
      
      // Extract video text
      const videoText = `${videoContent.title || ''} ${videoContent.description || ''}`.trim();
      
      if (!videoText) {
        console.log('⚠️ AISemanticService: No video text found');
        return [];
      }
      
      // Get video embedding
      const videoEmbedding = await this.getEmbedding(videoText);
      if (!videoEmbedding) {
        console.log('⚠️ AISemanticService: Failed to get video embedding');
        return [];
      }
      
      // Score each ad
      const scoredAds = [];
      for (const ad of ads) {
        try {
          const adText = `${ad.title || ''} ${ad.description || ''}`.trim();
          if (!adText) continue;
          
          const adEmbedding = await this.getEmbedding(adText);
          if (!adEmbedding) continue;
          
          const score = this.cosineSimilarity(videoEmbedding, adEmbedding);
          scoredAds.push({ ad, score });
        } catch (error) {
          continue;
        }
      }
      
      // Sort by score and return top matches
      const topMatches = scoredAds
        .filter(item => item.score > 0.3) // Minimum similarity threshold (30%)
        .sort((a, b) => b.score - a.score)
        .slice(0, 3) // Top 3 matches
        .map(item => item.ad);
      
      return topMatches;
    } catch (error) {
      console.error('❌ AISemanticService: Error in semantic matching:', error);
      return [];
    }
  }

  /**
   * Clear cache (useful for testing or memory management)
   */
  clearCache() {
    this.cache.clear();
    console.log('🗑️ AISemanticService: Cache cleared');
  }
}

export default new AISemanticService();
