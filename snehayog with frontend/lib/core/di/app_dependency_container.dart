import 'package:snehayog/core/managers/video_player_state_manager.dart';
import 'package:snehayog/core/services/video_url_service.dart';
import 'package:snehayog/core/services/error_logging_service.dart';


class AppDependencyContainer {
  static final AppDependencyContainer _instance = AppDependencyContainer._internal();
  factory AppDependencyContainer() => _instance;
  AppDependencyContainer._internal();

  // Service instances
  VideoUrlService? _videoUrlService;
  ErrorLoggingService? _errorLoggingService;

  // Manager instances
  final Map<String, VideoPlayerStateManager> _videoPlayerManagers = {};

  /// Get or create a VideoPlayerStateManager for a specific video
  VideoPlayerStateManager getVideoPlayerManager(String videoId) {
    if (!_videoPlayerManagers.containsKey(videoId)) {
      _videoPlayerManagers[videoId] = VideoPlayerStateManager();
    }
    return _videoPlayerManagers[videoId]!;
  }

  /// Dispose of a specific video player manager
  void disposeVideoPlayerManager(String videoId) {
    _videoPlayerManagers[videoId]?.dispose();
    _videoPlayerManagers.remove(videoId);
  }

  /// Dispose of all video player managers
  void disposeAllVideoPlayerManagers() {
    for (final manager in _videoPlayerManagers.values) {
      manager.dispose();
    }
    _videoPlayerManagers.clear();
  }

  /// Get the VideoUrlService instance
  VideoUrlService get videoUrlService {
    _videoUrlService ??= VideoUrlService();
    return _videoUrlService!;
  }

  /// Get the ErrorLoggingService instance
  ErrorLoggingService get errorLoggingService {
    _errorLoggingService ??= ErrorLoggingService();
    return _errorLoggingService!;
  }

  /// Clean up all resources
  void dispose() {
    disposeAllVideoPlayerManagers();
    _videoUrlService = null;
    _errorLoggingService = null;
  }

  /// Get the total number of active video player managers
  int get activeVideoPlayerCount => _videoPlayerManagers.length;

  /// Check if a specific video player manager exists
  bool hasVideoPlayerManager(String videoId) => _videoPlayerManagers.containsKey(videoId);
}
