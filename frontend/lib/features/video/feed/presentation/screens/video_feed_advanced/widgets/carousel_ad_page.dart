import 'package:flutter/material.dart';
import 'package:vayug/features/ads/data/carousel_ad_model.dart';
import 'package:vayug/features/ads/presentation/widgets/carousel_ad_widget.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';

class CarouselAdPage extends StatelessWidget {
  final List<CarouselAdModel> carouselAds;
  final String? videoId;
  final VoidCallback onClosed;

  const CarouselAdPage({
    Key? key,
    required this.carouselAds,
    required this.videoId,
    required this.onClosed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (carouselAds.isEmpty) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        color: AppColors.backgroundPrimary,
        child: Center(
          child: Text(
            'No carousel ads available',
            style: AppTypography.bodyMedium
                .copyWith(color: AppColors.textSecondary),
          ),
        ),
      );
    }

    final carouselAd = carouselAds[0];

    return CarouselAdWidget(
      carouselAd: carouselAd,
      videoId: videoId,
      onAdClosed: onClosed,
      autoPlay: true,
    );
  }
}
