import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/features/video/core/presentation/managers/shared_video_controller_pool.dart';

class VideoAspectSurface extends StatelessWidget {
  final VideoPlayerController controller;
  final double modelAspectRatio;

  final VoidCallback? onControllerInvalid;

  const VideoAspectSurface({
    Key? key,
    required this.controller,
    required this.modelAspectRatio,
    this.onControllerInvalid,
  }) : super(key: key);

  bool _isPortraitVideo(double aspectRatio) {
    const double portraitThreshold = 0.7;
    return aspectRatio < portraitThreshold;
  }

  @override
  Widget build(BuildContext context) {
    // **REACTIVE RECOVERY: Atomic validity check**
    final sharedPool = SharedVideoControllerPool();
    if (!sharedPool.isControllerValid(controller)) {
      // Trigger recovery on next frame
      if (onControllerInvalid != null) {
        Future.microtask(() => onControllerInvalid!());
      }
      return const Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white24,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        try {
          // Double check disposal within builder to prevent race conditions
          if (sharedPool.isControllerDisposed(controller)) {
            return const Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white24,
              ),
            );
          }

          final Size videoSize = controller.value.size;
          final int rotation = controller.value.rotationCorrection;

          AppLogger.log('🎬 MODEL aspect ratio: $modelAspectRatio');
          AppLogger.log(
              '🎬 Video dimensions: ${videoSize.width}x${videoSize.height}');
          AppLogger.log('🎬 Rotation: $rotation degrees');
          AppLogger.log('🎬 Using MODEL aspect ratio instead of detected ratio');

          // Debug aspect ratio
          double videoWidth = videoSize.width;
          double videoHeight = videoSize.height;
          if (rotation == 90 || rotation == 270) {
            videoWidth = videoSize.height;
            videoHeight = videoSize.width;
          }
          final double detectedAspectRatio = videoWidth / videoHeight;
          final bool isPortrait =
              detectedAspectRatio < 1.0 || _isPortraitVideo(detectedAspectRatio);
          AppLogger.log(
              '🔍 DETECTED aspect ratio: $detectedAspectRatio, isPortrait: $isPortrait');

          if (modelAspectRatio < 1.0) {
            // Portrait
            return FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: videoWidth,
                height: videoHeight,
                child: VideoPlayer(controller),
              ),
            );
          } else {
            // Landscape
            return FittedBox(
              fit: BoxFit.contain,
              child: SizedBox(
                width: videoWidth,
                height: videoHeight,
                child: VideoPlayer(controller),
              ),
            );
          }
        } catch (e) {
          AppLogger.log('⚠️ VideoAspectSurface: Caught disposal race condition: $e');
          // Trigger recovery on next frame
          if (onControllerInvalid != null) {
            Future.microtask(() => onControllerInvalid!());
          }
          return const Center(
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white24,
            ),
          );
        }
      },
    );
  }
}
