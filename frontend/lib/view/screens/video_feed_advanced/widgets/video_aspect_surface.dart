import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:vayu/utils/app_logger.dart';

class VideoAspectSurface extends StatelessWidget {
  final VideoPlayerController controller;
  final double modelAspectRatio;

  const VideoAspectSurface({
    Key? key,
    required this.controller,
    required this.modelAspectRatio,
  }) : super(key: key);

  bool _isPortraitVideo(double aspectRatio) {
    const double portraitThreshold = 0.7;
    return aspectRatio < portraitThreshold;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        final screenHeight = constraints.maxHeight;

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
      },
    );
  }
}
