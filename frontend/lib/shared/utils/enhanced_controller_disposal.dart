import 'package:video_player/video_player.dart';
import 'dart:async';
import 'dart:io';

/// Enhanced controller disposal utility to prevent memory leaks
/// This utility ensures proper cleanup of video controllers and associated resources
class EnhancedControllerDisposal {
  static final Map<String, VideoPlayerController> _disposalQueue = {};
  static final Map<String, Timer> _disposalTimers = {};
  static bool _isDisposing = false;

  /// Dispose a controller with comprehensive cleanup
  static Future<void> disposeController(
    VideoPlayerController controller, {
    String? identifier,
    bool forceDispose = false,
  }) async {
    // Controller is already checked to be non-null by the caller

    final id =
        identifier ?? 'controller_${DateTime.now().millisecondsSinceEpoch}';

    try {
      print('🗑️ EnhancedControllerDisposal: Starting disposal for $id');

      // **STEP 1: Pause and stop the controller**
      if (controller.value.isInitialized) {
        try {
          await controller.pause();
          controller.setVolume(0.0);
          print('⏸️ EnhancedControllerDisposal: Paused controller $id');
        } catch (e) {
          print(
              '⚠️ EnhancedControllerDisposal: Error pausing controller $id: $e');
        }
      }

      // **STEP 2: Remove from disposal queue if exists**
      _disposalQueue.remove(id);

      // **STEP 3: Cancel any existing disposal timer**
      _disposalTimers[id]?.cancel();
      _disposalTimers.remove(id);

      // **STEP 4: Force dispose if requested or if controller is invalid**
      if (forceDispose ||
          controller.value.hasError ||
          !controller.value.isInitialized) {
        await _forceDisposeController(controller, id);
        return;
      }

      // **STEP 5: Add to disposal queue for delayed cleanup**
      _disposalQueue[id] = controller;

      // **STEP 6: Set up delayed disposal timer**
      _disposalTimers[id] = Timer(const Duration(seconds: 2), () async {
        await _processDisposalQueue();
      });

      print('✅ EnhancedControllerDisposal: Controller $id queued for disposal');
    } catch (e) {
      print('❌ EnhancedControllerDisposal: Error disposing controller $id: $e');
      // Force dispose on error
      await _forceDisposeController(controller, id);
    }
  }

  /// Force dispose a controller immediately
  static Future<void> _forceDisposeController(
    VideoPlayerController controller,
    String id,
  ) async {
    try {
      print('🔨 EnhancedControllerDisposal: Force disposing controller $id');

      // **CRITICAL: Pause and mute before disposal**
      if (controller.value.isInitialized) {
        try {
          await controller.pause();
          controller.setVolume(0.0);
        } catch (e) {
          print(
              '⚠️ EnhancedControllerDisposal: Error pausing before force dispose: $e');
        }
      }

      // **DISPOSE: Call the actual dispose method**
      await controller.dispose();

      // **CLEANUP: Remove from queue and timers**
      _disposalQueue.remove(id);
      _disposalTimers[id]?.cancel();
      _disposalTimers.remove(id);

      print('✅ EnhancedControllerDisposal: Controller $id force disposed');

      // **MEMORY: Small delay to ensure MediaCodec cleanup**
      await Future.delayed(const Duration(milliseconds: 100));
    } catch (e) {
      print(
          '❌ EnhancedControllerDisposal: Error force disposing controller $id: $e');
    }
  }

  /// Process the disposal queue
  static Future<void> _processDisposalQueue() async {
    if (_isDisposing || _disposalQueue.isEmpty) return;

    _isDisposing = true;
    print(
        '🔄 EnhancedControllerDisposal: Processing disposal queue (${_disposalQueue.length} controllers)');

    final controllersToDispose =
        Map<String, VideoPlayerController>.from(_disposalQueue);
    _disposalQueue.clear();

    for (final entry in controllersToDispose.entries) {
      try {
        final controller = entry.value;
        final id = entry.key;

        // **FINAL CHECK: Only dispose if still valid**
        if (controller.value.isInitialized && !controller.value.hasError) {
          await controller.dispose();
          print('✅ EnhancedControllerDisposal: Disposed controller $id');
        } else {
          print(
              '⚠️ EnhancedControllerDisposal: Skipping invalid controller $id');
        }

        // **CLEANUP: Remove timer**
        _disposalTimers[id]?.cancel();
        _disposalTimers.remove(id);

        // **MEMORY: Small delay between disposals**
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        print(
            '❌ EnhancedControllerDisposal: Error processing controller ${entry.key}: $e');
      }
    }

    _isDisposing = false;
    print('✅ EnhancedControllerDisposal: Disposal queue processed');
  }

  /// Dispose all controllers immediately
  static Future<void> disposeAllControllers() async {
    print(
        '🗑️ EnhancedControllerDisposal: Disposing all controllers immediately');

    // **CANCEL: All timers first**
    for (final timer in _disposalTimers.values) {
      timer.cancel();
    }
    _disposalTimers.clear();

    // **DISPOSE: All controllers in queue**
    final controllersToDispose =
        Map<String, VideoPlayerController>.from(_disposalQueue);
    _disposalQueue.clear();

    for (final entry in controllersToDispose.entries) {
      try {
        final controller = entry.value;
        final id = entry.key;

        if (controller.value.isInitialized) {
          await controller.pause();
          controller.setVolume(0.0);
        }
        await controller.dispose();
        print('✅ EnhancedControllerDisposal: Disposed controller $id');

        // **MEMORY: Small delay between disposals**
        await Future.delayed(const Duration(milliseconds: 50));
      } catch (e) {
        print(
            '❌ EnhancedControllerDisposal: Error disposing controller ${entry.key}: $e');
      }
    }

    print('✅ EnhancedControllerDisposal: All controllers disposed');
  }

  /// Clear disposal queue without disposing
  static void clearDisposalQueue() {
    print('🧹 EnhancedControllerDisposal: Clearing disposal queue');

    // **CANCEL: All timers**
    for (final timer in _disposalTimers.values) {
      timer.cancel();
    }
    _disposalTimers.clear();

    // **CLEAR: Queue**
    _disposalQueue.clear();

    print('✅ EnhancedControllerDisposal: Disposal queue cleared');
  }

  /// Get disposal queue status
  static Map<String, dynamic> getDisposalStatus() {
    return {
      'queueSize': _disposalQueue.length,
      'activeTimers': _disposalTimers.length,
      'isDisposing': _isDisposing,
      'queuedControllers': _disposalQueue.keys.toList(),
    };
  }

  /// Force cleanup of all resources
  static Future<void> forceCleanup() async {
    print('🧹 EnhancedControllerDisposal: Force cleanup initiated');

    // **CANCEL: All timers**
    for (final timer in _disposalTimers.values) {
      timer.cancel();
    }
    _disposalTimers.clear();

    // **DISPOSE: All controllers immediately**
    await disposeAllControllers();

    // **MEMORY: Force garbage collection hint**
    await Future.delayed(const Duration(milliseconds: 200));

    print('✅ EnhancedControllerDisposal: Force cleanup completed');
  }

  /// Check if controller is in disposal queue
  static bool isControllerInQueue(String identifier) {
    return _disposalQueue.containsKey(identifier);
  }

  /// Remove controller from disposal queue
  static void removeFromQueue(String identifier) {
    if (_disposalQueue.containsKey(identifier)) {
      _disposalQueue.remove(identifier);
      _disposalTimers[identifier]?.cancel();
      _disposalTimers.remove(identifier);
      print(
          '🔄 EnhancedControllerDisposal: Removed controller $identifier from queue');
    }
  }

  /// Get memory usage statistics
  static Map<String, dynamic> getMemoryStats() {
    return {
      'disposalQueueSize': _disposalQueue.length,
      'activeTimers': _disposalTimers.length,
      'isDisposing': _isDisposing,
      'memoryPressure':
          Platform.isAndroid ? 'Android detected' : 'iOS detected',
    };
  }
}
