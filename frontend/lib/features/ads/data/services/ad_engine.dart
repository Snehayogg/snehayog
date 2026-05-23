import 'package:vayug/features/ads/domain/i_ad_provider.dart';
import 'package:vayug/features/ads/data/services/plugins/banner_ad_plugin.dart';
import 'package:vayug/features/ads/data/services/plugins/carousel_ad_plugin.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';

/// **AdEngine**
/// Central orchestration framework on the frontend.
/// Resolves and delegates ad requests and tracking events to pluggable format providers.
class AdEngine {
  static final AdEngine _instance = AdEngine._internal();
  factory AdEngine() => _instance;

  final List<IAdProvider> _providers = [];

  AdEngine._internal() {
    // Automatically register local ad plugins/codecs
    _registerProvider(BannerAdPlugin());
    _registerProvider(CarouselAdPlugin());
  }

  /// Register a format provider plugin
  void _registerProvider(IAdProvider provider) {
    if (!_providers.any((p) => p.adType == provider.adType)) {
      _providers.add(provider);
    }
  }

  /// Find active provider for the given adType
  IAdProvider? _getProvider(String adType) {
    final normalized = adType.toLowerCase().trim();
    return _providers.firstWhere(
      (p) => p.adType == normalized || normalized.contains(p.adType),
      orElse: () => _providers.firstWhere((p) => p.adType == 'banner'), // Fallback to banner
    );
  }

  /// Load targeted ads for a specific format type
  Future<List<Map<String, dynamic>>> loadTargetedAds({
    required String adType,
    VideoModel? video,
  }) async {
    final provider = _getProvider(adType);
    if (provider == null) return [];
    return await provider.loadAds(video: video);
  }

  /// Route impression tracking
  Future<bool> trackImpression(String adId, String adType) async {
    final provider = _getProvider(adType);
    if (provider == null) return false;
    return await provider.trackImpression(adId);
  }

  /// Route click tracking
  Future<bool> trackClick(String adId, String adType, {String? userId}) async {
    final provider = _getProvider(adType);
    if (provider == null) return false;
    return await provider.trackClick(adId, userId: userId);
  }
}

// Pre-initialized shared default instance
final adEngine = AdEngine();
