import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:vayu/features/video/video_model.dart';
import 'package:vayu/features/video/presentation/screens/video_feed_advanced/widgets/video_aspect_surface.dart';

class VideoPage extends StatelessWidget {
  final VideoModel video;
  final VideoPlayerController? controller;
  final bool isActive;
  final int index;
  final Widget overlay;
  final Widget? buffering;
  final Widget? progressBar;
  final bool showPlayer;

  const VideoPage({
    Key? key,
    required this.video,
    required this.controller,
    required this.isActive,
    required this.index,
    required this.overlay,
    this.buffering,
    this.progressBar,
    this.showPlayer = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(child: _buildVideoThumbnail(video)),
          if (controller != null &&
              showPlayer &&
              (() {
                try {
                  return controller!.value.isInitialized;
                } catch (_) {
                  return false;
                }
              }()))
            Positioned.fill(
              child: VideoAspectSurface(
                controller: controller!,
                modelAspectRatio: video.aspectRatio,
              ),
            ),
          if (buffering != null) Positioned.fill(child: buffering!),
          if (progressBar != null)
            Positioned(left: 0, right: 0, bottom: 0, child: progressBar!),
          overlay,
        ],
      ),
    );
  }

  Widget _buildVideoThumbnail(VideoModel video) {
    // TEMPORARY: Disabled thumbnail to test direct video loading
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
    );
  }
}
