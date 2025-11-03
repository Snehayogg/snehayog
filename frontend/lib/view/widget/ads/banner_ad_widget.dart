import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayu/services/active_ads_service.dart';
import 'package:vayu/services/ad_impression_service.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/config/app_config.dart';
import 'package:vayu/utils/app_logger.dart';

/// Widget to display banner ads at the top of video feed
class BannerAdWidget extends StatefulWidget {
  final Map<String, dynamic> adData;
  final VoidCallback? onAdClick;
  final VoidCallback? onAdImpression;

  const BannerAdWidget({
    Key? key,
    required this.adData,
    this.onAdClick,
    this.onAdImpression,
  }) : super(key: key);

  @override
  State<BannerAdWidget> createState() => _BannerAdWidgetState();
}

class _BannerAdWidgetState extends State<BannerAdWidget> {
  bool _imageLoadFailed = false;
  bool _hasTrackedView = false; // Prevent duplicate view tracking
  DateTime? _viewStartTime; // Track when ad became visible
  Timer? _viewTrackingTimer; // Timer to check view duration

  // Cache image provider per banner to avoid rebuild flicker
  static final Map<String, ImageProvider> _imageProviderCache = {};

  final AdImpressionService _adImpressionService = AdImpressionService();
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    // Start tracking view duration when widget is built
    _startViewTracking();
  }

  @override
  void dispose() {
    _viewTrackingTimer?.cancel();
    super.dispose();
  }

  /// **NEW: Track ad view duration (minimum 2 seconds)**
  void _startViewTracking() {
    _viewStartTime = DateTime.now();

    // Track view after minimum duration (2 seconds)
    _viewTrackingTimer = Timer(const Duration(seconds: 2), () async {
      if (!_hasTrackedView && mounted) {
        await _trackAdView();
      }
    });
  }

  /// **NEW: Track ad view (minimum 2 seconds visible)**
  Future<void> _trackAdView() async {
    if (_hasTrackedView || _viewStartTime == null) return;

    try {
      final viewDuration =
          DateTime.now().difference(_viewStartTime!).inMilliseconds / 1000.0;

      // Minimum view duration: 2 seconds
      if (viewDuration < 2.0) {
        AppLogger.log(
            '⚠️ BannerAdWidget: View duration too short ($viewDuration s), not tracking');
        return;
      }

      final userData = await _authService.getUserData();
      if (userData == null) {
        AppLogger.log(
            '⚠️ BannerAdWidget: No user data, skipping view tracking');
        return;
      }

      final videoId = widget.adData['videoId'] ?? '';
      final adId = widget.adData['_id'] ?? widget.adData['id'] ?? '';
      final userId = userData['id'] ?? '';

      if (videoId.isEmpty || adId.isEmpty) {
        AppLogger.log(
            '⚠️ BannerAdWidget: Missing videoId or adId, skipping view tracking');
        return;
      }

      await _adImpressionService.trackBannerAdView(
        videoId: videoId,
        adId: adId,
        userId: userId,
        viewDuration: viewDuration,
      );

      _hasTrackedView = true;
      AppLogger.log(
          '✅ BannerAdWidget: Ad view tracked (${viewDuration.toStringAsFixed(2)}s)');
    } catch (e) {
      AppLogger.log('❌ BannerAdWidget: Error tracking ad view: $e');
    }
  }

  // Ensure absolute URL (adds scheme or base URL if needed)
  String _ensureAbsoluteUrl(String url) {
    final u = url.trim();
    if (u.isEmpty) return u;
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (u.startsWith('//')) return 'https:$u';
    if (u.startsWith('/')) {
      // Use environment-configured baseUrl for relative backend paths
      return '${AppConfig.baseUrl}$u';
    }
    return 'https://$u';
  }

  @override
  Widget build(BuildContext context) {
    // Resolve image URL from multiple possible keys and ensure absolute URL
    final dynamic rawImage = widget.adData['imageUrl'] ??
        widget.adData['image'] ??
        widget.adData['bannerImageUrl'] ??
        widget.adData['mediaUrl'] ??
        widget.adData['cloudinaryUrl'] ??
        widget.adData['thumbnail'] ??
        '';
    final String imageUrl = _ensureAbsoluteUrl(
        rawImage is String ? rawImage : rawImage?.toString() ?? '');

    // **FIX: Don't show ad widget at all if no image URL or image load failed**
    if (imageUrl.isEmpty || imageUrl.trim() == '' || _imageLoadFailed) {
      if (_imageLoadFailed) {
        AppLogger.log(
            '⚠️ BannerAdWidget: Image load failed, hiding entire ad widget to prevent grey overlay');
      } else {
        AppLogger.log(
            '⚠️ BannerAdWidget: No image URL available, hiding ad widget');
      }
      return const SizedBox.shrink();
    }

    // **NEW: Track ad impression when widget is built**
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onAdImpression?.call();
    });

    // **FIX: Isolate banner with RepaintBoundary to prevent compositing over video texture**
    return RepaintBoundary(
      child: SafeArea(
        child: Align(
          alignment: Alignment.centerLeft,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.8, // 20% narrower
            height: 50, // **REDUCED from 60 for more video space**
            margin: const EdgeInsets.only(top: 1, left: 16), // left margin
            decoration: BoxDecoration(
              color: Colors.black, // opaque background
              borderRadius: BorderRadius.circular(12),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius:
                  BorderRadius.circular(12), // Match container rounded corners
              child: InkWell(
                borderRadius: BorderRadius.circular(
                    12), // Match container rounded corners
                onTap: () => _handleAdClickWithDialog(context),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12), // Rounded corners
                  clipBehavior: Clip
                      .hardEdge, // **FIX: Hard-edge clipping for isolation**
                  child: Row(
                    children: [
                      // 40% space for banner image
                      Expanded(
                        flex: 2,
                        child: SizedBox(
                          height: 50, // **REDUCED from 60 to match container**
                          child: imageUrl.isNotEmpty
                              ? RepaintBoundary(
                                  // **FIX: Isolate image with RepaintBoundary**
                                  child: Image(
                                    image: _getCachedImageProvider(imageUrl),
                                    fit: BoxFit.cover,
                                    filterQuality: FilterQuality.low,
                                    gaplessPlayback:
                                        true, // **FIX: Gapless image to prevent flicker**
                                    errorBuilder: (context, error, stackTrace) {
                                      AppLogger.log(
                                          '❌ BannerAdWidget: Failed to load image: $imageUrl, Error: $error');
                                      // **FIX: Hide entire widget when image fails to prevent grey overlay**
                                      if (mounted) {
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                          if (mounted) {
                                            setState(() {
                                              _imageLoadFailed = true;
                                            });
                                          }
                                        });
                                      }
                                      return const SizedBox.shrink();
                                    },
                                  ),
                                )
                              : Container(
                                  color: Colors.black,
                                  child: const SizedBox.shrink(),
                                ),
                        ),
                      ),

                      // 60% space for title and CTA
                      Expanded(
                        flex: 3,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6), // more compact
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Ad title
                              Expanded(
                                child: Text(
                                  widget.adData['title'] ?? 'Sponsored Content',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10, // compact text
                                    fontWeight: FontWeight.w600,
                                    height: 1.1, // Reduced line height
                                  ),
                                  maxLines:
                                      3, // Increased from 2 to 3 to accommodate more text
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),

                              const SizedBox(height: 3),

                              // Call to action button
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => _handleAdClick(context),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade600,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        widget.adData['callToAction']
                                                ?['label'] ??
                                            'Learn More',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  // Small "Sponsored" label
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.black, // **FIX: Fully opaque**
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Sponsored',
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // **FIX: Get cached image provider for banner image to avoid rebuild flicker**
  ImageProvider _getCachedImageProvider(String url) {
    final cached = _imageProviderCache[url];
    if (cached != null) return cached;
    final provider = NetworkImage(url);
    _imageProviderCache[url] = provider;
    return provider;
  }

  /// Handle ad click with confirmation dialog (for image/text clicks)
  void _handleAdClickWithDialog(BuildContext context) async {
    try {
      final adId = widget.adData['_id'] ?? widget.adData['id'];

      // Resolve link from multiple keys and ensure absolute URL
      String link = (widget.adData['link'] ??
              widget.adData['url'] ??
              widget.adData['ctaUrl'] ??
              widget.adData['callToActionUrl'] ??
              widget.adData['targetUrl'] ??
              '')
          .toString();

      // Fallback: nested callToAction map from backend
      if (link.trim().isEmpty && widget.adData['callToAction'] is Map) {
        final nested = widget.adData['callToAction'] as Map;
        final candidate = (nested['url'] ?? nested['link'])?.toString();
        if (candidate != null && candidate.trim().isNotEmpty) {
          link = candidate.trim();
        }
      }

      link = _ensureAbsoluteUrl(link);

      // Show confirmation dialog if link is available
      if (link.isNotEmpty) {
        final shouldOpen = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Open Link'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('This will open an external link:'),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    link,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 8),
                const Text('Do you want to continue?'),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Open Link'),
              ),
            ],
          ),
        );

        if (shouldOpen == true) {
          // Track click
          if (adId != null) {
            final activeAdsService = ActiveAdsService();
            await activeAdsService.trackClick(adId);
          }

          // Execute callback
          widget.onAdClick?.call();

          // Open link
          final uri = Uri.parse(link);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } else {
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
        }
      } else {
        // Show simple message to user
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('The ads has no link to open'),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.black,
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.log('❌ Error handling banner ad click: $e');

      // Show error to user
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error opening link'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Handle ad click directly (for Learn More button)
  void _handleAdClick(BuildContext context) async {
    try {
      final adId = widget.adData['_id'] ?? widget.adData['id'];

      // Resolve link from multiple keys and ensure absolute URL
      String link = (widget.adData['link'] ??
              widget.adData['url'] ??
              widget.adData['ctaUrl'] ??
              widget.adData['callToActionUrl'] ??
              widget.adData['targetUrl'] ??
              '')
          .toString();

      // Fallback: nested callToAction map from backend
      if (link.trim().isEmpty && widget.adData['callToAction'] is Map) {
        final nested = widget.adData['callToAction'] as Map;
        final candidate = (nested['url'] ?? nested['link'])?.toString();
        if (candidate != null && candidate.trim().isNotEmpty) {
          link = candidate.trim();
        }
      }

      link = _ensureAbsoluteUrl(link);

      // Directly open link if available (no confirmation dialog)
      if (link.isNotEmpty) {
        // Track click
        if (adId != null) {
          final activeAdsService = ActiveAdsService();
          await activeAdsService.trackClick(adId);
        }

        // Execute callback
        widget.onAdClick?.call();

        // Open link directly
        final uri = Uri.parse(link);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
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
        // Show simple message to user
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('The ads has no link to open'),
              duration: Duration(seconds: 3),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.log('❌ Error handling banner ad click: $e');

      // Show error to user
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error opening link'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }
}
