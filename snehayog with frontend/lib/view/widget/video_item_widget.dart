import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/model/ad_model.dart';
import 'package:snehayog/view/widget/video_info_widget.dart';
import 'package:snehayog/view/widget/action_buttons_widget.dart';
import 'package:snehayog/view/widget/ad_display_widget.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/controller/google_sign_in_controller.dart';
import 'package:snehayog/view/widget/video_player_widget.dart';
import 'package:snehayog/services/ad_service.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:snehayog/core/managers/video_cache_manager.dart';

class VideoItemWidget extends StatefulWidget {
  final VideoModel video;
  final VideoPlayerController? controller;
  final bool isActive;
  final int index;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onProfileTap;
  final VideoCacheManager? cacheManager; // Add cache manager

  const VideoItemWidget({
    Key? key,
    required this.video,
    required this.controller,
    required this.isActive,
    required this.index,
    this.onLike,
    this.onComment,
    this.onShare,
    this.onProfileTap,
    this.cacheManager, // Add cache manager parameter
  }) : super(key: key);

  @override
  State<VideoItemWidget> createState() => _VideoItemWidgetState();
}

class _VideoItemWidgetState extends State<VideoItemWidget> {
  final AdService _adService = AdService();
  final AuthService _authService = AuthService();
  bool _isAd = false;
  Map<String, dynamic>? _adData;

  @override
  void initState() {
    super.initState();
    _checkIfAd();
  }

  void _checkIfAd() {
    // Check if this video is actually an ad
    if (widget.video.videoType == 'ad' || widget.video.id.startsWith('ad_')) {
      _isAd = true;
      // Extract ad data if available
      if (widget.video.description?.contains('Sponsored') ?? true) {
        _adData = {
          'title': widget.video.videoName,
          'description': widget.video.description,
          'imageUrl': widget.video.thumbnailUrl,
          'videoUrl': widget.video.videoUrl,
          'link': widget.video.link,
          'adType': 'interstitial',
        };
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isAd) {
      return _buildAdWidget();
    }

    return _buildVideoWidget();
  }

  Widget _buildAdWidget() {
    return Container(
      width: double.infinity,
      height: MediaQuery.of(context).size.height,
      color: Colors.black,
      child: Stack(
        children: [
          // Ad content
          if (_adData != null)
            AdDisplayWidget(
              ad: AdModel.fromJson(_adData!),
              isVideoFeed: true,
              onAdClosed: () {
                // Handle ad close - could skip to next video
                print('Ad closed by user');
              },
            )
          else
            _buildFallbackAdWidget(),

          // Ad tag overlay
          Positioned(
            top: 50,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.campaign,
                    color: Colors.white,
                    size: 16,
                  ),
                  SizedBox(width: 4),
                  Text(
                    'Ad',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Skip button for ads
          Positioned(
            top: 50,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Skip in 3s',
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
    );
  }

  Widget _buildFallbackAdWidget() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.blue.withOpacity(0.8),
            Colors.purple.withOpacity(0.8),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.campaign,
              size: 64,
              color: Colors.white,
            ),
            const SizedBox(height: 16),
            Text(
              widget.video.videoName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.video.description ?? 'No description available',
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 16,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                // Handle ad click
                if (widget.video.link != null &&
                    widget.video.link!.isNotEmpty) {
                  // Launch ad link
                  print('Ad clicked: ${widget.video.link}');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: const Text(
                'Learn More',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoWidget() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Video player
        RepaintBoundary(
          child: VideoPlayerWidget(
            key: ValueKey('video_${widget.video.id}_${widget.index}'),
            controller: widget.controller,
            video: widget.video,
            play: widget.isActive,
            cacheManager: widget.cacheManager, // Pass cache manager
          ),
        ),

        // Video info overlay - ABOVE gesture detector, can receive touch events
        Positioned(
          left: 12,
          bottom: 12,
          right:
              120, // Increased from 100 to 120 to give maximum space for Visit Now button
          child: RepaintBoundary(
            child: VideoInfoWidget(video: widget.video),
          ),
        ),

        // Action buttons - ABOVE gesture detector, can receive touch events
        Positioned(
          right: 12,
          bottom: 12,
          child: RepaintBoundary(
            child: ActionButtonsWidget(
              video: widget.video,
              index: widget.index,
              isLiked: Provider.of<GoogleSignInController>(context,
                              listen: false)
                          .userData?['id'] !=
                      null &&
                  widget.video.likedBy.contains(
                    Provider.of<GoogleSignInController>(context, listen: false)
                        .userData?['id'],
                  ),
              onLike: widget.onLike ?? () {},
              onComment: widget.onComment ?? () {},
              onShare: widget.onShare ?? () {},
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildThumbnail() {
    if (widget.video.thumbnailUrl.isEmpty) {
      return _buildFallbackThumbnail();
    }

    return CachedNetworkImage(
      imageUrl: widget.video.thumbnailUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (context, url) => _buildFallbackThumbnail(),
      errorWidget: (context, url, error) {
        print('❌ Thumbnail loading error for $url: $error');
        return _buildFallbackThumbnail();
      },
      httpHeaders: const {
        'User-Agent': 'Snehayog-App/1.0',
      },
    );
  }

  Widget _buildFallbackThumbnail() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.video_library,
              size: 32,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 8),
            Text(
              'Video',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
