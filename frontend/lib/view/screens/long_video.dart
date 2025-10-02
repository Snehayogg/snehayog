import 'package:flutter/material.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/view/screens/video_feed_advanced.dart';

class VayuScreen extends StatefulWidget {
  final int? initialIndex;
  final List<VideoModel>? initialVideos;
  final String? initialVideoId;

  const VayuScreen({
    Key? key,
    this.initialIndex,
    this.initialVideos,
    this.initialVideoId,
  }) : super(key: key);

  @override
  State<VayuScreen> createState() => _VayuScreenState();
}

class _VayuScreenState extends State<VayuScreen> {
  final GlobalKey _videoFeedKey = GlobalKey();

  /// **PUBLIC: Refresh video list after upload**
  Future<void> refreshVideos() async {
    print('🔄 VayuScreen: refreshVideos() called');
    final videoFeedState = _videoFeedKey.currentState;
    if (videoFeedState != null) {
      // Cast to dynamic to access the refreshVideos method
      await (videoFeedState as dynamic).refreshVideos();
      print('✅ VayuScreen: Video refresh completed');
    } else {
      print('❌ VayuScreen: VideoFeedAdvanced state not found');
    }
  }

  @override
  Widget build(BuildContext context) {
    return VideoFeedAdvanced(
      key: _videoFeedKey,
      initialIndex: widget.initialIndex,
      initialVideos: widget.initialVideos,
      initialVideoId: widget.initialVideoId,
      videoType: 'sneha',
    );
  }
}
