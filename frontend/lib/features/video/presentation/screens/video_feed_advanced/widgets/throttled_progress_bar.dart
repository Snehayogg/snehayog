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
  bool _isDragging = false; // **NEW: Track if user is currently seeking**
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
    // **NEW: Don't update progress from controller while dragging/seeking**
    if (_isDragging) return;

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

  void _handleSeekUpdate(dynamic details) {
    // Calculate new progress based on touch/drag position
    final double dx = details is DragUpdateDetails 
        ? details.globalPosition.dx 
        : (details as TapDownDetails).globalPosition.dx;
    
    setState(() {
      _progress = (dx / widget.screenWidth).clamp(0.0, 1.0);
    });
    
    widget.onSeek(details);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        setState(() => _isDragging = true);
        _handleSeekUpdate(details);
      },
      onTapUp: (_) => setState(() => _isDragging = false),
      onTapCancel: () => setState(() => _isDragging = false),
      onHorizontalDragStart: (_) => setState(() => _isDragging = true),
      onHorizontalDragUpdate: (details) => _handleSeekUpdate(details),
      onHorizontalDragEnd: (_) => setState(() => _isDragging = false),
      onHorizontalDragCancel: () => setState(() => _isDragging = false),
      child: Container(
        height: 60, // **ENLARGED hit target for even easier access**
        color: Colors.transparent,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background track
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              height: _isDragging ? 6 : 2, // **DYNAMIC: Thickens on hold**
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(_isDragging ? 0.3 : 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            // Progress tracker
            Positioned(
              left: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                height: _isDragging ? 6 : 2, // **DYNAMIC: Thickens on hold**
                width: widget.screenWidth * _progress,
                decoration: BoxDecoration(
                  color: Colors.green[400],
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            // Thumb indicator
            Positioned(
              left: (widget.screenWidth * _progress) - (_isDragging ? 8 : 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: _isDragging ? 16 : 8, // **DYNAMIC: Larger thumb on hold**
                height: _isDragging ? 16 : 6,
                decoration: BoxDecoration(
                  color: Colors.green[400],
                  shape: _isDragging ? BoxShape.circle : BoxShape.rectangle,
                  borderRadius: _isDragging ? null : BorderRadius.circular(4),
                  boxShadow: _isDragging ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    )
                  ] : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
