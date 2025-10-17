import 'package:video_player/video_player.dart';
import '../model/video_model.dart';
import '../services/video_service.dart';

/// Helper class for video player operations with HLS support
class VideoPlayerHelper {
  /// Create VideoPlayerController with best available URL
  static VideoPlayerController createController(VideoModel video) {
    final playableUrl = VideoService.getPlayableUrl(video);
    return VideoPlayerController.networkUrl(Uri.parse(playableUrl));
  }

  /// Check if video can be played
  static bool canPlayVideo(VideoModel video) {
    return VideoService.hasPlayableUrl(video);
  }

  /// Get video type info for debugging
  static String getVideoTypeInfo(VideoModel video) {
    if (VideoService.hasHlsStreaming(video)) {
      return 'HLS Streaming (.m3u8)';
    } else if (video.videoUrl.isNotEmpty) {
      return 'Direct MP4';
    } else {
      return 'No playable URL';
    }
  }

  /// Initialize controller with error handling
  static Future<bool> initializeController(
      VideoPlayerController controller) async {
    try {
      await controller.initialize();
      return true;
    } catch (e) {
      print('❌ VideoPlayerHelper: Failed to initialize controller: $e');
      return false;
    }
  }

  /// Dispose controller safely
  static void disposeController(VideoPlayerController? controller) {
    try {
      controller?.dispose();
    } catch (e) {
      print('❌ VideoPlayerHelper: Error disposing controller: $e');
    }
  }
}
