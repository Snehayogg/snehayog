import { verifyGoogleToken, generateJWT } from '../utils/verifytoken.js';
import User from '../models/User.js';

export const googleSignIn = async (req, res) => {
  const { idToken, deviceId } = req.body; // **NEW: Accept deviceId from request

  try {
    const userData = await verifyGoogleToken(idToken);
    
    console.log('🔍 Google Token Verification Debug:');
    console.log('🔍 userData received:', JSON.stringify(userData, null, 2));
    console.log('🔍 userData.sub:', userData.sub);
    console.log('🔍 userData.sub type:', typeof userData.sub);
    console.log('🔍 userData.sub length:', userData.sub ? userData.sub.length : 'null');
    console.log('🔍 Device ID from request:', deviceId);

    let user = await User.findOne({ googleId: userData.sub });
    console.log('🔍 Auth Controller: Database lookup result:', user);
    
    if (!user) {
      // Create new user
      console.log('🔍 Auth Controller: Creating new user...');
      user = new User({
        googleId: userData.sub, // Add missing googleId field
        name: userData.name,
        email: userData.email,
        profilePic: userData.picture,
        videos: [], // Include videos field
        deviceIds: deviceId ? [deviceId] : [], // **NEW: Store device ID
      });
      await user.save();
      console.log('✅ Created new user with profile picture:', userData.picture);
      if (deviceId) {
        console.log('✅ Stored device ID for new user:', deviceId.substring(0, 8) + '...');
      }
      console.log('🔍 Auth Controller: New user saved:', JSON.stringify(user, null, 2));
    } else {
      // Update existing user's profile picture if they don't have one
      console.log('🔍 Auth Controller: Found existing user:', JSON.stringify(user, null, 2));
      let needsSave = false;
      
      if (!user.profilePic || user.profilePic.trim() === '') {
        user.profilePic = userData.picture;
        needsSave = true;
        console.log('✅ Updated existing user profile picture:', userData.picture);
      }
      
      // **NEW: Add device ID to user's deviceIds array if not already present**
      if (deviceId && deviceId.trim() !== '') {
        if (!user.deviceIds) {
          user.deviceIds = [];
        }
        if (!user.deviceIds.includes(deviceId)) {
          user.deviceIds.push(deviceId);
          needsSave = true;
          console.log('✅ Added device ID to user:', deviceId.substring(0, 8) + '...');
        } else {
          console.log('ℹ️ Device ID already registered for this user');
        }
      }
      
      if (needsSave) {
        await user.save();
      }
    }

    // **FIXED: Generate JWT with Google ID instead of MongoDB ObjectId**
    console.log('🔍 Auth Controller Debug:');
    console.log('🔍 User object:', JSON.stringify(user, null, 2));
    console.log('🔍 user.googleId:', user.googleId);
    console.log('🔍 user.googleId type:', typeof user.googleId);
    console.log('🔍 user.googleId length:', user.googleId ? user.googleId.length : 'null');
    
    const token = generateJWT(user.googleId);
    
    console.log('🔍 Generated token (first 50 chars):', token.substring(0, 50) + '...');

    res.json({
      token,
      user: {
        id: user.googleId, // **FIXED: Return Google ID as the main ID**
        _id: user._id, // **NEW: Include MongoDB ObjectId for reference**
        googleId: user.googleId,
        name: user.name,
        email: user.email,
        profilePic: user.profilePic,
        videos: user.videos,
      },
    });
  } catch (error) {
    console.error('Google Sign-In error:', error);
    res.status(400).json({ error: 'Google SignIn failed', details: error.message });
  }
};

// **NEW: Check if device ID has logged in before (for skipping login after reinstall)**
export const checkDeviceId = async (req, res) => {
  const { deviceId } = req.body;

  try {
    if (!deviceId || deviceId.trim() === '') {
      return res.status(400).json({ 
        error: 'Device ID is required',
        hasLoggedIn: false 
      });
    }

    console.log('🔍 Check Device ID: Checking device:', deviceId.substring(0, 8) + '...');

    // Find if any user has this device ID in their deviceIds array
    const user = await User.findOne({ deviceIds: deviceId });

    if (user) {
      console.log('✅ Device ID found - user has logged in before:', user.googleId);
      return res.json({
        hasLoggedIn: true,
        userId: user.googleId,
        userName: user.name
      });
    } else {
      console.log('ℹ️ Device ID not found - user has not logged in before');
      return res.json({
        hasLoggedIn: false
      });
    }
  } catch (error) {
    console.error('Check Device ID error:', error);
    res.status(500).json({ 
      error: 'Failed to check device ID', 
      details: error.message,
      hasLoggedIn: false 
    });
  }
};
