import 'package:snehayog/model/video_model.dart';

class VideoUrlService {
  /// Gets the best video URL for playback, with automatic HLS transformation
  static String getBestVideoUrl(VideoModel video) {
    // FORCE HLS ONLY - No MP4 fallback

    if (video.hlsMasterPlaylistUrl != null &&
        video.hlsMasterPlaylistUrl!.isNotEmpty) {
      print('🎬 Using HLS Master Playlist: ${video.hlsMasterPlaylistUrl}');
      return video.hlsMasterPlaylistUrl!;
    }

    if (video.hlsPlaylistUrl != null && video.hlsPlaylistUrl!.isNotEmpty) {
      print('🎬 Using HLS Playlist: ${video.hlsPlaylistUrl}');
      return video.hlsPlaylistUrl!;
    }

    // NO MP4 FALLBACK - Force HLS conversion
    if (video.videoUrl.isNotEmpty &&
        video.videoUrl.contains('cloudinary.com')) {
      final transformedUrl = _transformMp4ToHls(video.videoUrl);
      print('🎬 Transformed MP4 to HLS: $transformedUrl');
      return transformedUrl;
    }

    // If no HLS available, throw error
    throw Exception(
        'Video is not available in HLS format (.m3u8). Please re-upload the video to enable streaming.');
  }

  /// Transforms MP4 URLs to HLS for better streaming performance
  static String _transformMp4ToHls(String originalUrl) {
    if (originalUrl.contains('cloudinary.com') &&
        originalUrl.contains('.mp4')) {
      // Transform Cloudinary MP4 to HLS with adaptive bitrate
      final hlsUrl = originalUrl.replaceAll('/video/upload/',
          '/video/upload/f_hls,q_auto,w_1280,fl_sanitize,fl_attachment/');

      print('🎬 HLS Transformation: MP4 → HLS');
      print('   Original: $originalUrl');
      print('   Transformed: $hlsUrl');

      return hlsUrl;
    }

    // For other MP4 URLs, try to add HLS parameters if supported
    if (originalUrl.contains('.mp4')) {
      print('🎬 Non-Cloudinary MP4 detected, forcing HLS conversion');
      // Force HLS conversion for any MP4
      return originalUrl.replaceAll('.mp4', '.m3u8');
    }

    return originalUrl;
  }

  /// Checks if a video should use HLS streaming
  static bool shouldUseHLS(VideoModel video) {
    // FORCE HLS - All videos must use HLS
    return true;
  }

  /// Gets the video source type for logging/debugging
  static String getVideoSourceType(VideoModel video) {
    if (video.hlsMasterPlaylistUrl != null &&
        video.hlsMasterPlaylistUrl!.isNotEmpty) {
      return 'HLS Master Playlist';
    }

    if (video.hlsPlaylistUrl != null && video.hlsPlaylistUrl!.isNotEmpty) {
      return 'HLS Playlist';
    }

    return 'Regular Video';
  }

  /// Gets optimized video URL for reels feed (720p quality)
  static String getOptimizedVideoUrl(VideoModel video) {
    final baseUrl = getBestVideoUrl(video);

    // For HLS streams, we can't modify quality in URL
    if (shouldUseHLS(video)) {
      return baseUrl;
    }

    // For regular video URLs, try to optimize for 720p
    // This is a placeholder - in production, you'd have different quality URLs
    return baseUrl;
  }

  /// Gets video quality information for optimization
  static Map<String, dynamic> getVideoQualityInfo(VideoModel video) {
    return {
      'isHLS': shouldUseHLS(video),
      'sourceType': getVideoSourceType(video),
      'recommendedQuality': '720p',
      'optimizationLevel': 'reels_feed',
    };
  }
}
