import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:snehayog/config/app_config.dart';

/// Service to fetch all types of active ads (banner, carousel, video feed)
class ActiveAdsService {
  static String get _baseUrl => AppConfig.baseUrl;

  /// Fetch all active ads from backend
  Future<Map<String, List<Map<String, dynamic>>>> fetchActiveAds() async {
    try {
      print(
          '🎯 ActiveAdsService: Fetching all active ads from $_baseUrl/api/ads/serve');

      // Include optional targeting params to match backend filters
      final uri =
          Uri.parse('$_baseUrl/api/ads/serve').replace(queryParameters: {
        // platform helps backend $in filter match
        'platform': 'mobile',
        // Leave userId empty if unknown; backend should ignore if missing
      });

      final response = await http.get(uri, headers: {
        'Content-Type': 'application/json',
      });

      print('🔍 ActiveAdsService: Response status: ${response.statusCode}');
      print('🔍 ActiveAdsService: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final dynamic decoded = json.decode(response.body);
        final List<dynamic> ads = decoded is List
            ? decoded
            : (decoded is Map<String, dynamic>
                ? (decoded['ads'] as List<dynamic>? ?? [])
                : []);

        // Separate ads by normalized type (case/format tolerant)
        final Map<String, List<Map<String, dynamic>>> categorizedAds = {
          'banner': [],
          'carousel': [],
          'video feed ad': [],
        };

        String normalizeType(String? t) {
          final s = (t ?? '').toString().trim().toLowerCase();
          if (s.isEmpty) return 'unknown';
          if (s.contains('carousel')) return 'carousel';
          if (s.replaceAll(RegExp(r'[-_ ]'), '') == 'videofeedad' ||
              s.contains('video') && s.contains('feed')) {
            return 'video feed ad';
          }
          if (s.contains('banner')) return 'banner';
          return s;
        }

        for (final ad in ads) {
          if (ad is Map<String, dynamic>) {
            final adType = normalizeType(ad['adType']);
            if (categorizedAds.containsKey(adType)) {
              categorizedAds[adType]!.add(ad);
            }
          }
        }

        print('✅ ActiveAdsService: Found ads:');
        print('   Banner ads: ${categorizedAds['banner']!.length}');
        print('   Carousel ads: ${categorizedAds['carousel']!.length}');
        print('   Video feed ads: ${categorizedAds['video feed ad']!.length}');

        return categorizedAds;
      } else {
        print('❌ Error fetching active ads: ${response.statusCode}');
        print('Response body: ${response.body}');
        return {
          'banner': [],
          'carousel': [],
          'video feed ad': [],
        };
      }
    } catch (e) {
      print('❌ Exception fetching active ads: $e');
      return {
        'banner': [],
        'carousel': [],
        'video feed ad': [],
      };
    }
  }

  /// Fetch only banner ads
  Future<List<Map<String, dynamic>>> fetchBannerAds() async {
    final allAds = await fetchActiveAds();
    return allAds['banner'] ?? [];
  }

  /// Fetch only carousel ads
  Future<List<Map<String, dynamic>>> fetchCarouselAds() async {
    final allAds = await fetchActiveAds();
    return allAds['carousel'] ?? [];
  }

  /// Fetch only video feed ads
  Future<List<Map<String, dynamic>>> fetchVideoFeedAds() async {
    final allAds = await fetchActiveAds();
    return allAds['video feed ad'] ?? [];
  }

  /// Track ad impression
  Future<bool> trackImpression(String adId) async {
    try {
      print('📊 ActiveAdsService: Tracking impression for ad: $adId');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/ads/track-impression/$adId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      print('🔍 Impression tracking response: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Exception tracking impression: $e');
      return false;
    }
  }

  /// Track ad click
  Future<bool> trackClick(String adId, {String? userId}) async {
    try {
      print('🖱️ ActiveAdsService: Tracking click for ad: $adId');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/ads/track-click/$adId'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'userId': userId,
          'platform': 'mobile',
        }),
      );

      print('🔍 Click tracking response: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      print('❌ Exception tracking click: $e');
      return false;
    }
  }
}
