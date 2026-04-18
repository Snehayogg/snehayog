import request from 'supertest';
import app from '../server.js';
import mongoose from 'mongoose';

/**
 * 🩺 SMOKE TEST (Pulse Check)
 * 
 * This test verifies that the core backend engine is running.
 * It checks critical health and data routes to ensure no 
 * major breakdowns occur after code changes.
 */

describe('🚀 Backend Smoke Tests', () => {
  
  // 1. Core Health Check
  test('GET /health should return 200 OK', async () => {
    const res = await request(app).get('/health');
    expect(res.statusCode).toEqual(200);
    expect(res.body).toHaveProperty('status', 'OK');
  });

  // 2. API Health Check
  test('GET /api/health should return 200 OK', async () => {
    const res = await request(app).get('/api/health');
    expect(res.statusCode).toEqual(200);
    expect(res.body).toHaveProperty('status', 'OK');
  });

  // 3. Videos Feed Route Check (Public)
  test('GET /api/videos should return videos or empty list (not 500)', async () => {
    const res = await request(app).get('/api/videos?page=1&limit=5');
    // It might return 200 or 401 if auth is strictly required, 
    // but the feed is usually public for the first page.
    expect([200, 401]).toContain(res.statusCode);
  });

});
