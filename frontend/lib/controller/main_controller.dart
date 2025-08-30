import 'package:flutter/material.dart';
// Removed: import 'package:snehayog/core/managers/video_manager.dart';

class MainController extends ChangeNotifier {
  int _currentIndex = 0;
  final List<String> _routes = ['/yog', '/sneha', '/upload', '/profile'];
  bool _isAppInForeground = true;

  // Add a callback function to pause videos
  VoidCallback? _pauseVideosCallback;
  VoidCallback? _resumeVideosCallback;

  int get currentIndex => _currentIndex;
  String get currentRoute => _routes[_currentIndex];
  bool get isAppInForeground => _isAppInForeground;

  /// Change the current index and handle video control
  void changeIndex(int index) {
    if (_currentIndex == index) return; // No change needed

    print('🔄 MainController: Changing index from $_currentIndex to $index');

    _handleIndexChangeFallback(index);

    // **CRITICAL FIX: Add delay before updating index to ensure proper state transition**
    Future.delayed(const Duration(milliseconds: 100), () {
      // Update the current index
      _currentIndex = index;
      print('🔄 MainController: Index updated to $_currentIndex');
      notifyListeners();
    });
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

      // **SIMPLIFIED: App foreground state update (VideoManager removed)**

      notifyListeners();
    }
  }

  /// Check if the current screen is the video screen
  bool get isVideoScreen => _currentIndex == 0;

  /// Check if videos should be playing based on current state
  bool get shouldPlayVideos => _isAppInForeground && isVideoScreen;

  /// **SIMPLIFIED: Video tracking info (VideoManager removed)**
  Map<String, dynamic>? getVideoTrackingInfo() {
    return null; // VideoManager was removed
  }

  /// **SIMPLIFIED: Current visible video index (VideoManager removed)**
  int get currentVisibleVideoIndex {
    return 0; // VideoManager was removed
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

    // **SIMPLIFIED: Use callback since VideoManager was removed**
    _pauseVideosCallback?.call();
  }

  /// Check if videos should be paused based on current state
  bool get shouldPauseVideos => !isVideoScreen || !isAppInForeground;

  /// Emergency stop all videos (for critical situations)
  void emergencyStopVideos() {
    print('🚨 MainController: EMERGENCY STOP - pausing all videos immediately');

    // **SIMPLIFIED: Use callback since VideoManager was removed**
    _pauseVideosCallback?.call();

    // Multiple safety calls to ensure videos are stopped
    Future.delayed(const Duration(milliseconds: 50), () {
      _pauseVideosCallback?.call();
    });

    Future.delayed(const Duration(milliseconds: 150), () {
      _pauseVideosCallback?.call();
    });
  }

  /// **SIMPLIFIED: Update current video index (VideoManager removed)**
  void updateCurrentVideoIndex(int newIndex) {
    // VideoManager was removed
  }

  /// **SIMPLIFIED: Get comprehensive video state info (VideoManager removed)**
  Map<String, dynamic> getComprehensiveVideoState() {
    return <String, dynamic>{
      'currentIndex': _currentIndex,
      'isVideoScreen': isVideoScreen,
      'isAppInForeground': _isAppInForeground,
      'shouldPlayVideos': shouldPlayVideos,
      'shouldPauseVideos': shouldPauseVideos,
      'hasVideoManager': false, // VideoManager was removed
    };
  }
}
