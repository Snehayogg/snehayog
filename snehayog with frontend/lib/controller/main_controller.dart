import 'package:flutter/material.dart';

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
    print('🔄 MainController: Changing index from $_currentIndex to $index');
    print('🔄 MainController: Current time: ${DateTime.now()}');

    if (_currentIndex != index) {
      // If we're leaving the video tab (index 0), pause videos IMMEDIATELY
      if (_currentIndex == 0) {
        print(
            '⏸️ MainController: LEAVING VIDEO TAB - pausing videos immediately');
        print('⏸️ MainController: Calling pause callback...');

        // Call pause callback immediately
        _pauseVideosCallback?.call();
        print('⏸️ MainController: Pause callback executed');

        // Force pause again after a short delay to ensure videos stop
        Future.delayed(const Duration(milliseconds: 50), () {
          if (_currentIndex != 0) {
            print('🛑 MainController: Double-checking videos are paused');
            _pauseVideosCallback?.call();
          }
        });

        // Additional safety check after a longer delay
        Future.delayed(const Duration(milliseconds: 200), () {
          if (_currentIndex != 0) {
            print(
                '🛑 MainController: Final safety check - pausing videos again');
            _pauseVideosCallback?.call();
          }
        });
      }

      // Update the current index
      _currentIndex = index;
      print('🔄 MainController: Index updated to $_currentIndex');

      // If we're entering the video tab, resume videos with a delay
      if (index == 0) {
        print(
            '▶️ MainController: Entering video tab, will resume videos shortly');
        // Small delay to ensure clean state, then resume
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_currentIndex == 0 && isAppInForeground) {
            print(
                '▶️ MainController: Resuming videos after entering video tab');
            _resumeVideosCallback?.call();
          }
        });
      }

      notifyListeners();
    }
  }

  void navigateToProfile() {
    _currentIndex = 3; // Profile index
    notifyListeners();
  }

  void setAppInForeground(bool inForeground) {
    _isAppInForeground = inForeground;
    notifyListeners();
  }

  /// Check if the current screen is the video screen
  bool get isVideoScreen => _currentIndex == 0;

  /// Check if videos should be playing based on current state
  bool get shouldPlayVideos => _isAppInForeground && isVideoScreen;

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
    if (_pauseVideosCallback != null) {
      _pauseVideosCallback!();

      // Additional safety pause after a short delay
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_pauseVideosCallback != null) {
          print('🛑 MainController: Safety pause after force pause');
          _pauseVideosCallback!();
        }
      });
    }
  }

  /// Check if videos should be paused based on current state
  bool get shouldPauseVideos => !isVideoScreen || !isAppInForeground;
}
