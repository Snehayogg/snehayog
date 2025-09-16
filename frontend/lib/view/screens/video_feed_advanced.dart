import 'dart:async';
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
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:snehayog/core/services/auto_scroll_settings.dart';
import 'package:snehayog/controller/main_controller.dart';
import 'package:snehayog/core/managers/video_controller_manager.dart';

class VideoFeedAdvanced extends StatefulWidget {
  final int? initialIndex;
  final List<VideoModel>? initialVideos;
  final String? initialVideoId;

  const VideoFeedAdvanced({
    Key? key,
    this.initialIndex,
    this.initialVideos,
    this.initialVideoId,
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

  // **SERVICES**
  late VideoService _videoService;
  late AuthService _authService;
  late CarouselAdManager _carouselAdManager;
  final VideoControllerManager _videoControllerManager =
      VideoControllerManager();

  // **PAGE CONTROLLER**
  late PageController _pageController;
  bool _autoScrollEnabled = false;
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
      {}; // Track horizontal page for each video
  final Map<int, PageController> _horizontalPageControllers =
      {}; // Horizontal page controllers

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
    if (_isScreenVisible != isVisible) {
      _isScreenVisible = isVisible;
      print(
          '🔄 VideoFeedAdvanced: Screen visibility changed to ${isVisible ? "VISIBLE" : "HIDDEN"}');

      if (isVisible) {
        // Screen became visible - resume current video
        _tryAutoplayCurrent();
      } else {
        // Screen became hidden - pause current video
        _pauseCurrentVideo();
      }
    }
  }

  /// **PAUSE CURRENT VIDEO: When screen becomes hidden**
  void _pauseCurrentVideo() {
    // Pause local controller pool
    if (_controllerPool.containsKey(_currentIndex)) {
      final controller = _controllerPool[_currentIndex];
      if (controller != null &&
          controller.value.isInitialized &&
          controller.value.isPlaying) {
        controller.pause();
        _controllerStates[_currentIndex] = false;
        print('⏸️ VideoFeedAdvanced: Paused video on tab switch');
      }
    }

    // Also pause VideoControllerManager videos
    _videoControllerManager.pauseAllVideosOnTabChange();
  }

  void _tryAutoplayCurrent() {
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
        _videoControllerManager.pauseAllVideosOnTabChange();
      });
      mainController.registerResumeVideosCallback(() {
        _videoControllerManager.resumeVideosOnTabReturn();
      });
    });
  }

  /// **INITIAL DATA LOADING**
  Future<void> _loadInitialData() async {
    try {
      setState(() => _isLoading = true);

      // Load initial videos
      await _loadVideos(page: 1);

      // Load current user
      await _loadCurrentUserId();

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
      final response =
          await _videoService.getVideos(page: page, limit: _videosPerPage);
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
      _userPaused[index] = false; // Reset pause indicator for new page
      final ctrl = _controllerPool[index]!;
      _applyLoopingBehavior(ctrl);
      _attachEndListenerIfNeeded(ctrl, index);
      _attachBufferingListenerIfNeeded(ctrl, index);
    }

    // Trigger preloading
    _preloadNearbyVideos();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    // **VISIBILITY DETECTION: Check if this is the active tab**
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // This will be called every time the widget rebuilds
      // We can use this to detect tab visibility changes
      final mainController =
          Provider.of<MainController>(context, listen: false);
      final isVideoTabActive = mainController.currentIndex == 0;
      _handleVisibilityChange(isVideoTabActive);
    });

    return Scaffold(
      backgroundColor: Colors.black,
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Colors.white),
            )
          : _videos.isEmpty
              ? const Center(
                  child: Text(
                    'No videos available',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                )
              : _buildVideoFeed(),
    );
  }

  /// **BUILD VIDEO FEED: Instagram-style PageView**
  Widget _buildVideoFeed() {
    return PageView.builder(
      controller: _pageController,
      scrollDirection: Axis.vertical,
      onPageChanged: _onPageChanged,
      itemCount: _videos.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _videos.length) {
          // **FIXED: Show end of content message instead of infinite loading**
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

        final video = _videos[index];
        final controller = _getController(index);
        final isActive = index == _currentIndex;

        return _buildVideoItem(video, controller, isActive, index);
      },
    );
  }

  /// **BUILD SINGLE VIDEO ITEM: Instagram-style with carousel ads**
  Widget _buildVideoItem(
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
          // Main content with horizontal navigation
          IndexedStack(
            index: _horizontalIndices[index] ?? 0,
            children: [
              // Video page
              _buildVideoPage(video, controller, isActive, index),
              // Carousel ad page
              _buildCarouselAdPage(index),
            ],
          ),

          // Persistent overlay navigation arrows (visible on both pages)
          _buildOverlayNavArrows(index),

          // Loading indicator
          if (_loadingVideos.contains(index))
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
        ],
      ),
    );
  }

  /// Overlay arrows to navigate between video and carousel ad consistently
  Widget _buildOverlayNavArrows(int videoIndex) {
    final isOnCarousel = (_horizontalIndices[videoIndex] ?? 0) == 1;
    final hasCarousel =
        _carouselAdManager.getCarouselAdForIndex(videoIndex) != null;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 24,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Left arrow: only when on carousel, go back to video
          if (isOnCarousel)
            _circleArrowButton(
              icon: Icons.arrow_back_ios,
              onTap: () => _navigateBackToVideo(videoIndex),
            )
          else
            const SizedBox(width: 48),

          // Right arrow: on video -> go to carousel (if exists); on carousel -> next ad slide
          if (hasCarousel)
            _circleArrowButton(
              icon: Icons.arrow_forward_ios,
              onTap: () => isOnCarousel
                  ? _navigateToNextAdSlide(videoIndex)
                  : _navigateToCarouselAd(videoIndex),
            )
          else
            const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _circleArrowButton(
      {required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
    );
  }

  /// **BUILD VIDEO PAGE: Main video content - Instagram Reels style**
  Widget _buildVideoPage(
    VideoModel video,
    VideoPlayerController? controller,
    bool isActive,
    int index,
  ) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black, // Ensure black background
      child: Stack(
        children: [
          // Video player or thumbnail - Full screen
          Positioned.fill(
            child: controller != null && controller.value.isInitialized
                ? _buildVideoPlayer(controller, isActive, index)
                : _buildVideoThumbnail(video),
          ),

          // Top-layer tap zone to toggle play/pause
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _togglePlayPause(index),
              child: const SizedBox.expand(),
            ),
          ),

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
        ],
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

        return Container(
          height: 3,
          color: Colors.white,
          child: Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: progress,
              child: Container(color: Colors.white),
            ),
          ),
        );
      },
    );
  }

  void _togglePlayPause(int index) {
    final controller = _controllerPool[index];
    if (controller == null || !controller.value.isInitialized) return;

    if (_controllerStates[index] == true) {
      controller.pause();
      setState(() {
        _controllerStates[index] = false;
        _userPaused[index] = true; // show play indicator only on user pause
      });
    } else {
      controller.play();
      setState(() {
        _controllerStates[index] = true;
        _userPaused[index] = false; // hide when playing
      });
    }
  }

  /// **BUILD CAROUSEL AD PAGE: Horizontal carousel ads**
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

    // Initialize horizontal page controller if not exists
    if (!_horizontalPageControllers.containsKey(videoIndex)) {
      _horizontalPageControllers[videoIndex] = PageController();
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: PageView.builder(
        controller: _horizontalPageControllers[videoIndex],
        itemCount: carouselAd.slides.length,
        itemBuilder: (context, slideIndex) {
          return _buildCarouselAdSlide(
              carouselAd.slides[slideIndex], carouselAd, videoIndex);
        },
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
              fit: BoxFit.cover, // Cover the entire screen
              child: Image.network(
                slide.mediaUrl,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
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
                // Advertiser info
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundImage: NetworkImage(ad.advertiserProfilePic),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      ad.advertiserName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
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

          // Navigation controls
          Positioned(
            right: 16,
            bottom: 16,
            child: Column(
              children: [
                // Back to video button - Made more prominent
                GestureDetector(
                  onTap: () => _navigateBackToVideo(videoIndex),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Next ad slide button
                GestureDetector(
                  onTap: () => _navigateToNextAdSlide(videoIndex),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.arrow_forward_ios,
                      color: Colors.white,
                      size: 28,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // **NEW: Top left back button for better visibility**
          Positioned(
            top: 50,
            left: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _navigateBackToVideo(videoIndex),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.8),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(
                      Icons.arrow_back_ios,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'Back to Video',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
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
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final screenAspectRatio =
              constraints.maxWidth / constraints.maxHeight;
          final videoAspectRatio = controller.value.aspectRatio;

          if (videoAspectRatio > screenAspectRatio) {
            // Video is wider - fit to width
            return Center(
              child: AspectRatio(
                aspectRatio: videoAspectRatio,
                child: VideoPlayer(controller),
              ),
            );
          } else {
            // Video is taller - fit to height
            return Center(
              child: SizedBox(
                width: constraints.maxHeight * videoAspectRatio,
                height: constraints.maxHeight,
                child: VideoPlayer(controller),
              ),
            );
          }
        },
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
      color: Colors.black, // Ensure black background
      child: video.thumbnailUrl.isNotEmpty
          ? Center(
              child: Image.network(
                video.thumbnailUrl,
                fit: BoxFit.contain, // Use contain to maintain aspect ratio
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

  /// **BUILD VIDEO OVERLAY: Instagram-style UI with vertical action buttons**
  Widget _buildVideoOverlay(VideoModel video, int index) {
    return Stack(
      children: [
        // Bottom info section
        Positioned(
          bottom: 0,
          left: 0,
          right: 80, // Leave space for vertical action buttons
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.7),
                ],
              ),
            ),
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
                    const SizedBox(width: 8),
                    // Professional follow/unfollow button
                    _buildFollowTextButton(video),
                  ],
                ),
                const SizedBox(height: 16),

                // Visit Now button (if link exists)
                if (video.link?.isNotEmpty == true)
                  GestureDetector(
                    onTap: () => _handleVisitNow(video),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[700],
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Visit Now',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
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

              _buildVerticalActionButton(
                icon: Icons.arrow_forward_ios,
                onTap: () => _navigateToCarouselAd(index),
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

  /// **HANDLE LIKE: With API integration**
  Future<void> _handleLike(VideoModel video, int index) async {
    if (_currentUserId == null) {
      _showSnackBar('Please sign in to like videos', isError: true);
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

  /// **BUILD FOLLOW TEXT BUTTON: Professional text-only follow/unfollow button**
  Widget _buildFollowTextButton(VideoModel video) {
    // Don't show follow button for own videos
    if (_currentUserId == null || video.uploader.id == _currentUserId) {
      return const SizedBox.shrink();
    }

    final isFollowing = _isFollowing(video.uploader.id);

    return GestureDetector(
      onTap: () => _handleFollow(video),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isFollowing
              ? Colors.white.withOpacity(0.2)
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isFollowing
                ? Colors.white.withOpacity(0.4)
                : Colors.white.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Text(
          isFollowing ? 'Following' : 'Follow',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
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
      _showSnackBar('Please sign in to follow users', isError: true);
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

  /// **NAVIGATE TO CAROUSEL AD**
  void _navigateToCarouselAd(int videoIndex) {
    setState(() {
      _horizontalIndices[videoIndex] = 1; // Switch to carousel ad page
    });
  }

  /// **NAVIGATE BACK TO VIDEO**
  void _navigateBackToVideo(int videoIndex) {
    setState(() {
      _horizontalIndices[videoIndex] = 0; // Switch back to video page
    });
  }

  /// **NAVIGATE TO NEXT AD SLIDE**
  void _navigateToNextAdSlide(int videoIndex) {
    final carouselAd = _carouselAdManager.getCarouselAdForIndex(videoIndex);
    if (carouselAd != null && carouselAd.slides.length > 1) {
      final horizontalController = _horizontalPageControllers[videoIndex];
      if (horizontalController != null && horizontalController.hasClients) {
        final currentSlide = horizontalController.page?.round() ?? 0;
        final nextSlide = (currentSlide + 1) % carouselAd.slides.length;
        horizontalController.animateToPage(
          nextSlide,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    }
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

  @override
  void dispose() {
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

    // Clean up horizontal page controllers
    for (final controller in _horizontalPageControllers.values) {
      controller.dispose();
    }
    _horizontalPageControllers.clear();

    // Cancel timers
    _preloadTimer?.cancel();

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
