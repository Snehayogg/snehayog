import express from 'express';
import youtubeService from '../services/platforms/youtubeService.js';
import { verifyToken } from '../utils/verifytoken.js';
import User from '../models/User.js';

const router = express.Router();

/**
 * @route GET /api/auth/youtube
 * @desc Start YouTube OAuth flow
 * @access Private
 */
router.get('/youtube', verifyToken, (req, res) => {
  try {
    const userId = req.user.id;
    
    // Determine redirect URI based on host header or environment
    // Use the one configured in Google Console as per user screenshot
    let redirectUri = 'http://localhost:5001/api/auth/youtube/callback';
    
    // In production, use the appropriate domain
    if (req.get('host').includes('snehayog.site')) {
      redirectUri = 'https://api.snehayog.site/api/auth/youtube/callback';
    } else if (req.get('host').includes('vayug.fly.dev')) {
      redirectUri = 'https://vayug.fly.dev/api/auth/youtube/callback';
    }
    
    const authUrl = youtubeService.getAuthUrl(userId, redirectUri);
    res.json({ authUrl });
  } catch (error) {
    res.status(500).json({ error: 'Failed to generate auth URL' });
  }
});

/**
 * @route GET /api/auth/youtube/callback
 * @desc YouTube OAuth callback
 * @access Public (Google redirects here)
 */
router.get('/youtube/callback', async (req, res) => {
  try {
    const { code, state: userId } = req.query;
    
    if (!code || !userId) {
      return res.status(400).send('Missing code or state');
    }

    // Must match the one used in generateAuthUrl
    let redirectUri = 'http://localhost:5001/api/auth/youtube/callback';
    if (req.get('host').includes('snehayog.site')) {
      redirectUri = 'https://api.snehayog.site/api/auth/youtube/callback';
    } else if (req.get('host').includes('vayug.fly.dev')) {
      redirectUri = 'https://vayug.fly.dev/api/auth/youtube/callback';
    }

    await youtubeService.exchangeCodeForTokens(userId, code, redirectUri);

    // Redirect back to app (using deep link)
    res.send(`
      <html>
        <body>
          <h2>YouTube Connected!</h2>
          <p>You can close this window now.</p>
          <script>
            setTimeout(() => {
              window.location.href = 'vayu://auth/social-success?platform=youtube';
            }, 2000);
          </script>
        </body>
      </html>
    `);
  } catch (error) {
    console.error('❌ YouTube Callback Error:', error);
    res.status(500).send('Authentication failed: ' + error.message);
  }
});

export default router;
