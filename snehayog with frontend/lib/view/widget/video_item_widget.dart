import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/view/widget/video_player_widget.dart';
import 'package:snehayog/view/widget/video_info_widget.dart';
import 'package:snehayog/view/widget/video_actions_widget.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:url_launcher/url_launcher.dart';

class VideoItemWidget extends StatelessWidget {
  final VideoModel video;
  final int index;
  final VideoPlayerController? controller;
  final bool isActive;
  final Function(int) onLike;
  final VideoService videoService;

  const VideoItemWidget({
    Key? key,
    required this.video,
    required this.index,
    required this.controller,
    required this.isActive,
    required this.onLike,
    required this.videoService,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Video player widget
        RepaintBoundary(
          child: VideoPlayerWidget(
            key: ValueKey(video.id),
            controller: controller,
            video: video,
            play: isActive,
          ),
        ),

        // Video information overlay (bottom left)
         Positioned(
          left: 12,
          bottom: 12,
          right: 80,
          child: VideoInfoWidget(video: video,),
        ),

        // Action buttons overlay (bottom right)
        Positioned(
          right: 12,
          bottom: 12,
          child: VideoActionsWidget(
            video: video,
            index: index,
            onLike: onLike,
            videoService: videoService,
          ),
        ),

        // External link button (if video has a link)
        if (video.link != null && video.link!.isNotEmpty)
          const Positioned(
            left: 15,
            right: 15,
            bottom: 120, // Position above action buttons
            child: _ExternalLinkButton(),
          ),
      ],
    );
  }
}

// Lightweight external link button widget
class _ExternalLinkButton extends StatelessWidget {
  const _ExternalLinkButton();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          // Get video from context
          final video =
              context.findAncestorWidgetOfExactType<VideoItemWidget>()?.video;
          if (video?.link != null) {
            final url = Uri.tryParse(video!.link!);
            if (url != null && await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          }
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: const LinearGradient(
              colors: [
                Color(0x2EFFFFFF),
                Color(0xEB2196F3), 
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.open_in_new, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text(
                'Visit Now',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                  fontSize: 15,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
