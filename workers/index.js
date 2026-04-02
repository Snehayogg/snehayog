/**
 * Cloudflare Worker: index.js
 * Consolidated Worker for Snehayog Edge (Upload, Caching, and Processing)
 */

import { AwsClient } from 'aws4fetch';

export default {
  // --- 1. Fetch Handler (Upload URL & API Gateway) ---
  async fetch(request, env) {
    const url = new URL(request.url);
    console.log(`📡 [${request.method}] ${url.pathname} - Incoming Request`);

    // ROUTE: GET /upload-url (Phase 1)
    if (url.pathname === '/upload-url' && request.method === 'GET') {
      return handleUploadRequest(request, env);
    }

    // ROUTE: API Gateway (Phase 2)
    // Support GET and HEAD (for curl -I tests)
    if ((request.method === 'GET' || request.method === 'HEAD') && url.pathname.startsWith('/api')) {
      return handleApiGateway(request, env);
    }

    // Default: Forward to Backend (Origin) instead of 404
    console.log(`⏩ Passthrough: ${url.pathname}`);
    return fetch(`${env.BACKEND_URL}${url.pathname}${url.search}`, { headers: request.headers });
  },

  // --- 2. R2 Event Handler (Phase 3) ---
  // Triggered when a file is uploaded to R2 (if configured in wrangler/dashboard)
  async r2_event(event, env) {
    // Only process "put" events
    if (event.action === 'put') {
      console.log(`🎥 Media Processor: New file detected: ${event.object.key}`);
      
      // Notify Backend Webhook
      const webhookUrl = `${env.BACKEND_URL}/api/videos/r2-callback`;
      try {
        await fetch(webhookUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'X-Worker-Secret': env.WORKER_SECRET // Sync with backend
          },
          body: JSON.stringify({
            event: 'uploaded',
            key: event.object.key,
            size: event.object.size,
            timestamp: event.eventTime
          })
        });
        console.log(`✅ Webhook sent for ${event.object.key}`);
      } catch (err) {
        console.error(`❌ Webhook failed for ${event.object.key}:`, err);
      }
    }
  }
};

/**
 * Phase 1: Upload Request Logic
 */
async function handleUploadRequest(request, env) {
  const url = new URL(request.url);
  const authHeader = request.headers.get('Authorization');
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });
  }

  const token = authHeader.split(' ')[1];
  const isValid = await verifyJWT(token, env.JWT_SECRET);
  if (!isValid) {
    return new Response(JSON.stringify({ error: 'Invalid Token' }), { status: 403 });
  }

  const filename = url.searchParams.get('filename');
  const folder = url.searchParams.get('folder') || 'general';
  
  if (!filename) return new Response('Filename required', { status: 400 });

  const key = `${folder}/${Date.now()}-${filename}`;
  const r2Url = `https://${env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com/${env.R2_BUCKET_NAME}/${key}`;
  
  const client = new AwsClient({
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    service: 's3',
    region: 'auto',
  });

  const signedRequest = await client.sign(r2Url, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/octet-stream' }
  });

  return new Response(JSON.stringify({
    success: true,
    uploadUrl: signedRequest.url.toString(),
    key: key
  }), { headers: { 'Content-Type': 'application/json' } });
}

/**
 * Phase 2: API Gateway Logic (Optimized for Edge Caching)
 */
async function handleApiGateway(request, env) {
  const url = new URL(request.url);
  const authHeader = request.headers.get('Authorization');
  const deviceId = request.headers.get('X-Device-Id');

  // Identify Cacheable Routes
  const cacheableRoutes = [
    { pattern: /^\/api\/app-config$/, ttl: 3600, isPrivate: false },
    { pattern: /^\/api\/videos\/user\/([\w-]+)$/, ttl: 600, isPrivate: true }, // Private because of "earnings" injection
    { pattern: /^\/api\/videos\/([\da-fA-F]{24})$/, ttl: 3600, isPrivate: false },
    { pattern: /^\/api\/creator\/analytics\/([\w-]+)$/, ttl: 600, isPrivate: true },
    { pattern: /^\/api\/users\/profile\/([\w-]+)$/, ttl: 3600, isPrivate: true }
  ];

  const route = cacheableRoutes.find(r => r.pattern.test(url.pathname));

  // 1. If not cacheable or it's the personalized feed (/api/videos), passthrough
  if (!route || url.pathname === '/api/videos') {
    console.log(`⏩ Bypassing Cache for: ${url.pathname}`);
    return fetch(`${env.BACKEND_URL}${url.pathname}${url.search}`, { headers: request.headers });
  }

  // 2. Build Cache Key
  let cacheKey = `cache:${url.pathname}${url.search}`;
  if (route.isPrivate) {
    // For private routes, key by Auth token or Device ID to prevent leak
    const identity = authHeader ? await hashString(authHeader) : (deviceId || 'anon');
    cacheKey += `:${identity}`;
  }

  // 3. Try Cache
  const cachedBody = await env.VAYUG_CACHE.get(cacheKey);
  if (cachedBody) {
    console.log(`🚀 Edge Cache HIT: ${url.pathname} (Key: ${cacheKey.split(':').pop()})`);
    return new Response(cachedBody, { 
      headers: { 'Content-Type': 'application/json', 'X-Edge-Cache': 'HIT' } 
    });
  }

  // 4. Cache Miss: Fetch from Backend
  console.log(`☁️ Edge Cache MISS: ${url.pathname}. Fetching from origin...`);
  const response = await fetch(`${env.BACKEND_URL}${url.pathname}${url.search}`, { 
    headers: request.headers,
    method: request.method // Use the original method (GET or HEAD)
  });

  if (response.ok && request.method === 'GET') {
    const body = await response.clone().text();
    // Cache the response with TTL
    await env.VAYUG_CACHE.put(cacheKey, body, { expirationTtl: route.ttl });
    
    const newResponse = new Response(body, response);
    newResponse.headers.set('X-Edge-Cache', 'MISS');
    return newResponse;
  }

  // For non-GET or failed requests, just return the response
  return response;
}

/**
 * Helper: Simple SHA-256 hash for cache keys
 */
async function hashString(str) {
  const msgUint8 = new TextEncoder().encode(str);
  const hashBuffer = await crypto.subtle.digest('SHA-256', msgUint8);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).slice(0, 16).join('');
}

/**
 * Helper: JWT Verification
 */
async function verifyJWT(token, secret) {
  try {
    const [headerB64, payloadB64, signatureB64] = token.split('.');
    const encoder = new TextEncoder();
    const key = await crypto.subtle.importKey(
      'raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['verify']
    );

    const base64ToUint8Array = (b64) => {
      const s = atob(b64.replace(/-/g, '+').replace(/_/g, '/'));
      const bytes = new Uint8Array(s.length);
      for (let i = 0; i < s.length; i++) bytes[i] = s.charCodeAt(i);
      return bytes;
    };

    return await crypto.subtle.verify(
      'HMAC', key, base64ToUint8Array(signatureB64), encoder.encode(`${headerB64}.${payloadB64}`)
    );
  } catch (e) { return false; }
}
