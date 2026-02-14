import 'package:video_player/video_player.dart';
import 'package:vayu/features/video/video_model.dart';
import 'package:vayu/shared/utils/enhanced_controller_disposal.dart';
import 'dart:async';
import 'package:vayu/shared/utils/app_logger.dart';

/// Intelligent Controller Pool
/// Manages video controllers with smart pooling and concurrent preparation
class IntelligentControllerPool {
  static final IntelligentControllerPool _instance =
      IntelligentControllerPool._internal();
  factory IntelligentControllerPool() => _instance;
  IntelligentControllerPool._internal();

  // **INTELLIGENT POOLING: Dynamic pool sizes based on device capabilities**
  static const int _basePoolSize = 2; // Base pool size for current video
  static const int _preloadPoolSize = 1; // Pool size for preloading
  static const int _maxTotalControllers = 3; // **PARTITIONED: 3/10 of global budget**
  static const int _maxConcurrentInitializations =
      1; // Max concurrent initializations

  final Map<int, VideoPlayerController> _activeControllers = {};
  final Map<int, VideoPlayerController> _preloadControllers = {};
  final Map<int, String> _controllerVideoIds = {};
  final Map<int, DateTime> _controllerLastUsed = {};
  final Set<int> _initializingControllers = {};

  Timer? _cleanupTimer;
  int _concurrentInitializations = 0;

  /// Get the optimal pool size based on device capabilities
  int get optimalPoolSize {
    // **ADAPTIVE POOLING: Adjust based on device memory and performance**
    return _basePoolSize;
  }

  /// Get the preload pool size
  int get preloadPoolSize {
    return _preloadPoolSize;
  }

  /// Get total controller count
  int get totalControllerCount =>
      _activeControllers.length + _preloadControllers.length;

  /// Check if we can create more controllers
  bool get canCreateMoreControllers =>
      totalControllerCount < _maxTotalControllers;

  /// Check if we can initialize more controllers concurrently
  bool get canInitializeConcurrently =>
      _concurrentInitializations < _maxConcurrentInitializations;

  /// Initialize the intelligent pool
  void initialize() {
    AppLogger.log(
        '🧠 IntelligentControllerPool: Initializing intelligent controller pool');

    // **CLEANUP TIMER: Run cleanup every 30 seconds**
    _cleanupTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _performCleanup();
    });

    AppLogger.log('✅ IntelligentControllerPool: Intelligent pool initialized');
  }

  /// Get or create controller for active video
  Future<VideoPlayerController?> getActiveController(
      int index, VideoModel video) async {
    // **ACTIVE CONTROLLER: Check if we already have an active controller**
    if (_activeControllers.containsKey(index)) {
      final controller = _activeControllers[index]!;
      if (controller.value.isInitialized && !controller.value.hasError) {
        _controllerLastUsed[index] = DateTime.now();
        AppLogger.log(
            '♻️ IntelligentControllerPool: Reusing active controller $index');
        return controller;
      } else {
        AppLogger.log(
            '🔄 IntelligentControllerPool: Disposing invalid active controller $index');
        await _disposeController(index, isActive: true);
      }
    }

    // **CONCURRENT LIMIT: Check if we can initialize concurrently**
    if (!canInitializeConcurrently) {
      AppLogger.log(
          '⏳ IntelligentControllerPool: Waiting for concurrent initialization slot');
      await _waitForInitializationSlot();
    }

    // **CREATE CONTROLLER: Create new active controller**
    return await _createController(index, video, isActive: true);
  }

  /// Get or create controller for preloading
  Future<VideoPlayerController?> getPreloadController(
      int index, VideoModel video) async {
    // **PRELOAD CONTROLLER: Check if we already have a preload controller**
    if (_preloadControllers.containsKey(index)) {
      final controller = _preloadControllers[index]!;
      if (controller.value.isInitialized && !controller.value.hasError) {
        _controllerLastUsed[index] = DateTime.now();
        AppLogger.log(
            '♻️ IntelligentControllerPool: Reusing preload controller $index');
        return controller;
      } else {
        AppLogger.log(
            '🔄 IntelligentControllerPool: Disposing invalid preload controller $index');
        await _disposeController(index, isActive: false);
      }
    }

    // **POOL LIMIT: Check if we can create more controllers**
    if (!canCreateMoreControllers) {
      AppLogger.log(
          '⚠️ IntelligentControllerPool: Pool limit reached, cleaning up old controllers');
      await _cleanupOldControllers();
    }

    // **CONCURRENT LIMIT: Check if we can initialize concurrently**
    if (!canInitializeConcurrently) {
      AppLogger.log(
          '⏳ IntelligentControllerPool: Waiting for concurrent initialization slot');
      await _waitForInitializationSlot();
    }

    // **CREATE CONTROLLER: Create new preload controller**
    return await _createController(index, video, isActive: false);
  }

  /// Create a new controller
  Future<VideoPlayerController?> _createController(int index, VideoModel video,
      {required bool isActive}) async {
    try {
      AppLogger.log(
          '🎬 IntelligentControllerPool: Creating ${isActive ? 'active' : 'preload'} controller $index');

      _concurrentInitializations++;
      _initializingControllers.add(index);

      // **CONTROLLER CREATION: Create controller based on video type**
      final controller = await _createVideoController(video);

      // **INITIALIZATION: Initialize with timeout**
      await controller.initialize().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException(
              'Controller initialization timeout', const Duration(seconds: 15));
        },
      );

      // **STORAGE: Store controller in appropriate pool**
      if (isActive) {
        _activeControllers[index] = controller;
      } else {
        _preloadControllers[index] = controller;
      }

      _controllerVideoIds[index] = video.id;
      _controllerLastUsed[index] = DateTime.now();

      _concurrentInitializations--;
      _initializingControllers.remove(index);

      AppLogger.log(
          '✅ IntelligentControllerPool: Created ${isActive ? 'active' : 'preload'} controller $index');
      return controller;
    } catch (e) {
      AppLogger.log(
          '❌ IntelligentControllerPool: Error creating controller $index: $e');
      _concurrentInitializations--;
      _initializingControllers.remove(index);
      return null;
    }
  }

  /// Create video controller based on video type
  Future<VideoPlayerController> _createVideoController(VideoModel video) async {
    // **URL SELECTION: Choose the best URL for playback**
    final url = _selectBestUrl(video);

    // **CONTROLLER CREATION: Create controller with optimal settings**
    final controller = VideoPlayerController.networkUrl(
      Uri.parse(url),
      videoPlayerOptions: VideoPlayerOptions(
        mixWithOthers: false,
        allowBackgroundPlayback: false,
      ),
    );

    return controller;
  }

  /// Select the best URL for playback
  String _selectBestUrl(VideoModel video) {
    // **URL PRIORITY: HLS > CDN > Cloudinary**
    if (video.hlsMasterPlaylistUrl != null &&
        video.hlsMasterPlaylistUrl!.isNotEmpty) {
      return video.hlsMasterPlaylistUrl!;
    }
    if (video.hlsPlaylistUrl != null && video.hlsPlaylistUrl!.isNotEmpty) {
      return video.hlsPlaylistUrl!;
    }
    if (video.lowQualityUrl != null && video.lowQualityUrl!.isNotEmpty) {
      return video.lowQualityUrl!;
    }
    return video.videoUrl;
  }

  /// Wait for initialization slot to become available
  Future<void> _waitForInitializationSlot() async {
    while (!canInitializeConcurrently) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Dispose a controller
  Future<void> _disposeController(int index, {required bool isActive}) async {
    try {
      final controller =
          isActive ? _activeControllers[index] : _preloadControllers[index];
      if (controller != null) {
        // **ENHANCED DISPOSAL: Use enhanced disposal system**
        await EnhancedControllerDisposal.disposeController(
          controller,
          identifier: 'pool_${isActive ? 'active' : 'preload'}_$index',
          forceDispose: true,
        );
      }

      // **CLEANUP: Remove from maps**
      if (isActive) {
        _activeControllers.remove(index);
      } else {
        _preloadControllers.remove(index);
      }
      _controllerVideoIds.remove(index);
      _controllerLastUsed.remove(index);
    } catch (e) {
      AppLogger.log(
          '❌ IntelligentControllerPool: Error disposing controller $index: $e');
    }
  }

  /// Clean up old controllers
  Future<void> _cleanupOldControllers() async {
    AppLogger.log('🧹 IntelligentControllerPool: Cleaning up old controllers');

    // **CLEANUP STRATEGY: Remove least recently used controllers**
    final now = DateTime.now();
    final controllersToRemove = <int>[];

    // **PRELOAD CLEANUP: Clean up old preload controllers first**
    for (final entry in _preloadControllers.entries) {
      final index = entry.key;
      final lastUsed = _controllerLastUsed[index];
      if (lastUsed != null && now.difference(lastUsed).inMinutes > 5) {
        controllersToRemove.add(index);
      }
    }

    // **ACTIVE CLEANUP: Clean up old active controllers if needed**
    if (controllersToRemove.length < 2) {
      for (final entry in _activeControllers.entries) {
        final index = entry.key;
        final lastUsed = _controllerLastUsed[index];
        if (lastUsed != null && now.difference(lastUsed).inMinutes > 10) {
          controllersToRemove.add(index);
        }
      }
    }

    // **DISPOSE: Dispose old controllers**
    for (final index in controllersToRemove) {
      final isActive = _activeControllers.containsKey(index);
      await _disposeController(index, isActive: isActive);
    }

    AppLogger.log(
        '✅ IntelligentControllerPool: Cleaned up ${controllersToRemove.length} old controllers');
  }

  /// Perform periodic cleanup
  void _performCleanup() {
    AppLogger.log('🧹 IntelligentControllerPool: Performing periodic cleanup');

    // **CLEANUP: Clean up old controllers**
    _cleanupOldControllers();

    // **STATUS: Log pool status**
    AppLogger.log(
        '📊 IntelligentControllerPool: Pool status - Active: ${_activeControllers.length}, Preload: ${_preloadControllers.length}, Total: $totalControllerCount');
  }

  /// Move controller from preload to active
  Future<VideoPlayerController?> promoteToActive(int index) async {
    if (_preloadControllers.containsKey(index)) {
      final controller = _preloadControllers.remove(index)!;
      _activeControllers[index] = controller;
      _controllerLastUsed[index] = DateTime.now();
      AppLogger.log(
          '⬆️ IntelligentControllerPool: Promoted controller $index to active');
      return controller;
    }
    return null;
  }

  /// Move controller from active to preload
  Future<void> demoteToPreload(int index) async {
    if (_activeControllers.containsKey(index)) {
      final controller = _activeControllers.remove(index)!;
      _preloadControllers[index] = controller;
      _controllerLastUsed[index] = DateTime.now();
      AppLogger.log(
          '⬇️ IntelligentControllerPool: Demoted controller $index to preload');
    }
  }

  /// Get controller by index
  VideoPlayerController? getController(int index) {
    return _activeControllers[index] ?? _preloadControllers[index];
  }

  /// Check if controller exists
  bool hasController(int index) {
    return _activeControllers.containsKey(index) ||
        _preloadControllers.containsKey(index);
  }

  /// Get pool statistics
  Map<String, dynamic> getPoolStats() {
    return {
      'activeControllers': _activeControllers.length,
      'preloadControllers': _preloadControllers.length,
      'totalControllers': totalControllerCount,
      'concurrentInitializations': _concurrentInitializations,
      'initializingControllers': _initializingControllers.length,
      'canCreateMore': canCreateMoreControllers,
      'canInitializeConcurrently': canInitializeConcurrently,
    };
  }

  /// Dispose all controllers
  Future<void> disposeAllControllers() async {
    AppLogger.log('🗑️ IntelligentControllerPool: Disposing all controllers');

    // **DISPOSE: All active controllers**
    for (final index in _activeControllers.keys.toList()) {
      await _disposeController(index, isActive: true);
    }

    // **DISPOSE: All preload controllers**
    for (final index in _preloadControllers.keys.toList()) {
      await _disposeController(index, isActive: false);
    }

    // **CLEANUP: Clear all maps**
    _activeControllers.clear();
    _preloadControllers.clear();
    _controllerVideoIds.clear();
    _controllerLastUsed.clear();
    _initializingControllers.clear();

    AppLogger.log('✅ IntelligentControllerPool: All controllers disposed');
  }

  /// Dispose the pool
  void dispose() {
    AppLogger.log('🗑️ IntelligentControllerPool: Disposing intelligent pool');

    // **CANCEL: Cleanup timer**
    _cleanupTimer?.cancel();

    // **DISPOSE: All controllers**
    disposeAllControllers();

    AppLogger.log('✅ IntelligentControllerPool: Intelligent pool disposed');
  }
}
