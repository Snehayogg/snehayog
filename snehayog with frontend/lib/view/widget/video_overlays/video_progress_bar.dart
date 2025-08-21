import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/core/constants/video_constants.dart';

class VideoProgressBar extends StatelessWidget {
  final VideoPlayerController controller;

  const VideoProgressBar({
    Key? key,
    required this.controller,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final duration = controller.value.duration;
    final position = controller.value.position;

    if (duration.inMilliseconds == 0) {
      return const SizedBox.shrink();
    }

    final progress = position.inMilliseconds / duration.inMilliseconds;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SizedBox(
        height: VideoConstants.progressBarHeight,
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.white.withOpacity(VideoConstants.lightTextOpacity),
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
        ),
      ),
    );
  }
}
