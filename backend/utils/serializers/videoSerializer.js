/**
 * Video Serializer for API Versioning
 * 
 * This utility ensures that video objects are formatted correctly based on the 
 * requested API version (X-API-Version header).
 */

export const serializeVideo = (video, apiVersion, requestingUserObjectId) => {
  if (!video) return null;

  const videoObj = video.toObject ? video.toObject() : video;
  
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
    videoUrl: (videoObj.videoUrl || videoObj.hlsMasterPlaylistUrl || videoObj.hlsPlaylistUrl || '').replace(/\\/g, '/'),
    thumbnailUrl: (videoObj.thumbnailUrl || '').replace(/\\/g, '/'),
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
  };

  /**
   * VERSION SPECIFIC LOGIC
   */
  
  // Version: 2025-11-01 (App Launch baseline)
  if (apiVersion === '2025-11-01' || !apiVersion) {
    base.uploader = {
      id: videoObj.uploader?.googleId?.toString() || videoObj.uploader?._id?.toString() || '',
      _id: videoObj.uploader?._id?.toString() || '',
      googleId: videoObj.uploader?.googleId?.toString() || '',
      name: videoObj.uploader?.name || 'Unknown User',
      profilePic: videoObj.uploader?.profilePic || ''
    };
    
    base.hlsMasterPlaylistUrl = videoObj.hlsMasterPlaylistUrl || null;
    base.isHLSEncoded = videoObj.isHLSEncoded || false;
    
    return base;
  }

  // Future Versions can be added here
  // if (apiVersion >= '2026-01-26') { ... }

  return base;
};

export const serializeVideos = (videos, apiVersion, requestingUserObjectId) => {
  if (!Array.isArray(videos)) return [];
  return videos.map(v => serializeVideo(v, apiVersion, requestingUserObjectId));
};
