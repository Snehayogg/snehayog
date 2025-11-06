import 'package:flutter/material.dart';
import 'package:vayu/view/widget/ads/banner_ad_widget.dart';

class BannerAdSection extends StatelessWidget {
  final Map<String, dynamic>? adData;
  final VoidCallback? onClick;
  final Future<void> Function()? onImpression;

  const BannerAdSection({
    Key? key,
    required this.adData,
    this.onClick,
    this.onImpression,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
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
