import 'package:flutter/material.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/view/widget/video_card_widget.dart';

class VideoFeedWidget extends StatelessWidget {
  final List<VideoModel> videos;
  final Map<int, VideoPlayerController> controllers;
  final int activePage;
  final bool hasMore;
  final PageController pageController;
  final Function(int) onPageChanged;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const VideoFeedWidget({
    Key? key,
    required this.videos,
    required this.controllers,
    required this.activePage,
    required this.hasMore,
    required this.pageController,
    required this.onPageChanged,
    required this.isLoading,
    required this.onRefresh,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (videos.isEmpty) {
      return const Center(child: Text("No videos found."));
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: PageView.builder(
        controller: pageController,
        scrollDirection: Axis.vertical,
        itemCount: videos.length + (hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == videos.length) {
            return const Center(child: CircularProgressIndicator());
          }
          final video = videos[index];
          final controller = controllers[index];
          return VideoCardWidget(
            video: video,
            controller: controller,
            isActive: index == activePage,
          );
        },
        onPageChanged: onPageChanged,
      ),
    );
  }
}
