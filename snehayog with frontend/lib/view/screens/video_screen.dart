// Import statements for required Flutter and third-party packages
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:snehayog/view/screens/profile_screen.dart';
import 'package:snehayog/controller/main_controller.dart';
import 'package:snehayog/core/managers/video_controller_manager.dart';
import 'package:snehayog/core/managers/video_cache_manager.dart';
import 'package:snehayog/core/managers/video_state_manager.dart';
import 'package:snehayog/view/widget/video_ui_components.dart';
import 'package:snehayog/view/widget/comments_sheet.dart';
import 'package:snehayog/services/admob_service.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Refactored VideoScreen with modular architecture for better maintainability
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
  late VideoCacheManager _cacheManager;
  late VideoStateManager _stateManager;

  // Service
  final VideoService _videoService = VideoService();
  final AuthService _authService = AuthService();
  final AdMobService _adMobService = AdMobService();

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
    _loadVideos(isInitialLoad: false);
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

      // Dispose all video controllers to free memory
      _controllerManager.disposeAll();

      // Clear current videos and reset state
      _stateManager.reset();

      // Load fresh videos
      await _loadVideos(isInitialLoad: true);

      // Reinitialize first video if available
      if (_stateManager.videos.isNotEmpty) {
        _initializeCurrentVideo();
      }

      print('✅ VideoScreen: Video refresh completed successfully');

      // Show success feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '✅ Videos refreshed successfully! (Refresh #$_refreshCount)'),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('❌ VideoScreen: Error refreshing videos: $e');

      // Show error feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to refresh videos: ${e.toString()}'),
            duration: const Duration(seconds: 3),
            backgroundColor: Colors.red,
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

    // Initialize managers
    _controllerManager = VideoControllerManager();
    _cacheManager = VideoCacheManager();
    _stateManager = VideoStateManager();

    // Add observer to handle app lifecycle changes
    WidgetsBinding.instance.addObserver(this);

    // Register callbacks with MainController for screen switching
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mainController =
          Provider.of<MainController>(context, listen: false);
      mainController.registerPauseVideosCallback(_pauseAllVideos);
      mainController.registerResumeVideosCallback(_playActiveVideo);
      mainController.addListener(_onMainControllerChanged);
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
    _stateManager.addListener(_onStateChanged);

    // Initialize AdMob banner ad
    _initializeBannerAd();
  }

  void _initializeWithVideos() {
    _stateManager.initializeWithVideos(
      widget.initialVideos!,
      widget.initialIndex ?? 0,
    );
    _pageController = PageController(initialPage: _stateManager.activePage);

    // Initialize controller and preload
    _initializeCurrentVideo();
  }

  void _initializeEmptyState() {
    _pageController = PageController();
    _loadVideos();

    // Add listener for infinite scrolling
    _pageController.addListener(() {
      if (_pageController.position.pixels >=
              _pageController.position.maxScrollExtent - 200 &&
          !_stateManager.isLoadingMore) {
        _loadVideos(isInitialLoad: false);
      }

      // Detect page changes
      final currentPage =
          _pageController.page?.round() ?? _stateManager.activePage;
      if (currentPage != _stateManager.activePage &&
          _stateManager.isScreenVisible) {
        _onVideoPageChanged(currentPage);
      }
    });
  }

  void _initializeCurrentVideo() async {
    if (_stateManager.videos.isNotEmpty) {
      await _controllerManager.initController(
        _stateManager.activePage,
        _stateManager.videos[_stateManager.activePage],
      );

      if (mounted) {
        _playActiveVideo();
        _preloadVideosAround(_stateManager.activePage);
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    print('🔄 VideoScreen: DISPOSE METHOD CALLED');
    print(
        '🔄 VideoScreen: Current state - isScreenVisible: ${_stateManager.isScreenVisible}');
    print('🔄 VideoScreen: Active page: ${_stateManager.activePage}');
    print('🔄 VideoScreen: Total videos: ${_stateManager.videos.length}');

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

    print('🔄 VideoScreen: Disposing VideoStateManager...');
    _stateManager.dispose();
    print('🔄 VideoStateManager disposed');

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
      _stateManager.updateScreenVisibility(false);

      // Use emergency stop for app background
      _controllerManager.emergencyStopAllVideos();

      _cacheManager.automatedCacheCleanup();

      // Pause banner ad when app goes to background
      if (_bannerAd != null && _isBannerAdLoaded) {
        print('🛑 VideoScreen: Pausing banner ad');
      }
    } else if (state == AppLifecycleState.resumed) {
      print('👁️ VideoScreen: App resumed - checking video state');
      if (_stateManager.isScreenVisible &&
          (ModalRoute.of(context)?.isCurrent ?? false)) {
        // Use the new video visible handler
        _controllerManager.handleVideoVisible();

        // Then play the active video
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && _stateManager.isScreenVisible) {
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

    if (!isVideoScreenActive && _stateManager.isScreenVisible) {
      _stateManager.updateScreenVisibility(false);
      _forcePauseAllVideos();
    } else if (isVideoScreenActive && !_stateManager.isScreenVisible) {
      _stateManager.updateScreenVisibility(true);
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

      if (isVideoScreenActive && !_stateManager.isScreenVisible) {
        _stateManager.updateScreenVisibility(true);
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted &&
              _stateManager.isScreenVisible &&
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
      } else if (!isVideoScreenActive && _stateManager.isScreenVisible) {
        print('🛑 VideoScreen: Tab switched away, immediately pausing videos');
        _stateManager.updateScreenVisibility(false);

        // Use the new video invisible handler
        _controllerManager.handleVideoInvisible();

        // Additional safety pause after a short delay
        Future.delayed(const Duration(milliseconds: 50), () {
          if (mounted && !mainController.isVideoScreen) {
            print('🛑 VideoScreen: Safety pause after tab switch');
            _controllerManager.emergencyStopAllVideos();
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

  /// Handle video page changes
  void _onVideoPageChanged(int newPage) {
    if (newPage != _stateManager.activePage &&
        newPage >= 0 &&
        newPage < _stateManager.videos.length) {
      // Pause previous video
      _controllerManager.pauseVideo(_stateManager.activePage);

      // Update state
      _stateManager.updateActivePage(newPage);
      _controllerManager.updateActivePage(newPage);

      // Smart preloading
      _controllerManager.smartPreloadBasedOnDirection(
          newPage, _stateManager.videos);

      // Optimize controllers
      _controllerManager.optimizeControllers();

      // Initialize banner ad for new video
      _initializeVideoBannerAd(newPage, _stateManager.videos[newPage]);

      // Play new video if screen is visible
      if (_stateManager.isScreenVisible) {
        _playActiveVideo();
      }

      // Refresh banner ad if it's not loaded
      if (!_isVideoBannerAdLoaded(newPage) &&
          _videoBannerAds.containsKey(newPage)) {
        print('🔄 VideoScreen: Refreshing banner ad after video change');
        _retryVideoBannerAd(newPage, _stateManager.videos[newPage]);
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
    _stateManager.updateScreenVisibility(false);

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
    if (!_stateManager.isScreenVisible) return;
    _controllerManager.playActiveVideo();
  }

  /// Load videos
  Future<void> _loadVideos({bool isInitialLoad = true}) async {
    try {
      print('🎬 VideoScreen: Starting to load videos...');
      print(
          '🎬 VideoScreen: Current state - isLoading: ${_stateManager.isLoading}');
      print(
          '🎬 VideoScreen: Current videos count: ${_stateManager.videos.length}');

      await _stateManager.loadVideosWithAds(isInitialLoad: isInitialLoad);

      print(
          '🎬 VideoScreen: Videos loaded successfully: ${_stateManager.videos.length}');
      print('🎬 VideoScreen: Has error: ${_stateManager.hasError}');
      print('🎬 VideoScreen: Error message: ${_stateManager.errorMessage}');

      if (isInitialLoad && _stateManager.videos.isNotEmpty) {
        _initializeCurrentVideo();

        // Initialize banner ads for all loaded videos
        for (int i = 0; i < _stateManager.videos.length; i++) {
          _initializeVideoBannerAd(i, _stateManager.videos[i]);
        }
      } else if (isInitialLoad && _stateManager.hasError) {
        print(
            '❌ VideoScreen: Error loading videos: ${_stateManager.errorMessage}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content:
                  Text('Failed to load videos: ${_stateManager.errorMessage}'),
              backgroundColor: Colors.red,
              action: SnackBarAction(
                label: 'Retry',
                onPressed: () => _stateManager.retryLoading(),
              ),
            ),
          );
        }
      }

      // Refresh banner ad after loading videos
      if (_stateManager.videos.isNotEmpty) {
        final currentIndex = _stateManager.activePage;
        if (!_isVideoBannerAdLoaded(currentIndex) &&
            _videoBannerAds.containsKey(currentIndex)) {
          print('🔄 VideoScreen: Refreshing banner ad after loading videos');
          _retryVideoBannerAd(currentIndex, _stateManager.videos[currentIndex]);
        }
      }
    } catch (e) {
      print('❌ VideoScreen: Error in _loadVideos: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load videos: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Preload videos around index
  Future<void> _preloadVideosAround(int index) async {
    await _controllerManager.preloadVideosAround(index, _stateManager.videos);
  }

  /// Start health check timer
  void _startHealthCheckTimer() {
    _healthCheckTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted && _stateManager.isScreenVisible) {
        _controllerManager.checkVideoHealth();
        _controllerManager.optimizeControllers();
      } else if (mounted && !_stateManager.isScreenVisible) {
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
    Timer.periodic(const Duration(minutes: 2), (timer) {
      if (mounted) {
        _cacheManager.automatedCacheCleanup();
      }
    });

    Timer.periodic(const Duration(minutes: 5), (timer) {
      if (mounted) {
        _cacheManager.smartCacheManagement(
            _stateManager.totalVideos, _stateManager.activePage);
      }
    });
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

  /// Get real ad impressions from backend (if available)
  Future<int> _getRealAdImpressionsFromBackend(String videoId) async {
    try {
      // This should call your backend API to get real ad impressions
      // For now, return 0 to indicate no real data available

      // Example implementation:
      // final response = await http.get(
      //   Uri.parse('${AppConfig.baseUrl}/api/ads/impressions/$videoId'),
      //   headers: {'Authorization': 'Bearer $token'},
      // );
      //
      // if (response.statusCode == 200) {
      //   final data = json.decode(response.body);
      //   return data['impressions'] ?? 0;
      // }

      return 0; // No real data available yet
    } catch (e) {
      print('❌ Error getting real ad impressions: $e');
      return 0;
    }
  }

  /// Send ad analytics data to backend for revenue tracking
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
    return 'session_${DateTime.now().millisecondsSinceEpoch}_${_stateManager.activePage}';
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

  /// Handle like button
  Future<void> _handleLike(int index) async {
    String? userId; // Declare userId at the top level of the method

    try {
      print('🔍 Like Handler: Starting like process for video at index $index');

      // Refresh banner ad if it's not loaded
      if (!_isBannerAdLoaded && _bannerAd != null) {
        print('🔄 VideoScreen: Refreshing banner ad after like action');
        _refreshBannerAd();
      }

      // Validate index
      if (index < 0 || index >= _stateManager.videos.length) {
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

      if (userData == null || userData['id'] == null) {
        print('❌ Like Handler: User not authenticated');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please sign in to like videos'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      userId = userData['id']; // Assign to the top-level variable
      final video = _stateManager.videos[index];
      final isCurrentlyLiked = video.likedBy.contains(userId);

      print(
          '🔍 Like Handler: User ID: $userId, Video ID: ${video.id}, Currently liked: $isCurrentlyLiked');

      // Store original state for rollback
      final originalLikedBy = List<String>.from(video.likedBy);
      final originalLikes = video.likes;

      // Optimistically update UI first
      _stateManager.updateVideoLike(
          index, userId!); // Use ! since we know it's not null here

      print('🔍 Like Handler: UI updated optimistically, calling API...');

      // Call backend API
      final updatedVideo = await _videoService.toggleLike(video.id, userId);

      print('✅ Like Handler: API call successful, updating state...');

      // Update with server response
      _stateManager.videos[index] = VideoModel.fromJson(updatedVideo.toJson());

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
      if (index < _stateManager.videos.length && userId != null) {
        // Use the state manager to properly revert the like state
        _stateManager.updateVideoLike(
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

  /// Show comments sheet
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
        videoService: _videoService,
        onCommentsUpdated: (List<Comment> updatedComments) {
          _stateManager.updateVideoComments(
              _stateManager.activePage, updatedComments);
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

  /// Get cache info
  Future<void> _getCacheInfo() async {
    final cacheInfo = await _cacheManager.getCacheInfo();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            '📊 Cache: ${cacheInfo['sizeMB']} MB, ${cacheInfo['fileCount']} files'),
        backgroundColor: Colors.blue,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  /// Debug method to test like functionality
  void _debugLikeFunctionality() {
    print('🔍 DEBUG LIKE FUNCTIONALITY:');
    print('  - Total videos: ${_stateManager.videos.length}');
    print('  - Active page: ${_stateManager.activePage}');

    if (_stateManager.videos.isNotEmpty) {
      final currentVideo = _stateManager.videos[_stateManager.activePage];
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
      const cpm = 2.0; // Example: $2.00 per 1000 ad impressions

      // Get ad impressions for this video
      final adImpressions = _getAdImpressionsForVideo(videoIndex, video);

      // Calculate revenue: (Ad Impressions / 1000) × CPM
      double revenue = (adImpressions / 1000.0) * cpm;

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
          multiplier += (estimatedCompletionRate - 0.7) *
              0.5;
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
                    // Refresh button on the left
                    SizedBox(
                      width: 60,
                      height: 60,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton(
                            onPressed: _isRefreshing
                                ? null
                                : () {
                                    _refreshVideos();
                                  },
                            icon: _isRefreshing
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                          Colors.blue),
                                    ),
                                  )
                                : const Icon(
                                    Icons.refresh,
                                    color: Colors.blue,
                                    size: 24,
                                  ),
                            tooltip: _isRefreshing
                                ? 'Refreshing...'
                                : 'Refresh Videos (Tap to refresh)',
                          ),
                          if (_refreshCount > 0)
                            Text(
                              '$_refreshCount',
                              style: const TextStyle(
                                color: Colors.blue,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),

                    // Banner ad in the center (expanded)
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          final currentIndex = _stateManager.activePage;
                          if (!_isVideoBannerAdLoaded(currentIndex) &&
                              _videoBannerAds.containsKey(currentIndex)) {
                            _retryVideoBannerAd(currentIndex,
                                _stateManager.videos[currentIndex]);
                          }
                        },
                        child: _isVideoBannerAdLoaded(
                                    _stateManager.activePage) &&
                                _videoBannerAds
                                    .containsKey(_stateManager.activePage) &&
                                _videoBannerAds[_stateManager.activePage] !=
                                    null
                            ? AdWidget(
                                ad: _videoBannerAds[_stateManager.activePage]!)
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
                        child: _stateManager.isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.blue),
                                ),
                              )
                            : const Icon(
                                Icons.check_circle,
                                color: Colors.green,
                                size: 20,
                              ),
                      ),
                    ),
                  ],
                ),
              ),

              // Main video player area
              Expanded(
                child: _buildVideoPlayer(),
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
            _stateManager.updateScreenVisibility(false);
            _controllerManager.handleVideoInvisible();
          } else {
            print(
                '👁️ VideoScreen: Screen visible, checking if should play videos');
            _stateManager.updateScreenVisibility(true);
            _controllerManager.handleVideoVisible();

            // Only play if we're on the video tab and app is in foreground
            final mainController =
                Provider.of<MainController>(context, listen: false);
            if (mainController.isVideoScreen &&
                mainController.isAppInForeground) {
              Future.delayed(const Duration(milliseconds: 100), () {
                if (mounted && _stateManager.isScreenVisible) {
                  _playActiveVideo();
                }
              });
            }
          }
        },
        child: NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification scrollInfo) {
            if (scrollInfo is ScrollUpdateNotification) {
              final currentIndex =
                  _pageController.page?.round() ?? _stateManager.activePage;
              _stateManager.checkAndLoadMoreVideos(currentIndex);

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
            child: PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              itemCount:
                  _stateManager.videos.length + (_stateManager.hasMore ? 1 : 0),
              onPageChanged: (index) {
                print('📱 VideoScreen: PageView changed to index: $index');
                _onVideoPageChanged(index);
              },
              itemBuilder: (context, index) {
                // Show loading indicator at the end when loading more videos
                if (index == _stateManager.videos.length) {
                  return const RepaintBoundary(
                    child: LoadingIndicatorWidget(),
                  );
                }

                final video = _stateManager.videos[index];
                final controller = _controllerManager.getController(index);

                return RepaintBoundary(
                  child: VideoItemWidget(
                    video: video,
                    controller: controller,
                    isActive: index == _stateManager.activePage,
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

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) =>
                              ProfileScreen(userId: video.uploader.id),
                        ),
                      );
                    },
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
    if (_stateManager.videos.isEmpty) return const SizedBox.shrink();

    final currentVideo = _stateManager.videos[_stateManager.activePage];
    final currentIndex = _stateManager.activePage;
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
      if (_stateManager.videos.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('❌ No videos available for analytics'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final currentVideo = _stateManager.videos[_stateManager.activePage];
      final currentIndex = _stateManager.activePage;
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
}
