import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vayu/config/app_config.dart';
import 'package:vayu/services/authservices.dart';

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
      print('📊 AdImpressionService: Tracking banner ad impression:');
      print('   Video ID: $videoId');
      print('   Ad ID: $adId');
      print('   User ID: $userId');

      final url = '${AppConfig.baseUrl}/api/ads/impressions/banner';
      print('📊 AdImpressionService: Tracking API URL: $url');

      final response = await http.post(
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

      print(
          '📊 AdImpressionService: Tracking API response status: ${response.statusCode}');
      print(
          '📊 AdImpressionService: Tracking API response body: ${response.body}');

      if (response.statusCode == 201 || response.statusCode == 200) {
        print(
            '✅ AdImpressionService: Banner ad impression tracked successfully: Video $videoId, Ad $adId');
      } else {
        print(
            '❌ AdImpressionService: Failed to track banner ad impression: ${response.body}');
      }
    } catch (e) {
      print('❌ AdImpressionService: Error tracking banner ad impression: $e');
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
      final response = await http.post(
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
        print(
            '📊 Carousel ad impression tracked: Video $videoId, Ad $adId, Position: $scrollPosition');
      } else {
        print('❌ Failed to track carousel ad impression: ${response.body}');
      }
    } catch (e) {
      print('❌ Error tracking carousel ad impression: $e');
    }
  }

  /// Get total ad impressions for a video
  Future<Map<String, int>> getVideoAdImpressions(String videoId) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) return {'banner': 0, 'carousel': 0, 'total': 0};

      final response = await http.get(
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
      print('❌ Error getting ad impressions: $e');
      return {'banner': 0, 'carousel': 0, 'total': 0};
    }
  }

  /// Get banner ad impressions for a video (real API call)
  Future<int> getBannerAdImpressions(String videoId) async {
    try {
      print(
          '📊 AdImpressionService: Getting banner ad impressions for video: $videoId');

      final userData = await _authService.getUserData();
      if (userData == null) {
        print('❌ AdImpressionService: No authenticated user found');
        return 0;
      }

      final url =
          '${AppConfig.baseUrl}/api/ads/impressions/video/$videoId/banner';
      print('📊 AdImpressionService: API URL: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer ${userData['token']}',
        },
      );

      print(
          '📊 AdImpressionService: API response status: ${response.statusCode}');
      print('📊 AdImpressionService: API response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final count = data['count'] ?? 0;
        print('📊 AdImpressionService: Banner impressions count: $count');
        return count;
      } else {
        print(
            '❌ AdImpressionService: Failed to get banner impressions - Status: ${response.statusCode}');
        return 0;
      }
    } catch (e) {
      print('❌ AdImpressionService: Error getting banner ad impressions: $e');
      return 0;
    }
  }

  /// Get carousel ad impressions for a video (real API call)
  Future<int> getCarouselAdImpressions(String videoId) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) return 0;

      final response = await http.get(
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
      print('❌ Error getting carousel ad impressions: $e');
      return 0;
    }
  }
}
