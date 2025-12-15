import express from 'express';
import Report from '../models/Report.js';
import jwt from 'jsonwebtoken';
import { OAuth2Client } from 'google-auth-library';
import { config } from '../config.js';
import User from '../models/User.js';

const router = express.Router();

const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID || '406195883653-qp49f9nauq4t428ndscuu3nr9jb10g4h.apps.googleusercontent.com';
const client = new OAuth2Client(GOOGLE_CLIENT_ID);

// **OPTIONAL AUTH MIDDLEWARE: Extract user if token present, but don't fail if missing**
const optionalAuth = async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    if (authHeader && authHeader.startsWith('Bearer ')) {
      const token = authHeader.substring(7);
      
      // Try to verify token and set req.user, but don't fail if invalid
      try {
        // Try JWT first (most common)
        const JWT_SECRET = process.env.JWT_SECRET || config.auth.jwtSecret;
        try {
          const decoded = jwt.verify(token, JWT_SECRET);
          if (decoded && decoded.id) {
            // Find user by googleId or _id
            const user = await User.findOne({ 
              $or: [
                { googleId: decoded.id },
                { _id: decoded.id }
              ]
            });
            if (user) {
              req.user = {
                id: user._id.toString(),
                googleId: user.googleId,
                _id: user._id
              };
              console.log('✅ Report route: User authenticated via JWT:', req.user.googleId);
              return next();
            }
          }
        } catch (jwtError) {
          // JWT failed, try other methods
        }
        
        // Try Google access token
        try {
          const response = await fetch(`https://www.googleapis.com/oauth2/v2/userinfo?access_token=${token}`);
          if (response.ok) {
            const userInfo = await response.json();
            const user = await User.findOne({ googleId: userInfo.id });
            if (user) {
              req.user = {
                id: user._id.toString(),
                googleId: user.googleId,
                _id: user._id
              };
              console.log('✅ Report route: User authenticated via Google access token:', req.user.googleId);
              return next();
            }
          }
        } catch (googleError) {
          // Google access token failed, try ID token
        }
        
        // Try Google ID token
        try {
          const ticket = await client.verifyIdToken({
            idToken: token,
            audience: GOOGLE_CLIENT_ID,
          });
          const payload = ticket.getPayload();
          const user = await User.findOne({ googleId: payload.sub });
          if (user) {
            req.user = {
              id: user._id.toString(),
              googleId: user.googleId,
              _id: user._id
            };
            console.log('✅ Report route: User authenticated via Google ID token:', req.user.googleId);
            return next();
          }
        } catch (idTokenError) {
          // All methods failed - continue as anonymous
        }
        
        console.log('⚠️ Report route: Token verification failed, proceeding as anonymous');
      } catch (err) {
        console.log('⚠️ Report route: Token error, proceeding as anonymous:', err.message);
      }
    }
    next();
  } catch (error) {
    // Continue without auth on any error
    console.log('⚠️ Report route: Auth middleware error, proceeding as anonymous:', error.message);
    next();
  }
};

// Submit a report (auth optional; will attach userId if token present)
router.post('/', optionalAuth, async (req, res) => {
  try {
    const { targetType, targetId, reason, details } = req.body || {};

    if (!targetType || !targetId || !reason) {
      return res.status(400).json({ success: false, error: 'Missing required fields' });
    }

    // Extract user ID from req.user if available
    let userId = null;
    if (req.user) {
      userId = req.user.id || req.user.googleId || req.user._id?.toString() || null;
    }

    console.log('📝 Submitting report:', { targetType, targetId, reason, userId: userId || 'anonymous' });

    const report = new Report({
      targetType: String(targetType).toLowerCase(),
      targetId: String(targetId),
      reason: String(reason).toLowerCase(),
      details: details ? String(details) : undefined,
      userId: userId,
      userAgent: req.get('User-Agent') || '',
      ipAddress: req.ip || req.connection?.remoteAddress || '',
    });

    await report.save();

    console.log('✅ Report submitted successfully:', report._id);
    res.status(201).json({ success: true, message: 'Report submitted', reportId: report._id });
  } catch (error) {
    console.error('❌ Error submitting report:', error);
    res.status(500).json({ success: false, error: 'Failed to submit report', details: error.message });
  }
});

// Optional: List reports for admin (basic, can be expanded later)
router.get('/', async (req, res) => {
  try {
    const { status, targetType, limit = 100 } = req.query;
    const query = {};
    if (status) query.status = status;
    if (targetType) query.targetType = String(targetType).toLowerCase();
    const items = await Report.find(query).sort({ createdAt: -1 }).limit(Math.min(parseInt(limit) || 100, 500));
    res.json({ success: true, count: items.length, reports: items });
  } catch (error) {
    console.error('❌ Error fetching reports:', error);
    res.status(500).json({ success: false, error: 'Failed to fetch reports' });
  }
});

export default router;


