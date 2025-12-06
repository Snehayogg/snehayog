import 'dart:convert';
import 'package:vayu/config/app_config.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/utils/app_logger.dart';
import 'package:vayu/core/services/http_client_service.dart';

class AdImpressionService {
  static final AdImpressionService _instance = AdImpressionService._internal();
  factory AdImpressionService() => _instance;
  AdImpressionService._internal();

  final AuthService _authService = AuthService();

  /// Track banner ad impression for a video
  Future<void> trackBannerAdImpression({
    required String videoId,
    required String adId,
    required String userId,
  }) async {
    try {
      AppLogger.log('📊 AdImpressionService: Tracking banner ad impression:');
      AppLogger.log('   Video ID: $videoId');
      AppLogger.log('   Ad ID: $adId');
      AppLogger.log('   User ID: $userId');

      final url = '${AppConfig.baseUrl}/api/ads/impressions/banner';
      AppLogger.log('📊 AdImpressionService: Tracking API URL: $url');

      final response = await httpClientService.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Bearer ${(await _authService.getUserData())?['token']}',
        },
        body: json.encode({
          'videoId': videoId,
          'adId': adId,
          'userId': userId,
          'adType': 'banner',
          'timestamp': DateTime.now().toIso8601String(),
          'impressionType': 'view',
        }),
      );

      AppLogger.log(
          '📊 AdImpressionService: Tracking API response status: ${response.statusCode}');
      AppLogger.log(
          '📊 AdImpressionService: Tracking API response body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        AppLogger.log(
            '✅ AdImpressionService: Banner ad impression tracked successfully: Video $videoId, Ad $adId');
      } else {
        AppLogger.log(
            '❌ AdImpressionService: Failed to track banner ad impression: ${response.body}');
      }
    } catch (e) {
      AppLogger.log(
          '❌ AdImpressionService: Error tracking banner ad impression: $e');
    }
  }

  /// Track carousel ad impression when user scrolls
  Future<void> trackCarouselAdImpression({
    required String videoId,
    required String adId,
    required String userId,
    required int scrollPosition,
  }) async {
    try {
      final response = await httpClientService.post(
        Uri.parse('${AppConfig.baseUrl}/api/ads/impressions/carousel'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Bearer ${(await _authService.getUserData())?['token']}',
        },
        body: json.encode({
          'videoId': videoId,
          'adId': adId,
          'userId': userId,
          'adType': 'carousel',
          'scrollPosition': scrollPosition,
          'timestamp': DateTime.now().toIso8601String(),
          'impressionType': 'scroll_view',
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        AppLogger.log(
            '📊 Carousel ad impression tracked: Video $videoId, Ad $adId, Position: $scrollPosition');
      } else {
        AppLogger.log(
            '❌ Failed to track carousel ad impression: ${response.body}');
      }
    } catch (e) {
      AppLogger.log('❌ Error tracking carousel ad impression: $e');
    }
  }

  /// Get total ad impressions for a video
  Future<Map<String, int>> getVideoAdImpressions(String videoId) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) return {'banner': 0, 'carousel': 0, 'total': 0};

      final response = await httpClientService.get(
        Uri.parse('${AppConfig.baseUrl}/api/ads/impressions/video/$videoId'),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return {
          'banner': data['bannerImpressions'] ?? 0,
          'carousel': data['carouselImpressions'] ?? 0,
          'total': data['totalImpressions'] ?? 0,
        };
      }

      return {'banner': 0, 'carousel': 0, 'total': 0};
    } catch (e) {
      AppLogger.log('❌ Error getting ad impressions: $e');
      return {'banner': 0, 'carousel': 0, 'total': 0};
    }
  }

  /// Get banner ad impressions for a video (real API call)
  Future<int> getBannerAdImpressions(String videoId) async {
    try {
      AppLogger.log(
          '📊 AdImpressionService: Getting banner ad impressions for video: $videoId');

      final userData = await _authService.getUserData();
      if (userData == null) {
        AppLogger.log('❌ AdImpressionService: No authenticated user found');
        return 0;
      }

      final url =
          '${AppConfig.baseUrl}/api/ads/impressions/video/$videoId/banner';
      AppLogger.log('📊 AdImpressionService: API URL: $url');

      final response = await httpClientService.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
      );

      AppLogger.log(
          '📊 AdImpressionService: API response status: ${response.statusCode}');
      AppLogger.log(
          '📊 AdImpressionService: API response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final count = data['count'] ?? 0;
        AppLogger.log(
            '📊 AdImpressionService: Banner impressions count: $count');
        return count;
      } else {
        AppLogger.log(
            '❌ AdImpressionService: Failed to get banner impressions - Status: ${response.statusCode}');
        return 0;
      }
    } catch (e) {
      AppLogger.log(
          '❌ AdImpressionService: Error getting banner ad impressions: $e');
      return 0;
    }
  }

  /// Get carousel ad impressions for a video (real API call)
  Future<int> getCarouselAdImpressions(String videoId) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) return 0;

      final response = await httpClientService.get(
        Uri.parse(
            '${AppConfig.baseUrl}/api/ads/impressions/video/$videoId/carousel'),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['count'] ?? 0;
      }

      return 0;
    } catch (e) {
      AppLogger.log('❌ Error getting carousel ad impressions: $e');
      return 0;
    }
  }

  /// **NEW: Track banner ad VIEW (minimum 2-3 seconds visible) - for revenue calculation**
  Future<void> trackBannerAdView({
    required String videoId,
    required String adId,
    required String userId,
    required double viewDuration, // Duration in seconds
  }) async {
    try {
      AppLogger.log('👁️ AdImpressionService: Tracking banner ad VIEW:');
      AppLogger.log('   Video ID: $videoId');
      AppLogger.log('   Ad ID: $adId');
      AppLogger.log('   User ID: $userId');
      AppLogger.log('   View Duration: ${viewDuration}s');

      final url = '${AppConfig.baseUrl}/api/ads/impressions/banner/view';
      final response = await httpClientService.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Bearer ${(await _authService.getUserData())?['token']}',
        },
        body: json.encode({
          'videoId': videoId,
          'adId': adId,
          'userId': userId,
          'viewDuration': viewDuration,
        }),
      );

      if (response.statusCode == 200) {
        AppLogger.log(
            '✅ AdImpressionService: Banner ad VIEW tracked successfully: Video $videoId, Ad $adId, Duration: ${viewDuration}s');
      } else {
        AppLogger.log(
            '❌ AdImpressionService: Failed to track banner ad view: ${response.body}');
      }
    } catch (e) {
      AppLogger.log('❌ AdImpressionService: Error tracking banner ad view: $e');
    }
  }

  /// **NEW: Track carousel ad VIEW (minimum 2-3 seconds visible) - for revenue calculation**
  Future<void> trackCarouselAdView({
    required String videoId,
    required String adId,
    required String userId,
    required double viewDuration, // Duration in seconds
  }) async {
    try {
      AppLogger.log('👁️ AdImpressionService: Tracking carousel ad VIEW:');
      AppLogger.log('   Video ID: $videoId');
      AppLogger.log('   Ad ID: $adId');
      AppLogger.log('   User ID: $userId');
      AppLogger.log('   View Duration: ${viewDuration}s');

      final url = '${AppConfig.baseUrl}/api/ads/impressions/carousel/view';
      final response = await httpClientService.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization':
              'Bearer ${(await _authService.getUserData())?['token']}',
        },
        body: json.encode({
          'videoId': videoId,
          'adId': adId,
          'userId': userId,
          'viewDuration': viewDuration,
        }),
      );

      if (response.statusCode == 200) {
        AppLogger.log(
            '✅ AdImpressionService: Carousel ad VIEW tracked successfully: Video $videoId, Ad $adId, Duration: ${viewDuration}s');
      } else {
        AppLogger.log(
            '❌ AdImpressionService: Failed to track carousel ad view: ${response.body}');
      }
    } catch (e) {
      AppLogger.log(
          '❌ AdImpressionService: Error tracking carousel ad view: $e');
    }
  }

  /// **NEW: Get banner ad VIEWS (not impressions) for revenue calculation**
  Future<int> getBannerAdViews(String videoId) async {
    try {
      AppLogger.log(
          '👁️ AdImpressionService: Getting banner ad VIEWS for video: $videoId');

      final userData = await _authService.getUserData();
      if (userData == null) {
        AppLogger.log('❌ AdImpressionService: No authenticated user found');
        return 0;
      }

      final url = '${AppConfig.baseUrl}/api/ads/views/video/$videoId/banner';
      AppLogger.log('👁️ AdImpressionService: API URL: $url');

      final response = await httpClientService.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final count = data['count'] ?? 0;
        AppLogger.log('👁️ AdImpressionService: Banner VIEWS count: $count');
        return count;
      } else {
        AppLogger.log(
            '❌ AdImpressionService: Failed to get banner views - Status: ${response.statusCode}');
        return 0;
      }
    } catch (e) {
      AppLogger.log('❌ AdImpressionService: Error getting banner ad views: $e');
      return 0;
    }
  }

  /// **NEW: Get carousel ad VIEWS (not impressions) for revenue calculation**
  Future<int> getCarouselAdViews(String videoId) async {
    try {
      AppLogger.log(
          '👁️ AdImpressionService: Getting carousel ad VIEWS for video: $videoId');

      final userData = await _authService.getUserData();
      if (userData == null) return 0;

      final url = '${AppConfig.baseUrl}/api/ads/views/video/$videoId/carousel';
      final response = await httpClientService.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final count = data['count'] ?? 0;
        AppLogger.log('👁️ AdImpressionService: Carousel VIEWS count: $count');
        return count;
      }

      return 0;
    } catch (e) {
      AppLogger.log('❌ Error getting carousel ad views: $e');
      return 0;
    }
  }

  /// **NEW: Get banner ad VIEWS for current month only**
  Future<int> getBannerAdViewsForMonth(
      String videoId, int month, int year) async {
    try {
      AppLogger.log(
          '👁️ AdImpressionService: Getting banner ad VIEWS for current month (${month}/${year}) for video: $videoId');

      final userData = await _authService.getUserData();
      if (userData == null) {
        AppLogger.log('❌ AdImpressionService: No authenticated user found');
        return 0;
      }

      final url =
          '${AppConfig.baseUrl}/api/ads/views/video/$videoId/banner?month=$month&year=$year';
      AppLogger.log('👁️ AdImpressionService: API URL: $url');

      final response = await httpClientService.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final count = data['count'] ?? 0;
        AppLogger.log(
            '👁️ AdImpressionService: Banner VIEWS count for ${month}/${year}: $count');
        return count;
      } else {
        AppLogger.log(
            '❌ AdImpressionService: Failed to get banner views - Status: ${response.statusCode}');
        return 0;
      }
    } catch (e) {
      AppLogger.log(
          '❌ AdImpressionService: Error getting banner ad views for month: $e');
      return 0;
    }
  }

  /// **NEW: Get carousel ad VIEWS for current month only**
  Future<int> getCarouselAdViewsForMonth(
      String videoId, int month, int year) async {
    try {
      AppLogger.log(
          '👁️ AdImpressionService: Getting carousel ad VIEWS for current month (${month}/${year}) for video: $videoId');

      final userData = await _authService.getUserData();
      if (userData == null) return 0;

      final url =
          '${AppConfig.baseUrl}/api/ads/views/video/$videoId/carousel?month=$month&year=$year';
      final response = await httpClientService.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final count = data['count'] ?? 0;
        AppLogger.log(
            '👁️ AdImpressionService: Carousel VIEWS count for ${month}/${year}: $count');
        return count;
      }

      return 0;
    } catch (e) {
      AppLogger.log('❌ Error getting carousel ad views for month: $e');
      return 0;
    }
  }
}
