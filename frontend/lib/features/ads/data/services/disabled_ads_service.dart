import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/ads/domain/i_ad_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';

/// Disabled mock ad service for premium plans or local stub builds.
class DisabledAdsService implements IAdService {
  @override
  Future<Map<String, List<Map<String, dynamic>>>> fetchActiveAds({
    String? videoCategory,
    List<String>? videoTags,
    List<String>? videoKeywords,
    String? userId,
    VideoModel? videoData,
  }) async {
    AppLogger.log('🚫 [DisabledAdsService]: fetchActiveAds invoked (returning empty ads map)');
    return {
      'banner': [],
      'carousel': [],
      'video feed ad': [],
    };
  }

  @override
  Future<bool> trackImpression(String adId) async {
    AppLogger.log('🚫 [DisabledAdsService]: trackImpression mocked for ID $adId');
    return true;
  }

  @override
  Future<bool> trackClick(String adId, {String? userId}) async {
    AppLogger.log('🚫 [DisabledAdsService]: trackClick mocked for ID $adId');
    return true;
  }

  @override
  Future<void> clearAdsCache() async {
    AppLogger.log('🚫 [DisabledAdsService]: clearAdsCache mocked');
  }
}
