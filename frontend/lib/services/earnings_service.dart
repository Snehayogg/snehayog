import 'dart:async';
import 'package:vayu/config/app_config.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/services/ad_impression_service.dart';
import 'package:vayu/utils/app_logger.dart';

/// Centralized earnings calculations to ensure consistent values across the app
class EarningsService {
  EarningsService._();

  static final AdImpressionService _adImpressionService = AdImpressionService();

  static double _applyCreatorShare(double grossAmount) =>
      grossAmount * AppConfig.creatorRevenueShare;

  static double _applyPlatformShare(double grossAmount) =>
      grossAmount * AppConfig.platformRevenueShare;

  /// Calculate revenue for a single video using ad VIEWS (not impressions)
  /// **OPTIMIZED: Parallel API calls for banner and carousel views**
  static Future<double> calculateVideoRevenue(String videoId,
      {Duration timeout = const Duration(seconds: 3)}) async {
    try {
      // **OPTIMIZED: Fetch banner and carousel views in parallel instead of sequentially**
      final bannerViewsFuture = _adImpressionService
          .getBannerAdViews(videoId)
          .timeout(timeout, onTimeout: () => 0);

      final carouselViewsFuture = _adImpressionService
          .getCarouselAdViews(videoId)
          .timeout(timeout, onTimeout: () => 0);

      // Wait for both in parallel
      final results =
          await Future.wait<int>([bannerViewsFuture, carouselViewsFuture]);
      final bannerViews = results[0];
      final carouselViews = results[1];

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
  /// **OPTIMIZED: Uses parallel API calls instead of sequential for faster performance**
  static Future<double> calculateTotalRevenueForVideos(
    List<VideoModel> videos, {
    Duration timeout =
        const Duration(seconds: 3), // **OPTIMIZED: Reduced from 10s to 3s**
  }) async {
    if (videos.isEmpty) return 0.0;

    // **OPTIMIZED: Calculate all videos in parallel instead of sequentially**
    // This reduces total time from (videos.length × timeout) to just timeout
    final revenueFutures = videos
        .map((video) => calculateVideoRevenue(video.id, timeout: timeout));

    try {
      final revenues = await Future.wait(revenueFutures);
      final total = revenues.fold<double>(0.0, (sum, revenue) => sum + revenue);
      AppLogger.log(
          '💰 EarningsService: Calculated total revenue for ${videos.length} videos: ₹${total.toStringAsFixed(2)}');
      return total;
    } catch (e) {
      AppLogger.log('❌ EarningsService: Error calculating total revenue: $e');
      return 0.0;
    }
  }

  /// Calculate creator take-home revenue (after platform share) for a list of videos
  /// **OPTIMIZED: Uses parallel calculation for faster performance**
  static Future<double> calculateCreatorTotalRevenueForVideos(
    List<VideoModel> videos, {
    Duration timeout =
        const Duration(seconds: 3), // **OPTIMIZED: Reduced from 10s to 3s**
  }) async {
    final gross = await calculateTotalRevenueForVideos(
      videos,
      timeout: timeout,
    );
    return _applyCreatorShare(gross);
  }

  /// Calculate creator earnings for a single video (net of platform share)
  static Future<double> calculateCreatorRevenueForVideo(
    String videoId, {
    Duration timeout =
        const Duration(seconds: 3), // **OPTIMIZED: Reduced from 10s to 3s**
  }) async {
    final gross = await calculateVideoRevenue(videoId, timeout: timeout);
    return _applyCreatorShare(gross);
  }

  /// Calculate revenue for a single video for current month only
  /// **OPTIMIZED: Parallel API calls for banner and carousel views**
  static Future<double> calculateVideoRevenueForMonth(
    String videoId,
    int month,
    int year, {
    Duration timeout =
        const Duration(seconds: 3), // **OPTIMIZED: Reduced from 10s to 3s**
  }) async {
    try {
      // **OPTIMIZED: Fetch banner and carousel views in parallel instead of sequentially**
      final bannerViewsFuture = _adImpressionService
          .getBannerAdViewsForMonth(videoId, month, year)
          .timeout(timeout, onTimeout: () => 0);

      final carouselViewsFuture = _adImpressionService
          .getCarouselAdViewsForMonth(videoId, month, year)
          .timeout(timeout, onTimeout: () => 0);

      // Wait for both in parallel
      final results =
          await Future.wait<int>([bannerViewsFuture, carouselViewsFuture]);
      final bannerViews = results[0];
      final carouselViews = results[1];

      final bannerRevenue = (bannerViews / 1000.0) * AppConfig.bannerCpm;
      final carouselRevenue = (carouselViews / 1000.0) * AppConfig.fixedCpm;
      final total = bannerRevenue + carouselRevenue;

      AppLogger.log(
          '💰 EarningsService: video=$videoId month=$month/$year bannerViews=$bannerViews carouselViews=$carouselViews total=₹${total.toStringAsFixed(2)}');
      return total;
    } catch (e) {
      AppLogger.log(
          '❌ EarningsService: error calculating revenue for $videoId (month $month/$year): $e');
      return 0.0;
    }
  }

  /// Expose helpers so UI layers can convert gross to creator/platform shares
  static double creatorShareFromGross(double grossAmount) =>
      _applyCreatorShare(grossAmount);

  static double platformShareFromGross(double grossAmount) =>
      _applyPlatformShare(grossAmount);
}
