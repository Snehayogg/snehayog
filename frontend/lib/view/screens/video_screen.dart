import 'dart:async';
import 'package:flutter/material.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:share_plus/share_plus.dart';
import 'package:snehayog/view/screens/profile_screen.dart';
import 'package:snehayog/core/managers/video_controller_manager.dart';
import 'package:snehayog/core/managers/video_cache_manager.dart';
import 'package:snehayog/view/widget/video_item_widget.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:url_launcher/url_launcher.dart';

class VideoScreen extends StatefulWidget {
  final int? initialIndex;
  final List<VideoModel>? initialVideos;

  const VideoScreen({Key? key, this.initialIndex, this.initialVideos})
      : super(key: key);

  @override
  _VideoScreenState createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen>
    with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Core managers
  late VideoControllerManager _controllerManager;
  late VideoCacheManager _videoCacheManager;
  late VideoService _videoService;
  late AuthService _authService;

  // State management
  List<VideoModel> _videos = [];
  int _currentIndex = 0;
  bool _isLoading = true;
  bool _isRefreshing = false;
  bool _hasMore = true;
  int _page = 1;
  final int _limit = 10;

  // **NEW: Enhanced loading states for better user feedback**
  Map<int, bool> _videoLoadingStates = {}; // Track loading state for each video
  bool _isInitializingVideo =
      false; // Track if current video is being initialized
  bool _isPreloadingVideos = false; // Track if videos are being preloaded
  String _loadingMessage = 'Loading videos...'; // Dynamic loading message
  double _loadingProgress = 0.0; // Loading progress indicator

  // **NEW: Caching and state management**
  static List<VideoModel> _cachedVideos =
      []; // **NEW: Static cache for all instances**
  static bool _isVideosCached =
      false; // **NEW: Track if videos are already cached**
  static DateTime?
      _lastCacheTime; // **NEW: Track when videos were last cached**
  static const Duration _cacheValidDuration =
      Duration(minutes: 5); // **NEW: Cache validity duration**

  // UI controllers
  late PageController _pageController;
  Timer? _preloadTimer;
  Timer? _cacheTimer;

  // Ad management
  BannerAd? _bannerAd;
  final bool _isBannerAdLoaded = false;

  // **NEW: Video Management Service**
  // late VideoManagementService _videoManagementService; // REMOVED

  @override
  void initState() {
    super.initState();
    _initializeManagers();
    _initializePageController();
    _loadInitialVideos();
    WidgetsBinding.instance.addObserver(this);

    // **NEW: Initialize Video Management Service** // REMOVED
    // _videoManagementService = VideoManagementService( // REMOVED
    //   onVideoStarted: (index) { // REMOVED
    //     print('🎬 VideoScreen: Video started at index $index'); // REMOVED
    //   }, // REMOVED
    //   onVideoPaused: (index) { // REMOVED
    //     print('⏸️ VideoScreen: Video paused at index $index'); // REMOVED
    //   }, // REMOVED
    //   onError: (error) { // REMOVED
    //     print('❌ VideoScreen: Video error: $error'); // REMOVED
    //     if (mounted) { // REMOVED
    //       ScaffoldMessenger.of(context).showSnackBar( // REMOVED
    //         SnackBar( // REMOVED
    //           content: Text('Video error: $error'), // REMOVED
    //           backgroundColor: Colors.red, // REMOVED
    //         ), // REMOVED
    //       ); // REMOVED
    //     } // REMOVED
    //   }, // REMOVED
    // ); // REMOVED
  }

  void _initializeManagers() {
    _controllerManager = VideoControllerManager();
    _videoCacheManager = VideoCacheManager();
    _videoService = VideoService();
    _authService = AuthService();
  }

  /// **NEW: Initialize video at specific index - Fixed for proper video display**
  Future<void> _initializeVideoAtIndex(int index) async {
    // **FIXED: Add guard clause to prevent infinite loops**
    if (index < 0 || index >= _videos.length) {
      print('⚠️ VideoScreen: Invalid index for video initialization: $index');
      return;
    }

    // **FIXED: Check if this is still the current video before proceeding**
    if (_currentIndex != index) {
      print(
          '⚠️ VideoScreen: Video $index is no longer current, skipping initialization');
      return;
    }

    try {
      // **NEW: Show loading indicator for this video**
      _showVideoLoading(index);

      // **NEW: Set initializing state**
      if (mounted) {
        setState(() {
          _isInitializingVideo = true;
        });
      }

      final video = _videos[index];
      print(
          '🔄 VideoScreen: Initializing video at index $index: ${video.videoName}');

      // **NEW: Dispose all other video controllers first**
      await _disposeOtherVideoControllers(index);

      // **NEW: Initialize only the current video controller**
      await _controllerManager.initController(index, video);

      // **NEW: Wait for initialization to complete**
      await Future.delayed(const Duration(milliseconds: 300));

      // **NEW: Hide loading indicator and show success**
      _hideVideoLoading(index);

      // **NEW: Clear initializing state**
      if (mounted) {
        setState(() {
          _isInitializingVideo = false;
        });
      }

      print('✅ VideoScreen: Video initialized successfully at index $index');
    } catch (e) {
      print('❌ VideoScreen: Error initializing video at index $index: $e');
      // **NEW: Hide loading indicator on error**
      _hideVideoLoading(index);

      // **NEW: Clear initializing state on error**
      if (mounted) {
        setState(() {
          _isInitializingVideo = false;
        });
      }
    }
  }

  /// **NEW: Dispose all video controllers except the current one - FIXED to prevent infinite loops**
  Future<void> _disposeOtherVideoControllers(int currentIndex) async {
    // **FIXED: Add guard clause to prevent infinite loops**
    if (currentIndex < 0 || currentIndex >= _videos.length || _videos.isEmpty) {
      print(
          '⚠️ VideoScreen: Invalid index for disposing other controllers: $currentIndex');
      return;
    }

    try {
      print('🧹 VideoScreen: Disposing other video controllers...');

      for (int i = 0; i < _videos.length; i++) {
        if (i != currentIndex) {
          final controller = _controllerManager.getController(i);
          if (controller != null) {
            try {
              // **NEW: Pause first, then dispose for smooth transition**
              if (controller.value.isInitialized &&
                  !controller.value.hasError) {
                await controller.pause();
              }
              await _controllerManager.disposeController(i);
              print('🧹 VideoScreen: Disposed controller for video $i');
            } catch (e) {
              print(
                  '⚠️ VideoScreen: Error disposing controller for video $i: $e');
            }
          }
        }
      }

      print('✅ VideoScreen: Other video controllers disposed successfully');
    } catch (e) {
      print('❌ VideoScreen: Error disposing other controllers: $e');
    }
  }

  /// **NEW: Handle page change with proper video management - Fixed for Audio-Video Sync**
  void _onPageChanged(int index) async {
    print('🔄 VideoScreen: Page changed to index $index');

    // **FIXED: Prevent processing if index is invalid or same as current**
    if (index < 0 || index >= _videos.length || index == _currentIndex) {
      print(
          '⚠️ VideoScreen: Invalid page change request, skipping: index=$index, currentIndex=$_currentIndex');
      return;
    }

    // **NEW: Store previous index before updating**
    final previousIndex = _currentIndex;

    // Update current index
    setState(() {
      _currentIndex = index;
    });

    try {
      // **NEW: Pause and dispose previous video for smooth transition**
      if (previousIndex != index && previousIndex < _videos.length) {
        await _pauseAndDisposeVideo(previousIndex);
      }

      // **NEW: Initialize new video with proper audio-video sync**
      await _initializeVideoAtIndex(index);

      // **RESTORED: Auto-play new video when scrolled to**
      Future.delayed(const Duration(milliseconds: 200), () {
        if (mounted && _currentIndex == index) {
          _playVideoWithSync(index);
        }
      });

      print('✅ VideoScreen: Page change completed successfully');
    } catch (e) {
      print('❌ VideoScreen: Error during page change: $e');
    }
  }

  /// **NEW: Pause and dispose video for smooth transition - FIXED to prevent infinite loops**
  Future<void> _pauseAndDisposeVideo(int index) async {
    // **FIXED: Add guard clause to prevent infinite loops**
    if (index < 0 || index >= _videos.length || _videos.isEmpty) {
      print(
          '⚠️ VideoScreen: Invalid index for pausing/disposing video: $index');
      return;
    }

    try {
      final controller = _controllerManager.getController(index);
      if (controller != null) {
        // **NEW: Pause first to stop audio**
        if (controller.value.isInitialized && !controller.value.hasError) {
          await controller.pause();
          print('⏸️ Paused video at index $index');
        }

        // **NEW: Then dispose to free memory**
        await _controllerManager.disposeController(index);
        print('🧹 Disposed video controller at index $index');
      }
    } catch (e) {
      print('❌ Error pausing/disposing video at index $index: $e');
    }
  }

  /// **NEW: Play video with audio-video sync check - FIXED to prevent infinite loops**
  void _playVideoWithSync(int index) {
    try {
      final controller = _controllerManager.getController(index);
      if (controller != null &&
          controller.value.isInitialized &&
          !controller.value.hasError) {
        // **FIXED: Ensure audio and video are ready before playing**
        if (controller.value.duration.inMilliseconds > 0) {
          controller.play();
          print('▶️ Playing video at index $index with audio-video sync');
        } else {
          print('⚠️ VideoScreen: Video duration not ready, waiting...');
          // **FIXED: Only retry once to prevent infinite loops**
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted && _currentIndex == index) {
              // **FIXED: Check if this is still the current video before retrying**
              final currentController = _controllerManager.getController(index);
              if (currentController != null &&
                  currentController.value.isInitialized &&
                  !currentController.value.hasError &&
                  currentController.value.duration.inMilliseconds > 0) {
                currentController.play();
                print('▶️ Playing video at index $index after delay');
              } else {
                print(
                    '⚠️ VideoScreen: Video still not ready after delay, skipping playback');
              }
            }
          });
        }
      } else {
        print(
            '⚠️ VideoScreen: Controller not ready for video $index, attempting to initialize...');
        // **FIXED: Only initialize once to prevent infinite loops**
        _initializeVideoAtIndex(index).then((_) {
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted && _currentIndex == index) {
              // **FIXED: Check if controller is ready after initialization before playing**
              final finalController = _controllerManager.getController(index);
              if (finalController != null &&
                  finalController.value.isInitialized &&
                  !finalController.value.hasError &&
                  finalController.value.duration.inMilliseconds > 0) {
                finalController.play();
                print('▶️ Playing video at index $index after initialization');
              } else {
                print(
                    '⚠️ VideoScreen: Controller not ready after initialization, skipping playback');
              }
            }
          });
        });
      }
    } catch (e) {
      print('❌ Error playing video with sync: $e');
    }
  }

  void _initializePageController() {
    _pageController = PageController(
      initialPage: widget.initialIndex ?? 0,
      viewportFraction: 1.0,
    );
  }

  /// **NEW: Check if cached videos are still valid**
  bool _isCacheValid() {
    if (_lastCacheTime == null) return false;
    return DateTime.now().difference(_lastCacheTime!) < _cacheValidDuration;
  }

  /// **NEW: Load videos with caching - FIXED to prevent infinite loops**
  Future<void> _loadInitialVideos() async {
    try {
      // **NEW: Show initial loading progress**
      _updateLoadingProgress('Checking for cached videos...', 0.1);

      // **NEW: Check if we have valid cached videos**
      if (_isVideosCached && _isCacheValid() && _cachedVideos.isNotEmpty) {
        print(
            '📦 VideoScreen: Using cached videos (${_cachedVideos.length} videos)');
        _updateLoadingProgress('Using cached videos...', 0.8);

        if (mounted) {
          setState(() {
            _videos = List.from(_cachedVideos);
            _isLoading = false;
          });
        }

        // **NEW: Initialize video management service with cached videos** // REMOVED
        // _initializeVideosInService(); // REMOVED
        _updateLoadingProgress('Videos ready!', 1.0);
        return;
      }

      _updateLoadingProgress('Loading first batch of videos...', 0.2);
      print('🔄 VideoScreen: Loading first batch of videos...');

      final response = await _videoService.getVideos(
          page: 1, limit: 3); // Load only 3 videos first

      _updateLoadingProgress('Processing video data...', 0.5);

      if (response['videos'] != null) {
        final List<dynamic> videosData = response['videos'];
        final List<VideoModel> newVideos = [];

        // **FIXED: Handle VideoModel objects returned by service**
        for (final videoData in videosData) {
          try {
            if (videoData is VideoModel) {
              // Video service already converted JSON to VideoModel objects
              newVideos.add(videoData);
              print(
                  '✅ VideoScreen: Video is already VideoModel: ${videoData.videoName}');
            } else {
              print(
                  '⚠️ VideoScreen: Unexpected video data type: ${videoData.runtimeType}');
              // Skip unexpected types
            }
          } catch (parseError) {
            print('❌ VideoScreen: Error processing video: $parseError');
            print('❌ VideoScreen: Video data: $videoData');
            // Continue with other videos instead of failing completely
          }
        }

        if (newVideos.isNotEmpty) {
          _updateLoadingProgress('Initializing video players...', 0.7);

          if (mounted) {
            setState(() {
              _videos = newVideos;
              _isLoading = false;
            });
          }

          // **NEW: Cache the videos**
          _cacheVideos(newVideos);

          // **NEW: Initialize videos properly**
          _initializeVideosProperly();

          // **NEW: Load remaining videos in background**
          _loadRemainingVideosInBackground();

          _updateLoadingProgress('Videos ready!', 1.0);
        } else {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
          print('⚠️ VideoScreen: No valid videos could be parsed');
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
        print('⚠️ VideoScreen: No videos in response');
      }
    } catch (e) {
      print('❌ Error loading initial videos: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// **NEW: Cache videos for reuse**
  void _cacheVideos(List<VideoModel> videos) {
    _cachedVideos = List.from(videos);
    _isVideosCached = true;
    _lastCacheTime = DateTime.now();
    print('💾 VideoScreen: Cached ${videos.length} videos');
  }

  /// **NEW: Initialize videos in VideoManagementService** // REMOVED
  void _initializeVideosInService() {
    for (int i = 0; i < _videos.length; i++) {
      // _videoManagementService.initializeVideo(i, _videos[i].videoUrl); // REMOVED
    }
  }

  /// **NEW: Initialize videos properly - Fixed for video display**
  void _initializeVideosProperly() {
    print(
        '🔄 VideoScreen: Initializing only first video for better performance...');

    // **NEW: Only initialize the first video, not all videos**
    if (_videos.isNotEmpty) {
      _initializeVideoAtIndex(0);

      // **RESTORED: Auto-play first video when app opens**
      Future.delayed(const Duration(milliseconds: 800), () {
        if (mounted && _currentIndex == 0) {
          _playVideoWithSync(0);
        }
      });
    }
  }

  /// **NEW: Load remaining videos in background - FIXED to prevent infinite loops**
  Future<void> _loadRemainingVideosInBackground() async {
    try {
      print('🔄 VideoScreen: Loading remaining videos in background...');

      final response = await _videoService.getVideos(page: 1, limit: _limit);

      if (response['videos'] != null) {
        final List<dynamic> videosData = response['videos'];
        final List<VideoModel> allVideos = [];

        // **FIXED: Handle VideoModel objects returned by service**
        for (final videoData in videosData) {
          try {
            if (videoData is VideoModel) {
              // Video service already converted JSON to VideoModel objects
              allVideos.add(videoData);
              print(
                  '✅ VideoScreen: Video is already VideoModel: ${videoData.videoName}');
            } else {
              print(
                  '⚠️ VideoScreen: Unexpected video data type: ${videoData.runtimeType}');
              // Skip unexpected types
            }
          } catch (parseError) {
            print('❌ VideoScreen: Error processing video: $parseError');
            print('❌ VideoScreen: Video data: $videoData');
            // Continue with other videos instead of failing completely
          }
        }

        if (allVideos.isNotEmpty) {
          if (mounted) {
            setState(() {
              _videos = allVideos;
            });
          }

          // **NEW: Update cache with all videos**
          _cacheVideos(allVideos);

          // **NEW: Initialize all videos in service** // REMOVED
          // _initializeVideosInService(); // REMOVED

          print(
              '✅ VideoScreen: Loaded ${allVideos.length} videos in background');
        } else {
          print(
              '⚠️ VideoScreen: No valid videos could be parsed from remaining videos');
        }
      }
    } catch (e) {
      print('❌ Error loading remaining videos: $e');
    }
  }

  Future<void> _preloadAllVideos(List<VideoModel> videos) async {
    // **FIXED: Add guard clause to prevent infinite loops**
    if (videos.isEmpty) {
      print('⚠️ VideoScreen: No videos to preload');
      return;
    }

    try {
      print('🔄 VideoScreen: Preloading all videos for smooth scrolling...');

      // Preload videos in batches to avoid blocking
      for (int i = 0; i < videos.length; i += 3) {
        final batch = videos.skip(i).take(3).toList();

        for (final video in batch) {
          try {
            final index = videos.indexOf(video);
            if (index >= 0 && index < videos.length) {
              await _controllerManager.initController(index, video);
              print(
                  '✅ VideoScreen: Preloaded video $index: ${video.videoName}');
            }
          } catch (e) {
            print('⚠️ Error preloading video ${video.videoName}: $e');
          }
        }

        // Small delay between batches to keep UI responsive
        await Future.delayed(const Duration(milliseconds: 100));
      }

      print('✅ VideoScreen: All videos preloaded successfully');
    } catch (e) {
      print('❌ Error preloading all videos: $e');
    }
  }

  Future<void> _loadVideosFromService() async {
    try {
      final response =
          await _videoService.getVideos(page: _page, limit: _limit);

      if (response['videos'] != null) {
        final videosJson = response['videos'] as List<dynamic>;
        final List<VideoModel> videos = [];

        // Parse each video with error handling
        for (int i = 0; i < videosJson.length; i++) {
          try {
            final videoJson = videosJson[i];
            print('🔍 VideoScreen: Parsing video $i: ${videoJson.runtimeType}');

            if (videoJson is VideoModel) {
              // Video service already converted JSON to VideoModel objects
              videos.add(videoJson);
              print(
                  '✅ VideoScreen: Video $i is already VideoModel: ${videoJson.videoName}');
            } else {
              print(
                  '⚠️ VideoScreen: Skipping video $i - unexpected type: ${videoJson.runtimeType}');
              // Skip unexpected types
            }
          } catch (parseError) {
            print('❌ VideoScreen: Error processing video $i: $parseError');
            print('❌ VideoScreen: Video data: ${videosJson[i]}');
            // Continue with other videos instead of failing completely
          }
        }

        if (videos.isNotEmpty) {
          setState(() {
            _videos = videos;
            _hasMore = response['hasMore'] ?? false;
          });

          // Cache videos for faster loading
          _cacheVideos(videos);

          print('✅ VideoScreen: Successfully loaded ${videos.length} videos');
        } else {
          print(
              '⚠️ VideoScreen: No valid videos could be parsed from response');
          if (mounted) {
            _showErrorSnackBar('No valid videos found in response');
          }
        }
      } else {
        print('⚠️ VideoScreen: No videos field in response');
        if (mounted) {
          _showErrorSnackBar('Invalid response format from server');
        }
      }
    } catch (e) {
      print('❌ Error loading videos from service: $e');

      // Provide more specific error messages
      if (mounted) {
        if (e.toString().contains('TimeoutException')) {
          _showErrorSnackBar(
              'Request timed out. Please check your connection and try again.');
        } else if (e.toString().contains('SocketException')) {
          _showErrorSnackBar(
              'Cannot connect to server. Please check if the backend is running.');
        } else {
          _showErrorSnackBar('Failed to load videos: $e');
        }
      }

      rethrow;
    }
  }

  Future<void> _loadVideosWithRetry({int maxRetries = 3}) async {
    int retryCount = 0;

    while (retryCount < maxRetries) {
      try {
        print('🔄 VideoScreen: Attempt ${retryCount + 1} to load videos...');
        await _loadVideosFromService();

        if (_videos.isNotEmpty) {
          print(
              '✅ VideoScreen: Successfully loaded videos on attempt ${retryCount + 1}');
          return; // Success, exit retry loop
        }

        // If no videos but no error, wait before retry
        if (retryCount < maxRetries - 1) {
          print('⚠️ VideoScreen: No videos returned, waiting before retry...');
          await Future.delayed(
              Duration(seconds: (retryCount + 1) * 2)); // Exponential backoff
        }
      } catch (e) {
        retryCount++;
        print('❌ VideoScreen: Attempt $retryCount failed: $e');

        if (retryCount >= maxRetries) {
          print('❌ VideoScreen: All retry attempts failed');
          rethrow; // Re-throw the last error
        }

        // Wait before retry with exponential backoff
        final waitTime = Duration(seconds: (retryCount + 1) * 2);
        print(
            '⏳ VideoScreen: Waiting ${waitTime.inSeconds} seconds before retry...');
        await Future.delayed(waitTime);
      }
    }
  }

  Future<void> _cacheNextVideos() async {
    try {
      final nextIndex = _currentIndex + 1;
      // **FIXED: Add guard clause to prevent infinite loops**
      if (nextIndex < _videos.length && _videos.isNotEmpty) {
        // Use preloading instead of non-existent cacheVideo method
        await _videoCacheManager
            .preloadVideosForInstantStart([_videos[nextIndex]]);
        print('✅ Preloaded video at index $nextIndex');
      }
    } catch (e) {
      print('⚠️ Error preloading video: $e');
    }
  }

  void _onVideoPageChanged(int newIndex) {
    // **FIXED: Add more strict validation to prevent infinite loops**
    if (newIndex == _currentIndex ||
        newIndex < 0 ||
        newIndex >= _videos.length ||
        _videos.isEmpty) {
      print(
          '⚠️ VideoScreen: Invalid page change request, skipping: newIndex=$newIndex, currentIndex=$_currentIndex, videosLength=${_videos.length}');
      return;
    }

    final oldIndex = _currentIndex;
    _currentIndex = newIndex;

    print('🔄 VideoScreen: Page changed from $oldIndex to $newIndex');

    // **NEW: Detect scroll direction and handle accordingly**
    if (newIndex > oldIndex) {
      // Forward scrolling
      _controllerManager.onForwardScroll(newIndex);
    } else {
      // Backward scrolling
      _controllerManager.onBackwardScroll(newIndex);
    }

    // Pause old video
    _pauseVideo(oldIndex);

    // Initialize and play new video with better error handling
    _initializeAndPlayVideo(newIndex);

    // **IMPROVED: Preload videos in both directions for smooth scrolling**
    _preloadVideosForSmoothScrolling(newIndex);

    // Load more videos if needed
    if (newIndex >= _videos.length - 2 && _hasMore) {
      _loadMoreVideos();
    }
  }

  /// **IMPROVED: Preload videos in both directions for smooth scrolling - ONE AT A TIME**
  void _preloadVideosForSmoothScrolling(int currentIndex) {
    // **FIXED: Add guard clause to prevent infinite loops**
    if (currentIndex < 0 || currentIndex >= _videos.length || _videos.isEmpty) {
      print(
          '⚠️ VideoScreen: Invalid index for smooth scrolling preload: $currentIndex');
      return;
    }

    // **NEW: Use sequential loading queue instead of parallel loading**
    _addToPreloadQueue(currentIndex);
  }

  Future<void> _initializeAndPlayVideo(int index) async {
    // **FIXED: Add guard clause to prevent infinite loops**
    if (index < 0 || index >= _videos.length || _videos.isEmpty) {
      print('⚠️ VideoScreen: Invalid index for video initialization: $index');
      return;
    }

    // **FIXED: Check if this is still the current video before proceeding**
    if (_currentIndex != index) {
      print(
          '⚠️ VideoScreen: Video $index is no longer current, skipping initialization');
      return;
    }

    try {
      final video = _videos[index];
      final controller = _controllerManager.getController(index);

      // **FIXED: Only initialize if controller is missing or has errors**
      if (controller == null || controller.value.hasError) {
        print('🔄 VideoScreen: Initializing controller for video $index');

        // **FIXED: Only dispose if controller has errors, not if it's just not initialized**
        if (controller != null && controller.value.hasError) {
          print(
              '⚠️ VideoScreen: Disposing corrupted controller for video $index');
          try {
            await _controllerManager.disposeController(index);
          } catch (e) {
            print('⚠️ VideoScreen: Error disposing corrupted controller: $e');
          }
        }

        // **FIXED: Initialize with retry limit**
        await _initializeControllerWithRetry(index, video);

        // **FIXED: Get the newly initialized controller**
        final newController = _controllerManager.getController(index);
        if (newController == null) {
          throw Exception('Controller initialization failed for video $index');
        }
      }

      // **RESTORED: Auto-play videos when initialized**
      final finalController = _controllerManager.getController(index);
      if (finalController != null &&
          finalController.value.isInitialized &&
          !finalController.value.hasError) {
        _playVideo(index); // RESTORED: Auto-play videos
        print('✅ VideoScreen: Successfully playing video $index');
      } else {
        print(
            '⚠️ VideoScreen: Controller not ready for video $index, attempting recovery...');
        // **FIXED: Try to recover the controller instead of skipping**
        await _recoverVideoWithRetryLimit(index);
      }

      // Preload adjacent videos for smooth scrolling
      _preloadAdjacentVideos(index);
    } catch (e) {
      print('❌ Error initializing video $index: $e');

      // **IMPROVED: Show user-friendly error message**
      if (mounted) {
        _showErrorSnackBar('Failed to load video. Please try again.');
      }

      // **IMPROVED: Attempt to recover with retry limit**
      await _recoverVideoWithRetryLimit(index);
    }
  }

  /// **NEW: Initialize controller with retry limit to prevent infinite loops - FIXED**
  Future<void> _initializeControllerWithRetry(
      int index, VideoModel video) async {
    int retryCount = 0;
    const maxRetries = 2; // **FIXED: Limit retries to prevent infinite loops**

    while (retryCount <= maxRetries) {
      try {
        print(
            '🔄 VideoScreen: Attempt ${retryCount + 1} to initialize controller for video $index');

        await _controllerManager.initController(index, video);

        // Wait for initialization to complete
        await Future.delayed(const Duration(milliseconds: 300));

        // Check if initialization was successful
        final controller = _controllerManager.getController(index);
        if (controller != null &&
            controller.value.isInitialized &&
            !controller.value.hasError) {
          print(
              '✅ VideoScreen: Successfully initialized controller for video $index');
          return; // Success, exit retry loop
        }

        retryCount++;
        if (retryCount <= maxRetries) {
          print(
              '⚠️ VideoScreen: Controller not ready, retrying in 1 second...');
          await Future.delayed(const Duration(seconds: 1));
        } else {
          print(
              '⚠️ VideoScreen: Max retries reached, giving up on video $index');
          break; // **FIXED: Break out of loop when max retries reached**
        }
      } catch (e) {
        retryCount++;
        print('❌ VideoScreen: Attempt $retryCount failed for video $index: $e');

        if (retryCount > maxRetries) {
          print(
              '❌ VideoScreen: Max retries reached, giving up on video $index');
          break; // **FIXED: Break out of loop when max retries reached**
        }

        // Wait before retry
        await Future.delayed(const Duration(seconds: 1));
      }
    }

    // **FIXED: Throw exception if all retries failed**
    if (retryCount > maxRetries) {
      throw Exception(
          'Failed to initialize controller after $maxRetries attempts for video $index');
    }
  }

  /// **FIXED: Less strict controller health check to prevent unnecessary disposal**
  bool _isControllerHealthy(int index) {
    try {
      final controller = _controllerManager.getController(index);
      if (controller == null) return false;

      // **FIXED: Only check essential properties, not dimensions**
      return controller.value.isInitialized && !controller.value.hasError;
    } catch (e) {
      print(
          '❌ VideoScreen: Error checking controller health for index $index: $e');
      return false;
    }
  }

  /// **IMPROVED: Recover video with retry limit - FIXED to prevent infinite loops**
  Future<void> _recoverVideoWithRetryLimit(int index) async {
    try {
      print('🔄 VideoScreen: Attempting to recover video $index...');

      // Dispose the problematic controller
      await _controllerManager.disposeController(index);

      // Wait for cleanup
      await Future.delayed(const Duration(milliseconds: 1000));

      // **FIXED: Only try to reinitialize if this is still the current video**
      if (index < _videos.length && _currentIndex == index) {
        print('🔄 VideoScreen: Reinitializing recovered video $index');
        await _initializeControllerWithRetry(index, _videos[index]);
      } else {
        print(
            '⚠️ VideoScreen: Video $index is no longer current, skipping recovery');
      }
    } catch (e) {
      print('❌ VideoScreen: Recovery failed for video $index: $e');
      // Don't retry again to prevent infinite loops
    }
  }

  void _preloadAdjacentVideos(int currentIndex) {
    // **FIXED: Add guard clause to prevent infinite loops**
    if (currentIndex < 0 || currentIndex >= _videos.length || _videos.isEmpty) {
      print(
          '⚠️ VideoScreen: Invalid index for adjacent video preloading: $currentIndex');
      return;
    }

    // **IMPROVED: Use sequential loading for adjacent videos too**
    _addToPreloadQueue(currentIndex);
  }

  /// **NEW: Sequential preloading queue to load videos one at a time**
  final List<int> _preloadQueue = [];
  bool _isProcessingPreloadQueue = false;

  void _addToPreloadQueue(int currentIndex) {
    // **FIXED: Add guard clause to prevent infinite loops**
    if (currentIndex < 0 || currentIndex >= _videos.length || _videos.isEmpty) {
      print('⚠️ VideoScreen: Invalid index for preload queue: $currentIndex');
      return;
    }

    // Add videos to queue in priority order (closest first)
    final videosToPreload = <int>[];

    // Add adjacent videos first (highest priority)
    if (currentIndex > 0) {
      videosToPreload.add(currentIndex - 1); // Previous
    }
    if (currentIndex < _videos.length - 1) {
      videosToPreload.add(currentIndex + 1); // Next
    }

    // Add videos 2 positions away (lower priority)
    if (currentIndex > 1) {
      videosToPreload.add(currentIndex - 2);
    }
    if (currentIndex < _videos.length - 2) {
      videosToPreload.add(currentIndex + 2);
    }

    // Add to queue if not already there
    for (final index in videosToPreload) {
      if (!_preloadQueue.contains(index) && !_isVideoAlreadyPreloaded(index)) {
        _preloadQueue.add(index);
        print('📋 VideoScreen: Added video $index to preload queue');
      }
    }

    // Start processing queue if not already running
    if (!_isProcessingPreloadQueue) {
      _processPreloadQueue();
    }
  }

  /// **NEW: Check if video is already preloaded - FIXED to prevent infinite loops**
  bool _isVideoAlreadyPreloaded(int index) {
    // **FIXED: Add guard clause to prevent infinite loops**
    if (index < 0 || index >= _videos.length || _videos.isEmpty) {
      return false;
    }

    final controller = _controllerManager.getController(index);
    return controller != null && controller.value.isInitialized;
  }

  /// **NEW: Process preload queue sequentially - ONE VIDEO AT A TIME**
  Future<void> _processPreloadQueue() async {
    if (_isProcessingPreloadQueue || _preloadQueue.isEmpty) {
      return;
    }

    _isProcessingPreloadQueue = true;
    _showPreloadingIndicator(); // **NEW: Show preloading indicator**
    print('🔄 VideoScreen: Starting sequential preload queue processing...');

    try {
      while (_preloadQueue.isNotEmpty && mounted) {
        final index = _preloadQueue.removeAt(0);

        // **FIXED: Add validation to prevent infinite loops**
        if (index < 0 || index >= _videos.length || _videos.isEmpty) {
          print(
              '⚠️ VideoScreen: Invalid index in preload queue, skipping: $index');
          continue;
        }

        // Skip if video is already preloaded
        if (_isVideoAlreadyPreloaded(index)) {
          print('⏭️ VideoScreen: Skipping already preloaded video $index');
          continue;
        }

        try {
          // **NEW: Update loading message for current preload**
          _updateLoadingProgress('Preloading video ${index + 1}...', 0.3);

          print(
              '🔄 VideoScreen: Preloading video $index (${_preloadQueue.length} remaining in queue)');
          await _preloadVideoAtIndex(index);

          // **NEW: Small delay between preloads to prevent overwhelming the system**
          await Future.delayed(const Duration(milliseconds: 200));
        } catch (e) {
          print('⚠️ VideoScreen: Error preloading video $index: $e');
          // Continue with next video instead of stopping the queue
        }
      }
    } finally {
      _isProcessingPreloadQueue = false;
      _hidePreloadingIndicator(); // **NEW: Hide preloading indicator**
      print('✅ VideoScreen: Preload queue processing completed');
    }
  }

  Future<void> _preloadVideoAtIndex(int index) async {
    // **FIXED: Add guard clause to prevent infinite loops**
    if (index < 0 || index >= _videos.length || _videos.isEmpty) {
      print('⚠️ VideoScreen: Invalid index for video preloading: $index');
      return;
    }

    try {
      final video = _videos[index];
      final controller = _controllerManager.getController(index);

      if (controller == null || !controller.value.isInitialized) {
        print('🔄 VideoScreen: Preloading video at index $index');
        await _controllerManager.initController(index, video);
      }
    } catch (e) {
      print('⚠️ Error preloading video at index $index: $e');
    }
  }

  void _playVideo(int index) {
    // **FIXED: Add guard clause to prevent infinite loops**
    if (index < 0 || index >= _videos.length || _videos.isEmpty) {
      print('⚠️ VideoScreen: Invalid index for playing video: $index');
      return;
    }

    // **NEW: Use the sync method for better audio-video synchronization**
    _playVideoWithSync(index);
  }

  void _pauseVideo(int index) {
    // **FIXED: Add guard clause to prevent infinite loops**
    if (index < 0 || index >= _videos.length || _videos.isEmpty) {
      print('⚠️ VideoScreen: Invalid index for pausing video: $index');
      return;
    }

    // **NEW: Use the dispose method for better memory management**
    _pauseAndDisposeVideo(index);
  }

  Future<void> _loadMoreVideos() async {
    if (_isRefreshing || !_hasMore) return;

    try {
      setState(() => _isRefreshing = true);

      _page++;
      final response =
          await _videoService.getVideos(page: _page, limit: _limit);

      if (response['videos'] != null) {
        final videosJson = response['videos'] as List<dynamic>;
        final List<VideoModel> newVideos = [];

        // Parse each video with error handling (same as _loadVideosFromService)
        for (int i = 0; i < videosJson.length; i++) {
          try {
            final videoJson = videosJson[i];
            print(
                '🔍 VideoScreen: Parsing more video $i: ${videoJson.runtimeType}');

            if (videoJson is VideoModel) {
              // Video service already converted JSON to VideoModel objects
              newVideos.add(videoJson);
              print(
                  '✅ VideoScreen: Video $i is already VideoModel: ${videoJson.videoName}');
            } else {
              print(
                  '⚠️ VideoScreen: Skipping more video $i - unexpected type: ${videoJson.runtimeType}');
              // Skip unexpected types
            }
          } catch (parseError) {
            print('❌ VideoScreen: Error processing more video $i: $parseError');
            print('❌ VideoScreen: Video data: ${videosJson[i]}');
            // Continue with other videos instead of failing completely
          }
        }

        if (newVideos.isNotEmpty) {
          setState(() {
            _videos.addAll(newVideos);
            _hasMore = response['hasMore'] ?? false;
          });

          // Preload new videos
          await _videoCacheManager.preloadVideosForInstantStart(newVideos);

          print('✅ Loaded ${newVideos.length} more videos');
        } else {
          print('⚠️ VideoScreen: No valid more videos could be parsed');
          _page--; // Revert page since no valid videos were loaded
        }
      }
    } catch (e) {
      print('❌ Error loading more videos: $e');
      _page--; // Revert page on error
    } finally {
      setState(() => _isRefreshing = false);
    }
  }

  Future<void> _refreshVideos() async {
    try {
      setState(() => _isRefreshing = true);
      
      // **NEW: Show refresh loading progress**
      _updateLoadingProgress('Refreshing videos...', 0.2);

      // Clear existing videos and controllers
      _videos.clear();
      _controllerManager.disposeAll();

      // **NEW: Update progress**
      _updateLoadingProgress('Clearing cache...', 0.4);

      // **NEW: Reset video management service** // REMOVED
      // _videoManagementService.resetState(); // REMOVED

      // Load fresh videos - call the correct method
      _updateLoadingProgress('Loading fresh videos...', 0.6);
      await _loadVideosFromService();

      if (_videos.isNotEmpty) {
        // **NEW: Initialize videos properly**
        _updateLoadingProgress('Initializing video players...', 0.8);
        _initializeVideosProperly();
      }

      _updateLoadingProgress('Videos refreshed!', 1.0);

      if (mounted) {
        _showSuccessSnackBar('Videos refreshed successfully!');
      }
      
      // Clear success message after delay
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          _updateLoadingProgress('', 0.0);
        }
      });
    } catch (e) {
      print('❌ Error refreshing videos: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to refresh videos: $e');
      }
    } finally {
      setState(() => _isRefreshing = false);
    }
  }

  Future<void> _handleLike(int index) async {
    // **FIXED: Add guard clause to prevent infinite loops**
    if (index < 0 || index >= _videos.length || _videos.isEmpty) {
      print('⚠️ VideoScreen: Invalid index for like handling: $index');
      return;
    }

    try {
      final video = _videos[index];
      final userData = await _authService.getUserData();
      final userId = userData?['id'] ?? userData?['googleId'];

      if (userId == null) {
        if (mounted) {
          _showErrorSnackBar('Please sign in to like videos');
        }
        return;
      }

      // Optimistic update
      setState(() {
        if (video.likedBy.contains(userId)) {
          video.likedBy.remove(userId);
          video.likes = (video.likes - 1).clamp(0, double.infinity).toInt();
        } else {
          video.likedBy.add(userId);
          video.likes++;
        }
      });

      // API call
      await _videoService.toggleLike(video.id, userId);

      if (mounted) {
        _showSuccessSnackBar(
            video.likedBy.contains(userId) ? 'Video liked!' : 'Video unliked!');
      }
    } catch (e) {
      print('❌ Error handling like: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to update like: $e');
      }
    }
  }

  void _handleComment(VideoModel video) {
    // Show comments sheet or navigate to comments screen
    if (mounted) {
      _showSuccessSnackBar('Comments feature coming soon!');
    }
  }

  Future<void> _handleShare(VideoModel video) async {
    try {
      await Share.share(
        'Check out this video: ${video.videoName}\n\n${video.videoUrl}',
        subject: 'Snehayog Video',
      );
    } catch (e) {
      print('❌ Error sharing video: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to share video: $e');
      }
    }
  }

  Future<void> _handleProfileTap(VideoModel video) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileScreen(userId: video.uploader.id),
      ),
    );
  }

  Future<void> _handleVisitNow(VideoModel video) async {
    if (video.link == null || video.link!.isEmpty) {
      if (mounted) {
        _showErrorSnackBar('No link available for this video');
      }
      return;
    }

    try {
      final url = Uri.parse(video.link!);
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          _showErrorSnackBar('Could not open link');
        }
      }
    } catch (e) {
      print('❌ Error opening link: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to open link: $e');
      }
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        // **NEW: Pause current video when app goes to background**
        // _videoManagementService.onPageChanged(-1); // Pause all videos // REMOVED
        break;
      case AppLifecycleState.resumed:
        // **NEW: Resume video when app comes back to foreground**
        if (_videos.isNotEmpty && _currentIndex < _videos.length) {
          // _videoManagementService.onPageChanged(_currentIndex); // REMOVED
        }
        break;
      default:
        break;
    }
  }

  /// **NEW: Handle tab changes and screen visibility - Fixed for Audio-Video Sync**
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // **NEW: Check if this screen is visible and handle video state**
    final isVisible = ModalRoute.of(context)?.isCurrent ?? false;
    if (isVisible && _videos.isNotEmpty) {
      print('🔄 VideoScreen: Tab changed - screen is now visible');

      // **NEW: Initialize current video if needed**
      if (_currentIndex < _videos.length) {
        print(
            '🔄 VideoScreen: Reinitializing video at index $_currentIndex after tab change');

        // **NEW: Reinitialize video with proper delay**
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) {
            _initializeVideoAtIndex(_currentIndex).then((_) {
              // **NEW: Start video playback after initialization with sync**
              Future.delayed(const Duration(milliseconds: 200), () {
                if (mounted) {
                  _playVideoWithSync(_currentIndex);
                }
              });
            });
          }
        });
      }
    }
  }

  /// **NEW: Start video playback after tab change - FIXED to prevent infinite loops**
  Future<void> _startVideoPlaybackAfterTabChange() async {
    try {
      print('🔄 VideoScreen: Starting video playback after tab change...');

      // Wait a bit for the screen to fully render
      await Future.delayed(const Duration(milliseconds: 300));

      if (mounted && _currentIndex < _videos.length) {
        // **NEW: Check if video controller is ready**
        final controller = _controllerManager.getController(_currentIndex);
        if (controller != null &&
            controller.value.isInitialized &&
            !controller.value.hasError) {
          print('✅ VideoScreen: Controller ready, starting playback');
          _playVideo(_currentIndex); // RESTORED: Auto-play videos
        } else {
          print('⚠️ VideoScreen: Controller not ready, reinitializing...');
          // **FIXED: Only reinitialize if this is still the current video**
          if (_currentIndex < _videos.length) {
            await _reinitializeVideoController(_currentIndex);
            // **FIXED: Check if reinitialization was successful before playing**
            final finalController =
                _controllerManager.getController(_currentIndex);
            if (finalController != null &&
                finalController.value.isInitialized &&
                !finalController.value.hasError) {
              _playVideo(_currentIndex); // RESTORED: Auto-play videos
            } else {
              print(
                  '⚠️ VideoScreen: Reinitialization failed, skipping playback');
            }
          }
        }
      }
    } catch (e) {
      print('❌ VideoScreen: Error starting playback after tab change: $e');
    }
  }

  /// **NEW: Recover video playback when returning to app - FIXED to prevent infinite loops**
  Future<void> _recoverVideoPlayback() async {
    try {
      print('🔄 VideoScreen: Recovering video playback after app resume...');

      // Check if current video controller is healthy
      final currentController = _controllerManager.getController(_currentIndex);
      if (currentController == null ||
          !currentController.value.isInitialized ||
          currentController.value.hasError) {
        print(
            '⚠️ VideoScreen: Current video controller needs recovery, reinitializing...');
        await _reinitializeVideoController(_currentIndex);
      }

      // **FIXED: Check if controller is ready before playing**
      final finalController = _controllerManager.getController(_currentIndex);
      if (finalController != null &&
          finalController.value.isInitialized &&
          !finalController.value.hasError) {
        // **RESTORED: Auto-play videos when app resumes**
        _playVideo(_currentIndex); // RESTORED: Auto-play videos

        // Preload adjacent videos for smooth scrolling
        _preloadAdjacentVideos(_currentIndex);
      } else {
        print(
            '⚠️ VideoScreen: Controller not ready after recovery, skipping playback');
      }
    } catch (e) {
      print('❌ VideoScreen: Error recovering video playback: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to recover video playback');
      }
    }
  }

  /// **NEW: Reinitialize video controller with error recovery - FIXED to prevent infinite loops**
  Future<void> _reinitializeVideoController(int index) async {
    try {
      print(
          '🔄 VideoScreen: Reinitializing video controller for index $index...');

      // **FIXED: Check if this is still the current video before proceeding**
      if (_currentIndex != index) {
        print(
            '⚠️ VideoScreen: Video $index is no longer current, skipping reinitialization');
        return;
      }

      // Dispose existing controller if it has errors
      final existingController = _controllerManager.getController(index);
      if (existingController != null && existingController.value.hasError) {
        print('⚠️ VideoScreen: Disposing corrupted controller at index $index');
        try {
          await existingController.dispose();
        } catch (e) {
          print('⚠️ VideoScreen: Error disposing corrupted controller: $e');
        }
      }

      // **FIXED: Only reinitialize if this is still the current video**
      if (_currentIndex == index && index < _videos.length) {
        await _controllerManager.initController(index, _videos[index]);
        print(
            '✅ VideoScreen: Successfully reinitialized video controller for index $index');
      } else {
        print(
            '⚠️ VideoScreen: Video $index is no longer current, skipping reinitialization');
      }
    } catch (e) {
      print(
          '❌ VideoScreen: Failed to reinitialize video controller for index $index: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to load video: $e');
      }
    }
  }

  @override
  void dispose() {
    _preloadTimer?.cancel();
    _cacheTimer?.cancel();
    _pageController.dispose();
    _controllerManager.disposeAll();
    _bannerAd?.dispose();

    // **NEW: Dispose VideoManagementService** // REMOVED
    // _videoManagementService.disposeAll(); // REMOVED

    // **NEW: Clear preload queue when disposing**
    _clearPreloadQueue();

    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// **NEW: Clear preload queue to prevent unnecessary loading**
  void _clearPreloadQueue() {
    _preloadQueue.clear();
    _isProcessingPreloadQueue = false;
    print('🧹 VideoScreen: Preload queue cleared');
  }

  /// **NEW: Pause preloading when app goes to background**
  void _pausePreloading() {
    _isProcessingPreloadQueue = false;
    print('⏸️ VideoScreen: Preloading paused due to app backgrounding');
  }

  /// **NEW: Resume preloading when app comes back to foreground**
  void _resumePreloading() {
    if (_preloadQueue.isNotEmpty && !_isProcessingPreloadQueue) {
      print('▶️ VideoScreen: Resuming preloading after app foregrounding');
      _processPreloadQueue();
    }
  }

  /// **NEW: Update loading state for a specific video**
  void _updateVideoLoadingState(int index, bool isLoading) {
    if (mounted) {
      setState(() {
        _videoLoadingStates[index] = isLoading;
      });
    }
  }

  /// **NEW: Update overall loading message and progress**
  void _updateLoadingProgress(String message, double progress) {
    if (mounted) {
      setState(() {
        _loadingMessage = message;
        _loadingProgress = progress;
      });
    }
  }

  /// **NEW: Show video-specific loading indicator**
  void _showVideoLoading(int index) {
    _updateVideoLoadingState(index, true);
    _updateLoadingProgress('Loading video ${index + 1}...', 0.5);
  }

  /// **NEW: Hide video-specific loading indicator**
  void _hideVideoLoading(int index) {
    _updateVideoLoadingState(index, false);
    _updateLoadingProgress('Video ready!', 1.0);

    // Clear the message after a short delay
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        _updateLoadingProgress('', 0.0);
      }
    });
  }

  /// **NEW: Show preloading indicator**
  void _showPreloadingIndicator() {
    if (mounted) {
      setState(() {
        _isPreloadingVideos = true;
      });
    }
  }

  /// **NEW: Hide preloading indicator**
  void _hidePreloadingIndicator() {
    if (mounted) {
      setState(() {
        _isPreloadingVideos = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) {
      return _buildLoadingScreen();
    }

    if (_videos.isEmpty) {
      return _buildEmptyScreen();
    }

    return _buildVideoScreen();
  }

  Widget _buildLoadingScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // **NEW: Enhanced loading indicator with progress**
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 80,
                  height: 80,
                  child: CircularProgressIndicator(
                    value: _loadingProgress > 0 ? _loadingProgress : null,
                    color: Colors.blue,
                    strokeWidth: 4,
                    backgroundColor: Colors.grey.shade800,
                  ),
                ),
                if (_loadingProgress > 0 && _loadingProgress < 1.0)
                  Text(
                    '${(_loadingProgress * 100).toInt()}%',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),

            // **NEW: Dynamic loading message**
            Text(
              _loadingMessage,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // **NEW: Show current video count if available**
            if (_videos.isNotEmpty)
              Text(
                '${_videos.length} videos loaded',
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 16,
                ),
              ),
            const SizedBox(height: 24),

            // **NEW: Enhanced status information**
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.blue.withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  const Text(
                    '🚀 Smart Loading Enabled',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• Progressive video loading\n• Intelligent caching\n• Smooth playback experience',
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  // **NEW: Show specific loading states**
                  if (_isInitializingVideo)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: Colors.orange.withOpacity(0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.orange),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Initializing video player...',
                            style: TextStyle(
                              color: Colors.orange.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                  if (_isPreloadingVideos)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                        border:
                            Border.all(color: Colors.green.withOpacity(0.5)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.green),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Preloading videos...',
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.video_library,
              size: 64,
              color: Colors.white54,
            ),
            const SizedBox(height: 16),
            const Text(
              'No videos available',
              style: TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 8),
            const Text(
              'Pull down to refresh',
              style: TextStyle(color: Colors.white54, fontSize: 14),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _refreshVideos,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
            ),
            ElevatedButton.icon(
              onPressed: _refreshVideos, // Use the same refresh method
              icon: const Icon(Icons.replay),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoScreen() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                // Banner ad at top
                _buildBannerAd(),

                // Main video area
                Expanded(
                  child: _buildVideoPlayer(),
                ),
              ],
            ),

            // **NEW: Floating loading indicator for background operations**
            if (_isPreloadingVideos || _isInitializingVideo)
              Positioned(
                top: 80, // Below banner ad
                right: 16,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.blue.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            _isInitializingVideo ? Colors.orange : Colors.green,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isInitializingVideo
                            ? 'Initializing...'
                            : 'Preloading...',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBannerAd() {
    return Container(
      width: double.infinity,
      height: 60,
      color: Colors.white,
      child: _isBannerAdLoaded && _bannerAd != null
          ? AdWidget(ad: _bannerAd!)
          : const Center(
              child: Text(
                'Ad Space',
                style: TextStyle(color: Colors.grey),
              ),
            ),
    );
  }

  Widget _buildVideoPlayer() {
    return RefreshIndicator(
      onRefresh: _refreshVideos,
      color: Colors.blue,
      backgroundColor: Colors.white,
      child: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _videos.length + (_hasMore ? 1 : 0),
        onPageChanged:
            _onPageChanged, // **NEW: Use VideoManagementService-based page change handler**
        itemBuilder: (context, index) {
          if (index == _videos.length) {
            return _buildLoadingIndicator();
          }

          final video = _videos[index];
          final controller = _controllerManager.getController(index);
          final isActive = index == _currentIndex;
          final isLoading =
              _videoLoadingStates[index] ?? false; // **NEW: Get loading state**

          return Stack(
            children: [
              VideoItemWidget(
                key: ValueKey('video_${video.id}_$index'),
                video: video,
                controller: controller,
                isActive: isActive,
                index: index,
                onLike: () => _handleLike(index),
                onComment: () => _handleComment(video),
                onShare: () => _handleShare(video),
                onProfileTap: () => _handleProfileTap(video),
                onVisitNow: () => _handleVisitNow(video),
              ),

              // **NEW: Loading overlay for individual videos**
              if (isLoading)
                Container(
                  color: Colors.black.withOpacity(0.7),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                          strokeWidth: 3,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Loading video ${index + 1}...',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          video.videoName,
                          style: TextStyle(
                            color: Colors.grey[300],
                            fontSize: 14,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
              _videos.length < 3
                  ? 'Loading more videos...'
                  : 'Loading additional videos...',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              '${_videos.length} videos loaded so far',
              style: TextStyle(color: Colors.grey[400], fontSize: 14),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.2),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blue.withOpacity(0.5)),
              ),
              child: const Text(
                'Progressive loading in progress',
                style: TextStyle(
                  color: Colors.blue,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
