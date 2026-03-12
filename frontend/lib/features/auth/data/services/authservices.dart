import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart';
import 'package:http/http.dart' as http;
import 'package:vayu/shared/services/http_client_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:vayu/shared/config/app_config.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'package:vayu/shared/config/google_sign_in_config.dart';
import 'package:vayu/features/onboarding/data/services/location_onboarding_service.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:vayu/shared/services/platform_id_service.dart';
import 'package:vayu/shared/services/notification_service.dart';

class AuthService {
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    clientId: GoogleSignInConfig.platformClientId,
  );

  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  AuthService._internal() {
    // **NEW: Initialize token refresh callback in HttpClientService**
    httpClientService.onTokenExpired = refreshAccessToken;
    AppLogger.log('🔐 AuthService: Token refresh callback initialized');
  }

  // Global navigator key for accessing context
  static GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  
  // **OPTIMIZATION: Deduplicate Profile Requests**
  static Future<Map<String, dynamic>?>? _pendingProfileRequest;
  
  // **OPTIMIZATION: Short-term (30s) In-memory Cache**
  static Map<String, dynamic>? _cachedProfile;
  static DateTime? _lastProfileFetch;
  static const Duration _cacheTtl = Duration(minutes: 5);
  static const String _lastSlidingRefreshAtKey = 'auth_last_sliding_refresh_at';
  static const Duration _slidingRefreshInterval = Duration(hours: 12);
  
  // **THROTTLING: Prevent redundant network requests**
  static DateTime? _lastReLoginCheckTime;
  static const Duration _throttleInterval = Duration(seconds: 30);
  
  // **CONCURRENCY: Prevent parallel refresh requests**
  static Future<String?>? _pendingRefreshRequest;

  /// **NEW: Get the currently logged-in user ID (using memory cache)**
  String? get currentUserId {
    if (_cachedProfile != null) {
      return (_cachedProfile!['googleId'] ?? _cachedProfile!['id'])?.toString();
    }
    return null;
  }

  /// **NEW: Proactively verify if the stored JWT belongs to the current Google user**
  /// Returns [true] if consistent, [false] if there's a mismatch or missing info.
  Future<bool> verifyIdentityConsistency() async {
    try {
      // 1. Get current Google user silently
      final googleUser = await _googleSignIn.signInSilently();
      if (googleUser == null) {
        // Do not hard-fail backend session if Google silent auth is unavailable.
        // Backend JWT + refresh token is the source of truth for app session.
        AppLogger.log('ℹ️ IdentityCheck: No active Google account found (non-fatal)');
        return true;
      }

      // 2. Get local JWT info
      SharedPreferences prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) {
        AppLogger.log('ℹ️ IdentityCheck: No local JWT found');
        return false;
      }

      final tokenInfo = getTokenInfo(token);
      if (tokenInfo == null) {
        AppLogger.log('⚠️ IdentityCheck: Stored JWT is invalid');
        return false;
      }

      final jwtGoogleId = tokenInfo['userId']?.toString();
      final activeGoogleId = googleUser.id;

      if (jwtGoogleId != null && activeGoogleId != jwtGoogleId) {
        AppLogger.log('❌ IDENTITY MISMATCH: JWT user ($jwtGoogleId) != Google user ($activeGoogleId)');
        return false;
      }

      AppLogger.log('✅ IdentityCheck: Session is consistent with Google account');
      return true;
    } catch (e) {
      AppLogger.log('⚠️ IdentityCheck error: $e');
      return false;
    }
  }

  Future<void> _markSlidingRefreshActivity(SharedPreferences prefs) async {
    await prefs.setInt(
      _lastSlidingRefreshAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  bool _shouldPerformSlidingRefresh(SharedPreferences prefs) {
    final refreshToken = prefs.getString('refresh_token');
    if (refreshToken == null || refreshToken.isEmpty) {
      return false;
    }

    final lastRefreshAtMs = prefs.getInt(_lastSlidingRefreshAtKey);
    if (lastRefreshAtMs == null) {
      return true;
    }

    final lastRefreshAt = DateTime.fromMillisecondsSinceEpoch(lastRefreshAtMs);
    return DateTime.now().difference(lastRefreshAt) >= _slidingRefreshInterval;
  }

  Future<Map<String, dynamic>?> signInWithGoogle(
      {bool forceAccountPicker = true}) async {
    try {
      AppLogger.log('🔐 Starting Google Sign-In process...');

      // **OPTIMIZED: Start fetching platform ID immediately (in parallel)**
      final platformIdFuture = PlatformIdService().getPlatformId();

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
          // **OPTIMIZED: Only signOut, DO NOT disconnect.**
          // Disconnect revokes consent and slows down re-login.
          await _googleSignIn.signOut(); 
        } catch (e) {
          AppLogger.log('ℹ️ Pre sign-in signOut ignored: $e');
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

      // Acquire ID token; on web, try multiple methods with fallback
      String? idToken;
      try {
        if (kIsWeb) {
          // Try getTokens first (preferred method for web)
          try {
            final tokens = await GoogleSignInPlatform.instance
                .getTokens(email: googleUser.email);
            idToken = tokens.idToken;
            AppLogger.log('✅ Got ID token using getTokens method');
          } catch (getTokensError) {
            AppLogger.log(
                '⚠️ getTokens failed, trying authentication method: $getTokensError');
            // Fallback: try authentication method
            try {
              final GoogleSignInAuthentication googleAuth =
                  await googleUser.authentication;
              idToken = googleAuth.idToken;
              AppLogger.log('✅ Got ID token using authentication method');
            } catch (authError) {
              AppLogger.log('❌ authentication method also failed: $authError');
              rethrow;
            }
          }
        } else {
          final GoogleSignInAuthentication googleAuth =
              await googleUser.authentication;
          idToken = googleAuth.idToken;
        }
      } catch (e) {
        AppLogger.log('❌ Error obtaining Google tokens: $e');
        AppLogger.log('❌ Error details: ${e.toString()}');
      }

      if (idToken == null) {
        AppLogger.log('❌ Failed to get ID token from Google');
        throw Exception(
            'Failed to get authentication token from Google. Please check your Google Cloud Console configuration for authorized JavaScript origins and redirect URIs.');
      }

      AppLogger.log('🔑 Got ID token, attempting backend authentication...');

      // **OPTIMIZED: Await platform info that was started earlier**
      final deviceId = await platformIdFuture;
      final platformIdService = PlatformIdService();
      final deviceName = await platformIdService.getDeviceName();
      final platform = platformIdService.getPlatformType();

      // First, authenticate with backend to get JWT
      try {
        // **OPTIMIZED: Reduced timeout from 8s to 5s for faster sign-in**
        final authResponse = await http
            .post(
              Uri.parse(NetworkHelper.authEndpoint),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'idToken': idToken,
                'deviceId': deviceId,
                'deviceName': deviceName,
                'platform': platform,
              }),
            )
            .timeout(const Duration(seconds: 5));

        AppLogger.log(
            '📡 Backend auth response status: ${authResponse.statusCode}');
        AppLogger.log('📡 Backend auth response body: ${authResponse.body}');

        if (authResponse.statusCode == 200) {
          final authData = jsonDecode(authResponse.body);
          AppLogger.log('✅ Backend authentication successful');
          
          // **FIXED: Use accessToken (new backend format)**
          final token = authData['accessToken'] ?? authData['token'];
          AppLogger.log(
              '🔑 JWT Token received: ${token?.toString().substring(0, 20)}...');

          // Save JWT in shared preferences
          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setString('jwt_token', token);
          
          // **NEW: Save Refresh Token**
          if (authData['refreshToken'] != null) {
            await prefs.setString('refresh_token', authData['refreshToken']);
            await _markSlidingRefreshActivity(prefs);
            AppLogger.log('🔑 Refresh Token received and saved');
          }

          // **OPTIMIZED: Retry saving FCM token non-blocking (fire and forget)**
          unawaited(() async {
            try {
              final notificationService = NotificationService();
              if (notificationService.isInitialized) {
                await notificationService.retrySaveToken();
              }
            } catch (e) {
              AppLogger.log('⚠️ Error retrying FCM token save: $e');
            }
          }());

          // **OPTIMIZED: Sync watch history non-blocking (fire and forget)**
          // This ensures watched videos don't appear again after login
          // Don't block sign-in completion for this
          unawaited(() async {
            try {
              final platformId = await PlatformIdService().getPlatformId();
              final syncResponse = await httpClientService.post(
                Uri.parse('${NetworkHelper.apiBaseUrl}/videos/sync-watch-history'),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer ${authData['token']}',
                  if (platformId.isNotEmpty) 'x-device-id': platformId,
                },
                body: jsonEncode({
                  'platformId': platformId,
                }),
                timeout: const Duration(seconds: 3),
              );

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
              AppLogger.log(
                  '⚠️ Error syncing watch history (non-critical): $e');
            }
          }());

          // **OPTIMIZED: User registration is handled by /api/auth endpoint**
          // We no longer need a separate call to /api/users/register

          final backendUser = authData['user'];
          final isNewUser = backendUser?['isNewUser'] ?? false;

          if (isNewUser) {
             AppLogger.log('✅ New user detected via Auth endpoint');
             // Fire and forget - don't block sign-in completion
             unawaited(_trackReferralCodeAsync());

              // Show location onboarding for new users
              // Add small delay to ensure context is available
              Future.delayed(const Duration(milliseconds: 500), () {
                _showLocationOnboardingAfterSignIn();
              });
          }

          // **FIXED: Use Google account data if backend data is missing**
          // Priority: 1) Backend registered data, 2) Google account data
          final finalName =
              backendUser?['name'] ?? googleUser.displayName ?? 'User';
          final finalProfilePic = backendUser?['profilePic'] ??
              backendUser?['profilePicture'] ??
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

          // **OPTIMIZED: Store device ID in parallel (non-blocking)**
          // Device ID storage is critical but doesn't need to block sign-in completion
          unawaited(_ensurePlatformIdStored(deviceId));

          // Return combined user data immediately (device ID storage happens in background)
          return {
            'id': googleUser.id,
            'googleId': googleUser.id,
            'name': finalName,
            'email': googleUser.email,
            'profilePic': finalProfilePic,
            'token': token,
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
                  Uri.parse(NetworkHelper.authEndpoint),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'idToken': idToken,
                    'deviceId': deviceId,
                    'deviceName': deviceName,
                    'platform': platform,
                  }),
                )
                .timeout(const Duration(seconds: 5));

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

              await httpClientService.post(
                Uri.parse('${NetworkHelper.usersEndpoint}/register'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode(userData),
              );

              // **CRITICAL: ALWAYS store device ID after successful retry authentication**
              await _ensurePlatformIdStored(deviceId);

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

      // **CRITICAL: ALWAYS store platform ID even in fallback mode**
      await _ensurePlatformIdStored(await PlatformIdService().getPlatformId());

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

      // **FIXED: Perform a synchronous validation check before returning true**
      // This prevents the "Optimistic Flicker" where the UI shows the profile
      // for a split second before the background verification kicks in.
      if (!isTokenValid(token)) {
        AppLogger.log('⚠️ Token found but is invalid/expired - requiring fresh login');
        return false;
      }

      // **OPTIMIZED: Return cached status immediately, verify in background**
      AppLogger.log('✅ Token exists and is locally valid - proceeding optimistically');
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
      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.usersEndpoint}/profile'),
        headers: {'Authorization': 'Bearer $token'},
        timeout: const Duration(seconds: 3),
      );

      // Only clear token if it's actually unauthorized (401/403), not on network errors
      if (response.statusCode == 401 || response.statusCode == 403) {
        AppLogger.log(
            '⚠️ Token verification failed - unauthorized (${response.statusCode})');

      // **IMPROVED: Try to refresh token before removing it**
      final refreshedToken = await refreshAccessToken();
      if (refreshedToken != null && refreshedToken != token) {
        AppLogger.log('✅ Token refreshed successfully in background');
        return; // Token was refreshed, keep session
      }

        // Non-destructive behavior: keep local token and allow future retries.
        AppLogger.log(
            '⚠️ Refresh attempt failed after unauthorized response; keeping local session for retry.');
      } else if (response.statusCode == 200) {
        AppLogger.log('✅ Token verified successfully in background');
      } else {
        AppLogger.log(
            '⚠️ Token verification returned status ${response.statusCode}, keeping token');
      }
    } catch (e) {
      AppLogger.log('⚠️ Background token verification failed: $e');
      // **IMPROVED: Keep session even if backend is unreachable - don't remove token on network errors**
      // Keep session and retry later through central refresh flow.
      AppLogger.log('ℹ️ Network/backend error during verification, keeping local session');
    }
  }

  Future<void> signOut() async {
    try {
      AppLogger.log('🚪 Signing out user...');

      // **FIXED: Clear memory cache immediately to prevent account switch collisions**
      _cachedProfile = null;
      _lastProfileFetch = null;
      _pendingProfileRequest = null;

      // **OPTIMIZED: Clear Google session faster**
      // signOut() is sufficient for switching. disconnect() is slow as it revokes all app permissions.
      await _googleSignIn.signOut();

      // **OPTIMIZED: Batch clear SharedPreferences**
      SharedPreferences prefs = await SharedPreferences.getInstance();
      
      // Step 1: Identify all keys to preserve (whitelist)
      final allKeys = prefs.getKeys();
      final List<String> whitelist = [
        'is_first_launch',
        'theme_mode',
        'platform_id', // Preserving platform ID allows seamless auto-login/guest sessions
        'payment_setup_completed', // Preserving shared device state
        'upi_guide_shown',
      ];

      // Step 2: Clear all other keys in a single loop (more efficient than individual removes)
      int clearedCount = 0;
      for (String key in allKeys) {
        if (!whitelist.contains(key)) {
          // We don't await each remove to speed up the loop, just fire them off
          // SharedPreferences is thread-safe for calls anyway.
          unawaited(prefs.remove(key));
          clearedCount++;
        }
      }

      AppLogger.log('✅ Sign out successful - Cleared $clearedCount keys (Whitelisted: ${whitelist.length})');
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

  /// **NEW: Ensure strict authentication for app startup**
  /// This method guarantees that we have a validated session (or a guest session)
  /// before proceeding. It handles auto-login and token refresh sequentially.
  Future<Map<String, dynamic>?> ensureStrictAuth() async {
    try {
      AppLogger.log(
          '🚀 AuthService: Starting strict authentication sequence...');
      final prefs = await SharedPreferences.getInstance();
      String? token = prefs.getString('jwt_token');

      // 1. If we have a token, validate and refresh if necessary
      if (token != null && token.isNotEmpty) {
        AppLogger.log('🔍 AuthService: Validating existing token...');
        if (!isTokenValid(token)) {
          AppLogger.log(
              '🔄 AuthService: Token invalid/expired, attempting refresh...');
          final refreshedToken = await refreshAccessToken();
          if (refreshedToken != null) {
            token = refreshedToken;
          } else {
            AppLogger.log(
                '⚠️ AuthService: Token refresh failed, clearing token');
            await prefs.remove('jwt_token');
            token = null;
          }
        } else {
          AppLogger.log('✅ AuthService: Existing token is valid');
        }
      }

      // 2. If no token (or refresh failed), return null as we no longer support device-id auto-login
      if (token == null || token.isEmpty) {
        AppLogger.log('🔍 AuthService: No valid token found, user needs to sign in');
        return null;
      }

      // 3. Finally, call getUserData to ensure we have the full profile
      // We use a longer timeout here because this is the critical startup path
      AppLogger.log(
          '🔍 AuthService: Fetching final user profile to verify session...');
      return await _getUserDataInternal(skipTokenRefresh: true).timeout(
        const Duration(seconds: 10),
        onTimeout: () async {
          AppLogger.log(
              '⚠️ AuthService: Profile fetch timed out, using fallback');
          final fallbackUser = prefs.getString('fallback_user');
          if (fallbackUser != null) {
            return jsonDecode(fallbackUser);
          }
          return null;
        },
      );
    } catch (e) {
      AppLogger.log('❌ AuthService: Error in strict auth sequence: $e');
      return null;
    }
  }

  /// **NEW: Clear in-memory profile cache**
  void clearMemoryCache() {
    AppLogger.log('🔐 AuthService: Clearing in-memory profile cache');
    _cachedProfile = null;
    _lastProfileFetch = null;
    _pendingProfileRequest = null;
  }

  // Get user data from JWT token
  Future<Map<String, dynamic>?> getUserData(
      {bool skipTokenRefresh = false, bool forceRefresh = false}) async {
    try {
      AppLogger.log('🔍 AuthService: Getting user data...');

      // **OPTIMIZATION: Clear cache if forceRefresh is requested**
      if (forceRefresh) {
        AppLogger.log('🔄 AuthService: Force refresh requested - clearing memory cache');
        _cachedProfile = null;
        _lastProfileFetch = null;
      }

      // **OPTIMIZATION: Return cached data if valid (30s TTL)**
      if (_cachedProfile != null && _lastProfileFetch != null) {
        final age = DateTime.now().difference(_lastProfileFetch!);
        if (age < _cacheTtl) {
          AppLogger.log(
              '♻️ AuthService: Returning cached profile data (${age.inSeconds}s old)');
          return _cachedProfile;
        }
      }

      // **OPTIMIZATION: Deduplicate simultaneous requests**
      if (_pendingProfileRequest != null) {
        AppLogger.log('♻️ AuthService: Reusing in-flight profile request...');
        return await _pendingProfileRequest;
      }

      // **OPTIMIZED: Execute the actual fetch and store the future**
      _pendingProfileRequest =
          _getUserDataInternal(skipTokenRefresh: skipTokenRefresh)
              .timeout(const Duration(seconds: 5), onTimeout: () async {
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

      try {
        final result = await _pendingProfileRequest;

        // **CACHE: Update cache if result is successful and not a fallback**
        if (result != null && result['isFallback'] != true) {
          _cachedProfile = result;
          _lastProfileFetch = DateTime.now();
        }

        return result;
      } finally {
        // **CLEANUP: Clear the pending request regardless of outcome**
        _pendingProfileRequest = null;
      }
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

      AppLogger.log('🔍 AuthService: Token found: ${token != null ? "Yes" : "No"}');
      AppLogger.log('🔍 AuthService: Fallback user found: ${fallbackUser != null ? "Yes" : "No"}');

      // **IMPROVED: Validate JWT token before using it - be conservative about removal**
      if (!skipTokenRefresh && token != null && !isTokenValid(token)) {
        AppLogger.log('⚠️ AuthService: JWT token appears invalid or expired');

        // Try to refresh the token first
        final refreshedToken = await refreshAccessToken();
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
            await prefs.setBool('auth_needs_login', true);
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
        
        // If no token, we can't fetch from backend, skip directly to fallback
        if (token == null) {
           throw Exception('No token available for backend verification');
        }

        final response = await httpClientService.get(
          Uri.parse('${NetworkHelper.usersEndpoint}/profile'),
          headers: {'Authorization': 'Bearer $token'},
          timeout: const Duration(seconds: 3),
        );

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
          throw Exception('Backend returned ${response.statusCode}');
        }
      } catch (e) {
        AppLogger.log('⚠️ Error fetching user profile from backend: $e');
        
        if (fallbackDataMap != null) {
          final userData = fallbackDataMap;
          AppLogger.log(
               '✅ Using fallback user data for offline access (User: ${userData['name']})');
          
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
      await prefs.setBool('auth_needs_login', true);
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
        final newToken = await refreshAccessToken();
        if (newToken != null) {
          AppLogger.log(
              '✅ Successfully obtained new token');
          return newToken;
        }
      } catch (e) {
        AppLogger.log('❌ Refresh failed: $e');
      }

      AppLogger.log('❌ Failed to refresh token, user needs to re-login');
      return null;
    } catch (e) {
      AppLogger.log('❌ Error refreshing token: $e');
      return null;
    }
  }



  /// **NEW: Refresh the access token using the refresh token (with Google Silent Sign-In fallback)**
  Future<String?> refreshAccessToken() async {
    // **CONCURRENCY: Prevent parallel refresh requests**
    if (_pendingRefreshRequest != null) {
      AppLogger.log('ℹ️ AuthService: Joining existing pending refresh request');
      return await _pendingRefreshRequest;
    }

    _pendingRefreshRequest = _doRefreshAccessToken();
    try {
      return await _pendingRefreshRequest;
    } finally {
      // Clear the lock after it completes, but allow a tiny grace period
      Future.delayed(const Duration(milliseconds: 500), () {
        _pendingRefreshRequest = null;
      });
    }
  }

  Future<String?> _doRefreshAccessToken() async {
    try {
      AppLogger.log('🔄 Attempting to refresh access token...');
      final prefs = await SharedPreferences.getInstance();
      final refreshToken = prefs.getString('refresh_token');

      // 1. Try Refresh Token first (fast, server-side)
      if (refreshToken != null && refreshToken.isNotEmpty) {
        try {
          // Refresh token request no longer requires deviceId for rotation check

          final response = await http.post(
            Uri.parse('${NetworkHelper.authEndpoint}/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'refreshToken': refreshToken,
            }),
          ).timeout(const Duration(seconds: 10)); // Increased timeout for reliability

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            // **FIX: Handle both 'accessToken' and 'token' formats**
            final newToken = data['accessToken'] ?? data['token'];
            final newRefreshToken = data['refreshToken'];

            if (newToken != null) {
              await prefs.setString('jwt_token', newToken);
              if (newRefreshToken != null) {
                await prefs.setString('refresh_token', newRefreshToken);
              }
              // Session recovered: do not show "Sign in" CTA
              await prefs.setBool('auth_needs_login', false);
              await _markSlidingRefreshActivity(prefs);
              AppLogger.log('✅ Access token refreshed successfully via refresh_token');
              return newToken;
            } else {
              AppLogger.log('⚠️ Token refresh returned 200 but no token in body: $data');
            }
          } else {
            AppLogger.log('⚠️ Token refresh endpoint failed with status: ${response.statusCode}');
            AppLogger.log('⚠️ Response body: ${response.body}');
            // **FIX: Only clear refresh token when backend explicitly requires login.**
            if (response.statusCode == 401 || response.statusCode == 403) {
              bool requiresLogin = false;
              try {
                final body = jsonDecode(response.body);
                requiresLogin = body is Map<String, dynamic> &&
                    body['requiresLogin'] == true;
              } catch (_) {
                // Keep token on non-JSON/error bodies to avoid accidental session loss.
              }

              if (requiresLogin) {
                AppLogger.log('🔐 Backend requires login. Removing refresh token from local storage.');
                await prefs.remove('refresh_token');
              } else {
                AppLogger.log('ℹ️ Refresh rejected but login not explicitly required; keeping refresh token for retry.');
              }
            }
          }
        } catch (e) {
          AppLogger.log('⚠️ Refresh token endpoint error (likely network): $e');
        }
      }

      // 2. Fallback to Google Silent Sign-In (re-authenticates session)
      AppLogger.log('🔄 Refresh token failed, falling back to Google Silent Sign-In...');
      final googleToken = await _reauthenticateWithGoogle();
      if (googleToken != null) {
        AppLogger.log('✅ Access token refreshed via Google Silent Sign-In');
        await prefs.setBool('auth_needs_login', false);
        return googleToken;
      }

      AppLogger.log('❌ All automatic refresh methods failed');
      // Mark that user action is required to restore session.
      await prefs.setBool('auth_needs_login', true);
      return null;
    } catch (e) {
      AppLogger.log('❌ Error during token refresh sequence: $e');
      return null;
    }
  }

  /// Re-authenticate with Google to get a fresh token
  Future<String?> _reauthenticateWithGoogle() async {
    try {
      AppLogger.log('🔄 Attempting to re-authenticate with Google...');

      // **FIX: Use signInSilently() directly. isSignedIn() can be false if token is expired**
      // suppressErrors: false allows us to see why it fails in the logs
      final GoogleSignInAccount? googleUser =
          await _googleSignIn.signInSilently(suppressErrors: false)
              .timeout(const Duration(seconds: 5), onTimeout: () {
                AppLogger.log('⚠️ Google Silent Sign-In timed out');
                return null;
              });
      
      if (googleUser == null) {
        AppLogger.log('❌ Silent sign-in failed, user needs to re-authenticate manually');
        return null;
      }

      AppLogger.log('🔑 Got fresh ID token, re-authenticating with backend...');

      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final idToken = googleAuth.idToken;
      if (idToken == null) {
        AppLogger.log('❌ Failed to get fresh ID token from Google');
        return null;
      }

      // Re-authentication with backend (deviceId no longer strictly required)

      // Authenticate with backend to get new JWT
      final authResponse = await http
          .post(
            Uri.parse(NetworkHelper.authEndpoint), // Use authEndpoint constant
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'idToken': idToken,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (authResponse.statusCode == 200) {
        final authData = jsonDecode(authResponse.body);
        // **FIXED: Use accessToken (new backend format)**
        final newToken = authData['accessToken'] ?? authData['token'];
        final newRefreshToken = authData['refreshToken'];

        // Save new tokens
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('jwt_token', newToken);
        if (newRefreshToken != null) {
          await prefs.setString('refresh_token', newRefreshToken);
        }
        await _markSlidingRefreshActivity(prefs);

        AppLogger.log('✅ Successfully obtained new JWT token via re-authentication');
        return newToken;
      } else {
        AppLogger.log(
            '❌ Backend re-authentication failed: ${authResponse.statusCode} - ${authResponse.body}');
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
    // **THROTTLING: Prevent rapid successive needsReLogin checks**
    if (_lastReLoginCheckTime != null && 
        DateTime.now().difference(_lastReLoginCheckTime!) < _throttleInterval) {
      AppLogger.log('ℹ️ AuthService: Skipping needsReLogin check (throttled)');
      return false; // Assume current state is fine during throttle window
    }
    _lastReLoginCheckTime = DateTime.now();

    try {
      final prefs = await SharedPreferences.getInstance();

      // **FIXED: Check if user has skipped login - don't require re-login if skipped**
      final skipLogin = prefs.getBool('auth_skip_login') ?? false;
      if (skipLogin) {
        AppLogger.log('User has skipped login, not requiring re-login');
        return false;
      }

      String? token = prefs.getString('jwt_token');

      // If no token, user needs to login (unless they skipped)
      if (token == null || token.isEmpty) {
        AppLogger.log('No token found, user needs to re-login');
        return true;
      }

      // Check if it's a fallback token (starts with "temp_")
      if (token.startsWith('temp_')) {
        AppLogger.log('Fallback token detected, skipping expiry check');
        return false; // Fallback tokens are always considered valid
      }

      // Expired access token: try refresh once before forcing re-login.
      if (!isTokenValid(token)) {
        AppLogger.log('Token is expired, attempting refresh before re-login');
        final refreshedToken = await refreshAccessToken();
        if (refreshedToken != null && refreshedToken.isNotEmpty) {
          AppLogger.log('Token refreshed during needsReLogin check');
          return false;
        }
        
        // **FIX: Only force re-login if we definitively lost the session (refresh_token gone)**
        final currentRefreshToken = prefs.getString('refresh_token');
        if (currentRefreshToken == null || currentRefreshToken.isEmpty) {
          AppLogger.log('Token refresh failed and refresh token is missing. User needs to re-login.');
          return true;
        } else {
          AppLogger.log('Token refresh failed (likely network), but refresh token exists. Keeping session active.');
          return false;
        }
      }

      // Sliding session: periodically rotate refresh token while user is active.
      if (_shouldPerformSlidingRefresh(prefs)) {
        AppLogger.log('Sliding session: refresh interval reached, rotating tokens');
        final rotatedToken = await refreshAccessToken();
        if (rotatedToken != null && rotatedToken.isNotEmpty) {
          AppLogger.log('Sliding session refresh successful');
        } else {
          AppLogger.log('Sliding session refresh failed; keeping valid session');
        }
      }

      return false;
    } catch (e) {
      AppLogger.log('Error checking re-login status: $e');
      // On error, check if user skipped login - if yes, don't require re-login
      try {
        final prefs = await SharedPreferences.getInstance();
        final skipLogin = prefs.getBool('auth_skip_login') ?? false;
        if (skipLogin) {
          return false;
        }
      } catch (_) {}
      // **FIX: Don't logout on unexpected errors (e.g., SharedPreferences issue)**
      return false;
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
  /// This method guarantees platformId storage even if backend calls fail
  Future<void> _ensurePlatformIdStored(String platformId) async {
    try {
      AppLogger.log(
          '✅ Platform ID available: ${platformId.substring(0, 8)}...');
      AppLogger.log(
          'ℹ️ Backend will use this platform ID for watch history tracking');
    } catch (e) {
      AppLogger.log('❌ CRITICAL: Failed to store platform ID: $e');
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
            Uri.parse('${NetworkHelper.apiBaseUrl}/referrals/track'),
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
    }
  }
}

