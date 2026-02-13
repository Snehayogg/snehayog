import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class HeartAnimation extends StatelessWidget {
  final ValueListenable<bool> showNotifier;
  final Duration fadeDuration;
  final Duration scaleDuration;
  final double iconSize;

  const HeartAnimation({
    super.key,
    required this.showNotifier,
    this.fadeDuration = const Duration(milliseconds: 220),
    this.scaleDuration = const Duration(milliseconds: 420),
    this.iconSize = 48,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: showNotifier,
      builder: (context, isVisible, _) {
        return Positioned.fill(
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: isVisible ? 1.0 : 0.0,
              duration: fadeDuration,
              curve: Curves.easeOut,
              child: Center(
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(
                    begin: isVisible ? 0.85 : 0.7,
                    end: isVisible ? 1.05 : 0.85,
                  ),
                  duration: scaleDuration,
                  curve: Curves.easeOutBack,
                  builder: (context, scale, child) {
                    return Transform.scale(
                      scale: scale,
                      child: child,
                    );
                  },
                  child: _HeartBadge(iconSize: iconSize),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _HeartBadge extends StatelessWidget {
  final double iconSize;

  const _HeartBadge({required this.iconSize});

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFFE81B5C);

    return Stack(
      alignment: Alignment.center,
      children: [
        // Outer glow effect
        Container(
          width: iconSize * 2.5,
          height: iconSize * 2.5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              colors: [
                Color(0x33FF8FB1),
                Color(0x11FF4D6D),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(alpha: 0.35),
                blurRadius: 35,
                spreadRadius: 6,
              ),
            ],
          ),
        ),
        // Main heart badge with glass effect
        Container(
          padding: EdgeInsets.all(iconSize * 0.45),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.15),
                Colors.white.withValues(alpha: 0.05),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.25),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                spreadRadius: 2,
              ),
            ],
          ),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFFFF6FB1),
                  accent,
                ],
              ),
            ),
            child: Padding(
              padding: EdgeInsets.all(iconSize * 0.2),
              child: ShaderMask(
                shaderCallback: (rect) => const LinearGradient(
                  colors: [
                    Colors.white,
                    Color(0xFFFFDADA),
                  ],
                ).createShader(rect),
                blendMode: BlendMode.srcIn,
                child: Icon(
                  Icons.favorite_rounded,
                  size: iconSize,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
