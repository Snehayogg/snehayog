import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:snehayog/config/app_config.dart';
// **NEW: Import JWT decoder**
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:snehayog/config/google_sign_in_config.dart';
import 'package:snehayog/services/location_permission_service.dart';
import 'package:snehayog/services/location_service.dart';

class AuthService {
  // ✅ Use platform-specific client ID
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: GoogleSignInConfig.scopes,
    clientId: GoogleSignInConfig.platformClientId,
  );

  // Global navigator key for accessing context
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  Future<Map<String, dynamic>?> signInWithGoogle() async {
    try {
      print('🔐 Starting Google Sign-In process...');

      // **NEW: Check configuration before proceeding**
      if (!GoogleSignInConfig.isConfigured) {
        print('❌ Google Sign-In not properly configured!');
        GoogleSignInConfig.printConfig();
        throw Exception(
            'Google Sign-In configuration missing. Please set OAuth 2.0 Client IDs.');
      }

      // **NEW: Validate OAuth 2.0 Client ID format**
      if (!GoogleSignInConfig.isValidClientId) {
        final error = GoogleSignInConfig.getConfigurationError();
        print('❌ OAuth 2.0 Client ID validation failed: $error');
        GoogleSignInConfig.printConfig();
        throw Exception('OAuth 2.0 Client ID validation failed: $error');
      }

      // **NEW: Print configuration for debugging**
      GoogleSignInConfig.printConfig();

      // Ensure previous account session is fully cleared so account chooser appears
      try {
        await _googleSignIn.signOut();
        await _googleSignIn.disconnect();
      } catch (e) {
        print('ℹ️ Pre sign-in disconnect/signOut ignored: $e');
      }

      // Also clear any locally cached fallback to avoid auto-restoring prior account
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('fallback_user');
      } catch (_) {}

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        print('❌ User cancelled Google Sign-In');
        return null;
      }

      print('✅ Google Sign-In successful for: ${googleUser.email}');

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        print('❌ Failed to get ID token from Google');
        throw Exception('Failed to get authentication token from Google');
      }

      print('🔑 Got ID token, attempting backend authentication...');

      // First, authenticate with backend to get JWT
      try {
        final authResponse = await http
            .post(
              Uri.parse('${AppConfig.baseUrl}/api/auth'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'idToken': idToken}),
            )
            .timeout(const Duration(seconds: 10));

        print('📡 Backend auth response status: ${authResponse.statusCode}');
        print('📡 Backend auth response body: ${authResponse.body}');

        if (authResponse.statusCode == 200) {
          final authData = jsonDecode(authResponse.body);
          print('✅ Backend authentication successful');
          print(
              '🔑 JWT Token received: ${authData['token']?.substring(0, 20)}...');

          // Save JWT in shared preferences
          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setString('jwt_token', authData['token']);

          // Then register/update user profile
          final userData = {
            'googleId': googleUser.id,
            'name': googleUser.displayName ?? 'User',
            'email': googleUser.email,
            'profilePic': googleUser.photoUrl,
          };

          try {
            final registerResponse = await http
                .post(
                  Uri.parse('${AppConfig.baseUrl}/api/users/register'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode(userData),
                )
                .timeout(const Duration(seconds: 10));

            print(
                '📡 User registration response status: ${registerResponse.statusCode}');

            if (registerResponse.statusCode == 200 ||
                registerResponse.statusCode == 201) {
              print('✅ User registration successful');

              // Show location onboarding for new users
              // Add small delay to ensure context is available
              Future.delayed(const Duration(milliseconds: 500), () {
                _showLocationOnboardingAfterSignIn();
              });
            } else {
              print('⚠️ User registration failed: ${registerResponse.body}');
            }
          } catch (e) {
            print('⚠️ User registration error (non-critical): $e');
          }

          // Return combined user data
          return {
            'id': googleUser.id,
            'googleId': googleUser.id,
            'name': googleUser.displayName ?? 'User',
            'email': googleUser.email,
            'profilePic': googleUser.photoUrl,
            'token': authData['token'],
          };
        } else {
          print('❌ Backend authentication failed: ${authResponse.body}');

          // **IMPROVED: Better error messages for JWT issues**
          final errorBody = jsonDecode(authResponse.body);
          String errorMessage = 'Backend authentication failed';

          if (errorBody['error'] != null) {
            errorMessage = errorBody['error'];
            if (errorBody['details'] != null) {
              errorMessage += ': ${errorBody['details']}';
            }
          }

          // Check for specific JWT/Google auth errors
          if (errorMessage.contains('JWT_SECRET') ||
              errorMessage.contains('GOOGLE_CLIENT_ID')) {
            errorMessage =
                '🔐 Backend configuration error: $errorMessage\n\nPlease check your backend .env file for missing variables.';
          } else if (errorMessage.contains('Google SignIn failed')) {
            errorMessage =
                '🔐 Google authentication failed: $errorMessage\n\nPlease verify your Google OAuth configuration.';
          }

          // Try to provide a fallback for development/testing
          if (AppConfig.baseUrl.contains('localhost') ||
              AppConfig.baseUrl.contains('192.168')) {
            print(
                '🔄 Backend appears to be local, creating fallback session...');
            return await _createFallbackSession(googleUser);
          }

          throw Exception(errorMessage);
        }
      } catch (e) {
        print('❌ Backend communication error: $e');

        // If backend is unreachable, create a fallback session
        if (e.toString().contains('SocketException') ||
            e.toString().contains('Connection refused') ||
            e.toString().contains('timeout')) {
          print('🔄 Backend unreachable, creating fallback session...');
          return await _createFallbackSession(googleUser);
        }

        throw Exception('Failed to communicate with backend: $e');
      }
    } catch (e) {
      print('❌ Google Sign-In Error: $e');
      throw Exception('Sign-in failed: $e');
    }
  }

  // **NEW: Create fallback session when backend is unavailable**
  Future<Map<String, dynamic>?> _createFallbackSession(
      GoogleSignInAccount googleUser) async {
    try {
      print('🔄 Creating fallback session for: ${googleUser.email}');

      // Generate a temporary token for local use
      final tempToken =
          'temp_${DateTime.now().millisecondsSinceEpoch}_${googleUser.id}';

      // Save temporary token
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('jwt_token', tempToken);
      await prefs.setString(
          'fallback_user',
          jsonEncode({
            'id': googleUser.id,
            'googleId': googleUser.id, // Add explicit googleId field
            'name': googleUser.displayName ?? 'User',
            'email': googleUser.email,
            'profilePic': googleUser.photoUrl,
            'isFallback': true,
          }));

      print('✅ Fallback session created successfully');

      // Show location onboarding for fallback users too
      Future.delayed(const Duration(milliseconds: 500), () {
        _showLocationOnboardingAfterSignIn();
      });

      return {
        'id': googleUser.id,
        'googleId': googleUser.id, // Add explicit googleId field
        'name': googleUser.displayName ?? 'User',
        'email': googleUser.email,
        'profilePic': googleUser.photoUrl,
        'token': tempToken,
        'isFallback': true,
      };
    } catch (e) {
      print('❌ Failed to create fallback session: $e');
      return null;
    }
  }

  // Check if user is already logged in
  Future<bool> isLoggedIn() async {
    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('jwt_token');

      // Check if it's a fallback session
      String? fallbackUser = prefs.getString('fallback_user');
      if (fallbackUser != null) {
        print('🔄 User has fallback session');
        return true;
      }

      // Verify token with backend if possible
      try {
        final response = await http.get(
          Uri.parse('${AppConfig.baseUrl}/api/users/profile'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(seconds: 5));

        return response.statusCode == 200;
      } catch (e) {
        print('⚠️ Token verification failed, but keeping session: $e');
        return true; // Keep the session even if backend is unreachable
      }
    } catch (e) {
      print('❌ Error checking login status: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      print('🚪 Signing out user...');

      // **FIXED: Sign out from Google first**
      await _googleSignIn.signOut();
      // Also revoke granted permissions so the next sign-in prompts account chooser
      try {
        await _googleSignIn.disconnect();
      } catch (e) {
        print('ℹ️ Google disconnect failed (non-fatal): $e');
      }

      // **FIXED: Clear ALL stored authentication data**
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('jwt_token');
      await prefs.remove('fallback_user');

      // **FIXED: Clear any cached user data**
      await prefs.remove('user_profile');
      await prefs.remove('user_videos');
      await prefs.remove('last_user_id');

      // **FIXED: Clear all SharedPreferences keys related to user data**
      final keys = prefs.getKeys();
      for (String key in keys) {
        if (key.startsWith('user_') ||
            key.startsWith('video_') ||
            key.startsWith('profile_') ||
            key.startsWith('profile_cache_') ||
            key.startsWith('profile_cache_timestamp_') ||
            key.startsWith('auth_')) {
          await prefs.remove(key);
          print('🗑️ Cleared cached data: $key');
        }
      }

      // Explicit flags
      // NOTE: Do not remove payment setup flags so user payment profile persists across sessions

      print('✅ Sign out successful - All user data cleared');
    } catch (e) {
      print('❌ Error during sign out: $e');
      throw Exception('Sign out failed: $e');
    }
  }

  Future<bool> isSignedIn() async {
    try {
      return await _googleSignIn.isSignedIn();
    } catch (e) {
      print('❌ Error checking Google sign-in status: $e');
      return false;
    }
  }

  // Get user data from JWT token
  Future<Map<String, dynamic>?> getUserData(
      {bool skipTokenRefresh = false}) async {
    try {
      print('🔍 AuthService: Getting user data...');

      // Wait for internal retrieval with a sensible timeout; on timeout, fallback to cached user
      return await _getUserDataInternal(skipTokenRefresh: skipTokenRefresh)
          .timeout(const Duration(seconds: 12), onTimeout: () async {
        try {
          final prefs = await SharedPreferences.getInstance();
          final token = prefs.getString('jwt_token');
          final fallbackUser = prefs.getString('fallback_user');
          if (fallbackUser != null) {
            final data = jsonDecode(fallbackUser);
            return {
              'id': data['id'],
              'googleId': data['googleId'] ?? data['id'],
              'name': data['name'],
              'email': data['email'],
              'profilePic': data['profilePic'],
              'token': token,
              'isFallback': true,
            };
          }
        } catch (_) {}
        return null;
      });
    } catch (e) {
      print('❌ AuthService: Error getting user data: $e');
      return null;
    }
  }

  /// **INTERNAL: Actual user data retrieval logic**
  Future<Map<String, dynamic>?> _getUserDataInternal(
      {bool skipTokenRefresh = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('jwt_token');
      String? fallbackUser = prefs.getString('fallback_user');

      print('🔍 AuthService: Token found: ${'Yes'}');
      print('🔍 AuthService: Fallback user found: ${'Yes'}');

      // **NEW: Validate JWT token before using it**
      if (!skipTokenRefresh && !isTokenValid(token)) {
        print('❌ AuthService: JWT token is invalid or expired');

        // Try to refresh the token
        token = await refreshTokenIfNeeded();
        if (token == null) {
          print(
              '❌ AuthService: Failed to refresh token, clearing invalid token');
          await prefs.remove('jwt_token');
          token = null;
        }
      }

      if (token != null) {
        // **NEW: Log token information for debugging**
        final tokenInfo = getTokenInfo(token);
        if (tokenInfo != null) {
          print('🔍 AuthService: Token info:');
          print('   User ID: ${tokenInfo['userId']}');
          print('   Expires: ${tokenInfo['expiryDate']}');
          print('   Minutes until expiry: ${tokenInfo['minutesUntilExpiry']}');
          print('   Expires soon: ${tokenInfo['expiresSoon']}');
        }
      }

      // Check if we have fallback user data
      if (fallbackUser != null) {
        print('🔄 Found fallback user data, using it');
        final userData = jsonDecode(fallbackUser);
        return {
          'id': userData['id'],
          'googleId': userData['googleId'] ??
              userData['id'], // Add googleId if available
          'name': userData['name'],
          'email': userData['email'],
          'profilePic': userData['profilePic'],
          'token': token,
          'isFallback': true,
        };
      }

      // Try to verify token with backend and get actual user data
      try {
        print('🔍 Attempting to verify token with backend...');
        if (token != null) {
          print(
              '🔍 Token being sent (first 20 chars): ${token.substring(0, 20)}...');
          print('🔍 Token length: ${token.length}');
          print('🔍 Token type: ${token.runtimeType}');
        } else {
          print('🔍 Token is null!');
        }

        final response = await http.get(
          Uri.parse('${AppConfig.baseUrl}/api/users/profile'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(
            seconds: 3)); // **OPTIMIZED: Reduced timeout for faster startup**

        if (response.statusCode == 200) {
          final userData = jsonDecode(response.body);
          print('✅ Retrieved user profile from backend');

          // Save this as fallback data for future use
          final fallbackData = {
            'id': userData['googleId'] ?? userData['id'],
            'googleId':
                userData['googleId'] ?? userData['id'], // Preserve googleId
            'name': userData['name'],
            'email': userData['email'],
            'profilePic': userData['profilePic'],
          };
          await prefs.setString('fallback_user', jsonEncode(fallbackData));

          return {
            'id': userData['googleId'] ?? userData['id'],
            'googleId':
                userData['googleId'] ?? userData['id'], // Preserve googleId
            'name': userData['name'],
            'email': userData['email'],
            'profilePic': userData['profilePic'],
            'token': token,
          };
        } else {
          print('⚠️ Backend returned status: ${response.statusCode}');
          // If backend returns error, still try to use fallback if available
          print('🔄 Backend error, using fallback user data');
          if (fallbackUser != null) {
            final userData = jsonDecode(fallbackUser);
            return {
              'id': userData['id'],
              'googleId': userData['googleId'] ??
                  userData['id'], // Add googleId if available
              'name': userData['name'],
              'email': userData['email'],
              'profilePic': userData['profilePic'],
              'token': token,
              'isFallback': true,
            };
          }
        }
      } catch (e) {
        print('⚠️ Error fetching user profile from backend: $e');
        // If backend is unreachable, use fallback data if available
        print('🔄 Backend unreachable, using fallback user data');
        if (fallbackUser != null) {
          final userData = jsonDecode(fallbackUser);
          return {
            'id': userData['id'],
            'googleId': userData['googleId'] ??
                userData['id'], // Add googleId if available
            'name': userData['name'],
            'email': userData['email'],
            'profilePic': userData['profilePic'],
            'token': token,
            'isFallback': true,
          };
        }
      }

      // If we reach here, no valid data is available
      print('⚠️ No valid user data available, returning null');
      return null;
    } catch (e) {
      print('❌ Error getting user data: $e');
      return null;
    }
  }

  /// Check if JWT token is valid and not expired
  bool isTokenValid(String? token) {
    try {
      if (token == null || token.isEmpty) return false;

      // Decode JWT token
      Map<String, dynamic> decodedToken = JwtDecoder.decode(token);

      // Check if token has expiry
      if (!decodedToken.containsKey('exp')) {
        print('❌ JWT Token missing expiry claim');
        return false;
      }

      // Get expiry timestamp
      int expiryTimestamp = decodedToken['exp'];
      DateTime expiryDate =
          DateTime.fromMillisecondsSinceEpoch(expiryTimestamp * 1000);
      DateTime now = DateTime.now();

      print('🔍 JWT Token expiry: $expiryDate');
      print('🔍 Current time: $now');
      print(
          '🔍 Token expires in: ${expiryDate.difference(now).inMinutes} minutes');

      // Check if token is expired
      if (now.isAfter(expiryDate)) {
        print('❌ JWT Token has expired');
        return false;
      }

      // Check if token expires soon (within 5 minutes)
      if (expiryDate.difference(now).inMinutes < 5) {
        print('⚠️ JWT Token expires soon (within 5 minutes)');
      }

      print('✅ JWT Token is valid');
      return true;
    } catch (e) {
      print('❌ Error validating JWT token: $e');
      return false;
    }
  }

  /// Get token expiry information
  Map<String, dynamic>? getTokenInfo(String? token) {
    try {
      if (token == null || token.isEmpty) return null;

      Map<String, dynamic> decodedToken = JwtDecoder.decode(token);

      if (!decodedToken.containsKey('exp')) return null;

      int expiryTimestamp = decodedToken['exp'];
      DateTime expiryDate =
          DateTime.fromMillisecondsSinceEpoch(expiryTimestamp * 1000);
      DateTime now = DateTime.now();

      return {
        'expiryDate': expiryDate,
        'currentTime': now,
        'minutesUntilExpiry': expiryDate.difference(now).inMinutes,
        'isExpired': now.isAfter(expiryDate),
        'expiresSoon': expiryDate.difference(now).inMinutes < 5,
        'userId': decodedToken['id'],
        'issuedAt': decodedToken.containsKey('iat')
            ? DateTime.fromMillisecondsSinceEpoch(decodedToken['iat'] * 1000)
            : null,
      };
    } catch (e) {
      print('❌ Error getting token info: $e');
      return null;
    }
  }

  /// Refresh token if it's expired or expiring soon
  Future<String?> refreshTokenIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('jwt_token');

      // Check if token is valid
      if (isTokenValid(token)) {
        print('✅ Token is still valid, no refresh needed');
        return token;
      }

      print('🔄 Token expired or invalid, attempting to refresh...');
      // Try to get a new token by re-authenticating with Google
      try {
        final newToken = await _reauthenticateWithGoogle();
        if (newToken != null) {
          print('✅ Successfully obtained new token through re-authentication');
          return newToken;
        }
      } catch (e) {
        print('❌ Re-authentication failed: $e');
      }

      print('❌ Failed to refresh token, user needs to re-login');
      return null;
    } catch (e) {
      print('❌ Error refreshing token: $e');
      return null;
    }
  }

  /// Re-authenticate with Google to get a fresh token
  Future<String?> _reauthenticateWithGoogle() async {
    try {
      print('🔄 Attempting to re-authenticate with Google...');

      // Check if user is already signed in
      if (!await _googleSignIn.isSignedIn()) {
        print('❌ User not signed in with Google, cannot re-authenticate');
        return null;
      }

      // Get fresh authentication
      final GoogleSignInAccount? googleUser =
          await _googleSignIn.signInSilently();
      if (googleUser == null) {
        print('❌ Silent sign-in failed, user needs to re-authenticate');
        return null;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        print('❌ Failed to get fresh ID token from Google');
        return null;
      }

      // Authenticate with backend to get new JWT
      final authResponse = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/api/auth'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'idToken': idToken}),
          )
          .timeout(const Duration(seconds: 10));

      if (authResponse.statusCode == 200) {
        final authData = jsonDecode(authResponse.body);
        final newToken = authData['token'];

        // Save new token
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', newToken);

        print('✅ Successfully obtained new JWT token');
        return newToken;
      } else {
        print('❌ Backend authentication failed: ${authResponse.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Error during re-authentication: $e');
      return null;
    }
  }

  /// Clear expired tokens and force re-login
  Future<void> clearExpiredTokens() async {
    try {
      print('🧹 Clearing expired tokens...');
      final prefs = await SharedPreferences.getInstance();

      // Remove JWT token
      await prefs.remove('jwt_token');

      // Keep fallback user data for re-authentication
      print('✅ Expired tokens cleared, user needs to re-login');
    } catch (e) {
      print('❌ Error clearing expired tokens: $e');
    }
  }

  /// Check if user needs to re-login due to expired tokens
  Future<bool> needsReLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('jwt_token');

      // Check if token is expired
      if (!isTokenValid(token)) {
        print('⚠️ Token is expired, user needs to re-login');
        return true;
      }

      return false;
    } catch (e) {
      print('❌ Error checking re-login status: $e');
      return true;
    }
  }

  /// Show location onboarding for new users after sign-in
  Future<void> _showLocationOnboardingAfterSignIn() async {
    try {
      print('📍 Showing location onboarding for new user...');
      final context = navigatorKey.currentContext;
      if (context == null) {
        print('❌ No context available for location onboarding');
        return;
      }

      await LocationPermissionService.requestLocationPermissionOnStartup(
        context,
        appName: 'Snehayog',
      );
      print('✅ Location onboarding completed');
    } catch (e) {
      print('❌ Error showing location onboarding: $e');
    }
  }

  /// Alternative method to show location onboarding with explicit context
  static Future<void> showLocationOnboarding(BuildContext context) async {
    try {
      print('📍 Showing location onboarding...');

      await LocationPermissionService.requestLocationPermissionOnStartup(
        context,
        appName: 'Snehayog',
      );
    } catch (e) {
      print('❌ Error showing location onboarding: $e');
    }
  }

  /// **TESTING: Force show location dialog (ignores SharedPreferences check)**
  static Future<void> forceShowLocationDialog(BuildContext context) async {
    try {
      print('🧪 TESTING: Force showing location permission dialog...');

      // Reset onboarding state first
      await LocationPermissionService.resetPermissionRequest();

      // Then show the dialog
      await showLocationOnboarding(context);
    } catch (e) {
      print('❌ Error force showing location dialog: $e');
    }
  }

  /// **TESTING: Check if location permission is granted**
  static Future<bool> checkLocationPermission() async {
    final locationService = LocationService();
    return await locationService.isLocationPermissionGranted();
  }
}
