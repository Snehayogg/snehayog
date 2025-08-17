import 'package:flutter/material.dart';
import 'package:snehayog/services/authservices.dart';

class GoogleSignInController extends ChangeNotifier {
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _userData;

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isSignedIn => _userData != null;
  Map<String, dynamic>? get userData => _userData;

  GoogleSignInController() {
    _init();
  }

  Future<void> _init() async {
    _userData = await _authService.getUserData();
    notifyListeners();
  }

  Future<Map<String, dynamic>?> signIn() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final userInfo = await _authService.signInWithGoogle();
      if (userInfo != null) {
        _userData = userInfo;
        _error = null;
      } else {
        _error = 'Sign in failed';
      }

      _isLoading = false;
      notifyListeners();
      return userInfo;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      await _authService.signOut();
      _userData = null;
      _error = null;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }
}
