import express from 'express';
import User from '../models/User.js';
import { verifyToken, passiveVerifyToken } from '../utils/verifytoken.js'; // Added passiveVerifyToken
import jwt from 'jsonwebtoken'; // Added for token info endpoint
import redisService from '../services/redisService.js';
import { getGlobalLeaderboard } from '../controllers/videoController.js';
import RecommendationService from '../services/recommendationService.js';

const router = express.Router();

const TOP_EARNERS_CACHE_TTL = 120; // seconds

const getProfileCacheKey = (userId) =>
  userId ? `profile:${userId}` : null;

const getTopEarnersCacheKey = (userId) =>
  userId ? `top_earners_following:${userId}` : null;

const getIsFollowingCacheKey = (currentUserId, targetUserId) =>
  (currentUserId && targetUserId) ? `isfollowing:${currentUserId}:${targetUserId}` : null;

const IS_FOLLOWING_CACHE_TTL = 30; // 30 seconds

const cacheResponse = async (key, data, ttl) => {
  if (!key || !data) return;
  try {
    await redisService.set(key, data, ttl);
  } catch (err) {
    console.error('❌ Redis cache set error:', err.message);
  }
};

const getCachedResponse = async (key) => {
  if (!key) return null;
  try {
    return await redisService.get(key);
  } catch (err) {
    console.error('❌ Redis cache get error:', err.message);
    return null;
  }
};

const invalidateProfileCache = async (userIds) => {
  const ids = Array.isArray(userIds) ? userIds : [userIds];
  for (const id of ids) {
    if (!id) continue;
    const profileKey = getProfileCacheKey(id);
    const topKey = getTopEarnersCacheKey(id);
    try {
      if (profileKey) await redisService.del(profileKey);
      if (topKey) await redisService.del(topKey);
    } catch (err) {
      console.error('❌ Redis cache invalidate error:', err.message);
    }
  }
};

// ✅ Route to register/create user (for Google OAuth)
router.post('/register', async (req, res) => {
  try {
    console.log('🔍 User registration API: Request received');
    console.log('🔍 User registration API: Body:', req.body);
    
    const { googleId, name, email, profilePicture, profilePic } = req.body;
    const profilePictureUrl = profilePicture || profilePic || '';
    
    if (!googleId || !name || !email) {
      return res.status(400).json({ 
        error: 'Missing required fields: googleId, name, email' 
      });
    }
    
    // Check if user already exists
    const existingUser = await User.findOne({ googleId });
    if (existingUser) {
      console.log('✅ User already exists, checking for missing data...');
      
      // **FIXED: Update user profile data if it's missing**
      let needsUpdate = false;
      if (!existingUser.name || existingUser.name.trim() === '') {
        console.log('📝 Updating missing name from Google account');
        existingUser.name = name;
        needsUpdate = true;
      }
      if (!existingUser.profilePic || existingUser.profilePic.trim() === '') {
        console.log('📸 Updating missing profile picture from Google account');
        existingUser.profilePic = profilePictureUrl;
        needsUpdate = true;
      }
      if (needsUpdate) {
        await existingUser.save();
        console.log('✅ User profile updated with Google account data');
      }
      
      return res.json({
        success: true,
        user: {
          _id: existingUser._id,
          googleId: existingUser.googleId,
          name: existingUser.name,
          email: existingUser.email,
          profilePic: existingUser.profilePic,
          profilePicture: existingUser.profilePic, // Keep for backwards compatibility
          isNewUser: false
        }
      });
    }
    
    // Create new user
    const newUser = new User({
      googleId,
      name,
      email,
      profilePic: profilePictureUrl, // Use extracted value
      isActive: true
    });
    
    await newUser.save();
    console.log('✅ New user created successfully');
    
    res.status(201).json({
      success: true,
      user: {
        _id: newUser._id,
        googleId: newUser.googleId,
        name: newUser.name,
        email: newUser.email,
        profilePicture: newUser.profilePic, // **FIXED: Use correct field name**
        isNewUser: true
      }
    });
    
  } catch (error) {
    console.error('❌ Error in user registration:', error);
    res.status(500).json({ 
      error: 'User registration failed', 
      details: error.message 
    });
  }
});

// ✅ Route to get current user profile (requires authentication)
// **IMPORTANT: This must come before /:id route**
// **SECURITY FIX: Disabled caching to prevent data leaks between users**
router.get('/profile', verifyToken, async (req, res) => {
  try {
    const currentUserId = req.user.id; // This is the Google user ID
    
    // Find current user with selective fields and lean query for performance
    const currentUser = await User.findOne({ googleId: currentUserId })
      .select('_id googleId name email profilePic videos following followers preferredCurrency preferredPaymentMethod country')
      .lean();
    
    if (!currentUser) {
      console.log('❌ Profile API: User not found with googleId:', currentUserId);
      return res.status(404).json({ 
        error: 'User not found'
      });
    }
    
    // **SAFE: Wrap rank call so any failure doesn't cause a 500**
    let ownRank = 0;
    try {
      ownRank = await RecommendationService.getGlobalCreatorRank(currentUser._id);
    } catch (rankErr) {
      console.error('⚠️ GET /profile: Failed to get creator rank (non-fatal):', rankErr.message);
    }

    // currentUser is already a plain object due to .lean()
    const payload = {
      _id: currentUser._id,
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
      rank: ownRank,
    };

    res.json(payload);

  } catch (err) {
    console.error('Get profile error:', err);
    res.status(500).json({ error: 'Failed to get profile', details: err.message });
  }
});

// ✅ TEST: Simple test endpoint (no auth) to verify route is accessible
// **IMPORTANT: Must come BEFORE /:id route to avoid route conflicts**
router.get('/top-earners-test', (req, res) => {
  console.log('🧪 TEST: Top Earners test endpoint hit!');
  console.log('🧪 Request URL:', req.originalUrl);
  console.log('🧪 Request method:', req.method);
  res.json({ message: 'Top Earners route is working!', timestamp: new Date().toISOString() });
});

// ✅ Route to get global leaderboard (public)
// Reuses the bulk ranking logic from RecommendationService but masks earnings.
router.get('/leaderboard/global', getGlobalLeaderboard);

// ✅ Route to get top earners from user's following list
router.get('/top-earners-from-following', verifyToken, async (req, res) => {
  try {
    console.log('========================================');
    
    // Try both id and googleId from req.user
    const currentUserId = req.user.id || req.user.googleId;
    console.log('💰 Top Earners API: Current user ID:', currentUserId);
    console.log('💰 Top Earners API: Current user ID type:', typeof currentUserId);

    if (!currentUserId) {
      return res.status(401).json({ error: 'Invalid token - no user ID' });
    }

    // Find current user - try multiple methods
    let currentUser = await User.findOne({ googleId: currentUserId });
    
    if (!currentUser && req.user.email) {
      // Fallback: Try finding by email
      console.log('🔍 Top Earners API: Trying to find user by email:', req.user.email);
      currentUser = await User.findOne({ email: req.user.email });
    }
    
    if (!currentUser) {
      // Try finding by MongoDB _id if currentUserId is ObjectId
      try {
        const mongoose = (await import('mongoose')).default;
        if (mongoose.Types.ObjectId.isValid(currentUserId)) {
          currentUser = await User.findById(currentUserId);
        }
      } catch (e) {
        console.log('⚠️ Top Earners API: Error trying ObjectId lookup:', e);
      }
    }
    
    if (!currentUser) {
      console.log('❌ Top Earners API: User not found');
      console.log('🔍 Top Earners API: Searched with googleId:', currentUserId);
      console.log('🔍 Top Earners API: Searched with email:', req.user.email);
      // Debug: Show sample users
      const sampleUsers = await User.find({}).select('googleId name email').limit(3);
      console.log('🔍 Top Earners API: Sample users in DB:', sampleUsers.map(u => ({ 
        googleId: u.googleId, 
        name: u.name,
        email: u.email
      })));
      return res.status(404).json({ 
        error: 'User not found',
        debug: {
          searchedFor: currentUserId,
          searchedForType: typeof currentUserId,
          searchedEmail: req.user.email
        }
      });
    }
    console.log('✅ Top Earners API: User found:', currentUser.name);

    // Attempt cache
    const topEarnersCacheKey = getTopEarnersCacheKey(currentUser.googleId);
    if (topEarnersCacheKey) {
      const cachedTopEarners = await getCachedResponse(topEarnersCacheKey);
      if (cachedTopEarners) {
        console.log('⚡ Top Earners API: Cache hit for', currentUser.googleId);
        return res.json(cachedTopEarners);
      }
    }

    // Get user's following list (array of ObjectIds)
    const followingIds = currentUser.following || [];
    console.log('💰 Top Earners API: Following IDs:', followingIds);
    console.log('💰 Top Earners API: Following count:', followingIds.length);

    if (followingIds.length === 0) {
      console.log('ℹ️ Top Earners API: User is not following anyone');
      return res.json({ topEarners: [], message: 'Not following anyone' });
    }

    console.log(`💰 Top Earners API: Calculating earnings for ${followingIds.length} users in following list`);

    // Import AdImpression model
    const AdImpression = (await import('../models/AdImpression.js')).default;
    const Video = (await import('../models/Video.js')).default;

    // Get all users that current user is following
    const followingUsers = await User.find({
      _id: { $in: followingIds }
    }).select('googleId name email profilePic');

    if (followingUsers.length === 0) {
      return res.json({ topEarners: [] });
    }

    // Calculate earnings for each user in following list
    const earningsPromises = followingUsers.map(async (user) => {
      try {
        // Get user's videos
        const userVideos = await Video.find({ uploader: user._id }).select('_id');
        const videoIds = userVideos.map(v => v._id);

        if (videoIds.length === 0) {
          return {
            userId: user.googleId,
            name: user.name,
            email: user.email,
            profilePic: user.profilePic || null,
            totalEarnings: 0,
            videoCount: 0
          };
        }

        // Count ad impressions
        const bannerImpressions = await AdImpression.countDocuments({
          videoId: { $in: videoIds },
          adType: 'banner',
          impressionType: 'view'
        });

        const carouselImpressions = await AdImpression.countDocuments({
          videoId: { $in: videoIds },
          adType: 'carousel',
          impressionType: 'view'
        });

        // Calculate revenue (same logic as revenue API)
        const bannerCpm = 10; // ₹10 per 1000 impressions
        const carouselCpm = 30; // ₹30 per 1000 impressions
        
        const bannerRevenueINR = (bannerImpressions / 1000) * bannerCpm;
        const carouselRevenueINR = (carouselImpressions / 1000) * carouselCpm;
        const totalRevenueINR = bannerRevenueINR + carouselRevenueINR;
        const creatorRevenueINR = totalRevenueINR * 0.80; // 80% to creator

        return {
          userId: user.googleId,
          name: user.name,
          email: user.email,
          profilePic: user.profilePic || null,
          totalEarnings: creatorRevenueINR,
          videoCount: videoIds.length,
          bannerImpressions,
          carouselImpressions
        };
      } catch (err) {
        console.error(`❌ Error calculating earnings for user ${user.googleId}:`, err);
        return null;
      }
    });

    // Wait for all calculations
    const earningsResults = await Promise.all(earningsPromises);
    
    // Filter out null results and sort by earnings (descending)
    const topEarners = earningsResults
      .filter(result => result !== null && result.totalEarnings > 0)
      .sort((a, b) => b.totalEarnings - a.totalEarnings)
      .map((earner, index) => ({
        userId: earner.userId,
        name: earner.name,
        profilePic: earner.profilePic,
        rank: index + 1,
        // Hide actual money and impressions for privacy
        totalEarnings: 0, 
        bannerImpressions: 0,
        carouselImpressions: 0,
        videoCount: earner.videoCount
      }));

    console.log(`✅ Top Earners API: Found ${topEarners.length} top earners`);

    const payload = {
      topEarners,
      totalCount: topEarners.length
    };

    res.json(payload);

    if (topEarnersCacheKey) {
      await cacheResponse(topEarnersCacheKey, payload, TOP_EARNERS_CACHE_TTL);
    }
  } catch (err) {
    console.error('❌ Top earners error:', err);
    console.error('❌ Top earners error stack:', err.stack);
    res.status(500).json({ 
      error: 'Failed to get top earners',
      details: err.message 
    });
  }
});

// ✅ Route to get user profile by ID
// **IMPORTANT: This must come AFTER all specific routes**
// **SECURITY FIX: Disabled caching and added privacy filter**
router.get('/:id', passiveVerifyToken, async (req, res) => {
  try {
    const { id } = req.params;
    
    // First try to find by Google ID (primary identifier)
    let user = await User.findOne({ googleId: id });

    // If not found, try by MongoDB ObjectId
    if (!user) {
      try {
        user = await User.findById(id);
      } catch (e) {
        // ignore invalid ObjectId errors
      }
    }

    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // **PRIVACY CHECK**: Check if the requester is the owner of the profile
    const requesterId = req.user?.googleId || req.user?.id;
    const isOwner = requesterId && (requesterId === user.googleId || requesterId === user._id.toString());
    
    console.log(`🔒 Profile Access Check: Requester=${requesterId}, Target=${user.googleId}, IsOwner=${isOwner}`);

    // **SAFE: Wrap rank call so any failure doesn't cause a 500**
    let rank = 0;
    try {
      rank = await RecommendationService.getGlobalCreatorRank(user._id);
    } catch (rankErr) {
      console.error('⚠️ GET /:id: Failed to get creator rank (non-fatal):', rankErr.message);
    }

    const payload = {
      _id: user._id, // MongoDB ObjectID
      id: user.googleId,
      googleId: user.googleId,
      name: user.name,
      profilePic: user.profilePic,
      videos: user.videos,
      following: user.following?.length || 0,
      followers: user.followers?.length || 0,
      rank,
      // **SENSITIVE FIELDS**: Only include if owner
      email: isOwner ? user.email : null,
      preferredCurrency: isOwner ? user.preferredCurrency : null,
      preferredPaymentMethod: isOwner ? user.preferredPaymentMethod : null,
      country: isOwner ? user.country : null,
    };

    res.json(payload);

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

    await invalidateProfileCache(user.googleId);

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

    await invalidateProfileCache([
      currentUser.googleId || currentUserId,
      userToFollow.googleId || userIdToFollow,
    ]);

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

    await invalidateProfileCache([
      currentUser.googleId || currentUserId,
      userToUnfollow.googleId || userIdToUnfollow,
    ]);

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
    // console.log('🔍 IsFollowing API: Request received');
    // console.log('🔍 IsFollowing API: Request params:', req.params);
    // console.log('🔍 IsFollowing API: Current user from token:', req.user);
    
    const { userId } = req.params;
    const currentUserId = req.user.id; // This is now the Google user ID

    // console.log('🔍 IsFollowing API: userId to check:', userId);
    // console.log('🔍 IsFollowing API: currentUserId:', currentUserId);

    if (currentUserId === userId) {
      return res.json({ isFollowing: false });
    }

    const cacheKey = getIsFollowingCacheKey(currentUserId, userId);
    const cachedStatus = await getCachedResponse(cacheKey);
    if (cachedStatus !== null) {
      return res.json(cachedStatus);
    }

    const currentUser = await User.findOne({ googleId: currentUserId });
    if (!currentUser) {
      const response = { isFollowing: false };
      await cacheResponse(cacheKey, response, IS_FOLLOWING_CACHE_TTL);
      return res.json(response);
    }

    const userToCheck = await User.findOne({ googleId: userId });
    if (!userToCheck) {
      const response = { isFollowing: false };
      await cacheResponse(cacheKey, response, IS_FOLLOWING_CACHE_TTL);
      return res.json(response);
    }

    // Check if following by comparing MongoDB ObjectId references
    const isFollowing = currentUser.following.some(
      followingId => followingId.toString() === userToCheck._id.toString()
    );
    
    const response = { isFollowing };
    await cacheResponse(cacheKey, response, IS_FOLLOWING_CACHE_TTL);
    res.json(response);
  } catch (err) {
    console.error('Check follow status error:', err);
    res.status(500).json({ error: 'Failed to check follow status' });
  }
});

// ✅ **OPTIMIZED: Batch check follow status for multiple users in one call**
router.post('/isfollowing/batch', verifyToken, async (req, res) => {
  try {
    const { userIds } = req.body;
    const currentUserId = req.user.id;

    if (!userIds || !Array.isArray(userIds) || userIds.length === 0) {
      return res.json({ statuses: {} });
    }

    // Cap at 50 to prevent abuse
    const limitedIds = userIds.slice(0, 50);

    const currentUser = await User.findOne({ googleId: currentUserId }).select('following').lean();
    if (!currentUser || !currentUser.following || currentUser.following.length === 0) {
      // Not following anyone — all false
      const statuses = {};
      for (const id of limitedIds) { statuses[id] = false; }
      return res.json({ statuses });
    }

    // Find all target users by googleId in one query
    const targetUsers = await User.find({ googleId: { $in: limitedIds } })
      .select('_id googleId')
      .lean();

    // Build a set of followed ObjectIds for O(1) lookup
    const followingSet = new Set(currentUser.following.map(id => id.toString()));

    const statuses = {};
    const targetMap = new Map(targetUsers.map(u => [u.googleId, u._id.toString()]));

    for (const id of limitedIds) {
      const mongoId = targetMap.get(id);
      statuses[id] = mongoId ? followingSet.has(mongoId) : false;
    }

    res.json({ statuses });
  } catch (err) {
    console.error('Batch follow status error:', err);
    res.status(500).json({ error: 'Failed to check batch follow status' });
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

// **NEW: Location Data Endpoints**

// ✅ Route to update user location data
router.post('/update-location', verifyToken, async (req, res) => {
  try {
    console.log('📍 Update Location API: Request received');
    console.log('📍 Update Location API: Request body:', req.body);
    console.log('📍 Update Location API: Current user from token:', req.user);
    
    const { latitude, longitude, address, city, state, country } = req.body;
    const currentUserId = req.user.id; // Google user ID

    console.log('📍 Update Location API: currentUserId:', currentUserId);
    console.log('📍 Update Location API: Location data:', { latitude, longitude, address, city, state, country });

    if (!latitude || !longitude) {
      return res.status(400).json({ error: 'Latitude and longitude are required' });
    }

    // Find current user
    const user = await User.findOne({ googleId: currentUserId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Update location data
    user.location = {
      latitude: parseFloat(latitude),
      longitude: parseFloat(longitude),
      address: address || '',
      city: city || '',
      state: state || '',
      country: country || '',
      lastUpdated: new Date(),
      permissionGranted: true
    };

    await user.save();

    console.log('✅ Update Location API: Location updated successfully');

    res.json({
      message: 'Location updated successfully',
      location: user.location
    });
  } catch (err) {
    console.error('❌ Update location error:', err);
    res.status(500).json({ error: 'Failed to update location' });
  }
});

// ✅ Route to get user location data
router.get('/location', verifyToken, async (req, res) => {
  try {
    console.log('📍 Get Location API: Request received');
    console.log('📍 Get Location API: Current user from token:', req.user);
    
    const currentUserId = req.user.id; // Google user ID

    console.log('📍 Get Location API: currentUserId:', currentUserId);

    // Find current user
    const user = await User.findOne({ googleId: currentUserId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    console.log('📍 Get Location API: User location data:', user.location);

    res.json({
      location: user.location,
      hasLocation: !!(user.location && user.location.latitude && user.location.longitude)
    });
  } catch (err) {
    console.error('❌ Get location error:', err);
    res.status(500).json({ error: 'Failed to get location' });
  }
});

// ✅ Route to check if user has location permission
router.get('/location-permission', verifyToken, async (req, res) => {
  try {
    console.log('📍 Location Permission API: Request received');
    console.log('📍 Location Permission API: Current user from token:', req.user);
    
    const currentUserId = req.user.id; // Google user ID

    console.log('📍 Location Permission API: currentUserId:', currentUserId);

    // Find current user
    const user = await User.findOne({ googleId: currentUserId });
    if (!user) {
      return res.status(404).json({ error: 'User not found' });
    }

    const hasLocationPermission = user.location && user.location.permissionGranted;
    const hasLocationData = user.location && user.location.latitude && user.location.longitude;

    console.log('📍 Location Permission API: Permission status:', { hasLocationPermission, hasLocationData });

    res.json({
      hasLocationPermission,
      hasLocationData,
      needsLocationPermission: !hasLocationPermission,
      needsLocationData: !hasLocationData
    });
  } catch (err) {
    console.error('❌ Get location permission error:', err);
    res.status(500).json({ error: 'Failed to check location permission' });
  }
});

// Duplicate routes removed - moved before /:id route (see line 164)

export default router;
