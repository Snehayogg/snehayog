import 'package:video_player/video_player.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/core/services/video_player_config_service.dart';
import 'package:vayu/core/managers/smart_cache_manager.dart';
import 'package:vayu/core/services/hls_warmup_service.dart';

/// Factory for creating VideoPlayerController instances with optimized configuration
class VideoControllerFactory {
  static Future<VideoPlayerController> createController(
      VideoModel video) async {
    // **FIXED: Use MP4 URLs for better ExoPlayer compatibility**
    final isHLS = video.videoUrl.contains('.m3u8') ||
        video.videoUrl.contains('/hls/') ||
        video.isHLSEncoded == true;

    // Use the best available URL for streaming
    String videoUrl = video.videoUrl;

    // **FIXED: Prefer MP4 URLs over HLS for better ExoPlayer compatibility**
    if (videoUrl.isNotEmpty && !videoUrl.contains('.m3u8')) {
      print('🎬 VideoControllerFactory: Using 480p MP4 URL: $videoUrl');
    } else if (isHLS &&
        video.hlsPlaylistUrl != null &&
        video.hlsPlaylistUrl!.isNotEmpty) {
      videoUrl = video.hlsPlaylistUrl!;
      print('🎬 VideoControllerFactory: Using HLS playlist URL: $videoUrl');
    } else if (isHLS &&
        video.hlsMasterPlaylistUrl != null &&
        video.hlsMasterPlaylistUrl!.isNotEmpty) {
      videoUrl = video.hlsMasterPlaylistUrl!;
      print(
          '🎬 VideoControllerFactory: Using HLS master playlist URL: $videoUrl');
    }

    // Get standardized 480p quality preset
    final qualityPreset =
        VideoPlayerConfigService.getQualityPreset('standard_480p');

    // **CACHING INTEGRATION: Use SmartCacheManager for URL optimization**
    final smartCache = SmartCacheManager();

    // Ensure cache is initialized before use
    if (!smartCache.isInitialized) {
      await smartCache.initialize();
    }

    final cacheKey = 'video_url_${video.id}_${videoUrl.hashCode}';

    // Get optimized video URL with caching
    final optimizedUrl = await smartCache.get<String>(
          cacheKey,
          fetchFn: () async {
            print('🔄 VideoControllerFactory: Generating fresh optimized URL');
            return VideoPlayerConfigService.getOptimizedVideoUrl(
                videoUrl, qualityPreset);
          },
          cacheType: 'videos',
          maxAge: const Duration(minutes: 30),
        ) ??
        VideoPlayerConfigService.getOptimizedVideoUrl(videoUrl, qualityPreset);

    // Get optimized HTTP headers with caching support
    final headers = VideoPlayerConfigService.getOptimizedHeaders(optimizedUrl);

    // **HLS CACHING: Add HLS-specific cache headers**
    if (isHLS) {
      headers['Cache-Control'] =
          'public, max-age=300'; // 5 minutes for HLS playlists
      headers['X-Cache-Strategy'] = 'HLS-Adaptive';
    }

    // Get buffering configuration
    final bufferingConfig =
        VideoPlayerConfigService.getBufferingConfig(qualityPreset);

    print(
        '🎬 VideoControllerFactory: Creating controller for ${video.videoName}');
    print('🎬 VideoControllerFactory: Original URL: ${video.videoUrl}');
    print('🎬 VideoControllerFactory: Final URL: $optimizedUrl');
    print(
        '🎬 VideoControllerFactory: Quality Preset: ${qualityPreset.name} (${qualityPreset.targetResolution})');
    print(
        '🎬 VideoControllerFactory: Buffer Size: ${bufferingConfig.initialBufferSize}s');
    print('🎬 VideoControllerFactory: Is HLS: $isHLS');
    print('🎬 VideoControllerFactory: HLS Encoded: ${video.isHLSEncoded}');
    print(
        '🎬 VideoControllerFactory: HLS Variants: ${video.hlsVariants?.length ?? 0}');
    print(
        '🎬 VideoControllerFactory: Cache Strategy: ${isHLS ? "HLS-Adaptive" : "Standard"}');

    // Best-effort warm-up for HLS (manifest + first segments)
    if (optimizedUrl.contains('.m3u8')) {
      // Fire-and-forget warm-up to avoid blocking UI
      HlsWarmupService().warmUp(optimizedUrl);
    }

    return VideoPlayerController.networkUrl(
      Uri.parse(optimizedUrl),
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: true,
        allowBackgroundPlayback: false,
      ),
      httpHeaders: {
        ...headers,
        // ADD THESE FOR FASTER LOADING:
        'Connection': 'keep-alive',
        'Cache-Control': 'public, max-age=3600',
        'Accept-Encoding': 'gzip, deflate',
      },
    );
  }

  /// Creates a VideoPlayerController with custom quality preset (ENHANCED HLS SUPPORT)
  static VideoPlayerController createControllerWithQuality(
      VideoModel video, String qualityUseCase) {
    // **ENHANCED: Use HLS-specific URLs when available**
    final isHLS = video.videoUrl.contains('.m3u8') ||
        video.videoUrl.contains('/hls/') ||
        video.isHLSEncoded == true;

    String videoUrl = video.videoUrl;

    // **ENHANCED HLS: Prioritize HLS-specific URLs for better streaming**
    if (isHLS &&
        video.hlsPlaylistUrl != null &&
        video.hlsPlaylistUrl!.isNotEmpty) {
      videoUrl = video.hlsPlaylistUrl!;
      print(
          '🎬 VideoControllerFactory: Using HLS playlist URL for quality: $videoUrl');
    } else if (isHLS &&
        video.hlsMasterPlaylistUrl != null &&
        video.hlsMasterPlaylistUrl!.isNotEmpty) {
      videoUrl = video.hlsMasterPlaylistUrl!;
      print(
          '🎬 VideoControllerFactory: Using HLS master playlist URL for quality: $videoUrl');
    }

    final qualityPreset =
        VideoPlayerConfigService.getQualityPreset(qualityUseCase);
    final optimizedUrl =
        VideoPlayerConfigService.getOptimizedVideoUrl(videoUrl, qualityPreset);
    final headers = VideoPlayerConfigService.getOptimizedHeaders(optimizedUrl);

    print(
        '🎬 VideoControllerFactory: Creating controller with quality: $qualityUseCase');
    print(
        '🎬 VideoControllerFactory: Quality Preset: ${qualityPreset.name} (${qualityPreset.targetResolution})');
    print('🎬 VideoControllerFactory: Is HLS: $isHLS');

    return VideoPlayerController.networkUrl(
      Uri.parse(optimizedUrl),
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: true,
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
