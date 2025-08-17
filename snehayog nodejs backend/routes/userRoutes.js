import express from 'express';
import User from '../models/User.js';
import { verifyToken } from '../utils/verifytoken.js';
import jwt from 'jsonwebtoken'; // Added for token info endpoint
const router = express.Router();

// ✅ Route to get current user profile (requires authentication)
// **IMPORTANT: This must come before /:id route**
router.get('/profile', verifyToken, async (req, res) => {
  try {
    console.log('🔍 Profile API: Request received');
    console.log('🔍 Profile API: Current user from token:', req.user);
    
    const currentUserId = req.user.id; // This is the Google user ID
    
    console.log('🔍 Profile API: currentUserId:', currentUserId);
    
    // Find current user
    const currentUser = await User.findOne({ googleId: currentUserId });
    if (!currentUser) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    res.json({
      id: currentUser.googleId,
      googleId: currentUser.googleId,
      name: currentUser.name,
      email: currentUser.email,
      profilePic: currentUser.profilePic,
      videos: currentUser.videos,
      following: currentUser.following?.length || 0,
      followers: currentUser.followers?.length || 0,
      preferredCurrency: currentUser.preferredCurrency,
      preferredPaymentMethod: currentUser.preferredPaymentMethod,
      country: currentUser.country,
    });
  } catch (err) {
    console.error('Get profile error:', err);
    res.status(500).json({ error: 'Failed to get profile' });
  }
});

// ✅ Route to get user profile by ID
router.get('/:id', async (req, res) => {
  try {
    const { id } = req.params;
    const user = await User.findOne({ googleId: id });
    
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }
    
    res.json({
      id: user.googleId,
      name: user.name,
      email: user.email,
      profilePic: user.profilePic,
      videos: user.videos,
      following: user.following?.length || 0,
      followers: user.followers?.length || 0,
    });
  } catch (err) {
    console.error('Get user by ID error:', err);
    res.status(500).json({ error: 'Failed to get user' });
  }
});

// ✅ Route to update user profile (name and profilePic)
router.post('/update-profile', async (req, res) => {
  try {
    const { googleId, name, profilePic } = req.body;
    
    if (!googleId || !name) {
      return res.status(400).json({ error: 'Google ID and name are required' });
    }

    const user = await User.findOne({ googleId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Update user fields
    user.name = name;
    if (profilePic) {
      user.profilePic = profilePic;
    }

    await user.save();

    res.json({ 
      message: 'Profile updated successfully',
      user: {
        id: user._id,
        name: user.name,
        profilePic: user.profilePic,
        email: user.email
      }
    });
  } catch (err) {
    console.error('Update profile error:', err);
    res.status(500).json({ error: 'Failed to update profile' });
  }
});

// ✅ Route to follow a user
router.post('/follow', verifyToken, async (req, res) => {
  try {
    console.log('🔍 Follow API: Request received');
    console.log('🔍 Follow API: Request body:', req.body);
    console.log('🔍 Follow API: Current user from token:', req.user);
    
    const { userIdToFollow } = req.body;
    const currentUserId = req.user.id; // This is now the Google user ID

    console.log('🔍 Follow API: userIdToFollow:', userIdToFollow);
    console.log('🔍 Follow API: currentUserId:', currentUserId);

    if (!userIdToFollow) {
      return res.status(400).json({ error: 'User ID to follow is required' });
    }

    if (currentUserId === userIdToFollow) {
      return res.status(400).json({ error: 'Cannot follow yourself' });
    }

    // Find or create current user
    let currentUser = await User.findOne({ googleId: currentUserId });
    if (!currentUser) {
      // Create user if they don't exist
      currentUser = new User({
        googleId: currentUserId,
        name: req.user.name || 'Unknown User',
        email: req.user.email || '',
        following: [],
        followers: []
      });
      await currentUser.save();
    }

    // Find or create user to follow
    let userToFollow = await User.findOne({ googleId: userIdToFollow });
    if (!userToFollow) {
      // Create user if they don't exist
      userToFollow = new User({
        googleId: userIdToFollow,
        name: 'Unknown User',
        email: '',
        following: [],
        followers: []
      });
      await userToFollow.save();
    }

    // Check if already following
    if (currentUser.following.includes(userToFollow._id)) {
      return res.status(400).json({ error: 'Already following this user' });
    }

    // Add to following list (store MongoDB ObjectId reference)
    currentUser.following.push(userToFollow._id);
    await currentUser.save();

    // Add to followers list (store MongoDB ObjectId reference)
    userToFollow.followers.push(currentUser._id);
    await userToFollow.save();

    res.json({ 
      message: 'Successfully followed user',
      following: currentUser.following.length,
      followers: userToFollow.followers.length
    });
  } catch (err) {
    console.error('Follow user error:', err);
    res.status(500).json({ error: 'Failed to follow user' });
  }
});

// ✅ Route to unfollow a user
router.post('/unfollow', verifyToken, async (req, res) => {
  try {
    console.log('🔍 Unfollow API: Request received');
    console.log('🔍 Unfollow API: Request body:', req.body);
    console.log('🔍 Unfollow API: Current user from token:', req.user);
    
    const { userIdToUnfollow } = req.body;
    const currentUserId = req.user.id; // This is now the Google user ID

    console.log('🔍 Unfollow API: userIdToUnfollow:', userIdToUnfollow);
    console.log('🔍 Unfollow API: currentUserId:', currentUserId);

    if (!userIdToUnfollow) {
      return res.status(400).json({ error: 'User ID to unfollow is required' });
    }

    if (currentUserId === userIdToUnfollow) {
      return res.status(400).json({ error: 'Cannot unfollow yourself' });
    }

    // Find current user
    let currentUser = await User.findOne({ googleId: currentUserId });
    if (!currentUser) {
      return res.status(404).json({ error: 'Current user not found' });
    }

    // Find user to unfollow
    let userToUnfollow = await User.findOne({ googleId: userIdToUnfollow });
    if (!userToUnfollow) {
      return res.status(404).json({ error: 'User to unfollow not found' });
    }

    // Check if not following
    if (!currentUser.following.includes(userToUnfollow._id)) {
      return res.status(400).json({ error: 'Not following this user' });
    }

    // Remove from following list (remove MongoDB ObjectId reference)
    currentUser.following = currentUser.following.filter(
      id => id.toString() !== userToUnfollow._id.toString()
    );
    await currentUser.save();

    // Remove from followers list (remove MongoDB ObjectId reference)
    userToUnfollow.followers = userToUnfollow.followers.filter(
      id => id.toString() !== currentUser._id.toString()
    );
    await userToUnfollow.save();

    res.json({ 
      message: 'Successfully unfollowed user',
      following: currentUser.following.length,
      followers: userToUnfollow.followers.length
    });
  } catch (err) {
    console.error('Unfollow user error:', err);
    res.status(500).json({ error: 'Failed to unfollow user' });
  }
});

// ✅ Route to check if current user is following another user
router.get('/isfollowing/:userId', verifyToken, async (req, res) => {
  try {
    console.log('🔍 IsFollowing API: Request received');
    console.log('🔍 IsFollowing API: Request params:', req.params);
    console.log('🔍 IsFollowing API: Current user from token:', req.user);
    
    const { userId } = req.params;
    const currentUserId = req.user.id; // This is now the Google user ID

    console.log('🔍 IsFollowing API: userId to check:', userId);
    console.log('🔍 IsFollowing API: currentUserId:', currentUserId);

    if (currentUserId === userId) {
      return res.json({ isFollowing: false });
    }

    const currentUser = await User.findOne({ googleId: currentUserId });
    if (!currentUser) {
      return res.json({ isFollowing: false });
    }

    const userToCheck = await User.findOne({ googleId: userId });
    if (!userToCheck) {
      return res.json({ isFollowing: false });
    }

    // Check if following by comparing MongoDB ObjectId references
    const isFollowing = currentUser.following.some(
      followingId => followingId.toString() === userToCheck._id.toString()
    );
    
    res.json({ isFollowing });
  } catch (err) {
    console.error('Check follow status error:', err);
    res.status(500).json({ error: 'Failed to check follow status' });
  }
});

// **NEW: JWT Token validation endpoint (for debugging)**
router.get('/validate-token', verifyToken, async (req, res) => {
  try {
    console.log('🔍 Token validation request received');
    console.log('🔍 User from token:', req.user);
    
    res.json({
      valid: true,
      user: req.user,
      message: 'Token is valid',
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    console.error('❌ Token validation error:', err);
    res.status(401).json({ 
      valid: false, 
      error: 'Invalid token',
      timestamp: new Date().toISOString()
    });
  }
});

// **NEW: JWT Token info endpoint (for debugging)**
router.get('/token-info', async (req, res) => {
  try {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return res.status(401).json({ error: 'Bearer token required' });
    }
    
    const token = authHeader.split(' ')[1];
    console.log('🔍 Token info request for token:', token.substring(0, 20) + '...');
    
    // Decode JWT without verification (for info only)
    const decoded = jwt.decode(token);
    if (!decoded) {
      return res.status(400).json({ error: 'Invalid token format' });
    }
    
    const now = Math.floor(Date.now() / 1000);
    const isExpired = decoded.exp && decoded.exp < now;
    const expiresIn = decoded.exp ? decoded.exp - now : null;
    
    res.json({
      tokenInfo: {
        userId: decoded.id,
        issuedAt: decoded.iat ? new Date(decoded.iat * 1000).toISOString() : null,
        expiresAt: decoded.exp ? new Date(decoded.exp * 1000).toISOString() : null,
        isExpired: isExpired,
        expiresInSeconds: expiresIn,
        expiresInMinutes: expiresIn ? Math.floor(expiresIn / 60) : null,
        tokenType: 'JWT'
      },
      timestamp: new Date().toISOString()
    });
  } catch (err) {
    console.error('❌ Token info error:', err);
    res.status(500).json({ error: 'Failed to decode token' });
  }
});

export default router;
