import 'package:flutter/material.dart';

class PlayOverlayIcon extends StatelessWidget {
  const PlayOverlayIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: const Icon(
        Icons.play_arrow,
        color: Colors.white,
        size: 36,
      ),
    );
  }
}
