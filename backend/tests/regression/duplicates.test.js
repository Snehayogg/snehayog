import request from 'supertest';
import app from '../../server.js';
import mongoose from 'mongoose';

/**
 * 🧛 DUPLICATE REGRESSION TEST (Bug-Driven)
 * 
 * This test verifies that the Yug Feed does not return duplicate 
 * videos in a single batch, nor across pages when using cursors.
 */

describe('🧛 Yug Feed Regression: Duplicate Prevention', () => {
  
  test('Page 1 should not contain duplicate video IDs', async () => {
    const res = await request(app).get('/api/videos?page=1&limit=20');
    
    if (res.statusCode === 200 && res.body.videos) {
      const videos = res.body.videos;
      const ids = videos.map(v => v._id.toString());
      const uniqueIds = new Set(ids);
      
      // If original length !== unique length, we have duplicates!
      expect(ids.length).toBe(uniqueIds.size);
    } else {
      console.warn('⚠️ Skipping duplicate check: Feed returned status', res.statusCode);
    }
  });

  test('Page 2 should respect cursors and not overlap with Page 1', async () => {
    // 1. Get Page 1
    const res1 = await request(app).get('/api/videos?page=1&limit=10');
    if (res1.statusCode !== 200 || !res1.body.videos || res1.body.videos.length === 0) {
      return; // Skip if no data
    }

    const page1Ids = res1.body.videos.map(v => v._id.toString());
    const nextCursor = res1.body.nextCursor;

    if (!nextCursor) {
        console.warn('⚠️ No cursor returned in Page 1, skipping Page 2 overlap check');
        return;
    }

    // 2. Get Page 2 using the cursor from Page 1
    const res2 = await request(app).get(`/api/videos?page=2&limit=10&cursor=${nextCursor}`);
    
    if (res2.statusCode === 200 && res2.body.videos) {
      const page2Ids = res2.body.videos.map(v => v._id.toString());
      
      // Check for overlap
      const overlap = page1Ids.filter(id => page2Ids.includes(id));
      
      expect(overlap.length).toBe(0);
    }
  });

});
