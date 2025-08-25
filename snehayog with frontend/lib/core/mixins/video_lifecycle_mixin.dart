import 'dart:async';
import 'package:flutter/material.dart';
import 'package:snehayog/core/managers/video_controller_manager.dart';
import 'package:snehayog/core/managers/yog_cache_manager.dart';

/// Mixin for managing video lifecycle events
mixin VideoLifecycleMixin<T extends StatefulWidget> on State<T> {
  late VideoControllerManager _controllerManager;
  late YogCacheManager _cacheManager;
  bool _isScreenVisible = true;
  Timer? _healthCheckTimer;

  /// Initialize lifecycle management
  void initializeVideoLifecycle() {
    _controllerManager = VideoControllerManager();
    _cacheManager = YogCacheManager();
    _cacheManager.initialize();
    _startHealthCheckTimer();
  }

  /// Start periodic health check timer
  void _startHealthCheckTimer() {
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted && _isScreenVisible) {
        _checkVideoHealth();
      } else if (mounted && !_isScreenVisible) {
        _ensureVideosPaused();
      }
    });
  }

  /// Check video health and fix issues
  void _checkVideoHealth() {
    final activeController =
        _controllerManager.getController(_controllerManager.activePage);
    if (activeController != null && activeController.value.isInitialized) {
      print('🔍 VideoLifecycleMixin: Video health check passed');
    }
  }

  /// Ensure all videos are paused when screen is not visible
  void _ensureVideosPaused() {
    if (_isScreenVisible) {
      print(
          '⚠️ VideoLifecycleMixin: Skipping ensure pause - screen is visible');
      return;
    }

    bool anyPlaying = false;
    int pausedCount = 0;

    for (var controller in _controllerManager.controllers.values) {
      try {
        if (controller.value.isInitialized) {
          if (controller.value.isPlaying) {
            controller.pause();
            anyPlaying = true;
            pausedCount++;
            print(
                '🛑 VideoLifecycleMixin: Health check - Paused video that was still playing');
          }
          controller.setVolume(0.0);
        }
      } catch (e) {
        print('❌ Error ensuring video is paused: $e');
      }
    }

    if (anyPlaying) {
      print(
          '🛑 VideoLifecycleMixin: Health check - Paused $pausedCount videos that were still playing');
    } else {
      print(
          '✅ VideoLifecycleMixin: Health check - All videos are properly paused and muted');
    }
  }

  /// Handle app lifecycle changes
  void handleAppLifecycleChange(AppLifecycleState state) {
    print('📱 VideoLifecycleMixin: App lifecycle changed to: $state');

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      print(
          '⏸️ VideoLifecycleMixin: App going to background, pausing all videos');
      _isScreenVisible = false;
      _controllerManager.forcePauseAllVideos();
    } else if (state == AppLifecycleState.resumed) {
      print('🔄 VideoLifecycleMixin: App resumed');
      if (_isScreenVisible && (ModalRoute.of(context)?.isCurrent ?? false)) {
        print('▶️ VideoLifecycleMixin: Resuming videos after app resume');
        _controllerManager.playActiveVideo();
      }
    }
  }

  /// Set screen visibility
  void setScreenVisibility(bool visible) {
    _isScreenVisible = visible;
    if (visible) {
      _controllerManager.playActiveVideo();
    } else {
      _controllerManager.pauseAllVideos();
    }
  }

  /// Get screen visibility
  bool get isScreenVisible => _isScreenVisible;

  /// Get controller manager
  VideoControllerManager get controllerManager => _controllerManager;

  /// Get cache manager
  YogCacheManager get cacheManager => _cacheManager;

  /// Pause all videos
  void pauseAllVideos() {
    _controllerManager.pauseAllVideos();
  }

  /// Play active video
  void playActiveVideo() {
    if (_isScreenVisible) {
      _controllerManager.playActiveVideo();
    }
  }

  /// Force pause all videos
  void forcePauseAllVideos() {
    _controllerManager.forcePauseAllVideos();
  }

  /// Dispose lifecycle management
  void disposeVideoLifecycle() {
    _healthCheckTimer?.cancel();
    _cacheManager.dispose();
    _controllerManager.disposeAll();
    print('🗑️ VideoLifecycleMixin: Disposed video lifecycle management');
  }
}
