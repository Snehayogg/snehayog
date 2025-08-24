import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/core/services/video_player_config_service.dart';
import 'package:snehayog/core/services/video_url_service.dart';

/// Factory for creating VideoPlayerController instances with optimized configuration
class VideoControllerFactory {
  /// Creates a VideoPlayerController with optimized settings for reels feed
  static VideoPlayerController createController(VideoModel video) {
    final videoUrl = VideoUrlService.getBestVideoUrl(video);
    final isHLS = VideoUrlService.shouldUseHLS(video);

    // Get quality preset for reels feed (720p optimization)
    final qualityPreset =
        VideoPlayerConfigService.getQualityPreset('reels_feed');

    // Get optimized video URL
    final optimizedUrl =
        VideoPlayerConfigService.getOptimizedVideoUrl(videoUrl, qualityPreset);

    // Get optimized HTTP headers
    final headers = VideoPlayerConfigService.getOptimizedHeaders(optimizedUrl);

    // Get buffering configuration
    final bufferingConfig =
        VideoPlayerConfigService.getBufferingConfig(qualityPreset);

    print(
        '🎬 VideoControllerFactory: Creating controller for ${video.videoName}');
    print('🎬 VideoControllerFactory: Original URL: $videoUrl');
    print('🎬 VideoControllerFactory: Optimized URL: $optimizedUrl');
    print(
        '🎬 VideoControllerFactory: Quality Preset: ${qualityPreset.name} (${qualityPreset.targetResolution})');
    print(
        '🎬 VideoControllerFactory: Buffer Size: ${bufferingConfig.initialBufferSize}s');
    print('🎬 VideoControllerFactory: Is HLS: $isHLS');

    return VideoPlayerController.networkUrl(
      Uri.parse(optimizedUrl),
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: false,
        allowBackgroundPlayback: false,
      ),
      httpHeaders: headers,
    );
  }

  /// Creates a VideoPlayerController with custom quality preset
  static VideoPlayerController createControllerWithQuality(
      VideoModel video, String qualityUseCase) {
    final videoUrl = VideoUrlService.getBestVideoUrl(video);
    final qualityPreset =
        VideoPlayerConfigService.getQualityPreset(qualityUseCase);
    final optimizedUrl =
        VideoPlayerConfigService.getOptimizedVideoUrl(videoUrl, qualityPreset);
    final headers = VideoPlayerConfigService.getOptimizedHeaders(optimizedUrl);

    print(
        '🎬 VideoControllerFactory: Creating controller with quality: $qualityUseCase');
    print(
        '🎬 VideoControllerFactory: Quality Preset: ${qualityPreset.name} (${qualityPreset.targetResolution})');

    return VideoPlayerController.networkUrl(
      Uri.parse(optimizedUrl),
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: false,
        allowBackgroundPlayback: false,
      ),
      httpHeaders: headers,
    );
  }

  /// Creates a VideoPlayerController optimized for mobile data usage
  static VideoPlayerController createDataSaverController(VideoModel video) {
    return createControllerWithQuality(video, 'data_saver');
  }

  /// Creates a VideoPlayerController optimized for high-quality playback
  static VideoPlayerController createHighQualityController(VideoModel video) {
    return createControllerWithQuality(video, 'high_quality');
  }
}
