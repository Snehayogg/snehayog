import 'package:snehayog/core/managers/video_manager.dart';
import 'package:snehayog/core/services/video_url_service.dart';
import 'package:snehayog/core/services/error_logging_service.dart';


class AppDependencyContainer {
  static final AppDependencyContainer _instance =
      AppDependencyContainer._internal();
  factory AppDependencyContainer() => _instance;
  AppDependencyContainer._internal();

  // Service instances
  VideoUrlService? _videoUrlService;
  ErrorLoggingService? _errorLoggingService;

  // Manager instances
  final Map<String, VideoManager> _videoManagers = {};

  /// Get or create a VideoManager for a specific video
  VideoManager getVideoManager(String videoId) {
    if (!_videoManagers.containsKey(videoId)) {
      _videoManagers[videoId] = VideoManager();
    }
    return _videoManagers[videoId]!;
  }

  /// Dispose of a specific video manager
  void disposeVideoManager(String videoId) {
    _videoManagers[videoId]?.dispose();
    _videoManagers.remove(videoId);
  }

  /// Dispose of all video managers
  void disposeAllVideoManagers() {
    for (final manager in _videoManagers.values) {
      manager.dispose();
    }
    _videoManagers.clear();
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
    disposeAllVideoManagers();
    _videoUrlService = null;
    _errorLoggingService = null;
  }

  /// Get the total number of active video managers
  int get activeVideoCount => _videoManagers.length;

  /// Check if a specific video manager exists
  bool hasVideoManager(String videoId) => _videoManagers.containsKey(videoId);
}
