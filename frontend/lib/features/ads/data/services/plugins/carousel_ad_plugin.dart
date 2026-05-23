import 'package:vayug/features/ads/domain/i_ad_provider.dart';
import 'package:vayug/features/ads/data/services/active_ads_service.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';

import 'package:vayug/features/ads/domain/i_ad_service.dart';

/// **CarouselAdPlugin**
/// Decoupled format plugin that manages Carousel ads retrieval and tracking.
class CarouselAdPlugin implements IAdProvider {
  final IAdService _activeAdsService;
  final AuthService _authService = AuthService();

  CarouselAdPlugin({IAdService? adService}) : _activeAdsService = adService ?? ActiveAdsService();

  @override
  String get adType => 'carousel';

  @override
  Future<List<Map<String, dynamic>>> loadAds({VideoModel? video}) async {
    final userData = await _authService.getUserData();
    final userId = userData?['googleId'] ?? userData?['id'];

    final allAds = await _activeAdsService.fetchActiveAds(
      userId: userId,
      videoData: video,
    );

    return allAds['carousel'] ?? [];
  }

  @override
  Future<bool> trackImpression(String adId) async {
    return await _activeAdsService.trackImpression(adId);
  }

  @override
  Future<bool> trackClick(String adId, {String? userId}) async {
    return await _activeAdsService.trackClick(adId, userId: userId);
  }
}
