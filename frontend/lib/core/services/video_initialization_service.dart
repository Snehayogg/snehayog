import 'dart:async';
import 'package:flutter/material.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/core/managers/video_controller_manager.dart';
import 'package:snehayog/core/managers/video_cache_manager.dart';
import 'package:snehayog/core/services/video_screen_logger.dart';

/// Service to handle video initialization and recovery logic (SIMPLIFIED - VideoManager removed)
class VideoInitializationService {
  final VideoControllerManager _controllerManager;
  final VideoCacheManager _videoCacheManager;

  VideoInitializationService({
    required VideoControllerManager controllerManager,
    required VideoCacheManager videoCacheManager,
  })  : _controllerManager = controllerManager,
        _videoCacheManager = videoCacheManager;

  // **SIMPLIFIED: All methods now require explicit parameters instead of VideoManager**

  /// Initialize current video with timeout and retry logic (SIMPLIFIED)
  Future<void> initializeCurrentVideo({
    required bool mounted,
    required VoidCallback playActiveVideo,
    required VoidCallback preloadVideosAround,
    required VoidCallback setState,
    required int activePage,
    required List<VideoModel> videos,
  }) async {
    if (videos.isEmpty) return;

    try {
      VideoScreenLogger.logControllerInit(
        index: activePage,
        videoName: videos[activePage].videoName,
      );

      // Add timeout for video initialization
      final initFuture = _controllerManager.initController(
        activePage,
        videos[activePage],
      );

      final timeoutFuture = Future.delayed(const Duration(seconds: 15));

      await Future.any([initFuture, timeoutFuture]);

      // Check if initialization actually completed
      final controller = _controllerManager.getController(activePage);
      if (controller == null || !controller.value.isInitialized) {
        VideoScreenLogger.logWarning(
            'Video initialization may have timed out, retrying...');
        // Retry initialization
        await retryVideoInitialization(
          mounted: mounted,
          playActiveVideo: playActiveVideo,
          preloadVideosAround: preloadVideosAround,
          setState: setState,
          activePage: activePage,
          videos: videos,
        );
        return;
      }

      if (mounted) {
        playActiveVideo();
        preloadVideosAround();
        setState();
      }

      VideoScreenLogger.logControllerInitSuccess(index: activePage);
    } catch (e) {
      VideoScreenLogger.logControllerInitError(
        index: activePage,
        error: e.toString(),
      );
      // Handle initialization errors gracefully
      await handleVideoInitializationError(
        error: e,
        mounted: mounted,
        playActiveVideo: playActiveVideo,
        preloadVideosAround: preloadVideosAround,
        setState: setState,
        activePage: activePage,
        videos: videos,
      );
    }
  }

  /// Retry video initialization with delay (SIMPLIFIED)
  Future<void> retryVideoInitialization({
    required bool mounted,
    required VoidCallback playActiveVideo,
    required VoidCallback preloadVideosAround,
    required VoidCallback setState,
    required int activePage,
    required List<VideoModel> videos,
  }) async {
    try {
      VideoScreenLogger.logInfo('Retrying video initialization...');

      // Wait a bit before retrying
      await Future.delayed(const Duration(milliseconds: 1000));

      // Clear any existing controller for this index
      _controllerManager.disposeController(activePage);

      // Try initialization again
      await _controllerManager.initController(
        activePage,
        videos[activePage],
      );

      if (mounted) {
        playActiveVideo();
        preloadVideosAround();
        setState();
      }

      VideoScreenLogger.logSuccess('Video initialization retry successful');
    } catch (e) {
      VideoScreenLogger.logError('Video initialization retry failed: $e');
      // Show error to user
      if (mounted) {
        // This will be handled by the calling class
        rethrow;
      }
    }
  }

  /// Handle video initialization errors gracefully (SIMPLIFIED)
  Future<void> handleVideoInitializationError({
    required dynamic error,
    required bool mounted,
    required VoidCallback playActiveVideo,
    required VoidCallback preloadVideosAround,
    required VoidCallback setState,
    required int activePage,
    required List<VideoModel> videos,
  }) async {
    VideoScreenLogger.logWarning('Handling video initialization error: $error');

    // Check if it's a MediaCodec error
    if (error.toString().contains('MediaCodec') ||
        error.toString().contains('ExoPlaybackException') ||
        error.toString().contains('VideoError')) {
      VideoScreenLogger.logMediaCodecError(error.toString());

      // Force dispose all controllers to clear MediaCodec resources
      _controllerManager.disposeAllControllers();

      // Wait for system to release resources
      await Future.delayed(const Duration(milliseconds: 2000));

      // Clear video cache to force fresh loading
      _videoCacheManager.clearAllCaches();

      // Retry initialization with fresh resources
      try {
        await retryVideoInitialization(
          mounted: mounted,
          playActiveVideo: playActiveVideo,
          preloadVideosAround: preloadVideosAround,
          setState: setState,
          activePage: activePage,
          videos: videos,
        );
        return;
      } catch (e) {
        VideoScreenLogger.logMediaCodecRecoveryError(e.toString());
      }
    }

    // Try to recover by disposing and reinitializing
    try {
      _controllerManager.disposeController(activePage);

      // Wait a bit before retrying
      await Future.delayed(const Duration(milliseconds: 1000));

      // Try to initialize again
      await _controllerManager.initController(
        activePage,
        videos[activePage],
      );

      if (mounted) {
        playActiveVideo();
        preloadVideosAround();
        setState();
      }

      VideoScreenLogger.logSuccess('Error recovery successful');
    } catch (e) {
      VideoScreenLogger.logError('Error recovery failed: $e');
      // Re-throw to let calling class handle it
      rethrow;
    }
  }

  /// Recover frozen video (SIMPLIFIED)
  Future<void> recoverFrozenVideo({
    required int index,
    required bool mounted,
    required VoidCallback playActiveVideo,
    required VoidCallback preloadVideosAround,
    required VoidCallback setState,
    required List<VideoModel> videos,
  }) async {
    try {
      VideoScreenLogger.logFrozenVideoRecovery(index: index);

      // Dispose the problematic controller
      _controllerManager.disposeController(index);

      // Wait a bit for cleanup
      await Future.delayed(const Duration(milliseconds: 1000));

      // Reinitialize the controller
      if (index < videos.length) {
        await _controllerManager.initController(
          index,
          videos[index],
        );

        // Resume playback if not intentionally paused
        if (!_controllerManager.isVideoIntentionallyPaused(index)) {
          print('▶️ VideoScreen: Resuming recovered frozen video');
          playActiveVideo();
        } else {
          print(
              '⏸️ VideoScreen: Skipping auto-resume for intentionally paused video at index $index');
        }

        VideoScreenLogger.logFrozenVideoRecoverySuccess(index: index);
      }
    } catch (e) {
      VideoScreenLogger.logFrozenVideoRecoveryError(
        index: index,
        error: e.toString(),
      );
      rethrow;
    }
  }

  /// Recover video with error (SIMPLIFIED)
  Future<void> recoverVideoWithError({
    required int index,
    required bool mounted,
    required VoidCallback playActiveVideo,
    required VoidCallback preloadVideosAround,
    required VoidCallback setState,
    required List<VideoModel> videos,
  }) async {
    try {
      VideoScreenLogger.logVideoErrorRecovery(index: index);

      // Force dispose and recreate controller
      _controllerManager.disposeController(index);

      // Wait for system cleanup
      await Future.delayed(const Duration(milliseconds: 1500));

      // Try to reinitialize
      if (index < videos.length) {
        await _controllerManager.initController(
          index,
          videos[index],
        );

        // Check if video was intentionally paused before auto-resuming
        if (!_controllerManager.isVideoIntentionallyPaused(index)) {
          print('▶️ VideoScreen: Resuming recovered error video');
          playActiveVideo();
        } else {
          print(
              '⏸️ VideoScreen: Skipping auto-resume for intentionally paused video at index $index');
        }

        VideoScreenLogger.logVideoErrorRecoverySuccess(index: index);
      }
    } catch (e) {
      VideoScreenLogger.logVideoErrorRecoveryError(
        index: index,
        error: e.toString(),
      );
      rethrow;
    }
  }

  /// Force restart entire video system (SIMPLIFIED)
  Future<void> forceRestartVideoSystem({
    required bool mounted,
    required Future<void> Function() loadVideos,
    required Future<void> Function() initializeCurrentVideo,
    required VoidCallback setState,
  }) async {
    try {
      VideoScreenLogger.logVideoSystemRestart();

      // Dispose all controllers and clear resources
      _controllerManager.disposeAllControllers();
      _videoCacheManager.clearAllCaches();

      // Wait for system cleanup
      await Future.delayed(const Duration(milliseconds: 3000));

      // Reload videos
      await loadVideos();

      // Reinitialize current video
      await initializeCurrentVideo();

      VideoScreenLogger.logVideoSystemRestartSuccess();
    } catch (e) {
      VideoScreenLogger.logVideoSystemRestartError(e.toString());
      rethrow;
    }
  }

  /// Check for frozen videos and attempt recovery (SIMPLIFIED)
  Future<void> checkForFrozenVideos({
    required bool mounted,
    required VoidCallback playActiveVideo,
    required VoidCallback preloadVideosAround,
    required VoidCallback setState,
    required Future<void> Function(int) recoverFrozenVideo,
    required Future<void> Function(int) recoverVideoWithError,
    required int activePage,
    required List<VideoModel> videos,
    required bool isScreenVisible,
  }) async {
    try {
      if (videos.isEmpty) return;

      final currentIndex = activePage;
      final controller = _controllerManager.getController(currentIndex);

      if (controller != null && controller.value.isInitialized) {
        // Check if video was intentionally paused by user before recovery
        if (isScreenVisible &&
            !controller.value.isPlaying &&
            controller.value.isInitialized &&
            !_controllerManager.isVideoIntentionallyPaused(currentIndex)) {
          VideoScreenLogger.logFrozenVideoDetected(index: currentIndex);

          // Try to recover the frozen video
          await recoverFrozenVideo(currentIndex);
        }

        // Check for MediaCodec errors in the controller
        if (controller.value.hasError) {
          VideoScreenLogger.logVideoErrorRecovery(index: currentIndex);
          await recoverVideoWithError(currentIndex);
        }
      }
    } catch (e) {
      VideoScreenLogger.logError('Error checking for frozen videos: $e');
    }
  }

  /// Monitor memory pressure and take preventive action (SIMPLIFIED)
  void checkMemoryPressure() {
    try {
      // Check if we have too many controllers loaded
      final controllerCount = _controllerManager.controllerCount;
      const maxControllers = 5; // Reasonable limit

      if (controllerCount > maxControllers) {
        VideoScreenLogger.logMemoryPressure(
          controllerCount: controllerCount,
          maxControllers: maxControllers,
        );

        // Optimize controllers to reduce memory usage
        _controllerManager.optimizeControllers();

        // Force cleanup if needed
        if (controllerCount > maxControllers + 2) {
          VideoScreenLogger.logMemoryPressureForceCleanup(
            controllerCount: controllerCount,
            maxControllers: maxControllers,
          );
          _controllerManager.disposeAllControllers();
        }
      }
    } catch (e) {
      VideoScreenLogger.logMemoryPressureError(e.toString());
    }
  }
}
