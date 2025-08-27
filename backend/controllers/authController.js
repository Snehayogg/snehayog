import { verifyGoogleToken, generateJWT } from '../utils/verifytoken.js';
import User from '../models/User.js';

export const googleSignIn = async (req, res) => {
  const { idToken } = req.body;

  try {
    const userData = await verifyGoogleToken(idToken);
    
    console.log('🔍 Google Token Verification Debug:');
    console.log('🔍 userData received:', JSON.stringify(userData, null, 2));
    console.log('🔍 userData.sub:', userData.sub);
    console.log('🔍 userData.sub type:', typeof userData.sub);
    console.log('🔍 userData.sub length:', userData.sub ? userData.sub.length : 'null');

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
      });
      await user.save();
      console.log('✅ Created new user with profile picture:', userData.picture);
      console.log('🔍 Auth Controller: New user saved:', JSON.stringify(user, null, 2));
    } else {
      // Update existing user's profile picture if they don't have one
      console.log('🔍 Auth Controller: Found existing user:', JSON.stringify(user, null, 2));
      if (!user.profilePic || user.profilePic.trim() === '') {
        user.profilePic = userData.picture;
        await user.save();
        console.log('✅ Updated existing user profile picture:', userData.picture);
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
