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

  // **CACHE STATISTICS**
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _totalRequests = 0;

  /// **Check if video controller is already loaded**
  bool isVideoLoaded(String videoId) {
    return _controllerPool.containsKey(videoId) &&
        _controllerPool[videoId]!.value.isInitialized;
  }

  /// **Get existing controller for a video**
  VideoPlayerController? getController(String videoId) {
    return _controllerPool[videoId];
  }

  /// **Add controller to pool**
  void addController(String videoId, VideoPlayerController controller,
      {bool skipDisposeOld = false}) {
    print('📥 SharedPool: Adding controller for video: $videoId');

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
    }

    _controllerPool[videoId] = controller;
    _controllerStates[videoId] = false; // Not playing initially

    print(
        '✅ SharedPool: Controller added, total controllers: ${_controllerPool.length}');
  }

  /// **Remove controller from pool (but keep it initialized)**
  void removeController(String videoId) {
    if (_controllerPool.containsKey(videoId)) {
      final controller = _controllerPool[videoId]!;
      controller.removeListener(_listeners[videoId] ?? () {});
      _controllerPool.remove(videoId);
      _controllerStates.remove(videoId);
      _listeners.remove(videoId);

      print('🗑️ SharedPool: Removed controller for video: $videoId');
    }
  }

  /// **Dispose controller and remove from pool**
  void disposeController(String videoId) {
    if (_controllerPool.containsKey(videoId)) {
      final controller = _controllerPool[videoId]!;
      controller.removeListener(_listeners[videoId] ?? () {});
      controller.dispose();
      _controllerPool.remove(videoId);
      _controllerStates.remove(videoId);
      _listeners.remove(videoId);

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
