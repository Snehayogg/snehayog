import 'package:flutter/material.dart';
import 'package:snehayog/core/managers/video_manager.dart';

class MainController extends ChangeNotifier {
  int _currentIndex = 0;
  final List<String> _routes = ['/yog', '/sneha', '/upload', '/profile'];
  bool _isAppInForeground = true;

  // Add a callback function to pause videos
  VoidCallback? _pauseVideosCallback;
  VoidCallback? _resumeVideosCallback;

  // **NEW: VideoManager integration**
  VideoManager? _videoManager;

  int get currentIndex => _currentIndex;
  String get currentRoute => _routes[_currentIndex];
  bool get isAppInForeground => _isAppInForeground;

  /// **NEW: Set VideoManager reference**
  void setVideoManager(VideoManager videoManager) {
    _videoManager = videoManager;
    print('🔗 MainController: VideoManager reference set');
  }

  /// **NEW: Get VideoManager reference**
  VideoManager? get videoManager => _videoManager;

  /// Change the current index and handle video control
  void changeIndex(int index) {
    if (_currentIndex == index) return; // No change needed

    print('🔄 MainController: Changing index from $_currentIndex to $index');

    // **NEW: Use VideoManager for navigation state management**
    if (_videoManager != null) {
      _videoManager!.onNavigationTabChanged(index);
    } else {
      // Fallback to original behavior if VideoManager not available
      _handleIndexChangeFallback(index);
    }

    // Update the current index
    _currentIndex = index;
    print('🔄 MainController: Index updated to $_currentIndex');

    notifyListeners();
  }

  /// **NEW: Fallback method for when VideoManager is not available**
  void _handleIndexChangeFallback(int index) {
    // If we're leaving the video tab (index 0), pause videos immediately
    if (_currentIndex == 0) {
      print(
          '⏸️ MainController: LEAVING VIDEO TAB - pausing videos immediately (fallback)');

      // IMMEDIATE video pause
      _pauseVideosCallback?.call();

      // Multiple safety delays to ensure videos are paused
      Future.delayed(const Duration(milliseconds: 50), () {
        if (_currentIndex != 0) {
          print(
              '🛑 MainController: Safety check 1 - forcing video pause again');
          _pauseVideosCallback?.call();
        }
      });

      Future.delayed(const Duration(milliseconds: 100), () {
        if (_currentIndex != 0) {
          print(
              '🛑 MainController: Safety check 2 - forcing video pause again');
          _pauseVideosCallback?.call();
        }
      });

      Future.delayed(const Duration(milliseconds: 200), () {
        if (_currentIndex != 0) {
          print('🛑 MainController: Safety check 3 - final video pause');
          _pauseVideosCallback?.call();
        }
      });
    }

    // If we're entering the video tab, resume videos
    if (index == 0 && isAppInForeground) {
      print(
          '▶️ MainController: Entering video tab, resuming videos (fallback)');
      _resumeVideosCallback?.call();
    }
  }

  void navigateToProfile() {
    _currentIndex = 3; // Profile index
    notifyListeners();
  }

  void setAppInForeground(bool inForeground) {
    if (_isAppInForeground != inForeground) {
      _isAppInForeground = inForeground;
      print(
          '📱 MainController: App foreground state changed to ${inForeground ? "FOREGROUND" : "BACKGROUND"}');

      // **NEW: Update VideoManager with app foreground state**
      if (_videoManager != null) {
        _videoManager!.updateAppForegroundState(inForeground);
      }

      notifyListeners();
    }
  }

  /// Check if the current screen is the video screen
  bool get isVideoScreen => _currentIndex == 0;

  /// Check if videos should be playing based on current state
  bool get shouldPlayVideos => _isAppInForeground && isVideoScreen;

  /// **NEW: Get current video tracking info from VideoManager**
  Map<String, dynamic>? getVideoTrackingInfo() {
    if (_videoManager != null) {
      return _videoManager!.getVideoTrackingInfo();
    }
    return null;
  }

  /// **NEW: Get current visible video index from VideoManager**
  int get currentVisibleVideoIndex {
    if (_videoManager != null) {
      return _videoManager!.currentVisibleVideoIndex;
    }
    return 0;
  }

  /// Register callback to pause videos
  void registerPauseVideosCallback(VoidCallback callback) {
    _pauseVideosCallback = callback;
  }

  /// Register callback to resume videos
  void registerResumeVideosCallback(VoidCallback callback) {
    _resumeVideosCallback = callback;
  }

  /// Unregister callbacks
  void unregisterCallbacks() {
    _pauseVideosCallback = null;
    _resumeVideosCallback = null;
  }

  /// Force pause all videos (called from external sources)
  void forcePauseVideos() {
    print('🛑 MainController: Force pausing all videos');

    // **NEW: Use VideoManager if available**
    if (_videoManager != null) {
      _videoManager!.forcePauseAllVideos();
    } else {
      // Fallback to callback
      _pauseVideosCallback?.call();
    }
  }

  /// Check if videos should be paused based on current state
  bool get shouldPauseVideos => !isVideoScreen || !isAppInForeground;

  /// Emergency stop all videos (for critical situations)
  void emergencyStopVideos() {
    print('🚨 MainController: EMERGENCY STOP - pausing all videos immediately');

    // **NEW: Use VideoManager if available**
    if (_videoManager != null) {
      _videoManager!.forcePauseAllVideos();
    } else {
      // Fallback to callback
      _pauseVideosCallback?.call();

      // Multiple safety calls to ensure videos are stopped
      Future.delayed(const Duration(milliseconds: 50), () {
        _pauseVideosCallback?.call();
      });

      Future.delayed(const Duration(milliseconds: 150), () {
        _pauseVideosCallback?.call();
      });
    }
  }

  /// **NEW: Update current video index (called from VideoScreen)**
  void updateCurrentVideoIndex(int newIndex) {
    if (_videoManager != null) {
      _videoManager!.updateCurrentVideoIndex(newIndex);
    }
  }

  /// **NEW: Get comprehensive video state info**
  Map<String, dynamic> getComprehensiveVideoState() {
    final baseState = <String, dynamic>{
      'currentIndex': _currentIndex,
      'isVideoScreen': isVideoScreen,
      'isAppInForeground': _isAppInForeground,
      'shouldPlayVideos': shouldPlayVideos,
      'shouldPauseVideos': shouldPauseVideos,
      'hasVideoManager': _videoManager != null,
    };

    // Add VideoManager info if available
    if (_videoManager != null) {
      baseState.addAll(_videoManager!.getVideoTrackingInfo());
    }

    return baseState;
  }
}
