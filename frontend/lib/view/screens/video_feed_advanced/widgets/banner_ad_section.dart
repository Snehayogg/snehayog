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
  bool _admobAdLoaded = false;

  @override
  Widget build(BuildContext context) {
    // **FIXED: Try Google AdMob first if configured and enabled, then fallback to custom ads**
    final bool shouldTryAdMob =
        widget.useGoogleAds && AdMobConfig.isConfigured() && !_admobAdFailed;

    if (shouldTryAdMob) {
      final adUnitId = AdMobConfig.getBannerAdUnitId();
      if (adUnitId == null || adUnitId.isEmpty) {
        // If ad unit ID is not available, fallback to custom ads
        AppLogger.log(
            '⚠️ BannerAdSection: AdMob configured but ad unit ID not available, falling back to custom ads');
        if (mounted) {
          setState(() {
            _admobAdFailed = true;
          });
        }
      } else {
        AppLogger.log(
            '✅ BannerAdSection: Showing AdMob banner ad with unit ID: $adUnitId');

        // **FIXED: Show AdMob ad in a Stack with custom ads as fallback**
        // If AdMob hasn't loaded yet or fails, custom ads will be visible
        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Stack(
            children: [
              // Show custom ads as fallback (behind AdMob)
              if (widget.adData != null && !_admobAdLoaded)
                BannerAdWidget(
                  key: ValueKey(
                      'banner_fallback_${widget.adData!['videoId'] ?? widget.adData!['_id'] ?? widget.adData!['id']}'),
                  adData: widget.adData!,
                  onAdClick: () => widget.onClick?.call(),
                  onAdImpression: () async => await widget.onImpression?.call(),
                ),
              // Show AdMob ad on top
              GoogleAdMobBannerWidget(
                adUnitId: adUnitId,
                adSize: AdSize.banner,
                onAdFailed: () {
                  // When AdMob fails, mark as failed and rebuild to show custom ads
                  if (mounted) {
                    AppLogger.log(
                        '⚠️ BannerAdSection: AdMob ad failed, falling back to custom ads');
                    setState(() {
                      _admobAdFailed = true;
                      _admobAdLoaded = false;
                    });
                  }
                },
                onAdLoaded: () {
                  // When AdMob loads successfully, hide custom ads
                  if (mounted) {
                    AppLogger.log(
                        '✅ BannerAdSection: AdMob ad loaded successfully, hiding custom ads');
                    setState(() {
                      _admobAdLoaded = true;
                    });
                  }
                },
              ),
            ],
          ),
        );
      }
    } else {
      // **FIXED: Log why AdMob is not being used**
      if (!widget.useGoogleAds) {
        AppLogger.log(
            '⚠️ BannerAdSection: useGoogleAds is false, using custom ads');
      } else if (!AdMobConfig.isConfigured()) {
        AppLogger.log(
            '⚠️ BannerAdSection: AdMob not configured, using custom ads');
      } else if (_admobAdFailed) {
        AppLogger.log(
            '⚠️ BannerAdSection: AdMob failed previously, using custom ads');
      }
    }

    // **FALLBACK: Show custom banner ads if AdMob not configured, disabled, or failed**
    // Only show custom ads if adData is provided
    if (widget.adData == null) {
      // **FIXED: Log when no custom ad data is available**
      AppLogger.log(
          '⚠️ BannerAdSection: No custom ad data available (adData is null), hiding banner ad');
      // **FIXED: If AdMob is being used but failed, still show empty space to avoid layout issues**
      // If AdMob is not being used at all, show empty space
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
