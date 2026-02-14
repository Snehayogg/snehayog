import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/features/video/video_model.dart';
import 'package:vayu/features/auth/presentation/controllers/google_sign_in_controller.dart';
import 'package:vayu/shared/constants/app_constants.dart';
import 'package:vayu/features/video/data/services/video_service.dart';
import 'package:vayu/shared/widgets/custom_share_widget.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:vayu/shared/theme/app_theme.dart';

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
    return RepaintBoundary(child: Consumer<GoogleSignInController>(
      builder: (context, controller, child) {
        final isLiked = video.isLiked;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Like button
            _ActionButton(
              icon: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border,
                color: isLiked ? Colors.red : Colors.white,
              ),
              size: AppConstants.primaryActionButtonSize,
              containerSize: AppConstants.primaryActionButtonContainerSize,
              onPressed: () => onLike(index),
              label: '${video.likes}',
            ),

            // **REDUCED spacing from 20 to 12 for more compact look**
            const SizedBox(height: 12),

            // Share button
            _ActionButton(
              icon: const Icon(
                Icons.share,
                color: Colors.white,
              ),
              size: AppConstants.secondaryActionButtonSize,
              containerSize: AppConstants.secondaryActionButtonContainerSize,
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
    ));
  }

  // Move these methods back to VideoActionsWidget
  void _showCustomShareSheet(BuildContext context) async {
    try {
      // Track share
      try {
        await videoService.incrementShares(video.id);
        video.shares++;
      } catch (e) {
        AppLogger.log('Failed to track share: $e');
      }

      // Show custom share bottom sheet
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => CustomShareWidget(video: video),
      );
    } catch (e) {
      AppLogger.log('Failed to show share sheet: $e');
    }
  }
}

class _ActionButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback onPressed;
  final String label;
  final double size;
  final double containerSize;

  const _ActionButton({
    required this.icon,
    required this.onPressed,
    required this.label,
    required this.size,
    required this.containerSize,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: containerSize,
          height: containerSize,
          decoration: BoxDecoration(
            color: AppTheme.overlayMedium,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Center(
            child: IconButton(
              icon: IconTheme(
                data: IconThemeData(
                  size: size,
                  shadows: const [
                    Shadow(
                      color: Colors.black45,
                      blurRadius: 4.0,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: icon,
              ),
              onPressed: onPressed,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: AppTheme.textInverse,
            fontWeight: FontWeight.w600,
            shadows: [
              const Shadow(
                color: Colors.black45,
                blurRadius: 2.0,
                offset: Offset(0, 1),
              ),
            ],
          ),
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
      ),
      size: AppConstants.secondaryActionButtonSize,
      containerSize: AppConstants.secondaryActionButtonContainerSize,
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
