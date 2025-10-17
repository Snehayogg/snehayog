import 'package:flutter/material.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/video_processing_service.dart';
import 'package:snehayog/view/widget/video_processing_progress.dart';

/// Video item widget that shows processing progress overlay
class VideoItemWithProgress extends StatefulWidget {
  final VideoModel video;
  final Widget child; // The actual video content widget
  final bool showProgressOverlay;

  const VideoItemWithProgress({
    Key? key,
    required this.video,
    required this.child,
    this.showProgressOverlay = true,
  }) : super(key: key);

  @override
  State<VideoItemWithProgress> createState() => _VideoItemWithProgressState();
}

class _VideoItemWithProgressState extends State<VideoItemWithProgress> {
  final VideoProcessingService _processingService =
      VideoProcessingService.instance;
  VideoProcessingStatus? _currentStatus;
  bool _isPolling = false;

  @override
  void initState() {
    super.initState();
    _startProgressPolling();
  }

  @override
  void dispose() {
    _stopProgressPolling();
    super.dispose();
  }

  void _startProgressPolling() {
    if (!widget.showProgressOverlay || widget.video.isProcessingComplete) {
      return;
    }

    _isPolling = true;
    _processingService.pollProgress(widget.video.id).listen(
      (status) {
        if (mounted) {
          setState(() {
            _currentStatus = status;
          });
        }
      },
      onError: (error) {
        print('❌ VideoItemWithProgress: Polling error: $error');
      },
      onDone: () {
        if (mounted) {
          setState(() {
            _isPolling = false;
          });
        }
      },
    );
  }

  void _stopProgressPolling() {
    if (_isPolling) {
      _processingService.stopPolling(widget.video.id);
      _isPolling = false;
    }
  }

  void _retryProcessing() {
    // TODO: Implement retry functionality
    print('🔄 Retrying video processing for: ${widget.video.id}');
  }

  void _cancelProcessing() {
    // TODO: Implement cancel functionality
    print('❌ Cancelling video processing for: ${widget.video.id}');
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Main video content
        widget.child,

        // Processing progress overlay
        if (widget.showProgressOverlay && _shouldShowOverlay())
          VideoProcessingOverlay(
            progress: _getCurrentProgress(),
            processingStatus: _getCurrentStatus(),
            errorMessage: _currentStatus?.processingError,
            onRetry: _retryProcessing,
            onCancel: _cancelProcessing,
          ),
      ],
    );
  }

  bool _shouldShowOverlay() {
    // Show overlay if video is processing, pending, or failed
    return widget.video.isProcessing ||
        widget.video.isPending ||
        widget.video.isFailed ||
        (_currentStatus != null && !_currentStatus!.isCompleted);
  }

  double _getCurrentProgress() {
    if (_currentStatus != null) {
      return _currentStatus!.processingProgress.toDouble();
    }
    return widget.video.processingProgress?.toDouble() ?? 0.0;
  }

  String _getCurrentStatus() {
    if (_currentStatus != null) {
      return _currentStatus!.processingStatus;
    }
    return widget.video.processingStatus ?? 'unknown';
  }
}

/// Simple video processing indicator for list items
class VideoProcessingIndicator extends StatelessWidget {
  final VideoModel video;
  final double size;

  const VideoProcessingIndicator({
    Key? key,
    required this.video,
    this.size = 40.0,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (video.isProcessingComplete) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 8,
      right: 8,
      child: VideoProcessingProgress(
        progress: video.processingProgress?.toDouble() ?? 0.0,
        size: size,
        showPlayButton: false,
        statusText: _getStatusText(),
        progressColor: _getProgressColor(),
      ),
    );
  }

  String _getStatusText() {
    if (video.isProcessing) return 'Processing';
    if (video.isPending) return 'Pending';
    if (video.isFailed) return 'Failed';
    return 'Unknown';
  }

  Color _getProgressColor() {
    if (video.isProcessing) return Colors.blue;
    if (video.isPending) return Colors.orange;
    if (video.isFailed) return Colors.red;
    return Colors.grey;
  }
}
