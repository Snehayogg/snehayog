import 'package:snehayog/model/video_model.dart';

/// Service for handling video URL optimization and HLS conversion
class VideoUrlService {
  /// Gets the best video URL with automatic HLS transformation
  static String getBestVideoUrl(VideoModel video) {
    // FORCE HLS ONLY - Transform MP4 to HLS if needed

    if (video.hlsMasterPlaylistUrl != null &&
        video.hlsMasterPlaylistUrl!.isNotEmpty) {
      print('🎬 Using HLS Master Playlist: ${video.hlsMasterPlaylistUrl}');
      return video.hlsMasterPlaylistUrl!;
    }

    if (video.hlsPlaylistUrl != null && video.hlsPlaylistUrl!.isNotEmpty) {
      print('🎬 Using HLS Playlist: ${video.hlsPlaylistUrl}');
      return video.hlsPlaylistUrl!;
    }

    // Transform MP4 to HLS for better streaming performance
    if (video.videoUrl.isNotEmpty) {
      final transformedUrl = _transformMp4ToHls(video.videoUrl);
      print('🎬 Transformed MP4 to HLS: $transformedUrl');
      return transformedUrl;
    }

    // If no video URL available, throw error
    throw Exception('No video URL available for playback');
  }

  /// Transforms MP4 URLs to HLS for better streaming performance
  static String _transformMp4ToHls(String originalUrl) {
    if (originalUrl.contains('cloudinary.com') &&
        originalUrl.contains('.mp4')) {
      // Transform Cloudinary MP4 to HLS with adaptive bitrate
      final hlsUrl = originalUrl.replaceAll(
          '/video/upload/', '/video/upload/f_hls,q_auto,w_1280,fl_sanitize/');

      print('🎬 HLS Transformation: MP4 → HLS');
      print('   Original: $originalUrl');
      print('   Transformed: $hlsUrl');

      return hlsUrl;
    }

    // For other MP4 URLs, try to add HLS parameters if supported
    if (originalUrl.contains('.mp4')) {
      print('🎬 Non-Cloudinary MP4 detected, attempting HLS conversion');

      // Check if server supports HLS conversion
      if (originalUrl.contains('localhost') ||
          originalUrl.contains('192.168') ||
          originalUrl.contains('10.0.2.2')) {
        // Local development - try to use HLS endpoint
        final baseUrl = originalUrl.substring(0, originalUrl.lastIndexOf('/'));
        final fileName =
            originalUrl.substring(originalUrl.lastIndexOf('/') + 1);
        final videoId = fileName.replaceAll('.mp4', '');

        // Try to get HLS version from server
        final hlsUrl = '$baseUrl/hls/$videoId/master.m3u8';
        print('🎬 Attempting local HLS conversion: $hlsUrl');
        return hlsUrl;
      } else {
        // External server - try simple m3u8 replacement
        return originalUrl.replaceAll('.mp4', '.m3u8');
      }
    }

    // For URLs that don't have extensions, assume they can serve HLS
    if (!originalUrl.contains('.')) {
      return '$originalUrl/master.m3u8';
    }

    // If conversion fails, throw error to force proper HLS encoding
    print('⚠️ VideoUrlService: Could not convert to HLS format: $originalUrl');
    throw Exception(
        'Video is not available in HLS format (.m3u8). Please re-upload the video to enable streaming.');
  }

  /// Validates if a URL is a proper HLS stream
  static bool isValidHlsUrl(String url) {
    return url.contains('.m3u8') ||
        url.contains('/hls/') ||
        url.contains('f_hls') ||
        url.contains('application/vnd.apple.mpegurl');
  }

  /// Gets fallback strategies for failed HLS conversions
  static List<String> getHlsFallbackStrategies(VideoModel video) {
    final strategies = <String>[];

    // Strategy 1: Try different HLS formats
    if (video.videoUrl.isNotEmpty) {
      strategies.add('Convert MP4 to HLS on server');
      strategies.add('Use adaptive bitrate streaming');
      strategies.add('Request HLS re-encoding');
    }

    // Strategy 2: Quality adjustments
    strategies.add('Lower quality HLS stream');
    strategies.add('Progressive download with HLS headers');

    return strategies;
  }

  /// Checks if a video should use HLS streaming (ALWAYS TRUE for performance)
  static bool shouldUseHLS(VideoModel video) {
    // FORCE HLS - All videos must use HLS for optimal performance
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

    return 'Converted to HLS';
  }

  /// Gets optimized video URL for reels feed (720p quality)
  static String getOptimizedVideoUrl(VideoModel video) {
    final baseUrl = getBestVideoUrl(video);

    // For HLS streams, we can't modify quality in URL easily
    // but we can add quality parameters for supported services
    if (baseUrl.contains('cloudinary.com')) {
      // Add quality optimization for Cloudinary
      if (!baseUrl.contains('q_auto')) {
        return baseUrl.replaceAll(
            '/video/upload/', '/video/upload/q_auto,w_1280/');
      }
    }

    return baseUrl;
  }

  /// Gets video quality information for optimization
  static Map<String, dynamic> getVideoQualityInfo(VideoModel video) {
    return {
      'isHLS': shouldUseHLS(video),
      'sourceType': getVideoSourceType(video),
      'recommendedQuality': '720p',
      'optimizationLevel': 'reels_feed',
      'transformation': 'auto_hls',
    };
  }
}
