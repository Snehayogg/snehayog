import 'package:flutter/material.dart';
import 'package:snehayog/services/google_auth_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:snehayog/config/app_config.dart';

class GoogleSignInController extends ChangeNotifier {
  final GoogleAuthService _authService = GoogleAuthService();
  final bool _isLoading = false;
  String? _error;
  Map<String, dynamic>? _userData;

  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isSignedIn => _userData != null;
  Map<String, dynamic>? get userData => _userData;

  // Base URL for API endpoints
  static String get baseUrl {
    return AppConfig.baseUrl;
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

Future<Map<String, dynamic>?> signIn() async {
  try {
    final userInfo = await _authService.signInWithGoogle();
    if (userInfo != null) {
      _userData = userInfo;
      await _registerUser();
      notifyListeners();
    }
    return userInfo;
  } catch (e) {
    _error = e.toString();
    notifyListeners();
    return null;
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
