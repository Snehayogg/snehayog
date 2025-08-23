// config/cloudinary.js
import dotenv from 'dotenv';
dotenv.config();
import { v2 as cloudinary } from 'cloudinary';

// Check if Cloudinary environment variables are set
const cloudName = process.env.CLOUD_NAME;
const apiKey = process.env.CLOUD_KEY;
const apiSecret = process.env.CLOUD_SECRET;

if (!cloudName || !apiKey || !apiSecret) {
  console.warn('⚠️ Cloudinary environment variables not set:');
  console.warn('   CLOUD_NAME:', cloudName ? 'Set' : 'Missing');
  console.warn('   CLOUD_KEY:', apiKey ? 'Set' : 'Missing');
  console.warn('   CLOUD_SECRET:', apiSecret ? 'Set' : 'Missing');
  console.warn('   Please set these environment variables to use Cloudinary uploads');
  console.warn('   You can create a .env file in the backend directory with:');
  console.warn('   CLOUD_NAME=your_cloudinary_cloud_name');
  console.warn('   CLOUD_KEY=your_cloudinary_api_key');
  console.warn('   CLOUD_SECRET=your_cloudinary_api_secret');
} else {
  console.log('✅ Cloudinary environment variables loaded');
}

cloudinary.config({
  cloud_name: cloudName,
  api_key: apiKey,
  api_secret: apiSecret,
  secure: true,
});

// Custom streaming profiles for smooth scrolling (Instagram Reels style)
export const STREAMING_PROFILES = {
  // Portrait 9:16 aspect ratio optimized for mobile
  PORTRAIT_REELS: {
    name: 'portrait_reels',
    transformations: [
      // 1080p - 3.5 Mbps
      {
        width: 1080,
        height: 1920,
        crop: 'fill',
        video_codec: 'h264',
        bit_rate: '3.5m',
        audio_codec: 'aac',
        audio_bitrate: '128k',
        fps: 30,
        keyframe_interval: 60, // 2 seconds at 30fps
        segment_duration: 2,
        streaming_profile: 'hd',
        quality: 'auto:best'
      },
      // 720p - 1.8 Mbps
      {
        width: 720,
        height: 1280,
        crop: 'fill',
        video_codec: 'h264',
        bit_rate: '1.8m',
        audio_codec: 'aac',
        audio_bitrate: '128k',
        fps: 30,
        keyframe_interval: 60,
        segment_duration: 2,
        streaming_profile: 'hd',
        quality: 'auto:good'
      },
      // 480p - 0.9 Mbps
      {
        width: 480,
        height: 854,
        crop: 'fill',
        video_codec: 'h264',
        bit_rate: '0.9m',
        audio_codec: 'aac',
        audio_bitrate: '96k',
        fps: 30,
        keyframe_interval: 60,
        segment_duration: 2,
        streaming_profile: 'sd',
        quality: 'auto:eco'
      },
      // 360p - 0.6 Mbps
      {
        width: 360,
        height: 640,
        crop: 'fill',
        video_codec: 'h264',
        bit_rate: '0.6m',
        audio_codec: 'aac',
        audio_bitrate: '64k',
        fps: 30,
        keyframe_interval: 60,
        segment_duration: 2,
        streaming_profile: 'sd',
        quality: 'auto:low'
      }
    ]
  },
  
  // Landscape 16:9 aspect ratio for regular videos
  LANDSCAPE_STANDARD: {
    name: 'landscape_standard',
    transformations: [
      // 1080p - 4.0 Mbps
      {
        width: 1920,
        height: 1080,
        crop: 'fill',
        video_codec: 'h264',
        bit_rate: '4.0m',
        audio_codec: 'aac',
        audio_bitrate: '128k',
        fps: 30,
        keyframe_interval: 60,
        segment_duration: 2,
        streaming_profile: 'hd',
        quality: 'auto:best'
      },
      // 720p - 2.0 Mbps
      {
        width: 1280,
        height: 720,
        crop: 'fill',
        video_codec: 'h264',
        bit_rate: '2.0m',
        audio_codec: 'aac',
        audio_bitrate: '128k',
        fps: 30,
        keyframe_interval: 60,
        segment_duration: 2,
        streaming_profile: 'hd',
        quality: 'auto:good'
      },
      // 480p - 1.0 Mbps
      {
        width: 854,
        height: 480,
        crop: 'fill',
        video_codec: 'h264',
        bit_rate: '1.0m',
        audio_codec: 'aac',
        audio_bitrate: '96k',
        fps: 30,
        keyframe_interval: 60,
        segment_duration: 2,
        streaming_profile: 'sd',
        quality: 'auto:eco'
      }
    ]
  }
};

// HLS streaming configuration
export const HLS_CONFIG = {
  // Segment settings for smooth playback
  segment_duration: 2, // 2 seconds per segment
  keyframe_interval: 60, // 2 seconds at 30fps
  playlist_type: 'vod', // Video on demand
  streaming_profile: 'hd', // High definition profile
  
  // ABR (Adaptive Bitrate) settings
  abr_enabled: true,
  quality_switching: 'auto',
  buffer_size: 10, // 10 seconds buffer
  
  // HLS version and compatibility
  hls_version: '3',
  compatibility: 'modern'
};

// Get streaming profile by name
export function getStreamingProfile(profileName = 'portrait_reels') {
  return STREAMING_PROFILES[profileName.toUpperCase()] || STREAMING_PROFILES.PORTRAIT_REELS;
}

// Get HLS URL with custom profile
export function getHLSStreamingUrl(publicId, profileName = 'portrait_reels') {
  const profile = getStreamingProfile(profileName);
  const transformations = profile.transformations.map(t => {
    const parts = [];
    if (t.width && t.height) parts.push(`w_${t.width},h_${t.height}`);
    if (t.crop) parts.push(`c_${t.crop}`);
    if (t.video_codec) parts.push(`vc_${t.video_codec}`);
    if (t.bit_rate) parts.push(`b_${t.bit_rate}`);
    if (t.audio_codec) parts.push(`ac_${t.audio_codec}`);
    if (t.audio_bitrate) parts.push(`ab_${t.audio_bitrate}`);
    if (t.fps) parts.push(`fps_${t.fps}`);
    if (t.keyframe_interval) parts.push(`ki_${t.keyframe_interval}`);
    if (t.segment_duration) parts.push(`du_${t.segment_duration}`);
    if (t.streaming_profile) parts.push(`sp_${t.streaming_profile}`);
    if (t.quality) parts.push(`q_${t.quality}`);
    return parts.join(',');
  }).join('/');
  
  return `https://res.cloudinary.com/${cloudName}/video/upload/${transformations}/fl_sanitize,fl_attachment,fl_sep,fl_dpr_auto,fl_quality_auto/${publicId}.m3u8`;
}

// Get master playlist URL for ABR
export function getMasterPlaylistUrl(publicId, profileName = 'portrait_reels') {
  const profile = getStreamingProfile(profileName);
  const transformations = profile.transformations.map(t => {
    const parts = [];
    if (t.width && t.height) parts.push(`w_${t.width},h_${t.height}`);
    if (t.crop) parts.push(`c_${t.crop}`);
    if (t.video_codec) parts.push(`vc_${t.video_codec}`);
    if (t.bit_rate) parts.push(`b_${t.bit_rate}`);
    if (t.audio_codec) parts.push(`ac_${t.audio_codec}`);
    if (t.audio_bitrate) parts.push(`ab_${t.audio_bitrate}`);
    if (t.fps) parts.push(`fps_${t.fps}`);
    if (t.keyframe_interval) parts.push(`ki_${t.keyframe_interval}`);
    if (t.segment_duration) parts.push(`du_${t.segment_duration}`);
    if (t.streaming_profile) parts.push(`sp_${t.streaming_profile}`);
    if (t.quality) parts.push(`q_${t.quality}`);
    return parts.join(',');
  }).join('/');
  
  return `https://res.cloudinary.com/${cloudName}/video/upload/${transformations}/fl_sanitize,fl_attachment,fl_sep,fl_dpr_auto,fl_quality_auto,fl_master_playlist/${publicId}.m3u8`;
}

// Get thumbnail URL for video
export function getVideoThumbnailUrl(publicId, width = 400, height = 600) {
  return `https://res.cloudinary.com/${cloudName}/video/upload/w_${width},h_${height},c_fill,fl_sanitize/${publicId}.jpg`;
}

export default cloudinary;
