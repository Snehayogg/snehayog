import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class GoogleAuthService {
  static const String _userIdKey = 'user_id';
  static const String _userNameKey = 'user_name';
  static const String _userProfilePicKey = 'user_profile_pic';
  static const String _userEmailKey = 'user_email';
  static const String _userTokenKey = 'user_token';

  // Your Google Client ID
  static const String _webClientId =
      'YOUR_GOOGLE_CLIENT_ID.apps.googleusercontent.com';

  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'profile',
    ],
    clientId: kIsWeb ? _webClientId : null,
  );

  Map<String, dynamic>? _currentUser;

  Map<String, dynamic>? get currentUser => _currentUser;

  Future<Map<String, dynamic>?> _updateAndSaveUser(
      GoogleSignInAccount googleUser) async {
    final GoogleSignInAuthentication googleAuth =
        await googleUser.authentication;

    if (googleAuth.accessToken == null) {
      throw Exception('Failed to get access token from Google');
    }

    final userInfo = {
      'id': googleUser.id,
      'name': googleUser.displayName ?? 'User',
      'email': googleUser.email,
      'photoUrl': googleUser.photoUrl ?? 'https://via.placeholder.com/150',
      'token': googleAuth.accessToken,
    };

    await saveUserData(
      userId: userInfo['id']!,
      userName: userInfo['name']!,
      profilePic: userInfo['photoUrl']!,
      email: userInfo['email']!,
      token: userInfo['token']!,
    );

    _currentUser = userInfo;
    return _currentUser;
  }

  Future<String?> getCurrentUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  Future<bool> isLoggedIn() async {
    final userId = await getCurrentUserId();
    return userId != null;
  }

  Future<Map<String, dynamic>?> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) return null; // User cancelled the sign-in
      return await _updateAndSaveUser(googleUser);
    } catch (error) {
      print('Error signing in with Google: $error');
      // Clear any partial data
      await logout();
      return null;
    }
  }

  Future<void> saveUserData({
    required String userId,
    required String userName,
    required String profilePic,
    String? email,
    String? token,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIdKey, userId);
    await prefs.setString(_userNameKey, userName);
    await prefs.setString(_userProfilePicKey, profilePic);
    if (email != null) await prefs.setString(_userEmailKey, email);
    if (token != null) await prefs.setString(_userTokenKey, token);
  }

  Future<Map<String, dynamic>?> getUserData() async {
    try {
      // First try to get stored user data
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString(_userIdKey);
      final userName = prefs.getString(_userNameKey);
      final userProfilePic = prefs.getString(_userProfilePicKey);
      final userEmail = prefs.getString(_userEmailKey);
      final userToken = prefs.getString(_userTokenKey);

      // If we have stored data, return it
      if (userId != null && userName != null && userToken != null) {
        return {
          'id': userId,
          'name': userName,
          'profilePic': userProfilePic ?? 'https://via.placeholder.com/150',
          'email': userEmail ?? '',
          'token': userToken,
        };
      }

      // If no stored data, try silent sign-in
      final GoogleSignInAccount? googleUser = await _googleSignIn.signInSilently();
      if (googleUser != null) {
        return await _updateAndSaveUser(googleUser);
      }

      // No stored data and no silent sign-in possible
      return null;
    } catch (e) {
      print('Error getting user data: $e');
      return null;
    }
  }

  Future<void> logout() async {
    try {
      await _googleSignIn.signOut();
    } catch (e) {
      print('Error signing out from Google: $e');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_userIdKey);
    await prefs.remove(_userNameKey);
    await prefs.remove(_userProfilePicKey);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_userTokenKey);
    _currentUser = null;
  }
}
