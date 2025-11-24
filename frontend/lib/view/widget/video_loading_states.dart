import 'package:flutter/material.dart';
import 'package:vayu/core/enums/video_state.dart';

class VideoLoadingStates extends StatelessWidget {
  final VideoLoadState loadState;
  final String? errorMessage;
  final VoidCallback onRefresh;
  final VoidCallback onTestApi;
  final VoidCallback? onStartOver;

  const VideoLoadingStates({
    Key? key,
    required this.loadState,
    this.errorMessage,
    required this.onRefresh,
    required this.onTestApi,
    this.onStartOver,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    switch (loadState) {
      case VideoLoadState.loading:
        return const _LoadingState();
      case VideoLoadState.error:
        return _ErrorState(
          errorMessage: errorMessage,
          onRefresh: onRefresh,
          onTestApi: onTestApi,
        );
      case VideoLoadState.noMore:
        return _NoMoreState(
          onRefresh: onRefresh,
          onStartOver: onStartOver,
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// Lightweight loading state widget
class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: Colors.white),
    );
  }
}

// Lightweight error state widget
class _ErrorState extends StatelessWidget {
  final String? errorMessage;
  final VoidCallback onRefresh;
  final VoidCallback onTestApi;

  const _ErrorState({
    required this.errorMessage,
    required this.onRefresh,
    required this.onTestApi,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            size: 64,
            color: Colors.red,
          ),
          const SizedBox(height: 16),
          const Text(
            'Failed to load videos',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              errorMessage!,
              style: const TextStyle(
                color: Colors.white54,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRefresh,
            child: const Text('Retry'),
          ),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: onTestApi,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Test API Connection'),
          ),
        ],
      ),
    );
  }
}

// Lightweight no more state widget
class _NoMoreState extends StatelessWidget {
  final VoidCallback onRefresh;
  final VoidCallback? onStartOver;

  const _NoMoreState({
    required this.onRefresh,
    this.onStartOver,
  });

  @override
  Widget build(BuildContext context) {
    // Automatically restart when reaching the end (no buttons shown)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (onStartOver != null) {
        onStartOver!();
      } else {
        onRefresh();
      }
    });

    // Show loading indicator while restarting
    return const Center(
      child: CircularProgressIndicator(
        color: Colors.white,
      ),
    );
  }
}

class VideoEmptyState extends StatelessWidget {
  final VoidCallback onRefresh;
  final VoidCallback onTestApi;

  const VideoEmptyState({
    Key? key,
    required this.onRefresh,
    required this.onTestApi,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.video_library,
            size: 64,
            color: Colors.white54,
          ),
          const SizedBox(height: 16),
          const Text(
            "No videos found",
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Try refreshing or check if videos are available",
            style: TextStyle(
              color: Colors.white54,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onRefresh,
            child: const Text('Refresh'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onTestApi,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('Test API Connection'),
          ),
        ],
      ),
    );
  }
}
