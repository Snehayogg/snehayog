import dotenv from 'dotenv';
import jwt from 'jsonwebtoken';
import { OAuth2Client } from 'google-auth-library';

dotenv.config();

// Ensure we're using the correct Google Client ID
const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID || '406195883653-qp49f9nauq4t428ndscuu3nr9jb10g4h.apps.googleusercontent.com';
console.log('🔍 Using Google Client ID:', GOOGLE_CLIENT_ID.substring(0, 20) + '...');
const client = new OAuth2Client(GOOGLE_CLIENT_ID);

export const verifyGoogleToken = async (idToken) => {
    const ticket = await client.verifyIdToken({
        idToken,
        audience: GOOGLE_CLIENT_ID,
    });
    const payload = ticket.getPayload();
    return payload;
};

export const generateJWT = (userId) => {
    const JWT_SECRET = process.env.JWT_SECRET || 'hT7#bY29!sK8@Lp$9vRn*qX2mNe%zW13';
    console.log('🔍 Using JWT_SECRET:', JWT_SECRET.substring(0, 10) + '...');
    return jwt.sign({ id: userId }, JWT_SECRET, { expiresIn: '1h' });
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
                    audience: GOOGLE_CLIENT_ID,
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
            const JWT_SECRET = process.env.JWT_SECRET || 'hT7#bY29!sK8@Lp$9vRn*qX2mNe%zW13';
            const decoded = jwt.verify(token, JWT_SECRET);
            req.user = {
                ...decoded,
                googleId: decoded.id // Ensure googleId is set for JWT tokens too
            };
            console.log('✅ JWT token verified successfully for user:', decoded.id);
            console.log('🔍 Full decoded token:', JSON.stringify(decoded, null, 2));
            console.log('🔍 Token user ID type:', typeof decoded.id);
            console.log('🔍 Token user ID value:', decoded.id);
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
