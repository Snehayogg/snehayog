import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:video_player/video_player.dart';
import 'package:vayu/core/managers/video_position_cache_manager.dart';
import 'package:vayu/core/managers/hot_ui_state_manager.dart';
import 'package:vayu/core/factories/video_controller_factory.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/core/utils/video_disposal_utils.dart';
import 'dart:collection';
import 'dart:async';
import 'package:vayu/utils/app_logger.dart';

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

  final int maxPoolSize = 3; // **INCREASED: From 1 to 3 for smoother scrolling in debug mode**

  /// Choose a playback URL preferring Cloudflare/R2 or backend HLS over Cloudinary
  String _selectPlaybackUrl(VideoModel video) {

    // Prefer explicit HLS URLs if present (served by backend/CDN)
    if (video.hlsMasterPlaylistUrl != null &&
        video.hlsMasterPlaylistUrl!.isNotEmpty) {
      AppLogger.log('✅ SELECTED: HLS Master Playlist');
      return video.hlsMasterPlaylistUrl!;
    }
    if (video.hlsPlaylistUrl != null && video.hlsPlaylistUrl!.isNotEmpty) {
      AppLogger.log('✅ SELECTED: HLS Playlist');
      return video.hlsPlaylistUrl!;
    }

    // Prefer lowQualityUrl if it's Cloudflare/CDN
    if (video.lowQualityUrl != null && video.lowQualityUrl!.isNotEmpty) {
      final lower = video.lowQualityUrl!.toLowerCase();
      if (lower.contains('cdn.snehayog.site') ||
          lower.contains('cdn.snehayog.com') ||
          lower.contains('r2.cloudflarestorage.com')) {
        AppLogger.log('✅ SELECTED: Low Quality URL (CDN/R2)');
        return video.lowQualityUrl!;
      }
    }

    // Avoid Cloudinary for playback when possible; if original is Cloudflare/CDN use it
    final origLower = video.videoUrl.toLowerCase();
    final isCdn = origLower.contains('cdn.snehayog.site') ||
        origLower.contains('cdn.snehayog.com') ||
        origLower.contains('r2.cloudflarestorage.com') ||
        origLower.contains('/hls/');
    if (isCdn) {
      AppLogger.log('✅ SELECTED: Original Video URL (CDN/R2/HLS)');
      return video.videoUrl;
    }

    // Fallback: use lowQualityUrl even if not CDN, else original
    if (video.lowQualityUrl != null && video.lowQualityUrl!.isNotEmpty) {
      AppLogger.log('⚠️ FALLBACK: Low Quality URL');
      return video.lowQualityUrl!;
    }

    AppLogger.log('⚠️ FALLBACK: Original Video URL');
    return video.videoUrl;
  }

  /// Get URL source type for debugging
  String _getUrlSource(String url) {
    final lower = url.toLowerCase();

    if (lower.contains('r2.cloudflarestorage.com') ||
        lower.contains('r2.dev')) {
      return '🟢 CLOUDFLARE R2 (Best - Fast CDN)';
    }
    if (lower.contains('cdn.snehayog.site') ||
        lower.contains('cdn.snehayog.com')) {
      return '🟢 CUSTOM CDN (Good)';
    }
    if (lower.contains('/hls/')) {
      return '🟡 BACKEND HLS (Local Server)';
    }
    if (lower.contains('cloudinary.com')) {
      return '🔴 CLOUDINARY (Slow - Avoid)';
    }
    if (lower.contains('.m3u8')) {
      return '🟡 HLS STREAMING';
    }
    if (lower.contains('localhost') ||
        lower.contains('127.0.0.1') ||
        lower.contains('10.0.2.2')) {
      return '🟡 LOCALHOST (Development)';
    }

    return '⚪ UNKNOWN SOURCE';
  }

  Future<VideoPlayerController> getController(
      int index, VideoModel video) async {
    // Decide final URL without Cloudinary signing (prefer Cloudflare/CDN)
    String finalUrl = _selectPlaybackUrl(video);
    // AppLogger.log('🎯 VideoControllerManager: Selected playback URL: $finalUrl');

    // **OPTIMIZED: Reuse existing controller if available and valid**
    if (_controllers.containsKey(index)) {
      final existingController = _controllers[index];
      if (existingController != null &&
          existingController.value.isInitialized &&
          !existingController.value.hasError) {
        AppLogger.log(
            '♻️ VideoControllerManager: Reusing existing controller $index');
        return existingController;
      } else {
        AppLogger.log(
            '🔄 VideoControllerManager: Disposing invalid controller $index');
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
      AppLogger.log(
          '🗑️ VideoControllerManager: Disposing distant controller $key');
      _disposeController(key);
    }

    // Create video model with signed URL if needed
    final videoWithSignedUrl =
        finalUrl != video.videoUrl ? video.copyWith(videoUrl: finalUrl) : video;

    // Use VideoControllerFactory to create optimized controller
    final controller =
        await VideoControllerFactory.createController(videoWithSignedUrl);

    try {
      // **WEB FIX: Web video player initialization may need longer timeout or different handling**
     const timeoutDuration =
          kIsWeb ? Duration(seconds: 15) : Duration(seconds: 10);
      await controller.initialize().timeout(
        timeoutDuration,
        onTimeout: () {
          throw TimeoutException(
              'Video initialization timeout', timeoutDuration);
        },
      ).catchError((error) {
        // **WEB FIX: Catch platform channel errors on web**
        AppLogger.log(
          '⚠️ VideoControllerManager: Video initialization error (may be web-specific): $error',
          isError: true,
        );
        // Re-throw to let caller handle
        throw error;
      });

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

      AppLogger.log(
          '✅ VideoControllerManager: Successfully created controller using VideoControllerFactory for ${video.videoName} with position caching');
      return controller;
    } catch (e) {
      AppLogger.log(
          '❌ VideoControllerManager: Failed to initialize controller for ${video.videoName}: $e');

      // Try fallback URL if this is an HLS URL
      if (finalUrl.contains('.m3u8')) {
        final fallbackUrl = _getFallbackUrl(finalUrl);
        if (fallbackUrl != finalUrl) {
          AppLogger.log(
              '🔄 VideoControllerManager: Trying fallback URL: $fallbackUrl');
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
    );

    return getController(index, video);
  }

  /// Preload controller but don't play yet using VideoModel
  Future<void> preloadController(int index, VideoModel video) async {
    try {
      AppLogger.log(
          '🚀 VideoControllerManager: Preloading controller $index for ${video.videoName}');

      // **SIMPLIFIED: Direct video controller creation for 480p videos**
      AppLogger.log(
          '🎬 VideoControllerManager: Preloading 480p video for ${video.videoName}');

      await getController(index, video);
      _warmNetwork(video.videoUrl);
    } catch (e) {
      AppLogger.log(
          '❌ VideoControllerManager: Error preloading controller $index: $e');
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
    );

    await preloadController(index, video);
  }

  /// Play controller instantly (already initialized)
  Future<void> playController(int index) async {
    if (_controllers.containsKey(index)) {
      final controller = _controllers[index]!;
      if (controller.value.isInitialized && !controller.value.hasError) {
        // **AUDIO FIX: Pause/mute all other videos before playing to prevent overlap**
        for (final entry in _controllers.entries) {
          if (entry.key != index) {
            try {
              await entry.value.pause();
              entry.value.setVolume(0.0);
              _intentionallyPaused.add(entry.key);
            } catch (_) {}
          }
        }

        // If the video is at the end (or very close), reset to start before playing
        final duration = controller.value.duration;
        final position = controller.value.position;
        if (duration.inMilliseconds > 0 &&
            (position >= duration - const Duration(milliseconds: 300))) {
          try {
            await controller.seekTo(Duration.zero);
          } catch (_) {}
        }
        try {
          controller.setVolume(1.0);
        } catch (_) {}
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

  /// **IMPROVED: Pause all videos but keep controllers in memory (better UX)**
  Future<void> pauseAllVideos() async {
    AppLogger.log(
        '⏸️ VideoControllerManager: Pausing all videos (keeping controllers)');

    for (final index in _controllers.keys) {
      try {
        final controller = _controllers[index];
        if (controller != null &&
            controller.value.isInitialized &&
            controller.value.isPlaying) {
          await controller.pause();
          _intentionallyPaused.add(index);
          AppLogger.log(
              '⏸️ VideoControllerManager: Paused video at index $index');
        }
      } catch (e) {
        AppLogger.log(
            '⚠️ VideoControllerManager: Error pausing video $index: $e');
      }
    }

    AppLogger.log(
        '✅ VideoControllerManager: All videos paused (controllers kept in memory)');
  }

  /// **LEGACY: Force pause all videos with volume muting (for critical situations)**
  Future<void> forcePauseAllVideos() async {
    AppLogger.log(
        '🛑 VideoControllerManager: Force pausing all videos and clearing audio');

    for (final index in _controllers.keys) {
      try {
        final controller = _controllers[index];
        if (controller != null) {
          // **FIX: Force pause and mute immediately**
          await controller.pause();
          controller.setVolume(0.0);
          _intentionallyPaused.add(index);
          AppLogger.log(
              '🔇 VideoControllerManager: Paused and muted controller at index $index');
        }
      } catch (e) {
        AppLogger.log(
            '⚠️ VideoControllerManager: Error pausing controller at index $index: $e');
      }
    }

    // **FIX: Clear all controller states to prevent audio overlap**
    _intentionallyPaused.clear();
    AppLogger.log(
        '✅ VideoControllerManager: All videos paused and states cleared');
  }

  /// **ENHANCED: Force clear all controllers to ensure single video playback**
  Future<void> forceClearAllControllers() async {
    AppLogger.log(
        '🧹 VideoControllerManager: Force clearing all controllers for single video playback');

    // **CRITICAL: Pause and dispose all controllers immediately**
    for (final index in _controllers.keys) {
      try {
        final controller = _controllers[index];
        if (controller != null) {
          // **ENHANCED: Force pause and mute before disposal**
          await controller.pause();
          controller.setVolume(0.0);
          await controller.dispose();
          AppLogger.log(
              '🗑️ VideoControllerManager: Disposed and muted controller at index $index');
        }
      } catch (e) {
        AppLogger.log(
            '⚠️ VideoControllerManager: Error disposing controller at index $index: $e');
      }
    }

    // **CRITICAL: Clear all maps and sets to prevent any video overlap**
    _controllers.clear();
    _order.clear();
    _pinned.clear();
    _intentionallyPaused.clear();
    _controllerSourceUrl.clear();
    _controllerVideoIds.clear();

    AppLogger.log(
        '✅ VideoControllerManager: All controllers cleared - single video playback ensured');
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
    AppLogger.log('🗑️ VideoControllerManager: Disposing all controllers');
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

        // **POSITION CACHING: Stop tracking position for this video**
        final videoId = _controllerVideoIds[index];
        if (videoId != null) {
          _positionCache.stopPositionTracking(controller);
        }

        // **CACHING: Only dispose if we have too many controllers**
        if (_controllers.length > maxPoolSize) {
          // **MEMORY: Use disposal utility for proper cleanup**
          VideoDisposalUtils.disposeController(controller,
              identifier: 'manager_index_$index');
          _controllers.remove(index);
          _order.removeWhere((i) => i == index);
          _intentionallyPaused.remove(index);
          _controllerSourceUrl.remove(index);
          _controllerVideoIds.remove(index);
        } else {
          // **CACHING: Keep controller in cache but pause it**
          controller.pause();
          controller.setVolume(0.0);
          _intentionallyPaused.add(index);
          AppLogger.log(
              '💾 VideoControllerManager: Cached controller $index for reuse');
        }

        // **FORCE: Small delay to ensure MediaCodec cleanup**
        Future.delayed(const Duration(milliseconds: 50), () {
          AppLogger.log(
              '✅ VideoControllerManager: MediaCodec cleanup completed for controller $index');
        });
      } catch (e) {
        AppLogger.log(
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
    AppLogger.log(
        '🌐 VideoControllerManager: Network warming for 480p video: $url');
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
    AppLogger.log(
        '🗑️ VideoControllerManager: Clearing all controllers and freeing MediaCodec memory');

    for (final entry in _controllers.entries) {
      try {
        final controller = entry.value;
        final index = entry.key;

        // **POSITION CACHING: Stop tracking position for this video**
        final videoId = _controllerVideoIds[index];
        if (videoId != null) {
          _positionCache.stopPositionTracking(controller);
        }

        // Use the disposal utility for proper cleanup
        VideoDisposalUtils.disposeController(controller,
            identifier: 'manager_index_$index');
      } catch (e) {
        AppLogger.log(
            '❌ VideoControllerManager: Error disposing controller ${entry.key}: $e');
      }
    }

    _controllers.clear();
    _order.clear();
    _pinned.clear();
    _intentionallyPaused.clear();
    _controllerSourceUrl.clear();
    _controllerVideoIds.clear();

    // **FORCE: Delay to ensure MediaCodec cleanup completes**
    Future.delayed(const Duration(milliseconds: 100), () {
      AppLogger.log('✅ VideoControllerManager: All MediaCodec resources freed');
    });
  }

  /// **NEW: Handle app lifecycle changes**
  void onAppPaused() {
    AppLogger.log('⏸️ VideoControllerManager: App paused - pausing all videos');
    pauseAllVideos();
  }

  void onAppResumed() {
    AppLogger.log('▶️ VideoControllerManager: App resumed');
    // Don't auto-resume videos - let user decide
  }

  void onAppDetached() {
    AppLogger.log(
        '🔌 VideoControllerManager: App detached - disposing all controllers');
    clear();
  }

  /// **NEW: Comprehensive dispose method for complete cleanup**
  void dispose() {
    AppLogger.log(
        '🗑️ VideoControllerManager: Starting comprehensive disposal...');

    // Clear all controllers
    clear();

    // Dispose position cache manager
    _positionCache.dispose();

    // Dispose hot UI state manager
    _hotUIManager.dispose();

    AppLogger.log('✅ VideoControllerManager: Comprehensive disposal completed');
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
    AppLogger.log(
        '⏸️ VideoControllerManager: Tab change detected - pausing all videos');

    for (final index in _controllers.keys) {
      final controller = _controllers[index];
      if (controller != null) {
        try {
          if (controller.value.isInitialized && controller.value.isPlaying) {
            await controller.pause();
            _intentionallyPaused.add(index);
            AppLogger.log(
                '⏸️ VideoControllerManager: Paused video at index $index');
          }
        } catch (e) {
          AppLogger.log(
              '⚠️ VideoControllerManager: Error handling controller at index $index: $e');
        }
      }
    }
  }

  /// **TAB CHANGE DETECTION: Resume videos when returning to video tab**
  Future<void> resumeVideosOnTabReturn() async {
    AppLogger.log(
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
            AppLogger.log(
                '▶️ VideoControllerManager: Resumed video at index $activeIndex');
          } catch (e) {
            AppLogger.log(
                '❌ VideoControllerManager: Error resuming video at index $activeIndex: $e');
          }
        }
      }
    }
  }

  /// **TAB CHANGE DETECTION: Force pause all videos immediately (for critical situations)**
  void forcePauseAllVideosSync() {
    AppLogger.log(
        '🛑 VideoControllerManager: Force pausing all videos immediately');

    for (final index in _controllers.keys) {
      final controller = _controllers[index];
      if (controller != null && controller.value.isInitialized) {
        try {
          controller.pause();
          _intentionallyPaused.add(index);
        } catch (e) {
          AppLogger.log(
              '❌ VideoControllerManager: Error force pausing video at index $index: $e');
        }
      }
    }
  }

  void saveUIStateForBackground(
      int currentIndex, double scrollPosition, Map<int, VideoModel> videos) {
    AppLogger.log('💾 VideoControllerManager: Saving UI state for background');

    _hotUIManager.saveUIState(
      currentIndex: currentIndex,
      scrollPosition: scrollPosition,
      controllers: _controllers,
      videos: videos,
    );
  }

  /// **HOT UI: Restore state when app comes to foreground**
  Map<String, dynamic>? restoreUIStateFromBackground() {
    AppLogger.log(
        '🔄 VideoControllerManager: Restoring UI state from background');

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
