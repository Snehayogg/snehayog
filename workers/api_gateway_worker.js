/**
 * Cloudflare Worker: api_gateway_worker.js
 * Handles Edge Caching for high-traffic read APIs.
 */

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // 1. Only cache GET requests
    if (request.method !== 'GET') {
      return fetch(request);
    }

    // 2. Identify Cacheable Routes
    const cacheableRoutes = [
      { pattern: /^\/api\/users\/profile\/([\w-]+)/, ttl: 3600 }, // User Profiles (1 hr)
      { pattern: /^\/api\/videos$/, ttl: 300 },                   // Public Feed (5 min)
      { pattern: /^\/api\/videos\/user\/([\w-]+)/, ttl: 600 }     // User Videos (10 min)
    ];

    const route = cacheableRoutes.find(r => r.pattern.test(url.pathname));
    if (!route) {
      return fetch(request); // Passthrough to backend
    }

    // 3. Check KV Cache
    const cacheKey = `cache:${url.pathname}${url.search}`;
    const cachedResponse = await env.SNEHAYOG_CACHE.get(cacheKey);

    if (cachedResponse) {
      console.log(`🚀 Edge Cache HIT: ${cacheKey}`);
      return new Response(cachedResponse, {
        headers: {
          'Content-Type': 'application/json',
          'X-Edge-Cache': 'HIT'
        }
      });
    }

    // 4. Cache Miss: Fetch from Origin Backend
    console.log(`☁️ Edge Cache MISS: ${cacheKey}. Fetching from origin...`);
    const originUrl = `${env.BACKEND_URL}${url.pathname}${url.search}`;
    const response = await fetch(originUrl, {
      headers: request.headers
    });

    if (response.ok) {
      const body = await response.clone().text();
      // Store in KV with TTL
      await env.SNEHAYOG_CACHE.put(cacheKey, body, {
        expirationTtl: route.ttl
      });
      
      const newResponse = new Response(body, response);
      newResponse.headers.set('X-Edge-Cache', 'MISS');
      return newResponse;
    }

    return response;
  }
};
