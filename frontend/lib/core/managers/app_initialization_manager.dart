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

  // Track the vital first page of videos
  List<VideoModel>? initialVideos;

  // --- STAGE 1: AVAILABLE IMMEDIATELY (Before UI) ---
  /// Called before `runApp`. Setup basic config.
  Future<void> initializeStage1() async {
    if (_isStage1Complete) return;

    try {
      AppLogger.log('🚀 InitManager: Stage 1 (Config) Started');
      
      // 1. Determine Backend URL
      AppConfig.clearCache();
      final workingUrl = await AppConfig.checkAndUpdateServerUrl();
      AppLogger.log('✅ InitManager: Backend URL confirmed: $workingUrl');

      // 2. Initialize Smart Cache (Memory Only, NO HIVE)
      await SmartCacheManager().initialize();

      _isStage1Complete = true;
    } catch (e) {
      AppLogger.log('❌ InitManager: Stage 1 Failed: $e');
      // Even if failed, mark complete so app continues
      _isStage1Complete = true;
    }
  }

  // --- STAGE 2: VITAL CONTENT (While Splash Visible) ---
  /// Called by SplashScreen. Fetches First Video & Profile.
  /// Goal: Ensure VideoFeed has content READY when it mounts.
  // --- STAGE 2: VITAL CONTENT (While Splash Visible) ---
  /// Called by SplashScreen. Fetches First Video & Profile.
  /// Goal: Ensure VideoFeed has content READY when it mounts.
  Future<void> initializeStage2(BuildContext context) async {
    if (_isStage2Complete) return;

    try {
      AppLogger.log('🚀 InitManager: Stage 2 (Vital Content) Started');
      final stopwatch = Stopwatch()..start();

      final videoService = VideoService();
      final authService = AuthService();

      await Future.wait([
        // Task A: Video fetching moved to VideoFeedAdvanced for instant start
        // UPDATE: Re-enabled for Splash Prefetch (Parallel)
        _fetchAndPreloadFirstVideos(videoService),
        
        // Task B: Fetch User Data (Non-blocking for video, but good to have)
        authService.getUserData().then((data) {
           AppLogger.log('✅ InitManager: User Data loaded');
        }).catchError((e) {
           AppLogger.log('⚠️ InitManager: User Data fetch failed (non-critical): $e');
        }),
      ]);

      stopwatch.stop();
      AppLogger.log('✅ InitManager: Stage 2 Complete in ${stopwatch.elapsedMilliseconds}ms');
      _isStage2Complete = true;
    } catch (e) {
      AppLogger.log('❌ InitManager: Stage 2 Failed: $e');
      _isStage2Complete = true; // Proceed anyway
    }
  }

  /// Helper: Fetch videos and pre-initialize the first one
  Future<void> _fetchAndPreloadFirstVideos(VideoService videoService) async {
    try {
      AppLogger.log('📥 InitManager: Fetching Page 1 Videos (Yug)...');
      
      // 1. Network Call
      final result = await videoService.getVideos(
        page: 1, 
        limit: 10, 
        videoType: 'yog'
      );
      
      final List<dynamic> rawList = result['videos'];
      final videos = rawList.cast<VideoModel>();

      if (videos.isNotEmpty) {
        initialVideos = videos;
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

       // 1. Firebase (Notifications)
       try {
         await Firebase.initializeApp();
         final notificationService = NotificationService();
         await notificationService.initialize();
         AppLogger.log('✅ InitManager: Firebase initialized');
       } catch (e) {
         print('Firebase Init Error: $e');
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
