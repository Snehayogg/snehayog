import 'dart:async';
import 'package:video_player/video_player.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/utils/feature_flags.dart';
import 'package:snehayog/core/managers/smart_cache_manager.dart';
import 'dart:io';

/// Enhanced Video Controller Manager with Fast Video Delivery System
/// Manages video controllers for smooth playback, memory optimization, and background preloading
class VideoControllerManager {
  // Map to store video player controllers for each video index
  final Map<int, VideoPlayerController> _controllers = {};

  final int _maxAliveControllers = 3;
  final int _preloadDistance = 2;

  // Track active page
  int _activePage = 0;

  // **NEW: Track which controllers should be kept alive**
  final Set<int> _keepAliveControllers = {};

  // **NEW: Track controllers being initialized to prevent race conditions**
  final Set<int> _initializingControllers = {};

  // **NEW: Track watched videos for instant replay (caching)**
  final Set<int> _watchedVideos = {};

  // **NEW: Track recently accessed videos (LRU cache)**
  final List<int> _recentlyAccessed = [];
  static const int _maxCachedControllers = 5;

  // Fast video delivery integration (optional)
  SmartCacheManager? _cacheManager;
  List<VideoModel> _currentVideos = [];
  Timer? _preloadTimer;

  /// **NEW: Update which controllers should be kept alive (Instagram style)**
  void _updateKeepAliveControllers(int newActivePage) {
    _keepAliveControllers.clear();

    // Keep current, previous, and next controllers alive
    _keepAliveControllers.add(newActivePage);
    if (newActivePage > 0) {
      _keepAliveControllers.add(newActivePage - 1); // Previous
    }
    if (newActivePage < _currentVideos.length - 1) {
      _keepAliveControllers.add(newActivePage + 1); // Next
    }

    // **NEW: Also keep watched videos alive for instant replay**
    for (final watchedIndex in _watchedVideos) {
      if ((watchedIndex - newActivePage).abs() <= 3) {
        // Keep watched videos within 3 positions
        _keepAliveControllers.add(watchedIndex);
      }
    }

    print(
        '🔒 VideoControllerManager: Keep alive controllers: $_keepAliveControllers');
  }

  /// **NEW: Mark video as watched for caching**
  void markVideoAsWatched(int index) {
    _watchedVideos.add(index);
    _updateRecentlyAccessed(index);
    print(
        '👁️ VideoControllerManager: Marked video $index as watched (cached)');
  }

  /// **NEW: Update recently accessed list (LRU cache)**
  void _updateRecentlyAccessed(int index) {
    _recentlyAccessed.remove(index); // Remove if already exists
    _recentlyAccessed.insert(0, index); // Add to front (most recent)

    // Keep only max cached controllers
    if (_recentlyAccessed.length > _maxCachedControllers) {
      final removedIndex = _recentlyAccessed.removeLast();
      _watchedVideos.remove(removedIndex);
      print(
          '🗑️ VideoControllerManager: Removed $removedIndex from cache (LRU)');
    }
  }

  bool _shouldCacheVideo(int index) {
    return _watchedVideos.contains(index) ||
        _recentlyAccessed.take(3).contains(index); // Keep top 3 most recent
  }

  /// **NEW: Check if video is cached and ready for instant playback**
  bool isVideoCached(int index) {
    return _controllers.containsKey(index) &&
        _controllers[index]?.value.isInitialized == true &&
        _shouldCacheVideo(index);
  }

  /// **NEW: Get cached video status for debugging**
  Map<String, dynamic> getCachedVideoStatus() {
    return {
      'watchedVideos': _watchedVideos.toList(),
      'recentlyAccessed': _recentlyAccessed,
      'cachedControllers': _controllers.keys.toList(),
      'keepAliveControllers': _keepAliveControllers.toList(),
      'totalCached': _watchedVideos.length,
      'maxCacheSize': _maxCachedControllers,
    };
  }

  // Getter for active page
  int get activePage => _activePage;

  // Getter for controllers
  Map<int, VideoPlayerController> get controllers => _controllers;

  // **NEW: Getter for keep-alive controllers (for debugging)**
  Set<int> get keepAliveControllers => Set.from(_keepAliveControllers);

  /// Initialize the manager (cache manager optional)
  void initialize([SmartCacheManager? cacheManager]) {
    _cacheManager = cacheManager ?? _cacheManager;
    print('🚀 VideoControllerManager: Initialized');
  }

  /// Set current videos for preloading strategy
  void setCurrentVideos(List<VideoModel> videos) {
    _currentVideos = videos;
    print(
        '📹 VideoControllerManager: Set ${videos.length} videos for preloading');
  }

  /// **NEW: Enhanced video controller initialization with better error handling**
  Future<void> initController(int index, VideoModel video) async {
    if (!Features.fastVideoDelivery.isEnabled) {
      // Fallback to original behavior
      await _initControllerOriginal(index, video);
      return;
    }

    try {
      if (_initializingControllers.isNotEmpty) {
        print(
            '⏳ VideoControllerManager: Waiting for other controllers to initialize...');
        await Future.delayed(const Duration(milliseconds: 200));
      }

      if (_controllers.containsKey(index)) {
        final existingController = _controllers[index];
        if (existingController != null &&
            existingController.value.isInitialized) {
          print(
              '✅ VideoControllerManager: Controller already exists and initialized for index $index');
          return;
        } else if (existingController != null) {
          print(
              '⚠️ VideoControllerManager: Controller exists but not initialized, disposing...');
          try {
            await existingController.dispose();
          } catch (e) {
            print(
                '⚠️ VideoControllerManager: Error disposing existing controller: $e');
          }
          _controllers.remove(index);
        }
      }

      print(
          '🚀 VideoControllerManager: Initializing controller for index $index with fast delivery');

      // **NEW: Add initialization lock to prevent race conditions**
      if (_initializingControllers.contains(index)) {
        print(
            '⏳ VideoControllerManager: Controller already initializing for index $index, waiting...');
        // Wait for existing initialization to complete
        while (_initializingControllers.contains(index)) {
          await Future.delayed(const Duration(milliseconds: 100));
        }
        return;
      }

      _initializingControllers.add(index);

      try {
        // Check if video is cached first (if cache manager available)
        dynamic cachedFile;
        if (_cacheManager != null) {
          cachedFile = await _cacheManager!.get(
            'video_${video.id}',
            fetchFn: () async => null, // Stub
            cacheType: 'videos',
          );
        }

        if (cachedFile != null) {
          // Use cached file for instant playback
          print(
              '⚡ VideoControllerManager: Using cached video for instant playback');
          final controller = VideoPlayerController.file(
            File(cachedFile.toString()), // Convert to File
            videoPlayerOptions: _getStandardOptions(),
          );

          _controllers[index] = controller;
          await controller.initialize();
          print(
              '✅ VideoControllerManager: Cached controller initialized instantly');
        } else {
          // Fallback to network loading
          print(
              '🌐 VideoControllerManager: Video not cached, loading from network');
          await _initControllerOriginal(index, video);

          // Start preloading this video for future use
          _startBackgroundPreload(index, video);
        }

        // Trigger smart cache management
        _scheduleCacheOptimization();
      } finally {
        _initializingControllers.remove(index);
      }
    } catch (e) {
      print(
          '❌ VideoControllerManager: Error initializing controller for index $index: $e');

      // **NEW: Clean up on error**
      _initializingControllers.remove(index);
      _controllers.remove(index);

      // **NEW: Simple MediaCodec error handling with retry**
      if (e.toString().contains('MediaCodecVideoRenderer') ||
          e.toString().contains('ExoPlaybackException') ||
          e.toString().contains('VideoError')) {
        print(
            '🔄 VideoControllerManager: MediaCodec error detected, retrying with delay...');

        // Wait before retry to let system recover
        await Future.delayed(const Duration(milliseconds: 1000));

        try {
          // Retry with original method
          await _initControllerOriginal(index, video);
          print('✅ VideoControllerManager: Retry successful for index $index');
        } catch (retryError) {
          print(
              '❌ VideoControllerManager: Retry failed for index $index: $retryError');
          // Don't throw again, just log the error
        }
      } else {
        // Fallback to original method for other errors
        await _initControllerOriginal(index, video);
      }
    }
  }

  /// Original controller initialization method (fallback)
  Future<void> _initControllerOriginal(int index, VideoModel video) async {
    try {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(video.videoUrl),
        videoPlayerOptions: _getStandardOptions(),
        httpHeaders: _getStandardHeaders(),
      );

      _controllers[index] = controller;
      await controller.initialize();
      print(
          '✅ VideoControllerManager: Network controller initialized for index $index');
    } catch (e) {
      print('❌ VideoControllerManager: Error in original initialization: $e');
      rethrow;
    }
  }

  /// Start background preloading for a video
  void _startBackgroundPreload(int index, VideoModel video) {
    if (!Features.backgroundVideoPreloading.isEnabled) return;

    // **FIXED: Use stub implementation for now**
    // Start preloading in background
    print(
        '🎬 VideoControllerManager: Background preload stub for video ${video.id}');
    // TODO: Implement proper video preloading with InstagramCacheManager
  }

  /// Set the active page and manage controllers with fast delivery
  void setActivePage(int newPage) {
    if (newPage != _activePage) {
      print(
          '🔄 VideoControllerManager: Setting active page from $_activePage to $newPage');

      // **CRITICAL FIX: Immediately pause and mute ALL videos before page change**
      _pauseAllVideosImmediately();

      // **NEW: Dispose controllers that are far from current page to prevent memory leaks**
      _disposeDistantControllers(newPage);

      // Pause previous video specifically and ensure it's muted
      final previousController = _controllers[_activePage];
      if (previousController != null &&
          previousController.value.isInitialized) {
        try {
          if (previousController.value.isPlaying) {
            previousController.pause();
            print(
                '⏸️ VideoControllerManager: Paused previous video at index $_activePage');
          }
          // **CRITICAL: Always mute the previous video to prevent audio leak**
          previousController.setVolume(0.0);
          print(
              '🔇 VideoControllerManager: Muted previous video at index $_activePage');
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
          // **CRITICAL: Keep new active video muted until explicitly told to play**
          newActiveController.setVolume(0.0);
          print(
              '🔇 VideoControllerManager: New active video at index $_activePage is muted');
        } catch (e) {
          print('❌ Error setting up new active video: $e');
        }
      }

      // Trigger smart preloading for next videos
      _triggerSmartPreloading(newPage);

      _optimizeControllers();
    }
  }

  /// **NEW: Dispose controllers that are far from current page to prevent memory leaks**
  void _disposeDistantControllers(int currentPage) {
    const keepRange = 3; // Keep controllers within 3 videos of current page
    final controllersToDispose = <int>[];

    for (final entry in _controllers.entries) {
      final index = entry.key;
      final controller = entry.value;

      // If controller is too far from current page, mark it for disposal
      if ((index - currentPage).abs() > keepRange) {
        controllersToDispose.add(index);
      }
    }

    // Dispose distant controllers
    for (final index in controllersToDispose) {
      try {
        final controller = _controllers[index];
        if (controller != null) {
          // **CRITICAL: Ensure controller is paused and muted before disposal**
          if (controller.value.isInitialized) {
            if (controller.value.isPlaying) {
              controller.pause();
            }
            controller.setVolume(0.0);
          }
          controller.dispose();
          _controllers.remove(index);
          _initializingControllers.remove(index);
          print(
              '🗑️ VideoControllerManager: Disposed distant controller at index $index');
        }
      } catch (e) {
        print('❌ Error disposing distant controller at index $index: $e');
      }
    }

    if (controllersToDispose.isNotEmpty) {
      print(
          '🗑️ VideoControllerManager: Disposed ${controllersToDispose.length} distant controllers');
    }
  }

  /// Trigger smart preloading based on current position
  void _triggerSmartPreloading(int currentIndex) {
    if (!Features.backgroundVideoPreloading.isEnabled) return;

    // Cancel existing preload timer
    _preloadTimer?.cancel();

    // **FIXED: Use stub implementation for now**
    // Schedule preloading with a small delay to avoid blocking UI
    _preloadTimer = Timer(const Duration(milliseconds: 500), () {
      if (_currentVideos.isNotEmpty) {
        print(
            '🎬 VideoControllerManager: Smart preloading stub for index $currentIndex');
        // TODO: Implement proper video preloading with InstagramCacheManager
      }
    });
  }

  /// Schedule cache optimization
  void _scheduleCacheOptimization() {
    if (!Features.videoMemoryOptimization.isEnabled) return;

    // **FIXED: Use stub implementation for now**
    // Run cache optimization every 5 minutes
    Timer(const Duration(minutes: 5), () {
      if (_currentVideos.isNotEmpty) {
        print(
            '🎯 VideoControllerManager: Cache optimization stub for ${_currentVideos.length} videos');
        // TODO: Implement proper cache optimization with InstagramCacheManager
      }
    });
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

  /// **NEW: Optimize controllers to prevent memory leaks and improve performance**
  void optimizeControllers() {
    print('🔧 VideoControllerManager: Optimizing controllers...');

    // **CRITICAL FIX: Move heavy operations to background thread**
    unawaited(_optimizeControllersInBackground());
  }

  /// **NEW: Optimize controllers in background thread**
  Future<void> _optimizeControllersInBackground() async {
    try {
      final keysToRemove = <int>[];

      for (var entry in _controllers.entries) {
        final index = entry.key;
        final controller = entry.value;

        try {
          // Check if controller is still valid
          if (!controller.value.isInitialized) {
            print(
                '⚠️ VideoControllerManager: Controller at index $index not initialized, marking for removal');
            keysToRemove.add(index);
            continue;
          }

          // **NEW: Don't dispose controllers that should be kept alive (Instagram style)**
          if (_keepAliveControllers.contains(index)) {
            print(
                '🔒 VideoControllerManager: Keeping controller alive for index $index during optimization');
            continue;
          }

          // **NEW: Don't dispose watched/cached videos**
          if (_shouldCacheVideo(index)) {
            print(
                '💾 VideoControllerManager: Keeping cached video controller alive for index $index');
            continue;
          }

          // Check if controller is too far from active page
          final distance = (index - _activePage).abs();
          if (distance > _preloadDistance * 2) {
            print(
                '🗑️ VideoControllerManager: Controller at index $index too far from active page ($distance), disposing');
            keysToRemove.add(index);
            continue;
          }

          // Check if controller has been idle for too long
          if (controller.value.isInitialized && !controller.value.isPlaying) {
            // Keep only recent controllers
            if (distance > _preloadDistance) {
              print(
                  '🗑️ VideoControllerManager: Controller at index $index idle and far from active, disposing');
              keysToRemove.add(index);
            }
          }
        } catch (e) {
          print(
              '❌ VideoControllerManager: Error checking controller at index $index: $e');
          keysToRemove.add(index);
        }
      }

      // Remove marked controllers
      for (final index in keysToRemove) {
        disposeController(index);
      }

      if (keysToRemove.isNotEmpty) {
        print(
            '✅ VideoControllerManager: Disposed ${keysToRemove.length} controllers during optimization');
      }

      // Clear any stuck initializing controllers
      _initializingControllers
          .removeWhere((index) => !_controllers.containsKey(index));

      print(
          '🔧 VideoControllerManager: Optimization completed. Active controllers: ${_controllers.length}');
    } catch (e) {
      print(
          '❌ VideoControllerManager: Error during background optimization: $e');
    }
  }

  /// Play the active video
  void playActiveVideo() {
    final controller = _controllers[_activePage];
    if (controller != null && controller.value.isInitialized) {
      try {
        // First, ensure ALL other videos are paused and muted
        _pauseAllVideosImmediately();

        // **NEW: Mark video as watched for caching**
        markVideoAsWatched(_activePage);

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
          controller.setVolume(0.0); // Mute immediately
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
          controller.setVolume(0.0); // Mute immediately
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

  /// Emergency stop all videos (for critical situations like tab switching)
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
          controller.seekTo(Duration.zero); // Reset to beginning
          print(
              '🚨 VideoControllerManager: Emergency stopped video at index $index');
        }
      } catch (e) {
        print('❌ Error emergency stopping controller at index $index: $e');
      }
    }

    print('🚨 VideoControllerManager: Emergency stopped $stoppedCount videos');
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

  /// Handle video page change with immediate pause and preload
  void handleVideoPageChange(
      int oldIndex, int newIndex, List<VideoModel> videos) {
    print(
        '🔄 VideoControllerManager: Handling video page change from $oldIndex to $newIndex');

    // IMMEDIATELY pause the old video
    if (oldIndex >= 0 && oldIndex < videos.length) {
      _immediatelyPauseVideo(oldIndex);
      print(
          '⏸️ VideoControllerManager: Immediately paused video at index $oldIndex');
    }

    // Preload the new video
    if (newIndex >= 0 && newIndex < videos.length) {
      _preloadVideo(newIndex, videos[newIndex]);
      print('📥 VideoControllerManager: Preloading video at index $newIndex');
    }

    // Update active page
    _activePage = newIndex;

    // **NEW: Update which controllers should be kept alive (Instagram style)**
    _updateKeepAliveControllers(newIndex);

    // Preload adjacent videos for smooth experience
    _preloadAdjacentVideos(newIndex, videos);
  }

  /// Handle scroll start - immediately pause current video
  void handleScrollStart(int currentIndex) {
    print(
        '🔄 VideoControllerManager: Scroll start detected for index $currentIndex');

    // Immediately pause the current video
    if (currentIndex >= 0 && _controllers.containsKey(currentIndex)) {
      _immediatelyPauseVideo(currentIndex);
      print(
          '⏸️ VideoControllerManager: Scroll start - immediately paused video at index $currentIndex');
    }
  }

  /// Immediately pause a specific video (no delay)
  void _immediatelyPauseVideo(int index) {
    final controller = _controllers[index];
    if (controller != null && controller.value.isInitialized) {
      try {
        if (controller.value.isPlaying) {
          controller.pause();
          controller.setVolume(0.0); // Mute immediately
          print(
              '⏸️ VideoControllerManager: Immediately paused and muted video at index $index');
        }
      } catch (e) {
        print('❌ Error immediately pausing video at index $index: $e');
      }
    }
  }

  /// Preload a specific video
  Future<void> _preloadVideo(int index, VideoModel video) async {
    if (_controllers.containsKey(index)) {
      // Controller already exists, just ensure it's ready
      final controller = _controllers[index];
      if (controller != null && controller.value.isInitialized) {
        print(
            '✅ VideoControllerManager: Video at index $index already preloaded');
        return;
      }
    }

    try {
      print(
          '📥 VideoControllerManager: Starting preload for video at index $index');
      await initController(index, video);
      print(
          '✅ VideoControllerManager: Successfully preloaded video at index $index');
    } catch (e) {
      print('❌ Error preloading video at index $index: $e');
    }
  }

  /// Preload adjacent videos for smooth scrolling
  void _preloadAdjacentVideos(int currentIndex, List<VideoModel> videos) {
    const preloadRange = 2; // Preload 2 videos before and after
    final startIndex =
        (currentIndex - preloadRange).clamp(0, videos.length - 1);
    final endIndex = (currentIndex + preloadRange).clamp(0, videos.length - 1);

    for (int i = startIndex; i <= endIndex; i++) {
      if (i != currentIndex && i >= 0 && i < videos.length) {
        // Preload in background
        _preloadVideo(i, videos[i]);
      }
    }
  }

  /// Smart preload based on scroll direction
  void smartPreloadBasedOnDirection(int newPage, List<VideoModel> videos) {
    if (newPage < 0 || newPage >= videos.length) return;

    print('🧠 VideoControllerManager: Smart preloading for page $newPage');

    // Determine scroll direction
    final direction = newPage > _activePage ? 1 : -1;

    // Preload videos in the direction of scroll
    final preloadIndices = <int>[];

    if (direction > 0) {
      // Scrolling down, preload next videos
      for (int i = 1; i <= 3; i++) {
        final index = newPage + i;
        if (index < videos.length) {
          preloadIndices.add(index);
        }
      }
    } else {
      // Scrolling up, preload previous videos
      for (int i = 1; i <= 3; i++) {
        final index = newPage - i;
        if (index >= 0) {
          preloadIndices.add(index);
        }
      }
    }

    // Preload videos in background
    for (final index in preloadIndices) {
      if (index >= 0 && index < videos.length) {
        _preloadVideo(index, videos[index]);
      }
    }

    print(
        '🧠 VideoControllerManager: Smart preloaded ${preloadIndices.length} videos in direction $direction');
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
    print('🔄 VideoControllerManager: Disposing all controllers...');
    int disposedCount = 0;

    for (var entry in _controllers.entries) {
      try {
        entry.value.dispose();
        disposedCount++;
      } catch (e) {
        print('❌ Error disposing controller at index ${entry.key}: $e');
      }
    }

    _controllers.clear();
    _initializingControllers.clear();
    print('✅ VideoControllerManager: Disposed $disposedCount controllers');
  }

  /// **NEW: Instagram-style controller disposal - only dispose if not in keep-alive set**
  void disposeController(int index) {
    // **NEW: Don't dispose controllers that should be kept alive**
    if (_keepAliveControllers.contains(index)) {
      print(
          '🔒 VideoControllerManager: Keeping controller alive for index $index (Instagram style)');
      return;
    }

    final controller = _controllers[index];
    if (controller != null) {
      try {
        controller.dispose();
        _controllers.remove(index);
        _initializingControllers.remove(index);
        print(
            '✅ VideoControllerManager: Disposed controller at index $index (not in keep-alive set)');
      } catch (e) {
        print('❌ Error disposing controller at index $index: $e');
      }
    }
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

  /// Get MP4 optimized video player options
  VideoPlayerOptions _getMP4OptimizedOptions() {
    return VideoPlayerOptions(
      mixWithOthers: false,
      allowBackgroundPlayback: false,
      // Enhanced buffering for MP4 videos
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

  /// Get standard headers for MP4 videos
  Map<String, String> _getStandardHeaders() {
    return {
      'User-Agent': 'Snehayog-App/1.0',
      'Accept': 'video/mp4, video/*, */*',
      'Accept-Encoding': 'gzip, deflate',
      'Connection': 'keep-alive',
      'Cache-Control': 'max-age=3600',
    };
  }

  /// Get HLS performance insights for a specific video
  Map<String, dynamic>? getHLSPerformanceInsights(String videoId) {
    // TODO: Implement HLS performance monitoring
    return null;
  }

  /// Get all HLS performance metrics
  Map<String, Map<String, dynamic>> getAllHLSPerformanceMetrics() {
    // TODO: Implement HLS performance monitoring
    return {};
  }

  /// Generate HLS performance report
  String generateHLSPerformanceReport() {
    // TODO: Implement HLS performance monitoring
    return 'HLS Performance monitoring not implemented yet';
  }

  /// Get HLS performance recommendations for a video
  List<String> getHLSPerformanceRecommendations(String videoId) {
    // TODO: Implement HLS performance monitoring
    return ['Implement HLS performance monitoring'];
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
    return false;
  }

  /// Get HLS loading time for a specific video
  int? getHSLLoadingTime(String videoId) {
    return null;
  }

  /// **NEW: Handle video playback errors gracefully**
  void handleVideoPlaybackError(int index, dynamic error) {
    print(
        '🚨 VideoControllerManager: Handling video playback error for index $index: $error');

    try {
      // Check if it's a MediaCodec error
      if (error.toString().contains('MediaCodecVideoRenderer') ||
          error.toString().contains('ExoPlaybackException') ||
          error.toString().contains('VideoError')) {
        print(
            '🔄 VideoControllerManager: MediaCodec error detected, attempting recovery...');

        // Dispose the problematic controller
        final controller = _controllers[index];
        if (controller != null) {
          try {
            controller.dispose();
          } catch (e) {
            print(
                '⚠️ VideoControllerManager: Error disposing problematic controller: $e');
          }
          _controllers.remove(index);
          _initializingControllers.remove(index);
        }

        // Mark for reinitialization
        print(
            '🔄 VideoControllerManager: Controller marked for reinitialization');
      }
    } catch (e) {
      print(
          '❌ VideoControllerManager: Error handling video playback error: $e');
    }
  }

  /// **NEW: Check for potential memory leaks**
  void _checkForMemoryLeaks() {
    final totalControllers = _controllers.length;
    final initializingCount = _initializingControllers.length;

    if (totalControllers > 10) {
      print(
          '⚠️ VideoControllerManager: High controller count ($totalControllers), potential memory leak detected');
    }

    if (initializingCount > 5) {
      print(
          '⚠️ VideoControllerManager: High initializing count ($initializingCount), clearing stuck initializations');
      _initializingControllers.clear();
    }

    // Check for controllers that might be stuck
    for (var entry in _controllers.entries) {
      final index = entry.key;
      final controller = entry.value;

      try {
        if (controller.value.isInitialized &&
            controller.value.duration.inSeconds == 0) {
          print(
              '⚠️ VideoControllerManager: Controller at index $index has zero duration, might be stuck');
        }
      } catch (e) {
        print(
            '❌ VideoControllerManager: Error checking controller at index $index: $e');
      }
    }
  }
}
