import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:snehayog/services/active_ads_service.dart';
import 'package:snehayog/config/app_config.dart';

/// Widget to display banner ads at the top of video feed
class BannerAdWidget extends StatelessWidget {
  final Map<String, dynamic> adData;
  final VoidCallback? onAdClick;

  const BannerAdWidget({
    Key? key,
    required this.adData,
    this.onAdClick,
  }) : super(key: key);

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
    final dynamic rawImage = adData['imageUrl'] ??
        adData['image'] ??
        adData['bannerImageUrl'] ??
        adData['mediaUrl'] ??
        adData['cloudinaryUrl'] ??
        adData['thumbnail'] ??
        '';
    final String imageUrl = _ensureAbsoluteUrl(
        rawImage is String ? rawImage : rawImage?.toString() ?? '');

    // Debug logging for banner ad data
    print('🎯 BannerAdWidget: Building banner ad with data:');
    print('   Raw adData keys: ${adData.keys.toList()}');
    print('   Image URL: $imageUrl');
    print('   Ad ID: ${adData['_id'] ?? adData['id']}');
    print('   Title: ${adData['title']}');
    print('   Link: ${adData['link']}');
    print('   CallToAction: ${adData['callToAction']}');
    print('   AdType: ${adData['adType']}');

    return Container(
      width: double.infinity,
      height: 60, // Compact professional height
      margin: EdgeInsets.zero, // No margin - flush to screen edges
      decoration: BoxDecoration(
        borderRadius: BorderRadius.zero, // No rounded corners for full-width
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.zero, // No rounded corners
        child: InkWell(
          borderRadius: BorderRadius.zero, // No rounded corners
          onTap: () => _handleAdClick(context),
          child: ClipRRect(
            borderRadius: BorderRadius.zero, // Full-width, no rounding
            child: Stack(
              children: [
                // Full-width ad image
                Positioned.fill(
                  child: imageUrl.isNotEmpty
                      ? Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              color: Colors.grey[300],
                              child: const Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.grey,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            print(
                                '❌ BannerAdWidget: Failed to load image: $imageUrl, Error: $error');
                            return Container(
                              color: Colors.grey[300],
                              child: const Center(
                                child: Icon(
                                  Icons.image_not_supported,
                                  color: Colors.grey,
                                  size: 32,
                                ),
                              ),
                            );
                          },
                        )
                      : Container(
                          color: Colors.grey[300],
                          child: const Center(
                            child: Icon(
                              Icons.image_not_supported,
                              color: Colors.grey,
                              size: 32,
                            ),
                          ),
                        ),
                ),

                // Subtle gradient overlay for text readability
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.3),
                        ],
                      ),
                    ),
                  ),
                ),

                // Small "Recommended Ad" label at bottom-right
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Sponsored',
                      style: TextStyle(
                        fontSize: 9,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Handle ad click
  void _handleAdClick(BuildContext context) async {
    try {
      final adId = adData['_id'] ?? adData['id'];

      // Debug logging for click handling
      print('🖱️ BannerAdWidget: Handling ad click');
      print('   Ad ID: $adId');
      print('   Available keys: ${adData.keys.toList()}');
      print('   Raw link field: ${adData['link']}');
      print('   Raw callToAction field: ${adData['callToAction']}');

      // Resolve link from multiple keys and ensure absolute URL
      String link = (adData['link'] ??
              adData['url'] ??
              adData['ctaUrl'] ??
              adData['callToActionUrl'] ??
              adData['targetUrl'] ??
              '')
          .toString();

      // Fallback: nested callToAction map from backend
      if (link.trim().isEmpty && adData['callToAction'] is Map) {
        final nested = adData['callToAction'] as Map;
        final candidate = (nested['url'] ?? nested['link'])?.toString();
        if (candidate != null && candidate.trim().isNotEmpty) {
          link = candidate.trim();
          print('   Found link in callToAction: $link');
        }
      }

      link = _ensureAbsoluteUrl(link);
      print('   Final normalized link: $link');

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
            print('✅ Banner ad click tracked: $adId');
          }

          // Execute callback
          onAdClick?.call();

          // Open link
          final uri = Uri.parse(link);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
            print('✅ Opened banner ad link: $link');
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
        }
      } else {
        print('🔍 No link provided for banner ad');

        // Show info to user
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('This ad has no link to open'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      print('❌ Error handling banner ad click: $e');

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
