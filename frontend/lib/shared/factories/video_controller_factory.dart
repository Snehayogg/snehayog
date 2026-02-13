import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:video_player/video_player.dart';
import 'package:vayu/shared/models/video_model.dart';
import 'package:vayu/shared/services/video_player_config_service.dart';
import 'package:vayu/shared/managers/smart_cache_manager.dart';
import 'package:vayu/shared/services/hls_warmup_service.dart';
import 'package:vayu/features/video/data/services/video_cache_proxy_service.dart';
import 'package:vayu/shared/utils/app_logger.dart';

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

    } else if (isHLS &&
        video.hlsPlaylistUrl != null &&
        video.hlsPlaylistUrl!.isNotEmpty) {
      videoUrl = video.hlsPlaylistUrl!;

    } else if (isHLS &&
        video.hlsMasterPlaylistUrl != null &&
        video.hlsMasterPlaylistUrl!.isNotEmpty) {
      videoUrl = video.hlsMasterPlaylistUrl!;

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

            return VideoPlayerConfigService.getOptimizedVideoUrl(
                videoUrl, qualityPreset);
          },
          cacheType: 'videos',
          maxAge: const Duration(minutes: 30),
        ) ??
        VideoPlayerConfigService.getOptimizedVideoUrl(videoUrl, qualityPreset);

    // **INTEGRATION: Wrap with Video Cache Proxy for persistent caching**
    final proxiedUrl = videoCacheProxy.proxyUrl(optimizedUrl);

    // Get optimized HTTP headers with caching support
    final headers = VideoPlayerConfigService.getOptimizedHeaders(proxiedUrl);

    // **HLS CACHING: Add HLS-specific cache headers**
    if (isHLS) {
      headers['Cache-Control'] =
          'public, max-age=300'; // 5 minutes for HLS playlists
      headers['X-Cache-Strategy'] = 'HLS-Adaptive';
    }

    // Get buffering configuration












    // Best-effort warm-up for HLS (manifest + first segments)
    if (optimizedUrl.contains('.m3u8')) {
      // Fire-and-forget warm-up to avoid blocking UI
      HlsWarmupService().warmUp(optimizedUrl);
    }

    // **WEB FIX: Web video player needs different configuration**
    final videoPlayerOptions = VideoPlayerOptions(
      mixWithOthers: kIsWeb ? false : true, // Web doesn't support mixWithOthers
      allowBackgroundPlayback: false,
    );

    AppLogger.log(
      '🎬 VideoControllerFactory: Creating controller for web: $kIsWeb, URL: $optimizedUrl',
    );

    try {
      // **NEW: Support for local gallery videos**
      if (video.videoType == 'local_gallery' && !kIsWeb) {
        AppLogger.log('🎬 VideoControllerFactory: Creating File controller for: ${video.videoUrl}');
        return VideoPlayerController.file(
          File(video.videoUrl),
          videoPlayerOptions: videoPlayerOptions,
        );
      }

      return VideoPlayerController.networkUrl(
        Uri.parse(proxiedUrl),
        videoPlayerOptions: videoPlayerOptions,
        httpHeaders: {
          ...headers,
          // ADD THESE FOR FASTER LOADING:
          'Connection': 'keep-alive',
          'Cache-Control': 'public, max-age=3600',
          'Accept-Encoding': 'gzip, deflate',
        },
      );
    } catch (e) {
      AppLogger.log(
        '❌ VideoControllerFactory: Error creating controller: $e',
        isError: true,
      );
      // Re-throw to let caller handle
      rethrow;
    }
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

    } else if (isHLS &&
        video.hlsMasterPlaylistUrl != null &&
        video.hlsMasterPlaylistUrl!.isNotEmpty) {
      videoUrl = video.hlsMasterPlaylistUrl!;

    }

    final qualityPreset =
        VideoPlayerConfigService.getQualityPreset(qualityUseCase);
    final optimizedUrl =
        VideoPlayerConfigService.getOptimizedVideoUrl(videoUrl, qualityPreset);

    // **INTEGRATION: Wrap with Video Cache Proxy**
    final proxiedUrl = videoCacheProxy.proxyUrl(optimizedUrl);

    final headers = VideoPlayerConfigService.getOptimizedHeaders(proxiedUrl);





    return VideoPlayerController.networkUrl(
      Uri.parse(proxiedUrl),
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
