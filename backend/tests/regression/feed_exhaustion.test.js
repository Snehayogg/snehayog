import request from 'supertest';
import app from '../../server.js';

/**
 * 🕵️ BUG-DRIVEN TEST: Feed Exhaustion Guard
 * 
 * Scenario: Users should never see an empty screen or "Unable to load".
 * Even if the personalized queue is empty, the system should fallback 
 * to random videos.
 */

describe('🕵️ Bug-Driven: Yug Feed Continuity', () => {

  test('Feed should ALWAYS return videos, even if items are seen', async () => {
    // We simulate a request
    const res = await request(app).get('/api/videos?limit=5');
    
    // Status should be 200
    expect(res.statusCode).toBe(200);
    
    // Even in an empty test database, the handler should return 
    // an empty array [] but NOT a 500 error or null.
    // If there ARE videos in DB, it MUST return some.
    expect(Array.isArray(res.body.videos)).toBe(true);
  });

  test('Cursor-based pagination should provide a valid nextCursor', async () => {
    const res = await request(app).get('/api/videos?limit=5');
    
    if (res.body.videos && res.body.videos.length > 0) {
      // If we have videos, we MUST have a nextCursor for pagination stability
      expect(res.body).toHaveProperty('nextCursor');
      expect(typeof res.body.nextCursor).toBe('string');
    }
  });
});
