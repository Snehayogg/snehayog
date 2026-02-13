import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayu/shared/models/video_model.dart';
import 'package:vayu/features/video/presentation/screens/video_feed_advanced/widgets/vertical_action_button.dart';

class VideoOverlay extends StatelessWidget {
  final VideoModel video;
  final double? screenWidth;
  final double? screenHeight;
  final bool Function(VideoModel) isLiked;
  final VoidCallback onLike;
  final VoidCallback onShare;
  final VoidCallback onOpenCarouselAd;
  final VoidCallback onOpenProfile;
  final Widget followButton;

  const VideoOverlay({
    Key? key,
    required this.video,
    required this.screenWidth,
    required this.screenHeight,
    required this.isLiked,
    required this.onLike,
    required this.onShare,
    required this.onOpenCarouselAd,
    required this.onOpenProfile,
    required this.followButton,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        children: [
          Positioned(
            bottom: 8,
            left: 0,
            right: 75,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onOpenProfile,
                    child: Row(
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: onOpenProfile,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey,
                            ),
                            child: video.uploader.profilePic.isNotEmpty
                                ? ClipOval(
                                    child: CachedNetworkImage(
                                      imageUrl: video.uploader.profilePic,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) => Container(
                                        color: Colors.grey[300],
                                      ),
                                      errorWidget: (context, url, error) =>
                                          Container(color: Colors.grey[300]),
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: GestureDetector(
                            onTap: onOpenProfile,
                            child: Text(
                              video.uploader.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        followButton,
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    video.videoName.trim().isEmpty ? 'Untitled Video' : video.videoName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (video.link?.isNotEmpty == true)
                    // Host app handles onTap externally if needed
                    const SizedBox.shrink(),
                ],
              ),
            ),
          ),
          Positioned(
            right: 12,
            bottom: 12,
            child: Column(
              children: [
                VerticalActionButton(
                  icon: isLiked(video) ? Icons.favorite : Icons.favorite_border,
                  color: isLiked(video) ? Colors.red : Colors.white,
                  count: video.likes,
                  onTap: onLike,
                ),
                const SizedBox(height: 10),
                VerticalActionButton(
                  icon: Icons.share,
                  onTap: onShare,
                ),
                const SizedBox(height: 10),
                GestureDetector(
                  onTap: onOpenCarouselAd,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Swipe',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
