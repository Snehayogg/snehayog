import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/config/app_config.dart';

class VideoUrlService {
  /// Determines the best video URL to use based on priority:
  /// 1. HLS Master Playlist (highest quality)
  /// 2. HLS Playlist 
  /// 3. Regular video URL (fallback)
  static String getBestVideoUrl(VideoModel video) {
    // Priority: HLS Master Playlist > HLS Playlist > Regular Video URL
    if (video.hlsMasterPlaylistUrl != null &&
        video.hlsMasterPlaylistUrl!.isNotEmpty) {
      return _buildFullUrl(video.hlsMasterPlaylistUrl!);
    }

    if (video.hlsPlaylistUrl != null &&
        video.hlsPlaylistUrl!.isNotEmpty) {
      return _buildFullUrl(video.hlsPlaylistUrl!);
    }

    return video.videoUrl;
  }

  /// Builds a full URL from a relative path
  static String _buildFullUrl(String relativeUrl) {
    if (relativeUrl.startsWith('/uploads/hls/')) {
      return '${AppConfig.baseUrl}$relativeUrl';
    }
    return relativeUrl;
  }

  /// Checks if a video should use HLS streaming
  static bool shouldUseHLS(VideoModel video) {
    return video.isHLSEncoded == true ||
        video.hlsMasterPlaylistUrl != null ||
        video.hlsPlaylistUrl != null;
  }

  /// Gets the video source type for logging/debugging
  static String getVideoSourceType(VideoModel video) {
    if (video.hlsMasterPlaylistUrl != null &&
        video.hlsMasterPlaylistUrl!.isNotEmpty) {
      return 'HLS Master Playlist';
    }

    if (video.hlsPlaylistUrl != null &&
        video.hlsPlaylistUrl!.isNotEmpty) {
      return 'HLS Playlist';
    }

    return 'Regular Video';
  }
}
