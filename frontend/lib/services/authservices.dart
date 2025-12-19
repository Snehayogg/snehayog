import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:vayu/config/app_config.dart';
// **NEW: Import JWT decoder**
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:vayu/config/google_sign_in_config.dart';
import 'package:vayu/services/location_onboarding_service.dart';
import 'package:vayu/utils/app_logger.dart';
import 'package:vayu/services/device_id_service.dart';
import 'package:vayu/services/notification_service.dart';

class AuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: GoogleSignInConfig.scopes,
    clientId: GoogleSignInConfig.platformClientId,
  );

  // Global navigator key for accessing context
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  Future<Map<String, dynamic>?> signInWithGoogle(
      {bool forceAccountPicker = true}) async {
    try {
      AppLogger.log('🔐 Starting Google Sign-In process...');

      // **NEW: Check configuration before proceeding**
      if (!GoogleSignInConfig.isConfigured) {
        AppLogger.log('❌ Google Sign-In not properly configured!');
        GoogleSignInConfig.printConfig();
        throw Exception(
            'Google Sign-In configuration missing. Please set OAuth 2.0 Client IDs.');
      }

      // **NEW: Validate OAuth 2.0 Client ID format**
      if (!GoogleSignInConfig.isValidClientId) {
        final error = GoogleSignInConfig.getConfigurationError();
        AppLogger.log('❌ OAuth 2.0 Client ID validation failed: $error');
        GoogleSignInConfig.printConfig();
        throw Exception('OAuth 2.0 Client ID validation failed: $error');
      }

      // **NEW: Print configuration for debugging**
      GoogleSignInConfig.printConfig();

      // **IMPROVED: Only clear Google session if we want to force account picker (manual sign-in)**
      // This preserves Google session caching for auto-login flows
      // **FIXED: Don't clear fallback_user here - preserve it until successful sign-in**
      if (forceAccountPicker) {
        AppLogger.log(
            '🔄 Force account picker enabled - clearing previous Google session...');
        try {
          await _googleSignIn.signOut();
          await _googleSignIn.disconnect();
        } catch (e) {
          AppLogger.log('ℹ️ Pre sign-in disconnect/signOut ignored: $e');
        }

        // **IMPROVED: Keep fallback_user until successful sign-in to prevent data loss**
        // Only clear it after we have new valid token and user data
        AppLogger.log('ℹ️ Preserving fallback_user until successful sign-in');
      } else {
        AppLogger.log(
            'ℹ️ Preserving Google session cache for seamless sign-in');
      }

      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        AppLogger.log('❌ User cancelled Google Sign-In');
        return null;
      }

      AppLogger.log('✅ Google Sign-In successful for: ${googleUser.email}');

      // Acquire ID token; on web, prefer platform getTokens as authentication.idToken can be null
      String? idToken;
      try {
        if (kIsWeb) {
          final tokens = await GoogleSignInPlatform.instance
              .getTokens(email: googleUser.email);
          idToken = tokens.idToken;
        } else {
          final GoogleSignInAuthentication googleAuth =
              await googleUser.authentication;
          idToken = googleAuth.idToken;
        }
      } catch (e) {
        AppLogger.log('❌ Error obtaining Google tokens: $e');
      }

      if (idToken == null) {
        AppLogger.log('❌ Failed to get ID token from Google');
        throw Exception('Failed to get authentication token from Google');
      }

      AppLogger.log('🔑 Got ID token, attempting backend authentication...');

      // **NEW: Get device ID to send to backend**
      final deviceId = await DeviceIdService().getDeviceId();

      // First, authenticate with backend to get JWT
      try {
        // **OPTIMIZED: Reduced timeout for faster sign-in**
        final authResponse = await http
            .post(
              Uri.parse('${AppConfig.baseUrl}/api/auth'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'idToken': idToken,
                'deviceId': deviceId, // **NEW: Send device ID to backend
              }),
            )
            .timeout(const Duration(seconds: 8));

        AppLogger.log(
            '📡 Backend auth response status: ${authResponse.statusCode}');
        AppLogger.log('📡 Backend auth response body: ${authResponse.body}');

        if (authResponse.statusCode == 200) {
          final authData = jsonDecode(authResponse.body);
          AppLogger.log('✅ Backend authentication successful');
          AppLogger.log(
              '🔑 JWT Token received: ${authData['token']?.substring(0, 20)}...');

          // Save JWT in shared preferences
          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setString('jwt_token', authData['token']);

          // **NEW: Retry saving FCM token after successful login**
          try {
            final notificationService = NotificationService();
            if (notificationService.isInitialized) {
              await notificationService.retrySaveToken();
            }
          } catch (e) {
            AppLogger.log('⚠️ Error retrying FCM token save: $e');
          }

          // **PROFESSIONAL: Sync watch history after login to merge anonymous and authenticated history**
          // This ensures watched videos don't appear again after login
          try {
            final syncResponse = await http
                .post(
                  Uri.parse(
                      '${AppConfig.baseUrl}/api/videos/sync-watch-history'),
                  headers: {
                    'Content-Type': 'application/json',
                    'Authorization': 'Bearer ${authData['token']}',
                  },
                  body: jsonEncode({
                    'deviceId': deviceId,
                  }),
                )
                .timeout(const Duration(seconds: 5));

            if (syncResponse.statusCode == 200) {
              final syncData = jsonDecode(syncResponse.body);
              AppLogger.log(
                  '✅ Watch history synced successfully: ${syncData['syncedCount']} videos');
            } else {
              AppLogger.log(
                  '⚠️ Watch history sync failed: ${syncResponse.statusCode}');
            }
          } catch (e) {
            // Non-critical - don't fail login if sync fails
            AppLogger.log('⚠️ Error syncing watch history (non-critical): $e');
          }

          // Then register/update user profile
          final userData = {
            'googleId': googleUser.id,
            'name': googleUser.displayName ?? 'User',
            'email': googleUser.email,
            'profilePic': googleUser.photoUrl,
            'profilePicture': googleUser.photoUrl, // For backend compatibility
          };

          Map<String, dynamic>? registeredUserData;

          try {
            // **OPTIMIZED: Reduced timeout for faster sign-in**
            final registerResponse = await http
                .post(
                  Uri.parse('${AppConfig.baseUrl}/api/users/register'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode(userData),
                )
                .timeout(const Duration(seconds: 8));

            AppLogger.log(
                '📡 User registration response status: ${registerResponse.statusCode}');

            if (registerResponse.statusCode == 200 ||
                registerResponse.statusCode == 201) {
              AppLogger.log('✅ User registration successful');
              final regData = jsonDecode(registerResponse.body);
              registeredUserData = regData['user'];

              // **FIX: Track referral code if present (for new users)**
              // **OPTIMIZED: Make referral tracking non-blocking (fire and forget)**
              final isNewUser = regData['user']?['isNewUser'] ?? false;
              if (isNewUser) {
                // Fire and forget - don't block sign-in completion
                unawaited(_trackReferralCodeAsync());
              }

              // Show location onboarding for new users
              // Add small delay to ensure context is available
              Future.delayed(const Duration(milliseconds: 500), () {
                _showLocationOnboardingAfterSignIn();
              });
            } else {
              AppLogger.log(
                  '⚠️ User registration failed: ${registerResponse.body}');
            }
          } catch (e) {
            AppLogger.log('⚠️ User registration error (non-critical): $e');
          }

          // **FIXED: Use Google account data if backend data is missing**
          // Priority: 1) Backend registered data, 2) Google account data
          final finalName =
              registeredUserData?['name'] ?? googleUser.displayName ?? 'User';
          final finalProfilePic = registeredUserData?['profilePic'] ??
              registeredUserData?['profilePicture'] ??
              googleUser.photoUrl;

          // Save to SharedPreferences with fresh Google data
          final fallbackData = {
            'id': googleUser.id,
            'googleId': googleUser.id,
            'name': finalName,
            'email': googleUser.email,
            'profilePic': finalProfilePic,
          };
          await prefs.setString('fallback_user', jsonEncode(fallbackData));
          AppLogger.log('✅ Saved fallback_user with Google account data');

          // **CRITICAL: ALWAYS store device ID after successful authentication**
          await _ensureDeviceIdStored(deviceId);

          // Return combined user data
          return {
            'id': googleUser.id,
            'googleId': googleUser.id,
            'name': finalName,
            'email': googleUser.email,
            'profilePic': finalProfilePic,
            'token': authData['token'],
          };
        } else {
          AppLogger.log(
              '❌ Backend authentication failed: ${authResponse.body}');

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
            AppLogger.log(
                '🔄 Backend appears to be local, creating fallback session...');
            return await _createFallbackSession(googleUser);
          }

          throw Exception(errorMessage);
        }
      } catch (e) {
        AppLogger.log('❌ Backend communication error: $e');

        // If backend is unreachable, try to reconnect and retry
        if (e.toString().contains('SocketException') ||
            e.toString().contains('Connection refused') ||
            e.toString().contains('timeout')) {
          AppLogger.log(
              '🔄 Backend unreachable, checking server connectivity...');

          // Try to find a working server
          try {
            await AppConfig.checkAndUpdateServerUrl();
            AppLogger.log('🔄 Retrying with updated server URL...');

            // Retry the authentication with new URL
            final authResponse = await http
                .post(
                  Uri.parse('${AppConfig.baseUrl}/api/auth'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'idToken': idToken,
                    'deviceId': deviceId, // **NEW: Send device ID on retry
                  }),
                )
                .timeout(const Duration(seconds: 10));

            if (authResponse.statusCode == 200) {
              final authData = jsonDecode(authResponse.body);
              SharedPreferences prefs = await SharedPreferences.getInstance();
              await prefs.setString('jwt_token', authData['token']);

              // Continue with user registration...
              final userData = {
                'googleId': googleUser.id,
                'name': googleUser.displayName ?? 'User',
                'email': googleUser.email,
                'profilePic': googleUser.photoUrl,
              };

              await http.post(
                Uri.parse('${AppConfig.baseUrl}/api/users/register'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(userData),
              );

              // **CRITICAL: ALWAYS store device ID after successful retry authentication**
              await _ensureDeviceIdStored(deviceId);

              return {
                'id': googleUser.id,
                'googleId': googleUser.id,
                'name': googleUser.displayName ?? 'User',
                'email': googleUser.email,
                'profilePic': googleUser.photoUrl,
                'token': authData['token'],
              };
            }
          } catch (retryError) {
            AppLogger.log('❌ Retry failed: $retryError');
          }

          AppLogger.log('🔄 All servers failed, creating fallback session...');
          return await _createFallbackSession(googleUser);
        }

        throw Exception('Failed to communicate with backend: $e');
      }
    } catch (e) {
      AppLogger.log('❌ Google Sign-In Error: $e');
      throw Exception('Sign-in failed: $e');
    }
  }

  // **NEW: Create fallback session when backend is unavailable**
  Future<Map<String, dynamic>?> _createFallbackSession(
      GoogleSignInAccount googleUser) async {
    try {
      AppLogger.log('🔄 Creating fallback session for: ${googleUser.email}');

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

      // **CRITICAL: ALWAYS store device ID even in fallback mode**
      await _ensureDeviceIdStored(await DeviceIdService().getDeviceId());

      AppLogger.log('✅ Fallback session created successfully');

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
      AppLogger.log('❌ Failed to create fallback session: $e');
      return null;
    }
  }

  // **NEW: Show location onboarding after successful sign in**
  static void _showLocationOnboardingAfterSignIn() async {
    try {
      AppLogger.log(
          '📍 AuthService: Checking if location onboarding should be shown...');

      // Check if we should show location onboarding
      final shouldShow =
          await LocationOnboardingService.shouldShowLocationOnboarding();

      if (shouldShow) {
        AppLogger.log('📍 AuthService: Showing location onboarding...');

        // Get the current context
        final context = navigatorKey.currentContext;
        if (context != null) {
          // Show location permission request
          final granted =
              await LocationOnboardingService.showLocationOnboarding(context);

          if (granted) {
            AppLogger.log('✅ AuthService: Location permission granted');
          } else {
            AppLogger.log('❌ AuthService: Location permission denied');
          }
        } else {
          AppLogger.log(
              '❌ AuthService: No context available for location onboarding');
        }
      } else {
        AppLogger.log('📍 AuthService: Location onboarding not needed');
      }
    } catch (e) {
      AppLogger.log('❌ AuthService: Error in location onboarding: $e');
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
        AppLogger.log('🔄 User has fallback session');
        // Verify in background (non-blocking)
        unawaited(_verifyTokenInBackground(token));
        return true;
      }

      // If no token, try auto-login with device ID (for persistent login after reinstall)
      if (token == null || token.isEmpty) {
        AppLogger.log(
            'ℹ️ No JWT token found, attempting auto-login with device ID...');

        // **IMPROVED: Wait for auto-login if device ID is recognized (for seamless reinstall experience)**
        try {
          final deviceIdService = DeviceIdService();
          final deviceId = await deviceIdService.getDeviceId();

          // Check if device ID is valid and might be recognized
          if (deviceId.isNotEmpty && !deviceId.startsWith('fallback_')) {
            // Check if device has logged in before (with timeout)
            final hasStoredDeviceId = await deviceIdService
                .hasStoredDeviceId()
                .timeout(const Duration(seconds: 3), onTimeout: () => false);

            if (hasStoredDeviceId) {
              AppLogger.log(
                  '✅ Device ID recognized - waiting for auto-login to complete...');
              // Wait for auto-login with timeout (max 10 seconds)
              final autoLoginResult = await autoLoginWithDeviceId()
                  .timeout(const Duration(seconds: 10), onTimeout: () {
                AppLogger.log('⚠️ Auto-login timed out');
                return null;
              });

              if (autoLoginResult != null) {
                AppLogger.log(
                    '✅ Auto-login successful - user session restored');
                return true; // User is now logged in
              } else {
                AppLogger.log(
                    'ℹ️ Auto-login failed or cancelled - user needs to login manually');
                return false;
              }
            } else {
              AppLogger.log(
                  'ℹ️ Device ID not recognized - first time login required');
              return false;
            }
          } else {
            AppLogger.log('ℹ️ Invalid device ID - first time login required');
            return false;
          }
        } catch (e) {
          AppLogger.log('⚠️ Error during auto-login check: $e');
          // Fallback: try auto-login in background (non-blocking)
          unawaited(autoLoginWithDeviceId().then((userData) {
            if (userData != null) {
              AppLogger.log('✅ Auto-login successful in background');
            }
          }));
          return false;
        }
      }

      // **OPTIMIZED: Return cached status immediately, verify in background**
      AppLogger.log('✅ Using cached token status (optimistic)');
      // Verify token in background (non-blocking)
      unawaited(_verifyTokenInBackground(token));
      return true; // Optimistic return - assume valid if token exists
    } catch (e) {
      AppLogger.log('❌ Error checking login status: $e');
      return false;
    }
  }

  /// **IMPROVED: Verify token in background without blocking - tries refresh before removing**
  Future<void> _verifyTokenInBackground(String? token) async {
    if (token == null || token.isEmpty) return;

    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/users/profile'),
        headers: {'Authorization': 'Bearer $token'},
      ).timeout(const Duration(seconds: 3));

      // Only clear token if it's actually unauthorized (401/403), not on network errors
      if (response.statusCode == 401 || response.statusCode == 403) {
        AppLogger.log(
            '⚠️ Token verification failed - unauthorized (${response.statusCode})');

        // **IMPROVED: Try to refresh token before removing it**
        final refreshedToken = await refreshTokenIfNeeded();
        if (refreshedToken != null && refreshedToken != token) {
          AppLogger.log('✅ Token refreshed successfully in background');
          return; // Token was refreshed, keep session
        }

        // Only remove if token is actually expired AND refresh failed
        if (!isTokenValid(token)) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('jwt_token');
          AppLogger.log(
              '⚠️ Removed expired token after refresh attempt failed');
        } else {
          AppLogger.log(
              'ℹ️ Token is still valid according to expiry, keeping it (may be backend issue)');
        }
      } else if (response.statusCode == 200) {
        AppLogger.log('✅ Token verified successfully in background');
      } else {
        AppLogger.log(
            '⚠️ Token verification returned status ${response.statusCode}, keeping token');
      }
    } catch (e) {
      AppLogger.log('⚠️ Background token verification failed: $e');
      // **IMPROVED: Keep session even if backend is unreachable - don't remove token on network errors**
      // Only remove if token is clearly expired (not just network issue)
      try {
        if (!isTokenValid(token)) {
          AppLogger.log(
              '⚠️ Token is expired and backend unreachable, removing token');
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('jwt_token');
        } else {
          AppLogger.log(
              'ℹ️ Network error but token still valid, keeping session');
        }
      } catch (_) {
        // Ignore errors in expiry check
      }
    }
  }

  Future<void> signOut() async {
    try {
      AppLogger.log('🚪 Signing out user...');

      // **FIXED: Sign out from Google first**
      await _googleSignIn.signOut();
      // Also revoke granted permissions so the next sign-in prompts account chooser
      try {
        await _googleSignIn.disconnect();
      } catch (e) {
        AppLogger.log('ℹ️ Google disconnect failed (non-fatal): $e');
      }

      // **FIXED: Clear ALL stored authentication data**
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove('jwt_token');
      await prefs.remove('fallback_user');
      await prefs.remove('auth_skip_login');
      await prefs.remove('user_profile');
      await prefs.remove('user_videos');
      await prefs.remove('last_user_id');

      // **NEW: Clear device ID on logout (optional - remove if you want device ID to persist)**
      // Note: Keeping device ID allows user to skip login after reinstall
      // await DeviceIdService().clearDeviceId();

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
          AppLogger.log('🗑️ Cleared cached data: $key');
        }
      }

      // Explicit flags
      // NOTE: Do not remove payment setup flags so user payment profile persists across sessions

      AppLogger.log('✅ Sign out successful - All user data cleared');
    } catch (e) {
      AppLogger.log('❌ Error during sign out: $e');
      throw Exception('Sign out failed: $e');
    }
  }

  Future<bool> isSignedIn() async {
    try {
      return await _googleSignIn.isSignedIn();
    } catch (e) {
      AppLogger.log('❌ Error checking Google sign-in status: $e');
      return false;
    }
  }

  // Get user data from JWT token
  Future<Map<String, dynamic>?> getUserData(
      {bool skipTokenRefresh = false}) async {
    try {
      AppLogger.log('🔍 AuthService: Getting user data...');

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
      AppLogger.log('❌ AuthService: Error getting user data: $e');
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

      AppLogger.log('🔍 AuthService: Token found: ${'Yes'}');
      AppLogger.log('🔍 AuthService: Fallback user found: ${'Yes'}');

      // **IMPROVED: Validate JWT token before using it - be conservative about removal**
      if (!skipTokenRefresh && token != null && !isTokenValid(token)) {
        AppLogger.log('⚠️ AuthService: JWT token appears invalid or expired');

        // Try to refresh the token first
        final refreshedToken = await refreshTokenIfNeeded();
        if (refreshedToken != null) {
          AppLogger.log('✅ AuthService: Token refreshed successfully');
          token = refreshedToken;
        } else {
          // **IMPROVED: Only remove token if it's definitely expired (not just network issue)**
          // Check expiry one more time to be sure
          if (!isTokenValid(token)) {
            AppLogger.log(
                '❌ AuthService: Token is expired and refresh failed, clearing token');
            await prefs.remove('jwt_token');
            token = null;
          } else {
            AppLogger.log(
                'ℹ️ AuthService: Token validation failed but token appears valid, keeping it (may be network issue)');
          }
        }
      }

      if (token != null) {
        // **NEW: Log token information for debugging**
        final tokenInfo = getTokenInfo(token);
        if (tokenInfo != null) {
          AppLogger.log('🔍 AuthService: Token info:');
          AppLogger.log('   User ID: ${tokenInfo['userId']}');
          AppLogger.log('   Expires: ${tokenInfo['expiryDate']}');
          AppLogger.log(
              '   Minutes until expiry: ${tokenInfo['minutesUntilExpiry']}');
          AppLogger.log('   Expires soon: ${tokenInfo['expiresSoon']}');
        }
      }

      // **FIXED: Always check backend FIRST for fresh data, fallback is only for offline scenarios**
      Map<String, dynamic>? fallbackDataMap;
      if (fallbackUser != null) {
        AppLogger.log(
            '🔄 Found fallback user data available (will use if backend fails)');
        fallbackDataMap = jsonDecode(fallbackUser);
      }

      // Try to verify token with backend and get actual user data
      try {
        AppLogger.log('🔍 Attempting to verify token with backend...');
        if (token != null) {
          AppLogger.log(
              '🔍 Token being sent (first 20 chars): ${token.substring(0, 20)}...');
          AppLogger.log('🔍 Token length: ${token.length}');
          AppLogger.log('🔍 Token type: ${token.runtimeType}');
        } else {
          AppLogger.log('🔍 Token is null!');
        }

        final response = await http.get(
          Uri.parse('${AppConfig.baseUrl}/api/users/profile'),
          headers: {'Authorization': 'Bearer $token'},
        ).timeout(const Duration(
            seconds: 3)); // **OPTIMIZED: Reduced timeout for faster startup**

        if (response.statusCode == 200) {
          final userData = jsonDecode(response.body);
          AppLogger.log('✅ Retrieved user profile from backend');

          // **FIXED: Always update fallback with fresh backend data**
          final fallbackData = {
            'id': userData['googleId'] ?? userData['id'],
            'googleId':
                userData['googleId'] ?? userData['id'], // Preserve googleId
            'name': userData['name'],
            'email': userData['email'],
            'profilePic': userData['profilePic'],
          };
          await prefs.setString('fallback_user', jsonEncode(fallbackData));
          AppLogger.log('✅ Updated fallback_user with fresh backend data');

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
          AppLogger.log('⚠️ Backend returned status: ${response.statusCode}');
          // If backend returns error, still try to use fallback if available
          AppLogger.log('🔄 Backend error, using fallback user data');
          if (fallbackDataMap != null) {
            final userData = fallbackDataMap;
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
        AppLogger.log('⚠️ Error fetching user profile from backend: $e');
        // **IMPROVED: If backend is unreachable, use fallback data if available**
        // Don't remove token on network errors - user might just be offline
        final isNetworkError = e.toString().contains('SocketException') ||
            e.toString().contains('Connection refused') ||
            e.toString().contains('timeout') ||
            e.toString().contains('Failed host lookup');

        if (isNetworkError) {
          AppLogger.log(
              '🔄 Network error detected, using fallback user data (preserving session)');
        } else {
          AppLogger.log('🔄 Backend error, using fallback user data');
        }

        if (fallbackDataMap != null) {
          final userData = fallbackDataMap;
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
        } else if (token != null && isTokenValid(token)) {
          // **NEW: Even without fallback data, if token is valid, return minimal user info**
          AppLogger.log(
              'ℹ️ No fallback data but token is valid, returning minimal user info');
          return {
            'token': token,
            'isFallback': true,
          };
        }
      }

      // If we reach here, no valid data is available
      AppLogger.log('⚠️ No valid user data available, returning null');
      return null;
    } catch (e) {
      AppLogger.log('❌ Error getting user data: $e');
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
        AppLogger.log('❌ JWT Token missing expiry claim');
        return false;
      }

      // Get expiry timestamp
      int expiryTimestamp = decodedToken['exp'];
      DateTime expiryDate =
          DateTime.fromMillisecondsSinceEpoch(expiryTimestamp * 1000);
      DateTime now = DateTime.now();

      AppLogger.log('🔍 JWT Token expiry: $expiryDate');
      AppLogger.log('🔍 Current time: $now');
      AppLogger.log(
          '🔍 Token expires in: ${expiryDate.difference(now).inMinutes} minutes');

      // Check if token is expired
      if (now.isAfter(expiryDate)) {
        AppLogger.log('❌ JWT Token has expired');
        return false;
      }

      // Check if token expires soon (within 5 minutes)
      if (expiryDate.difference(now).inMinutes < 5) {
        AppLogger.log('⚠️ JWT Token expires soon (within 5 minutes)');
      }

      AppLogger.log('✅ JWT Token is valid');
      return true;
    } catch (e) {
      AppLogger.log('❌ Error validating JWT token: $e');
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
      AppLogger.log('❌ Error getting token info: $e');
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
        AppLogger.log('✅ Token is still valid, no refresh needed');
        return token;
      }

      AppLogger.log('🔄 Token expired or invalid, attempting to refresh...');
      // Try to get a new token by re-authenticating with Google
      try {
        final newToken = await _reauthenticateWithGoogle();
        if (newToken != null) {
          AppLogger.log(
              '✅ Successfully obtained new token through re-authentication');
          return newToken;
        }
      } catch (e) {
        AppLogger.log('❌ Re-authentication failed: $e');
      }

      AppLogger.log('❌ Failed to refresh token, user needs to re-login');
      return null;
    } catch (e) {
      AppLogger.log('❌ Error refreshing token: $e');
      return null;
    }
  }

  /// **IMPROVED: Auto-login using device ID (for persistent login after reinstall)**
  /// Attempts to restore user session if device ID indicates user logged in before
  /// Automatically triggers Google Sign-In if device ID is recognized but silent sign-in fails
  Future<Map<String, dynamic>?> autoLoginWithDeviceId() async {
    try {
      AppLogger.log('🔄 Attempting auto-login with device ID...');

      final deviceIdService = DeviceIdService();

      // Step 1: Get device ID (works even after reinstall)
      final deviceId = await deviceIdService.getDeviceId();
      if (deviceId.isEmpty || deviceId.startsWith('fallback_')) {
        AppLogger.log('❌ Invalid device ID - cannot auto-login');
        return null;
      }

      AppLogger.log('✅ Device ID retrieved: ${deviceId.substring(0, 8)}...');

      // Step 2: Check with backend if this device has logged in before
      final hasStoredDeviceId = await deviceIdService.hasStoredDeviceId();
      if (!hasStoredDeviceId) {
        AppLogger.log(
            'ℹ️ Device ID not found on backend - first time login required');
        return null;
      }

      AppLogger.log(
          '✅ Device ID verified with backend - user has logged in before');

      // **NEW: Get user email from backend for seamless auto-login**
      String? userEmail;
      try {
        final resolvedBaseUrl = await AppConfig.getBaseUrlWithFallback();
        final checkResponse = await http
            .post(
              Uri.parse('$resolvedBaseUrl/api/auth/check-device'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'deviceId': deviceId}),
            )
            .timeout(const Duration(seconds: 5));

        if (checkResponse.statusCode == 200) {
          final checkData = jsonDecode(checkResponse.body);
          userEmail = checkData['userEmail'] as String?;
          AppLogger.log(
              '✅ User email retrieved from backend: ${userEmail?.substring(0, 5)}...');
        }
      } catch (e) {
        AppLogger.log('⚠️ Failed to get user email from backend: $e');
      }

      AppLogger.log('🔄 Attempting to restore Google Sign-In session...');

      // Step 3: Try multiple Google Sign-In methods (improved reliability)
      GoogleSignInAccount? googleUser;

      // Method 1: Try silent sign-in (works if Google session is cached)
      // **IMPROVED: This will automatically use the previously linked Google account**
      try {
        googleUser = await _googleSignIn.signInSilently();
        if (googleUser != null) {
          // **VERIFY: Check if the signed-in account matches the device ID's user**
          if (userEmail != null &&
              googleUser.email.toLowerCase() != userEmail.toLowerCase()) {
            AppLogger.log(
                '⚠️ Silent sign-in returned different account (${googleUser.email}) than device account ($userEmail)');
            // Still proceed - user might have switched accounts
          } else {
            AppLogger.log('✅ Silent sign-in successful with matching account');
          }
        }
      } catch (e) {
        AppLogger.log('⚠️ Silent sign-in failed: $e');
      }

      // Method 2: If silent fails, check current sign-in status
      if (googleUser == null) {
        try {
          final isSignedIn = await _googleSignIn.isSignedIn();
          if (isSignedIn) {
            googleUser = await _googleSignIn.signInSilently();
            if (googleUser != null) {
              AppLogger.log('✅ Silent sign-in successful after status check');
            }
          }
        } catch (e) {
          AppLogger.log('⚠️ Check sign-in status failed: $e');
        }
      }

      // Method 3: If still null, try getting current user
      if (googleUser == null) {
        try {
          googleUser = _googleSignIn.currentUser;
          if (googleUser != null) {
            AppLogger.log('✅ Using current Google user');
          }
        } catch (e) {
          AppLogger.log('⚠️ Get current user failed: $e');
        }
      }

      // **IMPROVED: Method 4: If device ID is recognized but no Google session exists,
      // automatically trigger Google Sign-In - Google will remember the account
      // On Android, Google One Tap will automatically select the previously used account
      // On iOS, Google will show account picker but will pre-select the previously used account
      if (googleUser == null) {
        AppLogger.log(
            '🔄 Device ID recognized but no Google session - automatically triggering sign-in...');
        AppLogger.log(
            'ℹ️ Google will automatically select the previously used account (${userEmail ?? "unknown"})');
        try {
          // **IMPROVED: Call signIn - Google will automatically select the previously linked account**
          // On Android: Google One Tap will show the correct account automatically
          // On iOS: Account picker will pre-select the correct account
          googleUser = await _googleSignIn.signIn();
          if (googleUser != null) {
            // **VERIFY: Check if the selected account matches the device ID's user**
            if (userEmail != null &&
                googleUser.email.toLowerCase() != userEmail.toLowerCase()) {
              AppLogger.log(
                  '⚠️ User selected different account (${googleUser.email}) than device account ($userEmail)');
              AppLogger.log(
                  'ℹ️ Proceeding with selected account - user may have switched accounts');
              // Still proceed - user's choice to use different account
            } else {
              AppLogger.log(
                  '✅ Automatic sign-in successful with matching account: ${googleUser.email}');
            }
          } else {
            AppLogger.log('ℹ️ User cancelled automatic sign-in');
            return null;
          }
        } catch (e) {
          AppLogger.log('❌ Automatic sign-in failed: $e');
          return null;
        }
      }

      AppLogger.log('✅ Google user found: ${googleUser.email}');

      // Step 4: Get ID token from Google
      String? idToken;
      try {
        if (kIsWeb) {
          final tokens = await GoogleSignInPlatform.instance
              .getTokens(email: googleUser.email);
          idToken = tokens.idToken;
        } else {
          final GoogleSignInAuthentication googleAuth =
              await googleUser.authentication;
          idToken = googleAuth.idToken;
        }
      } catch (e) {
        AppLogger.log('❌ Failed to get ID token: $e');
        return null;
      }

      if (idToken == null || idToken.isEmpty) {
        AppLogger.log('❌ ID token is null or empty');
        return null;
      }

      // Step 5: Authenticate with backend to get JWT
      final resolvedBaseUrl = await AppConfig.getBaseUrlWithFallback();
      final authResponse = await http
          .post(
            Uri.parse('$resolvedBaseUrl/api/auth'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'idToken': idToken,
              'deviceId': deviceId,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (authResponse.statusCode == 200) {
        final authData = jsonDecode(authResponse.body);
        final token = authData['token'];

        if (token == null || token.toString().isEmpty) {
          AppLogger.log('❌ JWT token is null or empty in response');
          return null;
        }

        // Save JWT token
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', token);

        // Save fallback user data
        final fallbackData = {
          'id': googleUser.id,
          'googleId': googleUser.id,
          'name': googleUser.displayName ?? 'User',
          'email': googleUser.email,
          'profilePic': googleUser.photoUrl,
        };
        await prefs.setString('fallback_user', jsonEncode(fallbackData));

        // **CRITICAL: ALWAYS store device ID after successful auto-login**
        await _ensureDeviceIdStored(deviceId);

        AppLogger.log('✅ Auto-login successful! User: ${googleUser.email}');
        AppLogger.log('✅ JWT token restored and device ID stored');

        return {
          'id': googleUser.id,
          'googleId': googleUser.id,
          'name': googleUser.displayName ?? 'User',
          'email': googleUser.email,
          'profilePic': googleUser.photoUrl,
          'token': token,
        };
      } else {
        AppLogger.log(
            '❌ Backend authentication failed: ${authResponse.statusCode}');
        AppLogger.log('❌ Response body: ${authResponse.body}');
        return null;
      }
    } catch (e) {
      AppLogger.log('⚠️ Auto-login failed (non-critical): $e');
      // Don't throw - auto-login failure is not critical
      return null;
    }
  }

  /// Re-authenticate with Google to get a fresh token
  Future<String?> _reauthenticateWithGoogle() async {
    try {
      AppLogger.log('🔄 Attempting to re-authenticate with Google...');

      // Check if user is already signed in
      if (!await _googleSignIn.isSignedIn()) {
        AppLogger.log(
            '❌ User not signed in with Google, cannot re-authenticate');
        return null;
      }

      // Get fresh authentication
      final GoogleSignInAccount? googleUser =
          await _googleSignIn.signInSilently();
      if (googleUser == null) {
        AppLogger.log('❌ Silent sign-in failed, user needs to re-authenticate');
        return null;
      }

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        AppLogger.log('❌ Failed to get fresh ID token from Google');
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

        AppLogger.log('✅ Successfully obtained new JWT token');
        return newToken;
      } else {
        AppLogger.log(
            '❌ Backend authentication failed: ${authResponse.statusCode}');
        return null;
      }
    } catch (e) {
      AppLogger.log('❌ Error during re-authentication: $e');
      return null;
    }
  }

  /// Clear expired tokens and force re-login
  Future<void> clearExpiredTokens() async {
    try {
      AppLogger.log('🧹 Clearing expired tokens...');
      final prefs = await SharedPreferences.getInstance();

      // Remove JWT token
      await prefs.remove('jwt_token');

      // Keep fallback user data for re-authentication
      AppLogger.log('✅ Expired tokens cleared, user needs to re-login');
    } catch (e) {
      AppLogger.log('❌ Error clearing expired tokens: $e');
    }
  }

  /// Check if user needs to re-login due to expired tokens
  Future<bool> needsReLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // **FIXED: Check if user has skipped login - don't require re-login if skipped**
      final skipLogin = prefs.getBool('auth_skip_login') ?? false;
      if (skipLogin) {
        AppLogger.log('ℹ️ User has skipped login, not requiring re-login');
        return false;
      }

      String? token = prefs.getString('jwt_token');

      // If no token, user needs to login (unless they skipped)
      if (token == null || token.isEmpty) {
        AppLogger.log('⚠️ No token found, user needs to re-login');
        return true;
      }

      // Check if it's a fallback token (starts with "temp_")
      if (token.startsWith('temp_')) {
        AppLogger.log('ℹ️ Fallback token detected, skipping expiry check');
        return false; // Fallback tokens are always considered valid
      }

      // Check if real JWT token is expired
      if (!isTokenValid(token)) {
        AppLogger.log('⚠️ Token is expired, user needs to re-login');
        return true;
      }

      return false;
    } catch (e) {
      AppLogger.log('❌ Error checking re-login status: $e');
      // On error, check if user skipped login - if yes, don't require re-login
      try {
        final prefs = await SharedPreferences.getInstance();
        final skipLogin = prefs.getBool('auth_skip_login') ?? false;
        if (skipLogin) {
          return false;
        }
      } catch (_) {}
      return true;
    }
  }

  /// Alternative method to show location onboarding with explicit context
  static Future<void> showLocationOnboarding(BuildContext context) async {
    try {
      AppLogger.log('📍 Showing location onboarding...');

      final result =
          await LocationOnboardingService.showLocationOnboarding(context);
      if (result) {
        AppLogger.log('✅ User granted location permission');
      } else {
        AppLogger.log('❌ User denied location permission');
      }
    } catch (e) {
      AppLogger.log('❌ Error showing location onboarding: $e');
    }
  }

  /// Get current JWT token
  static Future<String?> getToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (e) {
      AppLogger.log('❌ Error getting token: $e');
      return null;
    }
  }

  /// Get base URL for API calls
  static String get baseUrl => AppConfig.baseUrl;

  /// **TESTING: Force show location dialog (ignores SharedPreferences check)**
  static Future<void> forceShowLocationDialog(BuildContext context) async {
    try {
      AppLogger.log('🧪 TESTING: Force showing location permission dialog...');

      // Reset onboarding state first
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('location_onboarding_shown');

      // Then show the dialog
      await showLocationOnboarding(context);
    } catch (e) {
      AppLogger.log('❌ Error force showing location dialog: $e');
    }
  }

  /// **TESTING: Check if location permission is granted**
  static Future<bool> checkLocationPermission() async {
    return await LocationOnboardingService.isLocationPermissionGranted();
  }

  /// **CRITICAL: Ensure device ID is ALWAYS stored after successful authentication**
  /// This method guarantees deviceId storage even if backend calls fail
  /// This is essential for auto-login to work after app reinstall
  Future<void> _ensureDeviceIdStored(String deviceId) async {
    try {
      final deviceIdService = DeviceIdService();

      // Store locally first (always succeeds)
      await deviceIdService.storeDeviceId();
      AppLogger.log(
          '✅ Device ID stored locally: ${deviceId.substring(0, 8)}...');

      // Try to verify with backend (non-blocking, doesn't fail if backend is down)
      try {
        final hasStored = await deviceIdService
            .hasStoredDeviceId()
            .timeout(const Duration(seconds: 3), onTimeout: () => false);

        if (!hasStored) {
          AppLogger.log(
              '⚠️ Device ID not yet verified on backend, but stored locally');
          AppLogger.log(
              'ℹ️ Backend verification will happen on next app launch');
        } else {
          AppLogger.log('✅ Device ID verified on backend');
        }
      } catch (e) {
        AppLogger.log('⚠️ Backend verification failed (non-critical): $e');
        AppLogger.log(
            'ℹ️ Device ID stored locally, will verify on next launch');
      }
    } catch (e) {
      AppLogger.log('❌ CRITICAL: Failed to store device ID: $e');
      // Don't throw - deviceId storage failure shouldn't break sign-in
      // But log it as critical since it affects auto-login
    }
  }

  /// **OPTIMIZED: Async referral tracking that doesn't block sign-in**
  Future<void> _trackReferralCodeAsync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final pendingRefCode = prefs.getString('pending_referral_code');

      if (pendingRefCode == null || pendingRefCode.isEmpty) {
        return;
      }

      AppLogger.log('🎁 Tracking referral code in background: $pendingRefCode');

      final trackResponse = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/api/referrals/track'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'code': pendingRefCode,
              'event': 'signup',
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (trackResponse.statusCode == 200) {
        AppLogger.log('✅ Referral signup tracked successfully');
        await prefs.remove('pending_referral_code');
      } else {
        AppLogger.log(
          '⚠️ Referral tracking failed: ${trackResponse.statusCode}',
        );
      }
    } catch (trackError) {
      AppLogger.log('⚠️ Error tracking referral: $trackError');
      // Don't block sign-in if referral tracking fails
    }
  }
}
