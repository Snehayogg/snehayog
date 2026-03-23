import 'package:flutter/material.dart';
import 'package:vayu/shared/constants/video_constants.dart';
import 'package:vayu/shared/widgets/app_button.dart';

class VideoErrorWidget extends StatelessWidget {
  final String errorMessage;
  final VoidCallback onRetry;

  const VideoErrorWidget({
    Key? key,
    required this.errorMessage,
    required this.onRetry,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: VideoConstants.mediumIconSize,
              color: Colors.red.withValues(alpha: VideoConstants.lightTextOpacity),
            ),
            const SizedBox(height: 16),
            const Text(
              'Playback Error',
              style: TextStyle(
                color: Colors.white,
                fontSize: VideoConstants.titleTextSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                errorMessage,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: VideoConstants.lightTextOpacity),
                  fontSize: VideoConstants.mediumTextSize,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 16),
            AppButton(
              onPressed: onRetry,
              label: 'Retry',
              variant: AppButtonVariant.primary,
            ),
          ],
        ),
      ),
    );
  }
}
