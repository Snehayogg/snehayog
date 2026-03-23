/**
 * **AI SEMANTIC SERVICE**
 * Free open-source AI service for semantic ad-video matching
 * Uses @xenova/transformers (local, no API costs)
 * Falls back gracefully if transformers are not available
 */
class AISemanticService {
  constructor() {
    this.model = null;
    this.cache = new Map(); // Cache for embeddings to speed up
    this.initialized = false;
    this.transformersModule = null;
    this.pipeline = null;
    this.initializing = false; // **FIX: Prevent concurrent initialization**
    this.initPromise = null; // **FIX: Store init promise to reuse**
  }

  async _loadTransformers() {
    if (this.transformersModule) {
      return true;
    }
    
    if (this.transformersModule === false) {
      // Already tried and failed, don't retry
      return false;
    }
    
    try {
      // **MEMORY EFFICIENT: Use dynamic import to load transformers only when needed**
      // This prevents loading the heavy library unless AI matching is required
      const transformers = await import('@xenova/transformers');
      this.transformersModule = transformers;
      this.pipeline = transformers.pipeline;
      console.log('✅ AISemanticService: @xenova/transformers imported successfully (lazy-loaded)');
      return true;
    } catch (error) {
      console.warn('⚠️ AISemanticService: @xenova/transformers not available:', error.message);
      console.warn('⚠️ AI semantic matching will be disabled. This is okay - keyword matching will be used instead.');
      this.transformersModule = false; // Mark as failed to prevent retry
      return false;
    }
  }

  async initialize() {
    // **FIX: Return cached promise if already initializing**
    if (this.initPromise) {
      return this.initPromise;
    }
    
    // **FIX: Return immediately if already initialized**
    if (this.initialized && this.model) {
      return Promise.resolve();
    }
    
    // **FIX: Prevent concurrent initialization**
    if (this.initializing) {
      return this.initPromise || Promise.resolve();
    }
    
    this.initializing = true;
    
    this.initPromise = (async () => {
      try {
        // Try to load transformers first
        const transformersReady = await this._loadTransformers();
        
        if (!transformersReady || !this.pipeline) {
          console.log('⚠️ AISemanticService: AI transformers not available, skipping initialization');
          this.initialized = true; // Mark as initialized to prevent retries
          this.initializing = false;
          return;
        }
        
        try {
          console.log('🤖 AISemanticService: Loading multilingual AI model...');
          this.model = await this.pipeline(
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
      } finally {
        this.initializing = false;
      }
    })();
    
    return this.initPromise;
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
        console.log('⚠️ AI model not available - skipping semantic matching');
        return [];
      }
      
      // Extract video text
      const videoText = `${videoContent.videoName || videoContent.title || ''} ${videoContent.description || ''}`.trim(); 
      
      if (!videoText) return [];
      
      // Get video embedding
      const videoEmbedding = await this.getEmbedding(videoText);
      if (!videoEmbedding) {
        console.log('⚠️ Failed to get video embedding');
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
          
          // Log top scores for debugging
           if (score > 0.2) {
             // console.log(`  📊 Score ${score.toFixed(3)}: Ad "${ad.title}" vs Video "${videoText.substring(0, 50)}"`);
           }
          
          scoredAds.push({ ad, score });
        } catch (error) {
          continue;
        }
      }
      
      // Sort by score
      scoredAds.sort((a, b) => b.score - a.score);
      
      // console.log(`📊 Top 3 scores: ${scoredAds.slice(0, 3).map(s => s.score.toFixed(3)).join(', ')}`);
      
      // **OPTIMIZED THRESHOLD: 0.15 for better ad coverage**
      // Lower threshold means more ads will match semantically
      const topMatches = scoredAds
        .filter(item => item.score > 0.15) // Lowered to 0.15 to catch more relevant ads
        .slice(0, 5) // Return top 5 instead of 3 for more variety
        .map(item => item.ad);
      
      // console.log(`✅ AI found ${topMatches.length} matching ads (threshold: 0.15)`);
      
      return topMatches;
    } catch (error) {
      console.error('❌ Error in semantic matching:', error);
      return [];
    }
  }

  /**
   * Clear cache (useful for testing or memory management)
   */
  clearCache() {
    this.cache.clear();
  }
}

export default new AISemanticService();
