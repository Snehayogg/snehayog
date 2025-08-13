import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Simplified AdMob Service for managing banner ads in Snehayog app
class AdMobService {
  static final AdMobService _instance = AdMobService._internal();
  factory AdMobService() => _instance;
  AdMobService._internal();

  bool _isInitialized = false;
  final List<BannerAd> _activeAds = [];

  /// Initialize AdMob service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await MobileAds.instance.initialize();
      _isInitialized = true;
      print('✅ AdMob Service: Initialized successfully');
    } catch (e) {
      print('❌ AdMob Service: Failed to initialize: $e');
    }
  }

  /// Create a banner ad
  BannerAd createBannerAd({
    String? adUnitId,
    AdSize size = AdSize.banner,
    AdRequest? request,
  }) {
    // Use test ad unit ID for development
    final adUnitIdToUse = adUnitId ?? 'ca-app-pub-3940256099942544/6300978111';

    final bannerAd = BannerAd(
      adUnitId: adUnitIdToUse,
      size: size,
      request: request ?? const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          print('✅ AdMob Service: Banner ad loaded successfully');
        },
        onAdFailedToLoad: (ad, error) {
          print('❌ AdMob Service: Banner ad failed to load: ${error.message}');
        },
      ),
    );

    _activeAds.add(bannerAd);
    return bannerAd;
  }

  /// Load a banner ad
  Future<bool> loadBannerAd(BannerAd bannerAd) async {
    try {
      await bannerAd.load();
      return true;
    } catch (e) {
      print('❌ AdMob Service: Error loading banner ad: $e');
      return false;
    }
  }

  /// Dispose all active ads
  void disposeAllAds() {
    for (final ad in _activeAds) {
      ad.dispose();
    }
    _activeAds.clear();
  }

  /// Get the number of active ads
  int get activeAdCount => _activeAds.length;

  bool get isInitialized => _isInitialized;
}
