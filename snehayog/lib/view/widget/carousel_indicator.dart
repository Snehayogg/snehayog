import 'package:flutter/material.dart';

class CarouselIndicator extends StatelessWidget {
  final int currentIndex;
  final int itemCount;
  final double dotSize;
  final double spacing;
  final Color activeColor;
  final Color inactiveColor;

  const CarouselIndicator({
    super.key,
    required this.currentIndex,
    required this.itemCount,
    this.dotSize = 8.0,
    this.spacing = 8.0,
    this.activeColor = const Color(0xFF268BD2),
    this.inactiveColor = const Color(0xFF586E75),
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        itemCount,
        (index) => Container(
          width: dotSize,
          height: dotSize,
          margin: EdgeInsets.symmetric(horizontal: spacing / 2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: index == currentIndex ? activeColor : inactiveColor,
            boxShadow: [
              if (index == currentIndex)
                BoxShadow(
                  color: activeColor.withOpacity(0.5),
                  blurRadius: 8,
                  spreadRadius: 2,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
