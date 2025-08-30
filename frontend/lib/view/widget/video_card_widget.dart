import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/view/widget/video_info_widget.dart';
import 'package:snehayog/view/widget/action_buttons_widget.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/controller/google_sign_in_controller.dart';

class VideoCardWidget extends StatelessWidget {
  final VideoModel video;
  final VideoPlayerController? controller;
  final bool isActive;

  const VideoCardWidget({
    Key? key,
    required this.video,
    required this.controller,
    required this.isActive,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // **NEW: Simple video player without deleted widget**
        _buildVideoPlayer(),
        Positioned(
          left: 12,
          bottom: 12,
          right: 80,
          child: VideoInfoWidget(video: video),
        ),
        Positioned(
          right: 12,
          bottom: 12,
          child: ActionButtonsWidget(
            video: video,
            index: 0, // index is not used in this stateless version
            isLiked: Provider.of<GoogleSignInController>(context, listen: false)
                        .userData?['id'] !=
                    null &&
                video.likedBy.contains(
                  Provider.of<GoogleSignInController>(context, listen: false)
                      .userData?['id'],
                ),
            onLike: () {}, // To be handled in parent if needed
            onComment: () {},
            onShare: () {},
          ),
        ),
      ],
    );
  }

  /// **NEW: Simple video player implementation**
  Widget _buildVideoPlayer() {
    if (controller == null || !controller!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: Center(
          child: Icon(
            Icons.video_library,
            size: 64,
            color: Colors.grey[400],
          ),
        ),
      );
    }

    return VideoPlayer(controller!);
  }
}
