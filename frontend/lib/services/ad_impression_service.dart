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
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/ad-impressions/banner'),
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

      if (response.statusCode == 201 || response.statusCode == 200) {
        print('📊 Banner ad impression tracked: Video $videoId, Ad $adId');
      } else {
        print('❌ Failed to track banner ad impression: ${response.body}');
      }
    } catch (e) {
      print('❌ Error tracking banner ad impression: $e');
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
        Uri.parse('${AppConfig.baseUrl}/api/ad-impressions/carousel'),
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
        Uri.parse('${AppConfig.baseUrl}/api/ad-impressions/video/$videoId'),
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
      final userData = await _authService.getUserData();
      if (userData == null) return 0;

      final response = await http.get(
        Uri.parse(
            '${AppConfig.baseUrl}/api/ad-impressions/video/$videoId/banner'),
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
      print('❌ Error getting banner ad impressions: $e');
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
            '${AppConfig.baseUrl}/api/ad-impressions/video/$videoId/carousel'),
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
