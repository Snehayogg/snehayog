/**
 * Video Serializer for API Versioning
 * 
 * This utility ensures that video objects are formatted correctly based on the 
 * requested API version (X-API-Version header).
 */

import cloudflareR2Service from '../../services/uploadServices/cloudflareR2Service.js';
import { logger } from '../../middleware/traceMiddleware.js';

export const serializeVideo = (video, apiVersion, requestingUserObjectId, traceId = 'internal') => {
  if (!video) return null;

  const videoObj = video.toObject ? video.toObject() : video;
  const dubbedUrls =
    videoObj.dubbedUrls instanceof Map
      ? Object.fromEntries(videoObj.dubbedUrls.entries())
      : (videoObj.dubbedUrls || null);
  
  // Calculate isLiked if user ID provided
  let isLiked = videoObj.isLiked || false;
  if (requestingUserObjectId && videoObj.likedBy) {
    const userObjectIdStr = requestingUserObjectId.toString();
    isLiked = videoObj.likedBy.some(id => id.toString() === userObjectIdStr);
  }

  // Base transformation (common for all versions)
  const base = {
    _id: videoObj._id?.toString(),
    videoName: videoObj.videoName || 'Untitled Video',
    videoUrl: cloudflareR2Service.getPublicUrl(videoObj.videoUrl || videoObj.hlsMasterPlaylistUrl || videoObj.hlsPlaylistUrl || ''),
    thumbnailUrl: cloudflareR2Service.getPublicUrl(videoObj.thumbnailUrl || ''),
    description: videoObj.description || '',
    likes: parseInt(videoObj.likes) || 0,
    views: parseInt(videoObj.views) || 0,
    shares: parseInt(videoObj.shares) || 0,
    duration: parseInt(videoObj.duration) || 0,
    aspectRatio: parseFloat(videoObj.aspectRatio) || 9 / 16,
    videoType: videoObj.videoType || 'yog',
    mediaType: videoObj.mediaType || 'video',
    link: videoObj.link || null,
    uploadedAt: videoObj.uploadedAt?.toISOString ? videoObj.uploadedAt.toISOString() : videoObj.uploadedAt,
    isLiked: isLiked,
    earnings: parseFloat(videoObj.earnings) || 0.0,
    hlsPlaylistUrl: cloudflareR2Service.getPublicUrl(videoObj.hlsPlaylistUrl || ''),
    lowQualityUrl: cloudflareR2Service.getPublicUrl(videoObj.lowQualityUrl || ''),
    seriesId: videoObj.seriesId || null,
    episodeNumber: videoObj.episodeNumber || 0,
    episodes: videoObj.episodes || [],
    dubbedUrls: dubbedUrls,
    quizzes: videoObj.quizzes || []
  };

  if (base.quizzes.length > 0) {
    logger.info(traceId, 'Serialized video with quizzes', { videoId: base._id, quizCount: base.quizzes.length });
  }

  /**
   * VERSION SPECIFIC LOGIC
   */
  
  // Baseline behavior for all versions up to and including 2026-04-02
  // Date-based versions compare correctly as strings (YYYY-MM-DD).
  if (!apiVersion || apiVersion <= '2026-04-02') {
    base.uploader = {
      id: videoObj.uploader?.googleId?.toString() || videoObj.uploader?._id?.toString() || '',
      _id: videoObj.uploader?._id?.toString() || '',
      googleId: videoObj.uploader?.googleId?.toString() || '',
      name: videoObj.uploader?.name || 'Unknown User',
      profilePic: videoObj.uploader?.profilePic || '',
      earnings: parseFloat(videoObj.uploader?.earnings) || 0.0
    };
    
    base.hlsMasterPlaylistUrl = cloudflareR2Service.getPublicUrl(videoObj.hlsMasterPlaylistUrl || '');
    
    // **ROBUST HLS CHECK**: If either URL contains .m3u8, it is HLS encoded
    base.isHLSEncoded = videoObj.isHLSEncoded === true || 
                       base.videoUrl.includes('.m3u8') || 
                       (base.hlsPlaylistUrl && base.hlsPlaylistUrl.includes('.m3u8')) ||
                       (base.hlsMasterPlaylistUrl && base.hlsMasterPlaylistUrl.includes('.m3u8'));
    
    return base;
  }

  // Future Versions can be added here
  // if (apiVersion >= '2026-01-26') { ... }

  return base;
};

export const serializeVideos = (videos, apiVersion, requestingUserObjectId, traceId = 'internal') => {
  if (!Array.isArray(videos)) return [];
  return videos.map(v => serializeVideo(v, apiVersion, requestingUserObjectId, traceId));
};
