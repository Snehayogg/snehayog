import redisService from '../services/redisService.js';

/**
 * Cache Middleware for Express routes
 * Automatically caches GET request responses in Redis
 * 
 * @param {number} duration - Cache duration in seconds (default: 300 = 5 minutes)
 * @param {object} options - Additional options
 * @param {boolean} options.skipAuth - Skip cache for authenticated requests (default: true)
 * @param {function} options.keyGenerator - Custom cache key generator function
 * @returns {function} Express middleware function
 */
export const cacheMiddleware = (duration = 300, options = {}) => {
  const {
    skipAuth = true, // Skip cache for authenticated requests by default
    keyGenerator = null, // Custom key generator
  } = options;

  return async (req, res, next) => {
    // Only cache GET requests
    if (req.method !== 'GET') {
      return next();
    }

    // Skip cache if Redis is not connected
    if (!redisService.getConnectionStatus()) {
      return next();
    }

    // Skip cache for authenticated requests if option is enabled
    if (skipAuth && req.headers.authorization) {
      return next();
    }

    // Generate cache key
    let cacheKey;
    if (keyGenerator) {
      cacheKey = keyGenerator(req);
    } else {
      // Default key generation: include URL and query params
      const queryString = Object.keys(req.query)
        .sort()
        .map(key => `${key}=${req.query[key]}`)
        .join('&');
      cacheKey = `cache:${req.originalUrl}${queryString ? `?${queryString}` : ''}`;
    }

    try {
      // Try to get from cache
      const cached = await redisService.get(cacheKey);
      if (cached) {
        console.log(`✅ Cache HIT: ${cacheKey.substring(0, 100)}...`);
        return res.json(cached);
      }

      console.log(`❌ Cache MISS: ${cacheKey.substring(0, 100)}...`);

      // Store original json function
      const originalJson = res.json.bind(res);

      // Override json to cache response
      res.json = function (data) {
        // Only cache successful responses (status 200)
        if (res.statusCode === 200) {
          redisService.set(cacheKey, data, duration).catch(err => {
            console.error('❌ Error caching response:', err.message);
          });
        }
        originalJson(data);
      };

      next();
    } catch (error) {
      console.error('❌ Cache middleware error:', error.message);
      // Continue without caching on error
      next();
    }
  };
};

/**
 * Cache invalidation helper
 * Clears cache for specific patterns
 * 
 * @param {string|string[]} patterns - Cache key patterns to clear
 */
export const invalidateCache = async (patterns) => {
  if (!redisService.getConnectionStatus()) {
    return;
  }

  const patternArray = Array.isArray(patterns) ? patterns : [patterns];
  
  for (const pattern of patternArray) {
    await redisService.clearPattern(pattern);
  }
};

/**
 * Video-specific cache keys
 */
export const VideoCacheKeys = {
  feed: (videoType = 'all') => `videos:feed:${videoType}`,
  user: (userId) => `videos:user:${userId}`,
  single: (videoId) => `video:${videoId}`,
  all: () => 'videos:*',
  seen: (userId) => `user:seen_all:${userId}`, // **NEW: Set of ALL seen video IDs**
};

/**
 * User-specific cache keys
 */
export const UserCacheKeys = {
  profile: (userId) => `user:${userId}`,
  videos: (userId) => `user:videos:${userId}`,
  all: () => 'user:*',
};

/**
 * Ad-specific cache keys
 */
export const AdCacheKeys = {
  active: (adType = 'banner') => `ads:active:${adType}`,
  all: () => 'ads:*',
};

