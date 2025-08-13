import 'dart:async';
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

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

  /// Initialize a video player controller for the video at the given index
  Future<void> initController(int index, VideoModel video) async {
    if (index < 0 || _controllers.containsKey(index)) return;

    try {
      print(
          '🎬 VideoControllerManager: Initializing controller for video $index');

      // Use cache manager to get cached video file
      final file = await DefaultCacheManager().getSingleFile(video.videoUrl);
      print('✅ VideoControllerManager: Cached video file ready: ${file.path}');

      // Create video player controller from cached file
      final controller = VideoPlayerController.file(file);

      // Add error listener
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
          '✅ VideoControllerManager: Controller initialized for video $index');
    } catch (e) {
      print('❌ Error initializing video at index $index: $e');
      // Fallback to network
      await _initControllerFromNetwork(index, video);
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

  /// Preload videos around the given index
  Future<void> preloadVideosAround(int index, List<VideoModel> videos) async {
    final indicesToPreload = <int>{};

    // Add current index
    if (index >= 0 && index < videos.length) {
      indicesToPreload.add(index);
    }

    // Add previous 1 video
    if (index > 0) {
      indicesToPreload.add(index - 1);
    }

    // Add next 2 videos
    if (index < videos.length - 1) {
      indicesToPreload.add(index + 1);
    }
    if (index < videos.length - 2) {
      indicesToPreload.add(index + 2);
    }

    print(
        '🎯 VideoControllerManager: Preloading videos for indices: $indicesToPreload');

    final preloadFutures =
        indicesToPreload.map((i) => initController(i, videos[i]));
    await Future.wait(preloadFutures);

    print(
        '✅ VideoControllerManager: Preloaded ${indicesToPreload.length} videos');
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
}
