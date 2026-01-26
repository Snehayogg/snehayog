import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;

/// AdMob configuration module for managing Google AdMob ad unit IDs
/// Follows the modular approach for better maintainability
class AdMobConfig {
  // **TEST Ad Unit IDs (for development)**
  // Replace these with your actual ad unit IDs from AdMob console
  static const String _testBannerAdUnitIdAndroid =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _testBannerAdUnitIdIOS =
      'ca-app-pub-3940256099942544/2934735716';

  // **PRODUCTION Ad Unit IDs**
  // These should be set via environment variables or from backend
  // Format: ca-app-pub-XXXXXXXXXXXXXXXX/XXXXXXXXXX
  static String? _productionBannerAdUnitIdAndroid =
      'ca-app-pub-2359959043864469/8166031130'; // Production Android Ad Unit ID
  static String? _productionBannerAdUnitIdIOS =
      'ca-app-pub-2359959043864469/8166031130'; // Production iOS Ad Unit ID (same for now)

  // **AdMob App ID (required for Android/iOS)**
  // Format: ca-app-pub-XXXXXXXXXXXXXXXX~XXXXXXXXXX
  static String? _admobAppId;

  // **Flag to force production ads even in debug mode**
  static bool _forceProductionAds = false; // **FIXED: Use test ads in debug mode**

  /// Force production ads even in debug mode (for testing real ads)
  static void setForceProductionAds(bool force) {
    _forceProductionAds = force;
  }

  /// Get banner ad unit ID for current platform
  static String? getBannerAdUnitId() {
    // **WEB FIX: Web platform doesn't support AdMob banner ads**
    if (kIsWeb) {
      return null; // AdMob doesn't support web banner ads
    }

    // **FIX: Use production ads if forced OR in release mode**
    // In debug mode, use test IDs UNLESS production ads are forced
    if (kDebugMode && !_forceProductionAds) {
      if (Platform.isAndroid) {
        return _testBannerAdUnitIdAndroid;
      } else if (Platform.isIOS) {
        return _testBannerAdUnitIdIOS;
      }
      return null;
    }

    // In production OR when forced, use production IDs
    if (Platform.isAndroid) {
      return _productionBannerAdUnitIdAndroid ??
          Platform.environment['ADMOB_BANNER_AD_UNIT_ID_ANDROID'];
    } else if (Platform.isIOS) {
      return _productionBannerAdUnitIdIOS ??
          Platform.environment['ADMOB_BANNER_AD_UNIT_ID_IOS'];
    }

    return null;
  }

  /// Get AdMob App ID for current platform
  static String? getAdMobAppId() {
    return _admobAppId ?? Platform.environment['ADMOB_APP_ID'];
  }

  /// Set production banner ad unit ID for Android
  static void setBannerAdUnitIdAndroid(String adUnitId) {
    _productionBannerAdUnitIdAndroid = adUnitId;
  }

  /// Set production banner ad unit ID for iOS
  static void setBannerAdUnitIdIOS(String adUnitId) {
    _productionBannerAdUnitIdIOS = adUnitId;
  }

  /// Set AdMob App ID
  static void setAdMobAppId(String appId) {
    _admobAppId = appId;
  }

  /// Check if AdMob is configured
  static bool isConfigured() {
    final adUnitId = getBannerAdUnitId();
    return adUnitId != null && adUnitId.isNotEmpty;
  }

  /// Get configuration summary for debugging
  static Map<String, dynamic> getConfigSummary() {
    return {
      'isConfigured': isConfigured(),
      'bannerAdUnitId': getBannerAdUnitId() ?? 'Not set',
      'admobAppId': getAdMobAppId() ?? 'Not set',
      'platform':
          Platform.isAndroid ? 'Android' : (Platform.isIOS ? 'iOS' : 'Unknown'),
      'environment': kDebugMode ? 'development' : 'production',
    };
  }
}
