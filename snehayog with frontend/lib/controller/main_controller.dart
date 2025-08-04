import 'package:flutter/material.dart';

class MainController extends ChangeNotifier {
  int _currentIndex = 0;
  final List<String> _routes = ['/yog', '/sneha', '/upload', '/profile'];
  bool _isAppInForeground = true;

  int get currentIndex => _currentIndex;
  String get currentRoute => _routes[_currentIndex];
  bool get isAppInForeground => _isAppInForeground;

  void changeIndex(int index) {
    if (index >= 0 && index < _routes.length) {
      _currentIndex = index;
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
}
