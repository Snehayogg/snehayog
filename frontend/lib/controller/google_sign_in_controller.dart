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
    // **OPTIMIZED: Don't block UI during initialization**
    _initInBackground();
  }

  Future<void> _initInBackground() async {
    try {
      _isLoading = true;
      notifyListeners();

      _userData = await _authService.getUserData();
    } catch (e) {
      print('⚠️ GoogleSignInController: Error during background init: $e');
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> signIn() async {
    try {
      print('🔐 GoogleSignInController: Starting sign in...');

      _isLoading = true;
      _error = null;
      notifyListeners();

      final userInfo = await _authService.signInWithGoogle();
      if (userInfo != null) {
        _userData = userInfo;
        _error = null;
        print(
            '✅ GoogleSignInController: Sign in successful for: ${userInfo['email']}');
      } else {
        _error = 'Sign in failed';
        print(
            '❌ GoogleSignInController: Sign in failed - No user data returned');
      }

      _isLoading = false;
      notifyListeners();
      return userInfo;
    } catch (e) {
      print('❌ GoogleSignInController: Error during sign in: $e');
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return null;
    }
  }

  Future<void> signOut() async {
    try {
      print('🚪 GoogleSignInController: Starting sign out...');

      await _authService.signOut();

      // **FIXED: Clear ALL state and force refresh**
      _userData = null;
      _error = null;
      _isLoading = false;

      print('✅ GoogleSignInController: Sign out completed - State cleared');
      notifyListeners();
    } catch (e) {
      print('❌ GoogleSignInController: Error during sign out: $e');
      _error = e.toString();
      notifyListeners();
    }
  }

  /// **Clear error state for retry functionality**
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// **FIXED: Force refresh authentication state after account switch**
  Future<void> refreshAuthState() async {
    try {
      print('🔄 GoogleSignInController: Refreshing authentication state...');

      _isLoading = true;
      notifyListeners();

      // **FIXED: Get fresh user data from AuthService**
      _userData = await _authService.getUserData();

      if (_userData != null) {
        print(
            '✅ GoogleSignInController: Auth state refreshed for: ${_userData?['email']}');
        _error = null;
      } else {
        print('⚠️ GoogleSignInController: No user data found after refresh');
        _error = 'No authentication data found';
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      print('❌ GoogleSignInController: Error refreshing auth state: $e');
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }
}
