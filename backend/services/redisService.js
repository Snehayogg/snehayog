import { createClient } from 'redis';

/**
 * Redis Service for caching and performance optimization
 * Provides in-memory caching to reduce database load and improve response times
 */
class RedisService {
  constructor() {
    this.client = null;
    this.isConnected = false;
    this.connectionAttempts = 0;
    this.maxReconnectAttempts = 10;
  }

  /**
   * Connect to Redis server
   * Uses Railway Redis URL from environment or provided URL
   */
  async connect() {
    try {
      // Get Redis URL from environment variables
      // Priority: REDIS_PUBLIC_URL > REDIS_URL > Construct from individual parts
      let redisUrl = process.env.REDIS_PUBLIC_URL || process.env.REDIS_URL;

      // If no full URL, try to construct from individual parts
      if (!redisUrl) {
        const redisHost = process.env.REDISHOST || process.env.REDIS_HOST;
        const redisPort = process.env.REDISPORT || process.env.REDIS_PORT || '6379';
        const redisUser = process.env.REDISUSER || process.env.REDIS_USER || 'default';
        const redisPassword = process.env.REDISPASSWORD || process.env.REDIS_PASSWORD || process.env.REDIS_PASSWORD;

        if (redisHost && redisPassword) {
          redisUrl = `redis://${redisUser}:${redisPassword}@${redisHost}:${redisPort}`;
          console.log('🔧 Redis: Constructed URL from individual environment variables');
        }
      }

      if (!redisUrl) {
        console.error('❌ Redis: No Redis URL found in environment variables');
        console.error('💡 Available options:');
        console.error('   1. REDIS_PUBLIC_URL (recommended) - Full connection string');
        console.error('   2. REDIS_URL - Full connection string');
        console.error('   3. Individual parts: REDISHOST, REDISPORT, REDISUSER, REDISPASSWORD');
        console.error('💡 Format: redis://USER:PASSWORD@HOST:PORT');
        return false;
      }

      // **FIX: Check if using internal Railway hostname (won't work locally)**
      if (redisUrl.includes('railway.internal')) {
        console.error('❌ Redis: Internal Railway hostname detected (redis.railway.internal)');
        console.error('💡 This URL only works inside Railway platform');
        console.error('💡 Use REDIS_PUBLIC_URL instead for local development');
        console.error('💡 Format: redis://default:PASSWORD@HOST:PORT');
        return false;
      }

      // Log connection attempt (hide full URL for security)
      console.log('🔄 Redis: Attempting to connect...');
      // Only show hostname, not full URL
      const urlMatch = redisUrl.match(/@([^:]+):(\d+)/);
      if (urlMatch) {
        console.log(`🔍 Redis: Connecting to ${urlMatch[1]}:${urlMatch[2]}`);
      } else {
        console.log('🔍 Redis: Connection configured');
      }

      this.client = createClient({
        url: redisUrl,
        socket: {
          reconnectStrategy: (retries) => {
            this.connectionAttempts = retries;
            if (retries > this.maxReconnectAttempts) {
              console.error('❌ Redis: Max reconnection attempts reached');
              return new Error('Max reconnection attempts');
            }
            const delay = Math.min(retries * 100, 3000);
            console.log(`🔄 Redis: Reconnecting attempt ${retries} in ${delay}ms`);
            return delay;
          },
          connectTimeout: 10000, // 10 seconds timeout
        },
      });

      // Error handler
      this.client.on('error', (err) => {
        console.error('❌ Redis Client Error:', err.message);
        this.isConnected = false;
      });

      // Connection events
      this.client.on('connect', () => {
        console.log('🔄 Redis: Connecting...');
      });

      this.client.on('ready', () => {
        console.log('✅ Redis: Connected and ready');
        this.isConnected = true;
        this.connectionAttempts = 0;
      });

      this.client.on('reconnecting', () => {
        console.log('🔄 Redis: Reconnecting...');
      });

      this.client.on('end', () => {
        console.log('⚠️ Redis: Connection ended');
        this.isConnected = false;
      });

      // Connect to Redis
      await this.client.connect();
      return true;
    } catch (error) {
      console.error('❌ Redis: Connection failed:', error.message);
      this.isConnected = false;
      // Don't throw error - app should work without Redis
      return false;
    }
  }

  /**
   * Get value from cache
   * @param {string} key - Cache key
   * @returns {Promise<any|null>} - Cached value or null
   */
  async get(key) {
    if (!this.isConnected || !this.client) {
      return null;
    }

    try {
      const value = await this.client.get(key);
      if (value) {
        return JSON.parse(value);
      }
      return null;
    } catch (error) {
      console.error(`❌ Redis: Error getting key ${key}:`, error.message);
      return null;
    }
  }

  /**
   * Set value in cache
   * @param {string} key - Cache key
   * @param {any} value - Value to cache
   * @param {number} expirySeconds - Expiry time in seconds (optional)
   * @returns {Promise<boolean>} - Success status
   */
  async set(key, value, expirySeconds = null) {
    if (!this.isConnected || !this.client) {
      return false;
    }

    try {
      const stringValue = JSON.stringify(value);
      if (expirySeconds && expirySeconds > 0) {
        await this.client.setEx(key, expirySeconds, stringValue);
      } else {
        await this.client.set(key, stringValue);
      }
      return true;
    } catch (error) {
      console.error(`❌ Redis: Error setting key ${key}:`, error.message);
      return false;
    }
  }

  /**
   * Delete a key from cache
   * @param {string} key - Cache key to delete
   * @returns {Promise<boolean>} - Success status
   */
  async del(key) {
    if (!this.isConnected || !this.client) {
      return false;
    }

    try {
      await this.client.del(key);
      return true;
    } catch (error) {
      console.error(`❌ Redis: Error deleting key ${key}:`, error.message);
      return false;
    }
  }

  /**
   * Delete multiple keys matching a pattern
   * @param {string} pattern - Pattern to match (e.g., 'videos:*')
   * @returns {Promise<number>} - Number of keys deleted
   */
  async clearPattern(pattern) {
    if (!this.isConnected || !this.client) {
      return 0;
    }

    try {
      const keys = await this.client.keys(pattern);
      if (keys.length > 0) {
        await this.client.del(keys);
        console.log(`🧹 Redis: Cleared ${keys.length} keys matching pattern: ${pattern}`);
        return keys.length;
      }
      return 0;
    } catch (error) {
      console.error(`❌ Redis: Error clearing pattern ${pattern}:`, error.message);
      return 0;
    }
  }

  /**
   * Check if key exists
   * @param {string} key - Cache key
   * @returns {Promise<boolean>} - True if key exists
   */
  async exists(key) {
    if (!this.isConnected || !this.client) {
      return false;
    }

    try {
      const result = await this.client.exists(key);
      return result === 1;
    } catch (error) {
      console.error(`❌ Redis: Error checking key ${key}:`, error.message);
      return false;
    }
  }

  /**
   * Get remaining TTL (time to live) for a key
   * @param {string} key - Cache key
   * @returns {Promise<number>} - TTL in seconds, -1 if no expiry, -2 if key doesn't exist
   */
  async ttl(key) {
    if (!this.isConnected || !this.client) {
      return -2;
    }

    try {
      return await this.client.ttl(key);
    } catch (error) {
      console.error(`❌ Redis: Error getting TTL for key ${key}:`, error.message);
      return -2;
    }
  }

  /**
   * Increment a numeric value
   * @param {string} key - Cache key
   * @param {number} increment - Amount to increment (default: 1)
   * @returns {Promise<number>} - New value after increment
   */
  async increment(key, increment = 1) {
    if (!this.isConnected || !this.client) {
      return null;
    }

    try {
      return await this.client.incrBy(key, increment);
    } catch (error) {
      console.error(`❌ Redis: Error incrementing key ${key}:`, error.message);
      return null;
    }
  }

  /**
   * Disconnect from Redis
   */
  async disconnect() {
    if (this.client && this.isConnected) {
      try {
        await this.client.quit();
        this.isConnected = false;
        console.log('✅ Redis: Disconnected gracefully');
      } catch (error) {
        console.error('❌ Redis: Error during disconnect:', error.message);
      }
    }
  }

  /**
   * Get connection status
   * @returns {boolean} - True if connected
   */
  getConnectionStatus() {
    return this.isConnected;
  }

  /**
   * Get multiple keys at once (batch operation)
   * @param {string[]} keys - Array of cache keys
   * @returns {Promise<Array<any|null>>} - Array of cached values or null
   */
  async mget(keys) {
    if (!this.isConnected || !this.client) {
      return keys.map(() => null);
    }

    try {
      if (keys.length === 0) return [];
      const values = await this.client.mGet(keys);
      return values.map(v => v ? JSON.parse(v) : null);
    } catch (error) {
      console.error(`❌ Redis: Error in mget:`, error.message);
      return keys.map(() => null);
    }
  }

  /**
   * Set multiple key-value pairs at once (batch operation)
   * @param {Array<[string, any]>} keyValuePairs - Array of [key, value] pairs
   * @param {number} expirySeconds - Expiry time in seconds (applied to all keys)
   * @returns {Promise<boolean>} - Success status
   */
  async mset(keyValuePairs, expirySeconds = null) {
    if (!this.isConnected || !this.client) {
      return false;
    }

    try {
      const pipeline = this.client.multi();
      for (const [key, value] of keyValuePairs) {
        const stringValue = JSON.stringify(value);
        if (expirySeconds && expirySeconds > 0) {
          pipeline.setEx(key, expirySeconds, stringValue);
        } else {
          pipeline.set(key, stringValue);
        }
      }
      await pipeline.exec();
      return true;
    } catch (error) {
      console.error(`❌ Redis: Error in mset:`, error.message);
      return false;
    }
  }

  /**
   * Redis Set operations for session state (more memory efficient)
   * Add video ID to session shown set
   */
  async setSessionShownVideos(userIdentifier, videoIds) {
    const key = `session:shown:${userIdentifier}`;
    if (!this.isConnected || !this.client) {
      return false;
    }

    try {
      const pipeline = this.client.multi();
      // Add all video IDs to set
      if (videoIds.length > 0) {
        pipeline.sAdd(key, videoIds);
      }
      pipeline.expire(key, 24 * 60 * 60); // 24h expiry
      await pipeline.exec();
      return true;
    } catch (error) {
      console.error(`❌ Redis: Error setting session videos:`, error.message);
      return false;
    }
  }

  /**
   * Check if video is shown in session (using Redis Set)
   */
  async isVideoShownInSession(userIdentifier, videoId) {
    const key = `session:shown:${userIdentifier}`;
    if (!this.isConnected || !this.client) {
      return false;
    }

    try {
      return await this.client.sIsMember(key, videoId);
    } catch (error) {
      console.error(`❌ Redis: Error checking session video:`, error.message);
      return false;
    }
  }

  /**
   * Get all videos shown in session (using Redis Set)
   */
  async getSessionShownVideos(userIdentifier) {
    const key = `session:shown:${userIdentifier}`;
    if (!this.isConnected || !this.client) {
      return new Set();
    }

    try {
      const members = await this.client.sMembers(key);
      return new Set(members);
    } catch (error) {
      console.error(`❌ Redis: Error getting session videos:`, error.message);
      return new Set();
    }
  }

  /**
   * Add video IDs to session shown set
   */
  async addToSessionShownVideos(userIdentifier, videoIds) {
    const key = `session:shown:${userIdentifier}`;
    if (!this.isConnected || !this.client || videoIds.length === 0) {
      return false;
    }

    try {
      await this.client.sAdd(key, videoIds);
      await this.client.expire(key, 24 * 60 * 60); // Refresh 24h expiry
      return true;
    } catch (error) {
      console.error(`❌ Redis: Error adding to session videos:`, error.message);
      return false;
    }
  }

  /**
   * Clear session shown videos (for feed restart)
   * @param {string} userIdentifier - User identifier (userId or platformId)
   * @returns {Promise<boolean>} - Success status
   */
  async clearSessionShownVideos(userIdentifier) {
    const key = `session:shown:${userIdentifier}`;
    if (!this.isConnected || !this.client) {
      return false;
    }

    try {
      await this.client.del(key);
      console.log(`🧹 Redis: Cleared session shown videos for: ${userIdentifier}`);
      return true;
    } catch (error) {
      console.error(`❌ Redis: Error clearing session videos:`, error.message);
      return false;
    }
  }

  /**
   * LONG-TERM WATCH HISTORY: Add video IDs to persistent watch set
   * @param {string} userIdentifier - User identifier
   * @param {string[]} videoIds - List of video IDs to add
   */
  async addToLongTermWatchHistory(userIdentifier, videoIds) {
    const key = `watch:history:${userIdentifier}`;
    if (!this.isConnected || !this.client || !videoIds.length) return false;

    try {
      // Add to set (no expiry for long-term history)
      await this.client.sAdd(key, videoIds);
      // Optional: Set a long expiry like 90 days to keep Redis clean
      await this.client.expire(key, 90 * 24 * 60 * 60);
      return true;
    } catch (error) {
      console.error(`❌ Redis: Error adding to long-term watch history:`, error.message);
      return false;
    }
  }

  /**
   * BATCH FILTERING: Check which of the provided video IDs have been watched
   * @param {string} userIdentifier - User identifier
   * @param {string[]} videoIds - List of video IDs to check
   * @returns {Promise<Set<string>>} - Returns a Set of watched video IDs
   */
  async checkWatchedBatch(userIdentifier, videoIds) {
    const key = `watch:history:${userIdentifier}`;
    if (!this.isConnected || !this.client || !videoIds.length) return new Set();

    try {
      if (videoIds.length === 0) return new Set();

      // Use SMISMEMBER for atomic batch check (Redis 6.2+)
      // Fallback for older Redis versions if needed: use pipeline with sIsMember
      const results = await this.client.smIsMember(key, videoIds);

      const watchedSet = new Set();
      results.forEach((isWatched, index) => {
        if (isWatched) watchedSet.add(videoIds[index]);
      });
      return watchedSet;
    } catch (error) {
      // Fallback: If smIsMember fails (older Redis), use pipeline
      try {
        const pipeline = this.client.multi();
        videoIds.forEach(id => pipeline.sIsMember(key, id));
        const results = await pipeline.exec();

        const watchedSet = new Set();
        results.forEach((isWatched, index) => {
          if (isWatched) watchedSet.add(videoIds[index]);
        });
        return watchedSet;
      } catch (err) {
        console.error(`❌ Redis: Error in checkWatchedBatch:`, err.message);
        return new Set();
      }
    }
  }

  /**
   * Get all watched video IDs for a user
   */
  async getLongTermWatchHistory(userIdentifier) {
    const key = `watch:history:${userIdentifier}`;
    if (!this.isConnected || !this.client) return new Set();

    try {
      const members = await this.client.sMembers(key);
      return new Set(members);
    } catch (error) {
      console.error(`❌ Redis: Error getting long-term watch history:`, error.message);
      return new Set();
    }
  }

  /**
   * Add members to a set
   * @param {string} key - key
   * @param {Array<string>} members - members to add
   */
  async addToSet(key, members) {
    if (!this.isConnected || !this.client) return false;
    try {
      if (members.length > 0) {
        await this.client.sAdd(key, members);
      }
      return true;
    } catch (error) {
      console.error(`❌ Redis: Error adding to set ${key}:`, error.message);
      return false;
    }
  }

  /**
   * Get all members of a set
   * @param {string} key - key
   * @returns {Promise<Set<string>>}
   */
  async getSetMembers(key) {
    if (!this.isConnected || !this.client) return new Set();
    try {
      const members = await this.client.sMembers(key);
      return new Set(members);
    } catch (error) {
      console.error(`❌ Redis: Error getting set members ${key}:`, error.message);
      return new Set();
    }
  }

  /**
   * Set expiry for a key
   * @param {string} key - key
   * @param {number} seconds - expiry in seconds
   */
  async expire(key, seconds) {
    if (!this.isConnected || !this.client) return false;
    try {
      await this.client.expire(key, seconds);
      return true;
    } catch (error) {
      console.error(`❌ Redis: Error setting expiry for ${key}:`, error.message);
      return false;
    }
  }

  /**
   * Get cache statistics (for monitoring)
   * @returns {Promise<object>} - Cache statistics
   */
  async getStats() {
    if (!this.isConnected || !this.client) {
      return {
        connected: false,
        keys: 0,
        memory: 'N/A'
      };
    }

    try {
      const info = await this.client.info('memory');
      const keys = await this.client.dbSize();

      return {
        connected: true,
        keys: keys,
        memory: info
      };
    } catch (error) {
      console.error('❌ Redis: Error getting stats:', error.message);
      return {
        connected: this.isConnected,
        keys: 0,
        memory: 'Error'
      };
    }
  }
}

// Export singleton instance
export default new RedisService();

