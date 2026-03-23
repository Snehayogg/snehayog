import axios from 'axios';
import fs from 'fs';
import FormData from 'form-data';
import User from '../models/User.js';

class MetaService {
  /**
   * Upload video to Instagram/Facebook Reels
   * Note: This is an asynchronous process. We upload the video and get a container ID.
   * Then Meta processes it, and we publish it.
   */
  async uploadReel(userId, platform, videoUrl, metadata) {
    try {
      const user = await User.findById(userId);
      if (!user) throw new Error('User not found');

      const account = user.socialAccounts[platform];
      if (!account || !account.connected) {
        throw new Error(`${platform} account not connected`);
      }

      const accessToken = account.accessToken;
      const baseUrl = 'https://graph.facebook.com/v19.0';
      const targetId = platform === 'instagram' ? account.instagramUserId : account.pageId;

      // 1. Initialize the upload (get container ID)
      // For Reels, Meta prefers a public video URL. Since we use R2/Cloudinary, we have one.
      const initUrl = `${baseUrl}/${targetId}/media`;
      const initResponse = await axios.post(initUrl, {
        media_type: 'REELS',
        video_url: videoUrl,
        caption: metadata.caption || '',
        access_token: accessToken
      });

      const containerId = initResponse.data.id;
      console.log(`✅ MetaService: Container ID created for ${platform}: ${containerId}`);

      // 2. Wait for processing (In a real app, we'd use webhooks or poll)
      // For now, we return the container ID and let the worker poll or delay the publish step.
      return {
        success: true,
        containerId,
        platform
      };
    } catch (error) {
      console.error(`❌ MetaService Error (${platform}):`, error.response?.data || error.message);
      throw error;
    }
  }

  /**
   * Publish the uploaded media container
   */
  async publishReel(userId, platform, containerId) {
    try {
      const user = await User.findById(userId);
      const account = user.socialAccounts[platform];
      const accessToken = account.accessToken;
      const targetId = platform === 'instagram' ? account.instagramUserId : account.pageId;

      const publishUrl = `https://graph.facebook.com/v19.0/${targetId}/media_publish`;
      const response = await axios.post(publishUrl, {
        creation_id: containerId,
        access_token: accessToken
      });

      console.log(`✅ MetaService: Reel published to ${platform}!`, response.data.id);
      return {
        success: true,
        postId: response.data.id
      };
    } catch (error) {
      console.error(`❌ MetaService Publish Error (${platform}):`, error.response?.data || error.message);
      throw error;
    }
  }

  /**
   * Poll status of a media container
   */
  async checkStatus(containerId, accessToken) {
    try {
      const statusUrl = `https://graph.facebook.com/v19.0/${containerId}?fields=status_code,status&access_token=${accessToken}`;
      const response = await axios.get(statusUrl);
      return response.data; // status_code: 'FINISHED', 'IN_PROGRESS', 'ERROR'
    } catch (error) {
      console.error('❌ MetaService Status Check Error:', error.response?.data || error.message);
      throw error;
    }
  }
}

export default new MetaService();
