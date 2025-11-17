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
    required this.adData,
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
      return Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: GoogleAdMobBannerWidget(
          adSize: AdSize.banner,
          onAdLoaded: () {
            AppLogger.log(
                '✅ BannerAdSection: Google AdMob ad loaded successfully');
            // Reset failed state if ad loads successfully
            if (_admobAdFailed) {
              setState(() {
                _admobAdFailed = false;
              });
            }
          },
          onAdFailed: () {
            AppLogger.log(
                '⚠️ BannerAdSection: Google AdMob ad failed, falling back to custom banner');
            // Mark AdMob as failed and show custom ad as fallback
            if (mounted) {
              setState(() {
                _admobAdFailed = true;
              });
            }
          },
        ),
      );
    }

    // **FALLBACK: Show custom banner ads if AdMob not configured, disabled, or failed**
    if (widget.adData == null) {
      return const Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: 60,
        child: ColoredBox(color: Colors.black),
      );
    }

    final data = widget.adData!;
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
