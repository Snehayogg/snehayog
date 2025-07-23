import 'package:video_player/video_player.dart';

class VideoControllerManager {
  static final VideoControllerManager _instance = VideoControllerManager._internal();
  factory VideoControllerManager() => _instance;
  VideoControllerManager._internal();

  final List<VideoPlayerController> _controllers = [];

  // Register a video controller
  void registerController(VideoPlayerController controller) {
    if (!_controllers.contains(controller)) {
      _controllers.add(controller);
    }
  }

  // Unregister a video controller
  void unregisterController(VideoPlayerController controller) {
    _controllers.remove(controller);
  }

  // Pause all registered video controllers
  void pauseAllVideos() {
    for (final controller in _controllers) {
      if (controller.value.isInitialized && controller.value.isPlaying) {
        controller.pause();
      }
    }
  }

  // Clear all controllers (useful for cleanup)
  void clearAll() {
    _controllers.clear();
  }

  // Get count of registered controllers (for debugging)
  int get controllerCount => _controllers.length;
}