import 'package:flutter/material.dart';
import '../../model/video_model.dart';
import '../../services/video_service.dart';

/// Extended video model with processing status
class VideoWithStatus extends VideoModel {
  final String processingStatus;
  final String message;
  final int processingProgress;
  final bool canPlay;

  VideoWithStatus({
    required super.id,
    required super.videoName,
    required super.videoUrl,
    required super.thumbnailUrl,
    required super.likes,
    required super.views,
    required super.shares,
    super.description,
    required super.uploader,
    required super.uploadedAt,
    required super.likedBy,
    required super.videoType,
    required super.aspectRatio,
    required super.duration,
    required super.comments,
    super.link,
    super.hlsMasterPlaylistUrl,
    super.hlsPlaylistUrl,
    super.hlsVariants,
    super.isHLSEncoded,
    super.lowQualityUrl,
    required this.processingStatus,
    required this.message,
    this.processingProgress = 0,
    this.canPlay = false,
  });

  factory VideoWithStatus.fromVideoModel(
    VideoModel video, {
    String processingStatus = 'completed',
    String message = 'Video is ready',
    int processingProgress = 100,
    bool canPlay = true,
  }) {
    // Check for any playable URL (MP4 or HLS) using VideoService helper
    final hasPlayableUrl = VideoService.hasPlayableUrl(video);

    // Determine appropriate message based on available URLs
    String statusMessage = message;
    if (hasPlayableUrl) {
      if (VideoService.hasHlsStreaming(video)) {
        statusMessage = 'HLS streaming ready';
      } else if (video.videoUrl.isNotEmpty) {
        statusMessage = 'Direct video ready';
      }
    } else {
      statusMessage = 'Video processing...';
    }

    return VideoWithStatus(
      id: video.id,
      videoName: video.videoName,
      videoUrl: video.videoUrl,
      thumbnailUrl: video.thumbnailUrl,
      likes: video.likes,
      views: video.views,
      shares: video.shares,
      description: video.description,
      uploader: video.uploader,
      uploadedAt: video.uploadedAt,
      likedBy: video.likedBy,
      videoType: video.videoType,
      aspectRatio: video.aspectRatio,
      duration: video.duration,
      comments: video.comments,
      link: video.link,
      hlsMasterPlaylistUrl: video.hlsMasterPlaylistUrl,
      hlsPlaylistUrl: video.hlsPlaylistUrl,
      hlsVariants: video.hlsVariants,
      isHLSEncoded: video.isHLSEncoded,
      lowQualityUrl: video.lowQualityUrl,
      processingStatus: processingStatus,
      message: statusMessage,
      processingProgress: processingProgress,
      canPlay: canPlay && hasPlayableUrl,
    );
  }

  /// Get the best playable URL for this video
  String getPlayableUrl() {
    return VideoService.getPlayableUrl(this);
  }

  /// Check if video has HLS streaming
  bool get hasHlsStreaming => VideoService.hasHlsStreaming(this);
}

/// Widget for displaying video processing status
/// Shows progress, status messages, and action buttons
class VideoStatusWidget extends StatelessWidget {
  final VideoWithStatus video;
  final VoidCallback? onRetry;
  final VoidCallback? onPlay;

  const VideoStatusWidget({
    super.key,
    required this.video,
    this.onRetry,
    this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _getStatusColor().withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _getStatusColor().withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status Header
          Row(
            children: [
              Icon(
                _getStatusIcon(),
                color: _getStatusColor(),
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  video.videoName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _getStatusText(),
                style: TextStyle(
                  fontSize: 12,
                  color: _getStatusColor(),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Status Message
          Text(
            video.message,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),

          // Progress Bar
          if (video.processingStatus == 'processing')
            Column(
              children: [
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value: video.processingProgress / 100,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(_getStatusColor()),
                ),
                const SizedBox(height: 8),
                Text(
                  '${video.processingProgress}% complete',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),

          // Action Buttons
          if (video.canPlay && onPlay != null)
            _buildActionButton(
              'Play Video',
              Icons.play_arrow,
              Colors.green,
              onPlay!,
            )
          else if (video.processingStatus == 'failed' && onRetry != null)
            _buildActionButton(
              'Retry Upload',
              Icons.refresh,
              Colors.orange,
              onRetry!,
            )
          else if (video.processingStatus == 'processing')
            _buildProcessingIndicator(),

          // Video Info
          if (video.canPlay) ...[
            const SizedBox(height: 12),
            _buildVideoInfo(),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String text,
    IconData icon,
    Color color,
    VoidCallback onPressed,
  ) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(text),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _buildProcessingIndicator() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Processing video... This may take a few minutes',
            style: TextStyle(
              fontSize: 12,
              color: Colors.blue[700],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Text(
                'Video Details',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Duration: ${_formatDuration(video.duration.inSeconds)}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
              Text(
                'Aspect: ${video.aspectRatio.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Likes: ${video.likes}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
              Text(
                'Views: ${video.views}',
                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getStatusColor() {
    switch (video.processingStatus) {
      case 'completed':
        return Colors.green;
      case 'failed':
        return Colors.red;
      case 'processing':
        return Colors.blue;
      case 'uploaded':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getStatusIcon() {
    if (video.canPlay) {
      return Icons.check_circle;
    }

    switch (video.processingStatus) {
      case 'completed':
        return Icons.check_circle;
      case 'failed':
        return Icons.error;
      case 'processing':
        return Icons.hourglass_empty;
      case 'uploaded':
        return Icons.upload;
      default:
        return Icons.help_outline;
    }
  }

  String _getStatusText() {
    if (video.canPlay) {
      return 'READY';
    }

    switch (video.processingStatus) {
      case 'completed':
        return 'COMPLETED';
      case 'failed':
        return 'FAILED';
      case 'processing':
        return 'PROCESSING';
      case 'uploaded':
        return 'UPLOADED';
      default:
        return 'UNKNOWN';
    }
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}

/// Compact video status widget for lists
class CompactVideoStatusWidget extends StatelessWidget {
  final VideoWithStatus video;
  final VoidCallback? onTap;

  const CompactVideoStatusWidget({
    super.key,
    required this.video,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: video.canPlay ? onTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: video.canPlay ? Colors.green[50] : Colors.grey[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: video.canPlay ? Colors.green[200]! : Colors.grey[200]!,
          ),
        ),
        child: Row(
          children: [
            // Thumbnail
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(6),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  video.thumbnailUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Icon(
                      Icons.video_file,
                      color: Colors.grey[600],
                      size: 20,
                    );
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Video Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.videoName,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    video.message,
                    style: TextStyle(
                      fontSize: 12,
                      color: video.canPlay
                          ? Colors.green[600]
                          : Colors.orange[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (video.processingStatus == 'processing')
                    LinearProgressIndicator(
                      value: video.processingProgress / 100,
                      backgroundColor: Colors.grey[300],
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.blue[600]!),
                    ),
                ],
              ),
            ),

            // Status Icon
            Icon(
              video.canPlay
                  ? Icons.play_circle_filled
                  : video.processingStatus == 'failed'
                      ? Icons.error
                      : Icons.hourglass_empty,
              color: video.canPlay
                  ? Colors.green[600]
                  : video.processingStatus == 'failed'
                      ? Colors.red[600]
                      : Colors.blue[600],
              size: 24,
            ),
          ],
        ),
      ),
    );
  }
}
