import { verifyGoogleToken, generateJWT } from '../utils/verifytoken.js';
import User from '../models/User.js';

export const googleSignIn = async (req, res) => {
  const { idToken } = req.body;

  try {
    const userData = await verifyGoogleToken(idToken);

    let user = await User.findOne({ googleId: userData.sub });
    if (!user) {
      // Create new user
      user = new User({
        googleId: userData.sub, // Add missing googleId field
        name: userData.name,
        email: userData.email,
        profilePic: userData.picture,
        videos: [], // Include videos field
      });
      await user.save();
      console.log('✅ Created new user with profile picture:', userData.picture);
    } else {
      // Update existing user's profile picture if they don't have one
      if (!user.profilePic || user.profilePic.trim() === '') {
        user.profilePic = userData.picture;
        await user.save();
        console.log('✅ Updated existing user profile picture:', userData.picture);
      }
    }

    // **FIXED: Generate JWT with Google ID instead of MongoDB ObjectId**
    const token = generateJWT(user.googleId);

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
