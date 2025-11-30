import 'package:flutter/material.dart';
import 'dart:math' as math;

/// **PROFESSIONAL LIKE BUTTON - YouTube/Instagram Style**
///
/// Features:
/// - Smooth scale animations
/// - Color transitions
/// - Visual feedback on tap
/// - Optimistic updates support
/// - Professional look and feel
class ProfessionalLikeButton extends StatefulWidget {
  final bool isLiked;
  final int likesCount;
  final VoidCallback onTap;
  final double iconSize;
  final bool showAnimation;
  final bool isProcessing;

  const ProfessionalLikeButton({
    Key? key,
    required this.isLiked,
    required this.likesCount,
    required this.onTap,
    this.iconSize = 28.0,
    this.showAnimation = true,
    this.isProcessing = false,
  }) : super(key: key);

  @override
  State<ProfessionalLikeButton> createState() => _ProfessionalLikeButtonState();
}

class _ProfessionalLikeButtonState extends State<ProfessionalLikeButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  bool _isLiked = false;
  bool _justLiked = false;

  @override
  void initState() {
    super.initState();
    _isLiked = widget.isLiked;

    // Scale animation for state change feedback (only when liking)
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 200),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
  }

  @override
  void didUpdateWidget(ProfessionalLikeButton oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Detect like state change
    if (oldWidget.isLiked != widget.isLiked) {
      _isLiked = widget.isLiked;
      if (widget.isLiked && widget.showAnimation) {
        _justLiked = true;
        _triggerAnimation();
        // Reset just liked flag after animation
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            setState(() {
              _justLiked = false;
            });
          }
        });
      }
    }
  }

  void _triggerAnimation() {
    if (widget.showAnimation) {
      _animationController.forward().then((_) {
        _animationController.reverse();
      });
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (!widget.isProcessing) {
      // Don't trigger animation on tap - let state change handle it
      // This prevents duplicate animations
      widget.onTap();
    }
  }

  String _formatLikeCount(int count) {
    if (count < 1000) {
      return count.toString();
    } else if (count < 1000000) {
      final kCount = (count / 1000).toStringAsFixed(1);
      return '${kCount}K'.replaceAll(RegExp(r'\.0'), '');
    } else {
      final mCount = (count / 1000000).toStringAsFixed(1);
      return '${mCount}M'.replaceAll(RegExp(r'\.0'), '');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLikedState = _isLiked || widget.isLiked;

    return GestureDetector(
      onTap: _handleTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Match styling with other action buttons - circular background
          AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              // Only animate on state change (when just liked), not on every tap
              final scale = _justLiked && widget.showAnimation
                  ? _scaleAnimation.value
                  : 1.0;

              return Transform.scale(
                scale: scale,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isLikedState ? Icons.favorite : Icons.favorite_border,
                    color: isLikedState ? Colors.red : Colors.white,
                    size: 18, // Match other action buttons
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 4),

          // Like count with smooth transitions
          AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 200),
            style: TextStyle(
              color: isLikedState ? Colors.red.shade400 : Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            child: Text(
              _formatLikeCount(widget.likesCount),
              style: const TextStyle(
                shadows: [
                  Shadow(
                    color: Colors.black54,
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// **HEART BURST ANIMATION - For double-tap like (Instagram style)**
class HeartBurstAnimation extends StatefulWidget {
  final Offset position;
  final VoidCallback? onComplete;

  const HeartBurstAnimation({
    Key? key,
    required this.position,
    this.onComplete,
  }) : super(key: key);

  @override
  State<HeartBurstAnimation> createState() => _HeartBurstAnimationState();
}

class _HeartBurstAnimationState extends State<HeartBurstAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _rotationAnimation;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(
      begin: 0.0,
      end: 1.5,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    ));

    _opacityAnimation = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.5, 1.0, curve: Curves.easeIn),
    ));

    _rotationAnimation = Tween<double>(
      begin: 0.0,
      end: 2 * math.pi,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _controller.forward().then((_) {
      widget.onComplete?.call();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: widget.position.dx - 24,
      top: widget.position.dy - 24,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Opacity(
              opacity: _opacityAnimation.value,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: Transform.rotate(
                  angle: _rotationAnimation.value,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Glow circles
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.red
                              .withOpacity(0.3 * _opacityAnimation.value),
                        ),
                      ),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.red
                              .withOpacity(0.5 * _opacityAnimation.value),
                        ),
                      ),
                      // Heart icon
                      const Icon(
                        Icons.favorite,
                        color: Colors.red,
                        size: 32,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
