import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vayu/config/app_config.dart';
import 'package:vayu/utils/app_logger.dart';

import 'package:vayu/model/video_model.dart';
import 'package:vayu/core/managers/smart_cache_manager.dart';

import 'package:vayu/services/authservices.dart';
import 'package:vayu/services/app_remote_config_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'package:firebase_core/firebase_core.dart';
import 'package:vayu/services/notification_service.dart';
import 'package:vayu/services/video_service.dart';
import 'package:vayu/core/managers/video_controller_manager.dart';
import 'package:vayu/core/services/hls_warmup_service.dart';
import 'dart:async'; // For unawaited
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

  bool get isStage2Complete => _isStage2Complete;

  // Track the vital first page of videos
  List<VideoModel>? _initialVideos;
  DateTime? _initialVideosTimestamp;
  bool _hasInitialVideosMore = false;
  
  // Public Getters
  List<VideoModel>? get initialVideos => _initialVideos;
  set initialVideos(List<VideoModel>? videos) => _initialVideos = videos;
  
  bool get hasInitialVideosMore => _hasInitialVideosMore;
  set hasInitialVideosMore(bool value) => _hasInitialVideosMore = value;

  /// **NEW: Check if initialVideos are still fresh (within 3 minutes)**
  bool get isInitialVideosFresh {
    if (_initialVideos == null || _initialVideosTimestamp == null) return false;
    final age = DateTime.now().difference(_initialVideosTimestamp!);
    return age < const Duration(minutes: 3);
  }

  // --- STAGE 1: AVAILABLE IMMEDIATELY (Before UI) ---
  /// Called before `runApp`. Setup basic config.
  Future<void> initializeStage1() async {
    if (_isStage1Complete) return;

    try {
      AppLogger.log('🚀 InitManager: Stage 1 (Config) Started');
      
      // 1. Firebase (Critical for Network Interceptors)
      try {
        await Firebase.initializeApp();
        AppLogger.log('✅ InitManager: Firebase initialized');
      } catch (e) {
        AppLogger.log('⚠️ InitManager: Firebase Init Error: $e');
      }

      // 2. Determine Backend URL
      // **OPTIMIZATION: Don't clear cache aggressively. Trust the "Race to Success"**
      // AppConfig.clearCache(); 
      final workingUrl = await AppConfig.checkAndUpdateServerUrl();
      AppLogger.log('✅ InitManager: Backend URL confirmed: $workingUrl');

      // 2. Initialize Smart Cache (Memory Only, NO HIVE)
      await SmartCacheManager().initialize();

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
      AppLogger.log('📍 Trace: Stage 2 called from:');
      AppLogger.log(StackTrace.current.toString().split('\n').take(5).join('\n'));
      
      final stopwatch = Stopwatch()..start();

      // **PARALLELISM: Start Stage 1 if skipped/pending, but don't await strictly**
      final stage1Future = initializeStage1();

      final videoService = VideoService();
      final authService = AuthService();

      // Task B: Fetch User Data (Strict sequence ensures tokens are ready for videos)
      try {
        AppLogger.log('🔐 InitManager: Authenticating user...');
        await authService.ensureStrictAuth();
        AppLogger.log('✅ InitManager: User Data (Strict) loaded');
      } catch (e) {
        AppLogger.log('⚠️ InitManager: User Data fetch failed (non-critical): $e');
      }

      // Task A: Video fetching (Now has access to validated tokens/user ID)
      // **FIX: Fire and forget video fetching to prevent Splash Screen hang**
      // Authenticated tokens are already ensured by ensureStrictAuth() above
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
        _initialVideos = videos;
        _hasInitialVideosMore = result['hasMore'] ?? false;
        _initialVideosTimestamp = DateTime.now();
        AppLogger.log('✅ InitManager: Fetched ${videos.length} videos.');

        // 2. Pre-initialize FIRST video only (The one user sees instantly)
        final firstVideo = videos.first;
        final controllerManager = VideoControllerManager();
        
        // Use preloadController which handles SharedPool logic internally
        AppLogger.log('🎬 InitManager: Pre-initializing first video controller (Index 0)...');
        await controllerManager.preloadController(0, firstVideo); 
        
        // 3. Warm up HLS for next few (Network only, low priority)
        unawaited(_warmUpNextVideos(videos));
      }
    } catch (e) {
       AppLogger.log('❌ InitManager: Video Fetch Failed: $e');
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


  // --- STAGE 3: DEFERRED SERVICES (After Home Mount) ---
  /// Called by MainScreen after 3-5 seconds.
  /// Goal: Load heavy SDKs without stuttering the scrolling.
  Future<void> initializeStage3() async {
    if (_isStage3Complete) return;

    try {
       // yield to UI thread first
       await Future.delayed(Duration.zero);
       
       AppLogger.log('🚀 InitManager: Stage 3 (Deferred) Started');

       // 1. Notifications (Firebase already initialized in Stage 1)
       try {
         final notificationService = NotificationService();
         await notificationService.initialize();
         AppLogger.log('✅ InitManager: Notifications initialized');
       } catch (e) {
         print('Notification Init Error: $e');
       }

       // 2. Remote Config
       try {
         await AppRemoteConfigService.instance.initialize();
       } catch(_) {}

       // 3. AdMob (Heavy!)
       try {
          await MobileAds.instance.initialize();
          // Configure request settings
           final requestConfiguration = RequestConfiguration(
            testDeviceIds: kDebugMode ? [] : [],
          );
          await MobileAds.instance.updateRequestConfiguration(requestConfiguration);
          AppLogger.log('✅ InitManager: AdMob initialized');
       } catch (_) {}

       _isStage3Complete = true;
       AppLogger.log('✅ InitManager: Stage 3 Complete');

    } catch (e) {
       AppLogger.log('❌ InitManager: Stage 3 Failed: $e');
    }
  }
}
