import 'package:flutter/material.dart';
import 'package:snehayog/core/constants/video_constants.dart';

class VideoLoadingWidget extends StatelessWidget {
  final bool isHLS;

  const VideoLoadingWidget({
    Key? key,
    required this.isHLS,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading video...',
              style: TextStyle(
                color:
                    Colors.white.withOpacity(VideoConstants.lightTextOpacity),
                fontSize: VideoConstants.largeTextSize,
              ),
            ),
            if (isHLS) ...[
              const SizedBox(height: 8),
              Text(
                'HLS Streaming',
                style: TextStyle(
                  color:
                      Colors.blue.withOpacity(VideoConstants.lightTextOpacity),
                  fontSize: VideoConstants.smallTextSize,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
