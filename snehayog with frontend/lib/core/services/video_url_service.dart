import 'package:snehayog/model/video_model.dart';

class VideoUrlService {
  /// Gets the best video URL for playback, with proper HLS handling
  static String getBestVideoUrl(VideoModel video) {
    print('🎬 VideoUrlService: Getting best URL for video: ${video.id}');
    print('🎬 VideoUrlService: Main videoUrl: ${video.videoUrl}');
    print('🎬 VideoUrlService: HLS Master URL: ${video.hlsMasterPlaylistUrl}');
    print('🎬 VideoUrlService: HLS Playlist URL: ${video.hlsPlaylistUrl}');

    // Priority 1: Use HLS playlist URL if available
    if (video.hlsPlaylistUrl != null && 
        video.hlsPlaylistUrl!.isNotEmpty && 
        video.hlsPlaylistUrl!.contains('.m3u8')) {
      print('🎬 Using HLS Playlist URL: ${video.hlsPlaylistUrl}');
      return video.hlsPlaylistUrl!;
    }

    // Priority 2: Use HLS master playlist URL if available
    if (video.hlsMasterPlaylistUrl != null &&
        video.hlsMasterPlaylistUrl!.isNotEmpty &&
        video.hlsMasterPlaylistUrl!.contains('.m3u8')) {
      print('🎬 Using HLS Master Playlist: ${video.hlsMasterPlaylistUrl}');
      return video.hlsMasterPlaylistUrl!;
    }

    // Priority 3: Check if main videoUrl is already HLS
    if (video.videoUrl.isNotEmpty && video.videoUrl.contains('.m3u8')) {
      print('🎬 Using main video URL (already HLS): ${video.videoUrl}');
      return video.videoUrl;
    }

    // Priority 4: Transform Cloudinary URLs to HLS if possible
    if (video.videoUrl.isNotEmpty && video.videoUrl.contains('cloudinary.com')) {
      final transformedUrl = _transformToHls(video.videoUrl);
      print('🎬 Transformed to HLS: $transformedUrl');
      return transformedUrl;
    }

    // Priority 5: Use original video URL as last resort
    if (video.videoUrl.isNotEmpty) {
      print('⚠️ Using original video URL (may not be HLS compatible): ${video.videoUrl}');
      return video.videoUrl;
    }

    // If no valid URL found, throw error
    throw Exception(
        'No valid video URL found for video: ${video.videoName}. Please re-upload the video.');
  }

  /// Transforms any video URL to HLS for better streaming performance
  static String _transformToHls(String originalUrl) {
    print('🎬 VideoUrlService: Transforming URL to HLS: $originalUrl');
    
    if (originalUrl.contains('cloudinary.com')) {
      // Extract Cloudinary public ID from URL
      final uri = Uri.parse(originalUrl);
      final pathSegments = uri.pathSegments;
      
      // Find the public ID (usually after 'upload' segment)
      int uploadIndex = pathSegments.indexOf('upload');
      if (uploadIndex != -1 && uploadIndex < pathSegments.length - 1) {
        String publicId = pathSegments.skip(uploadIndex + 1).join('/');
        
        // Remove file extension
        if (publicId.contains('.')) {
          publicId = publicId.substring(0, publicId.lastIndexOf('.'));
        }
        
        // Get cloud name from URL
        final cloudName = uri.host.split('.').first;
        
        // Generate proper HLS URL with Cloudinary
        final hlsUrl = 'https://res.cloudinary.com/$cloudName/video/upload/f_m3u8,q_auto/$publicId.m3u8';
        
        print('🎬 Cloudinary HLS transformation:');
        print('   Cloud Name: $cloudName');
        print('   Public ID: $publicId');
        print('   Original: $originalUrl');
        print('   HLS URL: $hlsUrl');
        
        return hlsUrl;
      }
    }

    // For other URLs, try basic HLS conversion
    if (originalUrl.contains('.mp4')) {
      final hlsUrl = originalUrl.replaceAll('.mp4', '.m3u8');
      print('🎬 Basic HLS conversion: $originalUrl → $hlsUrl');
      return hlsUrl;
    }

    print('🎬 No HLS transformation applied to: $originalUrl');
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
