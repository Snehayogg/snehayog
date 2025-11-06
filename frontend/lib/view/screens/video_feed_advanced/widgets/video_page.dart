import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/view/screens/video_feed_advanced/widgets/video_aspect_surface.dart';

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
              controller!.value.isInitialized &&
              showPlayer)
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
    return RepaintBoundary(
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: video.thumbnailUrl.isNotEmpty
            ? Center(
                child: CachedNetworkImage(
                  imageUrl: video.thumbnailUrl,
                  fit: BoxFit.contain,
                  placeholder: (context, url) => _buildFallbackThumbnail(),
                  errorWidget: (context, url, error) =>
                      _buildFallbackThumbnail(),
                  memCacheWidth: 854,
                  memCacheHeight: 480,
                ),
              )
            : _buildFallbackThumbnail(),
      ),
    );
  }

  Widget _buildFallbackThumbnail() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_circle_outline, size: 80, color: Colors.white54),
            SizedBox(height: 16),
            Text(
              'Tap to play video',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
