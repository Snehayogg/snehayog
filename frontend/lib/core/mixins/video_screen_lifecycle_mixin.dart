import 'dart:async';
import 'package:flutter/material.dart';
import 'package:snehayog/core/managers/video_controller_manager.dart';
// Removed: import 'package:snehayog/core/managers/video_manager.dart';

/// Mixin to handle video screen lifecycle events
mixin VideoScreenLifecycleMixin<T extends StatefulWidget> on State<T> {
  late VideoControllerManager _controllerManager;
  bool _isScreenVisible = true;
  bool _isTabActive = true;
  Timer? _visibilityTimer;

  void initializeLifecycleMixin(
    VideoControllerManager controllerManager,
  ) {
    _controllerManager = controllerManager;
    print('🔧 VideoScreenLifecycleMixin: Initialized');
  }

  /// Handle tab becoming active
  void onTabBecameActive() {
    if (!_isTabActive) {
      _isTabActive = true;
      print('🔄 VideoScreenLifecycleMixin: Tab became active');

      // Delay to ensure proper state transition
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_isTabActive && mounted) {
          _restoreVideoPlayback();
        }
      });
    }
  }

  /// Handle tab becoming inactive
  void onTabBecameInactive() {
    if (_isTabActive) {
      _isTabActive = false;
      print('⏸️ VideoScreenLifecycleMixin: Tab became inactive');

      // Immediately pause videos
      _pauseAllVideos();
    }
  }

  /// Handle screen visibility changes
  void onScreenVisibilityChanged(bool isVisible) {
    if (_isScreenVisible != isVisible) {
      _isScreenVisible = isVisible;
      print(
          '👁️ VideoScreenLifecycleMixin: Screen visibility changed to $isVisible');

      if (isVisible && _isTabActive) {
        // Screen became visible and tab is active
        Future.delayed(const Duration(milliseconds: 200), () {
          if (_isScreenVisible && _isTabActive && mounted) {
            _restoreVideoPlayback();
          }
        });
      } else {
        // Screen became invisible or tab is inactive
        _pauseAllVideos();
      }
    }
  }

  /// Restore video playback after tab return
  void _restoreVideoPlayback() {
    try {
      print('🔧 VideoScreenLifecycleMixin: Restoring video playback');
      // Simplified: Just play active video if controller is ready
      _playActiveVideo();
    } catch (e) {
      print('❌ VideoScreenLifecycleMixin: Error restoring video playback: $e');
    }
  }

  /// Reinitialize the active controller (SIMPLIFIED)
  void _reinitializeActiveController() {
    print(
        '🔧 VideoScreenLifecycleMixin: Controller reinitialization simplified');
    // This method is simplified since VideoManager was removed
  }

  /// Fallback controller initialization (SIMPLIFIED)
  void _fallbackControllerInitialization() {
    print('🔄 VideoScreenLifecycleMixin: Fallback initialization simplified');
    // This method is simplified since VideoManager was removed
  }

  /// Play the active video
  void _playActiveVideo() {
    try {
      if (_isScreenVisible && _isTabActive && mounted) {
        print('▶️ VideoScreenLifecycleMixin: Playing active video');
        _controllerManager.playActiveVideo();
      }
    } catch (e) {
      print('❌ VideoScreenLifecycleMixin: Error playing active video: $e');
    }
  }

  /// Pause all videos
  void _pauseAllVideos() {
    try {
      print('⏸️ VideoScreenLifecycleMixin: Pausing all videos');
      _controllerManager.pauseAllVideos();
    } catch (e) {
      print('❌ VideoScreenLifecycleMixin: Error pausing videos: $e');
    }
  }

  /// Clean up resources
  void disposeLifecycleMixin() {
    _visibilityTimer?.cancel();
    print('🗑️ VideoScreenLifecycleMixin: Disposed');
  }

  /// Get current lifecycle state
  Map<String, bool> getLifecycleState() {
    return {
      'isScreenVisible': _isScreenVisible,
      'isTabActive': _isTabActive,
    };
  }
}
