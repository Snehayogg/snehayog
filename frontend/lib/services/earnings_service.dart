import 'dart:async';
import 'package:vayu/config/app_config.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/services/ad_impression_service.dart';
import 'package:vayu/utils/app_logger.dart';

/// Centralized earnings calculations to ensure consistent values across the app
class EarningsService {
  EarningsService._();

  static final AdImpressionService _adImpressionService = AdImpressionService();

  /// Calculate revenue for a single video using ad VIEWS (not impressions)
  static Future<double> calculateVideoRevenue(String videoId,
      {Duration timeout = const Duration(seconds: 10)}) async {
    try {
      final bannerViews = await _adImpressionService
          .getBannerAdViews(videoId)
          .timeout(timeout, onTimeout: () => 0);

      final carouselViews = await _adImpressionService
          .getCarouselAdViews(videoId)
          .timeout(timeout, onTimeout: () => 0);

      final bannerRevenue = (bannerViews / 1000.0) * AppConfig.bannerCpm;
      final carouselRevenue = (carouselViews / 1000.0) * AppConfig.fixedCpm;
      final total = bannerRevenue + carouselRevenue;

      AppLogger.log(
          '💰 EarningsService: video=$videoId bannerViews=$bannerViews carouselViews=$carouselViews total=₹${total.toStringAsFixed(2)}');
      return total;
    } catch (e) {
      AppLogger.log(
          '❌ EarningsService: error calculating revenue for $videoId: $e');
      return 0.0;
    }
  }

  /// Calculate total revenue for a list of videos
  static Future<double> calculateTotalRevenueForVideos(
    List<VideoModel> videos, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    double total = 0.0;

    for (final video in videos) {
      total += await calculateVideoRevenue(video.id, timeout: timeout);
    }

    return total;
  }
}
