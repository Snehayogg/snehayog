import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';

/// **NEW APPROACH: Simple Video Controller Manager**
/// This manager prevents continuous loading and pipeline overflow by:
/// 1. One controller per video index
/// 2. Simple state tracking
/// 3. No complex preloading
/// 4. Immediate disposal of unused controllers
class VideoControllerManager {
  // **SIMPLE: One controller per index**
  final Map<int, VideoPlayerController> _controllers = {};

  // **SIMPLE: Track active video**
  int _activeIndex = -1;

  // **SIMPLE: Track initialization state**
  final Set<int> _initializing = {};

  // **SIMPLE: Maximum controllers to prevent memory issues**
  static const int _maxControllers = 3;

  /// **SIMPLE: Initialize controller**
  Future<void> initController(int index, VideoModel video) async {
    try {
      // **SIMPLE: Check if already initializing**
      if (_initializing.contains(index)) {
        print('⏳ VideoControllerManager: Already initializing index $index');
        return;
      }

      // **SIMPLE: Check if controller already exists and is healthy**
      if (_isControllerHealthy(index)) {
        print(
            '✅ VideoControllerManager: Controller already healthy for index $index');
        return;
      }

      // **SIMPLE: Mark as initializing**
      _initializing.add(index);

      print(
          '🔄 VideoControllerManager: Initializing controller for index $index');

      // **SIMPLE: Dispose existing controller if any**
      await _disposeController(index);

      // **SIMPLE: Create new controller**
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(video.videoUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      // **SIMPLE: Initialize with timeout**
      await controller.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Controller initialization timed out');
        },
      );

      // **SIMPLE: Set basic properties**
      await controller.setVolume(1.0);
      await controller.setLooping(true);

      // **SIMPLE: Add to controllers map**
      _controllers[index] = controller;

      // **SIMPLE: Cleanup if too many controllers**
      _cleanupIfNeeded();

      print(
          '✅ VideoControllerManager: Successfully initialized controller for index $index');
    } catch (e) {
      print(
          '❌ VideoControllerManager: Failed to initialize controller for index $index: $e');
      // **SIMPLE: Clean up failed controller**
      await _disposeController(index);
      rethrow;
    } finally {
      _initializing.remove(index);
    }
  }

  /// **FIXED: Less strict controller health check to prevent unnecessary disposal**
  bool _isControllerHealthy(int index) {
    try {
      final controller = _controllers[index];
      if (controller == null) return false;

      // **FIXED: Only check essential properties, not dimensions**
      final isHealthy =
          controller.value.isInitialized && !controller.value.hasError;

      if (!isHealthy) {
        print('⚠️ VideoControllerManager: Controller $index is unhealthy:');
        print('  - Initialized: ${controller.value.isInitialized}');
        print('  - Has Error: ${controller.value.hasError}');

        // **FIXED: Don't auto-dispose, let the calling code decide**
        return false;
      }

      return true;
    } catch (e) {
      print(
          '❌ VideoControllerManager: Error checking controller health for index $index: $e');
      // **FIXED: Don't auto-dispose on error, let the calling code decide**
      return false;
    }
  }

  /// **SIMPLE: Get controller**
  VideoPlayerController? getController(int index) {
    final controller = _controllers[index];
    if (controller != null && _isControllerHealthy(index)) {
      return controller;
    }
    return null;
  }

  /// **SIMPLE: Play video**
  Future<void> playVideo(int index) async {
    try {
      final controller = getController(index);
      if (controller == null) {
        print(
            '⚠️ VideoControllerManager: No healthy controller for index $index');
        return;
      }

      // **SIMPLE: Update active index**
      _activeIndex = index;

      // **SIMPLE: Pause other videos**
      await _pauseOtherVideos(index);

      // **SIMPLE: Play current video**
      await controller.play();

      print('▶️ VideoControllerManager: Playing video at index $index');
    } catch (e) {
      print(
          '❌ VideoControllerManager: Error playing video at index $index: $e');
    }
  }

  /// **SIMPLE: Pause other videos**
  Future<void> _pauseOtherVideos(int currentIndex) async {
    for (final entry in _controllers.entries) {
      if (entry.key != currentIndex && entry.value.value.isPlaying) {
        try {
          await entry.value.pause();
          print(
              '⏸️ VideoControllerManager: Paused video at index ${entry.key}');
        } catch (e) {
          print(
              '⚠️ VideoControllerManager: Error pausing video at index ${entry.key}: $e');
        }
      }
    }
  }

  /// **SIMPLE: Pause specific video**
  Future<void> pauseVideo(int index) async {
    try {
      final controller = _controllers[index];
      if (controller != null && controller.value.isPlaying) {
        await controller.pause();
        print('⏸️ VideoControllerManager: Paused video at index $index');
      }
    } catch (e) {
      print(
          '❌ VideoControllerManager: Error pausing video at index $index: $e');
    }
  }

  /// **SIMPLE: Handle scroll direction**
  void onForwardScroll(int newIndex) {
    print('🔄 VideoControllerManager: Forward scroll to index $newIndex');
    _handleScrollChange(newIndex);
  }

  void onBackwardScroll(int newIndex) {
    print('🔄 VideoControllerManager: Backward scroll to index $newIndex');
    _handleScrollChange(newIndex);
  }

  /// **SIMPLE: Handle scroll change**
  void _handleScrollChange(int newIndex) {
    try {
      // **SIMPLE: Pause old video**
      if (_activeIndex != -1 && _activeIndex != newIndex) {
        pauseVideo(_activeIndex);
      }

      // **SIMPLE: Update active index**
      _activeIndex = newIndex;

      // **SIMPLE: Cleanup old controllers**
      _cleanupIfNeeded();
    } catch (e) {
      print('❌ VideoControllerManager: Error handling scroll change: $e');
    }
  }

  /// **SIMPLE: Cleanup if too many controllers**
  void _cleanupIfNeeded() {
    if (_controllers.length <= _maxControllers) return;

    // **SIMPLE: Remove controllers that are not active or adjacent**
    final toRemove = <int>[];

    for (final entry in _controllers.entries) {
      final index = entry.key;
      if (index != _activeIndex &&
          index != _activeIndex - 1 &&
          index != _activeIndex + 1) {
        toRemove.add(index);
      }
    }

    // **SIMPLE: Remove excess controllers**
    while (_controllers.length > _maxControllers && toRemove.isNotEmpty) {
      final index = toRemove.removeAt(0);
      _disposeController(index);
    }
  }

  /// **SIMPLE: Dispose specific controller**
  Future<void> _disposeController(int index) async {
    final controller = _controllers[index];
    if (controller != null) {
      try {
        await controller.dispose();
        print(
            '🧹 VideoControllerManager: Disposed controller for index $index');
      } catch (e) {
        print(
            '⚠️ VideoControllerManager: Error disposing controller for index $index: $e');
      }
      _controllers.remove(index);
    }
  }

  /// **SIMPLE: Handle app lifecycle changes**
  void onAppLifecycleChanged(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _pauseAllVideos();
        break;
      case AppLifecycleState.resumed:
        // Do nothing - let user manually resume
        break;
      default:
        break;
    }
  }

  /// **SIMPLE: Pause all videos**
  Future<void> _pauseAllVideos() async {
    for (final controller in _controllers.values) {
      if (controller.value.isPlaying) {
        try {
          await controller.pause();
        } catch (e) {
          print(
              '⚠️ VideoControllerManager: Error pausing video on app pause: $e');
        }
      }
    }
  }

  /// **SIMPLE: Dispose all controllers**
  Future<void> disposeAll() async {
    for (final entry in _controllers.entries) {
      try {
        await entry.value.dispose();
      } catch (e) {
        print('⚠️ VideoControllerManager: Error disposing controller: $e');
      }
    }

    _controllers.clear();
    _initializing.clear();
    print('🧹 VideoControllerManager: All controllers disposed');
  }

  /// **SIMPLE: Get status for debugging**
  Map<String, dynamic> getStatus() {
    return {
      'controllersCount': _controllers.length,
      'maxControllers': _maxControllers,
      'activeIndex': _activeIndex,
      'initializing': _initializing.toList(),
      'controllerKeys': _controllers.keys.toList(),
    };
  }

  /// **NEW: Get controller count for memory management**
  int get controllerCount => _controllers.length;

  /// **NEW: Dispose specific controller by index**
  Future<void> disposeController(int index) async {
    await _disposeController(index);
  }

  /// **NEW: Dispose all controllers**
  Future<void> disposeAllControllers() async {
    await disposeAll();
  }

  /// **NEW: Check if video was intentionally paused**
  bool isVideoIntentionallyPaused(int index) {
    // **SIMPLIFIED: Always return false for now**
    return false;
  }

  /// **NEW: Optimize controllers for memory management**
  void optimizeControllers() {
    // **SIMPLIFIED: Just cleanup if too many**
    _cleanupIfNeeded();
  }

  /// **NEW: Get controllers map for external access**
  Map<int, VideoPlayerController> get controllers =>
      Map.unmodifiable(_controllers);

  /// **NEW: Play active video**
  Future<void> playActiveVideo() async {
    if (_activeIndex != -1) {
      await playVideo(_activeIndex);
    }
  }

  /// **NEW: Comprehensive pause all videos**
  Future<void> comprehensivePause() async {
    await _pauseAllVideos();
  }

  /// **NEW: Force restore active controller**
  Future<void> forceRestoreActiveController(VideoModel video) async {
    if (_activeIndex != -1) {
      await _disposeController(_activeIndex);
      await initController(_activeIndex, video);
    }
  }

  /// **NEW: Gentle pause for tab switch**
  Future<void> gentlePauseForTabSwitch() async {
    if (_activeIndex != -1) {
      await pauseVideo(_activeIndex);
    }
  }

  /// **NEW: Restore volume for tab switch**
  Future<void> restoreVolumeForTabSwitch() async {
    // **SIMPLIFIED: Do nothing for now**
    print('🔊 VideoControllerManager: Volume restore not implemented');
  }

  /// **NEW: Handle video visible**
  Future<void> handleVideoVisible() async {
    if (_activeIndex != -1) {
      await playVideo(_activeIndex);
    }
  }

  /// **NEW: Emergency stop all videos**
  Future<void> emergencyStopAllVideos() async {
    for (final entry in _controllers.entries) {
      try {
        if (entry.value.value.isPlaying) {
          await entry.value.pause();
        }
      } catch (e) {
        print('⚠️ VideoControllerManager: Error emergency stopping video: $e');
      }
    }
  }

  /// **NEW: Set active page**
  void setActivePage(int page) {
    _activeIndex = page;
  }

  /// **NEW: Preload videos around current index**
  Future<void> preloadVideosAround() async {
    // **SIMPLIFIED: Preload adjacent videos**
    final indices = <int>[];

    if (_activeIndex > 0) indices.add(_activeIndex - 1);
    if (_activeIndex < 100) indices.add(_activeIndex + 1);

    for (final index in indices) {
      if (!_controllers.containsKey(index)) {
        // Note: This would need video data to actually preload
        print('🔄 VideoControllerManager: Would preload video at index $index');
      }
    }
  }

  /// **NEW: Handle scroll start**
  void handleScrollStart() {
    // **SIMPLIFIED: Pause current video when scrolling starts**
    if (_activeIndex != -1) {
      pauseVideo(_activeIndex);
    }
  }

  /// **NEW: Pause all videos**
  Future<void> pauseAllVideos() async {
    await _pauseAllVideos();
  }
}
