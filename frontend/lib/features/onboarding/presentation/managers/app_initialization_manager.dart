import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/utils/app_logger.dart';

import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/managers/smart_cache_manager.dart';

import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/shared/services/app_remote_config_service.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:vayug/shared/services/notification_service.dart';
import 'package:vayug/features/video/core/data/services/video_service.dart';
import 'package:vayug/shared/services/hls_warmup_service.dart';
import 'dart:async'; // For unawaited
import 'package:shared_preferences/shared_preferences.dart';
/// **AppInitializationManager**
/// 
/// Centralizes and sequences app startup logic to prevent "thundering herd"
/// lag issues. It prioritizes vital UI content (First 10 Videos) over
/// background tasks (Ads, Firebase, etc.).
class AppInitializationManager {
  // Singleton instance
  static final AppInitializationManager instance =
      AppInitializationManager._internal();

  AppInitializationManager._internal();

  // State
  bool _isStage1Complete = false;
  bool _isStage2Complete = false;
  bool _isStage3Complete = false;
  
  // Progress tracking
  final ValueNotifier<double> initializationProgress = ValueNotifier(0.0);
  final ValueNotifier<String> initializationStatus = ValueNotifier('Initializing...');

  bool get isStage2Complete => _isStage2Complete;

  // Track the vital first page of videos
  List<VideoModel>? initialVideos;
  DateTime? _initialVideosTimestamp;
  bool hasInitialVideosMore = false;

  // **NEW: Track if a forced update is required**
  final ValueNotifier<bool> isUpdateRequired = ValueNotifier(false);

  /// **NEW: Check if initialVideos are still fresh (within 3 minutes)**
  bool get isInitialVideosFresh {
    if (initialVideos == null || _initialVideosTimestamp == null) return false;
    final age = DateTime.now().difference(_initialVideosTimestamp!);
    return age < const Duration(minutes: 3);
  }

  // --- STAGE 1: AVAILABLE IMMEDIATELY (Before UI) ---
  /// Called before `runApp`. Setup basic config.
  Future<void> initializeStage1() async {
    if (_isStage1Complete) return;

    try {
      AppLogger.log('🚀 InitManager: Stage 1 (Config) Started');
      initializationProgress.value = 0.05;
      initializationStatus.value = 'Connecting to services...';
      
      // 1. Firebase (Critical for Network Interceptors)
      try {
        await Firebase.initializeApp();
        initializationProgress.value = 0.15;
        AppLogger.log('✅ InitManager: Firebase initialized');
      } catch (e) {
        AppLogger.log('⚠️ InitManager: Firebase Init Error: $e');
      }

      // 2. Determine Backend URL
      initializationStatus.value = 'Configuring backend...';
      final workingUrl = await AppConfig.checkAndUpdateServerUrl();
      initializationProgress.value = 0.30;
      AppLogger.log('✅ InitManager: Backend URL confirmed: $workingUrl');

      // 2. Initialize Smart Cache (Memory Only, NO HIVE)
      initializationStatus.value = 'Preparing cache...';
      await SmartCacheManager().initialize();
      initializationProgress.value = 0.45;

      _isStage1Complete = true;
    } catch (e) {
      AppLogger.log('❌ InitManager: Stage 1 Failed: $e');
      _isStage1Complete = true;
    }
  }

  // --- STAGE 2: VITAL CONTENT (While Splash Visible) ---
  /// Called by SplashScreen. Fetches First Video & Profile.
  /// Goal: Ensure VideoFeed has content READY when it mounts.
  Future<void> initializeStage2(BuildContext context) async {
    if (_isStage2Complete) {
      AppLogger.log('ℹ️ InitManager: Stage 2 already complete, skipping. Called from:');
      AppLogger.log(StackTrace.current.toString().split('\n').take(5).join('\n'));
      return;
    }

    try {
      AppLogger.log('🚀 InitManager: Stage 2 (Vital Content) Started');
      initializationProgress.value = 0.0;
      AppLogger.log('📍 Trace: Stage 2 called from:');
      AppLogger.log(StackTrace.current.toString().split('\n').take(5).join('\n'));
      
      final stopwatch = Stopwatch()..start();

      // **PARALLELISM: Start Stage 1 if skipped/pending, but don't await strictly**
      final stage1Future = initializeStage1();

      final videoService = VideoService();

      // Task B: Fast local auth gate — validates token state without a network call.
      // Full profile fetch runs in the background after navigation.
      try {
        AppLogger.log('🔐 InitManager: Fast local auth gate...');
        initializationStatus.value = 'Authenticating...';
        initializationProgress.value = 0.50; // checkpoint
        await _fastAuthGate();
        initializationProgress.value = 0.65; // checkpoint
        AppLogger.log('✅ InitManager: Fast auth gate complete');
      } catch (e) {
        AppLogger.log('⚠️ InitManager: Auth gate error (non-critical): $e');
      }

      // Task A: Video fetching (Now has access to validated tokens/user ID)
      initializationStatus.value = 'Loading videos...';
      initializationProgress.value = 0.70; // checkpoint
      
      // **SMART CHANGE: Revert to unawaited for maximum logic speed**
      unawaited(_fetchAndPreloadFirstVideos(videoService));

      // Ensure Stage 1 is atleast triggered/checked
      await stage1Future;

      stopwatch.stop();
      AppLogger.log('✅ InitManager: Stage 2 Complete (Auth Verified) in ${stopwatch.elapsedMilliseconds}ms');
      _isStage2Complete = true;
    } catch (e) {
      AppLogger.log('❌ InitManager: Stage 2 Failed: $e');
      _isStage2Complete = true;
    }
  }

  /// Helper: Fetch videos and pre-initialize the first one
  Future<void> _fetchAndPreloadFirstVideos(VideoService videoService) async {
    try {
      AppLogger.log('📥 InitManager: Fetching Page 1 Videos (Yug) in background...');
      
      // 1. Network Call
      final result = await videoService.getVideos(
        page: 1, 
        limit: 15, 
        videoType: 'yog'
      );
      
      final List<dynamic> rawList = result['videos'];
      final videos = rawList.cast<VideoModel>();

      if (videos.isNotEmpty) {
        initialVideos = videos;
        hasInitialVideosMore = result['hasMore'] ?? false;
        _initialVideosTimestamp = DateTime.now();
        AppLogger.log('✅ InitManager: Fetched ${videos.length} videos.');
        initializationProgress.value = 0.90;

        // 2. Pre-initialize FIRST video only (The one user sees instantly)
        // **OPTIMIZED: Skip blocking pre-init to reduce startup latency**
        // User will see thumbnail first, then player initializes in Feed
        initializationProgress.value = 1.0;
        initializationStatus.value = 'Ready!';
        
        // 3. Warm up HLS for next few (Network only, low priority) - Non-blocking
        unawaited(_warmUpNextVideos(videos));
      }
    } catch (e) {
       AppLogger.log('❌ InitManager: Video Fetch Failed: $e');
       
       // **NEW: Check for Version Error (Force Update)**
       // Using string representation since DioException might be wrapped
       final errorStr = e.toString();
       if (errorStr.contains('Unsupported API Version') || 
           errorStr.contains('410') || 
           (errorStr.contains('400') && errorStr.contains('API Version'))) {
          AppLogger.log('🚨 InitManager: CRITICAL VERSION ERROR DETECTED. Forcing update dialog.');
          isUpdateRequired.value = true;
          initializationStatus.value = 'Update Required';
       }
       
       initializationProgress.value = 1.0; // Fail gracefully
    }
  }

  Future<void> _warmUpNextVideos(List<VideoModel> videos) async {
      // Warm up HLS connection for video 2 and 3
      for (var i = 1; i < videos.length && i < 3; i++) {
        final video = videos[i];
        final url = video.hlsPlaylistUrl ?? video.videoUrl;
        if (url.contains('.m3u8')) {
          HlsWarmupService().warmUp(url);
        }
      }
  }


  /// **FAST AUTH GATE: Checks token state locally, refreshes only if expired.**
  /// - Valid token: returns instantly (<50ms)
  /// - Expired token: tries one refresh call (~500ms), clears on failure
  /// - No token: returns instantly (AuthWrapper will route to login)
  Future<void> _fastAuthGate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      final authService = AuthService();

      // 1. No token → let AuthWrapper handle routing to login
      if (token == null || token.isEmpty) {
        AppLogger.log('🔐 InitManager: No token found, proceeding to AuthWrapper');
        return;
      }

      // 2. Token is locally valid → Check identity consistency
      if (authService.isTokenValid(token)) {
        AppLogger.log('🔍 InitManager: Token valid locally, verifying identity consistency...');
        
        // **NEW: Strict Identity Check**
        // Ensure the active Google account still matches this token
        final isConsistent = await authService.verifyIdentityConsistency()
            .timeout(const Duration(seconds: 3), onTimeout: () => true); // Default to true on timeout to avoid blocking

        if (isConsistent) {
          AppLogger.log('✅ InitManager: Identity verified, fast-tracking to home');
          
          // **OPTIMIZATION: Fetch profile in background to warm up cache**
          unawaited(authService.getUserData());
          return;
        } else {
          // Non-destructive: do not clear active session at startup.
          // Let explicit logout/account-switch flows manage identity transitions.
          AppLogger.log('⚠️ InitManager: Identity mismatch detected, preserving existing session');
          return;
        }
      }

      // 3. Token is expired → attempt a fast refresh (single network call)
      AppLogger.log('🔄 InitManager: Token expired, attempting fast refresh...');
      final refreshed = await authService.refreshAccessToken()
          .timeout(const Duration(seconds: 3), onTimeout: () => null);

      if (refreshed != null) {
        AppLogger.log('✅ InitManager: Token refreshed successfully, proceeding');
        // Warm up profile cache
        unawaited(authService.getUserData());
      } else {
        // Non-destructive on startup: keep token and allow retry later.
        AppLogger.log('⚠️ InitManager: Refresh failed during startup, preserving token for retry');
      }
    } catch (e) {
      AppLogger.log('⚠️ InitManager: _fastAuthGate error: $e — proceeding anyway');
    }
  }

  // --- STAGE 3: DEFERRED SERVICES (After Home Mount) ---
  /// Called by MainScreen after 3-5 seconds.
  /// Goal: Load heavy SDKs without stuttering the scrolling.
  Future<void> initializeStage3() async {
    if (_isStage3Complete) return;

    try {
       // yield to UI thread first
       // **DEBUG OPTIMIZATION: Extra delay in debug mode to let UI settle**
       if (kDebugMode) {
         await Future.delayed(const Duration(seconds: 3));
         AppLogger.log('⏭️ InitManager: Debug mode — extra Stage 3 delay applied');
       } else {
         await Future.delayed(Duration.zero);
       }
       
       AppLogger.log('🚀 InitManager: Stage 3 (Deferred) Started');

       // 1. Notifications (Firebase already initialized in Stage 1)
       try {
         final notificationService = NotificationService();
         await notificationService.initialize();
         AppLogger.log('✅ InitManager: Notifications initialized');
       } catch (e) {
         AppLogger.log('Notification Init Error: $e');
       }

       // 2. Remote Config
       try {
         await AppRemoteConfigService.instance.initialize();
       } catch(_) {}

       // 3. AdMob (Heavy!) — DISABLED per user request (Direct Banner Ad)
       // if (!kDebugMode) {
       //   try {
       //      await MobileAds.instance.initialize();
       //      // Configure request settings
       //       final requestConfiguration = RequestConfiguration(
       //        testDeviceIds: [],
       //      );
       //      await MobileAds.instance.updateRequestConfiguration(requestConfiguration);
       //      AppLogger.log('✅ InitManager: AdMob initialized');
       //   } catch (_) {}
       // } else {
       //   AppLogger.log('⏭️ InitManager: Skipping AdMob in debug mode');
       // }
       AppLogger.log('🚫 InitManager: AdMob initialization DISABLED (Using Custom Ads only)');

       _isStage3Complete = true;
       AppLogger.log('✅ InitManager: Stage 3 Complete');

    } catch (e) {
       AppLogger.log('❌ InitManager: Stage 3 Failed: $e');
    }
  }
}

