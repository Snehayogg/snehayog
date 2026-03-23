import { Redis } from '@upstash/redis';

/**
 * Redis Service for caching and performance optimization
 * Uses Upstash REST SDK for better stability and serverless compatibility
 */
class RedisService {
  constructor() {
    this.client = null;
    this.isConnected = false;
  }

  /**
   * Initialize Upstash Redis client
   */
  async connect() {
    try {
      const url = process.env.UPSTASH_REDIS_REST_URL;
      const token = process.env.UPSTASH_REDIS_REST_TOKEN;

      if (!url || !token) {
        console.warn('⚠️ Redis: Missing UPSTASH_REDIS_REST_URL or UPSTASH_REDIS_REST_TOKEN');
        return false;
      }

      console.log('🔄 Redis: Initializing Upstash REST client...');
      this.client = new Redis({
        url: url,
        token: token,
      });

      // Verify connection with a simple ping
      await this.client.ping();
      
      console.log('✅ Redis: Upstash REST client ready');
      this.isConnected = true;
      return true;
    } catch (error) {
      console.error('❌ Redis: Initialization failed:', error.message);
      this.isConnected = false;
      return false;
    }
  }

  /**
   * Get value from cache
   */
  async get(key) {
    if (!this.client) return null;
    try {
      return await this.client.get(key);
    } catch (error) {
      console.error(`❌ Redis: Error getting key ${key}:`, error.message);
      return null;
    }
  }

  /**
   * Set value in cache
   */
  async set(key, value, expirySeconds = null) {
    if (!this.client) return false;
    try {
      const options = expirySeconds ? { ex: expirySeconds } : {};
      await this.client.set(key, value, options);
      return true;
    } catch (error) {
      console.error(`❌ Redis: Error setting key ${key}:`, error.message);
      return false;
    }
  }

  /**
   * Set key only if it doesn't exist (Locking Pattern)
   */
  async setLock(key, value, expirySeconds) {
    if (!this.client) return false;
    try {
      // Upstash Redis 'set' returns 'OK' or null/nil if NX fails
      const result = await this.client.set(key, value, { nx: true, ex: expirySeconds });
      return result === 'OK';
    } catch (error) {
      console.error(`❌ Redis: Error acquiring lock ${key}:`, error.message);
      return false;
    }
  }

  /**
   * Delete a key from cache
   */
  async del(key) {
    if (!this.client) return false;
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
   * Note: Upstash REST doesn't support SCAN stream directly in the same way as ioredis.
   * We'll use the SCAN command iteratively.
   */
  async clearPattern(pattern) {
    if (!this.client) return 0;
    try {
      let count = 0;
      let cursor = "0";
      
      do {
        const [nextCursor, keys] = await this.client.scan(cursor, { match: pattern, count: 100 });
        cursor = nextCursor;
        if (keys.length > 0) {
          await this.client.del(...keys);
          count += keys.length;
        }
      } while (cursor !== "0");

      if (count > 0) {
        console.log(`🧹 Redis: Cleared ${count} keys matching pattern: ${pattern}`);
      }
      return count;
    } catch (error) {
      console.error(`❌ Redis: Error clearing pattern ${pattern}:`, error.message);
      return 0;
    }
  }

  /**
   * Check if key exists
   */
  async exists(key) {
    if (!this.client) return false;
    try {
      const result = await this.client.exists(key);
      return result === 1;
    } catch (error) {
      console.error(`❌ Redis: Error checking key ${key}:`, error.message);
      return false;
    }
  }

  /**
   * Get remaining TTL
   */
  async ttl(key) {
    if (!this.client) return -2;
    try {
      return await this.client.ttl(key);
    } catch (error) {
      console.error(`❌ Redis: Error getting TTL for key ${key}:`, error.message);
      return -2;
    }
  }

  /**
   * Increment a numeric value
   */
  async increment(key, increment = 1) {
    if (!this.client) return null;
    try {
      return await this.client.incrby(key, increment);
    } catch (error) {
      console.error(`❌ Redis: Error incrementing key ${key}:`, error.message);
      return null;
    }
  }

  /**
   * Disconnect (Not strictly needed for REST, but kept for API consistency)
   */
  async disconnect() {
    this.isConnected = false;
    this.client = null;
    console.log('✅ Redis: REST client disposed');
  }

  /**
   * Get connection status
   */
  getConnectionStatus() {
    return this.isConnected && this.client !== null;
  }

  /**
   * Get multiple keys at once
   */
  async mget(keys) {
    if (!this.client || keys.length === 0) return keys.map(() => null);
    try {
      return await this.client.mget(...keys);
    } catch (error) {
      console.error(`❌ Redis: Error in mget:`, error.message);
      return keys.map(() => null);
    }
  }

  /**
   * Set multiple key-value pairs at once
   */
  async mset(keyValuePairs, expirySeconds = null) {
    if (!this.client || keyValuePairs.length === 0) return false;
    try {
      const p = this.client.pipeline();
      for (const [key, value] of keyValuePairs) {
        if (expirySeconds) {
          p.set(key, value, { ex: expirySeconds });
        } else {
          p.set(key, value);
        }
      }
      await p.exec();
      return true;
    } catch (error) {
      console.error(`❌ Redis: Error in mset:`, error.message);
      return false;
    }
  }

  /**
   * Add video IDs to session shown set
   */
  async setSessionShownVideos(userIdentifier, videoIds) {
    const key = `session:shown:${userIdentifier}`;
    if (!this.client || videoIds.length === 0) return false;
    try {
      const p = this.client.pipeline();
      p.sadd(key, ...videoIds);
      p.expire(key, 24 * 60 * 60);
      await p.exec();
      return true;
    } catch (error) {
      console.error(`❌ Redis: Error setting session videos:`, error.message);
      return false;
    }
  }

  /**
   * Check if video is shown in session
   */
  async isVideoShownInSession(userIdentifier, videoId) {
    const key = `session:shown:${userIdentifier}`;
    if (!this.client) return false;
    try {
      const res = await this.client.sismember(key, videoId);
      return res === 1;
    } catch (error) {
      console.error(`❌ Redis: Error checking session video:`, error.message);
      return false;
    }
  }

  /**
   * Get all videos shown in session
   */
  async getSessionShownVideos(userIdentifier) {
    const key = `session:shown:${userIdentifier}`;
    if (!this.client) return new Set();
    try {
      const members = await this.client.smembers(key);
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
    return this.setSessionShownVideos(userIdentifier, videoIds);
  }

  /**
   * Clear session shown videos
   */
  async clearSessionShownVideos(userIdentifier) {
    const key = `session:shown:${userIdentifier}`;
    if (!this.client) return false;
    try {
      await this.client.del(key);
      return true;
    } catch (error) {
      console.error(`❌ Redis: Error clearing session videos:`, error.message);
      return false;
    }
  }

  /**
   * Add video IDs to persistent watch set
   */
  async addToLongTermWatchHistory(userIdentifier, videoIds) {
    const key = `watch:history:${userIdentifier}`;
    if (!this.client || videoIds.length === 0) return false;
    try {
      const p = this.client.pipeline();
      p.sadd(key, ...videoIds);
      p.expire(key, 90 * 24 * 60 * 60);
      await p.exec();
      return true;
    } catch (error) {
      console.error(`❌ Redis: Error adding to long-term watch history:`, error.message);
      return false;
    }
  }

  /**
   * BATCH FILTERING: Check which of the provided video IDs have been watched
   */
  async checkWatchedBatch(userIdentifier, videoIds) {
    const key = `watch:history:${userIdentifier}`;
    if (!this.client || videoIds.length === 0) return new Set();
    try {
      const results = await this.client.smismember(key, ...videoIds);
      const watchedSet = new Set();
      results.forEach((isWatched, index) => {
        if (isWatched === 1) watchedSet.add(videoIds[index]);
      });
      return watchedSet;
    } catch (error) {
      console.error(`❌ Redis: Error in checkWatchedBatch:`, error.message);
      return new Set();
    }
  }

  /**
   * Get all watched video IDs for a user
   */
  async getLongTermWatchHistory(userIdentifier) {
    const key = `watch:history:${userIdentifier}`;
    if (!this.client) return new Set();
    try {
      const members = await this.client.smembers(key);
      return new Set(members);
    } catch (error) {
      console.error(`❌ Redis: Error getting long-term watch history:`, error.message);
      return new Set();
    }
  }

  /**
   * Add members to a set
   */
  async addToSet(key, members) {
    if (!this.client || members.length === 0) return false;
    try {
      await this.client.sadd(key, ...members);
      return true;
    } catch (error) {
      console.error(`❌ Redis: Error adding to set ${key}:`, error.message);
      return false;
    }
  }

  /**
   * Get all members of a set
   */
  async getSetMembers(key) {
    if (!this.client) return new Set();
    try {
      const members = await this.client.smembers(key);
      return new Set(members);
    } catch (error) {
      console.error(`❌ Redis: Error getting set members ${key}:`, error.message);
      return new Set();
    }
  }

  /**
   * Check if multiple values exist in a set
   */
  async smIsMember(key, members) {
    if (!this.client || members.length === 0) return members.map(() => false);
    try {
      const results = await this.client.smismember(key, ...members);
      return results.map(r => r === 1);
    } catch (error) {
      console.error(`❌ Redis: Error in smIsMember ${key}:`, error.message);
      return members.map(() => false);
    }
  }

  /**
   * Set expiry for a key
   */
  async expire(key, seconds) {
    if (!this.client) return false;
    try {
      await this.client.expire(key, seconds);
      return true;
    } catch (error) {
      console.error(`❌ Redis: Error setting expiry for ${key}:`, error.message);
      return false;
    }
  }

  /**
   * Push values to the tail of a list
   */
  async rPush(key, values) {
    if (!this.client || values.length === 0) return 0;
    try {
      return await this.client.rpush(key, ...values);
    } catch (error) {
      console.error(`❌ Redis: Error rPush to ${key}:`, error.message);
      return 0;
    }
  }

  /**
   * Push value to the head of a list
   */
  async lPush(key, value) {
    if (!this.client) return 0;
    try {
      const values = Array.isArray(value) ? value : [value];
      if (values.length === 0) return 0;
      return await this.client.lpush(key, ...values);
    } catch (error) {
      console.error(`❌ Redis: Error lPush to ${key}:`, error.message);
      return 0;
    }
  }

  /**
   * Pop value(s) from the head of a list
   */
  async lPop(key, count = null) {
    if (!this.client) return null;
    try {
      if (count && count > 1) {
        // Upstash REST lpop supports count argument
        return await this.client.lpop(key, count);
      }
      return await this.client.lpop(key);
    } catch (error) {
      console.error(`❌ Redis: Error lPop from ${key}:`, error.message);
      return null;
    }
  }

  /**
   * Get range of elements from a list
   */
  async lRange(key, start, stop) {
    if (!this.client) return [];
    try {
      return await this.client.lrange(key, start, stop);
    } catch (error) {
      console.error(`❌ Redis: Error lRange from ${key}:`, error.message);
      return [];
    }
  }

  /**
   * Trim list to specified range
   */
  async lTrim(key, start, stop) {
    if (!this.client) return false;
    try {
      await this.client.ltrim(key, start, stop);
      return true;
    } catch (error) {
      console.error(`❌ Redis: Error lTrim ${key}:`, error.message);
      return false;
    }
  }

  /**
   * Get length of a list
   */
  async lLen(key) {
    if (!this.client) return 0;
    try {
      return await this.client.llen(key);
    } catch (error) {
      console.error(`❌ Redis: Error lLen ${key}:`, error.message);
      return 0;
    }
  }

  /**
   * Smart Push to Feed Queue (Lua Script)
   */
  async smartPushToFeed(queueKey, videoId, uploaderId) {
    if (!this.client) return false;

    try {
      const lastCreatorKey = `${queueKey}:last_creator`;
      
      const script = `
        local queueKey = KEYS[1]
        local lastCreatorKey = KEYS[2]
        local videoId = ARGV[1]
        local uploaderId = ARGV[2]

        local lastCreator = redis.call("GET", lastCreatorKey)

        if lastCreator == uploaderId then
          local v0 = redis.call("LPOP", queueKey)
          local v1 = redis.call("LPOP", queueKey)
          redis.call("LPUSH", queueKey, videoId)
          if v1 then redis.call("LPUSH", queueKey, v1) end
          if v0 then redis.call("LPUSH", queueKey, v0) end
          return "buffered"
        else
          redis.call("LPUSH", queueKey, videoId)
          redis.call("SET", lastCreatorKey, uploaderId)
          redis.call("EXPIRE", lastCreatorKey, 3600)
          return "top"
        end
      `;

      await this.client.eval(script, [queueKey, lastCreatorKey], [videoId, uploaderId]);
      return true;
    } catch (error) {
      console.error(`❌ Redis: SmartPush error for ${queueKey}:`, error.message);
      return this.lPush(queueKey, videoId);
    }
  }

  /**
   * Universal call method for compatibility with other libraries (like rate-limit-redis)
   */
  /**
   * Universal call method for compatibility with other libraries (like rate-limit-redis)
   */
  async call(command, ...args) {
    if (!this.client) return null;
    try {
      const cmd = command.toLowerCase();
      if (typeof this.client[cmd] === 'function') {
        return await this.client[cmd](...args);
      }
      console.warn(`⚠️ Redis: Command "${command}" not found on Upstash client`);
      return null;
    } catch (error) {
      console.error(`❌ Redis: Error in call (${command}):`, error.message);
      return null;
    }
  }

  // Method Aliases
  async sAdd(key, members) { return this.addToSet(key, members); }
  async sMembers(key) { return this.getSetMembers(key); }
  async sIsMember(key, member) { return this.isVideoShownInSession(key, member); }
}

export default new RedisService();
