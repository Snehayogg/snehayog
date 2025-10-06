import dotenv from 'dotenv';
import jwt from 'jsonwebtoken';
import { OAuth2Client } from 'google-auth-library';
import { config } from '../config.js';

dotenv.config();

// Accept multiple OAuth 2.0 Client IDs (Android, iOS, Web)
const parseEnvList = (value) =>
  (value || '')
    .split(',')
    .map((s) => s.trim())
    .filter((s) => s.length > 0);

const ANDROID_CLIENT_IDS = parseEnvList(process.env.GOOGLE_CLIENT_ID_ANDROID) || ['406195883653-c3l6apj3e6ruffil98pq6idirfvknrru.apps.googleusercontent.com'];
const IOS_CLIENT_IDS = parseEnvList(process.env.GOOGLE_CLIENT_ID_IOS) || ['406195883653-j5ek21oa130o1bga6hnhu2r1os624hho.apps.googleusercontent.com'];
const WEB_CLIENT_IDS = parseEnvList(process.env.GOOGLE_CLIENT_ID_WEB) || ['406195883653-qp49f9nauq4t428ndscuu3nr9jb10g4h.apps.googleusercontent.com'];

const ALLOWED_AUDIENCES = [...ANDROID_CLIENT_IDS, ...IOS_CLIENT_IDS, ...WEB_CLIENT_IDS];

console.log('🔍 Allowed Google Client IDs:', ALLOWED_AUDIENCES.map(id => id.substring(0, 20) + '...'));

const client = new OAuth2Client();

export const verifyGoogleToken = async (idToken) => {
    console.log('🔍 verifyGoogleToken Debug:');
    console.log('🔍 Input idToken (first 50 chars):', idToken.substring(0, 50) + '...');
    console.log('🔍 Input idToken length:', idToken.length);
    
    const ticket = await client.verifyIdToken({
        idToken,
        audience: ALLOWED_AUDIENCES,
    });
    const payload = ticket.getPayload();
    
    console.log('🔍 Google token payload extracted:');
    console.log('🔍 payload.sub:', payload.sub);
    console.log('🔍 payload.sub type:', typeof payload.sub);
    console.log('🔍 payload.sub length:', payload.sub ? payload.sub.length : 'null');
    console.log('🔍 Full payload keys:', Object.keys(payload));
    
    return payload;
};

export const generateJWT = (userId) => {
    const JWT_SECRET = process.env.JWT_SECRET || config.auth.jwtSecret;
    console.log('🔍 JWT Generation Debug:');
    console.log('🔍 Input userId:', userId);
    console.log('🔍 Input userId type:', typeof userId);
    console.log('🔍 Input userId length:', userId ? userId.length : 'null');
    console.log('🔍 Input userId trimmed:', userId ? userId.trim() : 'null');
    console.log('🔍 Using JWT_SECRET:', JWT_SECRET.substring(0, 10) + '...');
    
    const payload = { id: userId };
    console.log('🔍 JWT payload being signed:', JSON.stringify(payload, null, 2));
    
    const token = jwt.sign(payload, JWT_SECRET, { expiresIn: '1h' });
    console.log('🔍 Generated JWT token (first 50 chars):', token.substring(0, 50) + '...');
    
    return token;
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
                    googleId: userInfo.id, // Also store as googleId for clarity
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
                    audience: ALLOWED_AUDIENCES,
                });
                
                const payload = ticket.getPayload();
                                        req.user = { 
                            id: payload.sub, // Google user ID
                            googleId: payload.sub, // Also store as googleId for clarity
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
            const JWT_SECRET = process.env.JWT_SECRET || config.auth.jwtSecret;
            const decoded = jwt.verify(token, JWT_SECRET);
            
            console.log('🔍 JWT decoded successfully');
            console.log('🔍 Full decoded token:', JSON.stringify(decoded, null, 2));
            console.log('🔍 Token user ID type:', typeof decoded.id);
            console.log('🔍 Token user ID value:', decoded.id);
            console.log('🔍 Token user ID length:', decoded.id ? decoded.id.length : 'null');
            console.log('🔍 Token user ID trimmed:', decoded.id ? decoded.id.trim() : 'null');
            
            req.user = {
                ...decoded,
                googleId: decoded.id // Ensure googleId is set for JWT tokens too
            };
            
            console.log('✅ JWT token verified successfully for user:', decoded.id);
            console.log('🔍 Final req.user object:', JSON.stringify(req.user, null, 2));
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
