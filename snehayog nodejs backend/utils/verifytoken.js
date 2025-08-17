import dotenv from 'dotenv';
import jwt from 'jsonwebtoken';
import { OAuth2Client } from 'google-auth-library';

dotenv.config();

const client = new OAuth2Client(process.env.GOOGLE_CLIENT_ID);

export const verifyGoogleToken = async (idToken) => {
    const ticket = await client.verifyIdToken({
        idToken,
        audience: process.env.GOOGLE_CLIENT_ID,
    });
    const payload = ticket.getPayload();
    return payload;
};

export const generateJWT = (userId) => {
    return jwt.sign({ id: userId }, process.env.JWT_SECRET, { expiresIn: '1h' });
};

// Middleware to verify Google access token
export const verifyToken = async (req, res, next) => {
    try {
        console.log('🔍 verifyToken middleware called');
        console.log('🔍 Authorization header:', req.headers.authorization);
        
        const token = req.headers.authorization?.split(' ')[1];
        
        if (!token) {
            console.log('❌ No token provided in Authorization header');
            return res.status(401).json({ error: 'Access token required' });
        }

        console.log('🔍 Token extracted:', token.substring(0, 20) + '...');

        // First, try to verify as Google access token using Google People API
        try {
            console.log('🔍 Trying Google access token verification...');
            // Use the token to get user info from Google
            const response = await fetch(`https://www.googleapis.com/oauth2/v2/userinfo?access_token=${token}`);
            
            if (response.ok) {
                const userInfo = await response.json();
                req.user = { 
                    id: userInfo.id, // Google user ID
                    email: userInfo.email,
                    name: userInfo.name
                };
                console.log('✅ Google access token verified successfully for user:', userInfo.id);
                return next();
            } else {
                console.log('❌ Google access token verification failed, trying ID token...');
                throw new Error('Access token verification failed');
            }
        } catch (accessTokenError) {
            console.log('🔍 Access token verification failed, trying ID token...');
            
            // Fallback: try to verify as Google ID token
            try {
                console.log('🔍 Trying Google ID token verification...');
                const ticket = await client.verifyIdToken({
                    idToken: token,
                    audience: process.env.GOOGLE_CLIENT_ID,
                });
                
                const payload = ticket.getPayload();
                req.user = { 
                    id: payload.sub, // Google user ID
                    email: payload.email,
                    name: payload.name
                };
                console.log('✅ Google ID token verified successfully for user:', payload.sub);
                next();
            } catch (idTokenError) {
                console.log('🔍 ID token verification failed, trying JWT...');
                
                // Final fallback: try to verify as JWT token
                try {
                    console.log('🔍 Trying JWT verification...');
                    const decoded = jwt.verify(token, process.env.JWT_SECRET);
                    req.user = decoded;
                    console.log('✅ JWT token verified successfully for user:', decoded.id);
                    next();
                } catch (jwtError) {
                    console.error('❌ All token verification methods failed');
                    console.error('Access token error:', accessTokenError.message);
                    console.error('ID token error:', idTokenError.message);
                    console.error('JWT error:', jwtError.message);
                    return res.status(401).json({ error: 'Invalid or expired token' });
                }
            }
        }
    } catch (error) {
        console.error('❌ Token verification error:', error);
        return res.status(401).json({ error: 'Invalid or expired token' });
    }
};

export default verifyToken;
