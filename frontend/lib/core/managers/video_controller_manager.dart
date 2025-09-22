import 'package:video_player/video_player.dart';
import 'package:snehayog/core/managers/video_position_cache_manager.dart';
import 'package:snehayog/core/managers/hot_ui_state_manager.dart';
import 'package:snehayog/services/signed_url_service.dart';
import 'package:snehayog/core/factories/video_controller_factory.dart';
import 'package:snehayog/model/video_model.dart';
import 'dart:collection';
import 'dart:async';

class VideoControllerManager {
  static final VideoControllerManager _instance =
      VideoControllerManager._internal();
  factory VideoControllerManager() => _instance;
  VideoControllerManager._internal();

  final Map<int, VideoPlayerController> _controllers = {};
  final Queue<int> _order = Queue();
  final Set<int> _pinned = {};
  final Set<int> _intentionallyPaused = {};
  final Map<int, String> _controllerSourceUrl = {};
  final Map<int, String> _controllerVideoIds = {};

  final VideoPositionCacheManager _positionCache = VideoPositionCacheManager();
  final HotUIStateManager _hotUIManager = HotUIStateManager();

  final int maxPoolSize = 1;

  Future<VideoPlayerController> getController(
      int index, VideoModel video) async {
    // Resolve the intended final URL (with HLS signing if needed) before deciding reuse
    String finalUrl = video.videoUrl;
    if (video.videoUrl.contains('.m3u8')) {
      print('🔐 VideoControllerManager: Getting signed URL for HLS stream');
      try {
        final signedUrlService = SignedUrlService();
        final signedUrl =
            await signedUrlService.getBestSignedUrl(video.videoUrl).timeout(
          const Duration(seconds: 3), // Short timeout for signed URL
          onTimeout: () {
            print(
                '⏰ VideoControllerManager: Signed URL timeout, using original URL');
            return video.videoUrl;
          },
        );

        if (signedUrl != null && signedUrl != video.videoUrl) {
          finalUrl = signedUrl;
          print('✅ VideoControllerManager: Using signed URL: $finalUrl');
        } else {
          print('⚠️ VideoControllerManager: Using original URL: $finalUrl');
        }
      } catch (e) {
        print(
            '❌ VideoControllerManager: Signed URL service error: $e, using original URL');
        finalUrl = video.videoUrl;
      }
    }

    // **OPTIMIZED: Reuse existing controller if available and valid**
    if (_controllers.containsKey(index)) {
      final existingController = _controllers[index];
      if (existingController != null &&
          existingController.value.isInitialized &&
          !existingController.value.hasError) {
        print('♻️ VideoControllerManager: Reusing existing controller $index');
        return existingController;
      } else {
        print('🔄 VideoControllerManager: Disposing invalid controller $index');
        _disposeController(index);
      }
    }

    // **MEMORY MANAGEMENT: Only dispose controllers that are far from current index**
    final currentIndex = index;
    final controllersToRemove = <int>[];

    for (final key in _controllers.keys) {
      if (key != currentIndex && (key - currentIndex).abs() > 2) {
        controllersToRemove.add(key);
      }
    }

    for (final key in controllersToRemove) {
      print('🗑️ VideoControllerManager: Disposing distant controller $key');
      _disposeController(key);
    }

    // Create video model with signed URL if needed
    final videoWithSignedUrl =
        finalUrl != video.videoUrl ? video.copyWith(videoUrl: finalUrl) : video;

    // Use VideoControllerFactory to create optimized controller
    final controller =
        await VideoControllerFactory.createController(videoWithSignedUrl);

    try {
      await controller.initialize().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException(
              'Video initialization timeout', const Duration(seconds: 10));
        },
      );

      controller.setLooping(true);
      _controllers[index] = controller;
      _controllerSourceUrl[index] = finalUrl;
      _controllerVideoIds[index] =
          video.id; // Store video ID for position caching
      _order.addLast(index);
      _warmNetwork(finalUrl);
      _evictIfNeeded();

      // **POSITION CACHING: Restore video position and state**
      await _positionCache.restoreVideoState(controller, video.id);

      // **POSITION CACHING: Start tracking position for this video**
      _positionCache.startPositionTracking(controller, video.id);

      print(
          '✅ VideoControllerManager: Successfully created controller using VideoControllerFactory for ${video.videoName} with position caching');
      return controller;
    } catch (e) {
      print(
          '❌ VideoControllerManager: Failed to initialize controller for ${video.videoName}: $e');

      // Try fallback URL if this is an HLS URL
      if (finalUrl.contains('.m3u8')) {
        final fallbackUrl = _getFallbackUrl(finalUrl);
        if (fallbackUrl != finalUrl) {
          print('🔄 VideoControllerManager: Trying fallback URL: $fallbackUrl');
          final fallbackVideo = video.copyWith(videoUrl: fallbackUrl);
          return await getController(index, fallbackVideo);
        }
      }
      rethrow;
    }
  }

  /// Get controller for video index with URL (legacy method for backward compatibility)
  Future<VideoPlayerController> getControllerWithUrl(
      int index, String url) async {
    // Create a minimal VideoModel for backward compatibility
    final video = VideoModel(
      id: 'legacy_$index',
      videoName: 'Legacy Video $index',
      videoUrl: url,
      thumbnailUrl: '',
      likes: 0,
      views: 0,
      shares: 0,
      uploader: Uploader(id: 'legacy', name: 'Legacy', profilePic: ''),
      uploadedAt: DateTime.now(),
      likedBy: [],
      videoType: 'reel',
      aspectRatio: 9 / 16,
      duration: const Duration(seconds: 0),
      comments: [],
    );

    return getController(index, video);
  }

  /// Preload controller but don't play yet using VideoModel
  Future<void> preloadController(int index, VideoModel video) async {
    try {
      print(
          '🚀 VideoControllerManager: Preloading controller $index for ${video.videoName}');

      // **SIMPLIFIED: Direct video controller creation for 480p videos**
      print(
          '🎬 VideoControllerManager: Preloading 480p video for ${video.videoName}');

      await getController(index, video);
      _warmNetwork(video.videoUrl);
    } catch (e) {
      print('❌ VideoControllerManager: Error preloading controller $index: $e');
    }
  }

  /// Preload controller with URL (legacy method for backward compatibility)
  Future<void> preloadControllerWithUrl(int index, String url) async {
    // Create a minimal VideoModel for backward compatibility
    final video = VideoModel(
      id: 'legacy_$index',
      videoName: 'Legacy Video $index',
      videoUrl: url,
      thumbnailUrl: '',
      likes: 0,
      views: 0,
      shares: 0,
      uploader: Uploader(id: 'legacy', name: 'Legacy', profilePic: ''),
      uploadedAt: DateTime.now(),
      likedBy: [],
      videoType: 'yog',
      aspectRatio: 9 / 16,
      duration: const Duration(seconds: 0),
      comments: [],
    );

    await preloadController(index, video);
  }

  /// Play controller instantly (already initialized)
  Future<void> playController(int index) async {
    if (_controllers.containsKey(index)) {
      final controller = _controllers[index]!;
      if (controller.value.isInitialized && !controller.value.hasError) {
        // **AUDIO FIX: Pause all other videos before playing to prevent echo**
        await pauseAllVideos();

        // If the video is at the end (or very close), reset to start before playing
        final duration = controller.value.duration;
        final position = controller.value.position;
        if (duration.inMilliseconds > 0 &&
            (position >= duration - const Duration(milliseconds: 300))) {
          try {
            await controller.seekTo(Duration.zero);
          } catch (_) {}
        }
        await controller.play();
        _intentionallyPaused.remove(index);

        // **POSITION CACHING: Save last video info**
        final videoId = _controllerVideoIds[index];
        if (videoId != null) {
          await _positionCache.saveLastVideo(videoId, index);
        }
      }
    }
  }

  /// Pause controller
  Future<void> pauseController(int index) async {
    if (_controllers.containsKey(index)) {
      await _controllers[index]!.pause();
      _intentionallyPaused.add(index);
    }
  }

  /// Play active video (for compatibility)
  Future<void> playActiveVideo() async {
    if (_controllers.isNotEmpty) {
      final activeIndex = _order.isNotEmpty ? _order.last : 0;
      await playController(activeIndex);
    }
  }

  /// Pause all videos
  Future<void> pauseAllVideos() async {
    for (final index in _controllers.keys) {
      await pauseController(index);
    }
  }

  /// Check if video is intentionally paused
  bool isVideoIntentionallyPaused(int index) {
    return _intentionallyPaused.contains(index);
  }

  /// Get controller count
  int get controllerCount => _controllers.length;

  /// Pin indices to prevent eviction
  void pinIndices(Set<int> indices) {
    _pinned.addAll(indices);
  }

  /// Unpin indices
  void unpinIndices(Set<int> indices) {
    _pinned.removeAll(indices);
  }

  /// Optimize controllers (dispose old ones)
  void optimizeControllers() {
    // Dispose controllers that are not pinned and are old
    final toDispose = <int>[];
    for (final index in _controllers.keys) {
      if (!_pinned.contains(index) && _order.length > 2) {
        toDispose.add(index);
      }
    }

    for (final index in toDispose) {
      _disposeController(index);
    }
  }

  /// Dispose all controllers
  void disposeAllControllers() {
    print('🗑️ VideoControllerManager: Disposing all controllers');
    for (final index in List<int>.from(_controllers.keys)) {
      _disposeController(index);
    }
  }

  /// Dispose specific controller with proper cleanup
  void _disposeController(int index) {
    if (_controllers.containsKey(index)) {
      try {
        final controller = _controllers[index]!;

        // **CRITICAL: Pause and stop before disposing**
        if (controller.value.isInitialized) {
          controller.pause();
          controller.setVolume(0.0);
        }

        // **CACHING: Only dispose if we have too many controllers**
        if (_controllers.length > maxPoolSize) {
          // **MEMORY: Properly dispose controller to free MediaCodec resources**
          controller.dispose();
          _controllers.remove(index);
          _order.removeWhere((i) => i == index);
          _intentionallyPaused.remove(index);
          _controllerSourceUrl.remove(index);
          print(
              '🗑️ VideoControllerManager: Disposed controller $index and freed MediaCodec memory');
        } else {
          // **CACHING: Keep controller in cache but pause it**
          controller.pause();
          controller.setVolume(0.0);
          _intentionallyPaused.add(index);
          print(
              '💾 VideoControllerManager: Cached controller $index for reuse');
        }

        // **FORCE: Small delay to ensure MediaCodec cleanup**
        Future.delayed(const Duration(milliseconds: 50), () {
          print(
              '🗑️ VideoControllerManager: Disposed controller $index and freed MediaCodec memory');
        });
      } catch (e) {
        print(
            '❌ VideoControllerManager: Error disposing controller $index: $e');
      }
    }
  }

  /// Evict controllers if pool is too large
  void _evictIfNeeded() {
    while (_controllers.length > maxPoolSize) {
      // Find victim (oldest non-pinned)
      int? victim;
      for (final index in _order) {
        if (!_pinned.contains(index)) {
          victim = index;
          break;
        }
      }

      if (victim == null) break;
      _order.removeWhere((i) => i == victim);
      _disposeController(victim);
    }
  }

  void _warmNetwork(String url) {
    // Network warming removed since VideoCacheManager was deleted
    // Videos now load directly through VideoPlayer for 480p content
    print('🌐 VideoControllerManager: Network warming for 480p video: $url');
  }

  /// Get fallback URL for HLS streams
  String _getFallbackUrl(String originalUrl) {
    if (!originalUrl.contains('.m3u8')) return originalUrl;

    // Try different Cloudinary streaming profiles
    if (originalUrl.contains('sp_hd')) {
      // Try SD profile instead of HD
      return originalUrl.replaceAll('sp_hd', 'sp_sd');
    } else if (originalUrl.contains('sp_sd')) {
      // Try basic streaming profile
      return originalUrl.replaceAll('sp_sd', 'sp_auto');
    } else if (originalUrl.contains('sp_auto')) {
      // Try without streaming profile
      return originalUrl.replaceAll(RegExp(r'sp_[^,]+,'), '');
    }

    return originalUrl;
  }

  /// Clear all with proper MediaCodec cleanup
  void clear() {
    print(
        '🗑️ VideoControllerManager: Clearing all controllers and freeing MediaCodec memory');

    for (final entry in _controllers.entries) {
      try {
        final controller = entry.value;

        // **CRITICAL: Pause and stop before disposing**
        if (controller.value.isInitialized) {
          controller.pause();
          controller.setVolume(0.0);
        }

        controller.dispose();
        print('🗑️ VideoControllerManager: Disposed controller ${entry.key}');
      } catch (e) {
        print(
            '❌ VideoControllerManager: Error disposing controller ${entry.key}: $e');
      }
    }

    _controllers.clear();
    _order.clear();
    _pinned.clear();
    _intentionallyPaused.clear();
    _controllerSourceUrl.clear();

    // **FORCE: Delay to ensure MediaCodec cleanup completes**
    Future.delayed(const Duration(milliseconds: 100), () {
      print('✅ VideoControllerManager: All MediaCodec resources freed');
    });
  }

  // **COMPATIBILITY METHODS** - For existing code
  Future<void> initController(int index, dynamic video) async {
    await getController(index, video.videoUrl);
  }

  VideoPlayerController? getControllerByIndex(int index) {
    return _controllers[index];
  }

  Future<void> playVideo(int index) async {
    await playController(index);
  }

  Future<void> pauseVideo(int index) async {
    await pauseController(index);
  }

  Future<void> disposeController(int index) async {
    _disposeController(index);
  }

  /// Check if controller is cached and valid
  bool isControllerCached(int index) {
    if (!_controllers.containsKey(index)) return false;
    final controller = _controllers[index]!;
    return controller.value.isInitialized && !controller.value.hasError;
  }

  /// Get cached controller count
  int get cachedControllerCount => _controllers.length;

  /// Cleanup all controllers
  void cleanup() {
    clear();
  }

  /// **TAB CHANGE DETECTION: Pause all videos when user switches tabs**
  Future<void> pauseAllVideosOnTabChange() async {
    print(
        '⏸️ VideoControllerManager: Tab change detected - pausing all videos');

    for (final index in _controllers.keys) {
      final controller = _controllers[index];
      if (controller != null &&
          controller.value.isInitialized &&
          controller.value.isPlaying) {
        try {
          await controller.pause();
          _intentionallyPaused.add(index);
          print('⏸️ VideoControllerManager: Paused video at index $index');
        } catch (e) {
          print(
              '❌ VideoControllerManager: Error pausing video at index $index: $e');
        }
      }
    }
  }

  /// **TAB CHANGE DETECTION: Resume videos when returning to video tab**
  Future<void> resumeVideosOnTabReturn() async {
    print(
        '▶️ VideoControllerManager: Returning to video tab - resuming videos');

    // Only resume the current active video, not all videos
    if (_controllers.isNotEmpty) {
      final activeIndex =
          _order.isNotEmpty ? _order.last : _controllers.keys.first;
      if (_controllers.containsKey(activeIndex)) {
        final controller = _controllers[activeIndex]!;
        if (controller.value.isInitialized &&
            !controller.value.hasError &&
            !controller.value.isPlaying) {
          try {
            await controller.play();
            _intentionallyPaused.remove(activeIndex);
            print(
                '▶️ VideoControllerManager: Resumed video at index $activeIndex');
          } catch (e) {
            print(
                '❌ VideoControllerManager: Error resuming video at index $activeIndex: $e');
          }
        }
      }
    }
  }

  /// **TAB CHANGE DETECTION: Force pause all videos immediately (for critical situations)**
  void forcePauseAllVideos() {
    print('🛑 VideoControllerManager: Force pausing all videos immediately');

    for (final index in _controllers.keys) {
      final controller = _controllers[index];
      if (controller != null && controller.value.isInitialized) {
        try {
          controller.pause();
          _intentionallyPaused.add(index);
        } catch (e) {
          print(
              '❌ VideoControllerManager: Error force pausing video at index $index: $e');
        }
      }
    }
  }

  /// **HOT UI: Save state when app goes to background**
  void saveUIStateForBackground(
      int currentIndex, double scrollPosition, Map<int, VideoModel> videos) {
    print('💾 VideoControllerManager: Saving UI state for background');

    _hotUIManager.saveUIState(
      currentIndex: currentIndex,
      scrollPosition: scrollPosition,
      controllers: _controllers,
      videos: videos,
    );
  }

  /// **HOT UI: Restore state when app comes to foreground**
  Map<String, dynamic>? restoreUIStateFromBackground() {
    print('🔄 VideoControllerManager: Restoring UI state from background');

    if (_hotUIManager.isStateRestored) {
      final restoredState = _hotUIManager.restoreUIState();

      // Restore controllers from preserved state
      final preservedControllers = restoredState['preservedControllers']
          as Map<int, VideoPlayerController>?;
      if (preservedControllers != null) {
        _controllers.addAll(preservedControllers);
      }

      return restoredState;
    }

    return null;
  }

  /// **HOT UI: Check if we have preserved state**
  bool get hasPreservedState => _hotUIManager.isStateRestored;

  /// **HOT UI: Get state summary for debugging**
  Map<String, dynamic> getHotUIStateSummary() {
    return _hotUIManager.getStateSummary();
  }
}
