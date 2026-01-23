import { verifyGoogleToken, generateJWT } from '../utils/verifytoken.js';
import User from '../models/User.js';

export const googleSignIn = async (req, res) => {
  const { idToken, platformId } = req.body; // **NEW: Accept platformId from request

  try {
    const userData = await verifyGoogleToken(idToken);
    
    console.log('🔍 Google Token Verification Debug:');
    console.log('🔍 userData received:', JSON.stringify(userData, null, 2));
    console.log('🔍 userData.sub:', userData.sub);
    console.log('🔍 userData.sub type:', typeof userData.sub);
    console.log('🔍 userData.sub length:', userData.sub ? userData.sub.length : 'null');
    console.log('🔍 Platform ID from request:', platformId);

    // **OPTIMIZED: Select only needed fields for faster query**
    let user = await User.findOne({ googleId: userData.sub })
      .select('googleId name email profilePic deviceIds videos');
    console.log('🔍 Auth Controller: Database lookup result:', user);
    
    let isNewUser = false; // **NEW: Track if user is new**

    if (!user) {
      // Create new user
      console.log('🔍 Auth Controller: Creating new user...');
      isNewUser = true; // **NEW: Set flag**
      user = new User({
        googleId: userData.sub, // Add missing googleId field
        name: userData.name,
        email: userData.email,
        profilePic: userData.picture,
        videos: [], // Include videos field
        deviceIds: platformId ? [platformId] : [], // **NEW: Store platform ID (kept as deviceIds for backward compatibility)
      });
      await user.save();
      console.log('✅ Created new user with profile picture:', userData.picture);
      if (platformId) {
        console.log('✅ Stored platform ID for new user:', platformId.substring(0, 8) + '...');
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
      
      // **NEW: Add platform ID to user's deviceIds array if not already present (kept as deviceIds for backward compatibility)**
      if (platformId && platformId.trim() !== '') {
        if (!user.deviceIds) {
          user.deviceIds = [];
        }
        if (!user.deviceIds.includes(platformId)) {
          user.deviceIds.push(platformId);
          needsSave = true;
          console.log('✅ Added platform ID to user:', platformId.substring(0, 8) + '...');
        } else {
          console.log('ℹ️ Platform ID already registered for this user');
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
        isNewUser: isNewUser // **NEW: Return isNewUser flag**
      },
    });
  } catch (error) {
    console.error('Google Sign-In error:', error);
    res.status(400).json({ error: 'Google SignIn failed', details: error.message });
  }
};

// **NEW: Check if platform ID has logged in before (for skipping login after reinstall)**
export const checkDeviceId = async (req, res) => {
  // Support both platformId (new) and deviceId (legacy) for backward compatibility
  const { platformId, deviceId } = req.body;
  const identifier = platformId || deviceId;

  try {
    if (!identifier || identifier.trim() === '') {
      return res.status(400).json({ 
        error: 'Platform ID is required',
        hasLoggedIn: false 
      });
    }

    console.log('🔍 Check Platform ID: Checking platform:', identifier.substring(0, 8) + '...');

    // Find if any user has this platform ID in their deviceIds array (kept as deviceIds for backward compatibility)
    const user = await User.findOne({ deviceIds: identifier })
      .select('googleId name email profilePic deviceIds');

    if (user) {
      console.log('✅ Platform ID found - user has logged in before:', user.googleId);
      return res.json({
        hasLoggedIn: true,
        userId: user.googleId,
        userName: user.name,
        userEmail: user.email, // **NEW: Return email for seamless auto-login**
        profilePic: user.profilePic // **NEW: Return profile pic**
      });
    } else {
      console.log('ℹ️ Platform ID not found - user has not logged in before');
      return res.json({
        hasLoggedIn: false
      });
    }
  } catch (error) {
    console.error('Check Platform ID error:', error);
    res.status(500).json({ 
      error: 'Failed to check platform ID', 
      details: error.message,
      hasLoggedIn: false 
    });
  }
};
