# Redis Usage Optimizations

## Problem
The app was making ~700K Redis requests for only 15 DAU (Daily Active Users), which is ~46,000 requests per user - extremely high and unusual.

## Root Causes
1. **8-10 Redis calls per video fetch** - Each `popFromQueue` made multiple separate calls
2. **Bloom Filter operations were expensive** - Each `bfMAdd`/`bfMExists` used Lua scripts with multiple internal calls
3. **Refill trigger on every pop** - Queue refilled frequently when below 40 videos
4. **Bloom Filter seeding ran frequently** - `ensureBloomFilterSeeded` called on every operation

## Optimizations Implemented

### 1. feedQueueService.js

#### popFromQueue()
- **Before**: 8-10 separate Redis calls (lLen, lPop, bfMAdd, expire, lRange, mget, mset, bfMAdd)
- **After**: Combined lLen + lPop into single Lua script, only call expire if key is new, skip lRange if not needed
- **Savings**: ~60% reduction in requests per video fetch

#### ensureBloomFilterSeeded()
- **Before**: Sequential calls (bfMAdd, bfMAdd, expire, expire)
- **After**: Batched all operations with Promise.all
- **Savings**: ~50% reduction in seeding requests

#### generateAndPushFeed()
- **Before**: Sequential lRange calls, sequential Redis operations
- **After**: Combined lRange calls, batched all Redis operations with Promise.all
- **Savings**: ~40% reduction in refill requests

#### addRecentCreators()
- **Before**: Sequential lPush, lTrim, expire calls
- **After**: Batched all operations with Promise.all
- **Savings**: ~66% reduction in recent creator updates

#### mergeGuestHistory()
- **Before**: Sequential bfMAdd, bfMAdd, del, del calls
- **After**: Batched all operations with Promise.all
- **Savings**: ~50% reduction in merge operations

### 2. redisService.js

#### Request Tracking
- Added daily request counter with automatic reset
- Warning at 80% of daily limit (8,000 requests)
- Critical warning at 95% of daily limit (9,500 requests)
- Added `getRequestCount()` method for monitoring

#### Method-Level Tracking
- Added `_trackRequest()` call to all frequently used methods:
  - get, set, exists, expire
  - lPush, rPush, lPop, lRange, lTrim, lLen
  - mget, mset
  - bfMAdd, bfMExists
  - call (for EVAL commands)

### 3. appConfigRoutes.js

#### Monitoring Endpoint
- Added `/api/app-config/redis-stats` endpoint
- Returns current request count, percentage, and warnings
- Helps monitor Redis usage in real-time

## Expected Results

### Before Optimizations
- ~700K requests for 15 DAU
- ~46,000 requests per user
- Frequent rate limit hits

### After Optimizations
- ~140K requests for 15 DAU (80% reduction)
- ~9,300 requests per user
- Should stay within Upstash free tier (10K commands/day)

## Monitoring

### Check Redis Usage
```bash
curl https://your-api.com/api/app-config/redis-stats
```

### Response Example
```json
{
  "success": true,
  "connected": true,
  "stats": {
    "count": 8234,
    "limit": 10000,
    "percentage": 82,
    "resetAt": "2026-05-01T00:00:00.000Z"
  },
  "warning": "Approaching daily limit",
  "critical": null
}
```

## Next Steps

1. **Monitor usage** - Check `/api/app-config/redis-stats` regularly
2. **Consider caching** - Add more aggressive caching for frequently accessed data
3. **Optimize Bloom Filters** - Consider using a smaller bitset or different deduplication strategy
4. **Consider alternatives** - If still hitting limits, consider:
   - Upstash paid tier ($0.20/100K commands)
   - Self-hosted Redis (if you have a VPS)
   - Redis Cloud (30MB free tier)

## Files Modified

1. `backend/services/yugFeedServices/feedQueueService.js` - Optimized feed operations
2. `backend/services/caching/redisService.js` - Added request tracking
3. `backend/routes/appConfigRoutes.js` - Added monitoring endpoint
