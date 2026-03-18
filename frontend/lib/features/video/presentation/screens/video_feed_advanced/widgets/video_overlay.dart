import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayu/features/video/video_model.dart';
import 'package:vayu/features/video/presentation/screens/video_feed_advanced/widgets/vertical_action_button.dart';
import 'package:vayu/features/video/data/services/dubbing_service.dart';

class VideoOverlay extends StatefulWidget {
  final VideoModel video;
  final double? screenWidth;
  final double? screenHeight;
  final bool Function(VideoModel) isLiked;
  final VoidCallback onLike;
  final VoidCallback onShare;
  final VoidCallback onOpenCarouselAd;
  final VoidCallback onOpenProfile;
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
    required this.followButton,
    this.onPlayDubbed,
  }) : super(key: key);

  @override
  State<VideoOverlay> createState() => _VideoOverlayState();
}

class _VideoOverlayState extends State<VideoOverlay> {
  final _dubbingService = DubbingService();
  DubbingResult _dubResult = const DubbingResult(status: DubbingStatus.idle);
  StreamSubscription<DubbingResult>? _dubSub;

  @override
  void initState() {
    super.initState();
    // If video already has a cached dubbed URL, show the play button immediately
    final cachedUrl = _dubbingService.getCachedDubbedUrl(widget.video.dubbedUrls);
    if (cachedUrl != null) {
      _dubResult = DubbingResult(
        status: DubbingStatus.completed,
        progress: 100,
        dubbedUrl: cachedUrl,
        fromCache: true,
      );
    }
  }

  @override
  void dispose() {
    _dubSub?.cancel();
    super.dispose();
  }

  void _onSmartDubTap() {
    // If already completed and has dubbed URL — play it
    if (_dubResult.status == DubbingStatus.completed && _dubResult.dubbedUrl != null) {
      widget.onPlayDubbed?.call(_dubResult.dubbedUrl!);
      return;
    }

    // If already processing, do nothing
    if (!_dubResult.isDone && _dubResult.status != DubbingStatus.idle) return;

    // Start dubbing
    _dubSub?.cancel();
    _dubSub = _dubbingService
        .requestDub(widget.video.id)
        .listen((result) {
      if (mounted) setState(() => _dubResult = result);
    });
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

                // 🎙️ Smart Dub button
                _buildSmartDubButton(),
                const SizedBox(height: 10),

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

  Widget _buildSmartDubButton() {
    final isProcessing = !_dubResult.isDone &&
        _dubResult.status != DubbingStatus.idle;
    final isCompleted = _dubResult.status == DubbingStatus.completed;
    final isNotSuitable = _dubResult.status == DubbingStatus.notSuitable;
    final isFailed = _dubResult.status == DubbingStatus.failed;

    // Color scheme
    Color bgColor = Colors.black.withValues(alpha: 0.5);
    Color iconColor = Colors.white;
    IconData icon = Icons.record_voice_over_outlined;

    if (isCompleted) {
      bgColor = Colors.green.withValues(alpha: 0.85);
      icon = Icons.play_circle_fill;
    } else if (isNotSuitable) {
      bgColor = Colors.grey.withValues(alpha: 0.6);
      icon = Icons.music_note;
      iconColor = Colors.white54;
    } else if (isFailed) {
      bgColor = Colors.red.withValues(alpha: 0.6);
      icon = Icons.error_outline;
    } else if (isProcessing) {
      bgColor = Colors.purple.withValues(alpha: 0.6);
    }

    return GestureDetector(
      onTap: (isNotSuitable) ? null : _onSmartDubTap,
      child: Column(
        children: [
          Container(
            width: 42,
            height: 42,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
            child: isProcessing
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      value: _dubResult.progress > 0
                          ? _dubResult.progress / 100
                          : null,
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 52,
            child: Text(
              _dubResult.statusLabel,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                color: isNotSuitable ? Colors.white54 : Colors.white,
                fontSize: 8,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
