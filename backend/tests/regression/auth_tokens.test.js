import request from 'supertest';
import app from '../../server.js';
import User from '../../models/User.js';
import RefreshToken from '../../models/RefreshToken.js';

/**
 * 🔐 AUTH TOKEN REGRESSION TEST
 * 
 * This test verifies the Access/Refresh token lifecycle:
 * 1. Token Refresh (Rotation)
 * 2. Reuse Prevention (Security)
 * 3. Access Control (Protected routes)
 */

describe('🔐 Auth Token Lifecycle & Security', () => {
  let testUser;
  let setupToken;
  const testDeviceId = 'test-device-123';

  beforeAll(async () => {
    // 1. Create a mock test user
    testUser = await User.create({
      googleId: 'test-google-id-' + Date.now(),
      name: 'Test User',
      email: 'test' + Date.now() + '@example.com',
      videos: []
    });

    // 2. Create a manual refresh token for this user
    setupToken = await RefreshToken.createForDevice(
      testUser._id,
      testDeviceId,
      'Test Suite Runner',
      'web'
    );
  });

  test('POST /api/auth/refresh should issue new tokens (Rotation)', async () => {
    const res = await request(app)
      .post('/api/auth/refresh')
      .send({
        refreshToken: setupToken,
        deviceId: testDeviceId
      });

    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty('accessToken');
    expect(res.body).toHaveProperty('refreshToken');
    
    // The new refresh token should be DIFFERENT from the old one (Rotation)
    expect(res.body.refreshToken).not.toBe(setupToken);
    
    // Update our reference for next test
    setupToken = res.body.refreshToken;
  });

  test('POST /api/auth/refresh should FAIL if same token is used twice (Security)', async () => {
    // 1. Use the token once (already done in previous test, but let's do fresh rotation)
    const res1 = await request(app)
      .post('/api/auth/refresh')
      .send({
        refreshToken: setupToken,
        deviceId: testDeviceId
      });
    
    const usedToken = setupToken; // This one is now revoked
    const newToken = res1.body.refreshToken;

    // 2. Try to use 'usedToken' again
    const res2 = await request(app)
      .post('/api/auth/refresh')
      .send({
        refreshToken: usedToken,
        deviceId: testDeviceId
      });

    // Should be Forbidden or Unauthorized because it was revoked
    expect([403, 401]).toContain(res2.statusCode);

    // IMPORTANT: Update setupToken to the valid one for the NEXT test
    setupToken = newToken;
  });

  test('Protected routes should work with the new Access Token', async () => {
    // 1. Refresh to get a fresh Access Token
    const resAuth = await request(app)
      .post('/api/auth/refresh')
      .send({
        refreshToken: setupToken,
        deviceId: testDeviceId
      });
    
    const token = resAuth.body.accessToken;

    // 2. Try to access a protected route (e.g., sessions)
    const resPrivate = await request(app)
      .get('/api/auth/sessions')
      .set('Authorization', `Bearer ${token}`);

    expect(resPrivate.statusCode).toBe(200);
    expect(resPrivate.body).toHaveProperty('sessions');
  });

});
