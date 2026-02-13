import 'package:flutter/material.dart';
import 'package:vayu/features/ads/presentation/widgets/banner_ad_widget.dart';
import 'package:vayu/shared/utils/app_logger.dart';

/// Banner Ad Section Widget
/// Supports only custom banner ads (AdMob removed)
class BannerAdSection extends StatefulWidget {
  final Map<String, dynamic>? adData;
  final VoidCallback? onClick;
  final Future<void> Function()? onImpression;

  const BannerAdSection({
    Key? key,
    this.adData,
    this.onClick,
    this.onImpression,
  }) : super(key: key);

  @override
  State<BannerAdSection> createState() => _BannerAdSectionState();
}

class _BannerAdSectionState extends State<BannerAdSection> {
  @override
  Widget build(BuildContext context) {
    // Only show custom ads if adData is provided
    if (widget.adData == null) {
      // **FIX: Use topLeft alignment to avoid "middle of screen" placement in Stacks**
      return SafeArea(
        child: Align(
          alignment: Alignment.topLeft,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.4, // Smaller width for loading
            height: 30, // Smaller height for loading
            margin: const EdgeInsets.only(top: 20, left: 16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text(
                'Sponsored',
                style: TextStyle(color: Colors.white24, fontSize: 9),
              ),
            ),
          ),
        ),
      );
    }

    final data = widget.adData!;
    AppLogger.log(
        '🔄 BannerAdSection: Showing custom backend ad: ${data['title'] ?? data['id']}');
    return BannerAdWidget(
      key: ValueKey('banner_${data['videoId'] ?? data['_id'] ?? data['id']}'),
      adData: data,
      onAdClick: () => widget.onClick?.call(),
      onAdImpression: () async => await widget.onImpression?.call(),
    );
  }
}
