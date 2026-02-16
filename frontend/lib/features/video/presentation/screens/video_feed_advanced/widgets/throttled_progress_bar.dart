import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/services.dart';
import 'package:vayu/shared/theme/app_theme.dart';

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
    // We use globalPosition.dx but map it to the local RenderBox to ensure accuracy
    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final Offset localPosition = renderBox.globalToLocal(
      details is DragUpdateDetails ? details.globalPosition : (details as TapDownDetails).globalPosition
    );
    
    final newProgress = (localPosition.dx / widget.screenWidth).clamp(0.0, 1.0);
    
    setState(() {
      _progress = newProgress;
    });
    
    widget.onSeek(details);

    // **HAPTIC: Vibrate when reaching start or end**
    if (newProgress <= 0.0 || newProgress >= 1.0) {
      HapticFeedback.lightImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (details) {
        setState(() => _isDragging = true);
        HapticFeedback.selectionClick(); // **NEW: Initial touch feedback**
        _handleSeekUpdate(details);
      },
      onTapUp: (_) => setState(() => _isDragging = false),
      onTapCancel: () => setState(() => _isDragging = false),
      onHorizontalDragStart: (details) {
        setState(() => _isDragging = true);
        HapticFeedback.selectionClick();
      },
      onHorizontalDragUpdate: (details) => _handleSeekUpdate(details),
      onHorizontalDragEnd: (_) => setState(() => _isDragging = false),
      onHorizontalDragCancel: () => setState(() => _isDragging = false),
      child: Container(
        height: 40, // **ENLARGED hit target for even easier access**
        color: Colors.transparent,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            // 1. Background track (Height animates, width is constant)
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutCubic,
              height: _isDragging ? 6 : 2,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.white.withOpacity(_isDragging ? 0.3 : 0.2),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            
            // 2. Progress bar filled portion
            // We use a regular Positioned width to avoid animation flicker during seek
            Positioned(
              left: 0,
              width: widget.screenWidth * _progress,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                height: _isDragging ? 6 : 2, // Height animates on hold
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            
            // 3. Seek handle (thumb)
            // Positioned updates instantly (no animation)
            Positioned(
              left: ((widget.screenWidth * _progress) - (_isDragging ? 7 : 1.5))
                  .clamp(0.0, widget.screenWidth - (_isDragging ? 14 : 3)),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOutCubic,
                width: _isDragging ? 10 : 3, // Size animates on hold
                height: _isDragging ? 8 : 2,
                decoration: BoxDecoration(
                  color: AppTheme.primary,
                  shape: BoxShape.circle,
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
