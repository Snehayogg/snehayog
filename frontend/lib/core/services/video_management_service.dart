import 'dart:async';
import 'package:video_player/video_player.dart';

/// **NEW: TikTok-style Video Management Service**
/// Manages video controllers for smooth PageView scrolling
class VideoManagementService {
  // **Current video controller**
  VideoPlayerController? _currentController;
  int _currentIndex = -1;

  // **Preloaded controllers for adjacent videos**
  final Map<int, VideoPlayerController> _preloadedControllers = {};

  // **Video URLs for preloading**
  final Map<int, String> _videoUrls = {};

  // **Controller states for better tracking**
  final Map<int, bool> _controllerInitialized = {};
  final Map<int, bool> _controllerHasError = {};

  // **Callbacks**
  final Function(int index)? onVideoStarted;
  final Function(int index)? onVideoPaused;
  final Function(String error)? onError;

  VideoManagementService({
    this.onVideoStarted,
    this.onVideoPaused,
    this.onError,
  });

  /// **Initialize video at specific index**
  Future<void> initializeVideo(int index, String videoUrl) async {
    try {
      print('🎬 VideoManagementService: Initializing video at index $index');

      // **Store video URL for preloading**
      _videoUrls[index] = videoUrl;

      // **Reset error state for this index**
      _controllerHasError[index] = false;

      // **If this is the current video, initialize and play**
      if (index == _currentIndex) {
        await _playCurrentVideo();
      }

      // **Preload adjacent videos**
      await _preloadAdjacentVideos(index);
    } catch (e) {
      print('❌ Error initializing video at index $index: $e');
      _controllerHasError[index] = true;
      onError?.call('Failed to initialize video: $e');
    }
  }

  /// **Handle page change - pause previous, play current**
  Future<void> onPageChanged(int newIndex) async {
    try {
      print(
          '🔄 VideoManagementService: Page changed from $_currentIndex to $newIndex');

      // **Pause previous video**
      if (_currentIndex != -1 && _currentIndex != newIndex) {
        await _pauseVideoAtIndex(_currentIndex);
      }

      // **Update current index**
      _currentIndex = newIndex;

      // **Play current video**
      await _playCurrentVideo();

      // **Preload adjacent videos**
      await _preloadAdjacentVideos(newIndex);
    } catch (e) {
      print('❌ Error handling page change: $e');
      onError?.call('Failed to handle page change: $e');
    }
  }

  /// **Play current video**
  Future<void> _playCurrentVideo() async {
    try {
      // **Get or create controller for current video**
      final controller = await _getOrCreateController(_currentIndex);
      if (controller == null) return;

      // **Set as current controller**
      _currentController = controller;

      // **Initialize if not already done or has error**
      if (!controller.value.isInitialized ||
          _controllerHasError[_currentIndex] == true) {
        print(
            '🔄 VideoManagementService: Initializing controller for index $_currentIndex');
        await controller.initialize();
        _controllerInitialized[_currentIndex] = true;
        _controllerHasError[_currentIndex] = false;
      }

      // **Check if controller is ready**
      if (!controller.value.isInitialized || controller.value.hasError) {
        print(
            '⚠️ VideoManagementService: Controller not ready for index $_currentIndex');
        onError?.call('Video controller not ready');
        return;
      }

      // **Play video**
      await controller.play();
      controller.setLooping(true);

      print('▶️ VideoManagementService: Playing video at index $_currentIndex');
      onVideoStarted?.call(_currentIndex);
    } catch (e) {
      print('❌ Error playing current video: $e');
      _controllerHasError[_currentIndex] = true;
      onError?.call('Failed to play video: $e');
    }
  }

  /// **Pause video at specific index**
  Future<void> _pauseVideoAtIndex(int index) async {
    try {
      final controller = _preloadedControllers[index];
      if (controller != null && controller.value.isPlaying) {
        await controller.pause();
        print('⏸️ VideoManagementService: Paused video at index $index');
        onVideoPaused?.call(index);
      }
    } catch (e) {
      print('❌ Error pausing video at index $index: $e');
    }
  }

  /// **Get or create controller for video at index**
  Future<VideoPlayerController?> _getOrCreateController(int index) async {
    try {
      // **Check if controller already exists and is healthy**
      if (_preloadedControllers.containsKey(index) &&
          _controllerInitialized[index] == true &&
          _controllerHasError[index] != true) {
        final controller = _preloadedControllers[index]!;
        if (controller.value.isInitialized && !controller.value.hasError) {
          return controller;
        }
      }

      // **Dispose old controller if exists but corrupted**
      if (_preloadedControllers.containsKey(index)) {
        await _disposeController(index);
      }

      // **Create new controller**
      final videoUrl = _videoUrls[index];
      if (videoUrl == null) {
        print('⚠️ VideoManagementService: No URL found for index $index');
        return null;
      }

      final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      _preloadedControllers[index] = controller;
      _controllerInitialized[index] = false;
      _controllerHasError[index] = false;

      print('🔧 VideoManagementService: Created controller for index $index');
      return controller;
    } catch (e) {
      print('❌ Error creating controller for index $index: $e');
      _controllerHasError[index] = true;
      return null;
    }
  }

  /// **Preload adjacent videos (i-1 and i+1)**
  Future<void> _preloadAdjacentVideos(int currentIndex) async {
    try {
      final indicesToPreload = [currentIndex - 1, currentIndex + 1];

      for (final index in indicesToPreload) {
        if (index >= 0 && _videoUrls.containsKey(index)) {
          await _preloadVideoAtIndex(index);
        }
      }
    } catch (e) {
      print('❌ Error preloading adjacent videos: $e');
    }
  }

  /// **Preload video at specific index**
  Future<void> _preloadVideoAtIndex(int index) async {
    try {
      // **Skip if already preloaded and healthy**
      if (_preloadedControllers.containsKey(index) &&
          _controllerInitialized[index] == true &&
          _controllerHasError[index] != true) {
        return;
      }

      // **Create controller for preloading**
      final videoUrl = _videoUrls[index];
      if (videoUrl == null) return;

      final controller = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
      _preloadedControllers[index] = controller;
      _controllerInitialized[index] = false;
      _controllerHasError[index] = false;

      // **Initialize but don't play**
      await controller.initialize();
      _controllerInitialized[index] = true;
      print('📦 VideoManagementService: Preloaded video at index $index');
    } catch (e) {
      print('❌ Error preloading video at index $index: $e');
      _controllerHasError[index] = true;
    }
  }

  /// **Get current controller**
  VideoPlayerController? get currentController => _currentController;

  /// **Get current index**
  int get currentIndex => _currentIndex;

  /// **Check if video is playing at index**
  bool isVideoPlaying(int index) {
    final controller = _preloadedControllers[index];
    return controller?.value.isPlaying ?? false;
  }

  /// **Check if video is ready at index**
  bool isVideoReady(int index) {
    final controller = _preloadedControllers[index];
    return controller != null &&
        _controllerInitialized[index] == true &&
        _controllerHasError[index] != true &&
        controller.value.isInitialized &&
        !controller.value.hasError;
  }

  /// **Dispose controller at specific index**
  Future<void> _disposeController(int index) async {
    try {
      final controller = _preloadedControllers.remove(index);
      if (controller != null) {
        await controller.dispose();
        _controllerInitialized.remove(index);
        _controllerHasError.remove(index);
        print(
            '🗑️ VideoManagementService: Disposed controller for index $index');
      }
    } catch (e) {
      print('❌ Error disposing controller for index $index: $e');
    }
  }

  /// **Dispose all controllers**
  void disposeAll() {
    print('🧹 VideoManagementService: Disposing all controllers');

    // **Dispose current controller**
    _currentController?.dispose();
    _currentController = null;

    // **Dispose all preloaded controllers**
    for (final controller in _preloadedControllers.values) {
      controller.dispose();
    }
    _preloadedControllers.clear();

    // **Clear state maps**
    _controllerInitialized.clear();
    _controllerHasError.clear();

    // **Reset state**
    _currentIndex = -1;
    _videoUrls.clear();
  }

  /// **Clean up old controllers (keep only current + adjacent)**
  void cleanupOldControllers(int currentIndex) {
    final indicesToKeep = [currentIndex - 1, currentIndex, currentIndex + 1];

    final keysToRemove = _preloadedControllers.keys
        .where((index) => !indicesToKeep.contains(index))
        .toList();

    for (final index in keysToRemove) {
      _disposeController(index);
    }
  }

  /// **Reset service state (useful for tab changes)**
  void resetState() {
    print('🔄 VideoManagementService: Resetting state');
    _currentIndex = -1;
    _currentController = null;
  }
}
