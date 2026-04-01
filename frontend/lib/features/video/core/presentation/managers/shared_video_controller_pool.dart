import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:vayug/shared/utils/app_logger.dart';

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
  final Map<String, bool> _controllerStates = {}; // Track if controller is active
  final Map<String, VoidCallback> _listeners = {};

  // **DISPOSAL STREAM: Notify listeners when a controller is evicted**
  final StreamController<String> _disposalStreamController =
      StreamController<String>.broadcast();
  Stream<String> get disposalStream => _disposalStreamController.stream;

  // **LRU TRACKING**
  final Map<String, DateTime> _lastAccessed =
      {}; // Track when each video was last accessed
  final Map<String, int> _videoIndices =
      {}; // Track video indices for smart cleanup
  
  // **DYNAMIC CONFIG: Hard limit to prevent NO_MEMORY**
  // Android usually supports ~16 hardware decoders, but other apps/services might use them.
  // We stay well below this limit.
  int _maxPoolSize = 6; // **Increased from 4 to 6 for better multi-screen stability**

  /// **Configure pool based on device capabilities**
  void configurePool({required bool isLowEndDevice}) {
    // High-end: 6 controllers
    // Low-end: 2 controllers (ExoPlayer decoders are heavy on old phones)
    _maxPoolSize = isLowEndDevice ? 2 : 6;
    
    AppLogger.log(
      '📱 SharedPool Configured: Max $_maxPoolSize active controllers '
      '(${isLowEndDevice ? "Low End Mode" : "High End Mode"})'
    );
    
    // If shrinking, trigger immediate eviction
    if (_controllerPool.length > _maxPoolSize) {
       _evictLRUIfNeeded();
    }
  }

  /// **PROACTIVE CLEANUP: Ensure space exits BEFORE creating a new controller**
  /// Call this before `VideoPlayerController.networkUrl()` to prevent OOM.
  Future<void> makeRoomForNewController() async {
    if (_controllerPool.length >= _maxPoolSize) {
      // **PREEMPTIVE DISPOSAL: Be ruthless during fast scroll**
      // Don't just evict one, evict until we are at least 1 below the limit
      // to avoid fighting for decoders on every single swipe.
      _evictLRUIfNeeded(forceRelease: true);
    }
  }

  // **CACHE STATISTICS**
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _totalRequests = 0;

  /// **Check if video controller is already loaded (updates LRU)**
  bool isVideoLoaded(String videoId) {
    return _validatedController(videoId) != null;
  }

  /// **Check if a controller is effectively disposed**
  bool isControllerDisposed(VideoPlayerController? controller) {
    if (controller == null) return true;
    try {
      // Accessing value throws if disposed
      final _ = controller.value;
      return false;
    } catch (_) {
      return true;
    }
  }

  /// Safely read controller value. Returns null if controller is disposed.
  VideoPlayerValue? _safeControllerValue(
    String videoId,
    VideoPlayerController controller,
  ) {
    try {
      return controller.value;
    } catch (e) {
      _evictController(videoId, controller, reason: 'stale/disposed: $e');
      return null;
    }
  }

  /// Remove invalid controller references so caller can recreate a fresh one.
  void _evictController(
    String videoId,
    VideoPlayerController controller, {
    String? reason,
    bool disposeInstance = false,
  }) {
    final listener = _listeners[videoId];
    if (listener != null) {
      try {
        controller.removeListener(listener);
      } catch (_) {}
    }

    _controllerPool.remove(videoId);
    _controllerStates.remove(videoId);
    _listeners.remove(videoId);
    _lastAccessed.remove(videoId);
    _videoIndices.remove(videoId);

    // Notify listeners that this controller is being evicted
    _disposalStreamController.add(videoId);

    if (disposeInstance) {
      try {
        controller.dispose();
      } catch (_) {}
    }

    AppLogger.log(
      'SharedPool: Evicted invalid controller for video: $videoId'
      '${reason != null ? ' ($reason)' : ''}',
    );
  }

  VideoPlayerController? _validatedController(
    String videoId, {
    bool requireInitialized = true,
  }) {
    final controller = _controllerPool[videoId];
    if (controller == null) return null;

    final value = _safeControllerValue(videoId, controller);
    if (value == null) return null;

    if (value.hasError) {
      _evictController(
        videoId,
        controller,
        reason: 'controller has error',
        disposeInstance: true,
      );
      return null;
    }

    if (requireInitialized && !value.isInitialized) {
      _evictController(
        videoId,
        controller,
        reason: 'not initialized',
        disposeInstance: true,
      );
      return null;
    }

    _lastAccessed[videoId] = DateTime.now();
    return controller;
  }

  /// **Get existing controller for a video (updates LRU)**
  VideoPlayerController? getController(String videoId) {
    final controller = _validatedController(videoId);
    if (controller != null) {
      trackCacheHit();
      return controller;
    }
    trackCacheMiss();
    return null;
  }

  /// **Get controller with instant playback guarantee (for cached videos)**
  VideoPlayerController? getControllerForInstantPlay(String videoId) {
    final controller = getController(videoId);
    if (controller != null) {
      final value = _safeControllerValue(videoId, controller);
      if (value == null || !value.isInitialized) {
        trackCacheMiss();
        return null;
      }

      // **INSTANT PLAYBACK: Ensure first frame is ready**
      if (value.position > Duration.zero || !value.isBuffering) {
        return controller;
      }
    }
    return controller;
  }

  /// **Add controller to pool with LRU eviction**
  void addController(String videoId, VideoPlayerController controller,
      {bool skipDisposeOld = false, int? index}) {
    AppLogger.log('📥 SharedPool: Adding controller for video: $videoId');

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
        
        // Notify listeners that this controller is being evicted
        _disposalStreamController.add(videoId);
        
        AppLogger.log(
            '🗑️ SharedPool: Disposed old controller for video: $videoId');
      } else {
        AppLogger.log(
            '♻️ SharedPool: Skipping dispose - same controller instance or skipDisposeOld=true');
      }
    } else {
      // **NEW: LRU Eviction - Remove least recently used if pool is full**
      _evictLRUIfNeeded(excluding: videoId);
    }

    _controllerPool[videoId] = controller;
    _controllerStates[videoId] = false; // Not playing initially

    AppLogger.log(
        '✅ SharedPool: Controller added, total controllers: ${_controllerPool.length}');
  }

  /// **NEW: Smart Cleanup within specific range (optimized for preloading)**
  void cleanupSmart(int currentIndex, int startRange, int endRange) {
    final toRemove = <String>[];

    for (final entry in _videoIndices.entries) {
      final videoId = entry.key;
      final index = entry.value;

      // Keep only videos within the safe range [startRange, endRange]
      // Also keep the current video explicitly
      if (index != currentIndex && (index < startRange || index > endRange)) {
        toRemove.add(videoId);
      }
    }

    for (final videoId in toRemove) {
      disposeController(videoId);
    }

    if (toRemove.isNotEmpty) {
      AppLogger.log(
          '🧹 SharedPool: Smart cleaned up ${toRemove.length} controllers outside range [$startRange, $endRange]');
    }
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
      AppLogger.log(
          '🧹 SharedPool: Cleaned up ${toRemove.length} distant controllers');
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

      AppLogger.log('🗑️ SharedPool: Removed controller for video: $videoId');
    }
  }

  /// **LRU Eviction: Remove least recently used controllers**
  void _evictLRUIfNeeded({String? excluding, bool forceRelease = false}) {
    if (_controllerPool.length < _maxPoolSize) return;

    // Sort by last accessed time (oldest first)
    final sortedEntries = _lastAccessed.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    // Calculate how many to remove
    // If forceRelease is true, we remove 2 to create a healthy "buffer"
    final int targetCapacity = forceRelease ? _maxPoolSize - 2 : _maxPoolSize - 1;
    final toRemove = (_controllerPool.length - targetCapacity).clamp(1, _controllerPool.length);

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
      AppLogger.log('🧹 SharedPool: LRU evicted $removed old controllers (Reason: ${forceRelease ? "Ruthless/FastScroll" : "Pool Full"})');
    }
  }

  /// **Dispose controller and remove from pool**
  Future<void> disposeController(String videoId) async {
    if (_controllerPool.containsKey(videoId)) {
      final controller = _controllerPool[videoId]!;
      final listener = _listeners[videoId];
      
      // **CRITICAL: Remove from pool IMMEDIATELY to prevent reuse while disposing**
      _controllerPool.remove(videoId);
      _controllerStates.remove(videoId);
      _listeners.remove(videoId);
      _lastAccessed.remove(videoId); // Remove LRU tracking
      _videoIndices.remove(videoId); // Remove index tracking

      try {
        // **PROPER CLEANUP: Pause and mute before disposal**
        // This ensures audio actually stops before the object is killed
        if (controller.value.isInitialized) {
          // Fire and forget pause to avoid blocking UI, but ensure it runs
          controller.pause(); 
          controller.setVolume(0.0);
        }
        if (listener != null) {
          controller.removeListener(listener);
        }
        
        // **FIX: Instant disposal to prevent OOM**
        // Removed delay which caused decoder pile-up during fast scroll
        controller.dispose();
      } catch (e) {
        AppLogger.log('⚠️ SharedPool: Error disposing controller $videoId: $e');
      }

      AppLogger.log('🗑️ SharedPool: Disposed controller for video: $videoId');
    }
  }

  /// **Attach listener to controller**
  void attachListener(String videoId, VoidCallback listener) {
    if (_controllerPool.containsKey(videoId)) {
      _listeners[videoId] = listener;
      _controllerPool[videoId]!.addListener(listener);

      AppLogger.log('👂 SharedPool: Attached listener for video: $videoId');
    }
  }

  /// **Remove listener from controller**
  void removeListener(String videoId) {
    if (_controllerPool.containsKey(videoId) &&
        _listeners.containsKey(videoId)) {
      _controllerPool[videoId]!.removeListener(_listeners[videoId]!);
      _listeners.remove(videoId);

      AppLogger.log('👂 SharedPool: Removed listener for video: $videoId');
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
    return _validatedController(videoId, requireInitialized: false) != null;
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
  void pauseAllControllers({String? exceptVideoId}) {
    AppLogger.log(
        '⏸️ SharedPool: Pausing all controllers (except $exceptVideoId)');

    for (final entry in _controllerPool.entries) {
      if (exceptVideoId != null && entry.key == exceptVideoId) continue;

      try {
        if (entry.value.value.isInitialized && entry.value.value.isPlaying) {
          entry.value.pause();
          _controllerStates[entry.key] = false;
          AppLogger.log('⏸️ SharedPool: Paused controller ${entry.key}');
        }
      } catch (e) {
        AppLogger.log(
            '⚠️ SharedPool: Error pausing controller ${entry.key}: $e');
      }
    }

    AppLogger.log(
        '✅ SharedPool: Paused controllers${exceptVideoId != null ? ' (except current)' : ''}');
  }

  /// **Resume specific controller (for better UX)**
  void resumeController(String videoId) {
    if (_controllerPool.containsKey(videoId)) {
      try {
        final controller = _controllerPool[videoId]!;
        if (controller.value.isInitialized && !controller.value.isPlaying) {
          controller.play();
          _controllerStates[videoId] = true;
          AppLogger.log('▶️ SharedPool: Resumed controller $videoId');
        }
      } catch (e) {
        AppLogger.log('⚠️ SharedPool: Error resuming controller $videoId: $e');
      }
    }
  }

  /// **Check if any controller is currently playing**
  bool hasActivePlayback() {
    for (final controller in _controllerPool.values) {
      try {
        if (controller.value.isInitialized && controller.value.isPlaying) {
          return true;
        }
      } catch (_) {
        // Ignore controllers that may have been disposed mid-iteration
      }
    }
    return false;
  }

  /// **Check if controller is paused (not disposed)**
  bool isControllerPaused(String videoId) {
    final controller = _validatedController(videoId);
    if (controller == null) return false;

    final value = _safeControllerValue(videoId, controller);
    return value != null && !value.isPlaying;
  }

  /// **Memory management: Dispose controllers when memory usage is high**
  void disposeControllersForMemoryManagement() {
    AppLogger.log('🧹 SharedPool: Disposing controllers for memory management');

    // Keep only the most recent 2 controllers, dispose the rest
    if (_controllerPool.length > 2) {
      final sortedKeys = _controllerPool.keys.toList();
      final controllersToDispose = sortedKeys.take(sortedKeys.length - 2);

      for (final videoId in controllersToDispose) {
        disposeController(videoId);
      }

      AppLogger.log(
          '✅ SharedPool: Disposed ${controllersToDispose.length} controllers for memory management');
    }
  }

  /// **Smart resume: Resume controller if available, otherwise show first frame**
  void smartResumeController(String videoId) {
    if (_controllerPool.containsKey(videoId)) {
      final controller = _controllerPool[videoId]!;
      if (controller.value.isInitialized) {
        // Show first frame immediately (no loading)
        AppLogger.log('🖼️ SharedPool: Showing first frame for video $videoId');

        // Resume in background
        Future.microtask(() {
          if (controller.value.isInitialized && !controller.value.isPlaying) {
            controller.play();
            _controllerStates[videoId] = true;
            AppLogger.log(
                '▶️ SharedPool: Resumed video $videoId in background');
          }
        });
      }
    }
  }

  /// **Clear all controllers (only when memory is high)**
  void clearAll() {
    AppLogger.log('🗑️ SharedPool: Clearing all controllers');

    for (final entry in _controllerPool.entries) {
      try {
        entry.value.removeListener(_listeners[entry.key] ?? () {});
        entry.value.dispose();
      } catch (e) {
        AppLogger.log(
            '⚠️ SharedPool: Error disposing controller ${entry.key}: $e');
      }
    }

    _controllerPool.clear();
    _controllerStates.clear();
    _listeners.clear();
    _lastAccessed.clear(); // Clear LRU tracking
    _videoIndices.clear(); // Clear index tracking

    AppLogger.log('✅ SharedPool: All controllers cleared');
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

    AppLogger.log(
        '🗑️ SharedPool: Cleared ${toRemove.length} controllers, keeping ${keepVideoIds.length}');
  }

  /// **Print pool status**
  void printStatus() {
    AppLogger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    AppLogger.log('📊 SHARED VIDEO CONTROLLER POOL STATUS');
    AppLogger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    AppLogger.log('   Total Controllers: ${_controllerPool.length}');
    AppLogger.log('   Video IDs: ${_controllerPool.keys.toList()}');
    AppLogger.log('   Cache Hits: $_cacheHits');
    AppLogger.log('   Cache Misses: $_cacheMisses');
    AppLogger.log(
        '   Hit Rate: ${_totalRequests > 0 ? (_cacheHits / _totalRequests * 100).toStringAsFixed(2) : '0.00'}%');
    AppLogger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }

  /// **Dispose all resources**
  void dispose() {
    AppLogger.log('🗑️ SharedPool: Disposing all resources');
    clearAll();
    _disposalStreamController.close();
  }
}
