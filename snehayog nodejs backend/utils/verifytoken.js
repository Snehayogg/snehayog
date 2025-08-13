import dotenv from 'dotenv';
import jwt from 'jsonwebtoken';
import { OAuth2Client } from 'google-auth-library';

dotenv.config();

const client = new OAuth2Client(process.env.GOOGLE_CLIENT_ID);

const verifyGoogleToken = async (idToken) => {
    const ticket = await client.verifyIdToken({
        idToken,
        audience: process.env.GOOGLE_CLIENT_ID,
    });
    const payload = ticket.getPayload();
    return payload;
};

const generateJWT = (userId) => {
    return jwt.sign({ id: userId }, process.env.JWT_SECRET, { expiresIn: '1h' });
};

// Middleware to verify Google access token
const verifyToken = async (req, res, next) => {
    try {
        const token = req.headers.authorization?.split(' ')[1];
        
        if (!token) {
            return res.status(401).json({ error: 'Access token required' });
        }

        // First, try to verify as Google access token using Google People API
        try {
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
        console.error('Token verification error:', error);
        return res.status(401).json({ error: 'Invalid or expired token' });
    }
};

export { verifyGoogleToken, generateJWT, verifyToken };
export default verifyToken;
