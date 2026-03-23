import { google } from 'googleapis';
import fs from 'fs';
import User from '../../models/User.js';

/**
 * YouTube Data API v3 Service
 */
class YouTubeService {
  constructor() {
    this.oauth2Client = new google.auth.OAuth2(
      process.env.Client_ID,
      process.env.Client_secret
    );
  }

  /**
   * Generate Auth URL for YouTube
   * @param {string} userId - Vayu User ID
   * @param {string} redirectUri - Redirect URI from frontend/env
   */
  getAuthUrl(userId, redirectUri) {
    this.oauth2Client.redirectUri = redirectUri;
    return this.oauth2Client.generateAuthUrl({
      access_type: 'offline',
      scope: [
        'https://www.googleapis.com/auth/youtube.upload',
        'https://www.googleapis.com/auth/youtube.readonly'
      ],
      state: userId, // Pass userId as state to identify user on callback
      prompt: 'consent' // Ensure refresh token is provided
    });
  }

  /**
   * Exchange Auth Code for tokens
   * @param {string} userId - Vayu User ID
   * @param {string} code - Auth code from Google
   * @param {string} redirectUri - Must match the one used in getAuthUrl
   */
  async exchangeCodeForTokens(userId, code, redirectUri) {
    try {
      this.oauth2Client.redirectUri = redirectUri;
      const { tokens } = await this.oauth2Client.getToken(code);
      
      const user = await User.findById(userId);
      if (!user) throw new Error('User not found');

      // Get channel info
      this.oauth2Client.setCredentials(tokens);
      const youtube = google.youtube({ version: 'v3', auth: this.oauth2Client });
      const channelRes = await youtube.channels.list({
        part: 'snippet',
        mine: true
      });

      const channel = channelRes.data.items?.[0];

      // Update user social accounts
      user.socialAccounts.youtube = {
        connected: true,
        accessToken: tokens.access_token,
        refreshToken: tokens.refresh_token || user.socialAccounts.youtube?.refreshToken,
        expiryDate: tokens.expiry_date,
        channelId: channel?.id,
        channelTitle: channel?.snippet?.title
      };

      await user.save();
      return { success: true, channelTitle: channel?.snippet?.title };
    } catch (error) {
      console.error('❌ YouTubeService: Exchange Error:', error.message);
      throw error;
    }
  }

  /**
   * Upload video to YouTube
   * @param {string} userId - Vayu User ID
   * @param {string} filePath - Local path to video file
   * @param {Object} metadata - { title, description, tags, privacyStatus }
   * @param {Function} onProgress - Progress callback (percentage)
   */
  async uploadVideo(userId, filePath, metadata, onProgress = null) {
    try {
      const user = await User.findById(userId);
      if (!user || !user.socialAccounts?.youtube?.connected) {
        throw new Error('YouTube account not connected');
      }

      const { accessToken, refreshToken, expiryDate } = user.socialAccounts.youtube;

      this.oauth2Client.setCredentials({
        access_token: accessToken,
        refresh_token: refreshToken,
        expiry_date: expiryDate
      });

      // Check if token needs refresh
      if (Date.now() >= expiryDate - 60000) {
        console.log('🔄 YouTubeService: Refreshing access token...');
        const { credentials } = await this.oauth2Client.refreshAccessToken();
        
        // Update user tokens
        user.socialAccounts.youtube.accessToken = credentials.access_token;
        user.socialAccounts.youtube.expiryDate = credentials.expiry_date;
        if (credentials.refresh_token) {
          user.socialAccounts.youtube.refreshToken = credentials.refresh_token;
        }
        await user.save();
        this.oauth2Client.setCredentials(credentials);
      }

      const youtube = google.youtube({ version: 'v3', auth: this.oauth2Client });

      const response = await youtube.videos.insert({
        part: 'snippet,status',
        requestBody: {
          snippet: {
            title: metadata.title || 'Uploaded from Vayu',
            description: metadata.description || '',
            tags: metadata.tags || [],
            categoryId: '22', // People & Blogs
          },
          status: {
            privacyStatus: metadata.privacyStatus || 'public',
            selfDeclaredMadeForKids: false,
          },
        },
        media: {
          body: fs.createReadStream(filePath),
        },
      }, {
        onUploadProgress: (evt) => {
          if (onProgress && typeof onProgress === 'function') {
            const stats = fs.statSync(filePath);
            const totalSize = stats.size;
            const progress = Math.round((evt.bytesRead / totalSize) * 100);
            onProgress(progress);
          }
        }
      });

      console.log('✅ YouTubeService: Upload successful!', response.data.id);
      return {
        success: true,
        videoId: response.data.id,
        platformUrl: `https://www.youtube.com/watch?v=${response.data.id}`
      };
    } catch (error) {
      console.error('❌ YouTubeService Error:', error.response?.data || error.message);
      throw error;
    }
  }
}

export default new YouTubeService();
