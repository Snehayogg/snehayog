import 'package:flutter/material.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/view/screens/video_feed_advanced.dart';
import 'package:vayu/core/managers/video_controller_manager.dart';
import 'package:vayu/core/managers/shared_video_controller_pool.dart';
import 'package:provider/provider.dart';
import 'package:vayu/controller/main_controller.dart';
import 'package:vayu/utils/app_logger.dart';

class VideoScreen extends StatefulWidget {
  final int? initialIndex;
  final List<VideoModel>? initialVideos;
  final String? initialVideoId;

  const VideoScreen({
    Key? key,
    this.initialIndex,
    this.initialVideos,
    this.initialVideoId,
  }) : super(key: key);

  @override
  State<VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  final GlobalKey _videoFeedKey = GlobalKey();

  /// **PUBLIC: Refresh video list after upload**
  Future<void> refreshVideos() async {
    AppLogger.log('🔄 VideoScreen: refreshVideos() called');
    final videoFeedState = _videoFeedKey.currentState;
    if (videoFeedState != null) {
      // Cast to dynamic to access the refreshVideos method
      await (videoFeedState as dynamic).refreshVideos();
      AppLogger.log('✅ VideoScreen: Video refresh completed');
    } else {
      AppLogger.log('❌ VideoScreen: VideoFeedAdvanced state not found');
    }
  }

  @override
  void initState() {
    super.initState();
    AppLogger.log('🎬 VideoScreen: Initializing VideoScreen');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = _videoFeedKey.currentState;
      if (state != null) {
        try {
          (state as dynamic).forcePlayCurrent();
        } catch (_) {}
      }
      // Some devices need a short delay for the first frame to attach
      Future.delayed(const Duration(milliseconds: 120), () {
        final s = _videoFeedKey.currentState;
        if (s != null) {
          try {
            (s as dynamic).forcePlayCurrent();
          } catch (_) {}
        }
      });
    });
  }

  @override
  void dispose() {
    AppLogger.log('🗑️ VideoScreen: Disposing VideoScreen');

    // **FIX: Check if opened from ProfileScreen and dispose controllers immediately**
    final bool openedFromProfile =
        widget.initialVideos != null && widget.initialVideos!.isNotEmpty;

    if (openedFromProfile) {
      AppLogger.log(
          '🧹 VideoScreen: Opened from ProfileScreen - disposing controllers immediately');
      try {
        final sharedPool = SharedVideoControllerPool();
        sharedPool.clearAll();
        AppLogger.log(
            '✅ VideoScreen: Cleared shared pool on dispose (profile flow)');
      } catch (e) {
        AppLogger.log('⚠️ VideoScreen: Error clearing shared pool: $e');
      }
    }

    // **FIX: Pause all videos when leaving VideoScreen**
    try {
      final mainController =
          Provider.of<MainController>(context, listen: false);
      mainController.forcePauseVideos();

      final videoControllerManager = VideoControllerManager();
      videoControllerManager.forcePauseAllVideosSync(); // Use sync version

      AppLogger.log('🔇 VideoScreen: All videos paused on dispose');
    } catch (e) {
      AppLogger.log('⚠️ VideoScreen: Error pausing videos on dispose: $e');
    }

    // Clean up the video feed if needed
    final videoFeedState = _videoFeedKey.currentState;
    if (videoFeedState != null) {
      try {
        // The VideoFeedAdvanced dispose method will be called automatically
        AppLogger.log(
            '✅ VideoScreen: VideoFeedAdvanced disposal handled automatically');
      } catch (e) {
        AppLogger.log('⚠️ VideoScreen: Error during disposal: $e');
      }
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // When videos come from profile, don't filter by videoType
    // Only use videoType when loading from API (no initialVideos)
    final String? videoType =
        widget.initialVideos == null || widget.initialVideos!.isEmpty
            ? 'yug'
            : null;

    return VideoFeedAdvanced(
      key: _videoFeedKey,
      initialIndex: widget.initialIndex,
      initialVideos: widget.initialVideos,
      initialVideoId: widget.initialVideoId,
      videoType: videoType,
    );
  }
}
