// Import statements for required Flutter and third-party packages
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/services/google_auth_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:snehayog/view/screens/profile_screen.dart';
import 'package:snehayog/controller/main_controller.dart';
import 'package:snehayog/core/managers/video_controller_manager.dart';
import 'package:snehayog/core/managers/video_cache_manager.dart';
import 'package:snehayog/core/managers/video_state_manager.dart';
import 'package:snehayog/view/widgets/video_ui_components.dart';
import 'package:snehayog/view/widgets/comments_sheet.dart';

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

  // Controller for the PageView that handles vertical scrolling
  late PageController _pageController;

  // Timer for periodic video health checks
  Timer? _healthCheckTimer;

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

      // Play new video if screen is visible
      if (_stateManager.isScreenVisible) {
        _playActiveVideo();
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
    await _stateManager.loadVideos(isInitialLoad: isInitialLoad);

    if (isInitialLoad && _stateManager.videos.isNotEmpty) {
      _initializeCurrentVideo();
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
    }
  }

  /// Handle like button
  Future<void> _handleLike(int index) async {
    String? userId; // Declare userId at the top level of the method

    try {
      print('🔍 Like Handler: Starting like process for video at index $index');

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

      final googleAuthService = GoogleAuthService();
      final userData = await googleAuthService.getUserData();

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

  /// Test API connection
  Future<void> _testApiConnection() async {
    try {
      print('🧪 VideoScreen: Testing API connection...');
      final response = await _videoService.checkServerHealth();
      print('🧪 VideoScreen: API health check result: $response');

      if (response) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('✅ API is accessible'),
              backgroundColor: Colors.green),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('❌ API is not accessible'),
              backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('❌ API test failed: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  /// Test video link field
  Future<void> _testVideoLinkField() async {
    try {
      print('🔗 VideoScreen: Testing video link field...');
      await _videoService.testVideoLinkField();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('🔗 Check console for video link field info'),
            backgroundColor: Colors.blue),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('❌ Video link test failed: $e'),
            backgroundColor: Colors.red),
      );
    }
  }

  /// Clear video cache
  Future<void> _clearVideoCache() async {
    await _cacheManager.clearVideoCache();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('✅ Video cache cleared'),
          backgroundColor: Colors.green),
    );
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
      final googleAuthService = GoogleAuthService();
      googleAuthService.getUserData().then((userData) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Column(
        children: [
          // Main video player area
          Expanded(
            child: _buildVideoPlayer(),
          ),
        ],
      ),
    );
  }

  /// Build the main video player widget with PageView for vertical scrolling
  Widget _buildVideoPlayer() {
    // Show loading indicator while initially loading videos
    if (_stateManager.isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading videos...', style: TextStyle(color: Colors.white)),
          ],
        ),
      );
    }

    // Show message if no videos are available
    if (_stateManager.videos.isEmpty) {
      return EmptyVideoStateWidget(
        onRefresh: () => _stateManager.refreshVideos(),
        onTestApi: _testApiConnection,
        onTestVideoLink: _testVideoLinkField,
        onClearCache: _clearVideoCache,
        onGetCacheInfo: _getCacheInfo,
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await _stateManager.refreshVideos();
        _controllerManager.disposeAllControllers();
        await _cacheManager.clearVideoCache();
        await _loadVideos(isInitialLoad: true);
      },
      child: VisibilityDetector(
        key: const Key('video_screen_visibility'),
        onVisibilityChanged: (visibilityInfo) {
          print(
              '👁️ VideoScreen: Visibility changed to ${visibilityInfo.visibleFraction}');
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
            }
            return false;
          },
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
                return const LoadingIndicatorWidget();
              }

              final video = _stateManager.videos[index];
              final controller = _controllerManager.getController(index);

              return VideoItemWidget(
                video: video,
                controller: controller,
                isActive: index == _stateManager.activePage,
                onLike: () => _handleLike(index),
                onComment: () => _handleComment(video),
                onShare: () => _handleShare(video),
                onProfileTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          ProfileScreen(userId: video.uploader.id),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  // Add this method to VideoScreen for debugging
  void debugVideoState() {
    print('🔍 DEBUG VIDEO STATE:');
    print('  - Screen visible: ${_stateManager.isScreenVisible}');
    print('  - Active page: ${_stateManager.activePage}');
    print('  - Total videos: ${_stateManager.videos.length}');
    print('  - Controllers count: ${_controllerManager.controllers.length}');

    // Check if any videos are still playing
    bool anyPlaying = false;
    _controllerManager.controllers.forEach((index, controller) {
      if (controller.value.isPlaying) {
        print('  - Video at index $index is STILL PLAYING!');
        anyPlaying = true;
      }
    });

    if (!anyPlaying) {
      print('  - All videos are properly paused');
    }
  }

  // Call this method when you suspect issues
  // You can add a debug button or call it from console
}
