import 'package:flutter/material.dart';

class MainController extends ChangeNotifier {
  int _currentIndex = 0;
  final List<String> _routes = ['/yog', '/sneha', '/upload', '/profile'];
  
  // Callback to pause all videos when screen changes
  VoidCallback? _pauseAllVideosCallback;

  int get currentIndex => _currentIndex;
  String get currentRoute => _routes[_currentIndex];

  // Method to register pause callback
  void registerPauseCallback(VoidCallback callback) {
    _pauseAllVideosCallback = callback;
  }

  // Method to unregister pause callback
  void unregisterPauseCallback() {
    _pauseAllVideosCallback = null;
  }

  void changeIndex(int index) {
    if (index >= 0 && index < _routes.length) {
      // Pause all videos before changing screen
      _pauseAllVideosCallback?.call();
      
      _currentIndex = index;
      notifyListeners();
    }
  }

  void navigateToProfile() {
    // Pause all videos before changing screen
    _pauseAllVideosCallback?.call();
    
    _currentIndex = 3; // Profile index
    notifyListeners();
  }
}
