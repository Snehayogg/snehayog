import dotenv from 'dotenv';
import jwt from 'jsonwebtoken';
import { OAuth2Client } from 'google-auth-library';
import { config } from '../config.js';

dotenv.config();

// Ensure we're using the correct Google Client ID
const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID || '406195883653-qp49f9nauq4t428ndscuu3nr9jb10g4h.apps.googleusercontent.com';
const client = new OAuth2Client(GOOGLE_CLIENT_ID);

export const verifyGoogleToken = async (idToken) => {
    const ticket = await client.verifyIdToken({
        idToken,
        audience: GOOGLE_CLIENT_ID,
    });
    const payload = ticket.getPayload();
    
    return payload;
};

export const generateJWT = (userId, expiresIn = '1h') => {
    const JWT_SECRET = process.env.JWT_SECRET || config.auth.jwtSecret;
    const payload = { id: userId };
    const token = jwt.sign(payload, JWT_SECRET, { expiresIn });
    
    return token;
};

// NOTE: Refresh tokens are now handled by the RefreshToken MongoDB model
// with device-binding and secure hashing. See models/RefreshToken.js

// Verify JWT access token (used internally)
export const verifyJWT = (token) => {
    try {
        const JWT_SECRET = process.env.JWT_SECRET || config.auth.jwtSecret;
        const decoded = jwt.verify(token, JWT_SECRET);
        return decoded;
    } catch (error) {
        return null;
    }
};

// Middleware to verify Google access token
// **OPTIMIZED: Reduced logging - only log errors to prevent log spam**
export const verifyToken = async (req, res, next) => {
    try {
        const token = req.headers.authorization?.split(' ')[1];
        
        if (!token) {
            return res.status(401).json({ error: 'Access token required' });
        }

        // **HIGH-PERFORMANCE AUTH: Check for local JWT first (< 1ms)**
        try {
            const JWT_SECRET = process.env.JWT_SECRET || config.auth.jwtSecret;
            const decoded = jwt.verify(token, JWT_SECRET);
            
            req.user = {
                ...decoded,
                googleId: decoded.id // Ensure googleId is set for JWT tokens
            };
            
            return next(); // Fast-path: Skip Google API call
        } catch (jwtError) {
            // Not a local JWT, fallback to Google verification (slower)
        }

        // Second, try to verify as Google access token using Google People API (850ms+)
        try {
            // Use the token to get user info from Google
            const response = await fetch(`https://www.googleapis.com/oauth2/v2/userinfo?access_token=${token}`);
            
            if (response.ok) {
                const userInfo = await response.json();
                req.user = { 
                    id: userInfo.id, // Google user ID
                    googleId: userInfo.id, // Also store as googleId for clarity
                    email: userInfo.email,
                    name: userInfo.name
                };
                return next();
            } else {
                throw new Error('Access token verification failed');
            }
        } catch (accessTokenError) {
            // Fallback: try to verify as Google ID token
            try {
                const ticket = await client.verifyIdToken({
                    idToken: token,
                    audience: GOOGLE_CLIENT_ID,
                });
                
                const payload = ticket.getPayload();
                req.user = { 
                    id: payload.sub, // Google user ID
                    googleId: payload.sub, // Also store as googleId for clarity
                    email: payload.email,
                    name: payload.name
                };
                next();
            } catch (idTokenError) {
                // All verification methods failed
                console.error('❌ Token verification failed - all methods exhausted');
                return res.status(401).json({ error: 'Invalid or expired token' });
            }
        }
    } catch (error) {
        console.error('❌ Token verification error:', error.message);
        return res.status(401).json({ error: 'Invalid or expired token' });
    }
};


// **NEW: Passive Token Verification**
// Does NOT block request if token is missing/invalid.
// Just tries to set req.user so rate limiter can use it.
export const passiveVerifyToken = async (req, res, next) => {
    try {
        const token = req.headers.authorization?.split(' ')[1];
        
        if (!token) {
            return next(); // No token, just proceed as guest
        }

        // **HIGH-PERFORMANCE AUTH: Local JWT check first**
        try {
            const JWT_SECRET = process.env.JWT_SECRET || config.auth.jwtSecret;
            const decoded = jwt.verify(token, JWT_SECRET);
            req.user = {
                ...decoded,
                googleId: decoded.id
            };
            return next();
        } catch (e) { /* Fallback to Google */ }

        // Try Google Access Token (People API)
        try {
            const response = await fetch(`https://www.googleapis.com/oauth2/v2/userinfo?access_token=${token}`);
            if (response.ok) {
                const userInfo = await response.json();
                req.user = { 
                    id: userInfo.id,
                    googleId: userInfo.id,
                    email: userInfo.email,
                    name: userInfo.name
                };
                return next();
            }
        } catch (e) { /* Ignore */ }

        // Try ID Token
        try {
            const ticket = await client.verifyIdToken({
                idToken: token,
                audience: GOOGLE_CLIENT_ID,
            });
            const payload = ticket.getPayload();
            req.user = { 
                id: payload.sub,
                googleId: payload.sub,
                email: payload.email,
                name: payload.name
            };
            return next();
        } catch (e) { /* Ignore */ }

        // If all fail, just proceed without req.user
        next();

    } catch (error) {
        // Safety net - never block in passive mode
        next();
    }
};

export default verifyToken;
