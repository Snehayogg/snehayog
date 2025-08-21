import 'dart:io';
import 'package:video_player/video_player.dart';
import 'package:snehayog/core/services/video_url_service.dart';
import 'package:snehayog/model/video_model.dart';


class VideoControllerFactory {
  static VideoPlayerController createController(VideoModel video) {
    final videoUrl = VideoUrlService.getBestVideoUrl(video);

    return VideoPlayerController.networkUrl(
      Uri.parse(videoUrl),
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: false,
        allowBackgroundPlayback: false,
      ),
    );
  }

  static VideoPlayerController createControllerWithOptions(
    VideoModel video, {
    bool mixWithOthers = false,
    bool allowBackgroundPlayback = false,
  }) {
    final videoUrl = VideoUrlService.getBestVideoUrl(video);

    return VideoPlayerController.networkUrl(
      Uri.parse(videoUrl),
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: mixWithOthers,
        allowBackgroundPlayback: allowBackgroundPlayback,
      ),
    );
  }

  static VideoPlayerController createLocalController(String filePath) {
    return VideoPlayerController.file(
      File(filePath),
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: false,
        allowBackgroundPlayback: false,
      ),
    );
  }

  static VideoPlayerController createAssetController(String assetPath) {
    return VideoPlayerController.asset(
      assetPath,
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: false,
        allowBackgroundPlayback: false,
      ),
    );
  }

  static VideoPlayerOptions getRecommendedOptions(VideoModel video) {
    return VideoPlayerOptions(
      mixWithOthers: false,
      allowBackgroundPlayback: false,
    );
  }
}