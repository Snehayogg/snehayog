import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vayu/core/managers/video_controller_manager.dart';

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

  }

  /// Handle tab becoming active
  void onTabBecameActive() {
    if (!_isTabActive) {
      _isTabActive = true;


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


      // Immediately pause videos
      _pauseAllVideos();
    }
  }

  /// Handle screen visibility changes
  void onScreenVisibilityChanged(bool isVisible) {
    if (_isScreenVisible != isVisible) {
      _isScreenVisible = isVisible;


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

      // Simplified: Just play active video if controller is ready
      _playActiveVideo();
    } catch (e) {

    }
  }

  /// Play the active video
  void _playActiveVideo() {
    try {
      if (_isScreenVisible && _isTabActive && mounted) {

        _controllerManager.playActiveVideo();
      }
    } catch (e) {

    }
  }

  /// Pause all videos
  void _pauseAllVideos() {
    try {

      _controllerManager.pauseAllVideos();
    } catch (e) {

    }
  }

  /// Clean up resources
  void disposeLifecycleMixin() {
    _visibilityTimer?.cancel();

  }

  /// Get current lifecycle state
  Map<String, bool> getLifecycleState() {
    return {
      'isScreenVisible': _isScreenVisible,
      'isTabActive': _isTabActive,
    };
  }
}
