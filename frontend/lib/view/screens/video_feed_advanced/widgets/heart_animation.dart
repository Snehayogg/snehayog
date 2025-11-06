import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class HeartAnimation extends StatelessWidget {
  final ValueListenable<bool> showNotifier;

  const HeartAnimation({
    Key? key,
    required this.showNotifier,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: showNotifier,
      builder: (context, showAnimation, _) {
        if (!showAnimation) return const SizedBox.shrink();
        return Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: AnimatedOpacity(
                opacity: showAnimation ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: AnimatedScale(
                  scale: showAnimation ? 1.2 : 0.8,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child:
                        const Icon(Icons.favorite, color: Colors.red, size: 48),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
