import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';

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
  double _lastVibrateValue = 0.0; // **NEW: Track last haptic position**

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
                _lastVibrateValue = value;
              });
              HapticFeedback.mediumImpact(); // **STRONGER: Initial touch feedback**
            },
            onChanged: (value) {
              setState(() {
                _dragValue = value;
              });
              
              // **HAPTIC: Vibrate when reaching start or end**
              if (value <= 0.01 || value >= 0.99) {
                if ((value - _lastVibrateValue).abs() > 0.01) {
                  HapticFeedback.vibrate(); // **STRONGER: Boundary feedback**
                  _lastVibrateValue = value;
                }
              } else if ((value - _lastVibrateValue).abs() >= 0.02) {
                // **NEW: Increased frequency (2% notches) and stronger feel (lightImpact)**
                HapticFeedback.lightImpact();
                _lastVibrateValue = value;
              }
            },
            onChangeEnd: (value) async {
              HapticFeedback.mediumImpact(); // **STRONGER: End of seek feedback**
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
