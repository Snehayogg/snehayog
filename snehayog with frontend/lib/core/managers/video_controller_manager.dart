import 'dart:async';
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
// Added for precacheImage
// Added for CachedNetworkImageProvider
import 'package:snehayog/core/services/hls_performance_monitor.dart';

/// Manages video controllers for smooth playback and memory optimization
class VideoControllerManager {
  // Map to store video player controllers for each video index
  final Map<int, VideoPlayerController> _controllers = {};

  // Number of videos to preload in each direction
  final int _preloadDistance = 2;

  // Track active page
  int _activePage = 0;

  // Getter for active page
  int get activePage => _activePage;

  // Getter for controllers
  Map<int, VideoPlayerController> get controllers => _controllers;

  /// Initialize controller for a specific video index
  Future<void> initController(int index, VideoModel video) async {
    try {
      print(
          '🎬 VideoControllerManager: Initializing controller for video $index');
      print('🎬 VideoControllerManager: Video URL: ${video.videoUrl}');
      print('🎬 VideoControllerManager: Is HLS: ${video.isHLSEncoded}');
      print(
          '🎬 VideoControllerManager: HLS Master URL: ${video.hlsMasterPlaylistUrl}');
      print(
          '🎬 VideoControllerManager: HLS Playlist URL: ${video.hlsPlaylistUrl}');

      VideoPlayerController controller;

      // FORCE HLS ONLY - Reject MP4 videos
      if (video.isHLSEncoded != true) {
        throw Exception(
            'Video is not HLS encoded. Only .m3u8 streaming videos are supported.');
      }

      // Check if this is an HLS video
      if (video.hlsMasterPlaylistUrl != null &&
          video.hlsMasterPlaylistUrl!.isNotEmpty) {
        // Use HLS master playlist URL for adaptive streaming (BEST QUALITY)
        final hlsUrl = _buildHLSUrl(video.hlsMasterPlaylistUrl!);
        print('🎬 VideoControllerManager: Using HLS master URL: $hlsUrl');

        // Monitor HLS performance
        await HLSPerformanceMonitor().monitorHLSPerformance(
          videoId: video.id,
          videoUrl: hlsUrl,
          hlsType: 'master',
          onStart: () =>
              print('🚀 HLS Master loading started for video ${video.id}'),
          onComplete: () =>
              print('✅ HLS Master loading completed for video ${video.id}'),
          onError: (error) =>
              print('❌ HLS Master loading error for video ${video.id}: $error'),
        );

        controller = VideoPlayerController.networkUrl(
          Uri.parse(hlsUrl),
          videoPlayerOptions: _getHLSOptimizedOptions(),
          httpHeaders: _getHLSHeaders(),
        );
      } else if (video.hlsPlaylistUrl != null &&
          video.hlsPlaylistUrl!.isNotEmpty) {
        // Use HLS playlist URL for single quality streaming
        final hlsUrl = _buildHLSUrl(video.hlsPlaylistUrl!);
        print('🎬 VideoControllerManager: Using HLS playlist URL: $hlsUrl');

        // Monitor HLS performance
        await HLSPerformanceMonitor().monitorHLSPerformance(
          videoId: video.id,
          videoUrl: hlsUrl,
          hlsType: 'playlist',
          onStart: () =>
              print('🚀 HLS Playlist loading started for video ${video.id}'),
          onComplete: () =>
              print('✅ HLS Playlist loading completed for video ${video.id}'),
          onError: (error) => print(
              '❌ HLS Playlist loading error for video ${video.id}: $error'),
        );

        controller = VideoPlayerController.networkUrl(
          Uri.parse(hlsUrl),
          videoPlayerOptions: _getHLSOptimizedOptions(),
          httpHeaders: _getHLSHeaders(),
        );
      } else {
        // NO FALLBACK TO MP4 - Force HLS only
        throw Exception(
            'No HLS URLs available. Video must be converted to HLS streaming format (.m3u8) before playback.');
      }

      // Add error listener
      controller.addListener(() {
        if (controller.value.hasError) {
          print(
              '❌ Video controller error at index $index: ${controller.value.errorDescription}');
        }

        // Enhanced buffering state monitoring
        if (controller.value.isBuffering) {
          print('🔄 Video $index: Buffering...');
        } else if (controller.value.isInitialized &&
            !controller.value.isBuffering) {
          print('✅ Video $index: Buffering complete');
        }
      });

      await controller.initialize();

      // Enhanced initialization with INSTANT buffering optimization
      await _optimizeControllerForInstantPlayback(controller);

      controller.setLooping(true);
      controller.setVolume(0.0);

      _controllers[index] = controller;
      print(
          '✅ VideoControllerManager: Controller initialized for video $index');

      // Preload next video for instant switching (will be implemented later)
      // if (index < _activePage + _preloadDistance) {
      //   _preloadNextVideo(index + 1);
      // }
    } catch (error) {
      print(
          '❌ VideoControllerManager: Failed to initialize controller for video $index: $error');
      rethrow;
    }
  }

  /// Fallback method to initialize controller from network
  Future<void> _initControllerFromNetwork(int index, VideoModel video) async {
    try {
      print(
          '🌐 VideoControllerManager: Initializing from network for video $index');

      final controller =
          VideoPlayerController.networkUrl(Uri.parse(video.videoUrl));
      controller.addListener(() {
        if (controller.value.hasError) {
          print(
              'Video controller error at index $index: ${controller.value.errorDescription}');
        }
      });

      await controller.initialize();
      controller.setLooping(true);
      controller.setVolume(0.0);

      _controllers[index] = controller;
      print(
          '✅ VideoControllerManager: Controller initialized from network for video $index');
    } catch (e) {
      print('❌ Error initializing network video at index $index: $e');
    }
  }

  /// Optimize controller after initialization for better performance
  Future<void> _optimizeControllerAfterInit(
      VideoPlayerController controller) async {
    try {
      // Pre-buffer the video for smoother playback
      if (controller.value.isInitialized) {
        // Seek to beginning to trigger initial buffering
        await controller.seekTo(Duration.zero);

        // Set playback speed to 1.0 for optimal buffering
        await controller.setPlaybackSpeed(1.0);

        print(
            '🎬 VideoControllerManager: Controller optimized after initialization');
      }
    } catch (e) {
      print('⚠️ VideoControllerManager: Controller optimization failed: $e');
    }
  }

  /// Optimize controller for INSTANT playback (faster than smooth playback)
  Future<void> _optimizeControllerForInstantPlayback(
      VideoPlayerController controller) async {
    try {
      if (controller.value.isInitialized) {
        // Set minimal buffer for instant startup
        await controller.setPlaybackSpeed(1.0);

        // Pre-buffer first few seconds for instant playback
        await controller.seekTo(Duration.zero);

        // For HLS videos, trigger segment preloading
        if (controller.value.isInitialized) {
          // Preload first segment
          await controller.seekTo(const Duration(milliseconds: 100));
          await controller.seekTo(Duration.zero);

          // Set minimal buffer size for faster startup
          // This will be handled by the video player options
        }

        print(
            '🎬 VideoControllerManager: INSTANT playback optimization applied');
      }
    } catch (e) {
      print(
          '⚠️ VideoControllerManager: INSTANT playback optimization failed: $e');
    }
  }

  /// Set the active page and manage controllers
  void setActivePage(int newPage) {
    if (newPage != _activePage) {
      print(
          '🔄 VideoControllerManager: Setting active page from $_activePage to $newPage');

      // IMPORTANT: Pause ALL videos first to ensure clean state
      _pauseAllVideosImmediately();

      // Pause previous video specifically
      final previousController = _controllers[_activePage];
      if (previousController != null &&
          previousController.value.isInitialized) {
        try {
          if (previousController.value.isPlaying) {
            previousController.pause();
            print(
                '⏸️ VideoControllerManager: Paused previous video at index $_activePage');
          }
          // Mute the previous video
          previousController.setVolume(0.0);
        } catch (e) {
          print('❌ Error pausing previous video: $e');
        }
      }

      _activePage = newPage;

      // Ensure the new active video is properly set up
      final newActiveController = _controllers[_activePage];
      if (newActiveController != null &&
          newActiveController.value.isInitialized) {
        try {
          // Mute first, then unmute when ready to play
          newActiveController.setVolume(0.0);
          print(
              '🔇 VideoControllerManager: Muted new active video at index $_activePage');
        } catch (e) {
          print('❌ Error setting up new active video: $e');
        }
      }

      _optimizeControllers();
    }
  }

  /// Immediately pause all videos without any delay
  void _pauseAllVideosImmediately() {
    print('🛑 VideoControllerManager: IMMEDIATELY pausing all videos');
    int pausedCount = 0;

    for (var entry in _controllers.entries) {
      final index = entry.key;
      final controller = entry.value;

      try {
        if (controller.value.isInitialized) {
          if (controller.value.isPlaying) {
            controller.pause();
            pausedCount++;
            print(
                '🛑 VideoControllerManager: IMMEDIATELY paused video at index $index');
          }
          // Always mute videos during transitions
          controller.setVolume(0.0);
        }
      } catch (e) {
        print('❌ Error immediately pausing video at index $index: $e');
      }
    }

    print('🛑 VideoControllerManager: IMMEDIATELY paused $pausedCount videos');
  }

  /// Update active page (alias for setActivePage)
  void updateActivePage(int newPage) {
    setActivePage(newPage);
  }

  /// Optimize controllers - keep only needed ones active
  void _optimizeControllers() {
    final controllersToKeep = <int>{};

    // Keep current video
    if (_activePage >= 0) {
      controllersToKeep.add(_activePage);
    }

    // Keep previous 1 video
    if (_activePage > 0) {
      controllersToKeep.add(_activePage - 1);
    }

    // Keep next 2 videos
    for (int i = _activePage + 1; i <= _activePage + 2; i++) {
      controllersToKeep.add(i);
    }

    // Dispose unnecessary controllers - but be careful!
    final controllersToDispose = _controllers.keys
        .where((key) => !controllersToKeep.contains(key))
        .toList();

    for (final key in controllersToDispose) {
      try {
        final controller = _controllers[key];
        if (controller != null) {
          // IMPORTANT: Pause and mute before disposing
          if (controller.value.isInitialized) {
            if (controller.value.isPlaying) {
              controller.pause();
              print(
                  '⏸️ VideoControllerManager: Paused video at index $key before disposal');
            }
            controller.setVolume(0.0);
          }

          // Now dispose
          controller.dispose();
          _controllers.remove(key);
          print(
              '🗑️ VideoControllerManager: Safely disposed controller for index $key');
        }
      } catch (e) {
        print('❌ Error disposing controller at index $key: $e');
        // Remove from map even if disposal failed to prevent memory leaks
        _controllers.remove(key);
      }
    }

    print(
        '🎯 VideoControllerManager: Optimized controllers, kept ${controllersToKeep.length}, disposed ${controllersToDispose.length}');
  }

  /// Optimize controllers (public method)
  void optimizeControllers() {
    _optimizeControllers();
  }

  /// Play the active video
  void playActiveVideo() {
    final controller = _controllers[_activePage];
    if (controller != null && controller.value.isInitialized) {
      try {
        // First, ensure ALL other videos are paused and muted
        _pauseAllVideosImmediately();

        // Now set up the active video
        if (controller.value.volume == 0.0) {
          controller.setVolume(1.0);
          print(
              '🔊 VideoControllerManager: Unmuted active video at index $_activePage');
        }

        if (!controller.value.isPlaying) {
          controller.play();
          print(
              '▶️ VideoControllerManager: Playing active video at index $_activePage');
        } else {
          print(
              '▶️ VideoControllerManager: Active video at index $_activePage is already playing');
        }

        // Double-check that no other videos are playing
        _ensureOnlyActiveVideoPlaying();
      } catch (e) {
        print('❌ Error playing video at index $_activePage: $e');
      }
    } else {
      print(
          '⚠️ VideoControllerManager: Cannot play video at index $_activePage - controller not ready');
    }
  }

  /// Ensure only the active video is playing
  void _ensureOnlyActiveVideoPlaying() {
    int otherVideosPlaying = 0;

    for (var entry in _controllers.entries) {
      final index = entry.key;
      final controller = entry.value;

      if (index != _activePage &&
          controller.value.isInitialized &&
          controller.value.isPlaying) {
        try {
          controller.pause();
          controller.setVolume(0.0);
          otherVideosPlaying++;
          print(
              '🛑 VideoControllerManager: Stopped background video at index $index');
        } catch (e) {
          print('❌ Error stopping background video at index $index: $e');
        }
      }
    }

    if (otherVideosPlaying > 0) {
      print(
          '🛑 VideoControllerManager: Stopped $otherVideosPlaying background videos');
    }
  }

  /// Pause all videos
  void pauseAllVideos() {
    print('⏸️ VideoControllerManager: Pausing all videos');
    int pausedCount = 0;

    for (var entry in _controllers.entries) {
      final index = entry.key;
      final controller = entry.value;

      try {
        if (controller.value.isInitialized && controller.value.isPlaying) {
          controller.pause();
          pausedCount++;
          print('⏸️ VideoControllerManager: Paused video at index $index');
        }
      } catch (e) {
        print('❌ Error pausing controller at index $index: $e');
      }
    }

    print('⏸️ VideoControllerManager: Successfully paused $pausedCount videos');
  }

  /// Pause a specific video
  void pauseVideo(int index) {
    final controller = _controllers[index];
    if (controller != null && controller.value.isInitialized) {
      try {
        if (controller.value.isPlaying) {
          controller.pause();
          print('⏸️ VideoControllerManager: Paused video at index $index');
        }
      } catch (e) {
        print('❌ Error pausing video at index $index: $e');
      }
    }
  }

  /// Force pause all videos
  void forcePauseAllVideos() {
    print('🛑 VideoControllerManager: Force pausing all videos');
    int pausedCount = 0;

    for (var controller in _controllers.values) {
      try {
        if (controller.value.isInitialized) {
          if (controller.value.isPlaying) {
            controller.pause();
            pausedCount++;
          }
          controller.setVolume(0.0);
        }
      } catch (e) {
        print('❌ Error forcing pause controller: $e');
      }
    }

    print('🛑 VideoControllerManager: Successfully paused $pausedCount videos');
  }

  /// Get controller for specific index
  VideoPlayerController? getController(int index) {
    return _controllers[index];
  }

  /// Preload videos around index for better performance
  Future<void> preloadVideosAround(int index, List<VideoModel> videos) async {
    try {
      print('🎬 VideoControllerManager: Enhanced preloading for index $index');

      // Preload thumbnails for adjacent videos (instant preview)
      await _preloadThumbnails(index, videos);

      // Enhanced preload strategy: preload more videos for smoother experience
      const preloadRange = 3; // Preload 3 videos before and after
      final startIndex = (index - preloadRange).clamp(0, videos.length - 1);
      final endIndex = (index + preloadRange).clamp(0, videos.length - 1);

      // Preload controllers with priority for better performance
      final preloadTasks = <Future<void>>[];

      for (int i = startIndex; i <= endIndex; i++) {
        if (i != index && !_controllers.containsKey(i)) {
          // Prioritize immediate next/previous videos
          final priority = (i == index + 1 || i == index - 1) ? 1 : 2;

          preloadTasks
              .add(_preloadControllerWithPriority(i, videos[i], priority));
        }
      }

      // Execute preloading with priority
      await Future.wait(preloadTasks);

      print(
          '✅ VideoControllerManager: Enhanced preloading completed for range $startIndex-$endIndex');
    } catch (e) {
      print('❌ VideoControllerManager: Enhanced preloading error: $e');
    }
  }

  /// Preload controller with priority for better performance
  Future<void> _preloadControllerWithPriority(
      int index, VideoModel video, int priority) async {
    try {
      print(
          '🎬 VideoControllerManager: Preloading controller for index $index with priority $priority');

      // Add delay for lower priority videos to avoid overwhelming the system
      if (priority > 1) {
        await Future.delayed(Duration(milliseconds: priority * 100));
      }

      await initController(index, video);

      // Pre-buffer the video for smoother playback
      final controller = _controllers[index];
      if (controller != null && controller.value.isInitialized) {
        // Pre-buffer first few seconds
        await controller.seekTo(const Duration(seconds: 1));
        await controller.seekTo(Duration.zero);

        print('🎬 VideoControllerManager: Pre-buffered video at index $index');
      }
    } catch (e) {
      print('⚠️ VideoControllerManager: Preload failed for index $index: $e');
    }
  }

  /// Preload thumbnails for instant preview
  Future<void> _preloadThumbnails(
      int currentIndex, List<VideoModel> videos) async {
    try {
      const preloadRange = 3; // Preload 3 videos before and after
      final startIndex =
          (currentIndex - preloadRange).clamp(0, videos.length - 1);
      final endIndex =
          (currentIndex + preloadRange).clamp(0, videos.length - 1);

      print(
          '🖼️ VideoControllerManager: Preloading thumbnails for range $startIndex-$endIndex');

      for (int i = startIndex; i <= endIndex; i++) {
        if (i != currentIndex) {
          final video = videos[i];

          // Preload thumbnail if available
          if (video.thumbnailUrl.isNotEmpty) {
            try {
              // Use DefaultCacheManager to preload thumbnail
              await DefaultCacheManager().getSingleFile(video.thumbnailUrl);
              print(
                  '🖼️ VideoControllerManager: Thumbnail preloaded for index $i');
            } catch (e) {
              print(
                  '⚠️ VideoControllerManager: Thumbnail preload failed for index $i: $e');
            }
          }

          // Also preload video URL as fallback thumbnail
          if (video.videoUrl.isNotEmpty) {
            try {
              await DefaultCacheManager().getSingleFile(video.videoUrl);
              print(
                  '🖼️ VideoControllerManager: Video URL preloaded as thumbnail for index $i');
            } catch (e) {
              print(
                  '⚠️ VideoControllerManager: Video URL preload failed for index $i: $e');
            }
          }
        }
      }

      print('✅ VideoControllerManager: Thumbnail preloading completed');
    } catch (e) {
      print('❌ VideoControllerManager: Thumbnail preloading error: $e');
    }
  }

  /// Smart preloading based on user scrolling direction
  void smartPreloadBasedOnDirection(int newPage, List<VideoModel> videos) {
    final direction = newPage > _activePage ? 'forward' : 'backward';
    print(
        '🎯 VideoControllerManager: Smart preloading for $direction direction');

    if (direction == 'forward') {
      // Preload next 2-3 videos
      for (int i = newPage + 1; i <= newPage + 3 && i < videos.length; i++) {
        if (!_controllers.containsKey(i)) {
          initController(i, videos[i]);
        }
      }
    } else {
      // Preload previous 1-2 videos
      for (int i = newPage - 1; i >= newPage - 2 && i >= 0; i--) {
        if (!_controllers.containsKey(i)) {
          initController(i, videos[i]);
        }
      }
    }
  }

  /// Check video health and fix issues
  void checkVideoHealth() {
    final activeController = _controllers[_activePage];
    if (activeController != null && activeController.value.isInitialized) {
      // Add health check logic here
      // For now, just ensure volume is correct
      if (activeController.value.volume == 0.0) {
        activeController.setVolume(1.0);
      }
    }
  }

  /// Ensure all videos are paused (safety method)
  void ensureVideosPaused() {
    print('🛑 VideoControllerManager: Ensuring all videos are paused');
    int pausedCount = 0;

    for (var entry in _controllers.entries) {
      final index = entry.key;
      final controller = entry.value;

      try {
        if (controller.value.isInitialized && controller.value.isPlaying) {
          controller.pause();
          pausedCount++;
          print('🛑 VideoControllerManager: Paused video at index $index');
        }
      } catch (e) {
        print('❌ Error ensuring pause for video at index $index: $e');
      }
    }

    if (pausedCount > 0) {
      print(
          '🛑 VideoControllerManager: Successfully paused $pausedCount videos');
    }
  }

  /// Dispose all controllers
  void disposeAll() {
    print('🗑️ VideoControllerManager: Disposing all controllers');
    for (var controller in _controllers.values) {
      try {
        if (controller.value.isInitialized) {
          controller.pause();
          controller.setVolume(0.0);
          controller.dispose();
        }
      } catch (e) {
        print('❌ Error disposing controller: $e');
      }
    }
    _controllers.clear();
    print('✅ VideoControllerManager: All controllers disposed');
  }

  /// Dispose all controllers (alias for disposeAll)
  void disposeAllControllers() {
    disposeAll();
  }

  /// Check if controller exists and is ready
  bool isControllerReady(int index) {
    final controller = _controllers[index];
    return controller != null && controller.value.isInitialized;
  }

  /// Get total controller count
  int get controllerCount => _controllers.length;

  /// Check if any videos are still playing
  bool get hasPlayingVideos {
    for (var controller in _controllers.values) {
      try {
        if (controller.value.isInitialized && controller.value.isPlaying) {
          return true;
        }
      } catch (e) {
        print('❌ Error checking if video is playing: $e');
      }
    }
    return false;
  }

  /// Comprehensive pause method that ensures all videos are stopped
  void comprehensivePause() {
    print(
        '🛑 VideoControllerManager: Comprehensive pause - stopping all videos');

    // First, pause all videos normally
    pauseAllVideos();

    // Then force pause to ensure they're really stopped
    forcePauseAllVideos();

    // Finally, ensure they're paused one more time
    ensureVideosPaused();

    // Verify no videos are playing
    if (hasPlayingVideos) {
      print(
          '⚠️ VideoControllerManager: Some videos still playing after comprehensive pause');
      // One more attempt
      forcePauseAllVideos();
    } else {
      print('✅ VideoControllerManager: All videos successfully paused');
    }
  }

  /// Handle video becoming invisible (e.g., tab switch, app background)
  void handleVideoInvisible() {
    print(
        '🛑 VideoControllerManager: Video becoming invisible - pausing all videos');

    // Immediately pause all videos
    _pauseAllVideosImmediately();

    // Mute all videos to prevent any background audio
    for (var entry in _controllers.entries) {
      final index = entry.key;
      final controller = entry.value;

      try {
        if (controller.value.isInitialized) {
          controller.setVolume(0.0);
          print('🔇 VideoControllerManager: Muted video at index $index');
        }
      } catch (e) {
        print('❌ Error muting video at index $index: $e');
      }
    }

    print(
        '🛑 VideoControllerManager: All videos paused and muted for invisibility');
  }

  /// Handle video becoming visible again (e.g., returning to video tab)
  void handleVideoVisible() {
    print(
        '👁️ VideoControllerManager: Video becoming visible - preparing for playback');

    // Ensure only the active video is ready to play
    final activeController = _controllers[_activePage];
    if (activeController != null && activeController.value.isInitialized) {
      try {
        // Keep active video muted until explicitly told to play
        activeController.setVolume(0.0);
        print(
            '🔇 VideoControllerManager: Active video at index $_activePage ready but muted');
      } catch (e) {
        print('❌ Error preparing active video: $e');
      }
    }

    print('👁️ VideoControllerManager: Video visibility restored');
  }

  /// Emergency stop all videos (for critical situations)
  void emergencyStopAllVideos() {
    print(
        '🚨 VideoControllerManager: EMERGENCY STOP - stopping all videos immediately');

    int stoppedCount = 0;
    for (var entry in _controllers.entries) {
      final index = entry.key;
      final controller = entry.value;

      try {
        if (controller.value.isInitialized) {
          if (controller.value.isPlaying) {
            controller.pause();
            stoppedCount++;
          }
          controller.setVolume(0.0);
          print(
              '🚨 VideoControllerManager: Emergency stopped video at index $index');
        }
      } catch (e) {
        print('❌ Error emergency stopping video at index $index: $e');
      }
    }

    print('🚨 VideoControllerManager: Emergency stopped $stoppedCount videos');
  }

  /// Build optimized HLS URL with fallback support
  String _buildHLSUrl(String hlsUrl) {
    if (hlsUrl.startsWith('http')) {
      return hlsUrl;
    }

    // Try multiple fallback URLs for better reliability
    final fallbackUrls = [
      'http://192.168.0.190:5001', // Local network IP
      'http://10.0.2.2:5001', // Android emulator
      'http://localhost:5001', // Local development
    ];

    for (final baseUrl in fallbackUrls) {
      try {
        final fullUrl = '$baseUrl$hlsUrl';
        print('🔗 VideoControllerManager: Trying HLS URL: $fullUrl');
        return fullUrl;
      } catch (e) {
        print(
            '⚠️ VideoControllerManager: Failed to build URL with $baseUrl: $e');
      }
    }

    // Fallback to original URL
    return hlsUrl;
  }

  /// Get HLS optimized video player options for INSTANT startup
  VideoPlayerOptions _getHLSOptimizedOptions() {
    return VideoPlayerOptions(
      mixWithOthers: false,
      allowBackgroundPlayback: false,
      // Note: HLS-specific optimizations are handled by the video_player plugin automatically
      // The plugin will use optimal settings for HLS streaming
    );
  }

  /// Get standard VideoPlayerOptions for regular videos
  VideoPlayerOptions _getStandardOptions() {
    return VideoPlayerOptions(
      mixWithOthers: false,
      allowBackgroundPlayback: false,
      // Enhanced buffering for regular videos
    );
  }

  /// Get HLS headers for faster streaming
  Map<String, String> _getHLSHeaders() {
    return {
      'User-Agent': 'Snehayog-App/1.0',
      'Accept': 'application/vnd.apple.mpegurl, video/mp2t, */*',
      'Accept-Encoding': 'gzip, deflate',
      'Connection': 'keep-alive',
      // HLS specific headers for faster loading
      'Range': 'bytes=0-',
      'Cache-Control': 'no-cache',
    };
  }

  /// Get HLS performance insights for a specific video
  Map<String, dynamic>? getHLSPerformanceInsights(String videoId) {
    return HLSPerformanceMonitor().getVideoPerformance(videoId);
  }

  /// Get all HLS performance metrics
  Map<String, Map<String, dynamic>> getAllHLSPerformanceMetrics() {
    return HLSPerformanceMonitor().getAllMetrics();
  }

  /// Generate HLS performance report
  String generateHLSPerformanceReport() {
    return HLSPerformanceMonitor().generatePerformanceReport();
  }

  /// Get HLS performance recommendations for a video
  List<String> getHLSPerformanceRecommendations(String videoId) {
    final performance = HLSPerformanceMonitor().getVideoPerformance(videoId);
    if (performance != null && performance['recommendations'] != null) {
      return List<String>.from(performance['recommendations']);
    }
    return [];
  }

  /// Get enhanced network headers for better video streaming
  Map<String, String> _getEnhancedNetworkHeaders() {
    return {
      'User-Agent': 'Snehayog-App/1.0',
      'Accept': 'video/mp4, video/webm, video/ogg, */*',
      'Accept-Encoding': 'gzip, deflate',
      'Connection': 'keep-alive',
      'Range': 'bytes=0-', // Enable range requests
      'Cache-Control': 'max-age=3600', // Cache for 1 hour
    };
  }

  /// Check if HLS loading is slow for a specific video
  bool isHSLLoadingSlow(String videoId) {
    final performance = HLSPerformanceMonitor().getVideoPerformance(videoId);
    if (performance != null) {
      final masterMetrics = performance['master'];
      final playlistMetrics = performance['playlist'];

      // Check if loading time exceeds threshold (5 seconds)
      if (masterMetrics != null && masterMetrics['loadingTime'] != null) {
        return masterMetrics['loadingTime'] > 5000;
      }
      if (playlistMetrics != null && playlistMetrics['loadingTime'] != null) {
        return playlistMetrics['loadingTime'] > 5000;
      }
    }
    return false;
  }

  /// Get HLS loading time for a specific video
  int? getHSLLoadingTime(String videoId) {
    final performance = HLSPerformanceMonitor().getVideoPerformance(videoId);
    if (performance != null) {
      final masterMetrics = performance['master'];
      final playlistMetrics = performance['playlist'];

      // Return the fastest loading time
      int? masterTime = masterMetrics?['loadingTime'];
      int? playlistTime = playlistMetrics?['loadingTime'];

      if (masterTime != null && playlistTime != null) {
        return masterTime < playlistTime ? masterTime : playlistTime;
      } else if (masterTime != null) {
        return masterTime;
      } else if (playlistTime != null) {
        return playlistTime;
      }
    }
    return null;
  }
}
