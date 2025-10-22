import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/controller/google_sign_in_controller.dart';
import 'package:snehayog/core/constants/app_constants.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/services/comments/video_comments_data_source.dart';
import 'package:snehayog/view/widget/comments_sheet_widget.dart';
import 'package:snehayog/view/widget/custom_share_widget.dart';

class VideoActionsWidget extends StatelessWidget {
  final VideoModel video;
  final int index;
  final Function(int) onLike;
  final VideoService videoService;
  final int currentHorizontalIndex;
  final Function(int) onHorizontalIndexChanged;

  const VideoActionsWidget({
    Key? key,
    required this.video,
    required this.index,
    required this.onLike,
    required this.videoService,
    required this.currentHorizontalIndex,
    required this.onHorizontalIndexChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Consumer<GoogleSignInController>(
      builder: (context, controller, child) {
        final userData = controller.userData;
        final userId = userData?['id'];
        final isLiked = userId != null && video.likedBy.contains(userId);

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Like button
            _ActionButton(
              icon: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border,
                color: isLiked ? Colors.red : Colors.white,
                size: AppConstants.actionButtonSize,
              ),
              onPressed: () => onLike(index),
              label: '${video.likes}',
            ),

            // **REDUCED spacing from 20 to 12 for more compact look**
            const SizedBox(height: 12),

            // Comment button
            _ActionButton(
              icon: const Icon(
                Icons.comment,
                color: Colors.white,
                size: AppConstants.actionButtonSize,
              ),
              onPressed: () => _showComments(context),
              label: '${video.comments.length}',
            ),

            // **REDUCED spacing from 20 to 12 for more compact look**
            const SizedBox(height: 12),

            // Share button
            _ActionButton(
              icon: const Icon(
                Icons.share,
                color: Colors.white,
                size: AppConstants.actionButtonSize,
              ),
              onPressed: () => _showCustomShareSheet(context),
              label: '${video.shares}',
            ),

            // **REDUCED spacing from 20 to 12 for more compact look**
            const SizedBox(height: 12),

            // Ad toggle button
            _AdToggleButton(
              currentHorizontalIndex: currentHorizontalIndex,
              onHorizontalIndexChanged: onHorizontalIndexChanged,
            ),
          ],
        );
      },
    );
  }

  // Move these methods back to VideoActionsWidget
  void _showComments(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => CommentsSheetWidget(
        video: video,
        videoService: videoService,
        dataSource: VideoCommentsDataSource(
          videoId: video.id,
          videoService: videoService,
        ),
        onCommentsUpdated: (List<Comment> updatedComments) {
          // Update comments in the video model
          video.comments = updatedComments;
        },
      ),
    );
  }

  void _showCustomShareSheet(BuildContext context) async {
    try {
      // Track share
      try {
        await videoService.incrementShares(video.id);
        video.shares++;
      } catch (e) {
        print('Failed to track share: $e');
      }

      // Show custom share bottom sheet
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => CustomShareWidget(video: video),
      );
    } catch (e) {
      print('Failed to show share sheet: $e');
    }
  }
}

// Simplified _ActionButton widget (no methods needed)
class _ActionButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback onPressed;
  final String label;

  const _ActionButton({
    required this.icon,
    required this.onPressed,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        IconButton(
          icon: icon,
          onPressed: onPressed,
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white),
        ),
      ],
    );
  }
}

// Ad toggle button widget
class _AdToggleButton extends StatelessWidget {
  final int currentHorizontalIndex;
  final Function(int) onHorizontalIndexChanged;

  const _AdToggleButton({
    required this.currentHorizontalIndex,
    required this.onHorizontalIndexChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isOnAd = currentHorizontalIndex > 0;

    return _ActionButton(
      icon: Icon(
        isOnAd ? Icons.arrow_back : Icons.arrow_forward,
        color: Colors.white,
        size: AppConstants.actionButtonSize,
      ),
      onPressed: () {
        if (isOnAd) {
          // Return to video
          onHorizontalIndexChanged(0);
        } else {
          // Go to ad
          onHorizontalIndexChanged(1);
        }
      },
      label: isOnAd ? 'Back' : 'Product',
    );
  }
}
