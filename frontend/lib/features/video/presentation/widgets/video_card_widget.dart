import 'package:flutter/material.dart';
import '../../domain/entities/video_entity.dart';

/// Widget for displaying a video card in the feed
/// This follows the const constructor pattern for better performance
class VideoCardWidget extends StatelessWidget {
  final VideoEntity video;
  final VoidCallback onLike;
  final Function(String) onComment;

  const VideoCardWidget({
    super.key,
    required this.video,
    required this.onLike,
    required this.onComment,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Video thumbnail
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(4),
                ),
              ),
              child: Stack(
                children: [
                  // TODO: Replace with actual video thumbnail
                  Center(
                    child: Icon(
                      Icons.play_circle_outline,
                      size: 64,
                      color: Colors.grey[600],
                    ),
                  ),
                  // Video duration indicator
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '2:30', // TODO: Get actual duration
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Video info
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Title
                Text(
                  video.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),

                const SizedBox(height: 8),

                // Description
                if (video.description.isNotEmpty) ...[
                  Text(
                    video.description,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                ],

                // Uploader info and time
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: Colors.grey[300],
                      child: Text(
                        video.uploaderName.isNotEmpty
                            ? video.uploaderName[0].toUpperCase()
                            : 'U',
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video.uploaderName,
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            video.formattedUploadTime,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Video type indicator
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: video.videoType == 'yog'
                            ? Colors.blue[100]
                            : Colors.green[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        video.videoType.toUpperCase(),
                        style: TextStyle(
                          color: video.videoType == 'yog'
                              ? Colors.blue[700]
                              : Colors.green[700],
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Action buttons
                Row(
                  children: [
                    // Like button
                    _buildActionButton(
                      icon: Icons.favorite_border,
                      label: video.formattedLikeCount,
                      onTap: onLike,
                    ),

                    const SizedBox(width: 24),

                    // Comment button
                    _buildActionButton(
                      icon: Icons.comment_outlined,
                      label: '${video.comments.length}',
                      onTap: () => _showCommentDialog(context),
                    ),

                    const SizedBox(width: 24),

                    // Share button
                    _buildActionButton(
                      icon: Icons.share_outlined,
                      label: '${video.shares}',
                      onTap: () {
                        // TODO: Implement share functionality
                      },
                    ),

                    const Spacer(),

                    // Views
                    Text(
                      '${video.formattedViewCount} views',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 4),
            Text(label),
          ],
        ),
      ),
    );
  }

  void _showCommentDialog(BuildContext context) {
    final commentController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Comment'),
        content: TextField(
          controller: commentController,
          decoration: const InputDecoration(
            hintText: 'Write a comment...',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final comment = commentController.text.trim();
              if (comment.isNotEmpty) {
                onComment(comment);
                Navigator.pop(context);
              }
            },
            child: const Text('Post'),
          ),
        ],
      ),
    );
  }
}
