import 'dart:async';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/core/managers/video_controller_manager.dart';

/// Service to optimize video startup and auto-play after app clear
class VideoStartupOptimizer {
  static final VideoStartupOptimizer _instance =
      VideoStartupOptimizer._internal();
  factory VideoStartupOptimizer() => _instance;
  VideoStartupOptimizer._internal();

  final VideoControllerManager _controllerManager = VideoControllerManager();
  final Map<String, bool> _startupCache = {};
  Timer? _warmupTimer;

  /// **OPTIMIZE STARTUP: Pre-warm video controllers for faster loading**
  Future<void> optimizeVideoStartup(
      List<VideoModel> videos, int currentIndex) async {
    print('🚀 VideoStartupOptimizer: Starting video startup optimization');

    // Clear any existing warmup
    _warmupTimer?.cancel();

    // Immediate optimization for current video
    if (videos.isNotEmpty && currentIndex < videos.length) {
      await _preWarmCurrentVideo(videos[currentIndex], currentIndex);
    }

    // Background warmup for next videos
    _scheduleBackgroundWarmup(videos, currentIndex);
  }

  /// **PRE-WARM CURRENT VIDEO: Immediate optimization**
  Future<void> _preWarmCurrentVideo(VideoModel video, int index) async {
    try {
      print(
          '🔥 VideoStartupOptimizer: Pre-warming current video: ${video.videoName}');

      // Get controller immediately
      final controller = await _controllerManager.getController(index, video);

      // Pre-initialize without playing
      if (!controller.value.isInitialized) {
        await controller.initialize();
        print(
            '✅ VideoStartupOptimizer: Controller initialized for ${video.videoName}');
      }

      // Warm network connection
      _warmNetworkConnection(video.videoUrl);

      // Mark as warmed
      _startupCache[video.id] = true;
    } catch (e) {
      print('❌ VideoStartupOptimizer: Error pre-warming video: $e');
    }
  }

  /// **SCHEDULE BACKGROUND WARMUP: For next videos**
  void _scheduleBackgroundWarmup(List<VideoModel> videos, int currentIndex) {
    _warmupTimer?.cancel();

    _warmupTimer = Timer(const Duration(milliseconds: 500), () async {
      // Warm up next 2-3 videos
      final endIndex = (currentIndex + 3).clamp(0, videos.length);

      for (int i = currentIndex + 1; i < endIndex; i++) {
        if (i < videos.length) {
          final video = videos[i];
          if (!_startupCache.containsKey(video.id)) {
            await _preWarmVideoInBackground(video, i);
          }
        }
      }
    });
  }

  /// **PRE-WARM VIDEO IN BACKGROUND: Non-blocking**
  Future<void> _preWarmVideoInBackground(VideoModel video, int index) async {
    try {
      print(
          '🔥 VideoStartupOptimizer: Background warming video: ${video.videoName}');

      // Get controller
      final controller = await _controllerManager.getController(index, video);

      // Initialize if needed
      if (!controller.value.isInitialized) {
        await controller.initialize();
        print(
            '✅ VideoStartupOptimizer: Background controller initialized for ${video.videoName}');
      }

      // Mark as warmed
      _startupCache[video.id] = true;
    } catch (e) {
      print('❌ VideoStartupOptimizer: Error background warming video: $e');
    }
  }

  /// **WARM NETWORK CONNECTION: Pre-establish connection**
  void _warmNetworkConnection(String videoUrl) {
    try {
      // This helps establish network connection early
      print(
          '🌐 VideoStartupOptimizer: Warming network connection for: $videoUrl');

      // You can add actual network warming here if needed
      // For now, just log the action
    } catch (e) {
      print('❌ VideoStartupOptimizer: Error warming network: $e');
    }
  }

  /// **ENSURE AUTO-PLAY: Force auto-play after startup**
  Future<void> ensureAutoPlay(int currentIndex) async {
    try {
      print(
          '▶️ VideoStartupOptimizer: Ensuring auto-play for index: $currentIndex');

      // Wait a bit for initialization
      await Future.delayed(const Duration(milliseconds: 300));

      // Play the current video
      await _controllerManager.playController(currentIndex);

      print(
          '✅ VideoStartupOptimizer: Auto-play ensured for index: $currentIndex');
    } catch (e) {
      print('❌ VideoStartupOptimizer: Error ensuring auto-play: $e');
    }
  }

  /// **CLEAR STARTUP CACHE: When app is cleared**
  void clearStartupCache() {
    print('🧹 VideoStartupOptimizer: Clearing startup cache');
    _startupCache.clear();
    _warmupTimer?.cancel();
  }

  /// **CHECK IF VIDEO IS WARMED: Check cache**
  bool isVideoWarmed(String videoId) {
    return _startupCache[videoId] ?? false;
  }

  /// **DISPOSE: Clean up resources**
  void dispose() {
    _warmupTimer?.cancel();
    _startupCache.clear();
  }
}
