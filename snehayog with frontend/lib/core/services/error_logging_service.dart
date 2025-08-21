import 'package:flutter/foundation.dart';

class ErrorLoggingService {
  static const String _tag = '🎬';
  
  // Video player related logging
  static void logVideoInitialization(String videoName, bool autoPlay) {
    if (kDebugMode) {
      print('$_tag VideoPlayerWidget: Initializing for video: $videoName');
      print('$_tag VideoPlayerWidget: Auto-play enabled: $autoPlay');
    }
  }

  static void logVideoUrl(String videoUrl, bool isHLS) {
    if (kDebugMode) {
      print('$_tag Video URL: $videoUrl');
      print('$_tag Is HLS: $isHLS');
    }
  }

  static void logVideoControllerState(String state) {
    if (kDebugMode) {
      print('$_tag Video controller: $state');
    }
  }

  static void logVideoPlayback(String action) {
    if (kDebugMode) {
      print('$_tag Video $action');
    }
  }

  static void logVideoError(String error, {String? context}) {
    if (kDebugMode) {
      final contextStr = context != null ? ' in $context' : '';
      print('❌ Video player error$contextStr: $error');
    }
  }

  static void logVideoSuccess(String message) {
    if (kDebugMode) {
      print('✅ $message');
    }
  }

  static void logVideoStateChange(String from, String to) {
    if (kDebugMode) {
      print('🔄 Video state changed from $from to $to');
    }
  }

  static void logHLSStatus({
    required bool? isHLSEncoded,
    required String? masterPlaylistUrl,
    required String? playlistUrl,
    required bool finalStatus,
  }) {
    if (kDebugMode) {
      print('🔍 HLS Status Check:');
      print('   isHLSEncoded: $isHLSEncoded');
      print('   hlsMasterPlaylistUrl: $masterPlaylistUrl');
      print('   hlsPlaylistUrl: $playlistUrl');
      print('   Final HLS status: $finalStatus');
    }
  }

  static void logHLSStatusChange(bool from, bool to) {
    if (kDebugMode) {
      print('🔄 HLS status changed from $from to $to');
    }
  }

  static void logUserInteraction(String action) {
    if (kDebugMode) {
      print('🎯 $action');
    }
  }

  static void logSeeking(String direction, Duration duration) {
    if (kDebugMode) {
      print('⏪⏩ Video seeked $direction by ${duration.inSeconds} seconds');
    }
  }

  // General app logging
  static void logAppLifecycle(String state) {
    if (kDebugMode) {
      print('🔄 App $state');
    }
  }

  static void logServiceInitialization(String serviceName) {
    if (kDebugMode) {
      print('✅ $serviceName initialized');
    }
  }

  // Performance logging
  static void logPerformance(String operation, Duration duration) {
    if (kDebugMode) {
      print('⚡ $operation took ${duration.inMilliseconds}ms');
    }
  }

  // Network logging
  static void logNetworkRequest(String endpoint, {String? method}) {
    if (kDebugMode) {
      final methodStr = method != null ? ' ($method)' : '';
      print('🌐 Network request: $endpoint$methodStr');
    }
  }

  static void logNetworkResponse(String endpoint, int statusCode) {
    if (kDebugMode) {
      final emoji = statusCode >= 200 && statusCode < 300 ? '✅' : '❌';
      print('$emoji Network response: $endpoint - $statusCode');
    }
  }
}
