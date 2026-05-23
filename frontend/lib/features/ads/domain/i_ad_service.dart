import 'package:vayug/features/video/core/data/models/video_model.dart';

/// Abstract interface contract defining the frontend Ad system operations.
abstract class IAdService {
  /// Fetch all active ads from backend with optional targeting context.
  Future<Map<String, List<Map<String, dynamic>>>> fetchActiveAds({
    String? videoCategory,
    List<String>? videoTags,
    List<String>? videoKeywords,
    String? userId,
    VideoModel? videoData,
  });

  /// Track when an ad is displayed to the user.
  Future<bool> trackImpression(String adId);

  /// Track when a user clicks on an ad.
  Future<bool> trackClick(String adId, {String? userId});

  /// Clear any local ad caches.
  Future<void> clearAdsCache();
}
