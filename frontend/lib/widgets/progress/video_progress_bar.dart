import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoProgressBar extends StatelessWidget {
  final VideoPlayerController controller;
  final void Function(dynamic details) onTapDown;
  final void Function(dynamic details) onPanUpdate;

  const VideoProgressBar({
    super.key,
    required this.controller,
    required this.onTapDown,
    required this.onPanUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final duration = value.duration;
        final position = value.position;
        final totalMs = duration.inMilliseconds;
        final posMs = position.inMilliseconds;
        final progress = totalMs > 0 ? (posMs / totalMs).clamp(0.0, 1.0) : 0.0;

        return GestureDetector(
          onTapDown: onTapDown,
          onPanUpdate: onPanUpdate,
          child: Container(
            height: 4,
            color: Colors.black.withOpacity(0.2),
            child: Stack(
              children: [
                Container(
                  height: 2,
                  margin: const EdgeInsets.only(top: 1),
                  color: Colors.white.withOpacity(0.15),
                ),
                Positioned(
                  top: 1,
                  left: 0,
                  child: Container(
                    height: 2,
                    width: MediaQuery.of(context).size.width * progress,
                    color: Colors.green[400],
                  ),
                ),
                if (progress > 0)
                  Positioned(
                    top: 0,
                    left: (MediaQuery.of(context).size.width * progress) - 4,
                    child: Container(
                      width: 8,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.green[400],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
