import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:vayu/view/widget/ads/banner_ad_widget.dart';
import 'package:vayu/view/widget/ads/google_admob_banner_widget.dart';
import 'package:vayu/config/admob_config.dart';
import 'package:vayu/utils/app_logger.dart';

/// Banner Ad Section Widget
/// Supports both custom banner ads and Google AdMob banner ads
/// Uses Google AdMob by default if configured, falls back to custom ads
class BannerAdSection extends StatelessWidget {
  final Map<String, dynamic>? adData;
  final VoidCallback? onClick;
  final Future<void> Function()? onImpression;
  final bool useGoogleAds; // Flag to use Google AdMob instead of custom ads

  const BannerAdSection({
    Key? key,
    required this.adData,
    this.onClick,
    this.onImpression,
    this.useGoogleAds = true, // Default to Google AdMob
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Use Google AdMob if configured and enabled
    if (useGoogleAds && AdMobConfig.isConfigured()) {
      return Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: GoogleAdMobBannerWidget(
          adSize: AdSize.banner,
          onAdLoaded: () {
            AppLogger.log('✅ BannerAdSection: Google AdMob ad loaded');
          },
          onAdFailed: () {
            AppLogger.log('⚠️ BannerAdSection: Google AdMob ad failed, showing fallback');
            // Could show custom ad as fallback if needed
          },
        ),
      );
    }

    // Fallback to custom banner ads
    if (adData == null) {
      return const Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: 60,
        child: ColoredBox(color: Colors.black),
      );
    }

    final data = adData!;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: BannerAdWidget(
        key: ValueKey('banner_${data['videoId'] ?? data['_id'] ?? data['id']}'),
        adData: data,
        onAdClick: () => onClick?.call(),
        onAdImpression: () async => await onImpression?.call(),
      ),
    );
  }
}
