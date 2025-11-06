import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class ThrottledProgressBar extends StatefulWidget {
  final VideoPlayerController controller;
  final double screenWidth;
  final Function(dynamic) onSeek;

  const ThrottledProgressBar({
    Key? key,
    required this.controller,
    required this.screenWidth,
    required this.onSeek,
  }) : super(key: key);

  @override
  State<ThrottledProgressBar> createState() => _ThrottledProgressBarState();
}

class _ThrottledProgressBarState extends State<ThrottledProgressBar> {
  double _progress = 0.0;
  Timer? _updateTimer;
  DateTime _lastUpdate = DateTime.now();
  static const Duration _updateInterval = Duration(milliseconds: 33); // ~30fps

  @override
  void initState() {
    super.initState();
    _updateProgress();
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    final now = DateTime.now();
    final timeSinceLastUpdate = now.difference(_lastUpdate);

    if (timeSinceLastUpdate >= _updateInterval) {
      _updateProgress();
      _lastUpdate = now;
    } else {
      _updateTimer?.cancel();
      final remainingTime = _updateInterval - timeSinceLastUpdate;
      _updateTimer = Timer(remainingTime, () {
        if (mounted) {
          _updateProgress();
          _lastUpdate = DateTime.now();
        }
      });
    }
  }

  void _updateProgress() {
    if (!mounted || !widget.controller.value.isInitialized) return;

    final duration = widget.controller.value.duration;
    final position = widget.controller.value.position;
    final totalMs = duration.inMilliseconds;
    final posMs = position.inMilliseconds;
    final newProgress = totalMs > 0 ? (posMs / totalMs).clamp(0.0, 1.0) : 0.0;

    if ((newProgress - _progress).abs() > 0.001) {
      setState(() {
        _progress = newProgress;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onSeek,
      onPanUpdate: widget.onSeek,
      child: Container(
        height: 4,
        color: Colors.black.withOpacity(0.2),
        child: Stack(
          children: [
            Container(
              height: 2,
              margin: const EdgeInsets.only(top: 1),
              color: Colors.grey.withOpacity(0.2),
            ),
            Positioned(
              top: 1,
              left: 0,
              child: Container(
                height: 2,
                width: widget.screenWidth * _progress,
                color: Colors.green[400],
              ),
            ),
            if (_progress > 0)
              Positioned(
                top: 0,
                left: (widget.screenWidth * _progress) - 4,
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
  }
}
