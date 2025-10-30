import 'package:flutter/material.dart';
import 'package:vayu/model/video_model.dart';

class EarningsLabel extends StatelessWidget {
  final VideoModel video;
  const EarningsLabel({super.key, required this.video});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.green.withOpacity(0.6),
          width: 1,
        ),
      ),
      child: Text(
        '₹${video.earnings.toStringAsFixed(2)}',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
