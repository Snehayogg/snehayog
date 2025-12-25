import 'package:flutter/material.dart';
import 'package:vayu/services/authservices.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';

class GoogleSignInController extends ChangeNotifier {
  final AuthService _authService = AuthService();
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _userData;

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isSignedIn => _userData != null;
  Map<String, dynamic>? get userData => _userData;

  /// Manually check and refresh authentication status
  Future<void> checkAuthStatus() async {
    await _initInBackground();
  }

  GoogleSignInController() {
    // **OPTIMIZED: Don't block UI during initialization**
    _initInBackground();
  }

  Future<void> _initInBackground() async {
    try {
      // **OPTIMIZED: Use cached data immediately, verify in background**
      // First, try to get cached user data instantly (no network call)
      try {
        final prefs = await SharedPreferences.getInstance();
        final fallbackUser = prefs.getString('fallback_user');
        if (fallbackUser != null) {
          final cachedData = jsonDecode(fallbackUser);
          _userData = {
            'id': cachedData['id'],
            'googleId': cachedData['googleId'] ?? cachedData['id'],
            'name': cachedData['name'],
            'email': cachedData['email'],
            'profilePic': cachedData['profilePic'],
            'token': prefs.getString('jwt_token'),
            'isFallback': true,
          };
          _isLoading = false;
          notifyListeners();
          print('✅ GoogleSignInController: Using cached user data (instant)');

          // Refresh from backend in background (non-blocking)
          unawaited(_refreshUserDataInBackground());
          return;
        }
      } catch (e) {
        print('⚠️ GoogleSignInController: Error loading cached data: $e');
      }

      _isLoading = true;
      notifyListeners();

      // Check if user is already logged in
      final isLoggedIn = await _authService.isLoggedIn();
      if (isLoggedIn) {
        print(
            '✅ GoogleSignInController: User is already logged in, getting user data...');
        _userData = await _authService.getUserData();
        print(
            '✅ GoogleSignInController: User data loaded: ${_userData?['email']}');
      } else {
        print(
            'ℹ️ GoogleSignInController: User is not logged in, attempting auto-login...');

        // **NEW: Try auto-login with device ID (for persistent login after reinstall)**
        try {
          final autoLoginResult = await _authService.autoLoginWithDeviceId();
          if (autoLoginResult != null) {
            print('✅ GoogleSignInController: Auto-login successful!');
            _userData = autoLoginResult;
          } else {
            print(
                'ℹ️ GoogleSignInController: Auto-login not available - user needs to login manually');
            _userData = null;
          }
        } catch (e) {
          print(
              '⚠️ GoogleSignInController: Auto-login failed (non-critical): $e');
          _userData = null;
        }
      }
    } catch (e) {
      print('⚠️ GoogleSignInController: Error during background init: $e');
      _error = e.toString();
      _userData = null; // Ensure userData is null on error
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

  /// **OPTIMIZED: Refresh user data in background without blocking UI**
  Future<void> _refreshUserDataInBackground() async {
    try {
      final freshData = await _authService.getUserData();
      if (freshData != null) {
        _userData = freshData;
        notifyListeners();
        print('✅ GoogleSignInController: User data refreshed from backend');
      }
    } catch (e) {
      print('⚠️ GoogleSignInController: Error refreshing user data: $e');
      // Keep cached data on error
    }
  }
}
