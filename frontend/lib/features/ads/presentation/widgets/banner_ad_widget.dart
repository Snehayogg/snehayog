import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayu/features/ads/data/services/active_ads_service.dart';
import 'package:vayu/features/ads/data/services/ad_impression_service.dart';
import 'package:vayu/features/auth/data/services/authservices.dart';
import 'package:vayu/shared/theme/app_theme.dart';
import 'package:vayu/shared/config/app_config.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:vayu/shared/constants/app_constants.dart';

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

  /// **NEW: Track ad view duration (minimum 4 seconds)**
  void _startViewTracking() {
    _viewStartTime = DateTime.now();

    // Track view after minimum duration (4 seconds for ads)
    _viewTrackingTimer = Timer(AppConstants.adViewCountThreshold, () async {
      if (!_hasTrackedView && mounted) {
        await _trackAdView();
      }
    });
  }

  /// **NEW: Track ad view (minimum 4 seconds visible)**
  Future<void> _trackAdView() async {
    if (_hasTrackedView || _viewStartTime == null) return;

    try {
      final viewDuration =
          DateTime.now().difference(_viewStartTime!).inMilliseconds / 1000.0;

      // Minimum view duration for ads (4 seconds)
      final minSeconds = AppConstants.adViewCountThreshold.inSeconds;
      if (viewDuration < minSeconds) {
        AppLogger.log(
            '⚠️ BannerAdWidget: View duration too short ($viewDuration s), not tracking (min: ${minSeconds}s)');
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

    // **FIX: If no image or image failed, show text-only fallback instead of hiding**
    if (imageUrl.isEmpty || imageUrl.trim() == '' || _imageLoadFailed) {
      final reason = _imageLoadFailed ? 'image load failed' : 'no image URL';
      AppLogger.log('⚠️ BannerAdWidget: $reason, rendering text-only fallback');
      // Render compact sponsored bar with title and CTA
      return Align(
        alignment: Alignment.topLeft,
        child: Container(
          width: MediaQuery.of(context).size.width * 0.8,
          height: 50,
          margin: const EdgeInsets.only(top: 1, left: 16),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _handleAdClickWithDialog(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.adData['title'] ?? 'Sponsored',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade600.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white24, width: 0.5),
                      ),
                      child: const Text(
                        'Learn More',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    // **NEW: Track ad impression when widget is built**
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onAdImpression?.call();
    });

    // **FIX: Isolate banner with RepaintBoundary to prevent compositing over video texture**
    return RepaintBoundary(
      child: Align(
        alignment: Alignment.topLeft,
        child: Container(
            width: MediaQuery.of(context).size.width * 0.8, // 20% narrower
            height: 50, // **REDUCED from 60 for more video space**
            margin: const EdgeInsets.only(top: 1, left: 16), // left margin
            decoration: BoxDecoration(
              color: Colors.transparent,
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
                                      return Container(
                                        color: Colors.white10,
                                        child: const Center(
                                          child: Icon(Icons.broken_image_outlined, color: Colors.white24, size: 16),
                                        ),
                                      );
                                    },
                                  ),
                                )
                              : Container(
                                  color: Colors.white10,
                                  width: double.infinity,
                                  height: double.infinity,
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
                                        color: Colors.blue.shade600.withOpacity(0.5),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.white24, width: 0.5),
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
                                      color: Colors.black.withOpacity(0.3),
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
        final adTitle = widget.adData['title'] ?? 'Sponsored Content';
        
        final shouldOpen = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppTheme.backgroundSecondary,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusLarge),
              side: const BorderSide(color: AppTheme.borderPrimary, width: 1),
            ),
            title: Text(
              'Open Link',
              style: AppTheme.headlineSmall.copyWith(color: AppTheme.textPrimary),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This will open an external link:',
                  style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.backgroundTertiary.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(color: AppTheme.borderPrimary, width: 0.5),
                  ),
                  child: Text(
                    adTitle,
                    style: AppTheme.titleSmall.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Do you want to continue?',
                  style: AppTheme.bodyMedium.copyWith(color: AppTheme.textPrimary),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(
                  'Cancel',
                  style: AppTheme.labelLarge.copyWith(color: AppTheme.textSecondary),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: AppTheme.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  ),
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
