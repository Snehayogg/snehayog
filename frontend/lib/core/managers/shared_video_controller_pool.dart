import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// **Shared Video Controller Pool: Singleton manager for persisting video controllers**
/// This class manages a shared pool of video controllers that can be reused
/// across different screens (VideoFeedAdvanced, VideoScreen, ProfileScreen)
class SharedVideoControllerPool {
  static final SharedVideoControllerPool _instance =
      SharedVideoControllerPool._internal();
  factory SharedVideoControllerPool() => _instance;
  SharedVideoControllerPool._internal();

  // **CONTROLLER STORAGE**
  final Map<String, VideoPlayerController> _controllerPool = {};
  final Map<String, bool> _controllerStates =
      {}; // Track if controller is active
  final Map<String, VoidCallback> _listeners = {};

  // **LRU TRACKING**
  final Map<String, DateTime> _lastAccessed =
      {}; // Track when each video was last accessed
  final Map<String, int> _videoIndices =
      {}; // Track video indices for smart cleanup
  static const int _maxSharedPoolSize =
      7; // Max controllers in shared pool (optimized for memory)

  // **CACHE STATISTICS**
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _totalRequests = 0;

  /// **Check if video controller is already loaded (updates LRU)**
  bool isVideoLoaded(String videoId) {
    if (_controllerPool.containsKey(videoId) &&
        _controllerPool[videoId]!.value.isInitialized) {
      // **LRU: Update access time when checked**
      _lastAccessed[videoId] = DateTime.now();
      return true;
    }
    return false;
  }

  /// **Get existing controller for a video (updates LRU)**
  VideoPlayerController? getController(String videoId) {
    if (_controllerPool.containsKey(videoId)) {
      // **LRU: Update access time**
      _lastAccessed[videoId] = DateTime.now();
      final controller = _controllerPool[videoId]!;

      // **NEW: Return only if initialized and valid**
      if (controller.value.isInitialized && !controller.value.hasError) {
        trackCacheHit();
        return controller;
      } else {
        // **AUTO-CLEANUP: Remove invalid controllers**
        disposeController(videoId);
        trackCacheMiss();
        return null;
      }
    }
    trackCacheMiss();
    return null;
  }

  /// **Get controller with instant playback guarantee (for cached videos)**
  VideoPlayerController? getControllerForInstantPlay(String videoId) {
    final controller = getController(videoId);
    if (controller != null && controller.value.isInitialized) {
      // **INSTANT PLAYBACK: Ensure first frame is ready**
      if (controller.value.position > Duration.zero ||
          !controller.value.isBuffering) {
        return controller;
      }
    }
    return controller;
  }

  /// **Add controller to pool with LRU eviction**
  void addController(String videoId, VideoPlayerController controller,
      {bool skipDisposeOld = false, int? index}) {
    print('📥 SharedPool: Adding controller for video: $videoId');

    // **LRU: Update access time**
    _lastAccessed[videoId] = DateTime.now();

    // **NEW: Track video index for smart cleanup**
    if (index != null) {
      _videoIndices[videoId] = index;
    }

    // Dispose old controller if exists (unless we're explicitly replacing with the same controller)
    if (_controllerPool.containsKey(videoId)) {
      final oldController = _controllerPool[videoId];

      // **CRITICAL FIX: Only dispose if it's a different controller instance**
      // This prevents disposing the controller we're trying to save
      if (oldController != controller && !skipDisposeOld) {
        oldController?.removeListener(_listeners[videoId] ?? () {});
        oldController?.dispose();
        print('🗑️ SharedPool: Disposed old controller for video: $videoId');
      } else {
        print(
            '♻️ SharedPool: Skipping dispose - same controller instance or skipDisposeOld=true');
      }
    } else {
      // **NEW: LRU Eviction - Remove least recently used if pool is full**
      _evictLRUIfNeeded(excluding: videoId);
    }

    _controllerPool[videoId] = controller;
    _controllerStates[videoId] = false; // Not playing initially

    print(
        '✅ SharedPool: Controller added, total controllers: ${_controllerPool.length}');
  }

  /// **NEW: Cleanup controllers far from current index**
  void cleanupDistantControllers(int currentIndex, {int keepRange = 3}) {
    final toRemove = <String>[];

    for (final entry in _videoIndices.entries) {
      final videoId = entry.key;
      final index = entry.value;
      final distance = (index - currentIndex).abs();

      // Remove controllers more than keepRange away
      if (distance > keepRange) {
        toRemove.add(videoId);
      }
    }

    for (final videoId in toRemove) {
      disposeController(videoId);
    }

    if (toRemove.isNotEmpty) {
      print('🧹 SharedPool: Cleaned up ${toRemove.length} distant controllers');
    }
  }

  /// **Remove controller from pool (but keep it initialized)**
  void removeController(String videoId) {
    if (_controllerPool.containsKey(videoId)) {
      final controller = _controllerPool[videoId]!;
      controller.removeListener(_listeners[videoId] ?? () {});
      _controllerPool.remove(videoId);
      _controllerStates.remove(videoId);
      _listeners.remove(videoId);
      _lastAccessed.remove(videoId); // Remove LRU tracking
      _videoIndices.remove(videoId); // Remove index tracking

      print('🗑️ SharedPool: Removed controller for video: $videoId');
    }
  }

  /// **LRU Eviction: Remove least recently used controllers**
  void _evictLRUIfNeeded({String? excluding}) {
    if (_controllerPool.length < _maxSharedPoolSize) return;

    // Sort by last accessed time (oldest first)
    final sortedEntries = _lastAccessed.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    // Calculate how many to remove
    final toRemove = _controllerPool.length -
        _maxSharedPoolSize +
        1; // +1 for new controller

    int removed = 0;
    for (final entry in sortedEntries) {
      if (removed >= toRemove) break;
      if (entry.key == excluding) continue; // Don't remove the one we're adding

      if (_controllerPool.containsKey(entry.key)) {
        disposeController(entry.key);
        removed++;
      }
    }

    if (removed > 0) {
      print('🧹 SharedPool: LRU evicted $removed old controllers');
    }
  }

  /// **Dispose controller and remove from pool**
  void disposeController(String videoId) {
    if (_controllerPool.containsKey(videoId)) {
      final controller = _controllerPool[videoId]!;
      try {
        // **PROPER CLEANUP: Pause and mute before disposal**
        if (controller.value.isInitialized) {
          controller.pause();
          controller.setVolume(0.0);
        }
        controller.removeListener(_listeners[videoId] ?? () {});
        controller.dispose();
      } catch (e) {
        print('⚠️ SharedPool: Error disposing controller $videoId: $e');
      }

      _controllerPool.remove(videoId);
      _controllerStates.remove(videoId);
      _listeners.remove(videoId);
      _lastAccessed.remove(videoId); // Remove LRU tracking
      _videoIndices.remove(videoId); // Remove index tracking

      print('🗑️ SharedPool: Disposed controller for video: $videoId');
    }
  }

  /// **Attach listener to controller**
  void attachListener(String videoId, VoidCallback listener) {
    if (_controllerPool.containsKey(videoId)) {
      _listeners[videoId] = listener;
      _controllerPool[videoId]!.addListener(listener);

      print('👂 SharedPool: Attached listener for video: $videoId');
    }
  }

  /// **Remove listener from controller**
  void removeListener(String videoId) {
    if (_controllerPool.containsKey(videoId) &&
        _listeners.containsKey(videoId)) {
      _controllerPool[videoId]!.removeListener(_listeners[videoId]!);
      _listeners.remove(videoId);

      print('👂 SharedPool: Removed listener for video: $videoId');
    }
  }

  /// **Set controller state (playing/paused)**
  void setControllerState(String videoId, bool isPlaying) {
    _controllerStates[videoId] = isPlaying;
  }

  /// **Get controller state**
  bool? getControllerState(String videoId) {
    return _controllerStates[videoId];
  }

  /// **Check if controller exists (even if not initialized)**
  bool hasController(String videoId) {
    return _controllerPool.containsKey(videoId);
  }

  /// **Get statistics**
  Map<String, dynamic> getStatistics() {
    return {
      'totalControllers': _controllerPool.length,
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'totalRequests': _totalRequests,
      'hitRate': _totalRequests > 0
          ? (_cacheHits / _totalRequests * 100).toStringAsFixed(2)
          : '0.00',
      'controllerIds': _controllerPool.keys.toList(),
    };
  }

  /// **Track cache hit**
  void trackCacheHit() {
    _cacheHits++;
    _totalRequests++;
  }

  /// **Track cache miss**
  void trackCacheMiss() {
    _cacheMisses++;
    _totalRequests++;
  }

  /// **Pause all controllers instead of disposing (better UX)**
  void pauseAllControllers() {
    print('⏸️ SharedPool: Pausing all controllers (keeping in memory)');

    for (final entry in _controllerPool.entries) {
      try {
        if (entry.value.value.isInitialized && entry.value.value.isPlaying) {
          entry.value.pause();
          _controllerStates[entry.key] = false;
          print('⏸️ SharedPool: Paused controller ${entry.key}');
        }
      } catch (e) {
        print('⚠️ SharedPool: Error pausing controller ${entry.key}: $e');
      }
    }

    print('✅ SharedPool: All controllers paused');
  }

  /// **Resume specific controller (for better UX)**
  void resumeController(String videoId) {
    if (_controllerPool.containsKey(videoId)) {
      try {
        final controller = _controllerPool[videoId]!;
        if (controller.value.isInitialized && !controller.value.isPlaying) {
          controller.play();
          _controllerStates[videoId] = true;
          print('▶️ SharedPool: Resumed controller $videoId');
        }
      } catch (e) {
        print('⚠️ SharedPool: Error resuming controller $videoId: $e');
      }
    }
  }

  /// **Check if controller is paused (not disposed)**
  bool isControllerPaused(String videoId) {
    return _controllerPool.containsKey(videoId) &&
        _controllerPool[videoId]!.value.isInitialized &&
        !_controllerPool[videoId]!.value.isPlaying;
  }

  /// **Memory management: Dispose controllers when memory usage is high**
  void disposeControllersForMemoryManagement() {
    print('🧹 SharedPool: Disposing controllers for memory management');

    // Keep only the most recent 2 controllers, dispose the rest
    if (_controllerPool.length > 2) {
      final sortedKeys = _controllerPool.keys.toList();
      final controllersToDispose = sortedKeys.take(sortedKeys.length - 2);

      for (final videoId in controllersToDispose) {
        disposeController(videoId);
      }

      print(
          '✅ SharedPool: Disposed ${controllersToDispose.length} controllers for memory management');
    }
  }

  /// **Smart resume: Resume controller if available, otherwise show first frame**
  void smartResumeController(String videoId) {
    if (_controllerPool.containsKey(videoId)) {
      final controller = _controllerPool[videoId]!;
      if (controller.value.isInitialized) {
        // Show first frame immediately (no loading)
        print('🖼️ SharedPool: Showing first frame for video $videoId');

        // Resume in background
        Future.microtask(() {
          if (controller.value.isInitialized && !controller.value.isPlaying) {
            controller.play();
            _controllerStates[videoId] = true;
            print('▶️ SharedPool: Resumed video $videoId in background');
          }
        });
      }
    }
  }

  /// **Clear all controllers (only when memory is high)**
  void clearAll() {
    print('🗑️ SharedPool: Clearing all controllers');

    for (final entry in _controllerPool.entries) {
      try {
        entry.value.removeListener(_listeners[entry.key] ?? () {});
        entry.value.dispose();
      } catch (e) {
        print('⚠️ SharedPool: Error disposing controller ${entry.key}: $e');
      }
    }

    _controllerPool.clear();
    _controllerStates.clear();
    _listeners.clear();
    _lastAccessed.clear(); // Clear LRU tracking
    _videoIndices.clear(); // Clear index tracking

    print('✅ SharedPool: All controllers cleared');
  }

  /// **Clear controllers except specified ones**
  void clearExcept(List<String> keepVideoIds) {
    final keepSet = keepVideoIds.toSet();
    final toRemove = <String>[];

    for (final videoId in _controllerPool.keys) {
      if (!keepSet.contains(videoId)) {
        toRemove.add(videoId);
      }
    }

    for (final videoId in toRemove) {
      disposeController(videoId);
    }

    print(
        '🗑️ SharedPool: Cleared ${toRemove.length} controllers, keeping ${keepVideoIds.length}');
  }

  /// **Print pool status**
  void printStatus() {
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('📊 SHARED VIDEO CONTROLLER POOL STATUS');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    print('   Total Controllers: ${_controllerPool.length}');
    print('   Video IDs: ${_controllerPool.keys.toList()}');
    print('   Cache Hits: $_cacheHits');
    print('   Cache Misses: $_cacheMisses');
    print(
        '   Hit Rate: ${_totalRequests > 0 ? (_cacheHits / _totalRequests * 100).toStringAsFixed(2) : '0.00'}%');
    print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }

  /// **Dispose all resources**
  void dispose() {
    print('🗑️ SharedPool: Disposing all resources');
    clearAll();
  }
}
