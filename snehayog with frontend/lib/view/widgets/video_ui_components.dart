import 'package:flutter/material.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/view/widget/video_player_widget.dart';
import 'package:snehayog/view/widget/follow_button_widget.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

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

/// Video item widget to break down long widget tree
class VideoItemWidget extends StatelessWidget {
  final VideoModel video;
  final VideoPlayerController? controller;
  final bool isActive;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onProfileTap;

  const VideoItemWidget({
    Key? key,
    required this.video,
    required this.controller,
    required this.isActive,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onProfileTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Temporary debug logging
    print('🔗 VideoItemWidget: Building for video: ${video.videoName}');
    print('🔗 VideoItemWidget: Link value: ${video.link}');
    print('🔗 VideoItemWidget: Link is null: ${video.link == null}');
    print('🔗 VideoItemWidget: Link is empty: ${video.link?.isEmpty}');
    print(
        '🔗 VideoItemWidget: Should show link button: ${video.link != null && video.link!.isNotEmpty}');

    return Stack(
      fit: StackFit.expand,
      children: [
        // Video player widget
        RepaintBoundary(
          child: VideoPlayerWidget(
            key: ValueKey(video.id),
            controller: controller,
            video: video,
            play: isActive,
          ),
        ),

        // Video information overlay (bottom left)
        Positioned(
          left: 12,
          bottom: 12,
          right: 80,
          child: _buildVideoInfo(),
        ),

        // Action buttons overlay (bottom right)
        Positioned(
          right: 12,
          bottom: 12,
          child: _buildActionButtons(),
        ),

        // External link button (if video has a link)
        if (video.link != null && video.link!.isNotEmpty)
          Positioned(
            left: 15,
            right: 15,
            bottom: 10, // Position above action buttons
            child: _buildExternalLinkButton(),
          ),
      ],
    );
  }

  Widget _buildVideoInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          video.videoName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          video.description,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onProfileTap,
          child: Row(
            children: [
              const CircleAvatar(radius: 16, backgroundColor: Colors.grey),
              const SizedBox(width: 5),
              Text(
                video.uploader.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 8),
              // Add follow button
              Builder(
                builder: (context) {
                  print(
                      '🔍 Debug: Rendering follow button for ${video.uploader.name} (ID: ${video.uploader.id})');
                  return FollowButtonWidget(
                    uploaderId: video.uploader.id,
                    uploaderName: video.uploader.name,
                    onFollowChanged: () {
                      // Refresh the video data if needed
                      print(
                          '🔄 Follow status changed for ${video.uploader.name} (ID: ${video.uploader.id})');
                      // You can add a callback here to refresh the video data if needed
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(
            video.likedBy.isNotEmpty ? Icons.favorite : Icons.favorite_border,
            color: video.likedBy.isNotEmpty ? Colors.red : Colors.white,
            size: 32,
          ),
          onPressed: onLike,
        ),
        Text('${video.likes}', style: const TextStyle(color: Colors.white)),
        const SizedBox(height: 20),
        IconButton(
          icon: const Icon(Icons.comment, color: Colors.white, size: 32),
          onPressed: onComment,
        ),
        Text('${video.comments.length}',
            style: const TextStyle(color: Colors.white)),
        const SizedBox(height: 20),
        IconButton(
          icon: const Icon(Icons.share, color: Colors.white, size: 32),
          onPressed: onShare,
        ),
        Text('${video.shares}', style: const TextStyle(color: Colors.white)),
      ],
    );
  }

  Widget _buildExternalLinkButton() {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final url = Uri.tryParse(video.link!);
            if (url != null && await canLaunchUrl(url)) {
              await launchUrl(url, mode: LaunchMode.externalApplication);
            }
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(
                colors: [
                  Color(0xCC2196F3), // More opaque blue
                  Color(0xFF1976D2), // Solid blue
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.open_in_new, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  'Visit Now',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
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
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: onTestVideoLink,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
            ),
            child: const Text('Test Video Links'),
          ),
          const SizedBox(height: 16),
          // Add cache management buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: onClearCache,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                ),
                child: const Text('Clear Cache'),
              ),
              const SizedBox(width: 16),
              ElevatedButton(
                onPressed: onGetCacheInfo,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                ),
                child: const Text('Cache Info'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
