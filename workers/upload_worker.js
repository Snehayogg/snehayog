/**
 * Cloudflare Worker: upload_worker.js
 * Handles JWT-authorized direct-to-R2 upload URL generation.
 */

import { AwsClient } from 'aws4fetch'; // Lightweight alternative for signing

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // 1. Authenticate the user (JWT Verification)
    const authHeader = request.headers.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    const token = authHeader.split(' ')[1];
    const isValid = await verifyJWT(token, env.JWT_SECRET);
    if (!isValid) {
      return new Response(JSON.stringify({ error: 'Invalid Token' }), {
        status: 403,
        headers: { 'Content-Type': 'application/json' },
      });
    }

    // 2. Map the upload request to the correct folder
    // Request expected: GET /upload-url?filename=test.mp4&folder=videos
    if (url.pathname === '/upload-url' && request.method === 'GET') {
      const filename = url.searchParams.get('filename');
      const folder = url.searchParams.get('folder') || 'general';
      
      if (!filename) {
        return new Response(JSON.stringify({ error: 'Filename is required' }), {
          status: 400,
        });
      }

      const key = `${folder}/${Date.now()}-${filename}`;
      
      // 3. Generate a signed PUT URL using R2 S3 API
      // Note: You can use AWS SDK or aws4fetch to sign the request
      const r2Url = `https://${env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com/${env.R2_BUCKET_NAME}/${key}`;
      
      const client = new AwsClient({
        accessKeyId: env.R2_ACCESS_KEY_ID,
        secretAccessKey: env.R2_SECRET_ACCESS_KEY,
        service: 's3',
        region: 'auto',
      });

      const signedRequest = await client.sign(r2Url, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/octet-stream', // Generic binary
        }
      });

      // Extract the signed URL
      const uploadUrl = signedRequest.url.toString();

      return new Response(JSON.stringify({
        success: true,
        uploadUrl: uploadUrl,
        key: key,
        publicUrl: `https://pub-${env.R2_PUBLIC_DOMAIN}/${key}` // Assuming you have a public domain
      }), {
        headers: { 'Content-Type': 'application/json' },
      });
    }

    return new Response('Not Found', { status: 404 });
  }
};

/**
 * Basic JWT Verification (Web Crypto API)
 */
async function verifyJWT(token, secret) {
  try {
    const [headerB64, payloadB64, signatureB64] = token.split('.');
    
    // Verify signature
    const encoder = new TextEncoder();
    const key = await crypto.subtle.importKey(
      'raw',
      encoder.encode(secret),
      { name: 'HMAC', hash: 'SHA-256' },
      false,
      ['verify']
    );

    const isValid = await crypto.subtle.verify(
      'HMAC',
      key,
      base64UrlDecode(signatureB64),
      encoder.encode(`${headerB64}.${payloadB64}`)
    );

    return isValid;
  } catch (e) {
    return false;
  }
}

function base64UrlDecode(str) {
  str = str.replace(/-/g, '+').replace(/_/g, '/');
  while (str.length % 4) str += '=';
  const binaryString = atob(str);
  const bytes = new Uint8Array(binaryString.length);
  for (let i = 0; i < binaryString.length; i++) {
    bytes[i] = binaryString.charCodeAt(i);
  }
  return bytes;
}
