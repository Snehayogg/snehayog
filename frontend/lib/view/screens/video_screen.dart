import 'package:flutter/material.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/view/screens/video_feed_advanced.dart';

class VideoScreen extends StatelessWidget {
  final int? initialIndex;
  final List<VideoModel>? initialVideos;
  final String? initialVideoId;

  const VideoScreen({
    Key? key,
    this.initialIndex,
    this.initialVideos,
    this.initialVideoId,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return VideoFeedAdvanced(
      initialIndex: initialIndex,
      initialVideos: initialVideos,
      initialVideoId: initialVideoId,
    );
  }
}
