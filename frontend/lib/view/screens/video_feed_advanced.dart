import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/model/carousel_ad_model.dart';
import 'package:vayu/services/video_service.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/services/user_service.dart';
import 'package:vayu/core/managers/carousel_ad_manager.dart';
import 'package:vayu/view/widget/comments_sheet_widget.dart';
import 'package:vayu/services/active_ads_service.dart';
import 'package:vayu/services/video_view_tracker.dart';
import 'package:vayu/services/ad_refresh_notifier.dart';
import 'package:vayu/services/background_profile_preloader.dart';
import 'package:vayu/services/ad_impression_service.dart';
import 'package:vayu/view/widget/ads/banner_ad_widget.dart';
import 'package:vayu/view/widget/ads/carousel_ad_widget.dart';
import 'package:vayu/config/app_config.dart';
import 'package:vayu/view/screens/profile_screen.dart';
import 'package:vayu/view/screens/login_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayu/controller/main_controller.dart';
import 'package:vayu/core/managers/video_controller_manager.dart';
import 'package:vayu/core/managers/shared_video_controller_pool.dart';
import 'package:vayu/view/widget/report/report_dialog_widget.dart';
import 'package:vayu/core/managers/smart_cache_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:http/http.dart' as http;
import 'package:vayu/view/widget/custom_share_widget.dart';
import 'package:vayu/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VideoFeedAdvanced extends StatefulWidget {
  final int? initialIndex;
  final List<VideoModel>? initialVideos;
  final String? initialVideoId;
  final String? videoType;
  // Removed forceAutoplay; we'll infer autoplay from initialVideos presence

  const VideoFeedAdvanced({
    Key? key,
    this.initialIndex,
    this.initialVideos,
    this.initialVideoId,
    this.videoType, // **NEW: Accept videoType parameter**
  }) : super(key: key);

  @override
  _VideoFeedAdvancedState createState() => _VideoFeedAdvancedState();
}

class _VideoFeedAdvancedState extends State<VideoFeedAdvanced>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // **CORE STATE**
  List<VideoModel> _videos = [];
  bool _isLoading = true;
  String? _currentUserId;
  int _currentIndex = 0;
  final Set<String> _followingUsers = {}; // Track followed users
  String? _errorMessage; // Track error messages
  bool _isRefreshing = false; // Track if refresh is in progress

  // **SERVICES**
  late VideoService _videoService;
  late AuthService _authService;
  late CarouselAdManager _carouselAdManager;
  final VideoControllerManager _videoControllerManager =
      VideoControllerManager();

  // Decoder-budgeted priming: only allow a small number of actively playing
  // controllers during preload to avoid exhausting hardware decoders.
  static const int _decoderPrimeBudget = 2; // current + next
  int _primedStartIndex = -1;

  bool _canPrimeIndex(int index) {
    // Only prime when Yug tab is visible
    final mainController = Provider.of<MainController>(context, listen: false);
    final bool isYugVisible =
        mainController.currentIndex == 0 && _isScreenVisible;
    if (!isYugVisible) return false;

    final int start = _currentIndex;
    final int end =
        (_currentIndex + _decoderPrimeBudget - 1).clamp(0, _videos.length - 1);
    return index >= start && index <= end;
  }

  void _reprimeWindowIfNeeded() {
    final int start = _currentIndex;
    final int end =
        (_currentIndex + _decoderPrimeBudget - 1).clamp(0, _videos.length - 1);

    if (_primedStartIndex == start) return;

    // Pause anything outside the new prime window to free decoders
    _controllerPool.forEach((idx, controller) {
      if (idx < start || idx > end) {
        if (controller.value.isInitialized && controller.value.isPlaying) {
          try {
            controller.pause();
            _controllerStates[idx] = false;
          } catch (_) {}
        }
      }
    });

    _primedStartIndex = start;
  }

  /// Force play the current video regardless of tab/visibility checks.
  /// Used when navigating from Profile so the tapped video always starts.
  void forcePlayCurrent() {
    if (_videos.isEmpty ||
        _currentIndex < 0 ||
        _currentIndex >= _videos.length) {
      return;
    }

    final controller = _controllerPool[_currentIndex];
    if (controller != null && controller.value.isInitialized) {
      controller.play();
      _controllerStates[_currentIndex] = true;
      _userPaused[_currentIndex] = false;
      return;
    }

    _preloadVideo(_currentIndex).then((_) {
      if (!mounted) return;
      final c = _controllerPool[_currentIndex];
      if (c != null && c.value.isInitialized) {
        c.play();
        _controllerStates[_currentIndex] = true;
        _userPaused[_currentIndex] = false;
      }
    });
  }

  final ActiveAdsService _activeAdsService = ActiveAdsService();
  final VideoViewTracker _viewTracker = VideoViewTracker();
  final AdRefreshNotifier _adRefreshNotifier = AdRefreshNotifier();
  final BackgroundProfilePreloader _profilePreloader =
      BackgroundProfilePreloader();
  final AdImpressionService _adImpressionService = AdImpressionService();
  StreamSubscription? _adRefreshSubscription;

  // Cache manager for instant loading
  final SmartCacheManager _cacheManager = SmartCacheManager();

  // **CACHE STATUS TRACKING**
  final int _cacheHits = 0;
  final int _cacheMisses = 0;
  int _preloadHits = 0;
  final int _totalRequests = 0;

  // **AD STATE - DISABLED**
  List<Map<String, dynamic>> _bannerAds = [];
  final Map<String, Map<String, dynamic>> _lockedBannerAdByVideoId = {};
  bool _adsLoaded = false;

  // **PAGE CONTROLLER**
  late PageController _pageController;
  final bool _autoScrollEnabled = true;
  bool _isAnimatingPage = false;
  final Set<int> _autoAdvancedForIndex = {};

  final Map<int, VideoPlayerController> _controllerPool = {};
  final Map<int, bool> _controllerStates = {}; // Track if controller is active
  final int _maxPoolSize = 7; // Increased to reduce re-inits while scrolling
  final Map<int, bool> _userPaused = {};
  final Map<int, bool> _isBuffering = {};

  // **LRU TRACKING FOR LOCAL POOL**
  final Map<int, DateTime> _lastAccessedLocal =
      {}; // Track when each video was last accessed
  final Map<int, VoidCallback> _bufferingListeners = {};

  // **NEW: Track if video was playing before navigation (for resume on return)**
  final Map<int, bool> _wasPlayingBeforeNavigation = {};

  // **PRELOADING STATE**
  final Set<int> _preloadedVideos = {};
  final Set<int> _loadingVideos = {};
  final Set<int> _initializingVideos =
      {}; // Track videos currently initializing
  static const int _maxConcurrentInitializations =
      2; // Limit concurrent decoder usage
  final Map<int, int> _preloadRetryCount = {}; // Track retry attempts per video
  static const int _maxRetryAttempts = 2; // Maximum retry attempts
  Timer? _preloadTimer;

  // Track whether the first frame has rendered for each index (prevents grey texture)
  final Map<int, bool> _firstFrameReady = {};

  // Fallback to force mount player if first frame is slow (top items)
  final Map<int, bool> _forceMountPlayer = {};

  // Retention across refresh: keep visible controllers
  final Map<String, VideoPlayerController> _retainedByVideoId = {};
  final Set<int> _retainedIndices = {};

  // **INFINITE SCROLLING**
  static const int _infiniteScrollThreshold =
      4; // Load more when 4 videos from end (optimized for batch loading)
  bool _isLoadingMore = false;
  int _currentPage = 1;
  static const int _videosPerPage = 5; // Load 5 videos at a time for better UX
  bool _hasMore = true; // Track if more videos are available
  int? _totalVideos; // Total video count from backend

  // **CAROUSEL AD STATE**
  List<CarouselAdModel> _carouselAds = []; // Store loaded carousel ads
  final Map<int, ValueNotifier<int>> _currentHorizontalPage = {};

  // **USER STATE**
  bool _isScreenVisible = true;

  // **DOUBLE TAP LIKE ANIMATION**
  final Map<int, bool> _showHeartAnimation = {};

  // **EARNINGS CACHE**
  final Map<String, double> _earningsCache = {};

  // Persisted state keys
  static const String _kSavedFeedIndexKey = 'video_feed_saved_index';
  static const String _kSavedFeedTypeKey = 'video_feed_saved_type';

  // Track cold start to avoid restoring saved index on first app launch
  bool _isColdStart = true;

  // Save current feed state when app backgrounds
  Future<void> _saveBackgroundState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kSavedFeedIndexKey, _currentIndex);
      if (widget.videoType != null) {
        await prefs.setString(_kSavedFeedTypeKey, widget.videoType!);
      }
    } catch (_) {}
  }

  /// Restore retained controllers (by videoId) to their new indices after refresh
  void _restoreRetainedControllersAfterRefresh() {
    if (_retainedByVideoId.isEmpty) return;
    AppLogger.log('🔁 Restoring retained controllers after refresh...');
    final Map<String, int> idToIndex = {};
    for (int i = 0; i < _videos.length; i++) {
      idToIndex[_videos[i].id] = i;
    }
    _retainedByVideoId.forEach((videoId, controller) {
      final newIndex = idToIndex[videoId];
      if (newIndex != null) {
        // Attach back to pools
        _controllerPool[newIndex] = controller;
        _controllerStates[newIndex] = false;
        _preloadedVideos.add(newIndex);
        _firstFrameReady[newIndex] = true; // already had a frame
        AppLogger.log(
            '✅ Restored controller for video $videoId at index $newIndex');
      } else {
        try {
          controller.dispose();
          AppLogger.log(
              '🗑️ Disposed retained controller for old video $videoId');
        } catch (_) {}
      }
    });
    _retainedByVideoId.clear();
    _retainedIndices.clear();
  }

  // Restore saved state after data loads
  Future<void> _restoreBackgroundStateIfAny() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedIndex = prefs.getInt(_kSavedFeedIndexKey);
      final savedType = prefs.getString(_kSavedFeedTypeKey);

      if (savedIndex != null &&
          savedIndex >= 0 &&
          savedIndex < _videos.length &&
          (savedType == null || savedType == widget.videoType)) {
        _currentIndex = savedIndex;
        if (_pageController.hasClients) {
          _pageController.jumpToPage(_currentIndex);
        }
        WidgetsBinding.instance
            .addPostFrameCallback((_) => _tryAutoplayCurrent());
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();

    // Add app lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Initialize services
    _initializeServices();
  }

  /// Initialize services
  void _initializeServices() {
    // Reset cached URL to ensure local server is tried first
    AppConfig.resetCachedUrl();

    // **FIXED: Calculate correct initial page from initialVideoId if provided**
    int initialPage = widget.initialIndex ?? 0;
    if (widget.initialVideoId != null && widget.initialVideos != null) {
      // Find the index of the video with the given ID in initialVideos
      final videoIndex = widget.initialVideos!.indexWhere(
        (v) => v.id == widget.initialVideoId,
      );
      if (videoIndex != -1) {
        initialPage = videoIndex;
        _currentIndex = videoIndex;
      }
    }

    // Initialize page controller with correct initial page
    _pageController = PageController(initialPage: initialPage);

    // Initialize services
    _videoService = VideoService();
    _authService = AuthService();
    _carouselAdManager = CarouselAdManager();

    // Initialize cache manager
    _cacheManager.initialize();

    // Initialize ad refresh subscription
    _adRefreshSubscription = _adRefreshNotifier.refreshStream.listen((_) {
      _loadActiveAds();
    });

    // Load initial data
    _loadInitialData();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
        _saveBackgroundState();
        _videoControllerManager.pauseAllVideos();
        _videoControllerManager.onAppPaused();
        break;
      case AppLifecycleState.inactive:
        _saveBackgroundState();
        break;
      case AppLifecycleState.resumed:
        _videoControllerManager.onAppResumed();
        // Try restoring state after resume
        _restoreBackgroundStateIfAny().then((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final openedFromProfile = widget.initialVideos != null &&
                widget.initialVideos!.isNotEmpty;
            if (openedFromProfile) {
              _tryAutoplayCurrent();
              return;
            }
            final mainController =
                Provider.of<MainController>(context, listen: false);
            if (mainController.currentIndex == 0 &&
                !mainController.isMediaPickerActive &&
                !mainController.recentlyReturnedFromPicker) {
              _tryAutoplayCurrent();
            }
          });
        });
        break;
      case AppLifecycleState.detached:
        _videoControllerManager.disposeAllControllers();
        _videoControllerManager.onAppDetached();
        break;
      default:
        break;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mainController =
          Provider.of<MainController>(context, listen: false);
      // Only attempt autoplay if we're on the Yug tab and not returning from picker
      if (mainController.currentIndex == 0 &&
          !mainController.isMediaPickerActive &&
          !mainController.recentlyReturnedFromPicker) {
        _tryAutoplayCurrent();
      }
    });
  }

  /// **TRY AUTOPLAY CURRENT: Ensure current video starts playing**
  void _tryAutoplayCurrent() {
    if (_videos.isEmpty || _isLoading) return;
    // Simple rule: if opened with a provided list (from ProfileScreen), autoplay
    final openedFromProfile =
        widget.initialVideos != null && widget.initialVideos!.isNotEmpty;
    if (!openedFromProfile) {
      // Only autoplay on Yug tab when not opened from Profile
      final mainController =
          Provider.of<MainController>(context, listen: false);
      if (mainController.currentIndex != 0) return;
    }

    // Check if current video is preloaded
    if (_controllerPool.containsKey(_currentIndex)) {
      final controller = _controllerPool[_currentIndex];
      if (controller != null &&
          controller.value.isInitialized &&
          !controller.value.isPlaying) {
        // If opened from Profile, bypass tab/screen visibility guard
        if (!openedFromProfile) {
          final mainController =
              Provider.of<MainController>(context, listen: false);
          if (mainController.currentIndex != 0 || !_isScreenVisible) {
            AppLogger.log(
                '⏸️ Autoplay suppressed: not on Yug tab or screen not visible');
            return;
          }
        }

        controller.play();
        _controllerStates[_currentIndex] = true;
        _userPaused[_currentIndex] = false;
        AppLogger.log('✅ VideoFeedAdvanced: Current video autoplay started');
      }
    } else {
      // Video not preloaded, preload it and play when ready
      AppLogger.log(
          '🔄 VideoFeedAdvanced: Current video not preloaded, preloading...');
      _preloadVideo(_currentIndex).then((_) {
        if (mounted && _controllerPool.containsKey(_currentIndex)) {
          // If opened from Profile, bypass tab/screen visibility guard
          if (!openedFromProfile) {
            final mainController =
                Provider.of<MainController>(context, listen: false);
            if (mainController.currentIndex != 0 || !_isScreenVisible) {
              AppLogger.log(
                  '⏸️ Autoplay suppressed after preload: not on Yug tab or screen not visible');
              return;
            }
          }

          final controller = _controllerPool[_currentIndex];
          if (controller != null && controller.value.isInitialized) {
            controller.play();
            _controllerStates[_currentIndex] = true;
            _userPaused[_currentIndex] = false;
            AppLogger.log(
              '✅ VideoFeedAdvanced: Current video autoplay started after preloading',
            );
          }
        }
      });
    }
  }

  // (Reverted: removed _autoplayWhenReady helper)

  /// **HANDLE VISIBILITY CHANGES: Pause/resume videos based on tab visibility**
  void _handleVisibilityChange(bool isVisible) {
    if (_isScreenVisible != isVisible) {
      _isScreenVisible = isVisible;

      if (isVisible) {
        // Screen became visible - resume current video
        _tryAutoplayCurrent();

        // **NEW: Start background profile preloading**
        _profilePreloader.startBackgroundPreloading();
      } else {
        // Screen became hidden - pause current video
        _pauseCurrentVideo();

        // **NEW: Stop background profile preloading**
        _profilePreloader.stopBackgroundPreloading();
      }
    }
  }

  /// **PAUSE CURRENT VIDEO: When screen becomes hidden**
  void _pauseCurrentVideo() {
    // **NEW: Stop view tracking when pausing**
    if (_currentIndex < _videos.length) {
      final currentVideo = _videos[_currentIndex];
      _viewTracker.stopViewTracking(currentVideo.id);
    }

    // Pause local controller pool
    if (_controllerPool.containsKey(_currentIndex)) {
      final controller = _controllerPool[_currentIndex];

      if (controller != null &&
          controller.value.isInitialized &&
          controller.value.isPlaying) {
        controller.pause();
        _controllerStates[_currentIndex] = false;
      }
    }

    // Also pause VideoControllerManager videos
    _videoControllerManager.pauseAllVideosOnTabChange();
  }

  void _pauseAllVideosOnTabSwitch() {
    // Pause all active controllers in the pool
    _controllerPool.forEach((index, controller) {
      if (controller.value.isInitialized && controller.value.isPlaying) {
        controller.pause();
        _controllerStates[index] = false;
      }
    });

    // Also pause VideoControllerManager videos
    _videoControllerManager.pauseAllVideosOnTabChange();

    // Update screen visibility state
    _isScreenVisible = false;
  }

  /// **OPTIMIZED: Load initial data with parallel ad loading**
  Future<void> _loadInitialData() async {
    try {
      setState(() => _isLoading = true);

      // **CRITICAL FIX: Use initialVideos if provided, otherwise load from API**
      if (widget.initialVideos != null && widget.initialVideos!.isNotEmpty) {
        // Use provided videos instead of API call
        _videos = List.from(widget.initialVideos!);
      } else {
        // Load from API
        await _loadVideos(page: 1);
      }

      await _loadCurrentUserId();

      // **CRITICAL FIX: Verify the current index is correct with the loaded videos**
      // _currentIndex is already set correctly in _initializeServices
      // Just verify that the video at _currentIndex matches initialVideoId
      if (widget.initialVideoId != null && _videos.isNotEmpty) {
        final videoAtCurrentIndex = _videos[_currentIndex];
        if (videoAtCurrentIndex.id != widget.initialVideoId) {
          // Video mismatch detected, find correct index
          final correctIndex = _videos.indexWhere(
            (v) => v.id == widget.initialVideoId,
          );
          if (correctIndex != -1) {
            _currentIndex = correctIndex;
            // Also update PageController to correct page
            _pageController.jumpToPage(correctIndex);
          }
        }
      }

      // Attempt to restore background state now that videos are available
      // Skip on cold start so the first video plays by default
      if (!_isColdStart) {
        await _restoreBackgroundStateIfAny();
      }

      // **OPTIMIZED: Show videos immediately without waiting for ads**
      if (mounted) {
        setState(() => _isLoading = false);
        AppLogger.log(
          '🚀 VideoFeedAdvanced: Set loading to false, videos count: ${_videos.length}',
        );

        // **FIXED: Trigger autoplay immediately after videos load**
        // PageController is already initialized with correct page, so no jump needed
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Mark cold start complete after first frame renders
          _isColdStart = false;
          AppLogger.log(
            '🚀 VideoFeedAdvanced: Triggering instant autoplay after video load at index $_currentIndex',
          );
          _tryAutoplayCurrent();
        });
      }

      // **OPTIMIZED: Load ads in background (non-blocking)**
      // Ads will appear when ready, but won't delay video display
      _loadActiveAds(); // No 'await' - runs in background
    } catch (e) {
      AppLogger.log('❌ Error loading initial data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  /// **LOAD CURRENT USER ID: Get authenticated user's ID**
  Future<void> _loadCurrentUserId() async {
    try {
      final userData = await _authService.getUserData();
      if (userData != null && userData['id'] != null) {
        setState(() {
          _currentUserId = userData['id'];
        });
        AppLogger.log('✅ Loaded current user ID: $_currentUserId');
      }
    } catch (e) {
      AppLogger.log('❌ Error loading current user ID: $e');
    }
  }

  /// **OPTIMIZED: Load active ads in background without blocking videos**
  Future<void> _loadActiveAds() async {
    try {
      AppLogger.log(
          '🎯 VideoFeedAdvanced: Loading fallback ads in background...');

      // Load fallback ads for general use (when no specific video context)
      final allAds = await _activeAdsService.fetchActiveAds();

      if (mounted) {
        setState(() {
          _bannerAds = allAds['banner'] ?? [];
          _adsLoaded = true;
        });

        AppLogger.log('✅ VideoFeedAdvanced: Fallback ads loaded:');
        AppLogger.log('   Banner ads: ${_bannerAds.length}');

        // **NEW: Debug banner ad details**
        for (int i = 0; i < _bannerAds.length; i++) {
          final ad = _bannerAds[i];
          AppLogger.log(
            '   Banner Ad $i: ${ad['title']} (${ad['adType']}) - Active: ${ad['isActive']}',
          );
        }
      }

      await _carouselAdManager.loadCarouselAds();
      // Load carousel ads only for Yug/Yog tab
      if (widget.videoType == 'yug' || widget.videoType == 'yog') {
        await _loadCarouselAds();
      }
    } catch (e) {
      AppLogger.log('❌ Error loading fallback ads: $e');
      if (mounted) {
        setState(() {
          _adsLoaded =
              true; // Mark as loaded even on error to prevent infinite loading
        });
      }
    }
  }

  /// **LOAD FOLLOWING USERS: Check follow status for each video uploader**
  Future<void> _loadFollowingUsers() async {
    if (_currentUserId == null || _videos.isEmpty) return;

    try {
      final userService = UserService();

      // Check follow status for each unique uploader
      final uniqueUploaders = _videos
          .map((video) => video.uploader.id)
          .toSet()
          .where((id) => id != _currentUserId) // Don't check self
          .toList();

      AppLogger.log(
        '🔍 Checking follow status for ${uniqueUploaders.length} unique uploaders',
      );

      for (final uploaderId in uniqueUploaders) {
        try {
          final isFollowing = await userService.isFollowingUser(uploaderId);
          if (isFollowing) {
            setState(() {
              _followingUsers.add(uploaderId);
            });
          }
        } catch (e) {
          AppLogger.log('❌ Error checking follow status for $uploaderId: $e');
        }
      }

      AppLogger.log(
          '✅ Loaded follow status for ${_followingUsers.length} users');
    } catch (e) {
      AppLogger.log('❌ Error loading following users: $e');
    }
  }

  /// **LOAD VIDEOS WITH PAGINATION AND CACHING**
  Future<void> _loadVideos({int page = 1, bool append = false}) async {
    try {
      AppLogger.log('🔄 Loading videos - Page: $page, Append: $append');
      _printCacheStatus();

      AppLogger.log('🔍 VideoFeedAdvanced: Loading videos directly from API');
      final response = await _videoService.getVideos(
        page: page,
        limit: _videosPerPage,
        videoType: widget.videoType,
      );

      AppLogger.log('✅ VideoFeedAdvanced: Successfully loaded videos from API');
      AppLogger.log(
          '🔍 VideoFeedAdvanced: Response keys: ${response.keys.toList()}');

      final newVideos = response['videos'] as List<VideoModel>;

      // **NEW: Extract pagination metadata from backend**
      final hasMore = response['hasMore'] as bool? ?? false;
      final total = response['total'] as int? ?? 0;
      final currentPage = response['currentPage'] as int? ?? page;
      final totalPages = response['totalPages'] as int? ?? 1;

      AppLogger.log('📊 Video Loading Complete:');
      AppLogger.log('   New Videos Loaded: ${newVideos.length}');
      AppLogger.log('   Page: $currentPage / $totalPages');
      AppLogger.log('   Has More: $hasMore');
      AppLogger.log('   Total Videos Available: $total');

      if (mounted) {
        setState(() {
          if (append) {
            _videos.addAll(newVideos);
            AppLogger.log('📝 Appended videos, total: ${_videos.length}');
          } else {
            _videos = newVideos;
            AppLogger.log('📝 Set videos, total: ${_videos.length}');
          }
          _currentPage = currentPage;
          _hasMore = hasMore; // **NEW: Store hasMore flag**
          _totalVideos = total; // **NEW: Store total count**
        });

        // Load following users after videos are loaded
        await _loadFollowingUsers();

        // **FIXED: Trigger autoplay after videos are loaded**
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _tryAutoplayCurrent();
          });
        }

        // Preload current and nearby videos to avoid grey frames
        // Ensure index is valid after reload
        if (_currentIndex >= _videos.length) {
          _currentIndex = 0;
        }
        await _preloadVideo(_currentIndex);
        _preloadNearbyVideos();
        _tryAutoplayCurrent();

        // Pre-cache thumbnails for the first few items so an image shows instantly
        for (final v in _videos.take(5)) {
          if (v.thumbnailUrl.isNotEmpty) {
            try {
              // ignore: use_build_context_synchronously
              await precacheImage(
                  CachedNetworkImageProvider(v.thumbnailUrl), context);
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      AppLogger.log('❌ Error loading videos: $e');
      AppLogger.log('❌ Error stack trace: ${StackTrace.current}');
      // **NEW: Set hasMore to false on error to prevent infinite retries**
      if (mounted) {
        setState(() {
          _hasMore = false;
        });
      }
    }
  }

  /// **OPTIMIZED: Refresh video list with background ad loading**
  Future<void> refreshVideos() async {
    AppLogger.log('🔄 VideoFeedAdvanced: refreshVideos() called');

    // **CRITICAL FIX: Prevent multiple simultaneous refresh calls**
    if (_isLoading || _isRefreshing) {
      AppLogger.log(
        '⚠️ VideoFeedAdvanced: Already refreshing/loading, ignoring duplicate call',
      );
      return;
    }

    // **CRITICAL FIX: Pause and stop all existing controllers before refresh**
    AppLogger.log('🛑 Stopping all videos before refresh...');
    await _stopAllVideosAndClearControllers();

    // Mark as refreshing
    _isRefreshing = true;

    try {
      // Show loading state
      if (mounted) {
        setState(() {
          _isLoading = true;
          _errorMessage = null; // Clear any previous errors
        });
      }

      // **NEW: Clear video cache before refreshing to ensure fresh data**
      final cacheManager = SmartCacheManager();
      await cacheManager.invalidateVideoCache(videoType: widget.videoType);

      // Reset to page 1 and reload videos
      _currentPage = 1;
      await _loadVideos(page: 1, append: false);

      // **OPTIMIZED: Hide loading and show videos immediately**
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });

        // **CRITICAL FIX: Only autoplay if still on video feed**
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final mainController =
                Provider.of<MainController>(context, listen: false);
            // Only autoplay if we're actually on the video tab (index 0)
            if (mainController.currentIndex == 0) {
              _tryAutoplayCurrent();
            }
          }
        });
      }

      AppLogger.log('✅ VideoFeedAdvanced: Videos refreshed successfully');
      // After data loads, try to restore retained controllers by videoId
      _restoreRetainedControllersAfterRefresh();
      _loadActiveAds();

      // **MANUAL REFRESH: Reload carousel ads when user refreshes**
      AppLogger.log(
        '🔄 VideoFeedAdvanced: Reloading carousel ads after manual refresh...',
      );
      await _carouselAdManager.loadCarouselAds();

      // After a manual refresh, proactively preload current and nearby videos
      if (mounted && _videos.isNotEmpty) {
        if (_currentIndex >= _videos.length) {
          _currentIndex = 0;
        }
        await _preloadVideo(_currentIndex);
        _preloadNearbyVideos();
        _tryAutoplayCurrent();

        // Pre-cache thumbnails for the first few refreshed items
        for (final v in _videos.take(5)) {
          if (v.thumbnailUrl.isNotEmpty) {
            try {
              // ignore: use_build_context_synchronously
              await precacheImage(
                  CachedNetworkImageProvider(v.thumbnailUrl), context);
            } catch (_) {}
          }
        }
      }
    } catch (e) {
      AppLogger.log('❌ VideoFeedAdvanced: Error refreshing videos: $e');

      // Set error state
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }

      // Show user-friendly error message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Failed to refresh: ${_getUserFriendlyErrorMessage(e)}',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () {
                // Retry refresh
                refreshVideos();
              },
            ),
          ),
        );
      }
    } finally {
      // **CRITICAL FIX: Always clear the refreshing flag**
      _isRefreshing = false;
    }
  }

  /// **NEW: Stop all videos and dispose controllers before refresh**
  Future<void> _stopAllVideosAndClearControllers() async {
    AppLogger.log('🛑 _stopAllVideosAndClearControllers: Starting cleanup...');

    // Decide which indices to retain (current and adjacent)
    _retainedByVideoId.clear();
    _retainedIndices.clear();
    final toRetain = <int>{
      if (_currentIndex >= 0) _currentIndex,
      if (_currentIndex - 1 >= 0) _currentIndex - 1,
      if (_currentIndex + 1 < _videos.length) _currentIndex + 1,
    };

    // Step 1: Pause all active controllers
    _controllerPool.forEach((index, controller) {
      try {
        if (controller.value.isInitialized && controller.value.isPlaying) {
          controller.pause();
          AppLogger.log('⏸️ Paused video at index $index');
        }

        // Remove listeners to prevent memory leaks
        controller.removeListener(_bufferingListeners[index] ?? () {});
        controller.removeListener(_videoEndListeners[index] ?? () {});

        // Retain visible controllers; dispose others
        if (toRetain.contains(index) && index < _videos.length) {
          final vid = _videos[index].id;
          _retainedByVideoId[vid] = controller;
          _retainedIndices.add(index);
          AppLogger.log(
              '🔒 Retaining controller at index $index for video $vid');
        } else {
          controller.dispose();
          AppLogger.log('🗑️ Disposed controller at index $index');
        }
      } catch (e) {
        AppLogger.log('⚠️ Error stopping video at index $index: $e');
      }
    });

    // Step 2: Clear all controller-related state and initialization tracking
    _initializingVideos.clear();
    _preloadRetryCount.clear();
    _controllerPool.clear();
    _controllerStates.clear();
    _userPaused.clear();
    _isBuffering.clear();
    _preloadedVideos.clear();
    _loadingVideos.clear();
    _bufferingListeners.clear();
    _videoEndListeners.clear();
    _wasPlayingBeforeNavigation.clear();
    _firstFrameReady.clear();
    _forceMountPlayer.clear();

    // Prefer to retain visible controllers in shared pool to keep them warm
    try {
      final sharedPool = SharedVideoControllerPool();
      final keep = <String>[];
      if (_controllerPool.containsKey(_currentIndex) &&
          _currentIndex < _videos.length) {
        keep.add(_videos[_currentIndex].id);
      }
      if (_controllerPool.containsKey(_currentIndex + 1) &&
          _currentIndex + 1 < _videos.length) {
        keep.add(_videos[_currentIndex + 1].id);
      }
      if (keep.isEmpty) {
        sharedPool.clearAll();
      } else {
        sharedPool.clearExcept(keep);
      }
      AppLogger.log(
          '🗑️ Refreshed SharedVideoControllerPool, kept warm: ${keep.length}');
    } catch (e) {
      AppLogger.log('⚠️ Error refreshing SharedVideoControllerPool: $e');
    }

    // Step 3: Stop view tracking
    try {
      _viewTracker.dispose();
      AppLogger.log('🎯 Stopped view tracking');
    } catch (e) {
      AppLogger.log('⚠️ Error stopping view tracking: $e');
    }

    // Step 4: Clear VideoControllerManager
    try {
      _videoControllerManager.disposeAllControllers();
      AppLogger.log('🗑️ Disposed VideoControllerManager controllers');
    } catch (e) {
      AppLogger.log('⚠️ Error disposing VideoControllerManager: $e');
    }

    // Step 5: Reset current index to 0 if videos list changed
    if (_videos.isEmpty && mounted) {
      setState(() {
        _currentIndex = 0;
      });
      AppLogger.log('🔄 Reset current index to 0');
    }

    AppLogger.log('✅ _stopAllVideosAndClearControllers: Cleanup complete');
  }

  /// **NEW: Invalidate video cache keys when videos are deleted**
  Future<void> _invalidateVideoCache() async {
    try {
      AppLogger.log('🗑️ VideoFeedAdvanced: Invalidating video cache keys');
      final cacheManager = SmartCacheManager();
      await cacheManager.invalidateVideoCache(videoType: widget.videoType);
      AppLogger.log('✅ VideoFeedAdvanced: Video cache invalidated');
    } catch (e) {
      AppLogger.log('⚠️ VideoFeedAdvanced: Error invalidating cache: $e');
    }
  }

  /// **NEW: Refresh only ads (for when new ads are created)**
  Future<void> refreshAds() async {
    AppLogger.log('🔄 VideoFeedAdvanced: refreshAds() called');

    try {
      await _loadActiveAds();

      // Also refresh carousel ads only for Yog tab
      if (widget.videoType == 'yog') {
        await _loadCarouselAds();
      }

      AppLogger.log('✅ VideoFeedAdvanced: Ads refreshed successfully');
    } catch (e) {
      AppLogger.log('❌ Error refreshing ads: $e');
    }
  }

  /// **NEW: Load carousel ads for Yog tab**
  Future<void> _loadCarouselAds() async {
    try {
      AppLogger.log(
          '🎯 VideoFeedAdvanced: Loading carousel ads for Yog tab...');

      // **FIXED: Wait for carousel ads to load before accessing them**
      await _carouselAdManager.loadCarouselAds();
      final carouselAds = _carouselAdManager.carouselAds;

      if (mounted) {
        setState(() {
          _carouselAds = carouselAds;
        });
        AppLogger.log(
          '✅ VideoFeedAdvanced: Loaded ${_carouselAds.length} carousel ads',
        );
      }
    } catch (e) {
      AppLogger.log('❌ Error loading carousel ads: $e');
    }
  }

  /// **NEW: Load targeted ads when video changes**
  void _onVideoChanged(int newIndex) {
    if (_currentIndex != newIndex) {
      setState(() => _currentIndex = newIndex);
      AppLogger.log('🔄 VideoFeedAdvanced: Video changed to index $newIndex');
    }
  }

  /// **LOAD MORE VIDEOS FOR INFINITE SCROLLING**
  Future<void> _loadMoreVideos() async {
    // **NEW: Check if more videos are available**
    if (!_hasMore) {
      AppLogger.log('✅ All videos loaded (hasMore: false)');
      return;
    }

    if (_isLoadingMore) {
      AppLogger.log('⏳ Already loading more videos');
      return;
    }

    AppLogger.log('📡 Loading more videos: Page ${_currentPage + 1}');
    setState(() => _isLoadingMore = true);

    try {
      await _loadVideos(page: _currentPage + 1, append: true);
      AppLogger.log('✅ Loaded more videos successfully');
    } catch (e) {
      AppLogger.log('❌ Error loading more videos: $e');
      // Set hasMore to false on error to prevent infinite retries
      if (mounted) {
        setState(() {
          _hasMore = false;
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  /// **START PRELOADING TIMER**
  void _startPreloading() {
    _preloadTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _preloadNearbyVideos();
    });
  }

  /// **PRELOAD VIDEOS NEAR CURRENT INDEX (Smart: Current + Next 2)**
  void _preloadNearbyVideos() {
    if (_videos.isEmpty) return;

    final sharedPool = SharedVideoControllerPool();

    // **SMART PRELOADING: Preload current + next 2 videos (total 3)**
    final preloadWindow = 2; // Next 2 videos
    for (int i = _currentIndex;
        i <= _currentIndex + preloadWindow && i < _videos.length;
        i++) {
      final video = _videos[i];

      // **INSTANT LOADING: Skip if already in shared pool**
      if (sharedPool.isVideoLoaded(video.id)) {
        _preloadedVideos.add(i);
        continue;
      }

      // Preload if not already loading/preloaded
      if (!_preloadedVideos.contains(i) && !_loadingVideos.contains(i)) {
        _preloadVideo(i);
      }
    }

    // **MEMORY MANAGEMENT: Cleanup distant controllers**
    sharedPool.cleanupDistantControllers(_currentIndex, keepRange: 3);

    // **OPTIMIZED: Load more videos only if more are available and user is near the end**
    if (_hasMore &&
        !_isLoadingMore &&
        _currentIndex >= _videos.length - _infiniteScrollThreshold) {
      AppLogger.log(
          '📡 Triggering load more: index=$_currentIndex, total=${_videos.length}, hasMore=$_hasMore');
      _loadMoreVideos();
    } else if (!_hasMore) {
      AppLogger.log('✅ All videos loaded, no more to load');
    }
  }

  /// **PRELOAD SINGLE VIDEO**
  Future<void> _preloadVideo(int index) async {
    if (index >= _videos.length) return;

    // **NEW: Check if we're already at max concurrent initializations**
    if (_initializingVideos.length >= _maxConcurrentInitializations &&
        !_preloadedVideos.contains(index) &&
        !_loadingVideos.contains(index)) {
      // Queue this video for later initialization
      AppLogger.log(
          '⏳ Max concurrent initializations reached, deferring video $index');
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted && !_preloadedVideos.contains(index)) {
          _preloadVideo(index);
        }
      });
      return;
    }

    _loadingVideos.add(index);

    // **CACHE STATUS CHECK ON PRELOAD**
    AppLogger.log('🔄 Preloading video $index');
    _printCacheStatus();

    String? videoUrl;
    VideoPlayerController? controller;
    bool isReused = false;

    try {
      final video = _videos[index];

      // **REMOVED: Processing status check - backend now only returns completed videos**

      // **FIXED: Resolve playable URL (handles share page URLs)**
      videoUrl = await _resolvePlayableUrl(video);
      if (videoUrl == null || videoUrl.isEmpty) {
        AppLogger.log(
            '❌ Invalid video URL for video $index: ${video.videoUrl}');
        _loadingVideos.remove(index);
        return;
      }

      AppLogger.log('🎬 Preloading video $index with URL: $videoUrl');

      // **UNIFIED STRATEGY: Check shared pool FIRST for instant playback**
      final sharedPool = SharedVideoControllerPool();

      // **INSTANT LOADING: Try to get controller with instant playback guarantee**
      final instantController =
          sharedPool.getControllerForInstantPlay(video.id);
      if (instantController != null) {
        controller = instantController;
        isReused = true;
        AppLogger.log(
            '⚡ INSTANT: Reusing controller from shared pool for video: ${video.id}');
        // **CRITICAL: Add to local tracking for UI updates**
        _controllerPool[index] = controller;
        _lastAccessedLocal[index] = DateTime.now();
      } else if (sharedPool.isVideoLoaded(video.id)) {
        // Fallback: Get any controller from shared pool
        final fallbackController = sharedPool.getController(video.id);
        if (fallbackController != null) {
          controller = fallbackController;
          isReused = true;
          AppLogger.log(
              '♻️ Reusing controller from shared pool for video: ${video.id}');
          _controllerPool[index] = controller;
          _lastAccessedLocal[index] = DateTime.now();
        }
      }

      // If no controller in shared pool, create new one
      if (controller == null) {
        // **HLS SUPPORT: Check if URL is HLS and configure accordingly**
        final Map<String, String> headers = videoUrl.contains('.m3u8')
            ? const {
                'Accept': 'application/vnd.apple.mpegurl,application/x-mpegURL',
              }
            : const {};

        controller = VideoPlayerController.networkUrl(
          Uri.parse(videoUrl),
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: true,
            allowBackgroundPlayback: false,
          ),
          httpHeaders: headers,
        );
      }

      // **SKIP INITIALIZATION: If reusing from shared pool, controller is already initialized**
      if (!isReused) {
        // **NEW: Track concurrent initializations**
        _initializingVideos.add(index);

        try {
          // **HLS SUPPORT: Add HLS-specific configuration**
          if (videoUrl.contains('.m3u8')) {
            AppLogger.log('🎬 HLS Video detected: $videoUrl');
            AppLogger.log('🎬 HLS Video duration: ${video.duration}');
            await controller.initialize().timeout(
              const Duration(seconds: 30), // Increased timeout for HLS
              onTimeout: () {
                throw Exception('HLS video initialization timeout');
              },
            );
            AppLogger.log('✅ HLS Video initialized successfully');
          } else {
            AppLogger.log('🎬 Regular Video detected: $videoUrl');
            // **FIXED: Add timeout and better error handling for regular videos**
            await controller.initialize().timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                throw Exception('Video initialization timeout');
              },
            );
            AppLogger.log('✅ Regular Video initialized successfully');
          }
        } finally {
          // **NEW: Always remove from initializing set**
          _initializingVideos.remove(index);
        }
      } else {
        AppLogger.log(
            '♻️ Skipping initialization - reusing initialized controller');
      }

      if (mounted && _loadingVideos.contains(index)) {
        _controllerPool[index] = controller;
        _controllerStates[index] = false; // Not playing initially
        _preloadedVideos.add(index);
        _loadingVideos.remove(index);
        // **LRU: Track access time when controller is added**
        _lastAccessedLocal[index] = DateTime.now();

        // **UNIFIED STRATEGY: Always add to shared pool with index tracking**
        final sharedPool = SharedVideoControllerPool();
        final video = _videos[index];
        sharedPool.addController(video.id, controller, index: index);
        AppLogger.log(
            '✅ Added video controller to shared pool: ${video.id} (index: $index)');

        // Apply looping vs auto-advance behavior
        _applyLoopingBehavior(controller);
        // Attach end listener for auto-scroll
        _attachEndListenerIfNeeded(controller, index);
        // Attach buffering listener to track mid-playback stalls
        _attachBufferingListenerIfNeeded(controller, index);

        // First-frame priming: play muted off-screen to obtain first frame, then pause
        _firstFrameReady[index] = false;
        // Fallback force-mount for top items if first frame is slow
        if (index <= 1) {
          _forceMountPlayer[index] = false;
          Future.delayed(const Duration(milliseconds: 700), () {
            if (mounted && _firstFrameReady[index] != true) {
              _forceMountPlayer[index] = true;
              setState(() {});
            }
          });
        }
        // Prime only within decoder budget (current + next), and only when visible
        final bool shouldPrime = _canPrimeIndex(index);
        if (shouldPrime) {
          try {
            await controller?.setVolume(0.0);
            // Tiny seek helps codecs surface a real frame
            await controller?.seekTo(const Duration(milliseconds: 1));
            await controller?.play();
          } catch (_) {}
        }

        // Listen until first frame appears, then pause and mark ready
        void markReadyIfNeeded() async {
          if (_firstFrameReady[index] == true) return;
          final v = controller!.value;
          if (v.isInitialized && v.position > Duration.zero && !v.isBuffering) {
            _firstFrameReady[index] = true;
            try {
              await controller?.pause();
              await controller?.setVolume(1.0);
            } catch (_) {}
            if (mounted) setState(() {});

            // If this is the active cell and visible, start playback now
            if (index == _currentIndex) {
              final mainController =
                  Provider.of<MainController>(context, listen: false);
              if (mainController.currentIndex == 0 && _isScreenVisible) {
                try {
                  await controller?.play();
                  _controllerStates[_currentIndex] = true;
                  _userPaused[_currentIndex] = false;
                } catch (_) {}
              }
            }
          }
        }

        controller.addListener(markReadyIfNeeded);

        // **NEW: Start view tracking if this is the current video**
        if (index == _currentIndex && index < _videos.length) {
          _viewTracker.startViewTracking(video.id,
              videoUploaderId: video.uploader.id);
          AppLogger.log(
            '▶️ Started view tracking for preloaded current video: ${video.id}',
          );

          // **CRITICAL FIX: If reused controller for current video, start playing immediately**
          final bool openedFromProfile =
              widget.initialVideos != null && widget.initialVideos!.isNotEmpty;
          if (isReused &&
              controller.value.isInitialized &&
              !controller.value.isPlaying) {
            if (openedFromProfile) {
              controller.play();
              _controllerStates[index] = true;
              _userPaused[index] = false;
              AppLogger.log(
                  '✅ Started playback for reused controller (from Profile)');
            } else {
              final mainController =
                  Provider.of<MainController>(context, listen: false);
              if (mainController.currentIndex == 0 && _isScreenVisible) {
                controller.play();
                _controllerStates[index] = true;
                _userPaused[index] = false;
                AppLogger.log(
                    '✅ Started playback for reused controller at current index');
              }
            }
          }

          // **NEW: Resume video if it was playing before navigation (better UX)**
          if (_wasPlayingBeforeNavigation[index] == true &&
              controller.value.isInitialized &&
              !controller.value.isPlaying) {
            if (openedFromProfile) {
              controller.play();
              _controllerStates[index] = true;
              _userPaused[index] = false;
              _wasPlayingBeforeNavigation[index] = false; // Clear the flag
              AppLogger.log(
                  '▶️ Resumed video ${video.id} that was playing before navigation (from Profile)');
            } else {
              final mainController =
                  Provider.of<MainController>(context, listen: false);
              if (mainController.currentIndex == 0 && _isScreenVisible) {
                controller.play();
                _controllerStates[index] = true;
                _userPaused[index] = false;
                _wasPlayingBeforeNavigation[index] = false; // Clear the flag
                AppLogger.log(
                    '▶️ Resumed video ${video.id} that was playing before navigation');
              }
            }
          }
        }

        AppLogger.log('✅ Successfully preloaded video $index');

        // **CACHE STATUS UPDATE AFTER SUCCESSFUL PRELOAD**
        _preloadHits++;
        AppLogger.log('📊 Cache Status Update:');
        AppLogger.log('   Preload Hits: $_preloadHits');
        AppLogger.log('   Total Controllers: ${_controllerPool.length}');
        AppLogger.log('   Preloaded Videos: ${_preloadedVideos.length}');

        // Trigger UI update so isInitialized switch reflects immediately
        if (mounted) {
          setState(() {});
        }
        // Clean up old controllers to prevent memory leaks
        _cleanupOldControllers();
      } else {
        // **CRITICAL: Only dispose if not reused from shared pool**
        if (!isReused) {
          controller.dispose();
        }
      }
    } catch (e) {
      AppLogger.log('❌ Error preloading video $index: $e');
      _loadingVideos.remove(index);
      _initializingVideos.remove(index);

      // **NEW: Always dispose failed controllers to free decoder resources**
      if (controller != null && !isReused) {
        try {
          if (controller.value.isInitialized) {
            await controller.pause();
          }
          controller.dispose();
          AppLogger.log('🗑️ Disposed failed controller for video $index');
        } catch (disposeError) {
          AppLogger.log('⚠️ Error disposing failed controller: $disposeError');
        }
      }

      // **NEW: Detect NO_MEMORY errors specifically**
      final errorString = e.toString().toLowerCase();
      final isNoMemoryError = errorString.contains('no_memory') ||
          errorString.contains('0xfffffff4') ||
          errorString.contains('error 12') ||
          (errorString.contains('failed to initialize') &&
              errorString.contains('no_memory')) ||
          (errorString.contains('mediacodec') &&
              errorString.contains('memory')) ||
          (errorString.contains('videoplayer') &&
              errorString.contains('exoplaybackexception') &&
              errorString.contains('mediacodec'));

      // **NEW: Check retry count**
      final retryCount = _preloadRetryCount[index] ?? 0;

      if (isNoMemoryError) {
        AppLogger.log('⚠️ NO_MEMORY error detected for video $index');

        // **NEW: Clean up old controllers first when out of memory**
        _cleanupOldControllers();

        // **NEW: Wait longer and reduce concurrent load for NO_MEMORY errors**
        if (retryCount < _maxRetryAttempts) {
          _preloadRetryCount[index] = retryCount + 1;
          final retryDelay =
              Duration(seconds: 10 + (retryCount * 5)); // Exponential backoff
          AppLogger.log(
              '🔄 Retrying video $index after ${retryDelay.inSeconds} seconds (attempt ${retryCount + 1}/$_maxRetryAttempts)...');
          Future.delayed(retryDelay, () {
            if (mounted && !_preloadedVideos.contains(index)) {
              _preloadVideo(index);
            }
          });
        } else {
          AppLogger.log(
              '❌ Max retry attempts reached for video $index (NO_MEMORY)');
          _preloadRetryCount.remove(index);
        }
      } else if (videoUrl != null && videoUrl.contains('.m3u8')) {
        // **HLS SUPPORT: Enhanced retry logic for HLS videos**
        if (retryCount < _maxRetryAttempts) {
          _preloadRetryCount[index] = retryCount + 1;
          AppLogger.log('🔄 HLS video failed, retrying in 3 seconds...');
          AppLogger.log('🔄 HLS Error details: $e');
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted && !_preloadedVideos.contains(index)) {
              _preloadVideo(index);
            }
          });
        } else {
          AppLogger.log('❌ Max retry attempts reached for HLS video $index');
          _preloadRetryCount.remove(index);
        }
      } else if (e.toString().contains('400') || e.toString().contains('404')) {
        if (retryCount < _maxRetryAttempts) {
          _preloadRetryCount[index] = retryCount + 1;
          AppLogger.log('🔄 Retrying video $index in 5 seconds...');
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted && !_preloadedVideos.contains(index)) {
              _preloadVideo(index);
            }
          });
        } else {
          AppLogger.log('❌ Max retry attempts reached for video $index');
          _preloadRetryCount.remove(index);
        }
      } else {
        AppLogger.log('❌ Video preload failed with error: $e');
        AppLogger.log('❌ Video URL: $videoUrl');
        AppLogger.log('❌ Video index: $index');
        _preloadRetryCount.remove(index);
      }
    }
  }

  /// **VALIDATE AND FIX VIDEO URL**
  String? _validateAndFixVideoUrl(String url) {
    if (url.isEmpty) return null;

    // **FIXED: Handle relative URLs and ensure proper base URL**
    if (!url.startsWith('http')) {
      // Remove leading slash if present to avoid double slash
      String cleanUrl = url;
      if (cleanUrl.startsWith('/')) {
        cleanUrl = cleanUrl.substring(1);
      }
      return '${VideoService.baseUrl}/$cleanUrl';
    }

    // **FIXED: Validate URL format**
    try {
      final uri = Uri.parse(url);
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        return url;
      }
    } catch (e) {
      AppLogger.log('❌ Invalid URL format: $url');
    }

    return null;
  }

  /// **RESOLVE PLAYABLE URL:** Prefer HLS, handle web-share page URLs
  Future<String?> _resolvePlayableUrl(VideoModel video) async {
    try {
      // 1) Prefer HLS fields if available in model
      final hlsUrl = video.hlsPlaylistUrl?.isNotEmpty == true
          ? video.hlsPlaylistUrl
          : video.hlsMasterPlaylistUrl;
      if (hlsUrl != null && hlsUrl.isNotEmpty) {
        return _validateAndFixVideoUrl(hlsUrl);
      }

      // 2) If video.videoUrl is already HLS/progressive direct URL
      if (video.videoUrl.contains('.m3u8') || video.videoUrl.contains('.mp4')) {
        return _validateAndFixVideoUrl(video.videoUrl);
      }

      // 3) If it's an app/web route like snehayog.app/video/<id>, fetch the API to get real URLs
      final uri = Uri.tryParse(video.videoUrl);
      if (uri != null &&
          uri.host.contains('snehayog.site') &&
          uri.pathSegments.isNotEmpty &&
          uri.pathSegments.first == 'video') {
        try {
          final details = await VideoService().getVideoById(video.id);
          final candidate = details.hlsPlaylistUrl?.isNotEmpty == true
              ? details.hlsPlaylistUrl
              : details.videoUrl;
          if (candidate != null && candidate.isNotEmpty) {
            return _validateAndFixVideoUrl(candidate);
          }
        } catch (_) {}
      }

      // 4) Fallback to original with baseUrl fix
      return _validateAndFixVideoUrl(video.videoUrl);
    } catch (_) {
      return _validateAndFixVideoUrl(video.videoUrl);
    }
  }

  void _cleanupOldControllers() {
    final sharedPool = SharedVideoControllerPool();

    // **UNIFIED STRATEGY: Let shared pool handle cleanup based on distance**
    sharedPool.cleanupDistantControllers(_currentIndex, keepRange: 3);

    // **LOCAL CLEANUP: Only remove local tracking for controllers not in shared pool**
    final controllersToRemove = <int>[];

    for (final index in _controllerPool.keys.toList()) {
      // Keep controllers that are in shared pool (they're managed there)
      if (index < _videos.length) {
        final videoId = _videos[index].id;
        if (sharedPool.isVideoLoaded(videoId)) {
          // Controller is in shared pool, just remove from local tracking
          controllersToRemove.add(index);
          continue;
        }
      }

      // Remove local tracking for distant or invalid controllers
      final distance = (index - _currentIndex).abs();
      if (distance > 3 || _controllerPool.length > 5) {
        controllersToRemove.add(index);
      }
    }

    // **CLEANUP: Remove only local tracking (controllers are in shared pool)**
    for (final index in controllersToRemove) {
      final ctrl = _controllerPool[index];

      // **CRITICAL: Only dispose if NOT in shared pool**
      if (index < _videos.length) {
        final videoId = _videos[index].id;
        if (!sharedPool.isVideoLoaded(videoId) && ctrl != null) {
          // Controller not in shared pool, dispose it
          try {
            ctrl.removeListener(_bufferingListeners[index] ?? () {});
            ctrl.removeListener(_videoEndListeners[index] ?? () {});
            ctrl.dispose();
          } catch (e) {
            AppLogger.log('⚠️ Error disposing controller at index $index: $e');
          }
        }
      }

      // Remove local tracking
      _controllerPool.remove(index);
      _controllerStates.remove(index);
      _preloadedVideos.remove(index);
      _isBuffering.remove(index);
      _bufferingListeners.remove(index);
      _videoEndListeners.remove(index);
      _lastAccessedLocal.remove(index);
      _initializingVideos.remove(index);
      _preloadRetryCount.remove(index);
    }

    if (controllersToRemove.isNotEmpty) {
      AppLogger.log(
          '🧹 Cleaned up ${controllersToRemove.length} local controller trackings');
    }
  }

  /// **GET OR CREATE CONTROLLER: Unified shared pool strategy**
  VideoPlayerController? _getController(int index) {
    if (index >= _videos.length) return null;

    final video = _videos[index];
    final sharedPool = SharedVideoControllerPool();

    // **PRIMARY: Check shared pool first (guaranteed instant playback)**
    VideoPlayerController? controller =
        sharedPool.getControllerForInstantPlay(video.id);

    if (controller != null && controller.value.isInitialized) {
      // **CACHE HIT: Reuse from shared pool**
      AppLogger.log(
          '⚡ INSTANT: Reusing controller from shared pool for video ${video.id}');

      // Add to local pool for UI tracking only
      _controllerPool[index] = controller;
      _controllerStates[index] = false;
      _preloadedVideos.add(index);
      _lastAccessedLocal[index] = DateTime.now();

      return controller;
    }

    // **FALLBACK: Check local pool**
    if (_controllerPool.containsKey(index)) {
      controller = _controllerPool[index];
      if (controller != null && controller.value.isInitialized) {
        _lastAccessedLocal[index] = DateTime.now();
        return controller;
      }
    }

    // **PRELOAD: If not in any pool, preload it**
    _preloadVideo(index);
    return null;
  }

  /// **HANDLE PAGE CHANGES**
  void _onPageChanged(int index) {
    if (index == _currentIndex) return;

    // **LRU: Track access time for previous index**
    _lastAccessedLocal[_currentIndex] = DateTime.now();

    // **NEW: Stop view tracking for previous video**
    if (_currentIndex < _videos.length) {
      final previousVideo = _videos[_currentIndex];
      _viewTracker.stopViewTracking(previousVideo.id);
      AppLogger.log(
          '⏸️ Stopped view tracking for previous video: ${previousVideo.id}');
    }

    // Pause previous video
    if (_controllerPool.containsKey(_currentIndex)) {
      _controllerPool[_currentIndex]?.pause();
      _controllerStates[_currentIndex] = false;
    }

    _currentIndex = index;
    _reprimeWindowIfNeeded();

    // **UNIFIED STRATEGY: Use shared pool as primary source (Instant playback)**
    final sharedPool = SharedVideoControllerPool();
    VideoPlayerController? controllerToUse;

    if (index < _videos.length) {
      final video = _videos[index];

      // **INSTANT LOADING: Try to get controller with instant playback guarantee**
      controllerToUse = sharedPool.getControllerForInstantPlay(video.id);

      if (controllerToUse != null && controllerToUse.value.isInitialized) {
        AppLogger.log(
            '⚡ INSTANT: Reusing controller from shared pool for video ${video.id}');

        // Add to local pool for tracking only
        _controllerPool[index] = controllerToUse;
        _controllerStates[index] = false;
        _preloadedVideos.add(index);
        _lastAccessedLocal[index] = DateTime.now();

        // **MEMORY MANAGEMENT: Cleanup distant controllers**
        sharedPool.cleanupDistantControllers(index, keepRange: 3);
      } else if (sharedPool.isVideoLoaded(video.id)) {
        // Fallback: Get any available controller
        controllerToUse = sharedPool.getController(video.id);
        if (controllerToUse != null) {
          _controllerPool[index] = controllerToUse;
          _controllerStates[index] = false;
          _preloadedVideos.add(index);
          _lastAccessedLocal[index] = DateTime.now();
        }
      }
    }

    // **FALLBACK: Check local pool only if shared pool doesn't have it**
    if (controllerToUse == null && _controllerPool.containsKey(index)) {
      controllerToUse = _controllerPool[index];
      if (controllerToUse != null && !controllerToUse.value.isInitialized) {
        // **AUTO-CLEANUP: Remove invalid controllers**
        AppLogger.log('⚠️ Controller exists but not initialized, disposing...');
        try {
          controllerToUse.dispose();
        } catch (e) {
          AppLogger.log('Error disposing controller: $e');
        }
        _controllerPool.remove(index);
        _controllerStates.remove(index);
        _preloadedVideos.remove(index);
        _lastAccessedLocal.remove(index);
        controllerToUse = null;
      } else if (controllerToUse != null) {
        _lastAccessedLocal[index] = DateTime.now();
      }
    }

    // **FIXED: Play current video if we have a valid controller**
    if (controllerToUse != null && controllerToUse.value.isInitialized) {
      // Controller is ready, play immediately
      controllerToUse.play();
      _controllerStates[index] = true;
      _userPaused[index] = false;
      _applyLoopingBehavior(controllerToUse);
      _attachEndListenerIfNeeded(controllerToUse, index);
      _attachBufferingListenerIfNeeded(controllerToUse, index);

      // **NEW: Start view tracking for current video**
      if (index < _videos.length) {
        final currentVideo = _videos[index];
        _viewTracker.startViewTracking(currentVideo.id,
            videoUploaderId: currentVideo.uploader.id);
        AppLogger.log(
            '▶️ Started view tracking for current video: ${currentVideo.id}');
      }

      // Preload nearby videos for smooth scrolling
      _preloadNearbyVideos();
      return; // Exit early - video is ready!
    }

    // **FIX: If still no controller, preload and mark as loading immediately**
    if (!_controllerPool.containsKey(index)) {
      AppLogger.log(
          '🔄 Video not preloaded, preloading and will autoplay when ready');
      // Mark as loading immediately so UI shows thumbnail/loading instead of grey
      if (mounted) {
        setState(() {
          // This triggers UI rebuild to show loading state
        });
      }
      _preloadVideo(index).then((_) {
        // After preloading, check if this is still the current video
        if (mounted &&
            _currentIndex == index &&
            _controllerPool.containsKey(index)) {
          final loadedController = _controllerPool[index];
          if (loadedController != null &&
              loadedController.value.isInitialized) {
            // **LRU: Track access time**
            _lastAccessedLocal[index] = DateTime.now();

            loadedController.play();
            _controllerStates[index] = true;
            _userPaused[index] = false;
            _applyLoopingBehavior(loadedController);
            _attachEndListenerIfNeeded(loadedController, index);
            _attachBufferingListenerIfNeeded(loadedController, index);

            // **NEW: Start view tracking for current video**
            if (index < _videos.length) {
              final currentVideo = _videos[index];
              _viewTracker.startViewTracking(currentVideo.id,
                  videoUploaderId: currentVideo.uploader.id);
              AppLogger.log(
                  '▶️ Started view tracking for current video: ${currentVideo.id}');
            }

            AppLogger.log('✅ Video autoplay started after preloading');
          }
        }
      });
    }

    _preloadNearbyVideos();
  }

  Widget _buildVideoFeed() {
    return RefreshIndicator(
      onRefresh: refreshVideos,
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        onPageChanged: _onPageChanged,
        itemCount: _getTotalItemCount(),
        itemBuilder: (context, index) {
          return _buildFeedItem(index);
        },
      ),
    );
  }

  /// **BUILD ERROR STATE: Show error with retry button**
  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.red),
          const SizedBox(height: 16),
          const Text(
            'Failed to load videos',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _getUserFriendlyErrorMessage(_errorMessage!),
                style: const TextStyle(color: Colors.white54, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
          ],
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: refreshVideos,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _testApiConnection,
            icon: const Icon(Icons.wifi_find),
            label: const Text('Test Connection'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// **BUILD EMPTY STATE: Show when no videos are available**
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.video_library_outlined,
            size: 64,
            color: Colors.white54,
          ),
          const SizedBox(height: 16),
          const Text(
            'No videos available',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Try refreshing or check back later',
            style: TextStyle(color: Colors.white54, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: refreshVideos,
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  /// **NEW: Get total item count including videos and ads**
  int _getTotalItemCount() {
    return _videos.length + (_isLoadingMore ? 1 : 0);
  }

  /// **NEW: Build feed item (video or ad)**
  Widget _buildFeedItem(int index) {
    final totalVideos = _videos.length;
    final videoIndex = index;

    // Show loading indicator at the end
    if (videoIndex >= totalVideos) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.video_library_outlined,
                size: 64,
                color: Colors.white54,
              ),
              SizedBox(height: 16),
              Text(
                'No more videos',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'You\'ve reached the end!',
                style: TextStyle(color: Colors.white54, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    // Show regular video
    final video = _videos[videoIndex];
    final controller = _getController(videoIndex);
    final isActive = videoIndex == _currentIndex;

    return _buildVideoItem(video, controller, isActive, videoIndex);
  }

  /// **BUILD SINGLE VIDEO ITEM: Video with horizontal carousel navigation**
  Widget _buildVideoItem(
    VideoModel video,
    VideoPlayerController? controller,
    bool isActive,
    int index,
  ) {
    // Initialize horizontal page notifier for this index if not exists
    if (!_currentHorizontalPage.containsKey(index)) {
      _currentHorizontalPage[index] = ValueNotifier<int>(0);
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Stack(
        children: [
          // **Show only current page - optimized with ValueListenableBuilder**
          ValueListenableBuilder<int>(
            valueListenable: _currentHorizontalPage[index]!,
            builder: (context, currentPage, child) {
              return IndexedStack(
                index: currentPage,
                children: [
                  // Page 0: Video
                  _buildVideoPage(video, controller, isActive, index),

                  // Page 1: Carousel Ad (if available)
                  if (_carouselAds.isNotEmpty)
                    _buildCarouselAdPage(index)
                  else
                    Container(), // Empty container if no ads
                ],
              );
            },
          ),

          // Loading indicator
          if (_loadingVideos.contains(index))
            Center(child: _buildGreenSpinner(size: 28)),
        ],
      ),
    );
  }

  Widget _buildVideoPage(
    VideoModel video,
    VideoPlayerController? controller,
    bool isActive,
    int index,
  ) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Stack(
        children: [
          // Always keep thumbnail underneath to avoid grey texture
          Positioned.fill(child: _buildVideoThumbnail(video)),

          // Mount VideoPlayer after first frame ready, or force-mount for top items fallback
          if (controller != null &&
              controller.value.isInitialized &&
              (_firstFrameReady[index] == true ||
                  (_forceMountPlayer[index] == true)))
            Positioned.fill(
              child: _buildVideoPlayer(controller, isActive, index),
            ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _togglePlayPause(index),
              onDoubleTap: () => _handleDoubleTapLike(video, index),
              // **REMOVED: Horizontal drag navigation - now handled by PageView**
              child: const SizedBox.expand(),
            ),
          ),

          // **FIX: Banner ad OUTSIDE AnimatedBuilder - prevents rebuild on video frame updates**
          // This prevents grey overlay when video ends/loops (AnimatedBuilder rebuilds frequently)
          _buildBannerAd(video, index),

          // Center play indicator (only when user paused)
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity: _userPaused[index] == true ? 1.0 : 0.0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.play_arrow,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Buffering indicator during playback (mid-stream stalls)
          Positioned.fill(
            child: IgnorePointer(
              child: Opacity(
                opacity:
                    (_isBuffering[index] == true && _userPaused[index] != true)
                        ? 1.0
                        : 0.0,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
          ),

          // Bottom progress bar (fixed at very bottom)
          if (controller != null && controller.value.isInitialized)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _buildVideoProgressBar(controller),
            ),

          // Video info overlay
          _buildVideoOverlay(video, index),

          // Quality indicator removed per requirement

          // Report indicator on side (keeps original styling)
          _buildReportIndicator(index),

          // Heart animation for double tap like
          if (_showHeartAnimation[index] == true) _buildHeartAnimation(index),
        ],
      ),
    );
  }

  /// **BUILD HEART ANIMATION: Animated heart for double tap like**
  Widget _buildHeartAnimation(int index) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: AnimatedOpacity(
            opacity: _showHeartAnimation[index] == true ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 200),
            child: AnimatedScale(
              scale: _showHeartAnimation[index] == true ? 1.2 : 0.8,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.favorite, color: Colors.red, size: 48),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// **BUILD REPORT INDICATOR: Same styling as old swipe, tap to report**
  Widget _buildReportIndicator(int index) {
    final String videoId =
        (index >= 0 && index < _videos.length) ? _videos[index].id : '';
    return Positioned(
      right: 16,
      top: MediaQuery.of(context).size.height * 0.5 - 20,
      child: AnimatedOpacity(
        opacity: 0.7,
        duration: const Duration(milliseconds: 300),
        child: GestureDetector(
          onTap: () => _openReportDialog(videoId),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Report',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_ios, color: Colors.white, size: 12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// **CRITICAL FIX: Build banner ad separately to prevent rebuilds from AnimatedBuilder**
  /// **SIMPLIFIED: Only use fallback ads - no targeted ads to prevent grey overlay**
  Widget _buildBannerAd(VideoModel video, int index) {
    Map<String, dynamic>? adData;

    // **CRITICAL FIX: Check locked ad first - prevents switching/disappearance**
    // Once an ad is shown, it's locked and won't change (prevents grey overlay)
    if (_lockedBannerAdByVideoId.containsKey(video.id)) {
      adData = _lockedBannerAdByVideoId[video.id];
      if (adData != null) {
        AppLogger.log(
          '🔒 Using locked ad for video ${video.videoName}: ${adData['title']} (preventing grey overlay)',
        );
      }
    } else if (_adsLoaded && _bannerAds.isNotEmpty) {
      // **SIMPLE: Only use fallback ads - no targeted ads complexity**
      final adIndex = (video.id.hashCode.abs()) % _bannerAds.length;
      adData = _bannerAds[adIndex];
      AppLogger.log(
        '🔄 Showing fallback ad for video ${video.videoName}: ${adData['title']}',
      );
      // Lock this ad so it doesn't switch
      _lockedBannerAdByVideoId[video.id] = adData;
    } else {
      // **CRITICAL: No ads available - show placeholder to prevent grey overlay**
      // This prevents Stack recomposition grey overlay during video initialization
      return Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: 60,
        child: Container(color: Colors.black), // Temporary placeholder
      );
    }

    // **CRITICAL: Only render when we have ad data**
    if (adData == null) {
      // Show placeholder instead of empty space
      return Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: 60,
        child: Container(color: Colors.black), // Temporary placeholder
      );
    }

    // Store non-nullable reference for null safety
    final adDataNonNull = adData;

    return Positioned(
      top: 0, // Flush to top of screen
      left: 0, // No horizontal margin
      right: 0, // No horizontal margin
      child: BannerAdWidget(
        key: ValueKey(
            'banner_${video.id}'), // Stable key prevents widget recreation
        adData: adDataNonNull,
        onAdClick: () {
          AppLogger.log('🖱️ Banner ad clicked on video $index');
        },
        onAdImpression: () async {
          // Track banner ad impression for revenue calculation
          if (index < _videos.length) {
            final video = _videos[index];
            final adId = adDataNonNull['_id'] ?? adDataNonNull['id'];
            final userData = await _authService.getUserData();

            AppLogger.log('📊 Banner Ad Impression Tracking:');
            AppLogger.log('   Video ID: ${video.id}');
            AppLogger.log('   Video Name: ${video.videoName}');
            AppLogger.log('   Ad ID: $adId');
            AppLogger.log('   User ID: ${userData?['id']}');

            if (adId != null && userData != null) {
              try {
                await _adImpressionService.trackBannerAdImpression(
                  videoId: video.id,
                  adId: adId.toString(),
                  userId: userData['id'],
                );
              } catch (e) {
                AppLogger.log('❌ Error tracking banner ad impression: $e');
              }
            }
          }
        },
      ),
    );
  }

  void _openReportDialog(String videoId) {
    if (videoId.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) =>
          ReportDialogWidget(targetType: 'video', targetId: videoId),
    );
  }

  Widget _buildVideoProgressBar(VideoPlayerController controller) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        final duration = controller.value.duration;
        final position = controller.value.position;
        final totalMs = duration.inMilliseconds;
        final posMs = position.inMilliseconds;
        final progress = totalMs > 0 ? (posMs / totalMs).clamp(0.0, 1.0) : 0.0;

        return GestureDetector(
          onTapDown: (details) => _seekToPosition(controller, details),
          onPanUpdate: (details) => _seekToPosition(controller, details),
          child: Container(
            height: 4,
            color: Colors.black.withOpacity(0.2),
            child: Stack(
              children: [
                Container(
                  height: 2,
                  margin: const EdgeInsets.only(
                    top: 1,
                  ), // Center the progress bar
                  color: Colors.grey.withOpacity(0.2),
                ),
                // Progress bar filled portion
                Positioned(
                  top: 1,
                  left: 0,
                  child: Container(
                    height: 2,
                    width: MediaQuery.of(context).size.width * progress,
                    color: Colors.green[400],
                  ),
                ),
                // Seek handle (thumb)
                if (progress > 0)
                  Positioned(
                    top: 0,
                    left: (MediaQuery.of(context).size.width * progress) - 4,
                    child: Container(
                      width: 8,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.green[400],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Green spinner used across the yog tab
  Widget _buildGreenSpinner({double size = 24}) {
    return SizedBox(
      width: size,
      height: size,
      child: const CircularProgressIndicator(
        strokeWidth: 3,
        color: Colors.green,
      ),
    );
  }

  /// **SEEK TO POSITION: Handle progress bar tap/drag for seeking**
  void _seekToPosition(VideoPlayerController controller, dynamic details) {
    if (!controller.value.isInitialized) return;

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final localPosition = renderBox.globalToLocal(details.globalPosition);
    final screenWidth = MediaQuery.of(context).size.width;
    final seekPosition = (localPosition.dx / screenWidth).clamp(0.0, 1.0);

    final duration = controller.value.duration;
    final newPosition = duration * seekPosition;

    controller.seekTo(newPosition);
  }

  // Quality indicator methods removed per requirement

  void _togglePlayPause(int index) {
    final controller = _controllerPool[index];
    if (controller == null || !controller.value.isInitialized) return;

    if (_controllerStates[index] == true) {
      // Pausing video
      controller.pause();
      setState(() {
        _controllerStates[index] = false;
        _userPaused[index] = true;
      });

      // **NEW: Stop view tracking when user pauses**
      if (index < _videos.length) {
        final video = _videos[index];
        _viewTracker.stopViewTracking(video.id);
        AppLogger.log(
            '⏸️ User paused video: ${video.id}, stopped view tracking');
      }
    } else {
      // Playing video
      controller.play();
      setState(() {
        _controllerStates[index] = true;
        _userPaused[index] = false; // hide when playing
      });

      // **NEW: Start view tracking when user plays**
      if (index < _videos.length) {
        final video = _videos[index];
        _viewTracker.startViewTracking(video.id,
            videoUploaderId: video.uploader.id);
        AppLogger.log(
            '▶️ User played video: ${video.id}, started view tracking');
      }
    }
  }

  /// **BUILD CAROUSEL AD PAGE: Full-screen carousel ad within horizontal PageView**
  Widget _buildCarouselAdPage(int videoIndex) {
    if (_carouselAds.isEmpty) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: const Center(
          child: Text(
            'No carousel ads available',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    // Use the first carousel ad (you can implement rotation logic later)
    final carouselAd = _carouselAds[0];

    return CarouselAdWidget(
      carouselAd: carouselAd,
      onAdClosed: () {
        if (_currentHorizontalPage.containsKey(videoIndex)) {
          _currentHorizontalPage[videoIndex]!.value = 0;
        }
      },
      autoPlay: true,
    );
  }

  Widget _buildVideoPlayer(
    VideoPlayerController controller,
    bool isActive,
    int index,
  ) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Center(child: _buildVideoWithCorrectAspectRatio(controller)),
    );
  }

  /// **NEW: Build video with correct aspect ratio handling**
  Widget _buildVideoWithCorrectAspectRatio(VideoPlayerController controller) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;

        // **FIXED: Use aspect ratio from VideoModel instead of detecting from video metadata**
        final currentVideo = _videos[_currentIndex];
        final double modelAspectRatio = currentVideo.aspectRatio;

        // Get video dimensions for debugging
        final Size videoSize = controller.value.size;
        final int rotation = controller.value.rotationCorrection;

        AppLogger.log('🎬 MODEL aspect ratio: $modelAspectRatio');
        AppLogger.log(
            '🎬 Video dimensions: ${videoSize.width}x${videoSize.height}');
        AppLogger.log('🎬 Rotation: $rotation degrees');
        AppLogger.log('🎬 Using MODEL aspect ratio instead of detected ratio');

        // **DEBUG: Call debug method to get detailed aspect ratio info**
        _debugAspectRatio(controller);

        // **USE MODEL ASPECT RATIO: Trust the backend aspect ratio from VideoModel**
        if (modelAspectRatio < 1.0) {
          // This is a portrait video (9:16) according to model
          return _buildPortraitVideoFromModel(
            controller,
            screenWidth,
            screenHeight,
            modelAspectRatio,
          );
        } else {
          // This is a landscape video (16:9) according to model
          return _buildLandscapeVideoFromModel(
            controller,
            screenWidth,
            screenHeight,
            modelAspectRatio,
          );
        }
      },
    );
  }

  /// **NEW: Check if video is portrait based on aspect ratio**
  bool _isPortraitVideo(double aspectRatio) {
    const double portraitThreshold =
        0.7; // Anything below 0.7 is considered portrait
    return aspectRatio < portraitThreshold;
  }

  /// **NEW: Build portrait video using MODEL aspect ratio (prevent stretching)**
  Widget _buildPortraitVideoFromModel(
    VideoPlayerController controller,
    double screenWidth,
    double screenHeight,
    double modelAspectRatio,
  ) {
    // Get actual video dimensions from controller
    final Size videoSize = controller.value.size;
    final int rotation = controller.value.rotationCorrection;

    // Calculate actual video dimensions considering rotation
    double videoWidth = videoSize.width;
    double videoHeight = videoSize.height;

    if (rotation == 90 || rotation == 270) {
      videoWidth = videoSize.height;
      videoHeight = videoSize.width;
    }

    AppLogger.log(
      '🎬 MODEL Portrait video - Original video size: ${videoWidth}x$videoHeight',
    );
    AppLogger.log(
        '🎬 MODEL Portrait video - Model aspect ratio: $modelAspectRatio');
    AppLogger.log(
      '🎬 MODEL Portrait video - Screen size: ${screenWidth}x$screenHeight',
    );

    // Use FittedBox to prevent stretching while maintaining aspect ratio
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: videoWidth,
        height: videoHeight,
        child: VideoPlayer(controller),
      ),
    );
  }

  /// **NEW: Build landscape video using MODEL aspect ratio (prevent stretching)**
  Widget _buildLandscapeVideoFromModel(
    VideoPlayerController controller,
    double screenWidth,
    double screenHeight,
    double modelAspectRatio,
  ) {
    // Get actual video dimensions from controller
    final Size videoSize = controller.value.size;
    final int rotation = controller.value.rotationCorrection;

    // Calculate actual video dimensions considering rotation
    double videoWidth = videoSize.width;
    double videoHeight = videoSize.height;

    if (rotation == 90 || rotation == 270) {
      videoWidth = videoSize.height;
      videoHeight = videoSize.width;
    }

    AppLogger.log(
      '🎬 MODEL Landscape video - Original video size: ${videoWidth}x$videoHeight',
    );
    AppLogger.log(
        '🎬 MODEL Landscape video - Model aspect ratio: $modelAspectRatio');
    AppLogger.log(
      '🎬 MODEL Landscape video - Screen size: ${screenWidth}x$screenHeight',
    );

    // Use FittedBox to prevent stretching while maintaining aspect ratio
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: videoWidth,
        height: videoHeight,
        child: VideoPlayer(controller),
      ),
    );
  }

  /// **NEW: Debug method to test aspect ratio detection**
  void _debugAspectRatio(VideoPlayerController controller) {
    final Size videoSize = controller.value.size;
    final int rotation = controller.value.rotationCorrection;

    double videoWidth = videoSize.width;
    double videoHeight = videoSize.height;

    if (rotation == 90 || rotation == 270) {
      videoWidth = videoSize.height;
      videoHeight = videoSize.width;
    }

    final double aspectRatio = videoWidth / videoHeight;
    final bool isPortrait = aspectRatio < 1.0 || _isPortraitVideo(aspectRatio);

    // Get model aspect ratio
    final currentVideo = _videos[_currentIndex];
    final double modelAspectRatio = currentVideo.aspectRatio;

    AppLogger.log('🔍 ASPECT RATIO DEBUG:');
    AppLogger.log('🔍 MODEL aspect ratio: $modelAspectRatio');
    AppLogger.log('🔍 Raw size: ${videoSize.width}x${videoSize.height}');
    AppLogger.log('🔍 Rotation: $rotation degrees');
    AppLogger.log('🔍 Corrected size: ${videoWidth}x$videoHeight');
    AppLogger.log('🔍 DETECTED aspect ratio: $aspectRatio');
    AppLogger.log('🔍 Is portrait (detected): $isPortrait');
    AppLogger.log('🔍 Expected 9:16 ratio: ${9.0 / 16.0}');
    AppLogger.log(
      '🔍 Difference from 9:16 (detected): ${(aspectRatio - (9.0 / 16.0)).abs()}',
    );
    AppLogger.log(
      '🔍 Difference from 9:16 (model): ${(modelAspectRatio - (9.0 / 16.0)).abs()}',
    );
    AppLogger.log('🔍 Using MODEL aspect ratio for display');
  }

  void _attachEndListenerIfNeeded(VideoPlayerController controller, int index) {
    controller.removeListener(_videoEndListeners[index] ?? () {});
    void listener() {
      if (!_autoScrollEnabled) return;
      final position = controller.value.position;
      final duration = controller.value.duration;
      if (duration.inMilliseconds > 0 &&
          (duration - position).inMilliseconds <= 200) {
        // Near end: advance to next page
        if (_isAnimatingPage) return;
        if (_autoAdvancedForIndex.contains(index)) return;
        final int next = (_currentIndex + 1).clamp(0, _videos.length);
        if (next != _currentIndex && next < _videos.length) {
          _isAnimatingPage = true;
          _autoAdvancedForIndex.add(index);
          _pageController
              .animateToPage(
                next,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              )
              .whenComplete(() => _isAnimatingPage = false);
        }
      }
    }

    controller.addListener(listener);
    _videoEndListeners[index] = listener;
  }

  void _attachBufferingListenerIfNeeded(
    VideoPlayerController controller,
    int index,
  ) {
    controller.removeListener(_bufferingListeners[index] ?? () {});
    void listener() {
      if (!mounted) return;
      final bool next =
          controller.value.isInitialized && controller.value.isBuffering;
      final bool current = _isBuffering[index] ?? false;
      if (current != next) {
        setState(() {
          _isBuffering[index] = next;
        });
      }
    }

    controller.addListener(listener);
    _bufferingListeners[index] = listener;

    // (Removed first-frame tracking listener per revert)
  }

  final Map<int, VoidCallback> _videoEndListeners = {};

  void _applyLoopingBehavior(VideoPlayerController controller) {
    controller.setLooping(!_autoScrollEnabled);
  }

  Widget _buildVideoThumbnail(VideoModel video) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: video.thumbnailUrl.isNotEmpty
          ? Center(
              child: CachedNetworkImage(
                imageUrl: video.thumbnailUrl,
                fit: BoxFit.contain,
                placeholder: (context, url) => _buildFallbackThumbnail(),
                errorWidget: (context, url, error) => _buildFallbackThumbnail(),
                memCacheWidth: 854, // 480p width for memory efficiency
                memCacheHeight: 480, // 480p height
              ),
            )
          : _buildFallbackThumbnail(),
    );
  }

  /// **BUILD FALLBACK THUMBNAIL: When no thumbnail available**
  Widget _buildFallbackThumbnail() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_circle_outline, size: 80, color: Colors.white54),
            SizedBox(height: 16),
            Text(
              'Tap to play video',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// **Calculate earnings based on video views**
  /// Note: Since banner ads are shown on ALL videos, ad views = video views
  double _calculateEarningsFromViews(VideoModel video) {
    // Check cache first
    if (_earningsCache.containsKey(video.id)) {
      return _earningsCache[video.id]!;
    }

    try {
      // Calculate earnings based on video views
      // Banner ads: ₹10 per 1000 impressions (views)
      // Since banner ads are shown on all videos, earnings = (views / 1000) * 10
      const bannerCpm = 10.0;
      final totalEarnings = (video.views / 1000) * bannerCpm;

      // Cache the result
      _earningsCache[video.id] = totalEarnings;

      AppLogger.log(
          '💰 Video: ${video.videoName} - Views: ${video.views}, Earnings: ₹${totalEarnings.toStringAsFixed(2)}');

      return totalEarnings;
    } catch (e) {
      AppLogger.log('❌ Error calculating earnings for video ${video.id}: $e');
      return 0.0;
    }
  }

  /// **Build earnings label**
  Widget _buildEarningsLabel(VideoModel video) {
    // Calculate earnings directly from views (no async needed)
    final earnings = _calculateEarningsFromViews(video) * 0.8;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.green.withOpacity(0.6),
          width: 1,
        ),
      ),
      child: Text(
        '₹${earnings.toStringAsFixed(2)}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildProcessingIndicator(VideoModel video, int index) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 80,
              height: 80,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.green.withOpacity(0.3),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    height: 60,
                    child: CircularProgressIndicator(
                      strokeWidth: 4,
                      value: video.processingProgress / 100,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.green,
                      ),
                    ),
                  ),
                  // Center icon
                  Icon(
                    video.processingStatus == 'failed'
                        ? Icons.error_outline
                        : Icons.video_library_outlined,
                    size: 32,
                    color: video.processingStatus == 'failed'
                        ? Colors.red
                        : Colors.white54,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Text(
              _getProcessingStatusText(video.processingStatus),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 8),

            // Progress percentage
            if (video.processingStatus == 'processing')
              Text(
                '${video.processingProgress}% complete',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),

            // Error message if failed
            if (video.processingStatus == 'failed' &&
                video.processingError != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Text(
                  video.processingError!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),

            const SizedBox(height: 16),

            // Retry button for failed videos
            if (video.processingStatus == 'failed')
              ElevatedButton.icon(
                onPressed: () => _retryVideoProcessing(video.id),
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// **GET PROCESSING STATUS TEXT**
  String _getProcessingStatusText(String status) {
    switch (status) {
      case 'pending':
        return 'Video Uploaded\nProcessing will start soon...';
      case 'processing':
        return 'Processing Video\nPlease wait...';
      case 'failed':
        return 'Processing Failed\nPlease try again';
      default:
        return 'Video Processing\nPlease wait...';
    }
  }

  /// **GET USER TOKEN: Helper method for authentication**
  Future<String?> _getUserToken() async {
    try {
      final userData = await _authService.getUserData();
      return userData?['token']?.toString();
    } catch (e) {
      AppLogger.log('❌ Error getting user token: $e');
      return null;
    }
  }

  /// **RETRY VIDEO PROCESSING**
  Future<void> _retryVideoProcessing(String videoId) async {
    try {
      AppLogger.log('🔄 Retrying video processing for: $videoId');

      // Show loading state
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
              SizedBox(width: 12),
              Text('Retrying video processing...'),
            ],
          ),
          duration: Duration(seconds: 2),
        ),
      );

      // Call backend to retry processing
      final response = await http.post(
        Uri.parse(
          '${VideoService.baseUrl}/api/videos/$videoId/retry-processing',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _getUserToken()}',
        },
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Processing restarted successfully!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Refresh videos to get updated status
        await refreshVideos();
      } else {
        throw Exception('Failed to retry processing');
      }
    } catch (e) {
      AppLogger.log('❌ Error retrying video processing: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Failed to retry processing: ${e.toString()}'),
              ),
            ],
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  Widget _buildVideoOverlay(VideoModel video, int index) {
    return Stack(
      children: [
        // **NEW: Earnings label just below banner, top-right corner**
        Positioned(
          top: 62, // Added 2px margin from top
          right: 8,
          child: _buildEarningsLabel(video),
        ),

        Positioned(
          bottom: 12, // Increased spacing from progress bar
          left: 0,
          right: 80, // Leave space for vertical action buttons
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _navigateToCreatorProfile(video.uploader.id),
                  child: Row(
                    children: [
                      GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            _navigateToCreatorProfile(video.uploader.id),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundImage: video.uploader.profilePic.isNotEmpty
                              ? NetworkImage(video.uploader.profilePic)
                              : null,
                          child: video.uploader.profilePic.isEmpty
                              ? Text(
                                  video.uploader.name.isNotEmpty
                                      ? video.uploader.name[0].toUpperCase()
                                      : 'U',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: GestureDetector(
                          onTap: () =>
                              _navigateToCreatorProfile(video.uploader.id),
                          child: Text(
                            video.uploader.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Professional follow/unfollow button
                      _buildFollowTextButton(video),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Video title (moved below uploader name)
                Text(
                  video.videoName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 6),
                if (video.link?.isNotEmpty == true)
                  GestureDetector(
                    onTap: () => _handleVisitNow(video),
                    child: Container(
                      width: MediaQuery.of(context).size.width *
                          0.75, // 50% of screen width
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.open_in_new,
                            color: Colors.white,
                            size: 16,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Visit Now',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // **FIXED: Remove spacing to eliminate black empty space**
              ],
            ),
          ),
        ),

        // Vertical action buttons on the right
        Positioned(
          right: 16,
          bottom: 20, // **REDUCED: From 80 to 40**
          child: Column(
            children: [
              // Like button with count
              _buildVerticalActionButton(
                icon: _isLiked(video) ? Icons.favorite : Icons.favorite_border,
                color: _isLiked(video) ? Colors.red : Colors.white,
                count: video.likes,
                onTap: () => _handleLike(video, index),
              ),
              const SizedBox(height: 12),

              // Comment button with count
              _buildVerticalActionButton(
                icon: Icons.chat_bubble_outline,
                count: video.comments.length,
                onTap: () => _handleComment(video),
              ),
              const SizedBox(height: 12),

              // Share button
              _buildVerticalActionButton(
                icon: Icons.share,
                onTap: () => _handleShare(video),
              ),
              const SizedBox(height: 12),

              // **NEW: Carousel ad navigation - swipe indicator**
              // Always show the arrow indicator (per requirement)
              GestureDetector(
                onTap: () => _navigateToCarouselAd(index),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_forward_ios,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Swipe',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVerticalActionButton({
    required IconData icon,
    required VoidCallback onTap,
    Color color = Colors.white,
    int? count,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          if (count != null) ...[
            const SizedBox(height: 4),
            Text(
              _formatCount(count),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                shadows: [
                  Shadow(
                    offset: Offset(0, 1),
                    blurRadius: 2,
                    color: Colors.black54,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// **FORMAT COUNT: Convert numbers to K, M format**
  String _formatCount(int count) {
    if (count < 1000) {
      return count.toString();
    } else if (count < 1000000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    } else {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
  }

  /// **GET USER-FRIENDLY ERROR MESSAGE: Convert technical errors to user-friendly messages**
  String _getUserFriendlyErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('network') || errorString.contains('connection')) {
      return 'Network connection issue';
    } else if (errorString.contains('timeout')) {
      return 'Request timed out';
    } else if (errorString.contains('404')) {
      return 'Videos not found';
    } else if (errorString.contains('500')) {
      return 'Server error';
    } else if (errorString.contains('unauthorized') ||
        errorString.contains('401')) {
      return 'Authentication required';
    } else {
      return 'Unable to load videos';
    }
  }

  /// **HANDLE DOUBLE TAP LIKE: Show animation and like**
  Future<void> _handleDoubleTapLike(VideoModel video, int index) async {
    // Show heart animation
    setState(() {
      _showHeartAnimation[index] = true;
    });

    // Hide animation after 1 second
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        setState(() {
          _showHeartAnimation[index] = false;
        });
      }
    });

    // Handle the like
    await _handleLike(video, index);
  }

  /// **HANDLE LIKE: With API integration**
  Future<void> _handleLike(VideoModel video, int index) async {
    if (_currentUserId == null) {
      _showSignInPrompt();
      return;
    }

    // **FIXED: Store the original state before optimistic update**
    final wasLiked = video.likedBy.contains(_currentUserId);
    final originalLikes = video.likes;
    final originalLikedBy = List<String>.from(video.likedBy);

    try {
      // Optimistic UI update
      setState(() {
        if (wasLiked) {
          // User is currently liking, so unlike
          video.likedBy.remove(_currentUserId);
          video.likes = (video.likes - 1).clamp(0, double.infinity).toInt();
        } else {
          // User is not currently liking, so like
          video.likedBy.add(_currentUserId!);
          video.likes++;
        }
      });

      // **FIXED: Use toggle API which handles both like and unlike**
      await _videoService.toggleLike(video.id);
      AppLogger.log('✅ Successfully toggled like for video ${video.id}');
    } catch (e) {
      AppLogger.log('❌ Error handling like: $e');

      // **FIXED: Revert to original state on error**
      setState(() {
        video.likedBy.clear();
        video.likedBy.addAll(originalLikedBy);
        video.likes = originalLikes;
      });

      _showSnackBar('Failed to update like', isError: true);
    }
  }

  /// Prompt unauthenticated users to sign in with actionable UI
  void _showSignInPrompt() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Sign in required'),
          content:
              const Text('Please sign in to like videos and use this feature.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Not now'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(),
                  ),
                );
              },
              child: const Text('Sign in'),
            ),
          ],
        );
      },
    );
  }

  /// **HANDLE COMMENT: Open comment sheet**
  void _handleComment(VideoModel video) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => CommentsSheetWidget(
        video: video,
        videoService: _videoService,
        onCommentsUpdated: (updatedComments) {
          // Update video comments in the list
          setState(() {
            video.comments = updatedComments;
          });
        },
      ),
    );
  }

  /// **HANDLE SHARE: Show custom share widget with only 4 options**
  Future<void> _handleShare(VideoModel video) async {
    try {
      // Show custom share widget instead of system share
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => CustomShareWidget(video: video),
      );
    } catch (e) {
      AppLogger.log('❌ Error showing share widget: $e');
      _showSnackBar('Failed to open share options', isError: true);
    }
  }

  /// **HANDLE VISIT NOW: Open link in browser**
  Future<void> _handleVisitNow(VideoModel video) async {
    try {
      if (video.link?.isNotEmpty == true) {
        AppLogger.log('🔗 Visit Now tapped for: ${video.link}');

        // Use url_launcher to open the link
        final Uri url = Uri.parse(video.link!);

        // Check if the URL is valid
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        } else {
          _showSnackBar('Could not open link', isError: true);
        }
      }
    } catch (e) {
      AppLogger.log('❌ Error opening link: $e');
      _showSnackBar('Failed to open link', isError: true);
    }
  }

  /// **SHOW SNACKBAR: Helper method**
  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// **NAVIGATE TO CAROUSEL AD: Switch to carousel ad page (no rebuild)**
  void _navigateToCarouselAd(int index) {
    if (_carouselAds.isNotEmpty && _currentHorizontalPage.containsKey(index)) {
      _currentHorizontalPage[index]!.value =
          1; // Switch to carousel ad page - no setState needed!
      AppLogger.log('🎯 Navigated to carousel ad for video $index');
    }
  }

  /// **BUILD FOLLOW TEXT BUTTON: Professional follow/unfollow button**
  Widget _buildFollowTextButton(VideoModel video) {
    // Don't show follow button for own videos
    if (_currentUserId != null && video.uploader.id == _currentUserId) {
      return const SizedBox.shrink();
    }

    final isFollowing = _isFollowing(video.uploader.id);

    return GestureDetector(
      onTap: () => _handleFollow(video),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isFollowing ? Colors.grey[800] : Colors.blue[600],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isFollowing ? Colors.grey[600]! : Colors.blue[600]!,
            width: 1,
          ),
        ),
        child: Text(
          isFollowing ? 'Following' : 'Follow',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  /// **HANDLE FOLLOW/UNFOLLOW: With API integration**
  Future<void> _handleFollow(VideoModel video) async {
    if (_currentUserId == null) {
      // Silent return if not logged in
      return;
    }

    if (video.uploader.id == _currentUserId) {
      // Silent return for self
      return;
    }

    try {
      final isFollowing = _isFollowing(video.uploader.id);

      // Optimistic UI update
      setState(() {
        if (isFollowing) {
          _followingUsers.remove(video.uploader.id);
        } else {
          _followingUsers.add(video.uploader.id);
        }
      });

      // Call API using UserService
      final userService = UserService();
      if (isFollowing) {
        await userService.unfollowUser(video.uploader.id);
      } else {
        await userService.followUser(video.uploader.id);
      }
    } catch (e) {
      AppLogger.log('❌ Error handling follow/unfollow: $e');

      // Revert optimistic update on error
      setState(() {
        final isFollowing = _isFollowing(video.uploader.id);
        if (isFollowing) {
          _followingUsers.remove(video.uploader.id);
        } else {
          _followingUsers.add(video.uploader.id);
        }
      });

      // Silent on error per requirement
    }
  }

  /// **CHECK IF USER IS FOLLOWING**
  bool _isFollowing(String userId) {
    return _followingUsers.contains(userId);
  }

  /// **CHECK IF VIDEO IS LIKED**
  bool _isLiked(VideoModel video) {
    return _currentUserId != null && video.likedBy.contains(_currentUserId);
  }

  /// **NAVIGATE TO CREATOR PROFILE: Navigate to user profile screen**
  void _navigateToCreatorProfile(String userId) {
    if (userId.isEmpty) {
      _showSnackBar('User profile not available', isError: true);
      return;
    }

    AppLogger.log('🔗 Navigating to creator profile: $userId');

    // Navigate to profile screen
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => ProfileScreen(userId: userId)),
    ).catchError((error) {
      AppLogger.log('❌ Error navigating to profile: $error');
      _showSnackBar('Failed to open profile', isError: true);
      return null; // Return null to satisfy the return type
    });
  }

  /// **TEST API CONNECTION: Test if the API is reachable**
  Future<void> _testApiConnection() async {
    try {
      AppLogger.log('🔍 VideoFeedAdvanced: Testing API connection...');

      // Show loading state
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Text('Testing connection...'),
              ],
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Try to make a simple API call
      await _videoService.getVideos(page: 1, limit: 1);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Connection successful!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Clear error and try to refresh
        setState(() {
          _errorMessage = null;
        });
        await refreshVideos();
      }
    } catch (e) {
      AppLogger.log('❌ VideoFeedAdvanced: API connection test failed: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Connection failed: ${_getUserFriendlyErrorMessage(e)}',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    return Consumer<MainController>(
      builder: (context, mainController, child) {
        final isVideoTabActive = mainController.currentIndex == 0;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _handleVisibilityChange(isVideoTabActive);
        });

        return Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              _isLoading
                  ? Center(child: _buildGreenSpinner(size: 40))
                  : _errorMessage != null
                      ? _buildErrorState()
                      : _videos.isEmpty
                          ? _buildEmptyState()
                          : _buildVideoFeed(),
            ],
          ),
        );
      },
    );
  }

  /// **Initialize current user ID for likes and shares**
  Future<void> _initializeCurrentUserId() async {
    try {
      final userData = await _authService.getUserData();
      if (userData != null) {
        _currentUserId = userData['id'] ?? userData['googleId'];
        AppLogger.log(
          '✅ VideoFeedAdvanced: Current user ID initialized: $_currentUserId',
        );
      }
    } catch (e) {
      AppLogger.log('⚠️ VideoFeedAdvanced: Failed to initialize user ID: $e');
    }
  }

  @override
  void dispose() {
    // **CRITICAL: Unregister callbacks from MainController**
    try {
      final mainController = Provider.of<MainController>(
        context,
        listen: false,
      );
      mainController.unregisterCallbacks();
      AppLogger.log(
          '📱 VideoFeedAdvanced: Unregistered callbacks from MainController');
    } catch (e) {
      AppLogger.log('⚠️ VideoFeedAdvanced: Error unregistering callbacks: $e');
    }

    // **NEW: Clean up views service**
    _viewTracker.dispose();
    AppLogger.log('🎯 VideoFeedAdvanced: Disposed ViewsService');

    // **NEW: Clean up background profile preloader**
    _profilePreloader.dispose();
    AppLogger.log('🚀 VideoFeedAdvanced: Disposed BackgroundProfilePreloader');

    final sharedPool = SharedVideoControllerPool();
    int savedControllers = 0;

    _controllerPool.forEach((index, controller) {
      if (index < _videos.length) {
        final video = _videos[index];
        try {
          // **NEW: Track if video was playing before navigation**
          final wasPlaying = _controllerStates[index] == true &&
              !(_userPaused[index] ?? false);
          _wasPlayingBeforeNavigation[index] = wasPlaying;
          AppLogger.log(
              '💾 VideoFeedAdvanced: Video ${video.id} was ${wasPlaying ? "playing" : "paused"} before navigation');

          // **NEW: Pause video if it was playing (user didn't pause it)**
          if (wasPlaying &&
              controller.value.isInitialized &&
              controller.value.isPlaying) {
            controller.pause();
            _controllerStates[index] = false;
            AppLogger.log(
                '⏸️ VideoFeedAdvanced: Paused video ${video.id} before saving to shared pool');
          }

          // Remove listeners to avoid memory leaks
          controller.removeListener(_bufferingListeners[index] ?? () {});
          controller.removeListener(_videoEndListeners[index] ?? () {});

          // **CRITICAL FIX: Use skipDisposeOld=true to prevent disposing the controller we're trying to save**
          sharedPool.addController(video.id, controller, skipDisposeOld: true);
          savedControllers++;
          AppLogger.log(
            '💾 VideoFeedAdvanced: Saved controller for video ${video.id} to shared pool',
          );
        } catch (e) {
          AppLogger.log('⚠️ Error saving controller for video ${video.id}: $e');
          controller.dispose();
        }
      } else {
        // Dispose orphaned controllers (no corresponding video)
        controller.dispose();
      }
    });

    AppLogger.log(
      '💾 VideoFeedAdvanced: Saved $savedControllers controllers to shared pool',
    );

    // **MEMORY MANAGEMENT: Keep only recent controllers in shared pool**
    if (savedControllers > 2) {
      AppLogger.log(
        '🧹 VideoFeedAdvanced: Triggering memory management (keeping only 2 controllers)',
      );
      sharedPool.disposeControllersForMemoryManagement();
    }

    // Clear local pools but controllers remain in shared pool for reuse
    _controllerPool.clear();
    _controllerStates.clear();
    _isBuffering.clear();
    _bufferingListeners.clear();
    _videoEndListeners.clear();
    _wasPlayingBeforeNavigation.clear();
    _loadingVideos.clear();
    _initializingVideos.clear();
    _preloadRetryCount.clear();
    _preloadedVideos.clear();

    // **NEW: Dispose VideoControllerManager**
    _videoControllerManager.dispose();
    AppLogger.log('🗑️ VideoFeedAdvanced: Disposed VideoControllerManager');

    // Dispose page controller
    _pageController.dispose();

    // Cancel timers
    _preloadTimer?.cancel();

    // **NEW: Cancel ad refresh subscription**
    _adRefreshSubscription?.cancel();

    // Remove observer
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  /// **PRINT CACHE STATUS: Real-time cache information**
  void _printCacheStatus() {
    if (_totalRequests > 0) {
      final hitRate = (_cacheHits / _totalRequests * 100).toStringAsFixed(2);
      AppLogger.log('   Hit Rate: $hitRate%');
    }
  }

  /// **GET DETAILED CACHE INFO: Comprehensive cache information**
  Map<String, dynamic> _getDetailedCacheInfo() {
    final cacheStats = _cacheManager.getStats();

    return {
      'videoControllerPool': {
        'totalControllers': _controllerPool.length,
        'controllerKeys': _controllerPool.keys.toList(),
        'controllerStates': _controllerStates,
        'preloadedVideos': _preloadedVideos.toList(),
        'loadingVideos': _loadingVideos.toList(),
      },
      'cacheStatistics': {
        'cacheHits': _cacheHits,
        'cacheMisses': _cacheMisses,
        'preloadHits': _preloadHits,
        'totalRequests': _totalRequests,
        'hitRate': _totalRequests > 0
            ? (_cacheHits / _totalRequests * 100).toStringAsFixed(2)
            : '0.00',
      },
      'smartCacheManager': cacheStats,
      'videoLoadingStatus': {
        'currentIndex': _currentIndex,
        'totalVideos': _videos.length,
        'maxPoolSize': _maxPoolSize,
        'isLoading': _isLoading,
        'isScreenVisible': _isScreenVisible,
      },
      'memoryUsage': {
        'controllerPoolSize': _controllerPool.length,
        'preloadedVideosCount': _preloadedVideos.length,
        'loadingVideosCount': _loadingVideos.length,
      },
    };
  }

  /// **PRINT DETAILED CACHE INFO: For debugging purposes**
  void _printDetailedCacheInfo() {
    final info = _getDetailedCacheInfo();

    final poolInfo = info['videoControllerPool'] as Map<String, dynamic>;
    poolInfo.forEach((key, value) {
      AppLogger.log('   $key: $value');
    });

    AppLogger.log('📈 Cache Statistics:');
    final statsInfo = info['cacheStatistics'] as Map<String, dynamic>;
    statsInfo.forEach((key, value) {
      AppLogger.log('   $key: $value');
    });

    AppLogger.log('🧠 Smart Cache Manager:');
    final smartCacheInfo = info['smartCacheManager'] as Map<String, dynamic>;
    smartCacheInfo.forEach((key, value) {
      AppLogger.log('   $key: $value');
    });

    AppLogger.log('🎥 Video Loading Status:');
    final loadingInfo = info['videoLoadingStatus'] as Map<String, dynamic>;
    loadingInfo.forEach((key, value) {
      AppLogger.log('   $key: $value');
    });

    AppLogger.log('💾 Memory Usage:');
    final memoryInfo = info['memoryUsage'] as Map<String, dynamic>;
    memoryInfo.forEach((key, value) {
      AppLogger.log('   $key: $value');
    });

    AppLogger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }

  /// **MANUAL CACHE STATUS CHECK: Call this method to check cache status**
  void checkCacheStatus() {
    AppLogger.log('🔍 Manual Cache Status Check Triggered');
    _printDetailedCacheInfo();
  }

  /// **GET CACHE SUMMARY: Quick cache overview**
  Map<String, dynamic> getCacheSummary() {
    return {
      'totalVideos': _videos.length,
      'preloadedVideos': _preloadedVideos.length,
      'loadingVideos': _loadingVideos.length,
      'controllerPoolSize': _controllerPool.length,
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'hitRate': _totalRequests > 0
          ? (_cacheHits / _totalRequests * 100).toStringAsFixed(2)
          : '0.00',
      'currentIndex': _currentIndex,
      'isLoading': _isLoading,
    };
  }
}
