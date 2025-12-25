import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:vayu/services/admob_service.dart';
import 'package:vayu/utils/app_logger.dart';

/// Widget to display Google AdMob banner ad with retry mechanism
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
  int _retryCount = 0;
  static const int _maxRetries = 3;
  LoadAdError? _lastError;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _loadAd();
  }

  Future<void> _loadAd() async {
    if (_isAdLoading) return;

    try {
      _isAdLoading = true;
      _lastError = null;

      AppLogger.log(
          '🔄 GoogleAdMobBannerWidget: Loading ad (attempt ${_retryCount + 1}/$_maxRetries)');
      AppLogger.log('🔄 Ad Unit ID: ${widget.adUnitId}');

      // Initialize AdMob service if not already initialized
      final admobService = AdMobService();
      if (!admobService.isInitialized) {
        AppLogger.log(
            '🔄 GoogleAdMobBannerWidget: Initializing AdMob service...');
        await admobService.initialize();
        // Wait a bit for initialization to complete
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // Dispose previous ad if exists
      _bannerAd?.dispose();

      // Create banner ad directly with listener
      _bannerAd = BannerAd(
        adUnitId: widget.adUnitId,
        size: widget.adSize ?? AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {
            final bannerAd = ad as BannerAd;
            AppLogger.log(
                '✅ GoogleAdMobBannerWidget: Banner ad loaded successfully');
            AppLogger.log('✅ Ad Unit ID: ${widget.adUnitId}');
            AppLogger.log(
                '✅ Ad Size: ${bannerAd.size.width}x${bannerAd.size.height}');
            if (mounted) {
              setState(() {
                _isAdLoaded = true;
                _isAdLoading = false;
                _retryCount = 0; // Reset retry count on success
                _lastError = null;
              });
            }
          },
          onAdFailedToLoad: (ad, error) {
            _lastError = error;
            AppLogger.log(
                '❌ GoogleAdMobBannerWidget: Banner ad failed to load');
            AppLogger.log('❌ Error Code: ${error.code}');
            AppLogger.log('❌ Error Message: ${error.message}');
            AppLogger.log('❌ Error Domain: ${error.domain}');
            AppLogger.log('❌ Response Info: ${error.responseInfo}');
            AppLogger.log('❌ Ad Unit ID: ${widget.adUnitId}');

            // Log detailed error information
            if (error.responseInfo != null) {
              AppLogger.log('❌ Response ID: ${error.responseInfo?.responseId}');
              AppLogger.log(
                  '❌ Mediation Adapters: ${error.responseInfo?.mediationAdapterClassName}');
            }

            ad.dispose();
            if (mounted) {
              setState(() {
                _isAdLoaded = false;
                _isAdLoading = false;
                _bannerAd = null;
              });
            }

            // Retry if we haven't exceeded max retries
            if (_retryCount < _maxRetries && mounted) {
              _retryCount++;
              final delay =
                  Duration(seconds: _retryCount * 2); // Exponential backoff
              AppLogger.log(
                  '🔄 GoogleAdMobBannerWidget: Retrying in ${delay.inSeconds} seconds...');
              _retryTimer?.cancel();
              _retryTimer = Timer(delay, () {
                if (mounted) {
                  _loadAd();
                }
              });
            } else if (_retryCount >= _maxRetries) {
              AppLogger.log(
                  '❌ GoogleAdMobBannerWidget: Max retries reached. Giving up.');
            }
          },
          onAdOpened: (ad) {
            AppLogger.log('✅ GoogleAdMobBannerWidget: Banner ad opened');
          },
          onAdClosed: (ad) {
            AppLogger.log('✅ GoogleAdMobBannerWidget: Banner ad closed');
          },
          onAdImpression: (ad) {
            AppLogger.log(
                '✅ GoogleAdMobBannerWidget: Banner ad impression recorded');
          },
        ),
      );

      // Load the ad
      await _bannerAd!.load();
    } catch (e, stackTrace) {
      AppLogger.log('❌ GoogleAdMobBannerWidget: Exception loading ad: $e');
      AppLogger.log('❌ Stack trace: $stackTrace');
      if (mounted) {
        setState(() {
          _isAdLoading = false;
          _bannerAd = null;
        });
      }

      // Retry on exception too
      if (_retryCount < _maxRetries && mounted) {
        _retryCount++;
        final delay = Duration(seconds: _retryCount * 2);
        AppLogger.log(
            '🔄 GoogleAdMobBannerWidget: Retrying after exception in ${delay.inSeconds} seconds...');
        _retryTimer?.cancel();
        _retryTimer = Timer(delay, () {
          if (mounted) {
            _loadAd();
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _bannerAd?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Show loading indicator while loading (only in debug mode)
    if (_isAdLoading && kDebugMode) {
      return Container(
        height: widget.adSize?.height.toDouble() ?? 50,
        width: double.infinity,
        color: Colors.grey[200],
        child: const Center(
          child: Text(
            'Loading Ad...',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
      );
    }

    // Show error info in debug mode
    if (!_isAdLoaded &&
        _lastError != null &&
        kDebugMode &&
        _retryCount >= _maxRetries) {
      return Container(
        height: widget.adSize?.height.toDouble() ?? 50,
        width: double.infinity,
        color: Colors.red[50],
        padding: const EdgeInsets.all(4),
        child: Center(
          child: Text(
            'Ad Failed: ${_lastError!.code}',
            style: const TextStyle(fontSize: 10, color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

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
