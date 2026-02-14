import 'dart:async';
import 'package:flutter/material.dart';

class FingerTapGuide extends StatefulWidget {
  final GlobalKey targetKey;
  final VoidCallback onDismiss;

  const FingerTapGuide({
    super.key,
    required this.targetKey,
    required this.onDismiss,
  });

  @override
  State<FingerTapGuide> createState() => _FingerTapGuideState();
}

class _FingerTapGuideState extends State<FingerTapGuide>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _pulseAnimation;
  late Animation<double> _translateAnimation;
  Offset? _targetPosition;
  Timer? _updateTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    _translateAnimation = Tween<double>(begin: 0.0, end: 10.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );

    // **SMART: Use a periodic timer to update position (handles scrolling)**
    _updateTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      _updatePosition();
    });
  }

  void _updatePosition() {
    if (!mounted) return;

    final position = _calculatePosition();
    if (position != null && position != _targetPosition) {
      setState(() {
        _targetPosition = position;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _updateTimer?.cancel();
    super.dispose();
  }

  Offset? _calculatePosition() {
    try {
      final context = widget.targetKey.currentContext;
      if (context == null) return null;

      final renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) return null;

      final position = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;

      // Position finger at the center of the button
      return Offset(
        position.dx + size.width / 2,
        position.dy + size.height / 2,
      );
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_targetPosition == null) {
      // Return a transparent overlay while searching so taps still dismiss
      return Material(
        color: Colors.transparent,
        child: GestureDetector(
          onTap: widget.onDismiss,
          behavior: HitTestBehavior.opaque,
          child: Container(
            color: Colors.black.withValues(alpha: 0.05),
          ),
        ),
      );
    }

    final position = _targetPosition!;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Semi-transparent background that dismisses on tap
          GestureDetector(
            onTap: widget.onDismiss,
            behavior: HitTestBehavior.opaque,
            child: Container(
              color: Colors.black.withValues(alpha: 0.1),
            ),
          ),
          
          // The finger animation
          Positioned(
            left: position.dx - 25, // Centering adjustments
            top: position.dy - 25, // FIXED: Corrected vertical offset to point to center
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.translate(
                        offset: Offset(0, _translateAnimation.value),
                        child: Transform.scale(
                          scale: _pulseAnimation.value,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              // Pulse ring
                              Container(
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.green.withValues(alpha: 0.3 * (1 - _controller.value)),
                                  border: Border.all(
                                    color: Colors.green.withValues(alpha: 0.5 * (1 - _controller.value)),
                                    width: 2,
                                  ),
                                ),
                              ),
                              // Hand icon
                              const Icon(
                                Icons.touch_app,
                                size: 40,
                                color: Colors.white,
                                shadows: [
                                  Shadow(
                                    color: Colors.black45,
                                    blurRadius: 10,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black87,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'Tap here to add UPI ID',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
