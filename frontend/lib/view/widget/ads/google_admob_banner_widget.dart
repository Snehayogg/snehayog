import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:vayu/services/admob_service.dart';
import 'package:vayu/utils/app_logger.dart';

/// Widget to display Google AdMob banner ad
class GoogleAdMobBannerWidget extends StatefulWidget {
  final String adUnitId;
  final AdSize? adSize;

  const GoogleAdMobBannerWidget({
    super.key,
    required this.adUnitId,
    this.adSize,
  });

  @override
  State<GoogleAdMobBannerWidget> createState() =>
      _GoogleAdMobBannerWidgetState();
}

class _GoogleAdMobBannerWidgetState extends State<GoogleAdMobBannerWidget> {
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  bool _isAdLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  Future<void> _loadAd() async {
    if (_isAdLoading) return;

    try {
      _isAdLoading = true;

      // Initialize AdMob service if not already initialized
      final admobService = AdMobService();
      if (!admobService.isInitialized) {
        await admobService.initialize();
      }

      // Create banner ad directly with listener
      _bannerAd = BannerAd(
        adUnitId: widget.adUnitId,
        size: widget.adSize ?? AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            AppLogger.log('✅ GoogleAdMobBannerWidget: Banner ad loaded');
            if (mounted) {
              setState(() {
                _isAdLoaded = true;
                _isAdLoading = false;
              });
            }
          },
          onAdFailedToLoad: (ad, error) {
            AppLogger.log(
                '❌ GoogleAdMobBannerWidget: Banner ad failed to load: ${error.message}');
            ad.dispose();
            if (mounted) {
              setState(() {
                _isAdLoaded = false;
                _isAdLoading = false;
                _bannerAd = null;
              });
            }
          },
          onAdOpened: (ad) {
            AppLogger.log('✅ GoogleAdMobBannerWidget: Banner ad opened');
          },
          onAdClosed: (ad) {
            AppLogger.log('✅ GoogleAdMobBannerWidget: Banner ad closed');
          },
        ),
      );

      // Load the ad
      await _bannerAd!.load();
    } catch (e) {
      AppLogger.log('❌ GoogleAdMobBannerWidget: Error loading ad: $e');
      if (mounted) {
        setState(() {
          _isAdLoading = false;
          _bannerAd = null;
        });
      }
    }
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Only show ad if it's loaded
    if (!_isAdLoaded || _bannerAd == null) {
      return const SizedBox.shrink();
    }

    // Get the size of the ad
    final adSize = _bannerAd!.size;
    final height = adSize.height.toDouble();

    return Container(
      alignment: Alignment.center,
      width: double.infinity,
      height: height,
      color: Colors.transparent,
      child: AdWidget(ad: _bannerAd!),
    );
  }
}
