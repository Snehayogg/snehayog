import 'package:flutter/material.dart';
import 'package:vayu/shared/utils/app_logger.dart';

/// Service for managing video player configuration and quality optimization
class VideoPlayerConfigService {
  static const String _tag = 'VideoPlayerConfigService';

  // Standardized 480p quality preset for all videos
  static const Map<String, VideoQualityPreset> _qualityPresets = {
    'standard_480p': VideoQualityPreset(
      name: 'Standard 480p',
      targetResolution: '480p',
      maxBitrate: 400000,
      bufferSize: 3, // seconds
      preloadDistance: 3,
      compressionLevel: 0.8,
    ),
  };

  /// Get quality preset (always returns 480p standard)
  static VideoQualityPreset getQualityPreset(String useCase) {
    return _qualityPresets['standard_480p']!;
  }

  /// Get optimized video URL for specific quality preset
  static String getOptimizedVideoUrl(
      String originalUrl, VideoQualityPreset preset) {
    try {
      // Check if URL is already HLS
      if (originalUrl.contains('.m3u8') || originalUrl.contains('f_hls')) {
        // AppLogger.log('$_tag: URL is already HLS, no transformation needed');
        return originalUrl;
      }

      // Transform MP4 to HLS for Cloudinary URLs
      if (originalUrl.contains('cloudinary.com') &&
          originalUrl.contains('.mp4')) {
        final hlsUrl = _transformCloudinaryMp4ToHls(originalUrl, preset);
        // AppLogger.log('$_tag: Transformed Cloudinary MP4 to HLS: $hlsUrl');
        return hlsUrl;
      }

      // For other MP4 URLs, return as-is (consider implementing transformation)
      // AppLogger.log('$_tag: Non-Cloudinary MP4 detected, using original URL');
      return originalUrl;
    } catch (e) {
      AppLogger.log('$_tag: Error optimizing video URL: $e', isError: true);
      return originalUrl;
    }
  }

  /// Transform Cloudinary MP4 URLs to HLS with quality optimization
  static String _transformCloudinaryMp4ToHls(
      String mp4Url, VideoQualityPreset preset) {
    try {
      // Base HLS transformation
      String transformation = 'f_hls,q_auto,fl_sanitize';

      // Always use 480p resolution
      transformation += ',w_854,h_480';

      // Add bitrate optimization
      transformation += ',br_${(preset.maxBitrate / 1000).round()}k';

      // Add HLS-specific optimizations
      transformation += ',fl_attachment,fl_progressive';

      // Replace the upload path with transformation
      final hlsUrl =
          mp4Url.replaceAll('/video/upload/', '/video/upload/$transformation/');

      print('$_tag: HLS Transformation Parameters:');
      print('   Resolution: ${preset.targetResolution}');
      print('   Bitrate: ${preset.maxBitrate ~/ 1000}kbps');
      print('   Transformation: $transformation');

      return hlsUrl;
    } catch (e) {
      print('$_tag: Error in HLS transformation: $e');
      return mp4Url;
    }
  }

  /// Get HTTP headers optimized for video streaming
  static Map<String, String> getOptimizedHeaders(String videoUrl) {
    final headers = <String, String>{
      'User-Agent': 'Vayug-App/1.0',
      'Accept': 'video/*,application/x-mpegURL,application/vnd.apple.mpegurl',
      'Accept-Encoding': 'gzip, deflate',
      'Connection': 'keep-alive',
    };

    // Add HLS-specific headers if needed
    if (videoUrl.contains('.m3u8') || videoUrl.contains('.ts')) {
      headers['Accept'] =
          'application/x-mpegURL,application/vnd.apple.mpegurl,video/mp2t';
    }

    return headers;
  }

  static BufferingConfig getBufferingConfig(VideoQualityPreset preset) {
    return BufferingConfig(
      initialBufferSize: preset.bufferSize,
      maxBufferSize: preset.bufferSize * 2,
      bufferForPlaybackMs: 500,
      bufferForPlaybackAfterRebufferMs: 2000,
    );
  }

  /// Get preloading configuration for better UX
  static PreloadingConfig getPreloadingConfig(VideoQualityPreset preset) {
    return PreloadingConfig(
      preloadDistance: preset.preloadDistance,
      maxPreloadSize: 50 * 1024 * 1024, // 50 MB
      preloadTimeout: const Duration(seconds: 30),
    );
  }

  /// Check if device supports specific quality preset
  static bool isQualitySupported(
      VideoQualityPreset preset, BuildContext context) {
    try {
      final mediaQuery = MediaQuery.of(context);
      final screenWidth = mediaQuery.size.width;
      final screenHeight = mediaQuery.size.height;

      // Check screen resolution support
      if (preset.targetResolution == '720p') {
        return screenWidth >= 720 || screenHeight >= 720;
      } else if (preset.targetResolution == '1080p') {
        return screenWidth >= 1080 || screenHeight >= 1080;
      }

      return true; // Default to supported
    } catch (e) {
      print('$_tag: Error checking quality support: $e');
      return true;
    }
  }

  static VideoQualityPreset getRecommendedQualityPreset(BuildContext context) {
    return _qualityPresets['standard_480p']!;
  }
}

class VideoQualityPreset {
  final String name;
  final String targetResolution;
  final int maxBitrate;
  final int bufferSize;
  final int preloadDistance;
  final double compressionLevel;

  const VideoQualityPreset({
    required this.name,
    required this.targetResolution,
    required this.maxBitrate,
    required this.bufferSize,
    required this.preloadDistance,
    required this.compressionLevel,
  });

  @override
  String toString() {
    return 'VideoQualityPreset($name, $targetResolution, ${maxBitrate ~/ 1000}kbps)';
  }
}

class BufferingConfig {
  final int initialBufferSize;
  final int maxBufferSize;
  final int bufferForPlaybackMs;
  final int bufferForPlaybackAfterRebufferMs;

  const BufferingConfig({
    required this.initialBufferSize,
    required this.maxBufferSize,
    required this.bufferForPlaybackMs,
    required this.bufferForPlaybackAfterRebufferMs,
  });
}

class PreloadingConfig {
  final int preloadDistance;
  final int maxPreloadSize;
  final Duration preloadTimeout;

  const PreloadingConfig({
    required this.preloadDistance,
    required this.maxPreloadSize,
    required this.preloadTimeout,
  });
}
