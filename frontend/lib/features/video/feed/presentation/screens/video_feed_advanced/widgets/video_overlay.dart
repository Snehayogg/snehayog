import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/video/feed/presentation/screens/video_feed_advanced/widgets/vertical_action_button.dart';

class VideoOverlay extends StatefulWidget {
  final VideoModel video;
  final double? screenWidth;
  final double? screenHeight;
  final bool Function(VideoModel) isLiked;
  final VoidCallback onLike;
  final VoidCallback onShare;
  final VoidCallback onOpenCarouselAd;
  final VoidCallback onOpenProfile;
  final VoidCallback? onOpenEpisodes;
  final Widget followButton;
  /// Called when dubbed video is ready and user wants to play it.
  final void Function(String dubbedUrl)? onPlayDubbed;

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
    this.onOpenEpisodes,
    required this.followButton,
    this.onPlayDubbed,
  }) : super(key: key);

  @override
  State<VideoOverlay> createState() => _VideoOverlayState();
}

class _VideoOverlayState extends State<VideoOverlay> {

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }


  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        children: [
          // ── Bottom-left info ─────────────────────────────────
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
                    onTap: widget.onOpenProfile,
                    child: Row(
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onOpenProfile,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.grey,
                            ),
                            child: widget.video.uploader.profilePic.isNotEmpty
                                ? ClipOval(
                                    child: CachedNetworkImage(
                                      imageUrl: widget.video.uploader.profilePic,
                                      fit: BoxFit.cover,
                                      placeholder: (context, url) =>
                                          Container(color: Colors.grey[300]),
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
                            onTap: widget.onOpenProfile,
                            child: Text(
                              widget.video.uploader.name,
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
                        widget.followButton,
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.video.videoName.trim().isEmpty
                        ? 'Untitled Video'
                        : widget.video.videoName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),

          // ── Right-side action buttons ────────────────────────
          Positioned(
            right: 12,
            bottom: 12,
            child: Column(
              children: [
                // Like
                VerticalActionButton(
                  icon: widget.isLiked(widget.video)
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: widget.isLiked(widget.video) ? Colors.red : Colors.white,
                  count: widget.video.likes,
                  onTap: widget.onLike,
                ),
                const SizedBox(height: 10),

                // Share
                VerticalActionButton(
                  icon: Icons.share,
                  onTap: widget.onShare,
                ),
                const SizedBox(height: 10),

                // Episodes (Series)
                if (widget.video.episodes != null && widget.video.episodes!.isNotEmpty) ...[
                  VerticalActionButton(
                    icon: Icons.playlist_play_rounded,
                    onTap: widget.onOpenEpisodes ?? () {},
                    label: 'Series',
                  ),
                  const SizedBox(height: 10),
                ],


                // Swipe / Carousel Ad
                GestureDetector(
                  onTap: widget.onOpenCarouselAd,
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.5),
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

