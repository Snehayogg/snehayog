// video_loading_manager.dart
import 'dart:async';
import 'package:video_player/video_player.dart';
import 'video_cache_manager.dart';
import 'video_controller_manager.dart';
import 'progressive_video_cache_manager.dart';
import 'network_monitor.dart';
import 'package:snehayog/model/video_model.dart';

/// How many videos to keep prepared around the viewport
class PreloadProfile {
  final int ahead; // how many ahead to preload
  final int behind; // how many behind to keep warm
  final int concurrency; // parallel downloads/initializations
  const PreloadProfile({
    required this.ahead,
    required this.behind,
    required this.concurrency,
  });

  /// Good defaults:
  /// - wifi/high-end: PreloadProfile(ahead: 3, behind: 1, concurrency: 3)
  /// - mobile/low-end: PreloadProfile(ahead: 1, behind: 1, concurrency: 2)
  static const aggressive = PreloadProfile(ahead: 3, behind: 1, concurrency: 3);
  static const balanced = PreloadProfile(ahead: 2, behind: 1, concurrency: 2);
  static const lite = PreloadProfile(ahead: 1, behind: 1, concurrency: 2);
}

/// Provide VideoModel for a given index (you can map your own model to this)
typedef VideoModelAt = VideoModel Function(int index);

/// Internal task with priority (lower value = higher priority)
class _PreloadTask {
  final int index;
  final VideoModel video;
  final int priority; // 0 = current, 1 = next, 2 = next+1, 3 = previous, etc.
  int attempts = 0;
  _PreloadTask({
    required this.index,
    required this.video,
    required this.priority,
  });
}

class VideoLoadingManager {
  static final VideoLoadingManager _instance = VideoLoadingManager._internal();
  factory VideoLoadingManager() => _instance;
  VideoLoadingManager._internal();

  final _cache = VideoCacheManager();
  final _controllers = VideoControllerManager();
  final _progressiveCache = ProgressiveVideoCacheManager();
  final _networkMonitor = NetworkMonitor();

  PreloadProfile _profile = PreloadProfile.lite;
  VideoModelAt? _videoAt;
  int _itemCount = 0;
  int _epoch = 0;
  bool _initialized = false;

  final Set<int> _inProgress = {};

  /// **INITIALIZE**: Start with progressive streaming
  Future<void> init({
    required PreloadProfile profile,
    required VideoModelAt videoAt,
    required int itemCount,
  }) async {
    _profile = profile;
    _videoAt = videoAt;
    _itemCount = itemCount;
    _initialized = true;

    // **PROGRESSIVE STREAMING**: Initialize cache with network monitoring
    await _cache.init();
    await _progressiveCache.initialize();
    await _networkMonitor.startMonitoring();

    print('✅ VideoLoadingManager: Initialized with progressive streaming');
  }

  /// **PROGRESSIVE STREAMING**: Use adaptive streaming instead of full downloads
  Future<void> _runTask(_PreloadTask task, int epochAtStart) async {
    // If a new viewport came in, abort silently
    if (epochAtStart != _epoch) return;

    // **PROGRESSIVE STREAMING**: Start adaptive streaming immediately
    try {
      print(
          '🚀 VideoLoadingManager: Starting progressive streaming for ${task.video.videoName}');
      print('📊 Network Quality: ${_networkMonitor.currentQuality}');

      // **PROGRESSIVE CACHE**: Start progressive streaming
      _progressiveCache.getProgressiveStream(task.video.videoUrl).listen(
        (chunk) {
          // Data is being streamed progressively
          print('📥 Received chunk: ${chunk.length} bytes');
        },
        onError: (error) {
          print('❌ Progressive streaming error: $error');
        },
        onDone: () {
          print(
              '✅ Progressive streaming completed for ${task.video.videoName}');
        },
      );

      // **INSTANT CONTROLLER**: Initialize controller immediately for instant playback using VideoControllerFactory
      await _controllers.preloadController(task.index, task.video);

      print(
          '✅ VideoLoadingManager: Progressive streaming ready for ${task.video.videoName}');
    } catch (e) {
      print('❌ VideoLoadingManager: Progressive streaming failed: $e');
      // **FALLBACK**: Use direct network URL if streaming fails
      await _controllers.preloadController(task.index, task.video);
    }
  }

  bool _inRange(int i) => _initialized && i >= 0 && i < _itemCount;

  VideoModel? _safeVideo(int i) {
    // **FIXED: Check if manager is initialized before accessing _itemCount**
    if (!_initialized || !_inRange(i)) return null;
    return _videoAt!(i);
  }

  // **COMPATIBILITY METHODS** - For existing code
  Future<void> initializeVideoAtIndex(int index, VideoModel video) async {
    // **FIXED: Always use controller index 0 for single controller approach**
    const controllerIndex = 0;

    if (video.videoUrl.isEmpty) {
      print(
          '❌ VideoLoadingManager: Invalid video URL for index $index: ${video.videoUrl}');
      return;
    }

    try {
      // **PROGRESSIVE**: Use progressive streaming for instant playback
      await _cache.preloadFile(video.videoUrl);

      // **PROPER: Initialize controller with VideoModel using VideoControllerFactory**
      await _controllers.preloadController(controllerIndex, video);
      print(
          '✅ VideoLoadingManager: Controller $controllerIndex initialized with ${video.videoName} using VideoControllerFactory');
    } catch (e) {
      print(
          '❌ VideoLoadingManager: Error initializing controller $controllerIndex: $e');

      // **FALLBACK**: Try direct controller creation if preload fails
      if (e.toString().contains('401') ||
          e.toString().contains('Authentication')) {
        print(
            '🔄 VideoLoadingManager: Trying direct controller creation for ${video.videoName}');
        try {
          await _controllers.getController(controllerIndex, video);
          print('✅ VideoLoadingManager: Direct controller creation successful');
        } catch (fallbackError) {
          print(
              '❌ VideoLoadingManager: Direct controller creation also failed: $fallbackError');
          rethrow;
        }
      } else {
        rethrow;
      }
    }
  }

  VideoPlayerController? getController(int index) {
    // **FIXED: Always return controller 0 for single controller approach**
    return _controllers.getControllerByIndex(0);
  }

  /// Get cached controller count
  int get cachedControllerCount => _controllers.cachedControllerCount;

  Future<void> disposeController(int index) async {
    // **FIXED: Always dispose controller 0 for single controller approach**
    await _controllers.disposeController(0);
  }

  /// **CLEANUP**: Dispose all controllers and clear caches
  void cleanup() {
    _controllers.cleanup();
    _cache.clear();
    // Note: ProgressiveVideoCacheManager doesn't have clear method
  }

  /// **PRELOAD**: Start preloading videos around current index
  void preloadAround(int currentIndex) {
    if (!_initialized) return;

    _epoch++; // New viewport
    final tasks = <_PreloadTask>[];

    // Add current video (highest priority)
    final currentVideo = _safeVideo(currentIndex);
    if (currentVideo != null) {
      tasks.add(_PreloadTask(
        index: currentIndex,
        video: currentVideo,
        priority: 0,
      ));
    }

    // Add videos ahead
    for (int i = 1; i <= _profile.ahead; i++) {
      final index = currentIndex + i;
      final video = _safeVideo(index);
      if (video != null) {
        tasks.add(_PreloadTask(
          index: index,
          video: video,
          priority: i,
        ));
      }
    }

    // Add videos behind
    for (int i = 1; i <= _profile.behind; i++) {
      final index = currentIndex - i;
      final video = _safeVideo(index);
      if (video != null) {
        tasks.add(_PreloadTask(
          index: index,
          video: video,
          priority: i + _profile.ahead,
        ));
      }
    }

    // Sort by priority and run tasks
    tasks.sort((a, b) => a.priority.compareTo(b.priority));

    for (final task in tasks.take(_profile.concurrency)) {
      if (!_inProgress.contains(task.index)) {
        _inProgress.add(task.index);
        _runTask(task, _epoch).then((_) {
          _inProgress.remove(task.index);
        });
      }
    }
  }

  /// **STOP PRELOADING**: Cancel all ongoing preload tasks
  void stopPreloading() {
    _epoch++; // Invalidate all tasks
    _inProgress.clear();
  }

  /// **GET STATS**: Get loading statistics
  Map<String, dynamic> getStats() {
    return {
      'initialized': _initialized,
      'itemCount': _itemCount,
      'profile':
          '${_profile.ahead}ahead_${_profile.behind}behind_${_profile.concurrency}concurrent',
      'inProgress': _inProgress.length,
      'cacheStats': _cache.getCacheStats(),
      'networkQuality': _networkMonitor.currentQuality.toString(),
      // Note: NetworkMonitor doesn't have currentSpeed getter
    };
  }

  /// **LEGACY COMPATIBILITY**: Initialize with URL-based approach (for backward compatibility)
  Future<void> initWithUrls({
    required PreloadProfile profile,
    required VideoUrlAt urlAt,
    required int itemCount,
  }) async {
    // Convert URL-based approach to VideoModel-based approach
    _profile = profile;
    _videoAt = (index) {
      final url = urlAt(index);
      return VideoModel(
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
    };
    _itemCount = itemCount;
    _initialized = true;

    // **PROGRESSIVE STREAMING**: Initialize cache with network monitoring
    await _cache.init();
    await _progressiveCache.initialize();
    await _networkMonitor.startMonitoring();

    print('✅ VideoLoadingManager: Initialized with URL-based legacy approach');
  }
}

/// Legacy typedef for backward compatibility
typedef VideoUrlAt = String Function(int index);
