import 'package:flutter/material.dart';

/// Service for managing video player configuration and quality optimization
class VideoPlayerConfigService {
  static const String _tag = 'VideoPlayerConfigService';

  // Quality presets for different use cases
  static const Map<String, VideoQualityPreset> _qualityPresets = {
    'reels_feed': VideoQualityPreset(
      name: 'Reels Feed',
      targetResolution: '720p',
      maxBitrate: 2000000, // 2 Mbps
      bufferSize: 10, // seconds
      preloadDistance: 2, // videos
      compressionLevel: 0.8, // 80% quality
    ),
    'high_quality': VideoQualityPreset(
      name: 'High Quality',
      targetResolution: '1080p',
      maxBitrate: 5000000, // 5 Mbps
      bufferSize: 15, // seconds
      preloadDistance: 1, // videos
      compressionLevel: 1.0, // 100% quality
    ),
    'data_saver': VideoQualityPreset(
      name: 'Data Saver',
      targetResolution: '480p',
      maxBitrate: 800000, // 800 Kbps
      bufferSize: 5, // seconds
      preloadDistance: 1, // videos
      compressionLevel: 0.6, // 60% quality
    ),
  };

  /// Get quality preset for specific use case
  static VideoQualityPreset getQualityPreset(String useCase) {
    return _qualityPresets[useCase] ?? _qualityPresets['reels_feed']!;
  }

  /// Get optimized video URL for specific quality preset
  static String getOptimizedVideoUrl(
      String originalUrl, VideoQualityPreset preset) {
    try {
      // Check if URL is already HLS
      if (originalUrl.contains('.m3u8') || originalUrl.contains('f_hls')) {
        print('$_tag: URL is already HLS, no transformation needed');
        return originalUrl;
      }

      // Transform MP4 to HLS for Cloudinary URLs
      if (originalUrl.contains('cloudinary.com') &&
          originalUrl.contains('.mp4')) {
        final hlsUrl = _transformCloudinaryMp4ToHls(originalUrl, preset);
        print('$_tag: Transformed Cloudinary MP4 to HLS: $hlsUrl');
        return hlsUrl;
      }

      // For other MP4 URLs, return as-is (consider implementing transformation)
      print('$_tag: Non-Cloudinary MP4 detected, using original URL');
      return originalUrl;
    } catch (e) {
      print('$_tag: Error optimizing video URL: $e');
      return originalUrl;
    }
  }

  /// Transform Cloudinary MP4 URLs to HLS with quality optimization
  static String _transformCloudinaryMp4ToHls(
      String mp4Url, VideoQualityPreset preset) {
    try {
      // Base HLS transformation
      String transformation = 'f_hls,q_auto,fl_sanitize';

      // Add quality-specific parameters
      switch (preset.targetResolution) {
        case '720p':
          transformation += ',w_1280,h_720';
          break;
        case '1080p':
          transformation += ',w_1920,h_1080';
          break;
        case '480p':
          transformation += ',w_854,h_480';
          break;
        default:
          transformation += ',w_1280,h_720'; // Default to 720p
      }

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
      'User-Agent': 'Snehayog-App/1.0',
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

  /// Get buffering configuration for smooth playback
  static BufferingConfig getBufferingConfig(VideoQualityPreset preset) {
    return BufferingConfig(
      initialBufferSize: preset.bufferSize,
      maxBufferSize: preset.bufferSize * 2,
      bufferForPlaybackMs: 1000, // 1 second
      bufferForPlaybackAfterRebufferMs: 2000, // 2 seconds
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
      return true; // Default to supported
    }
  }

  /// Get recommended quality preset based on device capabilities
  static VideoQualityPreset getRecommendedQualityPreset(BuildContext context) {
    // Check device capabilities and network conditions
    if (isQualitySupported(_qualityPresets['reels_feed']!, context)) {
      return _qualityPresets['reels_feed']!;
    } else if (isQualitySupported(_qualityPresets['data_saver']!, context)) {
      return _qualityPresets['data_saver']!;
    }

    return _qualityPresets['data_saver']!;
  }
}

/// Video quality preset configuration
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

/// Buffering configuration for smooth playback
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

/// Preloading configuration for better UX
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
