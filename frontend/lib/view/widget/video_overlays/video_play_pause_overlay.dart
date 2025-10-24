import 'package:flutter/material.dart';
import 'package:vayu/core/constants/video_constants.dart';

class VideoPlayPauseOverlay extends StatelessWidget {
  final bool isVisible;
  final bool isPlaying;

  const VideoPlayPauseOverlay({
    Key? key,
    required this.isVisible,
    required this.isPlaying,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: isVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      child: Container(
        color: Colors.black.withOpacity(VideoConstants.lightOverlayOpacity),
        child: Center(
          child: Container(
            padding: const EdgeInsets.all(VideoConstants.overlayPadding),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(VideoConstants.overlayOpacity),
              borderRadius:
                  BorderRadius.circular(VideoConstants.largeBorderRadius),
              boxShadow: [
                BoxShadow(
                  color:
                      Colors.black.withOpacity(VideoConstants.overlayOpacity),
                  blurRadius: VideoConstants.lightShadowBlurRadius,
                  offset: const Offset(0, VideoConstants.lightShadowOffset),
                ),
              ],
            ),
            child: Icon(
              isPlaying ? Icons.pause : Icons.play_arrow,
              size: VideoConstants.largePlayButtonSize,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
