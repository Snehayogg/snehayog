import 'package:flutter/material.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/services/earnings_service.dart';

class EarningsLabel extends StatelessWidget {
  final VideoModel video;
  const EarningsLabel({super.key, required this.video});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<double>(
      future: EarningsService.calculateVideoRevenue(video.id),
      builder: (context, snapshot) {
        final value = snapshot.data ?? video.earnings;
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
            '₹${value.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      },
    );
  }
}
