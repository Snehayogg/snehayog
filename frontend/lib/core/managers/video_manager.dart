import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/services/instagram_video_service.dart';
import 'package:snehayog/core/managers/video_controller_manager.dart';
import 'package:snehayog/core/managers/video_cache_manager.dart';
import 'package:snehayog/core/services/video_player_config_service.dart';
import 'package:snehayog/model/video_model.dart';

/// **CONSOLIDATED VideoManager: Single manager for all video-related functionality**
/// This class consolidates:
/// - VideoStateManager (video data, pagination, loading)
/// - VideoPlayerStateManager (playback control, state management)
/// - Previous VideoManager (navigation state, tracking)
///
/// Eliminates duplication and provides a single source of truth for video operations
class VideoManager extends ChangeNotifier {
  // ===== VIDEO DATA & PAGINATION =====
  List<VideoModel> _videos = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  int _activePage = 0;

  // ===== VIDEO PLAYBACK STATE =====
  VideoPlayerController? _currentController;
  bool _isPlaying = false;
  bool _isBuffering = false;
  bool _isMuted = true;
  double _volume = 0.0;
  final bool _isHLS = false;
  final bool _showPlayPauseOverlay = false;
  final bool _isSeeking = false;

  // ===== SCREEN & NAVIGATION STATE =====
  bool _isScreenVisible = true;
  bool _isVideoScreenActive = true;
  bool _isAppInForeground = true;
  int _lastActiveTabIndex = 0;
  bool _wasOnVideoTab = true;

  // ===== ERROR STATE =====
  bool _hasError = false;
  String? _errorMessage;

  // ===== SERVICES & MANAGERS =====
  final VideoService _videoService = VideoService();
  final InstagramVideoService _instagramVideoService = InstagramVideoService();
  late VideoControllerManager _controllerManager;
  late VideoCacheManager _cacheManager;

  // ===== QUALITY CONFIGURATION =====
  late VideoQualityPreset _qualityPreset;
  late BufferingConfig _bufferingConfig;
  late PreloadingConfig _preloadingConfig;

  // ===== TIMERS =====
  Timer? _overlayTimer;
  Timer? _seekingTimer;
  Timer? _healthCheckTimer;

  // ===== INITIALIZATION =====
  bool _isInitialized = false;

  // ===== GETTERS =====
  // Video data getters
  List<VideoModel> get videos => _videos;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  int get currentPage => _currentPage;
  int get activePage => _activePage;
  int get totalVideos => _videos.length;

  // Playback state getters
  VideoPlayerController? get currentController => _currentController;
  bool get isPlaying => _isPlaying;
  bool get isBuffering => _isBuffering;
  bool get isMuted => _isMuted;
  double get volume => _volume;
  bool get isHLS => _isHLS;
  bool get showPlayPauseOverlay => _showPlayPauseOverlay;
  bool get isSeeking => _isSeeking;

  // Screen state getters
  bool get isScreenVisible => _isScreenVisible;
  bool get isVideoScreenActive => _isVideoScreenActive;
  bool get isAppInForeground => _isAppInForeground;
  bool get shouldPlayVideos => _isVideoScreenActive && _isAppInForeground;

  // Video tracking getters
  int get currentVisibleVideoIndex => _activePage;

  // Navigation state getters
  int get lastActiveTabIndex => _lastActiveTabIndex;
  bool get wasOnVideoTab => _wasOnVideoTab;

  // Error state getters
  bool get hasError => _hasError;
  String? get errorMessage => _errorMessage;

  // Configuration getters
  VideoQualityPreset get qualityPreset => _qualityPreset;
  BufferingConfig get bufferingConfig => _bufferingConfig;
  PreloadingConfig get preloadingConfig => _preloadingConfig;

  // Initialization getter
  bool get isInitialized => _isInitialized;

  /// Initialize the consolidated VideoManager
  void initialize(VideoControllerManager controllerManager,
      VideoCacheManager cacheManager) {
    if (_isInitialized) return;

    _controllerManager = controllerManager;
    _cacheManager =
        cacheManager; // Use the passed cache manager instead of creating a new one

    // Initialize quality configuration
    _qualityPreset = VideoPlayerConfigService.getQualityPreset('reels_feed');
    _bufferingConfig =
        VideoPlayerConfigService.getBufferingConfig(_qualityPreset);
    _preloadingConfig =
        VideoPlayerConfigService.getPreloadingConfig(_qualityPreset);

    // Register listeners for video service events
    _videoService.addVideoIndexChangeListener(_onVideoIndexChanged);
    _videoService.addVideoScreenStateListener(_onVideoScreenStateChanged);

    _isInitialized = true;
    print('🚀 VideoManager: Consolidated manager initialized successfully');
    notifyListeners();
  }

  // ===== VIDEO DATA MANAGEMENT =====

  /// Initialize with provided videos
  void initializeWithVideos(List<VideoModel> videos, int initialIndex) {
    _videos = List<VideoModel>.from(videos);
    _activePage = initialIndex;
    _isLoading = false;
    _currentPage = 1;
    _hasMore = true;
    notifyListeners();
  }

  /// Load videos from API with pagination support
  Future<void> loadVideos({bool isInitialLoad = true}) async {
    if (!_hasMore || (_isLoadingMore && !isInitialLoad)) return;

    _setLoadingState(isInitialLoad, true);

    try {
      print(
          '🎬 VideoManager: Loading videos - Page: $_currentPage, Initial: $isInitialLoad');

      final stopwatch = Stopwatch()..start();

      // **NEW: Use VideoCacheManager for instant cache returns**
      final response = await _cacheManager.getVideos(
        page: _currentPage,
        limit: 10,
        forceRefresh: false,
      );

      stopwatch.stop();
      print(
          '📡 VideoManager: API response received in ${stopwatch.elapsedMilliseconds}ms');

      // Handle 304 Not Modified response
      if (response['status'] == 304) {
        print('✅ VideoManager: Using cached videos (304 Not Modified)');
        if (_videos.isNotEmpty) {
          _setLoadingState(isInitialLoad, false);
          notifyListeners();
          return;
        } else {
          // Force refresh if no cached data
          final freshResponse = await _cacheManager.getVideos(
            page: _currentPage,
            limit: 10,
            forceRefresh: true,
          );
          _processVideoResponse(freshResponse, isInitialLoad);
        }
      } else {
        _processVideoResponse(response, isInitialLoad);
      }
    } catch (e) {
      print("❌ VideoManager: Error loading videos: $e");
      _setLoadingState(isInitialLoad, false);
      _setError(e.toString());
    }
  }

  /// Process video response and update state
  void _processVideoResponse(
      Map<String, dynamic> response, bool isInitialLoad) {
    final List<VideoModel> fetchedVideos = response['videos'];
    final bool hasMore = response['hasMore'];

    print('🎥 VideoManager: Fetched ${fetchedVideos.length} videos');

    if (isInitialLoad) {
      _videos = fetchedVideos;
    } else {
      _videos.addAll(fetchedVideos);
    }

    _hasMore = hasMore;
    _currentPage++;

    _setLoadingState(isInitialLoad, false);
    print('📱 VideoManager: Total videos now: ${_videos.length}');
    notifyListeners();
  }

  /// Load more videos for infinite scroll
  Future<void> loadMoreVideos() async {
    if (!_hasMore || _isLoadingMore) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      print('🔄 VideoManager: Loading more videos - Page: $_currentPage');

      final response = await _cacheManager.getVideos(
        page: _currentPage,
        limit: 10,
        forceRefresh: false,
      );

      if (response['status'] == 304) {
        print('✅ VideoManager: Using cached videos for page $_currentPage');
        if (_videos.length < _currentPage * 10) {
          final freshResponse = await _cacheManager.getVideos(
            page: _currentPage,
            limit: 10,
            forceRefresh: true,
          );
          _processVideoResponse(freshResponse, false);
        }
      } else {
        _processVideoResponse(response, false);
      }
    } catch (e) {
      print("❌ VideoManager: Error loading more videos: $e");
      _setError(e.toString());
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// Check if we need to load more videos for infinite scroll
  void checkAndLoadMoreVideos(int currentIndex) {
    if (_hasMore && !_isLoadingMore && currentIndex >= _videos.length - 3) {
      print(
          '🔄 VideoManager: Triggering infinite scroll load at index $currentIndex');
      loadMoreVideos();
    }
  }

  /// **NEW: Get cached videos for instant return when switching tabs**
  Map<String, dynamic>? getCachedVideos({int page = 1, int limit = 10}) {
    return _cacheManager.getCachedVideos(page: page, limit: limit);
  }

  /// **NEW: Check if we have cached videos for instant loading**
  bool hasCachedVideos({int page = 1}) {
    return _cacheManager.hasCachedVideos(page: page);
  }

  /// **NEW: Get cache statistics for debugging**
  Map<String, dynamic> getCacheStats() {
    return _cacheManager.getCacheStats();
  }

  /// Refresh videos
  Future<void> refreshVideos() async {
    print('🔄 VideoManager: Refreshing videos');

    _videos.clear();
    _currentPage = 1;
    _hasMore = true;
    _isLoading = true;
    _activePage = 0;

    notifyListeners();
    await loadVideos(isInitialLoad: true);
  }

  // ===== VIDEO PLAYBACK CONTROL =====

  /// Initialize video controller for a specific video
  Future<void> initializeVideoController(String videoUrl, bool autoPlay) async {
    try {
      clearError();

      // Use optimized video URL for better performance
      final optimizedUrl = VideoPlayerConfigService.getOptimizedVideoUrl(
          videoUrl, _qualityPreset);

      _currentController = VideoPlayerController.networkUrl(
        Uri.parse(optimizedUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
        httpHeaders: VideoPlayerConfigService.getOptimizedHeaders(optimizedUrl),
      );

      _currentController!.addListener(_onControllerStateChanged);

      // Add timeout for initialization
      await _currentController!.initialize().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Video initialization timed out');
        },
      );

      // Enhanced buffering optimization
      await _optimizeControllerForSmoothPlayback();

      // Always mute video by default (Instagram-style behavior)
      await _currentController!.setVolume(0.0);

      if (autoPlay && _currentController!.value.isInitialized) {
        await _currentController!.play();
        _isPlaying = true;
        notifyListeners();
      }
    } on PlatformException catch (e) {
      print(
          '❌ PlatformException in video initialization: ${e.code} - ${e.message}');
      _handlePlatformException(e);
    } on TimeoutException catch (e) {
      print('❌ TimeoutException in video initialization: $e');
      _setError(
          'Video loading timed out. Please check your connection and try again.');
    } catch (e) {
      print('❌ Error in video initialization: $e');
      _setError(_getUserFriendlyErrorMessage(e.toString()));
    }
  }

  /// Enhanced buffering optimization for smooth playback
  Future<void> _optimizeControllerForSmoothPlayback() async {
    try {
      if (_currentController != null &&
          _currentController!.value.isInitialized) {
        await _currentController!.seekTo(Duration.zero);
        await _currentController!.setPlaybackSpeed(1.0);

        if (_isHLS) {
          await _currentController!.seekTo(const Duration(milliseconds: 100));
          await _currentController!.seekTo(Duration.zero);
        }

        print('🎬 VideoManager: Enhanced buffering optimization applied');
      }
    } catch (e) {
      print('⚠️ VideoManager: Buffering optimization failed: $e');
    }
  }

  /// Play video
  Future<void> play() async {
    print('🎬 VideoManager: play() called');

    if (_currentController == null ||
        !_currentController!.value.isInitialized) {
      print('❌ VideoManager: No controller available for play');
      return;
    }

    try {
      await _currentController!.play();
      _isPlaying = true;
      print('🎬 VideoManager: Video play successful');
      notifyListeners();
    } on PlatformException catch (e) {
      print('❌ PlatformException in play: ${e.code} - ${e.message}');
      _handlePlatformException(e);
    } catch (e) {
      print('❌ Error in play: $e');
      _setError(_getUserFriendlyErrorMessage(e.toString()));
    }
  }

  /// Pause video
  Future<void> pause() async {
    print('🎬 VideoManager: pause() called');

    if (_currentController == null ||
        !_currentController!.value.isInitialized) {
      print('❌ VideoManager: No controller available for pause');
      return;
    }

    try {
      await _currentController!.pause();
      _isPlaying = false;
      print('🎬 VideoManager: Video pause successful');
      notifyListeners();
    } on PlatformException catch (e) {
      print('❌ PlatformException in pause: ${e.code} - ${e.message}');
      _handlePlatformException(e);
    } catch (e) {
      print('❌ Error in pause: $e');
      _setError(_getUserFriendlyErrorMessage(e.toString()));
    }
  }

  /// Toggle play/pause state
  Future<void> togglePlayPause() async {
    print(
        '🎬 VideoManager: togglePlayPause called, current state: $_isPlaying');

    if (_currentController == null ||
        !_currentController!.value.isInitialized) {
      print('❌ VideoManager: No controller available');
      return;
    }

    try {
      if (_isPlaying) {
        await pause();
      } else {
        await play();
      }
    } catch (e) {
      print('❌ VideoManager: Error in togglePlayPause: $e');
    }
  }

  /// Seek to specific position
  Future<void> seekTo(Duration position) async {
    if (_currentController != null && _currentController!.value.isInitialized) {
      try {
        await _currentController!.seekTo(position);
      } on PlatformException catch (e) {
        print('❌ PlatformException in seek: ${e.code} - ${e.message}');
        _handlePlatformException(e);
      } catch (e) {
        print('❌ Error in seek: $e');
        _setError(_getUserFriendlyErrorMessage(e.toString()));
      }
    }
  }

  /// Set volume
  Future<void> setVolume(double volume) async {
    if (_currentController != null && _currentController!.value.isInitialized) {
      try {
        await _currentController!.setVolume(volume);
        _volume = volume;
        notifyListeners();
      } on PlatformException catch (e) {
        print('❌ PlatformException in setVolume: ${e.code} - ${e.message}');
        _handlePlatformException(e);
      } catch (e) {
        print('❌ Error in setVolume: $e');
        _setError(_getUserFriendlyErrorMessage(e.toString()));
      }
    }
  }

  /// Toggle mute/unmute
  Future<void> toggleMute() async {
    if (_isMuted) {
      await unmute();
    } else {
      await mute();
    }
  }

  /// Mute video
  Future<void> mute() async {
    if (_currentController != null && _currentController!.value.isInitialized) {
      try {
        await _currentController!.setVolume(0.0);
        _isMuted = true;
        notifyListeners();
      } on PlatformException catch (e) {
        print('❌ PlatformException in mute: ${e.code} - ${e.message}');
        _handlePlatformException(e);
      } catch (e) {
        print('❌ Error in mute: $e');
        _setError(_getUserFriendlyErrorMessage(e.toString()));
      }
    }
  }

  /// Unmute video
  Future<void> unmute() async {
    if (_currentController != null && _currentController!.value.isInitialized) {
      try {
        await _currentController!.setVolume(1.0);
        _isMuted = false;
        _volume = 1.0;
        notifyListeners();
      } on PlatformException catch (e) {
        print('❌ PlatformException in unmute: ${e.code} - ${e.message}');
        _handlePlatformException(e);
      } catch (e) {
        print('❌ Error in unmute: $e');
        _setError(_getUserFriendlyErrorMessage(e.toString()));
      }
    }
  }

  // ===== CONTROLLER STATE MANAGEMENT =====

  /// Handle controller state changes
  void _onControllerStateChanged() {
    if (_currentController == null) return;

    try {
      final controllerValue = _currentController!.value;

      // Update playing state
      final wasPlaying = _isPlaying;
      _isPlaying = controllerValue.isPlaying;

      // Update buffering state
      final wasBuffering = _isBuffering;
      _isBuffering = controllerValue.isBuffering;

      // Update error state
      if (controllerValue.hasError) {
        final errorDesc =
            controllerValue.errorDescription ?? 'Video player error';
        print('❌ Video controller error: $errorDesc');
        _setError(_getUserFriendlyErrorMessage(errorDesc));
      }

      // Notify listeners if any important state changed
      if (wasPlaying != _isPlaying || wasBuffering != _isBuffering) {
        notifyListeners();
      }
    } catch (e) {
      print('❌ Error in controller state change listener: $e');
      _setError(_getUserFriendlyErrorMessage(e.toString()));
    }
  }

  // ===== NAVIGATION STATE MANAGEMENT =====

  /// Handle navigation tab changes
  void onNavigationTabChanged(int newTabIndex) {
    final wasOnVideoTab = _lastActiveTabIndex == 0;
    final isNowOnVideoTab = newTabIndex == 0;

    print(
        '🔄 VideoManager: Navigation tab changed from $_lastActiveTabIndex to $newTabIndex');
    print(
        '🔄 VideoManager: Was on video tab: $wasOnVideoTab, Now on video tab: $isNowOnVideoTab');

    _lastActiveTabIndex = newTabIndex;
    _wasOnVideoTab = wasOnVideoTab;

    if (wasOnVideoTab && !isNowOnVideoTab) {
      _handleLeavingVideoTab();
    } else if (!wasOnVideoTab && isNowOnVideoTab) {
      _handleEnteringVideoTab();
    }

    updateVideoScreenState(isNowOnVideoTab);
  }

  /// Handle leaving the video tab
  void _handleLeavingVideoTab() {
    print(
        '🛑 VideoManager: LEAVING VIDEO TAB - pausing all videos immediately');

    _isVideoScreenActive = false;

    if (_isInitialized) {
      _controllerManager.comprehensivePause();
      _controllerManager.emergencyStopAllVideos();
      updateScreenVisibility(false);
    }

    _videoService.updateVideoScreenState(false);
    notifyListeners();
  }

  /// Handle entering the video tab
  void _handleEnteringVideoTab() {
    print(
        '▶️ VideoManager: ENTERING VIDEO TAB - checking if should resume videos');

    _isVideoScreenActive = true;

    if (_isAppInForeground && _isInitialized) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_isVideoScreenActive && _isAppInForeground) {
          print('▶️ VideoManager: Resuming videos after entering video tab');
          _controllerManager.handleVideoVisible();
          playActiveVideo();
        }
      });
    }

    _videoService.updateVideoScreenState(true);
    notifyListeners();
  }

  /// Update app foreground state
  void updateAppForegroundState(bool inForeground) {
    if (_isAppInForeground != inForeground) {
      _isAppInForeground = inForeground;
      print(
          '📱 VideoManager: App foreground state changed to ${inForeground ? "FOREGROUND" : "BACKGROUND"}');

      _videoService.updateAppForegroundState(inForeground);

      if (!inForeground) {
        pauseAllVideos();
      } else if (_isVideoScreenActive) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (_isAppInForeground && _isVideoScreenActive) {
            playActiveVideo();
          }
        });
      }

      notifyListeners();
    }
  }

  // ===== VIDEO INDEX TRACKING =====

  /// Update the currently visible video index
  void updateCurrentVideoIndex(int newIndex) {
    if (_activePage != newIndex) {
      final oldIndex = _activePage;
      _activePage = newIndex;

      print('🎬 VideoManager: Video index changed from $oldIndex to $newIndex');

      _videoService.updateCurrentVideoIndex(newIndex);
      notifyListeners();
    }
  }

  /// Handle video index changes from video service
  void _onVideoIndexChanged(int newIndex) {
    print(
        '🎬 VideoManager: Received video index change notification: $newIndex');
    updateCurrentVideoIndex(newIndex);
  }

  /// Handle video screen state changes from video service
  void _onVideoScreenStateChanged(bool isActive) {
    print(
        '🔄 VideoManager: Received video screen state change notification: $isActive');
    updateVideoScreenState(isActive);
  }

  // ===== SCREEN VISIBILITY MANAGEMENT =====

  /// Update video screen state
  void updateVideoScreenState(bool isActive) {
    if (_isVideoScreenActive != isActive) {
      _isVideoScreenActive = isActive;
      print(
          '🔄 VideoManager: Video screen state updated to ${isActive ? "ACTIVE" : "INACTIVE"}');

      if (!isActive) {
        pauseAllVideos();
      } else if (_isAppInForeground) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (_isVideoScreenActive && _isAppInForeground) {
            playActiveVideo();
          }
        });
      }

      notifyListeners();
    }
  }

  /// Update screen visibility
  void updateScreenVisibility(bool visible) {
    if (_isScreenVisible != visible) {
      print('👁️ VideoManager: Screen visibility changed to: $visible');
      _isScreenVisible = visible;
      notifyListeners();
    }
  }

  void updateVideoLike(int index, String userId) {
    if (index >= 0 && index < _videos.length) {
      final video = _videos[index];
      final isCurrentlyLiked = video.likedBy.contains(userId);

      if (isCurrentlyLiked) {
        final updatedLikedBy = List<String>.from(video.likedBy)..remove(userId);
        _videos[index] = video.copyWith(
          likedBy: updatedLikedBy,
          likes: video.likes - 1,
        );
      } else {
        final updatedLikedBy = List<String>.from(video.likedBy)..add(userId);
        _videos[index] = video.copyWith(
          likedBy: updatedLikedBy,
          likes: video.likes + 1,
        );
      }

      notifyListeners();
    }
  }

  /// Update video comments
  void updateVideoComments(int index, List<Comment> comments) {
    if (index >= 0 && index < _videos.length) {
      _videos[index].comments = comments;
      notifyListeners();
    }
  }

  /// Get current video
  VideoModel? getCurrentVideo() {
    if (_videos.isNotEmpty && _activePage < _videos.length) {
      return _videos[_activePage];
    }
    return null;
  }

  /// Get video at specific index
  VideoModel? getVideoAt(int index) {
    if (index >= 0 && index < _videos.length) {
      return _videos[index];
    }
    return null;
  }

  // ===== VIDEO CONTROL OPERATIONS =====

  /// Pause all videos
  void pauseAllVideos() {
    if (_isInitialized) {
      print('⏸️ VideoManager: Pausing all videos');
      _controllerManager.comprehensivePause();
      _controllerManager.emergencyStopAllVideos();
      updateScreenVisibility(false);
    }
  }

  /// Play the currently active video
  void playActiveVideo() {
    if (_isInitialized && _isVideoScreenActive && _isAppInForeground) {
      print('▶️ VideoManager: Playing active video at index $_activePage');
      _controllerManager.playActiveVideo();
      updateScreenVisibility(true);
    }
  }

  /// Force pause all videos (for emergency situations)
  void forcePauseAllVideos() {
    print('🚨 VideoManager: FORCE PAUSING ALL VIDEOS');
    pauseAllVideos();

    if (_isInitialized) {
      _controllerManager.emergencyStopAllVideos();
      _controllerManager.comprehensivePause();
    }
  }

  // ===== ERROR HANDLING =====

  /// Set error state
  void _setError(String message) {
    _hasError = true;
    _errorMessage = message;
    notifyListeners();
  }

  /// Clear error state
  void clearError() {
    _hasError = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Handle PlatformException errors with specific error codes
  void _handlePlatformException(PlatformException e) {
    String userMessage;

    switch (e.code) {
      case 'VideoError':
        userMessage = 'Video playback error. Please try again.';
        break;
      case 'NetworkError':
        userMessage = 'Network error. Please check your connection.';
        break;
      case 'FormatError':
        userMessage =
            'Video format not supported. Please try a different video.';
        break;
      case 'PermissionError':
        userMessage = 'Permission denied. Please check app permissions.';
        break;
      default:
        userMessage = 'Video error: ${e.message ?? 'Unknown error'}';
    }

    _setError(userMessage);
  }

  /// Convert technical error messages to user-friendly ones
  String _getUserFriendlyErrorMessage(String technicalError) {
    if (technicalError.contains('timeout')) {
      return 'Video loading timed out. Please check your connection.';
    } else if (technicalError.contains('network')) {
      return 'Network error. Please check your internet connection.';
    } else if (technicalError.contains('format')) {
      return 'Video format not supported. Please try a different video.';
    } else if (technicalError.contains('permission')) {
      return 'Permission denied. Please check app permissions.';
    } else if (technicalError.contains('not found')) {
      return 'Video not found. Please try again later.';
    } else if (technicalError.contains('server')) {
      return 'Server error. Please try again later.';
    } else {
      return 'Video error. Please try again.';
    }
  }

  // ===== UTILITY METHODS =====

  /// Set loading state
  void _setLoadingState(bool isInitialLoad, bool loading) {
    if (isInitialLoad) {
      _isLoading = loading;
    } else {
      _isLoadingMore = loading;
    }
    notifyListeners();
  }

  /// Reset state
  void reset() {
    _videos.clear();
    _isLoading = true;
    _isLoadingMore = false;
    _hasMore = true;
    _currentPage = 1;
    _activePage = 0;
    _isScreenVisible = true;
    notifyListeners();
  }

  /// Get current video tracking information
  Map<String, dynamic> getVideoTrackingInfo() {
    return {
      'currentVisibleVideoIndex': _activePage,
      'isVideoScreenActive': _isVideoScreenActive,
      'isAppInForeground': _isAppInForeground,
      'shouldPlayVideos': shouldPlayVideos,
      'lastActiveTabIndex': _lastActiveTabIndex,
      'wasOnVideoTab': _wasOnVideoTab,
      'isInitialized': _isInitialized,
      'totalVideos': _videos.length,
      'isPlaying': _isPlaying,
      'isBuffering': _isBuffering,
      'isMuted': _isMuted,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// Check if videos should be playing based on current state
  bool get shouldVideosBePlaying {
    return _isVideoScreenActive && _isAppInForeground && _isInitialized;
  }

  /// Check if error is network-related and can be retried
  bool get isNetworkError {
    if (!_hasError || _errorMessage == null) return false;

    final error = _errorMessage!.toLowerCase();
    return error.contains('network') ||
        error.contains('connection') ||
        error.contains('timeout') ||
        error.contains('unreachable');
  }

  /// Check if error is recoverable (can be retried)
  bool get isRecoverableError {
    if (!_hasError || _errorMessage == null) return false;

    final error = _errorMessage!.toLowerCase();
    return !error.contains('format') &&
        !error.contains('codec') &&
        !error.contains('permission') &&
        !error.contains('not found');
  }

  // ===== CLEANUP =====

  /// Dispose the VideoManager
  @override
  void dispose() {
    print('🗑️ VideoManager: Disposing consolidated manager...');

    // Cancel timers
    _overlayTimer?.cancel();
    _seekingTimer?.cancel();
    _healthCheckTimer?.cancel();

    // Remove listeners
    _videoService.removeVideoIndexChangeListener(_onVideoIndexChanged);
    _videoService.removeVideoScreenStateListener(_onVideoScreenStateChanged);

    // Dispose video service
    _videoService.dispose();

    // Dispose current controller
    _currentController?.dispose();

    super.dispose();
    print('🗑️ VideoManager: Consolidated manager disposed successfully');
  }
}
