import 'package:flutter/material.dart';
import 'package:vayu/view/widget/ads/banner_ad_widget.dart';

class BannerAdSection extends StatelessWidget {
  final Future<List<Map<String, dynamic>>> futureAds;
  final List<Map<String, dynamic>> fallbackBannerAds;
  final String videoName;
  final bool adsLoaded;
  final void Function(Map<String, dynamic> adData) onImpression;
  final void Function(Map<String, dynamic> adData) onTap;
  // If provided, use this ad directly (prevents disappearance on rebuild)
  final Map<String, dynamic>? cachedAdData;
  // Notify caller which ad was resolved so it can be cached
  final void Function(Map<String, dynamic> adData)? onResolved;

  const BannerAdSection({
    super.key,
    required this.futureAds,
    required this.fallbackBannerAds,
    required this.videoName,
    required this.adsLoaded,
    required this.onImpression,
    required this.onTap,
    this.cachedAdData,
    this.onResolved,
  });

  @override
  Widget build(BuildContext context) {
    // If caller provided a cached ad, render it directly and skip async churn
    if (cachedAdData != null) {
      return RepaintBoundary(
        child: BannerAdWidget(
          adData: cachedAdData!,
          onAdClick: () => onTap(cachedAdData!),
          onAdImpression: () => onImpression(cachedAdData!),
        ),
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: futureAds,
      builder: (context, snapshot) {
        Map<String, dynamic>? adData;

        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          final targetedAds = snapshot.data!;
          final adIndex = videoName.hashCode.abs() % targetedAds.length;
          adData = targetedAds[adIndex];
        } else if (adsLoaded && fallbackBannerAds.isNotEmpty) {
          final adIndex = videoName.hashCode.abs() % fallbackBannerAds.length;
          adData = fallbackBannerAds[adIndex];
        } else {
          return const SizedBox.shrink();
        }

        // Isolate the banner from the video texture to prevent shared compositing
        onResolved?.call(adData);
        return RepaintBoundary(
          child: BannerAdWidget(
            adData: adData,
            onAdClick: () => onTap(adData!),
            onAdImpression: () => onImpression(adData!),
          ),
        );
      },
    );
  }
}
