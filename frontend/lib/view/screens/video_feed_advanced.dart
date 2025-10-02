import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/model/carousel_ad_model.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/services/user_service.dart';
import 'package:snehayog/core/managers/carousel_ad_manager.dart';
import 'package:snehayog/view/widget/comments_sheet_widget.dart';
import 'package:snehayog/services/active_ads_service.dart';
import 'package:snehayog/services/video_view_tracker.dart';
import 'package:snehayog/services/ad_refresh_notifier.dart';
import 'package:snehayog/services/realtime_ad_service.dart';
import 'package:snehayog/view/widget/ads/banner_ad_widget.dart';
import 'package:snehayog/view/widget/ads/video_feed_ad_widget.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:snehayog/core/services/auto_scroll_settings.dart';
import 'package:snehayog/controller/main_controller.dart';
import 'package:snehayog/core/managers/video_controller_manager.dart';

class VideoFeedAdvanced extends StatefulWidget {
  final int? initialIndex;
  final List<VideoModel>? initialVideos;
  final String? initialVideoId;
  final String? videoType; // **NEW: Add videoType parameter**

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

  // **SERVICES**
  late VideoService _videoService;
  late AuthService _authService;
  late CarouselAdManager _carouselAdManager;
  final VideoControllerManager _videoControllerManager =
      VideoControllerManager();
  final ActiveAdsService _activeAdsService = ActiveAdsService();
  final VideoViewTracker _viewTracker = VideoViewTracker();
  final AdRefreshNotifier _adRefreshNotifier = AdRefreshNotifier();
  final RealtimeAdService _realtimeAdService = RealtimeAdService();
  StreamSubscription? _adRefreshSubscription;
  StreamSubscription? _realtimeAdSubscription;
  Timer? _adPollingTimer;

  // **AD STATE**
  List<Map<String, dynamic>> _bannerAds = [];
  List<Map<String, dynamic>> _videoFeedAds = [];
  bool _adsLoaded = false;

  // **PAGE CONTROLLER**
  late PageController _pageController;
  bool _autoScrollEnabled = true;
  bool _isAnimatingPage = false;
  final Set<int> _autoAdvancedForIndex = {};

  final Map<int, VideoPlayerController> _controllerPool = {};
  final Map<int, bool> _controllerStates = {}; // Track if controller is active
  final int _maxPoolSize = 3;
  final Map<int, bool> _userPaused = {};
  final Map<int, bool> _isBuffering = {};
  final Map<int, VoidCallback> _bufferingListeners = {};

  // **PRELOADING STATE**
  final Set<int> _preloadedVideos = {};
  final Set<int> _loadingVideos = {};
  Timer? _preloadTimer;

  // **INFINITE SCROLLING**
  static const int _infiniteScrollThreshold =
      5; // Load more when 5 videos from end
  bool _isLoadingMore = false;
  int _currentPage = 1;
  static const int _videosPerPage = 10;

  // **CAROUSEL AD STATE**
  final Map<int, int> _horizontalIndices =
      {}; // Track horizontal page for each video (0=video, 1=ad)
  final Map<int, int> _currentCarouselSlideIndex =
      {}; // Track current slide index for each carousel

  bool _isScreenVisible = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Ensure autoplay when screen becomes visible (e.g., switching tabs)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryAutoplayCurrent();
    });
  }

  /// **HANDLE VISIBILITY CHANGES: Pause/resume videos based on tab visibility**
  void _handleVisibilityChange(bool isVisible) {
    print(
        '🔍 VideoFeedAdvanced: _handleVisibilityChange called - isVisible: $isVisible, _isScreenVisible: $_isScreenVisible');

    if (_isScreenVisible != isVisible) {
      _isScreenVisible = isVisible;
      print(
          '🔄 VideoFeedAdvanced: Screen visibility changed to ${isVisible ? "VISIBLE" : "HIDDEN"}');

      if (isVisible) {
        // Screen became visible - resume current video
        print(
            '▶️ VideoFeedAdvanced: Screen became visible, trying to resume video');
        _tryAutoplayCurrent();
      } else {
        // Screen became hidden - pause current video
        print(
            '⏸️ VideoFeedAdvanced: Screen became hidden, pausing current video');
        _pauseCurrentVideo();
      }
    } else {
      print('🔄 VideoFeedAdvanced: No visibility change needed');
    }
  }

  /// **PAUSE CURRENT VIDEO: When screen becomes hidden**
  void _pauseCurrentVideo() {
    print(
        '🔍 VideoFeedAdvanced: _pauseCurrentVideo called - current index: $_currentIndex');
    print(
        '🔍 VideoFeedAdvanced: Controller pool keys: ${_controllerPool.keys.toList()}');

    // **NEW: Stop view tracking when pausing**
    if (_currentIndex < _videos.length) {
      final currentVideo = _videos[_currentIndex];
      _viewTracker.stopViewTracking(currentVideo.id);
      print('⏸️ Stopped view tracking for paused video: ${currentVideo.id}');
    }

    // Pause local controller pool
    if (_controllerPool.containsKey(_currentIndex)) {
      final controller = _controllerPool[_currentIndex];
      print('🔍 VideoFeedAdvanced: Controller found for index $_currentIndex');
      print(
          '🔍 VideoFeedAdvanced: Controller initialized: ${controller?.value.isInitialized}');
      print(
          '🔍 VideoFeedAdvanced: Controller playing: ${controller?.value.isPlaying}');

      if (controller != null &&
          controller.value.isInitialized &&
          controller.value.isPlaying) {
        controller.pause();
        _controllerStates[_currentIndex] = false;
        print(
            '⏸️ VideoFeedAdvanced: Successfully paused video at index $_currentIndex');
      } else {
        print('⏸️ VideoFeedAdvanced: Video not playing or not initialized');
      }
    } else {
      print(
          '❌ VideoFeedAdvanced: No controller found for index $_currentIndex');
    }

    // Also pause VideoControllerManager videos
    _videoControllerManager.pauseAllVideosOnTabChange();
    print('⏸️ VideoFeedAdvanced: Called VideoControllerManager pause');
  }

  void _pauseAllVideosOnTabSwitch() {
    print('⏸️ VideoFeedAdvanced: Pausing all videos due to tab switch');

    // Pause all active controllers in the pool
    _controllerPool.forEach((index, controller) {
      if (controller.value.isInitialized && controller.value.isPlaying) {
        controller.pause();
        _controllerStates[index] = false;
        print('⏸️ VideoFeedAdvanced: Paused video at index $index');
      }
    });

    // Also pause VideoControllerManager videos
    _videoControllerManager.pauseAllVideosOnTabChange();

    // Update screen visibility state
    _isScreenVisible = false;
  }

  void _tryAutoplayCurrent() {
    // Update screen visibility when resuming
    _isScreenVisible = true;

    print(
        '🔍 VideoFeedAdvanced: _tryAutoplayCurrent called for index $_currentIndex');

    final ctrl = _controllerPool[_currentIndex];
    if (ctrl != null &&
        ctrl.value.isInitialized &&
        _userPaused[_currentIndex] != true) {
      if (!ctrl.value.isPlaying) {
        _applyLoopingBehavior(ctrl);
        _attachEndListenerIfNeeded(ctrl, _currentIndex);
        _attachBufferingListenerIfNeeded(ctrl, _currentIndex);
        ctrl.play();
        _controllerStates[_currentIndex] = true;
        print('▶️ VideoFeedAdvanced: Resumed video at index $_currentIndex');

        // **NEW: Start view tracking when video resumes**
        if (_currentIndex < _videos.length) {
          final currentVideo = _videos[_currentIndex];
          _viewTracker.startViewTracking(currentVideo.id);
          print(
              '▶️ Started view tracking for resumed video: ${currentVideo.id}');
        }
      }
    }

    // Also resume VideoControllerManager videos
    _videoControllerManager.resumeVideosOnTabReturn();
  }

  @override
  void initState() {
    super.initState();
    _videoService = VideoService();
    _authService = AuthService();
    _carouselAdManager = CarouselAdManager();
    _pageController = PageController(initialPage: widget.initialIndex ?? 0);

    _loadInitialData();
    _startPreloading();
    WidgetsBinding.instance.addObserver(this);

    // **CRITICAL: Register video pause/resume callbacks with MainController**
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final mainController =
            Provider.of<MainController>(context, listen: false);
        mainController.registerVideoPauseCallback(() {
          print('🔥 CALLBACK TRIGGERED: Pause callback called!');
          _pauseAllVideosOnTabSwitch();
        });
        mainController.registerVideoResumeCallback(() {
          print('🔥 CALLBACK TRIGGERED: Resume callback called!');
          _tryAutoplayCurrent();
        });
        print(
            '📱 VideoFeedAdvanced: Registered pause/resume callbacks with MainController - SUCCESS');
      } catch (e) {
        print('❌ VideoFeedAdvanced: Failed to register callbacks: $e');
      }
    });

    // Load auto-scroll preference
    AutoScrollSettings.isEnabled().then((value) {
      if (mounted) {
        setState(() {
          _autoScrollEnabled = value;
        });
        // Apply looping behavior to any initialized controllers
        _controllerPool.forEach((idx, ctrl) => _applyLoopingBehavior(ctrl));
      }
    });

    // **NEW: Listen for ad refresh notifications**
    _adRefreshSubscription = _adRefreshNotifier.refreshStream.listen((_) {
      print('🔄 VideoFeedAdvanced: Received ad refresh notification');
      refreshAds();
    });

    // **NEW: Connect to real-time ad updates**
    _connectToRealtimeAds();

    // **NEW: Start polling as fallback (every 30 seconds)**
    _startAdPolling();

    // React instantly to changes
    AutoScrollSettings.notifier.addListener(() {
      if (!mounted) return;
      final val = AutoScrollSettings.notifier.value;
      setState(() {
        _autoScrollEnabled = val;
      });
      _controllerPool.forEach((idx, ctrl) => _applyLoopingBehavior(ctrl));
    });

    // **TAB CHANGE DETECTION: Register callbacks with MainController**
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mainController =
          Provider.of<MainController>(context, listen: false);
      mainController.registerPauseVideosCallback(() {
        print('🔥 OLD CALLBACK: Pause callback triggered');
        _videoControllerManager.pauseAllVideosOnTabChange();
      });
      mainController.registerResumeVideosCallback(() {
        print('🔥 OLD CALLBACK: Resume callback triggered');
        _videoControllerManager.resumeVideosOnTabReturn();
      });
    });
  }

  /// **INITIAL DATA LOADING**
  Future<void> _loadInitialData() async {
    try {
      setState(() => _isLoading = true);

      await _loadVideos(page: 1);

      // Load current user
      await _loadCurrentUserId();

      // **NEW: Load active ads**
      await _loadActiveAds();

      // Navigate to specific video if provided
      if (widget.initialVideoId != null) {
        final videoIndex =
            _videos.indexWhere((v) => v.id == widget.initialVideoId);
        if (videoIndex != -1) {
          _currentIndex = videoIndex;
          _pageController.animateToPage(
            videoIndex,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeInOut,
          );
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);

        // **NEW: Trigger autoplay after initial data is loaded**
        WidgetsBinding.instance.addPostFrameCallback((_) {
          print(
              '🚀 VideoFeedAdvanced: Triggering initial autoplay after data load');
          _tryAutoplayCurrent();
        });
      }
    } catch (e) {
      print('❌ Error loading initial data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
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
        print('✅ Loaded current user ID: $_currentUserId');
      }
    } catch (e) {
      print('❌ Error loading current user ID: $e');
    }
  }

  /// **NEW: Load active ads for display**
  Future<void> _loadActiveAds() async {
    try {
      print('🎯 VideoFeedAdvanced: Loading active ads...');

      final allAds = await _activeAdsService.fetchActiveAds();

      print('🔍 VideoFeedAdvanced: Raw ads response: $allAds');

      setState(() {
        _bannerAds = allAds['banner'] ?? [];
        _videoFeedAds = allAds['video feed ad'] ?? [];
        _adsLoaded = true;
      });

      print('✅ VideoFeedAdvanced: Loaded ads:');
      print('   Banner ads: ${_bannerAds.length}');
      print('   Video feed ads: ${_videoFeedAds.length}');

      // **NEW: Debug ad details**
      for (int i = 0; i < _bannerAds.length; i++) {
        final ad = _bannerAds[i];
        print(
            '   Banner Ad $i: ${ad['title']} (${ad['adType']}) - Image: ${ad['imageUrl']}');
      }

      for (int i = 0; i < _videoFeedAds.length; i++) {
        final ad = _videoFeedAds[i];
        print('   Video Feed Ad $i: ${ad['title']} (${ad['adType']})');
      }

      // Also update carousel ad manager
      await _carouselAdManager.loadCarouselAds();
    } catch (e) {
      print('❌ Error loading active ads: $e');
      setState(() {
        _adsLoaded =
            true; // Mark as loaded even on error to prevent infinite loading
      });
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

      print(
          '🔍 Checking follow status for ${uniqueUploaders.length} unique uploaders');

      for (final uploaderId in uniqueUploaders) {
        try {
          final isFollowing = await userService.isFollowingUser(uploaderId);
          if (isFollowing) {
            setState(() {
              _followingUsers.add(uploaderId);
            });
          }
        } catch (e) {
          print('❌ Error checking follow status for $uploaderId: $e');
        }
      }

      print('✅ Loaded follow status for ${_followingUsers.length} users');
    } catch (e) {
      print('❌ Error loading following users: $e');
    }
  }

  /// **LOAD VIDEOS WITH PAGINATION**
  Future<void> _loadVideos({int page = 1, bool append = false}) async {
    try {
      final response = await _videoService.getVideos(
        page: page,
        limit: _videosPerPage,
        videoType: widget.videoType, // **FIX: Pass videoType for filtering**
      );
      final newVideos = response['videos'] as List<VideoModel>;

      if (mounted) {
        setState(() {
          if (append) {
            _videos.addAll(newVideos);
          } else {
            _videos = newVideos;
          }
          _currentPage = page;
        });

        // Load following users after videos are loaded
        await _loadFollowingUsers();
      }
    } catch (e) {
      print('❌ Error loading videos: $e');
    }
  }

  /// **PUBLIC: Refresh video list after upload**
  Future<void> refreshVideos() async {
    print('🔄 VideoFeedAdvanced: refreshVideos() called');

    // Prevent multiple simultaneous refresh calls
    if (_isLoading) {
      print(
          '⚠️ VideoFeedAdvanced: Already refreshing, ignoring duplicate call');
      return;
    }

    try {
      // Show loading state
      if (mounted) {
        setState(() {
          _isLoading = true;
          _errorMessage = null; // Clear any previous errors
        });
      }

      // Reset to page 1 and reload
      _currentPage = 1;
      await _loadVideos(page: 1, append: false);

      // **NEW: Also reload ads**
      await _loadActiveAds();

      // Hide loading state
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = null;
        });
      }

      print('✅ VideoFeedAdvanced: Videos refreshed successfully');
    } catch (e) {
      print('❌ VideoFeedAdvanced: Error refreshing videos: $e');

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
                      'Failed to refresh: ${_getUserFriendlyErrorMessage(e)}'),
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
    }
  }

  /// **NEW: Connect to real-time ad updates**
  void _connectToRealtimeAds() {
    print('📡 VideoFeedAdvanced: Connecting to real-time ad updates...');

    _realtimeAdService.connect();

    _realtimeAdSubscription = _realtimeAdService.adUpdates.listen((update) {
      print(
          '📡 VideoFeedAdvanced: Received real-time ad update: ${update['updateType']}');

      if (update['updateType'] == 'activated') {
        // New ad was activated, refresh ads immediately
        print('🔄 VideoFeedAdvanced: New ad activated, refreshing ads...');
        refreshAds();

        // Show success message to user
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  const Text('New ad is now live!'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    });
  }

  /// **NEW: Start polling for ad updates as fallback**
  void _startAdPolling() {
    print('🔄 VideoFeedAdvanced: Starting ad polling (30s interval)...');

    _adPollingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted && !_realtimeAdService.isConnected) {
        print('🔄 VideoFeedAdvanced: Polling for ad updates...');
        refreshAds();
      }
    });
  }

  /// **NEW: Refresh only ads (for when new ads are created)**
  Future<void> refreshAds() async {
    print('🔄 VideoFeedAdvanced: refreshAds() called');

    try {
      await _loadActiveAds();
      print('✅ VideoFeedAdvanced: Ads refreshed successfully');
    } catch (e) {
      print('❌ Error refreshing ads: $e');
    }
  }

  /// **LOAD MORE VIDEOS FOR INFINITE SCROLLING**
  Future<void> _loadMoreVideos() async {
    if (_isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    try {
      await _loadVideos(page: _currentPage + 1, append: true);
    } catch (e) {
      print('❌ Error loading more videos: $e');
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

  /// **PRELOAD VIDEOS NEAR CURRENT INDEX**
  void _preloadNearbyVideos() {
    if (_videos.isEmpty) return;

    // Preload current + next 2 videos
    for (int i = _currentIndex;
        i <= _currentIndex + 2 && i < _videos.length;
        i++) {
      if (!_preloadedVideos.contains(i) && !_loadingVideos.contains(i)) {
        _preloadVideo(i);
      }
    }

    // **FIXED: Only load more videos if we have enough videos to justify infinite scrolling**
    // Don't trigger infinite scrolling if we have less than 5 videos total
    if (_videos.length >= 5 &&
        _currentIndex >= _videos.length - _infiniteScrollThreshold) {
      _loadMoreVideos();
    }
  }

  /// **PRELOAD SINGLE VIDEO**
  Future<void> _preloadVideo(int index) async {
    if (index >= _videos.length) return;

    _loadingVideos.add(index);

    try {
      final video = _videos[index];

      // **FIXED: Validate and fix video URL before creating controller**
      final videoUrl = _validateAndFixVideoUrl(video.videoUrl);
      if (videoUrl == null || videoUrl.isEmpty) {
        print('❌ Invalid video URL for video $index: ${video.videoUrl}');
        _loadingVideos.remove(index);
        return;
      }

      print('🎬 Preloading video $index with URL: $videoUrl');

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
      );

      // **FIXED: Add timeout and better error handling**
      await controller.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Video initialization timeout');
        },
      );

      if (mounted && _loadingVideos.contains(index)) {
        _controllerPool[index] = controller;
        _controllerStates[index] = false; // Not playing initially
        _preloadedVideos.add(index);
        _loadingVideos.remove(index);

        // Apply looping vs auto-advance behavior
        _applyLoopingBehavior(controller);
        // Attach end listener for auto-scroll
        _attachEndListenerIfNeeded(controller, index);
        // Attach buffering listener to track mid-playback stalls
        _attachBufferingListenerIfNeeded(controller, index);

        // **NEW: Start view tracking if this is the current video**
        if (index == _currentIndex && index < _videos.length) {
          final video = _videos[index];
          _viewTracker.startViewTracking(video.id);
          print(
              '▶️ Started view tracking for preloaded current video: ${video.id}');
        }

        print('✅ Successfully preloaded video $index');
        // Clean up old controllers to prevent memory leaks
        _cleanupOldControllers();
      } else {
        controller.dispose();
      }
    } catch (e) {
      print('❌ Error preloading video $index: $e');
      _loadingVideos.remove(index);

      // **FIXED: Add retry logic for failed preloads**
      if (e.toString().contains('400') || e.toString().contains('404')) {
        print('🔄 Retrying video $index in 5 seconds...');
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted && !_preloadedVideos.contains(index)) {
            _preloadVideo(index);
          }
        });
      }
    }
  }

  /// **VALIDATE AND FIX VIDEO URL**
  String? _validateAndFixVideoUrl(String url) {
    if (url.isEmpty) return null;

    // **FIXED: Handle relative URLs and ensure proper base URL**
    if (!url.startsWith('http')) {
      if (url.startsWith('/')) {
        return '${VideoService.baseUrl}$url';
      } else {
        return '${VideoService.baseUrl}/$url';
      }
    }

    // **FIXED: Validate URL format**
    try {
      final uri = Uri.parse(url);
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        return url;
      }
    } catch (e) {
      print('❌ Invalid URL format: $url');
    }

    return null;
  }

  /// **CLEANUP OLD CONTROLLERS: Instagram-style recycling**
  void _cleanupOldControllers() {
    if (_controllerPool.length <= _maxPoolSize) return;

    // Find controllers that are far from current index
    final currentIndex = _currentIndex;
    final controllersToRemove = <int>[];

    for (final index in _controllerPool.keys) {
      if ((index - currentIndex).abs() > _maxPoolSize) {
        controllersToRemove.add(index);
      }
    }

    // Remove old controllers
    for (final index in controllersToRemove) {
      final ctrl = _controllerPool[index];
      if (ctrl != null) {
        ctrl.removeListener(_bufferingListeners[index] ?? () {});
        ctrl.removeListener(_videoEndListeners[index] ?? () {});
        ctrl.dispose();
      }
      _controllerPool.remove(index);
      _controllerStates.remove(index);
      _preloadedVideos.remove(index);
      _isBuffering.remove(index);
      _bufferingListeners.remove(index);
      _videoEndListeners.remove(index);
    }
  }

  /// **GET OR CREATE CONTROLLER: Instagram-style recycling**
  VideoPlayerController? _getController(int index) {
    if (_controllerPool.containsKey(index)) {
      return _controllerPool[index];
    }

    // If not in pool, preload it
    _preloadVideo(index);
    return null;
  }

  /// **HANDLE PAGE CHANGES**
  void _onPageChanged(int index) {
    if (index == _currentIndex) return;

    // **NEW: Stop view tracking for previous video**
    if (_currentIndex < _videos.length) {
      final previousVideo = _videos[_currentIndex];
      _viewTracker.stopViewTracking(previousVideo.id);
      print('⏸️ Stopped view tracking for previous video: ${previousVideo.id}');
    }

    // Pause previous video
    if (_controllerPool.containsKey(_currentIndex)) {
      _controllerPool[_currentIndex]?.pause();
      _controllerStates[_currentIndex] = false;
    }

    _currentIndex = index;

    // Play current video if preloaded
    if (_controllerPool.containsKey(index)) {
      _controllerPool[index]?.play();
      _controllerStates[index] = true;
      _userPaused[index] = false;
      final ctrl = _controllerPool[index]!;
      _applyLoopingBehavior(ctrl);
      _attachEndListenerIfNeeded(ctrl, index);
      _attachBufferingListenerIfNeeded(ctrl, index);

      // **NEW: Start view tracking for current video**
      if (index < _videos.length) {
        final currentVideo = _videos[index];
        _viewTracker.startViewTracking(currentVideo.id);
        print('▶️ Started view tracking for current video: ${currentVideo.id}');
      }
    }

    _preloadNearbyVideos();
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
                  ? const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    )
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
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
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
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
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
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
            ),
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
    if (!_adsLoaded) {
      return _videos.length + (_isLoadingMore ? 1 : 0);
    }

    // **FIXED: Ads are integrated with video content, not separate items**
    // Only video feed ads are separate items, banner and carousel are integrated
    const videoFeedAdInterval = 1; // Show video feed ad after every video
    final totalVideos = _videos.length;
    final estimatedVideoFeedAds = (totalVideos / videoFeedAdInterval).floor();
    final actualVideoFeedAds = _videoFeedAds.length;
    final videoFeedAdsToShow =
        actualVideoFeedAds.clamp(0, estimatedVideoFeedAds);

    return totalVideos + videoFeedAdsToShow + (_isLoadingMore ? 1 : 0);
  }

  /// **NEW: Build feed item (video or ad)**
  Widget _buildFeedItem(int index) {
    final totalVideos = _videos.length;

    // **FIXED: Check if this should be a video feed ad (separate item)**
    if (_adsLoaded && _videoFeedAds.isNotEmpty) {
      const videoFeedAdInterval = 1; // Show video feed ad after every video

      // Calculate if this index should show a video feed ad
      if ((index + 1) % (videoFeedAdInterval + 1) == 0) {
        // This should be a video feed ad position
        final adIndex = ((index + 1) ~/ (videoFeedAdInterval + 1)) - 1;

        if (adIndex < _videoFeedAds.length) {
          print('🎯 Showing video feed ad at index $index (ad $adIndex)');
          print('   Ad title: ${_videoFeedAds[adIndex]['title']}');
          print('   Ad type: ${_videoFeedAds[adIndex]['adType']}');
          return VideoFeedAdWidget(
            adData: _videoFeedAds[adIndex],
            onAdClick: () {
              print(
                  '🖱️ Video feed ad clicked: ${_videoFeedAds[adIndex]['title']}');
            },
          );
        } else {
          print('⚠️ No video feed ad available at index $index (ad $adIndex)');
        }
      }
    }

    // Calculate actual video index accounting for video feed ads
    int videoIndex = index;
    if (_adsLoaded && _videoFeedAds.isNotEmpty) {
      const videoFeedAdInterval = 1;
      final adsBeforeThisIndex = (index / (videoFeedAdInterval + 1)).floor();
      videoIndex = index - adsBeforeThisIndex;
    }

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
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 14,
                ),
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

  /// **BUILD SINGLE VIDEO ITEM: Instagram-style with simple conditional display**
  Widget _buildVideoItem(
    VideoModel video,
    VideoPlayerController? controller,
    bool isActive,
    int index,
  ) {
    // Initialize horizontal index for this video if not exists
    if (!_horizontalIndices.containsKey(index)) {
      _horizontalIndices[index] = 0; // Start with video (index 0)
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Stack(
        children: [
          // **UPDATED: Show video or carousel ad based on horizontal index**
          _horizontalIndices[index] == 0
              ? _buildVideoPage(video, controller, isActive, index)
              : _buildCarouselAdPage(index),

          // Loading indicator
          if (_loadingVideos.contains(index))
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
        ],
      ),
    );
  }

  // Removed: _buildOverlayNavArrows method - using only vertical action buttons for navigation

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
          Positioned.fill(
            child: controller != null && controller.value.isInitialized
                ? _buildVideoPlayer(controller, isActive, index)
                : _buildVideoThumbnail(video),
          ),
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _togglePlayPause(index),
              // **REMOVED: Horizontal drag navigation - now handled by PageView**
              child: const SizedBox.expand(),
            ),
          ),

          // **NEW: Banner ad at top of video (if available)**
          if (_adsLoaded && _bannerAds.isNotEmpty) ...[
            // Debug: Log when banner ad is being displayed
            if (kDebugMode)
              Positioned(
                top: 0,
                left: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  color: Colors.red.withOpacity(0.8),
                  child: Text(
                    'Banner Ad ${index % _bannerAds.length}',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SizedBox(
                height: 60,
                child: BannerAdWidget(
                  adData: _bannerAds[index % _bannerAds.length],
                  onAdClick: () {
                    if (kDebugMode) {
                      print('🖱️ Banner ad clicked on video $index');
                    }
                  },
                ),
              ),
            ),
          ],
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

          // Quality indicator - Green for 480p, Red for others
          if (controller != null && controller.value.isInitialized)
            _buildQualityIndicator(controller, video),

          // **NEW: Swipe indicator for carousel ads**
          if (_carouselAdManager.getCarouselAdForIndex(index) != null)
            _buildSwipeIndicator(index),

          // **NEW: Debug info for ads (only in debug mode)**
          if (kDebugMode)
            Positioned(
              top: 100,
              left: 16,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Banner: ${_bannerAds.length}, Video: ${_videoFeedAds.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: refreshAds,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Refresh Ads',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// **BUILD SWIPE INDICATOR: Shows users they can swipe for ads**
  Widget _buildSwipeIndicator(int index) {
    return Positioned(
      right: 16,
      top: MediaQuery.of(context).size.height * 0.5 - 20,
      child: AnimatedOpacity(
        opacity: _horizontalIndices[index] == 0 ? 0.7 : 0.0,
        duration: const Duration(milliseconds: 300),
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
                'Swipe',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: 4),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.white,
                size: 12,
              ),
            ],
          ),
        ),
      ),
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
            height: 8, // Increased height for better touch target
            color: Colors.black.withOpacity(0.4),
            child: Stack(
              children: [
                // Progress bar background
                Container(
                  height: 4,
                  margin:
                      const EdgeInsets.only(top: 2), // Center the progress bar
                  color: Colors.grey.withOpacity(0.3),
                ),
                // Progress bar filled portion
                Positioned(
                  top: 2,
                  left: 0,
                  child: Container(
                    height: 4,
                    width: MediaQuery.of(context).size.width * progress,
                    color: Colors.green[400],
                  ),
                ),
                // Seek handle (thumb)
                if (progress > 0)
                  Positioned(
                    top: 0,
                    left: (MediaQuery.of(context).size.width * progress) - 6,
                    child: Container(
                      width: 12,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.green[400],
                        borderRadius: BorderRadius.circular(6),
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

  /// **BUILD QUALITY INDICATOR: Green for 480p, Red for others**
  Widget _buildQualityIndicator(
      VideoPlayerController controller, VideoModel video) {
    return Positioned(
      top: 16,
      right: 16,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) {
          // Determine if video is 480p
          final is480p = _isVideo480p(controller, video);
          final qualityText = _getQualityText(controller, video);

          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: is480p ? Colors.green : Colors.red,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Quality indicator dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: is480p ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                // Quality text
                Text(
                  qualityText,
                  style: TextStyle(
                    color: is480p ? Colors.green : Colors.red,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// **CHECK IF VIDEO IS 480P**
  bool _isVideo480p(VideoPlayerController controller, VideoModel video) {
    // Check if using 480p URL from video model
    if (video.lowQualityUrl != null && video.lowQualityUrl!.isNotEmpty) {
      return true; // App is configured to use 480p URLs
    }

    // Check actual video resolution from controller
    final videoValue = controller.value;
    if (videoValue.size.width > 0 && videoValue.size.height > 0) {
      final height = videoValue.size.height.toInt();
      return height <= 480;
    }

    // Default assumption based on app configuration (all videos are 480p)
    return true;
  }

  /// **GET QUALITY TEXT**
  String _getQualityText(VideoPlayerController controller, VideoModel video) {
    // Check if video is HLS
    final isHLS =
        video.videoUrl.contains('.m3u8') || video.isHLSEncoded == true;

    // Get actual resolution from controller if available
    final videoValue = controller.value;
    if (videoValue.size.width > 0 && videoValue.size.height > 0) {
      final height = videoValue.size.height.toInt();
      final suffix = isHLS ? ' HLS' : '';
      return '${height}p$suffix';
    }

    // Default to 480p as per app configuration
    return isHLS ? '480p HLS' : '480p';
  }

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
        print('⏸️ User paused video: ${video.id}, stopped view tracking');
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
        _viewTracker.startViewTracking(video.id);
        print('▶️ User played video: ${video.id}, started view tracking');
      }
    }
  }

  /// **BUILD CAROUSEL AD PAGE: Simple carousel ads with button navigation**
  Widget _buildCarouselAdPage(int videoIndex) {
    final carouselAd = _carouselAdManager.getCarouselAdForIndex(videoIndex);

    if (carouselAd == null || carouselAd.slides.isEmpty) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: const Center(
          child: Text(
            'No ad available',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
        ),
      );
    }

    // Initialize carousel slide index if not exists
    if (!_currentCarouselSlideIndex.containsKey(videoIndex)) {
      _currentCarouselSlideIndex[videoIndex] = 0;
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Stack(
        children: [
          // **FIXED: Remove PageView from carousel, use simple index-based display**
          _buildCarouselAdSlide(
            carouselAd.slides[_currentCarouselSlideIndex[videoIndex] ?? 0],
            carouselAd,
            videoIndex,
          ),

          // **NEW: Carousel dot indicator**
          if (carouselAd.slides.length > 1)
            _buildCarouselDotIndicator(videoIndex, carouselAd.slides.length),

          // **NEW: Arrow navigation buttons**
          _buildCarouselArrowButtons(videoIndex, carouselAd),
        ],
      ),
    );
  }

  /// **BUILD CAROUSEL DOT INDICATOR: Shows current slide position**
  Widget _buildCarouselDotIndicator(int videoIndex, int slideCount) {
    final currentSlide = _currentCarouselSlideIndex[videoIndex] ?? 0;

    return Positioned(
      bottom: 20,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(slideCount, (index) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: index == currentSlide
                  ? Colors.white
                  : Colors.white.withOpacity(0.4),
            ),
          );
        }),
      ),
    );
  }

  /// **BUILD CAROUSEL ARROW BUTTONS: Navigation arrows placed horizontally**
  Widget _buildCarouselArrowButtons(
      int videoIndex, CarouselAdModel carouselAd) {
    return Positioned(
      left: 16,
      right: 16,
      bottom: 20,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Back to video arrow (always visible)
          GestureDetector(
            onTap: () => _navigateBackToVideo(videoIndex),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back_ios,
                color: Colors.white,
                size: 20,
              ),
            ),
          ),

          // Next slide arrow (only if multiple slides)
          if (carouselAd.slides.length > 1)
            GestureDetector(
              onTap: () => _navigateToNextCarouselSlide(videoIndex, carouselAd),
              child: Container(
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
            )
          else
            // Empty container for consistent spacing when no next arrow
            const SizedBox(
              width: 44,
              height: 44,
            ),
        ],
      ),
    );
  }

  /// **BUILD CAROUSEL AD SLIDE: Individual ad slide**
  Widget _buildCarouselAdSlide(
    CarouselSlide slide,
    CarouselAdModel ad,
    int videoIndex,
  ) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Stack(
        children: [
          // Ad media - Full screen like Instagram Reels
          Container(
            width: double.infinity,
            height: double.infinity,
            color: Colors.black,
            child: FittedBox(
              fit:
                  BoxFit.contain, // Changed to contain to preserve aspect ratio
              child: Image.network(
                slide.mediaUrl,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit
                    .contain, // Changed to contain to preserve aspect ratio
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.black,
                    child: const Center(
                      child: Icon(
                        Icons.image_not_supported,
                        size: 64,
                        color: Colors.white54,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          // Ad content overlay
          Positioned(
            bottom: 100,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Advertiser info with follow button
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => _navigateToCreatorProfile(ad.campaignId),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundImage: NetworkImage(ad.advertiserProfilePic),
                        onBackgroundImageError: (exception, stackTrace) {
                          print(
                              'Error loading advertiser profile pic: $exception');
                        },
                        child: ad.advertiserProfilePic.isEmpty
                            ? Text(
                                ad.advertiserName.isNotEmpty
                                    ? ad.advertiserName[0].toUpperCase()
                                    : 'A',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              )
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _navigateToCreatorProfile(ad.campaignId),
                        child: Text(
                          ad.advertiserName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Ad title
                Text(
                  slide.title ?? 'Ad Title',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                // Ad description
                Text(
                  slide.description ?? 'Ad Description',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 16),

                // Call to action button
                GestureDetector(
                  onTap: () {
                    print('🔗 Carousel ad CTA tapped: ${ad.callToActionUrl}');
                    _carouselAdManager.onCarouselAdClicked(ad);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: Text(
                      ad.callToActionLabel,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPlayer(
      VideoPlayerController controller, bool isActive, int index) {
    // Preserve original video size without cropping (no zoom-to-fill)
    // Compute effective dimensions considering rotation metadata
    final Size rawSize = controller.value.size;
    final int rotationDegrees = controller.value.rotationCorrection;
    final bool swapSides = rotationDegrees == 90 || rotationDegrees == 270;

    final double sourceWidth = (rawSize.width > 0 && rawSize.height > 0)
        ? (swapSides ? rawSize.height : rawSize.width)
        : 9.0;
    final double sourceHeight = (rawSize.width > 0 && rawSize.height > 0)
        ? (swapSides ? rawSize.width : rawSize.height)
        : 16.0;

    // Calculate aspect ratio to determine if this is a portrait (9:16) or landscape (16:9) video
    final double aspectRatio = sourceWidth / sourceHeight;
    // final bool isPortraitVideo = aspectRatio < 1.0; // Portrait videos have width < height

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain, // Always use contain to preserve aspect ratio
          child: SizedBox(
            width: sourceWidth,
            height: sourceHeight,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
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
      VideoPlayerController controller, int index) {
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
  }

  final Map<int, VoidCallback> _videoEndListeners = {};

  void _applyLoopingBehavior(VideoPlayerController controller) {
    // Loop when auto-scroll is OFF; do not loop when auto-scroll is ON
    controller.setLooping(!_autoScrollEnabled);
  }

  Widget _buildVideoThumbnail(VideoModel video) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: video.thumbnailUrl.isNotEmpty
          ? Center(
              child: Image.network(
                video.thumbnailUrl,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return _buildFallbackThumbnail();
                },
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
            Icon(
              Icons.play_circle_outline,
              size: 80,
              color: Colors.white54,
            ),
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

  Widget _buildVideoOverlay(VideoModel video, int index) {
    return Stack(
      children: [
        // Bottom info section
        Positioned(
          bottom: 8, // Leave space for interactive progress bar (8px height)
          left: 0,
          right: 80, // Leave space for vertical action buttons
          child: Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Video title
                Text(
                  video.videoName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),

                // Uploader info with follow button
                Row(
                  children: [
                    CircleAvatar(
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
                const SizedBox(height: 16),

                if (video.link?.isNotEmpty == true)
                  GestureDetector(
                    onTap: () => _handleVisitNow(video),
                    child: Container(
                      // **UPDATED: Increased width significantly while keeping height same**
                      width: MediaQuery.of(context).size.width *
                          0.75, // 50% of screen width
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[700],
                        borderRadius: BorderRadius.circular(12),
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

              // Carousel ad navigation with consistent size
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
                        size:
                            20, // **REDUCED: From 24 to 20 to match other buttons visually**
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

  /// **BUILD VERTICAL ACTION BUTTON: Instagram-style with count**
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
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
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

  /// **HANDLE LIKE: With API integration**
  Future<void> _handleLike(VideoModel video, int index) async {
    if (_currentUserId == null) {
      _showSignInPrompt(
          'To like videos, please sign in with your Google account.');
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
      print('✅ Successfully toggled like for video ${video.id}');
    } catch (e) {
      print('❌ Error handling like: $e');

      // **FIXED: Revert to original state on error**
      setState(() {
        video.likedBy.clear();
        video.likedBy.addAll(originalLikedBy);
        video.likes = originalLikes;
      });

      _showSnackBar('Failed to update like', isError: true);
    }
  }

  /// **HANDLE COMMENT: Open comment sheet**
  void _handleComment(VideoModel video) {
    if (_currentUserId == null) {
      _showSignInPrompt(
          'To view and add comments, please sign in with your Google account.');
      return;
    }

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

  /// **HANDLE SHARE: With proper share functionality**
  Future<void> _handleShare(VideoModel video) async {
    try {
      final shareText = 'Check out this video: ${video.videoName}\n\n'
          'By: ${video.uploader.name}\n\n'
          'Watch it on Snehayog!';

      await Share.share(
        shareText,
        subject: video.videoName,
      );
    } catch (e) {
      print('❌ Error sharing video: $e');
      _showSnackBar('Failed to share video', isError: true);
    }
  }

  /// **HANDLE VISIT NOW: Open link in browser**
  Future<void> _handleVisitNow(VideoModel video) async {
    try {
      if (video.link?.isNotEmpty == true) {
        print('🔗 Visit Now tapped for: ${video.link}');

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
      print('❌ Error opening link: $e');
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

  /// **SHOW SIGN IN PROMPT: Better UX for guest users**
  void _showSignInPrompt(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(
                Icons.login,
                color: Colors.blue[600],
                size: 28,
              ),
              const SizedBox(width: 12),
              const Text(
                'Sign In Required',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.blue[600],
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sign in to enjoy all features like liking, commenting, and following creators!',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blue[700],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Maybe Later',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                Navigator.pushReplacementNamed(context, '/login');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Sign In',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// **NAVIGATE TO CAROUSEL AD: Switch to carousel ad view**
  void _navigateToCarouselAd(int index) {
    setState(() {
      _horizontalIndices[index] = 1; // Switch to carousel ad page
    });
    print('🎯 Navigated to carousel ad for video $index');
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isFollowing ? Colors.grey[800] : Colors.blue[600],
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isFollowing ? Colors.grey[600]! : Colors.blue[600]!,
            width: 1,
          ),
        ),
        child: Text(
          isFollowing ? 'Following' : 'Follow',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  /// **HANDLE FOLLOW/UNFOLLOW: With API integration**
  Future<void> _handleFollow(VideoModel video) async {
    if (_currentUserId == null) {
      _showSignInPrompt(
          'To follow users, please sign in with your Google account.');
      return;
    }

    if (video.uploader.id == _currentUserId) {
      _showSnackBar('You cannot follow yourself', isError: true);
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
        _showSnackBar('Unfollowed ${video.uploader.name}');
      } else {
        await userService.followUser(video.uploader.id);
        _showSnackBar('Following ${video.uploader.name}');
      }
    } catch (e) {
      print('❌ Error handling follow/unfollow: $e');

      // Revert optimistic update on error
      setState(() {
        final isFollowing = _isFollowing(video.uploader.id);
        if (isFollowing) {
          _followingUsers.remove(video.uploader.id);
        } else {
          _followingUsers.add(video.uploader.id);
        }
      });

      _showSnackBar(
          'Failed to ${_isFollowing(video.uploader.id) ? 'unfollow' : 'follow'} user',
          isError: true);
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

  /// **NAVIGATE BACK TO VIDEO: Simple state change**
  void _navigateBackToVideo(int videoIndex) {
    setState(() {
      _horizontalIndices[videoIndex] = 0; // Show video
    });
  }

  /// **NAVIGATE TO NEXT CAROUSEL SLIDE: Simple state change**
  void _navigateToNextCarouselSlide(
      int videoIndex, CarouselAdModel carouselAd) {
    if (carouselAd.slides.length > 1) {
      final currentSlide = _currentCarouselSlideIndex[videoIndex] ?? 0;
      final nextSlide = (currentSlide + 1) % carouselAd.slides.length;

      setState(() {
        _currentCarouselSlideIndex[videoIndex] = nextSlide;
      });
    }
  }

  /// **NAVIGATE TO CREATOR PROFILE: Navigate to user profile screen**
  void _navigateToCreatorProfile(String userId) {
    if (userId.isEmpty) {
      _showSnackBar('User profile not available', isError: true);
      return;
    }

    print('🔗 Navigating to creator profile: $userId');

    // Navigate to profile screen
    Navigator.pushNamed(
      context,
      '/profile',
      arguments: {'userId': userId},
    ).catchError((error) {
      print('❌ Error navigating to profile: $error');
      _showSnackBar('Failed to open profile', isError: true);
      return null; // Return null to satisfy the return type
    });
  }

  /// **APP LIFECYCLE HANDLING**
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // Pause current video
        if (_controllerPool.containsKey(_currentIndex)) {
          _controllerPool[_currentIndex]?.pause();
          _controllerStates[_currentIndex] = false;
        }
        break;
      case AppLifecycleState.resumed:
        // Resume current video
        if (_controllerPool.containsKey(_currentIndex)) {
          _userPaused[_currentIndex] = false;
          _tryAutoplayCurrent();
        }
        break;
      default:
        break;
    }
  }

  /// **TEST API CONNECTION: Test if the API is reachable**
  Future<void> _testApiConnection() async {
    try {
      print('🔍 VideoFeedAdvanced: Testing API connection...');

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
      print('❌ VideoFeedAdvanced: API connection test failed: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                      'Connection failed: ${_getUserFriendlyErrorMessage(e)}'),
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
  void dispose() {
    // **CRITICAL: Unregister callbacks from MainController**
    try {
      final mainController =
          Provider.of<MainController>(context, listen: false);
      mainController.unregisterCallbacks();
      print('📱 VideoFeedAdvanced: Unregistered callbacks from MainController');
    } catch (e) {
      print('⚠️ VideoFeedAdvanced: Error unregistering callbacks: $e');
    }

    // **NEW: Clean up views service**
    _viewTracker.dispose();
    print('🎯 VideoFeedAdvanced: Disposed ViewsService');

    // Clean up all video controllers
    _controllerPool.forEach((index, controller) {
      controller.removeListener(_bufferingListeners[index] ?? () {});
      controller.removeListener(_videoEndListeners[index] ?? () {});
      controller.dispose();
    });
    _controllerPool.clear();
    _controllerStates.clear();
    _isBuffering.clear();
    _bufferingListeners.clear();
    _videoEndListeners.clear();

    // **REMOVED: No more PageControllers to clean up**

    // Cancel timers
    _preloadTimer?.cancel();

    // **NEW: Cancel ad refresh subscription**
    _adRefreshSubscription?.cancel();

    // **NEW: Disconnect from real-time ad updates**
    _realtimeAdSubscription?.cancel();
    _realtimeAdService.disconnect();

    // **NEW: Cancel ad polling timer**
    _adPollingTimer?.cancel();

    // Remove observer
    WidgetsBinding.instance.removeObserver(this);

    // **TAB CHANGE DETECTION: Unregister callbacks**
    try {
      final mainController =
          Provider.of<MainController>(context, listen: false);
      mainController.unregisterCallbacks();
    } catch (e) {
      print('⚠️ VideoFeedAdvanced: Error unregistering callbacks: $e');
    }

    super.dispose();
  }
}
