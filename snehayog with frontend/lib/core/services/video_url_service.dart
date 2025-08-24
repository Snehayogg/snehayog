import 'package:snehayog/model/video_model.dart';

class VideoUrlService {
  /// Gets the best video URL for playback, with proper fallback handling
  static String getBestVideoUrl(VideoModel video) {
    print('🎬 VideoUrlService: Getting best video URL for video: ${video.videoName}');
    print('🎬 VideoUrlService: Available URLs:');
    print('   - hlsMasterPlaylistUrl: ${video.hlsMasterPlaylistUrl}');
    print('   - hlsPlaylistUrl: ${video.hlsPlaylistUrl}');
    print('   - videoUrl: ${video.videoUrl}');

    // 1. Try HLS Master Playlist first (best for adaptive streaming)
    if (video.hlsMasterPlaylistUrl != null &&
        video.hlsMasterPlaylistUrl!.isNotEmpty &&
        _isValidHlsUrl(video.hlsMasterPlaylistUrl!)) {
      print('🎬 Using HLS Master Playlist: ${video.hlsMasterPlaylistUrl}');
      return video.hlsMasterPlaylistUrl!;
    }

    // 2. Try HLS Playlist as fallback
    if (video.hlsPlaylistUrl != null && 
        video.hlsPlaylistUrl!.isNotEmpty &&
        _isValidHlsUrl(video.hlsPlaylistUrl!)) {
      print('🎬 Using HLS Playlist: ${video.hlsPlaylistUrl}');
      return video.hlsPlaylistUrl!;
    }

    // 3. Try main videoUrl (should be HLS from backend)
    if (video.videoUrl.isNotEmpty) {
      // Check if it's already an HLS URL
      if (_isValidHlsUrl(video.videoUrl)) {
        print('🎬 Using HLS video URL: ${video.videoUrl}');
        return video.videoUrl;
      }
      
      // Try to transform to HLS URL for backend consistency
      if (_isCloudinaryUrl(video.videoUrl)) {
        final transformedUrl = _transformToBackendHlsUrl(video.videoUrl);
        print('🎬 Transformed to backend HLS URL: $transformedUrl');
        return transformedUrl;
      }
      
      // Fallback to original URL and let video player handle it
      print('🎬 Using original video URL as fallback: ${video.videoUrl}');
      return video.videoUrl;
    }

    // If no valid URL found, throw error
    throw Exception(
        'No valid video URL found. Video ID: ${video.id}, Name: ${video.videoName}');
  }

  /// Validates if a URL is a valid HLS URL
  static bool _isValidHlsUrl(String url) {
    return url.isNotEmpty && 
           (url.contains('.m3u8') || url.toLowerCase().contains('hls'));
  }

  /// Checks if a URL is from Cloudinary
  static bool _isCloudinaryUrl(String url) {
    return url.contains('cloudinary.com');
  }

  /// Transforms URLs to match backend HLS URL patterns
  static String _transformToBackendHlsUrl(String originalUrl) {
    // If it's already an HLS URL, return as-is
    if (_isValidHlsUrl(originalUrl)) {
      return originalUrl;
    }

    // For backend-served videos, try to construct the HLS URL
    if (originalUrl.contains('/uploads/')) {
      // Extract video ID and construct HLS path
      final uri = Uri.parse(originalUrl);
      final path = uri.path;
      
      // Try to extract video ID from path
      final pathSegments = path.split('/');
      if (pathSegments.length > 2) {
        final fileName = pathSegments.last;
        final videoId = fileName.split('.').first;
        
        // Construct HLS URL path based on backend structure
        final hlsPath = '/uploads/hls/$videoId/playlist.m3u8';
        return Uri(
          scheme: uri.scheme,
          host: uri.host,
          port: uri.port,
          path: hlsPath,
        ).toString();
      }
    }

    // Fallback: return original URL
    return originalUrl;
  }

  /// Legacy method for backward compatibility
  static String _transformMp4ToHls(String originalUrl) {
    return _transformToBackendHlsUrl(originalUrl);
  }

  /// Checks if a video should use HLS streaming
  static bool shouldUseHLS(VideoModel video) {
    // Check if any HLS URLs are available
    return video.hlsMasterPlaylistUrl?.isNotEmpty == true ||
           video.hlsPlaylistUrl?.isNotEmpty == true ||
           _isValidHlsUrl(video.videoUrl);
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

  /// Debug method to log all video URL information
  static void debugVideoUrls(VideoModel video) {
    print('🔍 VideoUrlService DEBUG for video: ${video.videoName}');
    print('   📹 Video ID: ${video.id}');
    print('   🎬 videoUrl: ${video.videoUrl}');
    print('   📺 hlsMasterPlaylistUrl: ${video.hlsMasterPlaylistUrl}');
    print('   📻 hlsPlaylistUrl: ${video.hlsPlaylistUrl}');
    print('   🔗 isHLSEncoded: ${video.isHLSEncoded}');
    print('   📊 shouldUseHLS: ${shouldUseHLS(video)}');
    print('   📝 sourceType: ${getVideoSourceType(video)}');
    
    try {
      final bestUrl = getBestVideoUrl(video);
      print('   ✅ Best URL: $bestUrl');
    } catch (e) {
      print('   ❌ Error getting best URL: $e');
    }
    print('🔍 End debug info\n');
  }
}
