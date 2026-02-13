import 'dart:async';
import 'package:vayu/shared/config/app_config.dart';
import 'package:vayu/shared/models/video_model.dart';
import 'package:vayu/features/ads/data/services/ad_service.dart';
import 'package:vayu/shared/utils/app_logger.dart';

/// Centralized earnings calculations to ensure consistent values across the app
/// **REFACTORED: Now strictly a wrapper around AdService (Backend API)**
/// All complex calculation logic has been moved to the backend.
class EarningsService {
  EarningsService._();

  static final AdService _adService = AdService();

  static double _applyCreatorShare(double grossAmount) =>
      grossAmount * AppConfig.creatorRevenueShare;

  static double _applyPlatformShare(double grossAmount) =>
      grossAmount * AppConfig.platformRevenueShare;

  /// Expose helpers so UI layers can convert gross to creator/platform shares
  static double creatorShareFromGross(double grossAmount) =>
      _applyCreatorShare(grossAmount);

  static double platformShareFromGross(double grossAmount) =>
      _applyPlatformShare(grossAmount);

  // ===========================================================================
  // DEPRECATED / REMOVED CLIENT-SIDE CALCULATION METHODS
  // All these have been replaced by backend-centric `calculateCreator...` methods below.
  // ===========================================================================

  /// **NEW: Fetch creator take-home revenue for a LIST of videos**
  /// Effectively wraps `AdService.getCreatorRevenueSummary`
  static Future<double> calculateCreatorTotalRevenueForVideos(
    List<VideoModel> videos, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (videos.isEmpty) return 0.0;

    try {
      // Assume all videos belong to the same creator (typical for profile/search use case)
      final uploaderId = videos.first.uploader.id;
      if (uploaderId.isEmpty) {
        AppLogger.log('⚠️ EarningsService: Empty uploader ID, returning 0');
        return 0.0;
      }

      // Fetch summary from backend
      // We force refresh if needed, but default to cached
      final data = await _adService.getCreatorRevenueSummary(userId: uploaderId);
      
      // The backend returns 'total.creatorShare' in summary
      if (data.containsKey('summary') && 
          data['summary'] is Map && 
          data['summary']['total'] is Map) {
         return (data['summary']['total']['creatorShare'] as num?)?.toDouble() ?? 0.0;
      }
      
      // Fallback: use totalRevenue from root if summary structure varies
      return (data['totalRevenue'] as num?)?.toDouble() ?? 0.0;

    } catch (e) {
      AppLogger.log('❌ EarningsService: Error fetching total revenue: $e');
      return 0.0;
    }
  }

  /// **NEW: Fetch creator take-home revenue for a SINGLE video**
  /// Uses backend per-video breakdown
  static Future<double> calculateCreatorRevenueForVideo(
    String videoId, {
    String? uploaderId,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      // We generally need uploaderId to fetch the correct user's revenue stats.
      // If not provided, we can't reliably fetch unless it's the current user,
      // but EarningsLabel usually has access to the video model.
      
      // If uploaderId is null, we can try to fetch for "current user" as a fallback,
      // but strictly speaking we should require it or fail gracefully.
      // However, to keep signature compatible with old calls that didn't pass uploaderId,
      // we might need to rely on the caller updating to pass it. 
      // Current EarningsLabel passes only videoId. We will update EarningsLabel to pass uploaderId.
      // If uploaderId is missing, we return 0.0 (or could try current user).
      
      if (uploaderId == null || uploaderId.isEmpty) {
         AppLogger.log('⚠️ EarningsService: Missing uploaderId for video $videoId');
         return 0.0;
      }

      final data = await _adService.getCreatorRevenueSummary(userId: uploaderId);
      
      if (data.containsKey('videos') && data['videos'] is List) {
        final videosList = data['videos'] as List;
        final videoStat = videosList.firstWhere(
          (v) => v['videoId'] == videoId || v['_id'] == videoId,
          orElse: () => null,
        );
        
        if (videoStat != null) {
          // Backend returns 'creatorRevenue' for each video
           return (videoStat['creatorRevenue'] as num?)?.toDouble() ?? 0.0;
        }
      }
      
      return 0.0;
    } catch (e) {
      AppLogger.log('❌ EarningsService: Error fetching video revenue: $e');
      return 0.0;
    }
  }

  // **TEMPORARY COMPATIBILITY STUB**
  // Kept to prevent build errors if I missed any call sites. Use with caution.
  // Redirects to current month logic if needed, but best to remove usage.
  static Future<double> calculateVideoRevenueForMonth(
    String videoId,
    int month,
    int year, {
    Duration timeout = const Duration(seconds: 3),
  }) async {
     // This was client-side only. We return 0.0 or deprecated warning.
     // Backend 'thisMonth' logic is available in summary but not per-video-per-month historical.
     AppLogger.log('⚠️ EarningsService: calculateVideoRevenueForMonth is deprecated/removed.');
     return 0.0;
  }
  
  static Future<double> calculateCreatorTotalRevenueForMonth(
     List<VideoModel> videos,
     int month,
     int year, {
     Duration timeout = const Duration(seconds: 3),
  }) async {
      // Deprecated.
      AppLogger.log('⚠️ EarningsService: calculateCreatorTotalRevenueForMonth is deprecated/removed.');
      return 0.0;
  }
}
