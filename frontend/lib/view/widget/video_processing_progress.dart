import 'package:flutter/material.dart';

/// Circular progress indicator for video processing
class VideoProcessingProgress extends StatelessWidget {
  final double progress;
  final String? statusText;
  final bool showPlayButton;
  final double size;
  final Color? progressColor;
  final Color? backgroundColor;

  const VideoProcessingProgress({
    Key? key,
    required this.progress,
    this.statusText,
    this.showPlayButton = true,
    this.size = 80.0,
    this.progressColor,
    this.backgroundColor,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final effectiveProgressColor = progressColor ?? Colors.green;
    final effectiveBackgroundColor = backgroundColor ?? Colors.grey.shade800;

    return Container(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Background circle
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: effectiveBackgroundColor,
            ),
          ),

          // Progress circle
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: progress / 100,
              strokeWidth: 4.0,
              valueColor: AlwaysStoppedAnimation<Color>(effectiveProgressColor),
              backgroundColor: Colors.grey.shade600,
            ),
          ),

          // Center content
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Play button or progress text
              if (showPlayButton)
                Icon(
                  Icons.play_arrow,
                  color: Colors.white,
                  size: size * 0.3,
                )
              else
                Text(
                  '${progress.toInt()}%',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: size * 0.15,
                    fontWeight: FontWeight.bold,
                  ),
                ),

              // Status text below
              if (statusText != null && statusText!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Text(
                    statusText!,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: size * 0.1,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Processing status overlay widget
class VideoProcessingOverlay extends StatelessWidget {
  final double progress;
  final String processingStatus;
  final String? errorMessage;
  final VoidCallback? onRetry;
  final VoidCallback? onCancel;

  const VideoProcessingOverlay({
    Key? key,
    required this.progress,
    required this.processingStatus,
    this.errorMessage,
    this.onRetry,
    this.onCancel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.8),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress indicator
            VideoProcessingProgress(
              progress: progress,
              statusText: _getStatusText(),
              showPlayButton: processingStatus == 'completed',
              size: 120.0,
              progressColor: _getProgressColor(),
            ),

            const SizedBox(height: 24),

            // Status message
            Text(
              _getStatusMessage(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),

            // Error message if any
            if (errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                errorMessage!,
                style: const TextStyle(
                  color: Colors.red,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],

            // Action buttons
            if (processingStatus == 'failed') ...[
              const SizedBox(height: 24),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onRetry != null)
                    ElevatedButton(
                      onPressed: onRetry,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Retry'),
                    ),
                  if (onCancel != null) ...[
                    const SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: onCancel,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Cancel'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getStatusText() {
    switch (processingStatus) {
      case 'pending':
        return 'Preparing...';
      case 'processing':
        return 'Processing...';
      case 'completed':
        return 'Ready!';
      case 'failed':
        return 'Failed';
      default:
        return 'Unknown';
    }
  }

  String _getStatusMessage() {
    switch (processingStatus) {
      case 'pending':
        return 'Your video is being prepared for processing';
      case 'processing':
        return 'Video is being processed. Please wait...';
      case 'completed':
        return 'Video processing completed successfully!';
      case 'failed':
        return 'Video processing failed. Please try again.';
      default:
        return 'Processing status unknown';
    }
  }

  Color _getProgressColor() {
    switch (processingStatus) {
      case 'pending':
        return Colors.orange;
      case 'processing':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
