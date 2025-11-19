# 📊 Performance Monitoring Guide

## Redis Cache Performance Tracking

Ab aapke app me detailed performance metrics track ho rahe hain! Yeh guide aapko batayegi ki kaise monitor karein.

---

## 🎯 Performance Metrics

### 1. **Cache HIT vs MISS**

**Cache HIT** (Fast - Redis se):
```
✅ Cache HIT: videos:feed:all:page:1:limit:10... | Redis: 5ms | Total: 10ms ⚡
```
- **Meaning**: Data Redis cache se mila (10-100x faster!)
- **Time**: Usually 5-20ms
- **Performance**: ⚡ Excellent

**Cache MISS** (Slow - Database se):
```
❌ Cache MISS: videos:feed:all:page:1:limit:10... | Redis check: 3ms
📊 Performance: DB: 450ms | Total: 500ms | Videos: 10
```
- **Meaning**: Data database se fetch hua (normal speed)
- **Time**: Usually 200-1000ms
- **Performance**: Normal (first time ya cache expired)

---

## 📈 How to Monitor Performance

### Method 1: Real-time Logs (Terminal/Console)

Server logs me yeh dikhega:

```bash
# Fast response (Cache HIT)
✅ Cache HIT: videos:feed:all:page:1:limit:10... | Redis: 5ms | Total: 10ms ⚡

# Slow response (Cache MISS - first time)
❌ Cache MISS: videos:feed:all:page:1:limit:10... | Redis check: 3ms
📊 Performance: DB: 450ms | Total: 500ms | Videos: 10

# After caching (next request will be fast)
✅ Cached response: videos:feed:all:page:1:limit:10... | Cache write: 15ms
```

### Method 2: Cache Statistics Endpoint

**GET** `/api/videos/cache-stats`

Response:
```json
{
  "redis": {
    "connected": true,
    "status": "✅ Connected",
    "keys": 25,
    "memory": "..."
  },
  "cache": {
    "videoFeed": "videos:feed:*",
    "userVideos": "videos:user:*",
    "singleVideo": "video:*",
    "all": "videos:*"
  },
  "message": "Cache statistics - Use this endpoint to monitor Redis performance",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

### Method 3: Log Analysis (Production)

**Count Cache HITs:**
```bash
grep "Cache HIT" logs/backend.log | wc -l
```

**Count Cache MISSes:**
```bash
grep "Cache MISS" logs/backend.log | wc -l
```

**Calculate Cache Hit Rate:**
```bash
# Total requests
total=$(grep -E "Cache HIT|Cache MISS" logs/backend.log | wc -l)

# Cache hits
hits=$(grep "Cache HIT" logs/backend.log | wc -l)

# Hit rate percentage
hit_rate=$((hits * 100 / total))
echo "Cache Hit Rate: ${hit_rate}%"
```

**View Performance Metrics:**
```bash
grep "Performance:" logs/backend.log | tail -20
```

---

## 📊 Performance Benchmarks

### Expected Performance:

| Scenario | Response Time | Status |
|----------|--------------|--------|
| **Cache HIT** (Redis) | 5-20ms | ⚡ Excellent |
| **Cache MISS** (Database) | 200-1000ms | ✅ Normal |
| **Cache Write** | 10-30ms | ✅ Normal |

### Performance Improvement:

- **Before Redis**: 500-1000ms (database only)
- **After Redis** (Cache HIT): 5-20ms
- **Speed Improvement**: **25-200x faster!** 🚀

---

## 🎯 Cache Hit Rate Targets

| Hit Rate | Status | Action |
|----------|--------|--------|
| **80%+** | ✅ Excellent | No action needed |
| **50-80%** | ⚠️ Good | Monitor and optimize |
| **<50%** | ❌ Needs Improvement | Check cache TTL, increase cache duration |

---

## 🔍 What to Look For

### ✅ Good Signs:
- High cache hit rate (80%+)
- Fast response times (5-20ms for cache hits)
- Low database load
- Consistent performance

### ⚠️ Warning Signs:
- Low cache hit rate (<50%)
- Frequent cache misses
- High database query times
- Memory usage too high

---

## 🛠️ Troubleshooting

### Issue: Low Cache Hit Rate

**Possible Causes:**
1. Cache TTL too short
2. Too many unique cache keys
3. Cache being cleared too frequently

**Solutions:**
- Increase cache TTL (currently 5 min for videos, 10 min for user videos)
- Review cache invalidation logic
- Check for unnecessary cache clears

### Issue: High Memory Usage

**Check Redis Memory:**
```bash
# Via cache-stats endpoint
GET /api/videos/cache-stats

# Or check Redis directly
redis-cli INFO memory
```

**Solutions:**
- Reduce cache TTL
- Clear old cache keys
- Increase Redis memory limit

---

## 📱 Monitoring Dashboard (Future)

Aap ek simple dashboard bhi bana sakte hain:

```javascript
// Example: Real-time cache stats
setInterval(async () => {
  const stats = await fetch('/api/videos/cache-stats');
  const data = await stats.json();
  console.log('Cache Status:', data.redis.status);
  console.log('Cached Keys:', data.redis.keys);
}, 5000); // Every 5 seconds
```

---

## 🎉 Summary

**Performance Monitoring Checklist:**

- ✅ Check logs for "Cache HIT" vs "Cache MISS"
- ✅ Monitor response times (should be 5-20ms for cache hits)
- ✅ Calculate cache hit rate (target: 80%+)
- ✅ Use `/api/videos/cache-stats` endpoint
- ✅ Compare before/after Redis performance

**Expected Results:**
- **10-100x faster** response times with cache
- **80%+ cache hit rate** after warm-up
- **Reduced database load** by 80-90%

---

## 📞 Quick Reference

**Endpoints:**
- `GET /api/videos/cache-stats` - Cache statistics
- `GET /api/videos/` - Video feed (with performance logging)
- `GET /api/videos/user/:googleId` - User videos (with performance logging)

**Log Patterns:**
- `✅ Cache HIT` - Fast response from Redis
- `❌ Cache MISS` - Slow response from database
- `📊 Performance:` - Detailed timing metrics

Happy Monitoring! 🚀

