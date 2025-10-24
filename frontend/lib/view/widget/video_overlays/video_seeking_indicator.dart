import 'package:flutter/material.dart';
import 'package:vayu/core/constants/video_constants.dart';

class VideoSeekingIndicator extends StatelessWidget {
  final bool isVisible;

  const VideoSeekingIndicator({
    Key? key,
    required this.isVisible,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(VideoConstants.lightOverlayOpacity),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(VideoConstants.smallOverlayPadding),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(VideoConstants.overlayOpacity),
              borderRadius: BorderRadius.circular(VideoConstants.borderRadius),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: VideoConstants.smallIconSize,
                  height: VideoConstants.smallIconSize,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Text(
                  'Seeking...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: VideoConstants.mediumTextSize,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
