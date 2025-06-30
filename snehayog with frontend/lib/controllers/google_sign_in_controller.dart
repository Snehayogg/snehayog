import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:snehayog/services/google_auth_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class GoogleSignInController extends ChangeNotifier {
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final GoogleAuthService _authService = GoogleAuthService();
  bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _userData;

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isSignedIn => _userData != null;
  Map<String, dynamic>? get userData => _userData;

  // Base URL for API endpoints
  static String get baseUrl {
    return 'http://192.168.0.197:5000';
  }

  GoogleSignInController() {
    _init();
  }

  Future<void> _init() async {
    _userData = await _authService.getUserData();
    if (_userData != null) {
      await _registerUser();
    }
    notifyListeners();
  }

  Future<void> _registerUser() async {
    if (_userData == null) return;

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/users/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'googleId': _userData!['id'],
          'name': _userData!['name'],
          'email': _userData!['email'],
          'profilePic': _userData!['profilePic'],
        }),
      );

      if (response.statusCode != 200 && response.statusCode != 201) {
        print('User registration failed: ${response.body}');
      }
    } catch (e) {
      print('Error registering user: $e');
    }
  }

  Future<bool> signIn() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final userInfo = await _authService.signInWithGoogle();

      if (userInfo == null) {
        _error = 'Sign in was cancelled';
        return false;
      }

      _userData = userInfo;
      await _registerUser();
      return true;
    } catch (e) {
      _error = e.toString();
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    try {
      await _authService.logout();
      _userData = null;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }
}
