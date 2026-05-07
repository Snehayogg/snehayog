import { Redis } from '@upstash/redis';
import crypto from 'crypto';

/**
 * Redis Service for caching and performance optimization
 * Uses Upstash REST SDK for better stability and serverless compatibility
 */
class RedisService {
  constructor() {
    this.client = null;
    this.isConnected = false;
    this.disabledUntil = 0;
    this.circuitCooldownMs = 10 * 60 * 1000; // 10 minutes
    this.lastCircuitLogAt = 0;
    // OPTIMIZATION: Track request count and warn when approaching limit
    this.requestCount = 0;
    this.requestCountResetAt = Date.now();
    this.dailyLimit = 10000; // Upstash free tier limit
    this.warningThreshold = 8000; // Warn at 80% of limit
  }

  _isMaxRequestLimitError(error) {
    if (!error) return false;
    const message = error?.message || '';
    return typeof message === 'string' && message.toLowerCase().includes('max requests limit exceeded');
  }

  _canUseRedis() {
    if (!this.client || !this.isConnected) return false;
    if (this.disabledUntil && Date.now() < this.disabledUntil) return false;
    if (this.disabledUntil && Date.now() >= this.disabledUntil) {
      this.disabledUntil = 0;
    }
    return true;
  }

  _handleRedisError(error, context = 'operation') {
    if (!error) return;
    if (this._isMaxRequestLimitError(error)) {
      const now = Date.now();
      this.disabledUntil = now + this.circuitCooldownMs;
      if (now - this.lastCircuitLogAt > 60000) {
        this.lastCircuitLogAt = now;
        console.error(`⚠️ Redis: Rate limit reached. Disabling Redis usage for ${Math.round(this.circuitCooldownMs / 60000)} minutes.`);
      }
      return;
    }
    console.error(`❌ Redis: Error during ${context}:`, error?.message || error);
  }

  _trackRequest() {
    const now = Date.now();
    if (now - this.requestCountResetAt > 24 * 60 * 60 * 1000) {
      this.requestCount = 0;
      this.requestCountResetAt = now;
    }
    this.requestCount++;

    if (this.requestCount === this.warningThreshold) {
      console.warn(`⚠️ Redis: Approaching daily limit (${this.requestCount}/${this.dailyLimit}).`);
    }
  }

  getRequestCount() {
    return {
      count: this.requestCount,
      limit: this.dailyLimit,
      percentage: Math.round((this.requestCount / this.dailyLimit) * 100),
      resetAt: new Date(this.requestCountResetAt + 24 * 60 * 60 * 1000).toISOString()
    };
  }

  async connect() {
    try {
      const url = process.env.UPSTASH_REDIS_REST_URL;
      const token = process.env.UPSTASH_REDIS_REST_TOKEN;

      if (!url || !token) {
        console.warn('⚠️ Redis: Missing environment variables');
        return false;
      }

      console.log('🔄 Redis: Initializing Upstash REST client...');
      
      const baseClient = new Redis({
        url: url,
        token: token,
        enableAutoPipelining: true
      });
      
      this.client = new Proxy(baseClient, {
        get: (target, prop, receiver) => {
          const value = Reflect.get(target, prop, receiver);
          if (typeof value !== 'function') return value;
          
          return async (...args) => {
            this._trackRequest();
            try {
              return await value.apply(target, args);
            } catch (error) {
              this._handleRedisError(error, `client.${String(prop)}`);
              throw error;
            }
          };
        }
      });

      await this.client.ping();
      console.log('✅ Redis: Upstash REST client ready');
      this.isConnected = true;
      this.disabledUntil = 0;
      return true;
    } catch (error) {
      console.error('❌ Redis: Initialization failed:', error?.message || error);
      this.isConnected = false;
      return false;
    }
  }

  // --- BASIC OPERATIONS ---

  async get(key) {
    if (!this._canUseRedis()) return null;
    try { return await this.client.get(key); }
    catch (error) { return null; }
  }

  async set(key, value, options = {}) {
    if (!this._canUseRedis()) return false;
    try {
      // Fix for 'Cannot use in operator to search for nx in 3600'
      if (typeof options === 'number' || typeof options === 'string') {
        await this.client.set(key, value, { ex: parseInt(options, 10) });
      } else {
        await this.client.set(key, value, options);
      }
      return true;
    } catch (error) { return false; }
  }

  async del(...keys) {
    if (!this._canUseRedis() || keys.length === 0) return false;
    try {
      const validKeys = keys.filter(Boolean);
      if (validKeys.length > 0) await this.client.del(...validKeys);
      return true;
    } catch (error) { return false; }
  }

  async exists(key) {
    if (!this._canUseRedis()) return false;
    try { return (await this.client.exists(key)) === 1; }
    catch (error) { return false; }
  }

  async expire(key, seconds) {
    if (!this._canUseRedis()) return false;
    try { await this.client.expire(key, seconds); return true; }
    catch (error) { return false; }
  }

  // --- BATCH OPERATIONS ---

  async mget(keys) {
    if (!this._canUseRedis() || keys.length === 0) return keys.map(() => null);
    try { return await this.client.mget(...keys); }
    catch (error) { return keys.map(() => null); }
  }

  async mset(keyValuePairs, expirySeconds = null) {
    if (!this._canUseRedis() || keyValuePairs.length === 0) return false;
    try {
      const p = this.client.pipeline();
      keyValuePairs.forEach(([key, value]) => {
        if (expirySeconds) p.set(key, value, { ex: expirySeconds });
        else p.set(key, value);
      });
      await p.exec();
      return true;
    } catch (error) { return false; }
  }

  // --- LIST OPERATIONS ---

  async lRange(key, start, stop) {
    if (!this._canUseRedis()) return [];
    try { return await this.client.lrange(key, start, stop); }
    catch (error) { return []; }
  }

  async lPop(key, count = null) {
    if (!this._canUseRedis()) return null;
    try {
      if (count && count > 1) return await this.client.lpop(key, count);
      return await this.client.lpop(key);
    } catch (error) { return null; }
  }

  async lLen(key) {
    if (!this._canUseRedis()) return 0;
    try { return await this.client.llen(key); }
    catch (error) { return 0; }
  }

  async rPush(key, values) {
    if (!this._canUseRedis() || values.length === 0) return 0;
    try { return await this.client.rpush(key, ...values); }
    catch (error) { return 0; }
  }

  // --- SET OPERATIONS ---

  async sAdd(key, ...members) {
    if (!this._canUseRedis() || members.length === 0) return 0;
    try { return await this.client.sadd(key, ...members); }
    catch (error) { return 0; }
  }

  async sMembers(key) {
    if (!this._canUseRedis()) return [];
    try { return await this.client.smembers(key); }
    catch (error) { return []; }
  }

  async sIsMember(key, member) {
    if (!this._canUseRedis()) return false;
    try { return (await this.client.sismember(key, member)) === 1; }
    catch (error) { return false; }
  }

  // --- BLOOM FILTER (MANUAL BITSET) ---

  _getBitPositions(item) {
    const hash = crypto.createHash('sha256').update(String(item)).digest();
    const positions = [];
    const bitsetSize = 8388608; // 1MB
    for (let i = 0; i < 4; i++) {
      positions.push(hash.readUInt32BE(i * 4) % bitsetSize);
    }
    return positions;
  }

  async bfMAdd(key, items) {
    if (!this._canUseRedis() || !items || items.length === 0) return false;
    try {
      const allPositions = items.flatMap(item => this._getBitPositions(item));
      const script = `
        for i, pos in ipairs(ARGV) do
          redis.call('SETBIT', KEYS[1], pos, 1)
        end
        redis.call('EXPIRE', KEYS[1], 1296000)
        return true
      `;
      await this.client.eval(script, [key], allPositions);
      return true;
    } catch (error) { return false; }
  }

  async bfMExists(key, items) {
    if (!this._canUseRedis() || !items || items.length === 0) return items.map(() => false);
    try {
      const allPositions = items.flatMap(item => this._getBitPositions(item));
      const script = `
        local results = {}
        local key = KEYS[1]
        for i=1, #ARGV, 4 do
          local isPresent = 1
          if redis.call('GETBIT', key, ARGV[i]) == 0 then isPresent = 0
          elseif redis.call('GETBIT', key, ARGV[i+1]) == 0 then isPresent = 0
          elseif redis.call('GETBIT', key, ARGV[i+2]) == 0 then isPresent = 0
          elseif redis.call('GETBIT', key, ARGV[i+3]) == 0 then isPresent = 0
          end
          table.insert(results, isPresent)
        end
        return results
      `;
      const results = await this.client.eval(script, [key], allPositions);
      if (!Array.isArray(results)) return items.map(() => false);
      return results.map(r => r === 1);
    } catch (error) { return items.map(() => false); }
  }

  // --- APP SPECIFIC HELPERS ---

  async setSessionShownVideos(userIdentifier, videoIds) {
    const key = `session:shown:${userIdentifier}`;
    if (!this._canUseRedis() || videoIds.length === 0) return false;
    try {
      const p = this.client.pipeline();
      p.sadd(key, ...videoIds);
      p.expire(key, 24 * 60 * 60);
      await p.exec();
      return true;
    } catch (error) { return false; }
  }

  async addToLongTermWatchHistory(userIdentifier, videoIds) {
    if (!this._canUseRedis() || !videoIds || videoIds.length === 0) return false;
    const key = `watch:history:${userIdentifier}`;
    try {
      const p = this.client.pipeline();
      p.sadd(key, ...videoIds);
      p.expire(key, 90 * 24 * 60 * 60);
      await p.exec();
      return true;
    } catch (error) { return false; }
  }

  async checkWatchedBatch(userIdentifier, videoIds) {
    const key = `watch:history:${userIdentifier}`;
    if (!this._canUseRedis() || videoIds.length === 0) return new Set();
    try {
      const results = await this.client.smismember(key, ...videoIds);
      const watchedSet = new Set();
      results.forEach((isWatched, index) => {
        if (isWatched === 1) watchedSet.add(videoIds[index]);
      });
      return watchedSet;
    } catch (error) { return new Set(); }
  }

  // --- UTILS ---

  async disconnect() {
    this.isConnected = false;
    this.client = null;
  }

  getConnectionStatus() {
    return this._canUseRedis();
  }
  
  // Aliases for compatibility
  async setLock(key, value, expirySeconds) { return this.set(key, value, { nx: true, ex: expirySeconds }); }
  async delMany(keys) { return this.del(...keys); }
  
  async addToSet(key, members) {
    if (!this._canUseRedis() || !members || members.length === 0) return 0;
    try {
      return await this.client.sadd(key, ...members);
    } catch (error) { return 0; }
  }

  async clearPattern(pattern) {
    if (!this._canUseRedis()) return;
    try {
      let cursor = '0';
      do {
        const result = await this.client.scan(cursor, { match: pattern, count: 100 });
        cursor = result[0];
        const keys = result[1];
        if (keys && keys.length > 0) {
          await this.del(...keys);
        }
      } while (cursor !== 0 && cursor !== '0');
    } catch (e) {
      console.error('❌ Redis: Error in clearPattern:', e.message);
    }
  }

  async eval(script, keys = [], args = []) {
    if (!this._canUseRedis()) return null;
    try {
      return await this.client.eval(script, keys, args);
    } catch (error) {
      console.error(`❌ Redis: Error in eval:`, error?.message || error);
      return null;
    }
  }
}

export default new RedisService();
