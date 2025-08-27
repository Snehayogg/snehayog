import 'dart:async';
import 'package:flutter/material.dart';
// **CRITICAL FIX: Added for compute function**
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/instagram_video_service.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:snehayog/view/screens/profile_screen.dart';
import 'package:snehayog/controller/main_controller.dart';
import 'package:snehayog/core/managers/video_controller_manager.dart';
import 'package:snehayog/core/managers/smart_cache_manager.dart';
import 'package:snehayog/core/managers/video_manager.dart';
import 'package:snehayog/core/managers/video_cache_manager.dart';
import 'package:snehayog/view/widget/video_item_widget.dart';
import 'package:snehayog/view/widget/video_ui_components.dart' as ui_components;
import 'package:snehayog/view/widget/comments_sheet.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:snehayog/utils/feature_flags.dart';
import 'package:snehayog/config/app_config.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VideoScreen extends StatefulWidget {
  final int? initialIndex;
  final List<VideoModel>? initialVideos;

  const VideoScreen({Key? key, this.initialIndex, this.initialVideos})
      : super(key: key);

  static GlobalKey<_VideoScreenState> createKey() =>
      GlobalKey<_VideoScreenState>();

  @override
  _VideoScreenState createState() => _VideoScreenState();
}

/// State class for VideoScreen that manages video playback, pagination, and UI interactions
class _VideoScreenState extends State<VideoScreen> with WidgetsBindingObserver {
  // Managers
  late VideoControllerManager _controllerManager;
  late SmartCacheManager _smartCacheManager;
  late VideoManager _videoManager;
  late VideoCacheManager _videoCacheManager;

  // Service - Only keep what's needed
  final InstagramVideoService _videoService =
      InstagramVideoService(); // Only for toggleLike
  final AuthService _authService = AuthService();

  // AdMob
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;
  final Map<int, BannerAd> _videoBannerAds =
      {}; // Store banner ads for each video
  final Map<int, bool> _videoAdLoaded =
      {}; // Track loading state for each video
  final Map<int, String> _videoAdUnitIds =
      {}; // Store ad unit IDs for each video

  // Controller for the PageView that handles vertical scrolling
  late PageController _pageController;

  // Timer for periodic video health checks
  Timer? _healthCheckTimer;

  // Refresh state
  bool _isRefreshing = false;
  int _refreshCount = 0;

  // Public method to refresh videos (can be called from outside)
  void refreshVideos() {
    print('🔄 VideoScreen: refreshVideos() called from outside');
    _refreshVideos(); // Use the proper refresh method instead of _loadVideos
  }

  /// Private method to refresh videos with proper cleanup
  Future<void> _refreshVideos() async {
    try {
      print('🔄 VideoScreen: Starting video refresh...');

      // Set refreshing state
      setState(() {
        _isRefreshing = true;
        _refreshCount++;
      });

      // **NEW: Show pull-to-refresh feedback**
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Text('🔄 Refreshing videos...'),
              ],
            ),
            duration: Duration(seconds: 2),
            backgroundColor: Colors.blue,
            behavior: SnackBarBehavior.floating,
            margin: EdgeInsets.all(16),
          ),
        );
      }

      // Dispose all video controllers to free memory
      _controllerManager.disposeAll();

      // Clear current videos and reset state
      _videoManager.reset();

      // Load fresh videos
      await _loadVideos();

      // Reinitialize first video if available
      if (_videoManager.videos.isNotEmpty) {
        _initializeCurrentVideo();
      }

      print('✅ VideoScreen: Video refresh completed successfully');

      // Show success feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                    '✅ Videos refreshed! (${_videoManager.videos.length} videos)'),
              ],
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } catch (e) {
      print('❌ VideoScreen: Error refreshing videos: $e');

      // Show error feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Text('❌ Refresh failed: ${e.toString()}'),
              ],
            ),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      // Reset refreshing state
      if (mounted) {
        setState(() {
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    print('🎬 VideoScreen: Initializing with fast video delivery system');

    // Initialize managers
    _controllerManager = VideoControllerManager();
    _smartCacheManager = SmartCacheManager();
    _videoManager = VideoManager();
    _videoCacheManager = VideoCacheManager();

    // Initialize VideoManager with controller manager
    _videoManager.initialize(_controllerManager, _videoCacheManager);

    // **NEW: Initialize VideoCacheManager with disk cache BEFORE loading videos**
    _initializeVideoCachePreloading().then((_) {
      // Initialize other components after cache is ready
      _initializeComponents();

      // **DEBUG: Check if we should load videos on initialization**
      print('🔍 VideoScreen: initState - checking if videos need to be loaded');
      if (_videoManager.videos.isEmpty) {
        print(
            '📹 VideoScreen: initState - no videos in VideoManager, calling _loadVideos');
        _loadVideos();
      } else {
        print(
            '✅ VideoScreen: initState - videos already in VideoManager (${_videoManager.videos.length}), skipping _loadVideos');
      }

      _initializeAdMob();

      // Initialize smart preloading and track navigation
      _initializeSmartPreloading();

      // **NEW: Show refresh instructions for first-time users**
      Future.delayed(const Duration(seconds: 2), () {
        _showRefreshInstructions();
      });
    });
  }

  /// Initialize smart preloading system
  void _initializeSmartPreloading() async {
    if (!Features.smartVideoCaching.isEnabled) return;

    try {
      print('🚀 VideoScreen: Initializing smart preloading...');

      // Initialize smart cache manager
      await _smartCacheManager.initialize();

      // **NEW: Use VideoCacheManager instead of InstagramVideoService for preloading**
      await _videoCacheManager.preloadAndCacheData();

      // Track navigation to video screen
      _smartCacheManager.trackNavigation('video_feed', context: {
        'userId': await _getCurrentUserId(),
        'screenType': 'video_feed',
        'timestamp': DateTime.now().toIso8601String(),
      });

      // Start smart preloading for other screens
      await _smartCacheManager.smartPreload('video_feed', userContext: {
        'userId': await _getCurrentUserId(),
        'currentScreen': 'video_feed',
      });

      print('✅ VideoScreen: Smart preloading initialized');
    } catch (e) {
      print('❌ VideoScreen: Error initializing smart preloading: $e');
    }
  }

  /// **NEW: Initialize VideoCacheManager with disk cache for instant video loading**
  Future<void> _initializeVideoCachePreloading() async {
    try {
      print(
          '🚀 VideoScreen: Initializing VideoCacheManager with disk cache...');

      // Initialize disk cache
      await _videoCacheManager.initialize();

      // Force enable preloading features for testing
      print('🔧 VideoScreen: Force enabling preloading features...');
      FeatureFlags.instance.enable('smart_video_caching');
      FeatureFlags.instance.enable('background_video_preloading');
      FeatureFlags.instance.enable('instant_video_playback');

      // Preload and cache data for better performance
      await _videoCacheManager.preloadAndCacheData();

      print('✅ VideoScreen: VideoCacheManager with disk cache initialized');
    } catch (e) {
      print(
          '❌ VideoScreen: Error initializing VideoCacheManager with disk cache: $e');
    }
  }

  /// Initialize fast video delivery system
  void _initializeFastVideoDelivery() async {
    if (!Features.fastVideoDelivery.isEnabled) {
      print('🚫 VideoScreen: Fast video delivery disabled');
      return;
    }

    try {
      print('🚀 VideoScreen: Initializing fast video delivery system...');

      // Initialize controller manager
      _controllerManager.initialize();

      print('✅ VideoScreen: Fast video delivery system initialized');
    } catch (e) {
      print('❌ VideoScreen: Failed to initialize fast video delivery: $e');
    }
  }

  /// Initialize AdMob banner ad
  void _initializeAdMob() {
    _initializeBannerAd();
  }

  void _initializeComponents() {
    // Add observer to handle app lifecycle changes
    WidgetsBinding.instance.addObserver(this);

    // Register callbacks with MainController for screen switching
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mainController =
          Provider.of<MainController>(context, listen: false);
      mainController.registerPauseVideosCallback(_pauseAllVideos);
      mainController.registerResumeVideosCallback(_playActiveVideo);
      mainController.addListener(_onMainControllerChanged);

      // **NEW: Set VideoManager reference in MainController**
      mainController.setVideoManager(_videoManager);

      // Immediate check for current state
      if (!mainController.isVideoScreen) {
        print(
            '🛑 VideoScreen: Initial state check - not on video tab, pausing videos');
        _forcePauseAllVideos();
        _videoManager.updateScreenVisibility(false);
      }
    });

    // Check if videos were passed from another screen
    if (widget.initialVideos != null && widget.initialVideos!.isNotEmpty) {
      _initializeWithVideos();
    } else {
      _initializeEmptyState();
    }

    // Start periodic health checks
    _startHealthCheckTimer();

    // Listen to state changes
    _videoManager.addListener(_onStateChanged);
  }

  void _initializeWithVideos() {
    _videoManager.initializeWithVideos(
      widget.initialVideos!,
      widget.initialIndex ?? 0,
    );
    _pageController = PageController(initialPage: _videoManager.activePage);

    // Initialize controller and preload
    _initializeCurrentVideo();
  }

  void _initializeEmptyState() {
    _pageController = PageController();

    // **CRITICAL FIX: Only load videos if we don't have any cached**
    if (_videoManager.videos.isEmpty) {
      _loadVideos();
    }

    // Add listener for infinite scrolling
    _pageController.addListener(() {
      if (_pageController.position.pixels >=
              _pageController.position.maxScrollExtent - 200 &&
          !_videoManager.isLoadingMore) {
        // **CRITICAL FIX: Use VideoManager's method for loading more videos instead of _loadVideos**
        _videoManager.checkAndLoadMoreVideos(_videoManager.activePage);
      }

      // Detect page changes
      final currentPage =
          _pageController.page?.round() ?? _videoManager.activePage;
      if (currentPage != _videoManager.activePage &&
          _videoManager.isScreenVisible) {
        _onVideoPageChanged(currentPage);
      }
    });
  }

  void _initializeCurrentVideo() async {
    if (_videoManager.videos.isNotEmpty) {
      try {
        print(
            '🎬 VideoScreen: Initializing current video at index ${_videoManager.activePage}');

        // **NEW: Add timeout for video initialization**
        final initFuture = _controllerManager.initController(
          _videoManager.activePage,
          _videoManager.videos[_videoManager.activePage],
        );

        final timeoutFuture = Future.delayed(const Duration(seconds: 15));

        await Future.any([initFuture, timeoutFuture]);

        // Check if initialization actually completed
        final controller =
            _controllerManager.controllers[_videoManager.activePage];
        if (controller == null || !controller.value.isInitialized) {
          print(
              '⚠️ VideoScreen: Video initialization may have timed out, retrying...');
          // Retry initialization
          await _retryVideoInitialization();
          return;
        }

        if (mounted) {
          _playActiveVideo();
          _preloadVideosAround(_videoManager.activePage);
          setState(() {});
        }

        print('✅ VideoScreen: Current video initialized successfully');
      } catch (e) {
        print('❌ VideoScreen: Error initializing current video: $e');
        // **NEW: Handle initialization errors gracefully**
        await _handleVideoInitializationError(e);
      }
    }
  }

  /// **NEW: Retry video initialization with delay**
  Future<void> _retryVideoInitialization() async {
    try {
      print('🔄 VideoScreen: Retrying video initialization...');

      // Wait a bit before retrying
      await Future.delayed(const Duration(milliseconds: 1000));

      // Clear any existing controller for this index
      _controllerManager.disposeController(_videoManager.activePage);

      // Try initialization again
      await _controllerManager.initController(
        _videoManager.activePage,
        _videoManager.videos[_videoManager.activePage],
      );

      if (mounted) {
        _playActiveVideo();
        _preloadVideosAround(_videoManager.activePage);
        setState(() {});
      }

      print('✅ VideoScreen: Video initialization retry successful');
    } catch (e) {
      print('❌ VideoScreen: Video initialization retry failed: $e');
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load video: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _retryVideoInitialization(),
            ),
          ),
        );
      }
    }
  }

  /// **NEW: Handle video initialization errors gracefully**
  Future<void> _handleVideoInitializationError(dynamic error) async {
    print('⚠️ VideoScreen: Handling video initialization error: $error');

    // Try to recover by disposing and reinitializing
    try {
      _controllerManager.disposeController(_videoManager.activePage);

      // Wait a bit before retrying
      await Future.delayed(const Duration(milliseconds: 500));

      // Try to initialize again
      await _controllerManager.initController(
        _videoManager.activePage,
        _videoManager.videos[_videoManager.activePage],
      );

      if (mounted) {
        _playActiveVideo();
        _preloadVideosAround(_videoManager.activePage);
        setState(() {});
      }

      print('✅ VideoScreen: Error recovery successful');
    } catch (e) {
      print('❌ VideoScreen: Error recovery failed: $e');

      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Video playback error: ${e.toString()}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () => _handleVideoInitializationError(e),
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    print('🔄 VideoScreen: DISPOSE METHOD CALLED');
    print(
        '🔄 VideoScreen: Current state - isScreenVisible: ${_videoManager.isScreenVisible}');
    print('🔄 VideoScreen: Active page: ${_videoManager.activePage}');
    print('🔄 VideoScreen: Total videos: ${_videoManager.videos.length}');

    WidgetsBinding.instance.removeObserver(this);
    _healthCheckTimer?.cancel();
    print('🔄 VideoScreen: Health timer cancelled');

    // Unregister callbacks from MainController
    try {
      final mainController =
          Provider.of<MainController>(context, listen: false);
      mainController.unregisterCallbacks();
      mainController.removeListener(_onMainControllerChanged);
      print('🔄 VideoScreen: MainController callbacks unregistered');
    } catch (e) {
      print('❌ VideoScreen: Error unregistering callbacks: $e');
    }

    // Dispose managers with detailed logging
    print('🔄 VideoScreen: Disposing VideoControllerManager...');
    _controllerManager.disposeAllControllers();
    print('🔄 VideoControllerManager disposed');

    print('🔄 VideoScreen: Disposing VideoManager...');
    _videoManager.dispose();
    print('🔄 VideoManager disposed');

    print('🔄 VideoScreen: Disposing VideoCacheManager...');
    _videoCacheManager.dispose();
    print('🔄 VideoCacheManager disposed');

    print('🔄 VideoScreen: Disposing PageController...');
    _pageController.dispose();
    print('🔄 VideoScreen: PageController disposed');

    // Dispose banner ad
    _bannerAd?.dispose();
    print('🔄 VideoScreen: Banner ad disposed');

    // Dispose all video banner ads
    print('🔄 VideoScreen: Disposing video banner ads...');
    for (final entry in _videoBannerAds.entries) {
      try {
        entry.value.dispose();
        print('🔄 VideoScreen: Disposed banner ad for video ${entry.key}');
      } catch (e) {
        print('❌ Error disposing banner ad for video ${entry.key}: $e');
      }
    }
    _videoBannerAds.clear();
    _videoAdLoaded.clear();
    _videoAdUnitIds.clear();
    print('🔄 VideoScreen: All video banner ads disposed');

    super.dispose();
    print('🔄 VideoScreen: DISPOSE COMPLETED');
  }

  /// Handle app lifecycle changes
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      print('🛑 VideoScreen: App going to background - stopping all videos');

      // **NEW: Use VideoManager for app lifecycle state changes**
      _videoManager.updateAppForegroundState(false);

      // Use emergency stop for app background
      _controllerManager.emergencyStopAllVideos();

      // Pause banner ad when app goes to background
      if (_bannerAd != null && _isBannerAdLoaded) {
        print('🛑 VideoScreen: Pausing banner ad');
      }
    } else if (state == AppLifecycleState.resumed) {
      print('👁️ VideoScreen: App resumed - checking video state');

      // **NEW: Use VideoManager for app lifecycle state changes**
      _videoManager.updateAppForegroundState(true);

      if (_videoManager.isScreenVisible &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        // Use the new video visible handler
        _controllerManager.handleVideoVisible();

        // Then play the active video
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && _videoManager.isScreenVisible) {
            _playActiveVideo();
          }
        });
      }

      // Resume banner ad when app comes to foreground
      if (_bannerAd != null && !_isBannerAdLoaded) {
        print('👁️ VideoScreen: Resuming banner ad');
        _refreshBannerAd();
      }
    }
  }

  /// Handle route changes
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _checkScreenVisibility();
      }
    });
  }

  /// Check screen visibility
  void _checkScreenVisibility() {
    final mainController = Provider.of<MainController>(context, listen: false);
    final isVideoScreenActive = mainController.currentIndex == 0;

    if (!isVideoScreenActive && _videoManager.isScreenVisible) {
      print(
          '🛑 VideoScreen: Screen visibility check - tab not active, pausing videos');
      _videoManager.updateScreenVisibility(false);
      _forcePauseAllVideos();

      // Additional safety measures
      _controllerManager.handleVideoInvisible();

      // Safety check after delay
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && !mainController.isVideoScreen) {
          print('🛑 VideoScreen: Visibility check safety pause');
          _controllerManager.emergencyStopAllVideos();
        }
      });
    } else if (isVideoScreenActive && !_videoManager.isScreenVisible) {
      _videoManager.updateScreenVisibility(true);
      if (mainController.isAppInForeground) {
        _playActiveVideo();
      }

      // Refresh banner ad when screen becomes visible
      if (!_isBannerAdLoaded && _bannerAd != null) {
        print(
            '🔄 VideoScreen: Refreshing banner ad after screen visibility change');
        _refreshBannerAd();
      }
    }
  }

  /// Handle MainController changes
  void _onMainControllerChanged() {
    if (mounted) {
      final mainController =
          Provider.of<MainController>(context, listen: false);
      final isVideoScreenActive = mainController.currentIndex == 0;

      if (isVideoScreenActive && !_videoManager.isScreenVisible) {
        print('👁️ VideoScreen: Returning to video tab - checking video state');
        _videoManager.updateScreenVisibility(true);

        // **CRITICAL FIX: Check if we need to load videos or use cached data**
        if (_videoManager.videos.isEmpty) {
          print('📹 VideoScreen: No videos in memory, loading from cache/API');
          _loadVideos();
        } else {
          print(
              '✅ VideoScreen: Videos already in memory (${_videoManager.videos.length}), using cached data');
          // Just resume playback without reloading
        }

        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted &&
              _videoManager.isScreenVisible &&
              mainController.isAppInForeground) {
            _playActiveVideo();
          }
        });

        // Refresh banner ad when screen becomes visible
        if (!_isBannerAdLoaded && _bannerAd != null) {
          print(
              '🔄 VideoScreen: Refreshing banner ad after main controller change');
          _refreshBannerAd();
        }
      } else if (!isVideoScreenActive && _videoManager.isScreenVisible) {
        print('🛑 VideoScreen: Tab switched away, immediately pausing videos');
        _videoManager.updateScreenVisibility(false);

        // IMMEDIATE video pause - no delay
        _forcePauseAllVideos();

        // Use the new video invisible handler
        _controllerManager.handleVideoInvisible();

        // Additional safety pause after a short delay
        Future.delayed(const Duration(milliseconds: 25), () {
          if (mounted && !mainController.isVideoScreen) {
            print('🛑 VideoScreen: Safety pause 1 after tab switch');
            _controllerManager.emergencyStopAllVideos();
            _forcePauseAllVideos(); // Double safety
          }
        });

        // Second safety check after longer delay
        Future.delayed(const Duration(milliseconds: 75), () {
          if (mounted && !mainController.isVideoScreen) {
            print('🛑 VideoScreen: Safety pause 2 after tab switch');
            _controllerManager.emergencyStopAllVideos();
            _forcePauseAllVideos();
          }
        });

        // Third safety check after longer delay
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted && !mainController.isVideoScreen) {
            print(
                '🛑 VideoScreen: Final safety check - ensuring all videos stopped');
            _controllerManager.comprehensivePause();
            _forcePauseAllVideos();
          }
        });

        // Refresh banner ad when returning to video tab
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && mainController.isVideoScreen && !_isBannerAdLoaded) {
            print('🔄 VideoScreen: Refreshing banner ad after tab switch');
            _refreshBannerAd();
          }
        });
      }

      _checkScreenVisibility();
    }
  }

  /// Handle video page changes with immediate pause and preload
  void _onVideoPageChanged(int newPage) {
    if (newPage != _videoManager.activePage &&
        newPage >= 0 &&
        newPage < _videoManager.videos.length) {
      final oldPage = _videoManager.activePage;
      print('🔄 VideoScreen: Video page changing from $oldPage to $newPage');

      // **NEW: Update VideoManager with new video index**
      _videoManager.updateCurrentVideoIndex(newPage);

      // IMMEDIATELY pause the current video when scroll starts
      if (_videoManager.isScreenVisible) {
        _controllerManager.handleScrollStart(oldPage);
        print(
            '⏸️ VideoScreen: Immediately paused current video at index $oldPage');
      }

      _videoManager.updateCurrentVideoIndex(newPage);

      _controllerManager.handleVideoPageChange(
          oldPage, newPage, _videoManager.videos);

      // Smart preloading based on direction
      _controllerManager.smartPreloadBasedOnDirection(
          newPage, _videoManager.videos);

      // Optimize controllers
      _controllerManager.optimizeControllers();

      // Initialize banner ad for new video
      _initializeVideoBannerAd(newPage, _videoManager.videos[newPage]);

      // Play new video if screen is visible (with small delay for smooth transition)
      if (_videoManager.isScreenVisible) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted &&
              _videoManager.isScreenVisible &&
              _videoManager.activePage == newPage) {
            _playActiveVideo();
            print('▶️ VideoScreen: Playing new video at index $newPage');
          }
        });
      }

      // Refresh banner ad if it's not loaded
      if (!_isVideoBannerAdLoaded(newPage) &&
          _videoBannerAds.containsKey(newPage)) {
        print('🔄 VideoScreen: Refreshing banner ad after video change');
        _retryVideoBannerAd(newPage, _videoManager.videos[newPage]);
      }
    }
  }

  /// Pause all videos
  void _pauseAllVideos() {
    _controllerManager.pauseAllVideos();
  }

  /// Force pause all videos
  void _forcePauseAllVideos() {
    print('🛑 VideoScreen: Force pausing all videos');
    _controllerManager.comprehensivePause();
  }

  /// Comprehensive pause method that ensures all videos are stopped
  void _comprehensivePauseVideos() {
    print(
        '🛑 VideoScreen: Comprehensive pause - ensuring all videos are stopped');

    // Update screen visibility
    _videoManager.updateScreenVisibility(false);

    // Use comprehensive pause from controller manager
    _controllerManager.comprehensivePause();

    // Additional safety check after a short delay
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) {
        print('🛑 VideoScreen: Safety check after comprehensive pause');
        _controllerManager.ensureVideosPaused();
      }
    });
  }

  /// Play active video
  void _playActiveVideo() {
    if (!_videoManager.isScreenVisible) return;
    _controllerManager.playActiveVideo();
  }

  /// Load videos from service or use initial videos
  Future<void> _loadVideos() async {
    try {
      print('🔄 VideoScreen: Loading videos...');
      print(
          '🔍 VideoScreen: Current videos in VideoManager: ${_videoManager.videos.length}');
      print(
          '🔍 VideoScreen: Has cached videos (Page 1): ${_videoCacheManager.hasCachedVideos(page: 1)}');

      // **CRITICAL FIX: Check if we already have videos loaded to prevent unnecessary API calls**
      if (_videoManager.videos.isNotEmpty) {
        print(
            '✅ VideoScreen: Videos already loaded (${_videoManager.videos.length}), skipping API call');
        return;
      }

      if (widget.initialVideos != null && widget.initialVideos!.isNotEmpty) {
        print(
            '📹 VideoScreen: Using initial videos (${widget.initialVideos!.length})');
        _videoManager.initializeWithVideos(
          widget.initialVideos!,
          widget.initialIndex ?? 0,
        );

        // Set videos for fast video delivery preloading
        if (Features.fastVideoDelivery.isEnabled) {
          _controllerManager.setCurrentVideos(widget.initialVideos!);
        }
      } else {
        print(
            '🌐 VideoScreen: Loading videos with VideoCacheManager for instant cache returns...');

        // **NEW: Use VideoCacheManager for instant cache returns**
        Map<String, dynamic>? cachedVideos;
        try {
          print(
              '🔍 VideoScreen: Attempting to get cached videos from VideoCacheManager...');
          cachedVideos = _videoCacheManager.getCachedVideos(page: 1, limit: 20);
          print('🔍 VideoScreen: Cached videos result: Found');

          final cachedList = cachedVideos?['videos'];
          if (cachedList != null) {
            print('✅ VideoScreen: Found cached videos, using them instantly');
            final videos = (cachedList as List<dynamic>).cast<VideoModel>();
            _videoManager.initializeWithVideos(videos, 0);
            print('📹 VideoScreen: Loaded ${videos.length} cached videos');

            // Start background refresh for fresh data
            _refreshVideosInBackground();
            return;
          } else {
            print(
                '⚠️ VideoScreen: No cached videos found, will fetch from API');
          }
        } catch (e) {
          print('⚠️ VideoScreen: Error getting cached videos: $e');
        }

        // **NEW: Use VideoCacheManager with enhanced caching**
        print('🔍 VideoScreen: Calling VideoCacheManager.getVideos()...');
        final response = await _videoCacheManager.getVideos(
          page: 1,
          limit: 20,
          forceRefresh: false, // Use cached data if available
        );

        print(
            '🔍 VideoScreen: VideoCacheManager response status: ${response['status']}');

        if (response['status'] == 304) {
          print('✅ VideoScreen: Using cached videos (304 Not Modified)');
          // Use cached data from previous response
          final cachedVideos = _videoManager.videos;
          if (cachedVideos.isNotEmpty) {
            _videoManager.initializeWithVideos(cachedVideos, 0);
            print(
                '📹 VideoScreen: Loaded ${cachedVideos.length} cached videos');
          } else {
            // Fallback to fresh fetch if no cached data
            print(
                '⚠️ VideoScreen: No cached videos in VideoManager, forcing fresh fetch');
            final freshResponse = await _videoCacheManager.getVideos(
              page: 1,
              limit: 20,
              forceRefresh: true,
            );
            print(
                '🔍 VideoScreen: Fresh response type: ${freshResponse.runtimeType}');
            print(
                '🔍 VideoScreen: Fresh response videos type: ${freshResponse['videos']?.runtimeType}');
            final videos =
                (freshResponse['videos'] as List<dynamic>).cast<VideoModel>();
            _videoManager.initializeWithVideos(videos, 0);
            print('📹 VideoScreen: Loaded ${videos.length} fresh videos');
          }
        } else {
          print('🔍 VideoScreen: Response type: ${response.runtimeType}');
          print(
              '🔍 VideoScreen: Response videos type: ${response['videos']?.runtimeType}');
          final videos =
              (response['videos'] as List<dynamic>).cast<VideoModel>();
          _videoManager.initializeWithVideos(videos, 0);
          print('📹 VideoScreen: Loaded ${videos.length} videos from service');
        }

        // Set videos for fast video delivery preloading
        if (Features.fastVideoDelivery.isEnabled) {
          _controllerManager.setCurrentVideos(_videoManager.videos);

          // **NEW: Start smart preloading for instant video start**
          print(
              '🚀 VideoScreen: Starting smart video preloading for ${_videoManager.videos.length} videos');

          // Preload first 8 seconds of each video for instant start (non-blocking)
          try {
            unawaited(_videoCacheManager
                .preloadVideosForInstantStart(_videoManager.videos)
                .then((_) {
              print('✅ VideoScreen: Smart preloading completed successfully');
            }).catchError((e) {
              print('❌ VideoScreen: Smart preloading failed: $e');
            }));
          } catch (e) {
            print('❌ VideoScreen: Error starting smart preloading: $e');
          }

          // Preload next few pages for smooth scrolling
          await _preloadNextPages();
        }
      }

      print('✅ VideoScreen: Videos loaded successfully');
    } catch (e) {
      print('❌ VideoScreen: Error loading videos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading videos: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// **NEW: Refresh videos in background without blocking UI**
  Future<void> _refreshVideosInBackground() async {
    try {
      print('🔄 VideoScreen: Starting background video refresh...');

      // **NEW: Use VideoCacheManager for background refresh**
      final response = await _videoCacheManager.getVideos(
        page: 1,
        limit: 20,
        forceRefresh: true,
      );

      if (response['videos'] != null && mounted) {
        final videos = (response['videos'] as List<dynamic>).cast<VideoModel>();
        _videoManager.initializeWithVideos(videos, 0);
        print(
            '✅ VideoScreen: Background refresh completed with ${videos.length} videos');

        // Update UI if needed
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      print('❌ VideoScreen: Background refresh failed: $e');
    }
  }

  /// Preload next pages for smooth scrolling
  Future<void> _preloadNextPages() async {
    if (!Features.backgroundVideoPreloading.isEnabled) return;

    try {
      print('🚀 VideoScreen: Preloading next pages for smooth scrolling...');

      // Preload next 2-3 pages
      for (int page = 2; page <= 4; page++) {
        unawaited(_videoCacheManager
            .getVideos(
          page: page,
          limit: 20,
          forceRefresh: false, // Use cache if available
        )
            .then((response) {
          if (response['videos'] != null) {
            print(
                '📹 VideoScreen: Preloaded page $page with ${response['videos'].length} videos');
          }
        }));
      }

      print('✅ VideoScreen: Next pages preloading started');
    } catch (e) {
      print('⚠️ VideoScreen: Error preloading next pages: $e');
    }
  }

  /// Preload videos around index
  Future<void> _preloadVideosAround(int index) async {
    await _controllerManager.preloadVideosAround(index, _videoManager.videos);
  }

  /// Start health check timer
  void _startHealthCheckTimer() {
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted && _videoManager.isScreenVisible) {
        _controllerManager.checkVideoHealth();
        _controllerManager.optimizeControllers();
      } else if (mounted && !_videoManager.isScreenVisible) {
        print('🛑 VideoScreen: Health check - ensuring videos are paused');

        // Use the new video invisible handler
        _controllerManager.handleVideoInvisible();
      }

      // Additional safety check - ensure videos are paused if not on video tab
      if (mounted) {
        try {
          final mainController =
              Provider.of<MainController>(context, listen: false);
          if (!mainController.isVideoScreen) {
            print(
                '🛑 VideoScreen: Health check - not on video tab, forcing pause');
            _controllerManager.emergencyStopAllVideos();
          }
        } catch (e) {
          print(
              '❌ VideoScreen: Error checking main controller in health timer: $e');
        }
      }
    });

    // Cache management timers
    // Periodic tasks handled by controller manager if needed
  }

  /// Handle state changes
  void _onStateChanged() {
    if (mounted) {
      setState(() {});

      // Refresh banner ad if it's not loaded
      if (!_isBannerAdLoaded && _bannerAd != null) {
        print('🔄 VideoScreen: Refreshing banner ad after state change');
        _refreshBannerAd();
      }
    }
  }

  /// Initialize AdMob banner ad
  void _initializeBannerAd() async {
    try {
      // Create banner ad with custom listener
      _bannerAd = BannerAd(
        adUnitId: 'ca-app-pub-3940256099942544/6300978111', // Test ad unit ID
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            print('✅ Banner ad loaded successfully in VideoScreen');
            if (mounted) {
              setState(() {
                _isBannerAdLoaded = true;
              });
            }
          },
          onAdFailedToLoad: (ad, error) {
            print('❌ Banner ad failed to load: ${error.message}');
            if (mounted) {
              setState(() {
                _isBannerAdLoaded = false;
              });
            }
            // Retry after 5 seconds
            Future.delayed(const Duration(seconds: 5), () {
              if (mounted && !_isBannerAdLoaded) {
                _refreshBannerAd();
              }
            });
          },
          onAdOpened: (ad) {
            print('🎯 Banner ad opened');
          },
          onAdClosed: (ad) {
            print('🔒 Banner ad closed');
          },
        ),
      );

      // Load the ad
      await _bannerAd!.load();
    } catch (e) {
      print('❌ Error initializing banner ad: $e');
      // Retry after 5 seconds
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && !_isBannerAdLoaded) {
          _refreshBannerAd();
        }
      });
    }
  }

  /// Initialize per-video banner ad for specific video index
  Future<void> _initializeVideoBannerAd(
      int videoIndex, VideoModel video) async {
    try {
      // Skip if already initialized
      if (_videoBannerAds.containsKey(videoIndex)) {
        return;
      }

      print(
          '📱 VideoScreen: Initializing banner ad for video $videoIndex: ${video.videoName}');

      // Generate unique ad unit ID for this video (in production, use real ad unit IDs)
      final adUnitId = _generateAdUnitIdForVideo(videoIndex, video);
      _videoAdUnitIds[videoIndex] = adUnitId;

      // Create banner ad for this specific video
      final bannerAd = BannerAd(
        adUnitId: adUnitId,
        size: AdSize.banner,
        request: AdRequest(
          // Add video-specific targeting
          keywords: [
            video.videoName,
            if (video.description != null) video.description!,
            video.uploader.name,
          ].where((keyword) => keyword.isNotEmpty).toList(),
        ),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            print('✅ Video $videoIndex: Banner ad loaded successfully');
            if (mounted) {
              setState(() {
                _videoAdLoaded[videoIndex] = true;
              });
            }
            // Track ad load for revenue analytics
            _trackAdLoad(videoIndex, video);
          },
          onAdFailedToLoad: (ad, error) {
            print(
                '❌ Video $videoIndex: Banner ad failed to load: ${error.message}');
            if (mounted) {
              setState(() {
                _videoAdLoaded[videoIndex] = false;
              });
            }
            // Retry after 3 seconds
            Future.delayed(const Duration(seconds: 3), () {
              if (mounted && !(_videoAdLoaded[videoIndex] ?? false)) {
                _retryVideoBannerAd(videoIndex, video);
              }
            });
          },
          onAdOpened: (ad) {
            print('🎯 Video $videoIndex: Banner ad opened');
            // Track ad click for revenue analytics
            _trackAdClick(videoIndex, video);
          },
          onAdClosed: (ad) {
            print('🔒 Video $videoIndex: Banner ad closed');
          },
          onAdImpression: (ad) {
            print('👁️ Video $videoIndex: Banner ad impression');
            // Track ad impression for revenue analytics
            _trackAdImpression(videoIndex, video);
            // Track real ad impression for revenue calculation
            _trackRealAdImpression(videoIndex, video);
          },
        ),
      );

      // Store the banner ad
      _videoBannerAds[videoIndex] = bannerAd;
      _videoAdLoaded[videoIndex] = false;

      // Load the ad
      await bannerAd.load();

      print(
          '📱 VideoScreen: Banner ad initialization started for video $videoIndex');
    } catch (e) {
      print('❌ Error initializing video banner ad for index $videoIndex: $e');
      _videoAdLoaded[videoIndex] = false;
    }
  }

  /// Generate unique ad unit ID for video (in production, use real ad unit IDs)
  String _generateAdUnitIdForVideo(int videoIndex, VideoModel video) {
    // For testing, use different test ad unit IDs
    // In production, you would have different real ad unit IDs for different video categories
    final testAdUnitIds = [
      'ca-app-pub-3940256099942544/6300978111', // Test Banner 1
      'ca-app-pub-3940256099942544/6300978112', // Test Banner 2 (if available)
      'ca-app-pub-3940256099942544/6300978113', // Test Banner 3 (if available)
    ];

    // Use video index to cycle through different ad unit IDs
    final adUnitIndex = videoIndex % testAdUnitIds.length;
    return testAdUnitIds[adUnitIndex];
  }

  /// Retry loading banner ad for specific video
  Future<void> _retryVideoBannerAd(int videoIndex, VideoModel video) async {
    try {
      print('🔄 VideoScreen: Retrying banner ad for video $videoIndex');

      // Dispose old ad if exists
      _videoBannerAds[videoIndex]?.dispose();

      // Reinitialize
      await _initializeVideoBannerAd(videoIndex, video);
    } catch (e) {
      print('❌ Error retrying video banner ad for index $videoIndex: $e');
    }
  }

  /// Track ad load for revenue analytics
  void _trackAdLoad(int videoIndex, VideoModel video) {
    try {
      print('📊 Ad Analytics: Ad loaded for video $videoIndex');
      print('📊 Ad Analytics: Video ID: ${video.id}');
      print('📊 Ad Analytics: Video Name: ${video.videoName}');
      print('📊 Ad Analytics: Ad Unit ID: ${_videoAdUnitIds[videoIndex]}');

      // Send analytics data to backend
      _sendAdAnalytics('load', videoIndex, video);
    } catch (e) {
      print('❌ Error tracking ad load: $e');
    }
  }

  /// Track ad click for revenue analytics
  void _trackAdClick(int videoIndex, VideoModel video) {
    try {
      print('📊 Ad Analytics: Ad clicked for video $videoIndex');
      print('📊 Ad Analytics: Video ID: ${video.id}');
      print('📊 Ad Analytics: Video Name: ${video.videoName}');

      // Send analytics data to backend
      _sendAdAnalytics('click', videoIndex, video);
    } catch (e) {
      print('❌ Error tracking ad click: $e');
    }
  }

  /// Track ad impression for revenue analytics
  void _trackAdImpression(int videoIndex, VideoModel video) {
    try {
      print('📊 Ad Analytics: Ad impression for video $videoIndex');
      print('📊 Ad Analytics: Video ID: ${video.id}');
      print('📊 Ad Analytics: Video Name: ${video.videoName}');

      // Send analytics data to backend
      _sendAdAnalytics('impression', videoIndex, video);
    } catch (e) {
      print('❌ Error tracking ad impression: $e');
    }
  }

  /// Track real ad impression for revenue calculation
  void _trackRealAdImpression(int videoIndex, VideoModel video) {
    try {
      print('📊 Real Ad Impression: Video $videoIndex - ${video.videoName}');

      // In production, this would send data to your backend
      // to track actual ad impressions for revenue calculation

      // You can implement this method to:
      // 1. Send impression data to your analytics backend
      // 2. Update ad impression counters
      // 3. Calculate real-time revenue

      // Example implementation:
      // await _sendAdImpressionToBackend({
      //   'video_id': video.id,
      //   'video_index': videoIndex,
      //   'ad_unit_id': _videoAdUnitIds[videoIndex],
      //   'impression_timestamp': DateTime.now().toIso8601String(),
      //   'user_id': await _getCurrentUserId(),
      // });

      print('📊 Ad impression tracked for revenue calculation');
    } catch (e) {
      print('❌ Error tracking ad impression: $e');
    }
  }

  Future<void> _sendAdAnalytics(
      String eventType, int videoIndex, VideoModel video) async {
    try {
      print(
          '📊 Sending ad analytics to backend: $eventType for video $videoIndex');

      // Prepare analytics data
      final analyticsData = {
        'event_type': eventType, // 'load', 'click', 'impression'
        'video_id': video.id,
        'video_index': videoIndex,
        'video_name': video.videoName,
        'uploader_id': video.uploader.id,
        'uploader_name': video.uploader.name,
        'ad_unit_id': _videoAdUnitIds[videoIndex],
        'timestamp': DateTime.now().toIso8601String(),
        'user_id': await _getCurrentUserId(),
        'session_id': _generateSessionId(),
        'device_info': {
          'platform': Theme.of(context).platform.name,
          'screen_size': MediaQuery.of(context).size.toString(),
        }
      };

      print('📊 Analytics data: $analyticsData');

      // Send to backend (you can implement this based on your backend API)
      // await _sendAnalyticsToBackend(analyticsData);

      // For now, just log the data
      print('📊 Ad analytics data prepared for backend:');
      print('   Event: $eventType');
      print('   Video: ${video.videoName} (ID: ${video.id})');
      print('   Ad Unit: ${_videoAdUnitIds[videoIndex]}');
      print('   Timestamp: ${analyticsData['timestamp']}');
    } catch (e) {
      print('❌ Error sending ad analytics: $e');
    }
  }

  /// Get current user ID for analytics
  Future<String?> _getCurrentUserId() async {
    try {
      final userData = await _authService.getUserData();
      return userData?['id'] ?? userData?['googleId'];
    } catch (e) {
      print('❌ Error getting user ID: $e');
      return null;
    }
  }

  /// Generate session ID for analytics
  String _generateSessionId() {
    return 'session_${DateTime.now().millisecondsSinceEpoch}_${_videoManager.activePage}';
  }

  /// Get banner ad for specific video
  BannerAd? _getVideoBannerAd(int videoIndex) {
    return _videoBannerAds[videoIndex];
  }

  /// Check if video banner ad is loaded
  bool _isVideoBannerAdLoaded(int videoIndex) {
    return _videoAdLoaded[videoIndex] ?? false;
  }

  /// Refresh banner ad
  void _refreshBannerAd() async {
    if (_bannerAd != null) {
      _bannerAd!.dispose();
      _bannerAd = null;
    }

    setState(() {
      _isBannerAdLoaded = false;
    });

    await Future.delayed(const Duration(milliseconds: 500));
    _initializeBannerAd();
  }

  /// Handle like button - Uses InstagramVideoService only for toggleLike API call
  Future<void> _handleLike(int index) async {
    late String userId; // Non-null after guard

    try {
      print('🔍 Like Handler: Starting like process for video at index $index');

      // Refresh banner ad if it's not loaded
      if (!_isBannerAdLoaded && _bannerAd != null) {
        print('🔄 VideoScreen: Refreshing banner ad after like action');
        _refreshBannerAd();
      }

      // Validate index
      if (index < 0 || index >= _videoManager.videos.length) {
        print('❌ Like Handler: Invalid video index: $index');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid video index'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final userData = await _authService.getUserData();

      final rawId = userData?['id'] ?? userData?['googleId'];
      if (rawId == null) {
        print('❌ Like Handler: User not authenticated');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please sign in to like videos'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      userId = rawId as String; // Safe after guard
      final video = _videoManager.videos[index];
      final isCurrentlyLiked = video.likedBy.contains(userId);

      print(
          '🔍 Like Handler: User ID: $userId, Video ID: ${video.id}, Currently liked: $isCurrentlyLiked');

      // Store original state for rollback
      final originalLikedBy = List<String>.from(video.likedBy);
      final originalLikes = video.likes;

      // Optimistically update UI first
      _videoManager.updateVideoLike(index, userId);

      print('🔍 Like Handler: UI updated optimistically, calling API...');

      // **ONLY USE: InstagramVideoService for toggleLike API call**
      final updatedVideo = await _videoService.toggleLike(video.id, userId);

      print('✅ Like Handler: API call successful, updating state...');

      // Update with server response
      _videoManager.videos[index] = VideoModel.fromJson(updatedVideo.toJson());

      // Show success message
      final action = isCurrentlyLiked ? 'unliked' : 'liked';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Successfully $action video!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ),
      );

      print('✅ Like Handler: Like process completed successfully');
    } catch (e) {
      print('❌ Like Handler Error: $e');
      print('❌ Like Handler Error Type: ${e.runtimeType}');
      print('❌ Like Handler Error Details: ${e.toString()}');

      // Revert optimistic update on error
      if (index < _videoManager.videos.length) {
        // Use the state manager to properly revert the like state
        _videoManager.updateVideoLike(
            index, userId); // Use ! since we checked it's not null
        print('🔄 Like Handler: Reverted optimistic update due to error');
      }

      // Show error message
      String errorMessage = 'Failed to update like';
      if (e.toString().contains('sign in')) {
        errorMessage = 'Please sign in to like videos';
      } else if (e.toString().contains('timeout')) {
        errorMessage = 'Request timed out. Please try again.';
      } else if (e.toString().contains('network')) {
        errorMessage = 'Network error. Please check your connection.';
      } else if (e.toString().contains('not found')) {
        errorMessage = 'Video not found. Please refresh and try again.';
      } else if (e.toString().contains('userId is required')) {
        errorMessage = 'User authentication error. Please sign in again.';
      } else if (e.toString().contains('Failed to like video')) {
        errorMessage = 'Server error. Please try again later.';
      } else {
        // Show the actual error message if it's not one of the known types
        errorMessage = e.toString().replaceAll('Exception: ', '');
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Handle comment button
  void _handleComment(VideoModel video) {
    // Refresh banner ad if it's not loaded
    if (!_isBannerAdLoaded && _bannerAd != null) {
      print('🔄 VideoScreen: Refreshing banner ad after comment action');
      _refreshBannerAd();
    }

    _showCommentsSheet(video);
  }

  /// Show comments sheet - Uses InstagramVideoService for comment functionality
  void _showCommentsSheet(VideoModel video) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => CommentsSheet(
        video: video,
        videoService: _videoService, // Still needed for comment operations
        onCommentsUpdated: (List<Comment> updatedComments) {
          _videoManager.updateVideoComments(
              _videoManager.activePage, updatedComments);
        },
      ),
    );
  }

  /// Handle share button
  void _handleShare(VideoModel video) async {
    // Refresh banner ad if it's not loaded
    if (!_isBannerAdLoaded && _bannerAd != null) {
      print('🔄 VideoScreen: Refreshing banner ad after share action');
      _refreshBannerAd();
    }

    try {
      await Share.share(
        'Check out this video: ${video.videoName}\n\n${video.videoUrl}',
        subject: 'Snehayog Video',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share video: $e')),
      );
    }
  }

  /// Debug method to test like functionality
  void _debugLikeFunctionality() {
    print('🔍 DEBUG LIKE FUNCTIONALITY:');
    print('  - Total videos: ${_videoManager.videos.length}');
    print('  - Active page: ${_videoManager.activePage}');

    if (_videoManager.videos.isNotEmpty) {
      final currentVideo = _videoManager.videos[_videoManager.activePage];
      print('  - Current video ID: ${currentVideo.id}');
      print('  - Current video likes: ${currentVideo.likes}');
      print('  - Current video likedBy: ${currentVideo.likedBy}');
      print('  - Current video likedBy length: ${currentVideo.likedBy.length}');
    }

    // Check authentication
    try {
      _authService.getUserData().then((userData) {
        if (userData != null) {
          print('  - User authenticated: Yes');
          print('  - User ID: ${userData['id']}');
          print('  - User name: ${userData['name']}');
        } else {
          print('  - User authenticated: No');
        }
      });
    } catch (e) {
      print('  - Error checking authentication: $e');
    }
  }

  /// Debug method to test backend connectivity
  Future<void> _debugBackendConnectivity() async {
    print('🔍 DEBUG BACKEND CONNECTIVITY:');
    try {
      final isHealthy = await _videoService.checkServerHealth();
      print('  - Backend health check: ${isHealthy ? 'OK' : 'FAILED'}');

      if (isHealthy) {
        print('  - Backend is accessible');
        // Try to fetch a small number of videos
        try {
          final response = await _videoService.getVideos(page: 1, limit: 5);
          print('  - Video fetch test: SUCCESS');
          print('  - Videos count: ${response['videos']?.length ?? 0}');
        } catch (e) {
          print('  - Video fetch test: FAILED - $e');
        }
      } else {
        print('  - Backend is not accessible');
      }
    } catch (e) {
      print('  - Backend connectivity test failed: $e');
    }
  }

  /// Get revenue analytics summary for a specific video
  Map<String, dynamic> _getVideoRevenueAnalytics(
      int videoIndex, VideoModel video) {
    try {
      final adUnitId = _videoAdUnitIds[videoIndex];
      final isAdLoaded = _videoAdLoaded[videoIndex] ?? false;

      return {
        'video_id': video.id,
        'video_name': video.videoName,
        'video_index': videoIndex,
        'uploader_id': video.uploader.id,
        'uploader_name': video.uploader.name,
        'ad_unit_id': adUnitId,
        'ad_status': isAdLoaded ? 'loaded' : 'not_loaded',
        'ad_loaded_at': isAdLoaded ? DateTime.now().toIso8601String() : null,
        'estimated_revenue': _calculateEstimatedRevenue(videoIndex, video),
        'analytics_timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      print('❌ Error getting video revenue analytics: $e');
      return {};
    }
  }

  /// Calculate estimated revenue for a video based on AD IMPRESSIONS
  double _calculateEstimatedRevenue(int videoIndex, VideoModel video) {
    try {
      // Revenue is based on AD IMPRESSIONS, not video views
      // CPM (Cost Per Mille) = Revenue per 1000 ad impressions
      // Using weighted average CPM: 80% carousel/video feed ads (₹30), 20% banner ads (₹10)
      const weightedCpm =
          26.0; // ₹26 per 1000 ad impressions (weighted average)

      // Get ad impressions for this video
      final adImpressions = _getAdImpressionsForVideo(videoIndex, video);

      // Calculate revenue: (Ad Impressions / 1000) × CPM
      double revenue = (adImpressions / 1000.0) * weightedCpm;

      // Apply ad performance multipliers
      final adPerformanceMultiplier = _calculateAdPerformanceMultiplier(video);
      revenue *= adPerformanceMultiplier;

      return revenue;
    } catch (e) {
      print('❌ Error calculating estimated revenue: $e');
      return 0.0;
    }
  }

  /// Get ad impressions for a specific video
  int _getAdImpressionsForVideo(int videoIndex, VideoModel video) {
    try {
      // This should come from your ad analytics backend
      // For now, we'll simulate based on video engagement

      // Base impressions = video views
      int baseImpressions = video.views ?? 0;

      // Ad impressions are typically higher than video views
      // because ads can be shown multiple times per video view
      const adImpressionsMultiplier =
          1.5; // 50% more ad impressions than video views

      // Calculate estimated ad impressions
      final estimatedAdImpressions =
          (baseImpressions * adImpressionsMultiplier).round();

      print(
          '📊 Video ${video.videoName}: ${video.views} views → $estimatedAdImpressions estimated ad impressions');

      return estimatedAdImpressions;
    } catch (e) {
      print('❌ Error getting ad impressions: $e');
      return 0;
    }
  }

  /// Calculate ad performance multiplier based on engagement
  double _calculateAdPerformanceMultiplier(VideoModel video) {
    try {
      double multiplier = 1.0;

      // Higher engagement = better ad performance = higher revenue

      // Likes factor: +0.1 for every 100 likes
      if (video.likes > 0) {
        multiplier += (video.likes / 100.0) * 0.1;
      }

      // Comments factor: +0.05 for every 10 comments
      if (video.comments.isNotEmpty) {
        multiplier += (video.comments.length / 10.0) * 0.05;
      }

      // Video completion rate factor
      // Higher completion rate = better ad retention
      if (video.views > 0) {
        const estimatedCompletionRate = 0.7;
        if (estimatedCompletionRate > 0.7) {
          multiplier += (estimatedCompletionRate - 0.7) * 0.5;
        }
      }

      // Cap multiplier to reasonable bounds
      return multiplier.clamp(0.5, 2.0);
    } catch (e) {
      print('❌ Error calculating ad performance multiplier: $e');
      return 1.0;
    }
  }

  /// Get revenue multiplier for specific ad unit
  double _getRevenueMultiplierForAdUnit(String adUnitId) {
    // In production, this would come from your ad network configuration
    // For now, return different multipliers for different test ad units
    if (adUnitId.contains('6300978111')) return 1.0;
    if (adUnitId.contains('6300978112')) return 1.2;
    if (adUnitId.contains('6300978113')) return 1.5;
    return 1.0;
  }

  /// Calculate engagement multiplier based on video metrics
  double _calculateEngagementMultiplier(VideoModel video) {
    try {
      double multiplier = 1.0;

      // Likes factor
      if (video.likes > 0) {
        multiplier += (video.likes / 100.0) * 0.1; // +0.1 for every 100 likes
      }

      // Comments factor
      if (video.comments.isNotEmpty) {
        multiplier += (video.comments.length / 10.0) *
            0.05; // +0.05 for every 10 comments
      }

      // Views factor (if available)
      if (video.views > 0) {
        multiplier +=
            (video.views / 1000.0) * 0.02; // +0.02 for every 1000 views
      }

      // Cap the multiplier to reasonable bounds
      return multiplier.clamp(0.5, 3.0);
    } catch (e) {
      print('❌ Error calculating engagement multiplier: $e');
      return 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Column(
            children: [
              // Banner ad at the top with refresh button
              Container(
                width: double.infinity,
                height: 60,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    bottom: BorderSide(color: Colors.grey.shade300, width: 1),
                  ),
                ),
                child: Row(
                  children: [
                    // **REMOVED: Double-tap refresh button - now handled by Yog tab double-tap**

                    // Banner ad in the center (expanded)
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          final currentIndex = _videoManager.activePage;
                          if (!_isVideoBannerAdLoaded(currentIndex) &&
                              _videoBannerAds.containsKey(currentIndex)) {
                            _retryVideoBannerAd(currentIndex,
                                _videoManager.videos[currentIndex]);
                          }
                        },
                        child: _isVideoBannerAdLoaded(
                                    _videoManager.activePage) &&
                                _videoBannerAds
                                    .containsKey(_videoManager.activePage) &&
                                _videoBannerAds[_videoManager.activePage] !=
                                    null
                            ? AdWidget(
                                ad: _videoBannerAds[_videoManager.activePage]!)
                            : const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Loading Ad...',
                                      style: TextStyle(
                                        color: Colors.grey,
                                        fontSize: 12,
                                      ),
                                    ),
                                    Text(
                                      'Tap to retry',
                                      style: TextStyle(
                                        color: Colors.blue,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),

                    // Status indicator on the right
                    SizedBox(
                      width: 60,
                      height: 60,
                      child: Center(
                        child: _videoManager.isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.blue),
                                ),
                              )
                            : _isRefreshing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.green),
                                    ),
                                  )
                                : IconButton(
                                    onPressed: _showCurrentVideoTrackingInfo,
                                    icon: const Icon(
                                      Icons.info_outline,
                                      color: Colors.blue,
                                      size: 20,
                                    ),
                                    tooltip: 'Video Tracking Info',
                                  ),
                      ),
                    ),
                  ],
                ),
              ),

              // Main video player area
              Expanded(
                child: Column(
                  children: [
                    // Main video player
                    Expanded(
                      child: _buildVideoPlayer(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build the main video player area
  Widget _buildVideoPlayer() {
    return RepaintBoundary(
      child: VisibilityDetector(
        key: const Key('video_screen'),
        onVisibilityChanged: (VisibilityInfo visibilityInfo) {
          if (visibilityInfo.visibleFraction == 0) {
            print('🛑 VideoScreen: Screen not visible, pausing videos');
            _videoManager.updateScreenVisibility(false);
            _controllerManager.handleVideoInvisible();
          } else {
            print(
                '👁️ VideoScreen: Screen visible, checking if should play videos');
            _videoManager.updateScreenVisibility(true);
            _controllerManager.handleVideoVisible();

            // Only play if we're on the video tab and app is in foreground
            final mainController =
                Provider.of<MainController>(context, listen: false);
            if (mainController.isVideoScreen &&
                mainController.isAppInForeground) {
              Future.delayed(const Duration(milliseconds: 100), () {
                if (mounted && _videoManager.isScreenVisible) {
                  _playActiveVideo();
                }
              });
            }
          }
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification scrollInfo) {
            if (scrollInfo is ScrollUpdateNotification) {
              // Check if scrolling has started
              if (scrollInfo.dragDetails != null) {
                // User is actively scrolling - immediately pause current video
                final currentIndex =
                    _pageController.page?.round() ?? _videoManager.activePage;
                if (_videoManager.isScreenVisible &&
                    currentIndex == _videoManager.activePage) {
                  print(
                      '🔄 VideoScreen: Scroll detected - immediately pausing current video');
                  _controllerManager.handleScrollStart(currentIndex);
                }
              }

              // **NEW: Check for pull-to-refresh gesture**
              if (scrollInfo.metrics.pixels < 0) {
                // User is pulling down (negative pixels)
                if (!_isRefreshing) {
                  print('🔄 VideoScreen: Pull-down refresh gesture detected');
                  _handleScrollDownRefresh();
                }
              }

              final currentIndex =
                  _pageController.page?.round() ?? _videoManager.activePage;
              _videoManager.checkAndLoadMoreVideos(currentIndex);

              // Refresh banner ad if it's not loaded
              if (!_isBannerAdLoaded && _bannerAd != null) {
                print('🔄 VideoScreen: Refreshing banner ad after scroll');
                _refreshBannerAd();
              }
            }
            return false;
          },
          child: RefreshIndicator(
            onRefresh: _refreshVideos,
            color: Colors.blue,
            backgroundColor: Colors.white,
            strokeWidth: 3.0,
            displacement: 20.0,
            child: PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount:
                  _videoManager.videos.length + (_videoManager.hasMore ? 1 : 0),
              onPageChanged: (index) {
                print('📱 VideoScreen: PageView changed to index: $index');
                _onVideoPageChanged(index);
              },
              itemBuilder: (context, index) {
                // Show loading indicator at the end when loading more videos
                if (index == _videoManager.videos.length) {
                  return const RepaintBoundary(
                    child: ui_components.LoadingIndicatorWidget(),
                  );
                }

                final video = _videoManager.videos[index];
                final controller = _controllerManager.getController(index);

                return RepaintBoundary(
                  child: VideoItemWidget(
                    video: video,
                    controller: controller,
                    isActive: index == _videoManager.activePage,
                    index: index,
                    onLike: () => _handleLike(index),
                    onComment: () => _handleComment(video),
                    onShare: () => _handleShare(video),
                    onProfileTap: () {
                      // Refresh banner ad if it's not loaded
                      if (!_isBannerAdLoaded && _bannerAd != null) {
                        print(
                            '🔄 VideoScreen: Refreshing banner ad after profile tap');
                        _refreshBannerAd();
                      }

                      // Track navigation to profile screen for smart preloading
                      _smartCacheManager.trackNavigation('profile', context: {
                        'userId': video.uploader.id,
                        'fromScreen': 'video_feed',
                        'timestamp': DateTime.now().toIso8601String(),
                      });

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              ProfileScreen(userId: video.uploader.id),
                        ),
                      );
                    },
                    // cacheManager removed; Instagram-like caching is internal
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Build revenue display widget for current video
  Widget _buildRevenueDisplay() {
    if (_videoManager.videos.isEmpty) return const SizedBox.shrink();

    final currentVideo = _videoManager.videos[_videoManager.activePage];
    final currentIndex = _videoManager.activePage;
    final revenueAnalytics =
        _getVideoRevenueAnalytics(currentIndex, currentVideo);
    final estimatedRevenue = revenueAnalytics['estimated_revenue'] ?? 0.0;

    return Positioned(
      top: 80, // Below banner ad
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.8),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.green.withOpacity(0.6),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.attach_money,
              color: Colors.green,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(
              '\$${estimatedRevenue.toStringAsFixed(4)}',
              style: const TextStyle(
                color: Colors.green,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 4),
            GestureDetector(
              onTap: () => _showCurrentVideoRevenueAnalytics(),
              child: Icon(
                Icons.info_outline,
                color: Colors.white.withOpacity(0.7),
                size: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Show revenue analytics for current video
  void _showCurrentVideoRevenueAnalytics() {
    try {
      if (_videoManager.videos.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ No videos available for analytics'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final currentVideo = _videoManager.videos[_videoManager.activePage];
      final currentIndex = _videoManager.activePage;
      final revenueAnalytics =
          _getVideoRevenueAnalytics(currentIndex, currentVideo);

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('📊 Video Revenue Analytics'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Video: ${currentVideo.videoName}'),
              Text('Index: $currentIndex'),
              Text('Ad Unit ID: ${revenueAnalytics['ad_unit_id'] ?? 'N/A'}'),
              Text('Ad Status: ${revenueAnalytics['ad_status'] ?? 'N/A'}'),
              Text(
                  'Estimated Revenue: \$${revenueAnalytics['estimated_revenue']?.toStringAsFixed(4) ?? '0.0000'}'),
              const SizedBox(height: 16),
              const Text('Engagement Factors:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Likes: ${currentVideo.likes}'),
              Text('Comments: ${currentVideo.comments.length}'),
              Builder(
                builder: (context) {
                  final views = currentVideo.views;
                  if (views > 0) {
                    return Text('Views: $views');
                  }
                  return const SizedBox.shrink();
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } catch (e) {
      print('❌ Error showing revenue analytics: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error showing revenue analytics: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// **NEW: Get current video tracking information**
  Map<String, dynamic> getCurrentVideoTrackingInfo() {
    return _videoManager.getVideoTrackingInfo();
  }

  /// **NEW: Get current visible video index**
  int get currentVisibleVideoIndex => _videoManager.currentVisibleVideoIndex;

  /// **NEW: Show current video tracking info in debug dialog**
  void _showCurrentVideoTrackingInfo() {
    try {
      final trackingInfo = getCurrentVideoTrackingInfo();
      final cacheStats = _videoCacheManager.getCacheStats();

      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('🎬 Video Tracking Info'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                  'Current Video Index: ${trackingInfo['currentVisibleVideoIndex']}'),
              Text(
                  'Video Screen Active: ${trackingInfo['isVideoScreenActive']}'),
              Text('App In Foreground: ${trackingInfo['isAppInForeground']}'),
              Text('Should Play Videos: ${trackingInfo['shouldPlayVideos']}'),
              Text('Last Active Tab: ${trackingInfo['lastActiveTabIndex']}'),
              Text('Was On Video Tab: ${trackingInfo['wasOnVideoTab']}'),
              Text('Is Initialized: ${trackingInfo['isInitialized']}'),
              Text('Timestamp: ${trackingInfo['timestamp']}'),
              const SizedBox(height: 16),
              const Text('📊 Cache Info:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Cache Size: ${cacheStats['cacheSize']}'),
              Text('Cached Pages: ${cacheStats['totalCachedPages']}'),
              Text('Cache Time: ${cacheStats['videosCacheTime']} minutes'),
              Text(
                  'Stale Time: ${cacheStats['staleWhileRevalidateTime']} minutes'),
              const SizedBox(height: 16),
              const Text('🌐 CDN Edge Cache:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('CDN Cache Time: ${cacheStats['cdnCacheTime']} minutes'),
              Text('Total ETags: ${cacheStats['cdnCacheStats']['totalEtags']}'),
              Text(
                  'Total Last-Modified: ${cacheStats['cdnCacheStats']['totalLastModified']}'),
              Text(
                  'CDN Optimized Requests: ${cacheStats['cdnCacheStats']['cdnOptimizedRequests']}'),
              Text(
                  'Conditional Requests: ${cacheStats['cdnCacheStats']['conditionalRequestsSupported'] ? 'Supported' : 'Not Supported'}'),
              const SizedBox(height: 16),
              const Text('💾 Disk Cache:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Total Cached Videos: ${cacheStats['totalCachedVideos']}'),
              Text('Fully Downloaded: ${cacheStats['fullyDownloadedVideos']}'),
              Text('Preload Only: ${cacheStats['preloadOnlyVideos']}'),
              Text('Cache Size: ${cacheStats['diskCacheSizeMB']} MB'),
              const SizedBox(height: 16),
              const Text('🔍 Cache Status:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                  'Has Cached Videos (Page 1): ${cacheStats['hasCachedVideos']}'),
              Text('Total Videos: ${_videoManager.videos.length}'),
              Text('Current Page: ${_videoManager.currentPage}'),
              const SizedBox(height: 16),
              const Text('📋 Memory Cache Keys:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              ...cacheStats['memoryCacheKeys'].map((key) => Text('• $key')),
              const SizedBox(height: 16),
              const Text('🌐 Backend Info:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Backend URL: ${AppConfig.baseUrl}'),
              Text('Video Service URL: ${_videoService.baseUrl}'),
              const SizedBox(height: 16),
              const Text('🚀 Preloading Status:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                  'Smart Video Caching: ${Features.smartVideoCaching.isEnabled ? 'Enabled' : 'Disabled'}'),
              Text(
                  'Background Preloading: ${Features.backgroundVideoPreloading.isEnabled ? 'Enabled' : 'Disabled'}'),
              Text(
                  'Instant Playback: ${Features.instantVideoPlayback.isEnabled ? 'Enabled' : 'Disabled'}'),
              const SizedBox(height: 16),
              const Text('🔒 Controller Management:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text('Total Controllers: ${_controllerManager.controllerCount}'),
              Text(
                  'Keep-Alive Controllers: ${_controllerManager.keepAliveControllers.join(', ')}'),
              Text('Active Page: ${_videoManager.activePage}'),
              const SizedBox(height: 16),
              const Text('💾 Video Cache Status:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Builder(
                builder: (context) {
                  final cacheStatus = _controllerManager.getCachedVideoStatus();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          'Watched Videos: ${cacheStatus['watchedVideos'].join(', ')}'),
                      Text(
                          'Recently Accessed: ${cacheStatus['recentlyAccessed'].join(', ')}'),
                      Text(
                          'Cached Controllers: ${cacheStatus['cachedControllers'].join(', ')}'),
                      Text(
                          'Total Cached: ${cacheStatus['totalCached']}/${cacheStatus['maxCacheSize']}'),
                    ],
                  );
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _debugBackendConnectivity();
              },
              child: const Text('Test Backend'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _videoCacheManager.clearAllCaches();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🗑️ All caches cleared!'),
                    backgroundColor: Colors.red,
                  ),
                );
              },
              child: const Text('Clear All Caches'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                print(
                    '🧪 VideoScreen: Manually triggering video preloading...');
                try {
                  await _videoCacheManager
                      .preloadVideosForInstantStart(_videoManager.videos);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✅ Video preloading triggered!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('❌ Preloading failed: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
              child: const Text('Test Preloading'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                print('🧪 VideoScreen: Testing controller management...');
                print(
                    '🔒 Keep-alive controllers: ${_controllerManager.keepAliveControllers}');
                print(
                    '📊 Total controllers: ${_controllerManager.controllerCount}');
                print('🎯 Active page: ${_videoManager.activePage}');
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('🔒 Controller info logged to console'),
                    backgroundColor: Colors.blue,
                  ),
                );
              },
              child: const Text('Test Controllers'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                print('🧪 VideoScreen: Testing video caching system...');
                final cacheStatus = _controllerManager.getCachedVideoStatus();
                print('💾 Cache Status: $cacheStatus');

                // Test if current video is cached
                final isCurrentCached =
                    _controllerManager.isVideoCached(_videoManager.activePage);
                print('🎯 Current video cached: $isCurrentCached');

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('💾 Cache test completed - check console'),
                    backgroundColor: Colors.green,
                  ),
                );
              },
              child: const Text('Test Caching'),
            ),
          ],
        ),
      );
    } catch (e) {
      print('❌ Error showing video tracking info: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('❌ Error showing video tracking info: $e'),
        ),
      );
    }
  }

  /// **NEW: Handle double-tap refresh with haptic feedback**
  void _handleDoubleTapRefresh() {
    if (_isRefreshing) {
      // Already refreshing, show feedback
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔄 Already refreshing videos...'),
          duration: Duration(seconds: 1),
          backgroundColor: Colors.blue,
        ),
      );
      return;
    }

    print('🔄 VideoScreen: Double-tap refresh triggered');

    // Add haptic feedback
    HapticFeedback.lightImpact();

    // Show visual feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('🔄 Refreshing videos...'),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.blue,
        action: SnackBarAction(
          label: 'Cancel',
          textColor: Colors.white,
          onPressed: () {
            // Could implement cancel refresh if needed
            print('🔄 VideoScreen: Refresh cancelled by user');
          },
        ),
      ),
    );

    // Start refresh
    _refreshVideos();
  }

  /// **NEW: Handle scroll-down refresh (Instagram Reels style)**
  void _handleScrollDownRefresh() {
    if (_isRefreshing) {
      // Already refreshing, show feedback
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🔄 Already refreshing videos...'),
          duration: Duration(seconds: 1),
          backgroundColor: Colors.blue,
        ),
      );
      return;
    }

    print('🔄 VideoScreen: Scroll-down refresh triggered');

    // Add haptic feedback
    HapticFeedback.mediumImpact();

    // Show visual feedback
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🔄 Pull down to refresh videos'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.blue,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(16),
      ),
    );
  }

  /// **NEW: Show refresh instructions for first-time users only**
  void _showRefreshInstructions() async {
    try {
      // Check if user has seen the refresh instructions before
      final prefs = await SharedPreferences.getInstance();
      final hasSeenRefreshTips =
          prefs.getBool('has_seen_refresh_tips') ?? false;

      // Only show tips for first-time users
      if (!hasSeenRefreshTips && mounted) {
        // Mark that user has seen the tips
        await prefs.setBool('has_seen_refresh_tips', true);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.info, color: Colors.white),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '💡 Tip: Pull down to refresh or double-tap the Yog tab',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            duration: const Duration(seconds: 4),
            backgroundColor: Colors.blue,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.all(16),
            action: SnackBarAction(
              label: 'Got it',
              textColor: Colors.white,
              onPressed: () {
                print('🔄 VideoScreen: User acknowledged refresh instructions');
              },
            ),
          ),
        );
      }
    } catch (e) {
      print('❌ Error showing refresh instructions: $e');
    }
  }
}
