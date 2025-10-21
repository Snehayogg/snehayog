import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

/// Utility class for proper video controller disposal
/// Helps prevent memory leaks and ensures clean resource cleanup
class VideoDisposalUtils {
  /// Dispose a single video controller with proper cleanup
  static void disposeController(VideoPlayerController controller,
      {String? identifier}) {
    try {
      // Pause and stop before disposing
      if (controller.value.isInitialized) {
        controller.pause();
        controller.setVolume(0.0);
      }

      // Dispose the controller
      controller.dispose();

      if (identifier != null) {
        print('🗑️ VideoDisposalUtils: Disposed controller $identifier');
      }
    } catch (e) {
      print(
          '❌ VideoDisposalUtils: Error disposing controller ${identifier ?? 'unknown'}: $e');
    }
  }

  /// Dispose multiple controllers with proper cleanup
  static void disposeControllers(Map<int, VideoPlayerController> controllers) {
    controllers.forEach((index, controller) {
      disposeController(controller, identifier: 'index_$index');
    });
  }

  /// Dispose controllers with listeners cleanup
  static void disposeControllersWithListeners(
    Map<int, VideoPlayerController> controllers,
    Map<int, VoidCallback> listeners,
  ) {
    controllers.forEach((index, controller) {
      try {
        // Remove listeners first
        if (listeners.containsKey(index)) {
          controller.removeListener(listeners[index]!);
        }

        // Dispose the controller
        disposeController(controller, identifier: 'index_$index');
      } catch (e) {
        print(
            '❌ VideoDisposalUtils: Error disposing controller with listeners index_$index: $e');
      }
    });
  }

  /// Dispose all controllers in a list
  static void disposeControllerList(List<VideoPlayerController> controllers) {
    for (int i = 0; i < controllers.length; i++) {
      disposeController(controllers[i], identifier: 'list_index_$i');
    }
  }

  /// Check if a controller is properly disposed
  static bool isControllerDisposed(VideoPlayerController controller) {
    try {
      // Try to access a property - if it throws, controller is disposed
      final _ = controller.value;
      return false;
    } catch (e) {
      return true;
    }
  }

  /// Force garbage collection after disposal (for debugging)
  static void forceGarbageCollection() {
    // This is mainly for debugging purposes
    // In production, let Flutter handle garbage collection
    print('🧹 VideoDisposalUtils: Requesting garbage collection');
  }
}
