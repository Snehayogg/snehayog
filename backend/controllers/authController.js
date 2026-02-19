import { verifyGoogleToken, generateJWT } from '../utils/verifytoken.js';
import User from '../models/User.js';
import RefreshToken from '../models/RefreshToken.js';

/**
 * Google Sign-In (First Time / Re-authentication)
 * Verifies Google ID Token, creates/finds user, issues device-bound tokens
 */
export const googleSignIn = async (req, res) => {
  const { idToken, deviceId, deviceName, platform } = req.body;

  try {
    if (!idToken) {
      return res.status(400).json({ error: 'Google ID Token is required' });
    }

    if (!deviceId || deviceId.trim() === '') {
      return res.status(400).json({ error: 'Device ID is required' });
    }

    // Verify Google ID Token
    const userData = await verifyGoogleToken(idToken);
    console.log('🔐 Google Sign-In: Verified user:', userData.email);

    // Find or create user
    let user = await User.findOne({ googleId: userData.sub })
      .select('googleId name email profilePic videos');
    
    let isNewUser = false;

    if (!user) {
      isNewUser = true;
      user = new User({
        googleId: userData.sub,
        name: userData.name,
        email: userData.email,
        profilePic: userData.picture,
        videos: [],
      });
      await user.save();
      console.log('✅ Created new user:', user.email);
    } else {
      // Update profile pic if missing
      if (!user.profilePic || user.profilePic.trim() === '') {
        user.profilePic = userData.picture;
        await user.save();
      }
      console.log('✅ Found existing user:', user.email);
    }

    // Generate Access Token (JWT, 1 hour)
    const accessToken = generateJWT(user.googleId, '1h');

    // Generate Device-Bound Refresh Token (stored in MongoDB)
    const refreshToken = await RefreshToken.createForDevice(
      user._id,
      deviceId,
      deviceName || 'Unknown Device',
      platform || 'unknown'
    );

    console.log('🔐 Issued tokens for device:', deviceId.substring(0, 8) + '...');

    res.json({
      accessToken,
      refreshToken,
      user: {
        id: user.googleId,
        _id: user._id,
        googleId: user.googleId,
        name: user.name,
        email: user.email,
        profilePic: user.profilePic,
        videos: user.videos,
        isNewUser
      }
    });

  } catch (error) {
    console.error('❌ Google Sign-In error:', error);
    res.status(400).json({ error: 'Google Sign-In failed', details: error.message });
  }
};

/**
 * Device Login (Auto-login after app reinstall)
 * Uses device ID to find existing session and issue new tokens
 */
export const deviceLogin = async (req, res) => {
  res.status(410).json({ error: 'Device login is no longer supported. Please use Google Sign-In.' });
};
/*
export const deviceLogin = async (req, res) => {
  const { deviceId } = req.body;
  // ... (rest of the code)
};
*/

/**
 * Refresh Access Token
 * Uses refresh token + device ID to issue new tokens
 */
export const refreshAccessToken = async (req, res) => {
  const { refreshToken, deviceId } = req.body;

  try {
    if (!refreshToken) {
      return res.status(401).json({ error: 'Refresh token required' });
    }

    if (!deviceId) {
      return res.status(400).json({ error: 'Device ID required' });
    }

    // Verify and rotate refresh token
    const result = await RefreshToken.verifyAndRotate(refreshToken, deviceId);

    if (!result) {
      console.log('❌ Invalid or expired refresh token');
      return res.status(403).json({ 
        error: 'Invalid or expired refresh token',
        requiresLogin: true 
      });
    }

    const { newToken: newRefreshToken, user } = result;

    // Generate new Access Token
    const accessToken = generateJWT(user.googleId, '1h');

    console.log('✅ Token refreshed for:', user.email);

    res.json({
      accessToken,
      refreshToken: newRefreshToken
    });

  } catch (error) {
    console.error('❌ Refresh token error:', error);
    res.status(500).json({ error: 'Failed to refresh token' });
  }
};

/**
 * Logout (Current Device)
 * Revokes refresh token for the current device
 */
export const logout = async (req, res) => {
  const { deviceId } = req.body;
  const googleId = req.user?.googleId;

  try {
    if (!googleId) {
      return res.status(401).json({ error: 'Not authenticated' });
    }

    const user = await User.findOne({ googleId }).select('_id');
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    if (deviceId) {
      const count = await RefreshToken.revokeForDevice(user._id, deviceId);
      console.log(`✅ Revoked ${count} token(s) for device`);
    }

    res.json({ success: true, message: 'Logged out successfully' });

  } catch (error) {
    console.error('❌ Logout error:', error);
    res.status(500).json({ error: 'Logout failed' });
  }
};

/**
 * Logout All Devices
 * Revokes all refresh tokens for the user
 */
export const logoutAllDevices = async (req, res) => {
  const googleId = req.user?.googleId;

  try {
    if (!googleId) {
      return res.status(401).json({ error: 'Not authenticated' });
    }

    const user = await User.findOne({ googleId }).select('_id');
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const count = await RefreshToken.revokeAllForUser(user._id);
    console.log(`✅ Revoked ${count} token(s) for user ${googleId}`);

    res.json({ success: true, message: `Logged out from ${count} device(s)` });

  } catch (error) {
    console.error('❌ Logout all error:', error);
    res.status(500).json({ error: 'Logout failed' });
  }
};

/**
 * Get Active Sessions
 * Returns list of devices with active sessions
 */
export const getActiveSessions = async (req, res) => {
  const googleId = req.user?.googleId;

  try {
    if (!googleId) {
      return res.status(401).json({ error: 'Not authenticated' });
    }

    const user = await User.findOne({ googleId }).select('_id');
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const sessions = await RefreshToken.getActiveSessions(user._id);

    res.json({
      sessions: sessions.map(s => ({
        deviceId: s.deviceId,
        deviceName: s.deviceName,
        platform: s.platform,
        createdAt: s.createdAt,
        lastUsedAt: s.lastUsedAt
      }))
    });

  } catch (error) {
    console.error('❌ Get sessions error:', error);
    res.status(500).json({ error: 'Failed to get sessions' });
  }
};

// Legacy endpoint - kept for backward compatibility during migration
export const checkDeviceId = async (req, res) => {
  const { platformId, deviceId } = req.body;
  const identifier = platformId || deviceId;

  try {
    if (!identifier || identifier.trim() === '') {
      return res.status(400).json({ 
        error: 'Device ID is required',
        hasLoggedIn: false 
      });
    }

    // Check RefreshToken collection first (new system)
    const session = await RefreshToken.findValidSessionByDevice(identifier);
    
    if (session && session.userId) {
      const user = session.userId;
      return res.json({
        hasLoggedIn: true,
        userId: user.googleId,
        userName: user.name,
        userEmail: user.email,
        profilePic: user.profilePic
      });
    }

    // Fallback: Check legacy deviceIds array in User model
    const user = await User.findOne({ deviceIds: identifier })
      .select('googleId name email profilePic');

    if (user) {
      return res.json({
        hasLoggedIn: true,
        userId: user.googleId,
        userName: user.name,
        userEmail: user.email,
        profilePic: user.profilePic
      });
    }

    return res.json({ hasLoggedIn: false });

  } catch (error) {
    console.error('Check Device ID error:', error);
    res.status(500).json({ error: 'Check failed', hasLoggedIn: false });
  }
};
