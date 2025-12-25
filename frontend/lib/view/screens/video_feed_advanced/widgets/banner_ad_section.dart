import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:vayu/view/widget/ads/banner_ad_widget.dart';
import 'package:vayu/view/widget/ads/google_admob_banner_widget.dart';
import 'package:vayu/config/admob_config.dart';
import 'package:vayu/utils/app_logger.dart';

/// Banner Ad Section Widget
/// Supports both custom banner ads and Google AdMob banner ads
/// Uses Google AdMob by default if configured, falls back to custom ads when AdMob fails
class BannerAdSection extends StatefulWidget {
  final Map<String, dynamic>? adData;
  final VoidCallback? onClick;
  final Future<void> Function()? onImpression;
  final bool useGoogleAds; // Flag to use Google AdMob instead of custom ads

  const BannerAdSection({
    Key? key,
    this.adData, // **FIXED: Make adData optional to prioritize AdMob**
    this.onClick,
    this.onImpression,
    this.useGoogleAds = true, // Default to Google AdMob
  }) : super(key: key);

  @override
  State<BannerAdSection> createState() => _BannerAdSectionState();
}

class _BannerAdSectionState extends State<BannerAdSection> {
  bool _admobAdFailed = false;

  @override
  Widget build(BuildContext context) {
    // **FIXED: Try Google AdMob first if configured and enabled, then fallback to custom ads**
    if (widget.useGoogleAds && AdMobConfig.isConfigured() && !_admobAdFailed) {
      final adUnitId = AdMobConfig.getBannerAdUnitId();
      if (adUnitId == null || adUnitId.isEmpty) {
        // If ad unit ID is not available, fallback to custom ads
        AppLogger.log(
            '⚠️ BannerAdSection: AdMob configured but ad unit ID not available');
        if (mounted) {
          setState(() {
            _admobAdFailed = true;
          });
        }
      } else {
        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: GoogleAdMobBannerWidget(
            adUnitId: adUnitId,
            adSize: AdSize.banner,
          ),
        );
      }
    }

    // **FALLBACK: Show custom banner ads if AdMob not configured, disabled, or failed**
    // Only show custom ads if adData is provided
    if (widget.adData == null) {
      // No custom ad data available - show empty space
      return const Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: 60,
        child: SizedBox.shrink(), // Don't show anything if no ads available
      );
    }

    // **FIXED: Show custom backend ad as fallback**
    final data = widget.adData!;
    AppLogger.log(
        '🔄 BannerAdSection: Showing custom backend ad as fallback: ${data['title'] ?? data['id']}');
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: BannerAdWidget(
        key: ValueKey('banner_${data['videoId'] ?? data['_id'] ?? data['id']}'),
        adData: data,
        onAdClick: () => widget.onClick?.call(),
        onAdImpression: () async => await widget.onImpression?.call(),
      ),
    );
  }
}
