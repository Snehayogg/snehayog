import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoProgressBar extends StatefulWidget {
  final VideoPlayerController controller;

  const VideoProgressBar({
    Key? key,
    required this.controller,
  }) : super(key: key);

  @override
  State<VideoProgressBar> createState() => _VideoProgressBarState();
}

class _VideoProgressBarState extends State<VideoProgressBar> {
  bool _isDragging = false;
  double _dragValue = 0.0;

  @override
  Widget build(BuildContext context) {
    if (!widget.controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final duration = widget.controller.value.duration;
    final position = widget.controller.value.position;

    if (duration.inMilliseconds == 0) {
      return const SizedBox.shrink();
    }

    final progress = _isDragging
        ? _dragValue
        : position.inMilliseconds / duration.inMilliseconds;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        height: 30, // Increased height for better touch area
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3.0,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 6.0,
              pressedElevation: 8.0,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
            activeTrackColor: Colors.lightGreen[400], // Light green color
            inactiveTrackColor: Colors.white.withOpacity(0.3),
            thumbColor: Colors.lightGreen[300],
            overlayColor: Colors.lightGreen.withOpacity(0.2),
          ),
          child: Slider(
            value: progress.clamp(0.0, 1.0),
            onChangeStart: (value) {
              setState(() {
                _isDragging = true;
                _dragValue = value;
              });
            },
            onChanged: (value) {
              setState(() {
                _dragValue = value;
              });
            },
            onChangeEnd: (value) async {
              final newPosition = Duration(
                milliseconds: (value * duration.inMilliseconds).round(),
              );
              await widget.controller.seekTo(newPosition);
              setState(() {
                _isDragging = false;
              });
            },
          ),
        ),
      ),
    );
  }
}
