import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:vayu/services/admob_service.dart';
import 'package:vayu/config/admob_config.dart';
import 'package:vayu/utils/app_logger.dart';

/// Google AdMob Banner Widget
/// Displays real Google AdMob banner ads in place of custom banner ads
/// Follows modular approach for better maintainability
class GoogleAdMobBannerWidget extends StatefulWidget {
  final String? adUnitId;
  final AdSize adSize;
  final VoidCallback? onAdLoaded;
  final VoidCallback? onAdFailed;
  final double? width;
  final double? height;
  final EdgeInsets? margin;
  final BorderRadius? borderRadius;

  const GoogleAdMobBannerWidget({
    Key? key,
    this.adUnitId,
    this.adSize = AdSize.banner,
    this.onAdLoaded,
    this.onAdFailed,
    this.width,
    this.height,
    this.margin,
    this.borderRadius,
  }) : super(key: key);

  @override
  State<GoogleAdMobBannerWidget> createState() =>
      _GoogleAdMobBannerWidgetState();
}

class _GoogleAdMobBannerWidgetState extends State<GoogleAdMobBannerWidget> {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  Future<void> _loadAd() async {
    try {
      // Get ad unit ID from config or widget parameter
      final adUnitId = widget.adUnitId ?? AdMobConfig.getBannerAdUnitId();

      if (adUnitId == null || adUnitId.isEmpty) {
        AppLogger.log('⚠️ GoogleAdMobBannerWidget: No ad unit ID available');
        _handleAdFailed();
        return;
      }

      final adMobService = AdMobService();

      // Ensure AdMob is initialized
      if (!adMobService.isInitialized) {
        await adMobService.initialize();
      }

      // Create BannerAd with listener directly (listener is final, must be set in constructor)
      _bannerAd = BannerAd(
        adUnitId: adUnitId,
        size: widget.adSize,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            AppLogger.log('✅ GoogleAdMobBannerWidget: Ad loaded successfully');
            if (mounted) {
              setState(() {
                _isAdLoaded = true;
              });
              widget.onAdLoaded?.call();
            }
          },
          onAdFailedToLoad: (ad, error) {
            AppLogger.log(
                '❌ GoogleAdMobBannerWidget: Failed to load ad: ${error.message}');
            ad.dispose();
            _bannerAd = null;
            if (mounted) {
              _handleAdFailed();
            }
          },
          onAdOpened: (ad) {
            AppLogger.log('✅ GoogleAdMobBannerWidget: Ad opened');
          },
          onAdClosed: (ad) {
            AppLogger.log('✅ GoogleAdMobBannerWidget: Ad closed');
          },
          onAdImpression: (ad) {
            AppLogger.log('📊 GoogleAdMobBannerWidget: Ad impression recorded');
          },
        ),
      );

      await _bannerAd?.load();
    } catch (e) {
      AppLogger.log('❌ GoogleAdMobBannerWidget: Error loading ad: $e');
      _handleAdFailed();
    }
  }

  void _handleAdFailed() {
    if (mounted) {
      setState(() {
        _isAdLoaded = false;
      });
      widget.onAdFailed?.call();
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show nothing if ad failed to load or not loaded yet
    if (!_isAdLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    // Match the styling of current banner ad
    final width = widget.width ?? MediaQuery.of(context).size.width * 0.8;
    final height = widget.height ?? widget.adSize.height.toDouble();
    final margin = widget.margin ?? const EdgeInsets.only(top: 1, left: 16);
    final borderRadius = widget.borderRadius ?? BorderRadius.circular(12);

    return SafeArea(
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: width,
          height: height,
          margin: margin,
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: borderRadius,
          ),
          child: ClipRRect(
            borderRadius: borderRadius,
            child: AdWidget(ad: _bannerAd!),
          ),
        ),
      ),
    );
  }
}
