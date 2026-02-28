import 'package:flutter/material.dart';

/// A wrapper widget that provides a smooth, "bouncy" scaling micro-interaction
/// when the user taps on it.
///
/// Use this to wrap any static button or card to instantly give it a premium,
/// tactile feel (The "Smooth" Factor).
class InteractiveScaleButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double scaleDownFactor;
  final Duration animationDuration;
  final HitTestBehavior behavior;

  const InteractiveScaleButton({
    Key? key,
    required this.child,
    this.onTap,
    this.scaleDownFactor = 0.95,
    this.animationDuration = const Duration(milliseconds: 150),
    this.behavior = HitTestBehavior.opaque,
  }) : super(key: key);

  @override
  State<InteractiveScaleButton> createState() => _InteractiveScaleButtonState();
}

class _InteractiveScaleButtonState extends State<InteractiveScaleButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    // Use a spring-like curve for a more natural, fluid feel.
    _controller = AnimationController(
      vsync: this,
      duration: widget.animationDuration,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: widget.scaleDownFactor,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutSine,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onTap != null) {
      _controller.forward();
    }
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.onTap != null) {
      _controller.reverse();
      widget.onTap!();
    }
  }

  void _onTapCancel() {
    if (widget.onTap != null) {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            alignment: Alignment.center,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
