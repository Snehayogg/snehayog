import 'package:flutter/foundation.dart';

/// Comprehensive logging service for VideoScreen operations
/// Follows the existing logging patterns in the codebase
class VideoScreenLogger {
  static const String _tag = '🎬';
  static const String _videoTag = '📹';
  static const String _cacheTag = '💾';
  static const String _controllerTag = '🎮';
  static const String _adTag = '📱';
  static const String _analyticsTag = '📊';
  static const String _errorTag = '❌';
  static const String _successTag = '✅';
  static const String _warningTag = '⚠️';
  static const String _refreshTag = '🔄';
  static const String _pauseTag = '⏸️';
  static const String _playTag = '▶️';
  static const String _backgroundTag = '🛑';
  static const String _foregroundTag = '👁️';
  static const String _scrollTag = '📱';
  static const String _preloadTag = '🚀';
  static const String _healthTag = '💚';
  static const String _memoryTag = '🧠';
  static const String _revenueTag = '💰';

  // Video initialization and lifecycle
  static void logVideoScreenInit() {
    if (kDebugMode) {
      print('$_tag VideoScreen: Initializing with fast video delivery system');
    }
  }

  static void logVideoScreenDispose() {
    if (kDebugMode) {
      print('$_tag VideoScreen: DISPOSE METHOD CALLED');
    }
  }

  static void logVideoScreenDisposeComplete() {
    if (kDebugMode) {
      print('$_tag VideoScreen: DISPOSE COMPLETED');
    }
  }

  // Video management
  static void logVideoLoad({int? count, String? source}) {
    if (kDebugMode) {
      final sourceStr = source != null ? ' from $source' : '';
      final countStr = count != null ? ' ($count videos)' : '';
      print('$_videoTag VideoScreen: Loading videos$sourceStr$countStr');
    }
  }

  static void logVideoLoadSuccess({required int count, String? source}) {
    if (kDebugMode) {
      final sourceStr = source != null ? ' from $source' : '';
      print(
          '$_successTag VideoScreen: Videos loaded successfully$sourceStr ($count videos)');
    }
  }

  static void logVideoLoadError(String error) {
    if (kDebugMode) {
      print('$_errorTag VideoScreen: Error loading videos: $error');
    }
  }

  static void logVideoRefresh({bool isBackground = false}) {
    if (kDebugMode) {
      final type = isBackground ? 'background' : 'manual';
      print('$_refreshTag VideoScreen: Starting $type video refresh...');
    }
  }

  static void logVideoRefreshSuccess(
      {required int count, bool isBackground = false}) {
    if (kDebugMode) {
      final type = isBackground ? 'background' : 'manual';
      print(
          '$_successTag VideoScreen: $type video refresh completed successfully ($count videos)');
    }
  }

  static void logVideoRefreshError(String error) {
    if (kDebugMode) {
      print('$_errorTag VideoScreen: Error refreshing videos: $error');
    }
  }

  // Video controller management
  static void logControllerInit(
      {required int index, required String videoName}) {
    if (kDebugMode) {
      print(
          '$_controllerTag VideoScreen: Initializing controller for video $index: $videoName');
    }
  }

  static void logControllerInitSuccess({required int index}) {
    if (kDebugMode) {
      print(
          '$_successTag VideoScreen: Controller initialized successfully for video $index');
    }
  }

  static void logControllerInitError(
      {required int index, required String error}) {
    if (kDebugMode) {
      print(
          '$_errorTag VideoScreen: Error initializing controller for video $index: $error');
    }
  }

  static void logControllerDispose({required int index}) {
    if (kDebugMode) {
      print(
          '$_controllerTag VideoScreen: Disposing controller for video $index');
    }
  }

  static void logControllerDisposeAll() {
    if (kDebugMode) {
      print('$_controllerTag VideoScreen: Disposing all controllers');
    }
  }

  static void logControllerCount({required int count}) {
    if (kDebugMode) {
      print('$_controllerTag VideoScreen: Total controllers: $count');
    }
  }

  // Video playback control
  static void logVideoPlay({required int index}) {
    if (kDebugMode) {
      print('$_playTag VideoScreen: Playing video at index $index');
    }
  }

  static void logVideoPause({required int index}) {
    if (kDebugMode) {
      print('$_pauseTag VideoScreen: Pausing video at index $index');
    }
  }

  static void logVideoPauseAll() {
    if (kDebugMode) {
      print('$_pauseTag VideoScreen: Pausing all videos');
    }
  }

  static void logVideoForcePause() {
    if (kDebugMode) {
      print('$_pauseTag VideoScreen: Force pausing all videos');
    }
  }

  static void logVideoComprehensivePause() {
    if (kDebugMode) {
      print(
          '$_pauseTag VideoScreen: Comprehensive pause - ensuring all videos are stopped');
    }
  }

  // Video page changes
  static void logVideoPageChange({required int from, required int to}) {
    if (kDebugMode) {
      print('$_scrollTag VideoScreen: Video page changing from $from to $to');
    }
  }

  static void logVideoPageChangeImmediatePause({required int index}) {
    if (kDebugMode) {
      print(
          '$_pauseTag VideoScreen: Immediately paused current video at index $index');
    }
  }

  // App lifecycle
  static void logAppBackground() {
    if (kDebugMode) {
      print(
          '$_backgroundTag VideoScreen: App going to background - stopping all videos');
    }
  }

  static void logAppResume() {
    if (kDebugMode) {
      print('$_foregroundTag VideoScreen: App resumed - checking video state');
    }
  }

  static void logAppLifecycleState(String state) {
    if (kDebugMode) {
      print('$_tag VideoScreen: App lifecycle state: $state');
    }
  }

  // Screen visibility
  static void logScreenVisibility({required bool isVisible, String? reason}) {
    if (kDebugMode) {
      final reasonStr = reason != null ? ' ($reason)' : '';
      final status = isVisible ? 'visible' : 'not visible';
      print('$_tag VideoScreen: Screen $status$reasonStr');
    }
  }

  static void logScreenVisibilityCheck({required bool isVideoScreenActive}) {
    if (kDebugMode) {
      final status = isVideoScreenActive ? 'active' : 'not active';
      print('$_tag VideoScreen: Screen visibility check - tab $status');
    }
  }

  // Tab switching
  static void logTabSwitch({required bool toVideoTab, String? reason}) {
    if (kDebugMode) {
      final direction = toVideoTab ? 'to video tab' : 'away from video tab';
      final reasonStr = reason != null ? ' ($reason)' : '';
      print('$_tag VideoScreen: Tab switched $direction$reasonStr');
    }
  }

  // Video caching
  static void logCacheInit() {
    if (kDebugMode) {
      print(
          '$_cacheTag VideoScreen: Initializing VideoCacheManager with disk cache...');
    }
  }

  static void logCacheInitSuccess() {
    if (kDebugMode) {
      print(
          '$_successTag VideoScreen: VideoCacheManager with disk cache initialized');
    }
  }

  static void logCacheInitError(String error) {
    if (kDebugMode) {
      print(
          '$_errorTag VideoScreen: Error initializing VideoCacheManager with disk cache: $error');
    }
  }

  static void logCachePreload() {
    if (kDebugMode) {
      print('$_preloadTag VideoScreen: Starting smart video preloading...');
    }
  }

  static void logCachePreloadSuccess() {
    if (kDebugMode) {
      print('$_successTag VideoScreen: Smart preloading initialized');
    }
  }

  static void logCachePreloadError(String error) {
    if (kDebugMode) {
      print(
          '$_errorTag VideoScreen: Error initializing smart preloading: $error');
    }
  }

  static void logCachePreloadVideos({required int count}) {
    if (kDebugMode) {
      print(
          '$_preloadTag VideoScreen: Starting smart video preloading for $count videos');
    }
  }

  static void logCachePreloadVideosSuccess() {
    if (kDebugMode) {
      print(
          '$_successTag VideoScreen: Smart preloading completed successfully');
    }
  }

  static void logCachePreloadVideosError(String error) {
    if (kDebugMode) {
      print('$_errorTag VideoScreen: Smart preloading failed: $error');
    }
  }

  static void logCachePreloadNextPages() {
    if (kDebugMode) {
      print(
          '$_preloadTag VideoScreen: Preloading next pages for smooth scrolling...');
    }
  }

  static void logCachePreloadNextPagesSuccess() {
    if (kDebugMode) {
      print('$_successTag VideoScreen: Next pages preloading started');
    }
  }

  static void logCachePreloadNextPagesError(String error) {
    if (kDebugMode) {
      print('$_warningTag VideoScreen: Error preloading next pages: $error');
    }
  }

  // Video health monitoring
  static void logHealthCheck() {
    if (kDebugMode) {
      print(
          '$_healthTag VideoScreen: Health check - ensuring videos are paused');
    }
  }

  static void logHealthCheckTabInactive() {
    if (kDebugMode) {
      print(
          '$_healthTag VideoScreen: Health check - not on video tab, forcing pause');
    }
  }

  static void logHealthCheckError(String error) {
    if (kDebugMode) {
      print(
          '$_errorTag VideoScreen: Error checking main controller in health timer: $error');
    }
  }

  // Frozen video detection and recovery
  static void logFrozenVideoDetected({required int index}) {
    if (kDebugMode) {
      print(
          '$_warningTag VideoScreen: Detected frozen video at index $index, attempting recovery...');
    }
  }

  static void logFrozenVideoRecovery({required int index}) {
    if (kDebugMode) {
      print(
          '$_refreshTag VideoScreen: Recovering frozen video at index $index...');
    }
  }

  static void logFrozenVideoRecoverySuccess({required int index}) {
    if (kDebugMode) {
      print('$_successTag VideoScreen: Frozen video recovery successful');
    }
  }

  static void logFrozenVideoRecoveryError(
      {required int index, required String error}) {
    if (kDebugMode) {
      print('$_errorTag VideoScreen: Frozen video recovery failed: $error');
    }
  }

  // Video error recovery
  static void logVideoErrorRecovery({required int index}) {
    if (kDebugMode) {
      print(
          '$_refreshTag VideoScreen: Recovering video with error at index $index...');
    }
  }

  static void logVideoErrorRecoverySuccess({required int index}) {
    if (kDebugMode) {
      print('$_successTag VideoScreen: Video error recovery successful');
    }
  }

  static void logVideoErrorRecoveryError(
      {required int index, required String error}) {
    if (kDebugMode) {
      print('$_errorTag VideoScreen: Video error recovery failed: $error');
    }
  }

  // MediaCodec error handling
  static void logMediaCodecError(String error) {
    if (kDebugMode) {
      print(
          '$_warningTag VideoScreen: MediaCodec error detected, attempting recovery...');
    }
  }

  static void logMediaCodecRecovery() {
    if (kDebugMode) {
      print('$_refreshTag VideoScreen: MediaCodec recovery started...');
    }
  }

  static void logMediaCodecRecoverySuccess() {
    if (kDebugMode) {
      print('$_successTag VideoScreen: MediaCodec recovery successful');
    }
  }

  static void logMediaCodecRecoveryError(String error) {
    if (kDebugMode) {
      print('$_errorTag VideoScreen: MediaCodec recovery failed: $error');
    }
  }

  // Memory pressure monitoring
  static void logMemoryPressure(
      {required int controllerCount, required int maxControllers}) {
    if (kDebugMode) {
      print(
          '$_memoryTag VideoScreen: High controller count ($controllerCount), optimizing...');
    }
  }

  static void logMemoryPressureForceCleanup(
      {required int controllerCount, required int maxControllers}) {
    if (kDebugMode) {
      print(
          '$_memoryTag VideoScreen: Forcing controller cleanup due to high memory usage');
    }
  }

  static void logMemoryPressureError(String error) {
    if (kDebugMode) {
      print('$_errorTag VideoScreen: Error checking memory pressure: $error');
    }
  }

  // Ad management
  static void logAdInit() {
    if (kDebugMode) {
      print('$_adTag VideoScreen: Initializing AdMob banner ad');
    }
  }

  static void logAdInitSuccess() {
    if (kDebugMode) {
      print('$_successTag Banner ad loaded successfully in VideoScreen');
    }
  }

  static void logAdInitError(String error) {
    if (kDebugMode) {
      print('$_errorTag Error initializing banner ad: $error');
    }
  }

  static void logVideoAdInit(
      {required int videoIndex, required String videoName}) {
    if (kDebugMode) {
      print(
          '$_adTag VideoScreen: Initializing banner ad for video $videoIndex: $videoName');
    }
  }

  static void logVideoAdInitSuccess({required int videoIndex}) {
    if (kDebugMode) {
      print('$_successTag Video $videoIndex: Banner ad loaded successfully');
    }
  }

  static void logVideoAdInitError(
      {required int videoIndex, required String error}) {
    if (kDebugMode) {
      print('$_errorTag Video $videoIndex: Banner ad failed to load: $error');
    }
  }

  static void logAdRefresh() {
    if (kDebugMode) {
      print('$_refreshTag VideoScreen: Refreshing banner ad');
    }
  }

  // Analytics and revenue
  static void logAdAnalytics(
      {required String eventType,
      required int videoIndex,
      required String videoName}) {
    if (kDebugMode) {
      print(
          '$_analyticsTag Ad Analytics: $eventType for video $videoIndex: $videoName');
    }
  }

  static void logRevenueCalculation(
      {required int videoIndex,
      required String videoName,
      required double revenue}) {
    if (kDebugMode) {
      print(
          '$_revenueTag Video $videoIndex: $videoName - Estimated revenue: \$${revenue.toStringAsFixed(4)}');
    }
  }

  // User interactions
  static void logLikeHandler({required int index}) {
    if (kDebugMode) {
      print('🔍 Like Handler: Starting like process for video at index $index');
    }
  }

  static void logLikeHandlerUserAuth(
      {required String userId,
      required String videoId,
      required bool isCurrentlyLiked}) {
    if (kDebugMode) {
      print(
          '🔍 Like Handler: User ID: $userId, Video ID: $videoId, Currently liked: $isCurrentlyLiked');
    }
  }

  static void logLikeHandlerUIUpdate() {
    if (kDebugMode) {
      print('🔍 Like Handler: UI updated optimistically, calling API...');
    }
  }

  static void logLikeHandlerAPISuccess() {
    if (kDebugMode) {
      print('✅ Like Handler: API call successful, updating state...');
    }
  }

  static void logLikeHandlerComplete() {
    if (kDebugMode) {
      print('✅ Like Handler: Like process completed successfully');
    }
  }

  static void logLikeHandlerError(String error) {
    if (kDebugMode) {
      print('❌ Like Handler Error: $error');
    }
  }

  static void logLikeHandlerErrorType(String errorType) {
    if (kDebugMode) {
      print('❌ Like Handler Error Type: $errorType');
    }
  }

  static void logLikeHandlerErrorDetails(String errorDetails) {
    if (kDebugMode) {
      print('❌ Like Handler Error Details: $errorDetails');
    }
  }

  static void logLikeHandlerRevert() {
    if (kDebugMode) {
      print('🔄 Like Handler: Reverted optimistic update due to error');
    }
  }

  // Scroll and refresh gestures
  static void logScrollDetected() {
    if (kDebugMode) {
      print(
          '$_scrollTag VideoScreen: Scroll detected - immediately pausing current video');
    }
  }

  static void logPullDownRefresh() {
    if (kDebugMode) {
      print('$_refreshTag VideoScreen: Pull-down refresh gesture detected');
    }
  }

  static void logDoubleTapRefresh() {
    if (kDebugMode) {
      print('$_refreshTag VideoScreen: Double-tap refresh triggered');
    }
  }

  // Background operations
  static void logBackgroundRefresh() {
    if (kDebugMode) {
      print('$_refreshTag VideoScreen: Starting background video refresh...');
    }
  }

  static void logBackgroundRefreshSuccess({required int count}) {
    if (kDebugMode) {
      print(
          '$_successTag VideoScreen: Background refresh completed with $count videos');
    }
  }

  static void logBackgroundRefreshError(String error) {
    if (kDebugMode) {
      print('$_errorTag VideoScreen: Background refresh failed: $error');
    }
  }

  // Video system restart
  static void logVideoSystemRestart() {
    if (kDebugMode) {
      print(
          '$_refreshTag VideoScreen: Force restarting entire video system...');
    }
  }

  static void logVideoSystemRestartSuccess() {
    if (kDebugMode) {
      print('$_successTag VideoScreen: Video system restart completed');
    }
  }

  static void logVideoSystemRestartError(String error) {
    if (kDebugMode) {
      print('$_errorTag VideoScreen: Video system restart failed: $error');
    }
  }

  // Cache operations
  static void logCacheClear() {
    if (kDebugMode) {
      print('$_cacheTag VideoScreen: Clearing all caches...');
    }
  }

  static void logCacheClearSuccess() {
    if (kDebugMode) {
      print('$_successTag VideoScreen: All caches cleared successfully');
    }
  }

  static void logCacheClearError(String error) {
    if (kDebugMode) {
      print('$_errorTag VideoScreen: Error clearing caches: $error');
    }
  }

  // Debug operations
  static void logDebugLikeFunctionality() {
    if (kDebugMode) {
      print('🔍 DEBUG LIKE FUNCTIONALITY:');
    }
  }

  static void logDebugBackendConnectivity() {
    if (kDebugMode) {
      print('🔍 DEBUG BACKEND CONNECTIVITY:');
    }
  }

  static void logDebugBackendHealth({required bool isHealthy}) {
    if (kDebugMode) {
      final status = isHealthy ? 'OK' : 'FAILED';
      print('  - Backend health check: $status');
    }
  }

  static void logDebugBackendAccessible() {
    if (kDebugMode) {
      print('  - Backend is accessible');
    }
  }

  static void logDebugBackendNotAccessible() {
    if (kDebugMode) {
      print('  - Backend is not accessible');
    }
  }

  static void logDebugVideoFetchTest(
      {required bool success, int? count, String? error}) {
    if (kDebugMode) {
      if (success) {
        print('  - Video fetch test: SUCCESS');
        if (count != null) {
          print('  - Videos count: $count');
        }
      } else {
        print('  - Video fetch test: FAILED - $error');
      }
    }
  }

  static void logDebugBackendConnectivityError(String error) {
    if (kDebugMode) {
      print('  - Backend connectivity test failed: $error');
    }
  }

  // General info logging
  static void logInfo(String message) {
    if (kDebugMode) {
      print('$_tag VideoScreen: $message');
    }
  }

  static void logWarning(String message) {
    if (kDebugMode) {
      print('$_warningTag VideoScreen: $message');
    }
  }

  static void logError(String message) {
    if (kDebugMode) {
      print('$_errorTag VideoScreen: $message');
    }
  }

  static void logSuccess(String message) {
    if (kDebugMode) {
      print('$_successTag VideoScreen: $message');
    }
  }

  // Performance logging
  static void logPerformance(String operation, Duration duration) {
    if (kDebugMode) {
      print('⚡ VideoScreen: $operation took ${duration.inMilliseconds}ms');
    }
  }

  // Network logging
  static void logNetworkRequest(String endpoint, {String? method}) {
    if (kDebugMode) {
      final methodStr = method != null ? ' ($method)' : '';
      print('🌐 VideoScreen: Network request: $endpoint$methodStr');
    }
  }

  static void logNetworkResponse(String endpoint, int statusCode) {
    if (kDebugMode) {
      final emoji = statusCode >= 200 && statusCode < 300 ? '✅' : '❌';
      print('$emoji VideoScreen: Network response: $endpoint - $statusCode');
    }
  }
}
