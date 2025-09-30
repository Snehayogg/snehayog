import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:snehayog/services/active_ads_service.dart';

/// Widget to display video feed ads between videos (like Instagram Reels ads)
class VideoFeedAdWidget extends StatefulWidget {
  final Map<String, dynamic> adData;
  final VoidCallback? onAdClick;
  final bool autoPlay;

  const VideoFeedAdWidget({
    Key? key,
    required this.adData,
    this.onAdClick,
    this.autoPlay = true,
  }) : super(key: key);

  @override
  State<VideoFeedAdWidget> createState() => _VideoFeedAdWidgetState();
}

class _VideoFeedAdWidgetState extends State<VideoFeedAdWidget> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _hasTrackedImpression = false;

  @override
  void initState() {
    super.initState();
    _initializeAd();
  }

  void _initializeAd() {
    // Track impression when ad is initialized
    _trackImpression();

    // Initialize video if it's a video ad
    final videoUrl = widget.adData['videoUrl'] as String?;
    if (videoUrl != null && videoUrl.isNotEmpty) {
      _initializeVideo(videoUrl);
    }
  }

  void _initializeVideo(String videoUrl) async {
    try {
      _videoController = VideoPlayerController.network(videoUrl);
      await _videoController!.initialize();

      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });

        // Auto-play if enabled
        if (widget.autoPlay) {
          _videoController!.play();
          _videoController!.setLooping(true);
        }
      }
    } catch (e) {
      print('❌ Error initializing video feed ad video: $e');
    }
  }

  void _trackImpression() async {
    if (_hasTrackedImpression) return;

    try {
      final adId = widget.adData['_id'] ?? widget.adData['id'];
      if (adId != null) {
        final activeAdsService = ActiveAdsService();
        await activeAdsService.trackImpression(adId);
        _hasTrackedImpression = true;
        print('✅ Video feed ad impression tracked: $adId');
      }
    } catch (e) {
      print('❌ Error tracking video feed ad impression: $e');
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.adData['title'] ?? 'Advertisement';
    final description = widget.adData['description'] ?? '';
    final imageUrl = widget.adData['imageUrl'] as String?;
    final videoUrl = widget.adData['videoUrl'] as String?;
    final advertiserName = widget.adData['uploaderName'] ?? 'Advertiser';
    final advertiserProfilePic = widget.adData['uploaderProfilePic'] as String?;

    return Container(
      width: double.infinity,
      height: MediaQuery.of(context).size.height, // Full screen like video
      color: Colors.black,
      child: Stack(
        children: [
          // Media content (video or image)
          Positioned.fill(
            child: GestureDetector(
              onTap: () => _handleAdClick(context),
              child: _buildMediaContent(imageUrl, videoUrl),
            ),
          ),

          // Ad overlay information
          Positioned(
            top: 50,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: const Text(
                'Ad',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          // Bottom overlay with ad information
          Positioned(
            bottom: 100,
            left: 16,
            right: 80,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [
                    Colors.black.withOpacity(0.8),
                    Colors.transparent,
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Advertiser info
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: Colors.grey[300],
                        backgroundImage: advertiserProfilePic != null &&
                                advertiserProfilePic.isNotEmpty
                            ? NetworkImage(advertiserProfilePic)
                            : null,
                        child: advertiserProfilePic == null ||
                                advertiserProfilePic.isEmpty
                            ? const Icon(Icons.business,
                                size: 16, color: Colors.grey)
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        advertiserName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'Sponsored',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Ad title
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // Ad description
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // CTA button
          Positioned(
            bottom: 120,
            right: 16,
            child: GestureDetector(
              onTap: () => _handleAdClick(context),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Text(
                  'Learn More',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaContent(String? imageUrl, String? videoUrl) {
    // Prefer video over image
    if (videoUrl != null &&
        videoUrl.isNotEmpty &&
        _videoController != null &&
        _isVideoInitialized) {
      return Center(
        child: AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
      );
    } else if (imageUrl != null && imageUrl.isNotEmpty) {
      return Image.network(
        imageUrl,
        fit: BoxFit.contain,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stackTrace) {
          return Container(
            color: Colors.grey[800],
            child: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.image, color: Colors.white, size: 48),
                  SizedBox(height: 8),
                  Text(
                    'Ad Image',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } else {
      // Fallback for ads without media
      return Container(
        color: Colors.grey[800],
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.ad_units, color: Colors.white, size: 48),
              SizedBox(height: 8),
              Text(
                'Advertisement',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ],
          ),
        ),
      );
    }
  }

  /// Handle ad click
  void _handleAdClick(BuildContext context) async {
    try {
      final adId = widget.adData['_id'] ?? widget.adData['id'];

      // Track click
      if (adId != null) {
        final activeAdsService = ActiveAdsService();
        await activeAdsService.trackClick(adId);
        print('✅ Video feed ad click tracked: $adId');
      }

      // Execute callback
      widget.onAdClick?.call();

      // Open link if available
      final link = widget.adData['link'] as String?;
      if (link != null && link.isNotEmpty) {
        final uri = Uri.parse(link);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
          print('✅ Opened video feed ad link: $link');
        } else {
          print('❌ Cannot launch URL: $link');

          // Show error to user
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Unable to open link'),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 2),
              ),
            );
          }
        }
      } else {
        print('🔍 No link provided for video feed ad');

        // Show info to user
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ad clicked'),
              duration: Duration(seconds: 1),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error handling video feed ad click: $e');
    }
  }
}
