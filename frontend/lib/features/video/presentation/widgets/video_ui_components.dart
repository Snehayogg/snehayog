import 'package:flutter/material.dart';
import 'package:vayu/shared/widgets/app_button.dart';

/// Loading indicator widget for better performance
class LoadingIndicatorWidget extends StatelessWidget {
  const LoadingIndicatorWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            SizedBox(height: 16),
            Text(
              'Loading more videos...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Empty state widget when no videos are available
class EmptyVideoStateWidget extends StatelessWidget {
  final VoidCallback onRefresh;
  final VoidCallback onTestApi;
  final VoidCallback onTestVideoLink;
  final VoidCallback onClearCache;
  final VoidCallback onGetCacheInfo;

  const EmptyVideoStateWidget({
    Key? key,
    required this.onRefresh,
    required this.onTestApi,
    required this.onTestVideoLink,
    required this.onClearCache,
    required this.onGetCacheInfo,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.video_library, size: 64, color: Colors.white54),
          const SizedBox(height: 16),
          const Text(
            "No videos found",
            style: TextStyle(color: Colors.white, fontSize: 18),
          ),
          const SizedBox(height: 8),
          const Text(
            "Try refreshing or check if videos are available",
            style: TextStyle(color: Colors.white54, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          AppButton(
            onPressed: onRefresh,
            label: 'Refresh',
            variant: AppButtonVariant.primary,
          ),
          const SizedBox(height: 16),
          AppButton(
            onPressed: onTestApi,
            label: 'Test API Connection',
            variant: AppButtonVariant.secondary,
          ),
          const SizedBox(height: 16),
          AppButton(
            onPressed: onTestVideoLink,
            label: 'Test Video Links',
            variant: AppButtonVariant.secondary,
          ),
          const SizedBox(height: 16),
          // Add cache management buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppButton(
                onPressed: onClearCache,
                label: 'Clear Cache',
                variant: AppButtonVariant.danger,
              ),
              const SizedBox(width: 16),
              AppButton(
                onPressed: onGetCacheInfo,
                label: 'Cache Info',
                variant: AppButtonVariant.secondary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
