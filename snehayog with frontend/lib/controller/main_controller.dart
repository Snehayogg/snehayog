import 'package:flutter/material.dart';

class MainController extends ChangeNotifier {
  int _currentIndex = 0;
  final List<String> _routes = ['/yog', '/sneha', '/upload', '/profile'];

  int get currentIndex => _currentIndex;
  String get currentRoute => _routes[_currentIndex];

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
}
