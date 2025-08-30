import 'package:flutter/material.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/core/constants/app_constants.dart';

class ActionButtonsWidget extends StatelessWidget {
  final VideoModel video;
  final int index;
  final bool isLiked;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;

  const ActionButtonsWidget({
    Key? key,
    required this.video,
    required this.index,
    required this.isLiked,
    required this.onLike,
    required this.onComment,
    required this.onShare,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              isLiked ? Icons.favorite : Icons.favorite_border,
              color: isLiked ? Colors.red : Colors.white,
              // **UPDATED to use constant**
              size: AppConstants.actionButtonSize,
            ),
            onPressed: onLike,
          ),
          Text('${video.likes}', style: const TextStyle(color: Colors.white)),
          // **REDUCED spacing from 20 to 12 for more compact look**
          const SizedBox(height: 12),
          IconButton(
            icon: const Icon(Icons.comment,
                color: Colors.white,
                // **UPDATED to use constant**
                size: AppConstants.actionButtonSize),
            onPressed: onComment,
          ),
          Text('${video.comments.length}',
              style: const TextStyle(color: Colors.white)),
          // **REDUCED spacing from 20 to 12 for more compact look**
          const SizedBox(height: 12),
          IconButton(
            icon: const Icon(Icons.share,
                color: Colors.white,
                // **UPDATED to use constant**
                size: AppConstants.actionButtonSize),
            onPressed: onShare,
          ),
          Text('${video.shares}', style: const TextStyle(color: Colors.white)),
        ],
      ),
    );
  }
}
