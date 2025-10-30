import 'package:flutter/material.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/widgets/indicators/earnings_label.dart';

class VideoOverlay extends StatelessWidget {
  final VideoModel video;
  final bool showPlayOverlay;
  final bool showBuffering;
  final VoidCallback onReport;
  final VoidCallback onProfileTap;
  final Widget actionButtons;
  final Widget? banner;

  const VideoOverlay({
    super.key,
    required this.video,
    required this.showPlayOverlay,
    required this.showBuffering,
    required this.onReport,
    required this.onProfileTap,
    required this.actionButtons,
    this.banner,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (banner != null) banner!,
        Positioned(
          top: 62,
          right: 8,
          child: EarningsLabel(video: video),
        ),
        if (showPlayOverlay)
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Container(
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
                ),
              ),
            ),
          ),
        if (showBuffering)
          const Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          ),
        Positioned(
          right: 16,
          top: MediaQuery.of(context).size.height * 0.5 - 20,
          child: GestureDetector(
            onTap: onReport,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Report',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios, color: Colors.white, size: 12),
                ],
              ),
            ),
          ),
        ),
        actionButtons,
      ],
    );
  }
}
