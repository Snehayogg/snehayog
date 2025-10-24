import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vayu/config/app_config.dart';
import 'package:vayu/core/managers/smart_cache_manager.dart';

/// Service to fetch all types of active ads (banner, carousel, video feed)
class ActiveAdsService {
  static String get _baseUrl => AppConfig.baseUrl;
  final SmartCacheManager _cacheManager = SmartCacheManager();

  /// Fetch all active ads from backend
  /// Optionally pass contextual signals to improve targeting
  Future<Map<String, List<Map<String, dynamic>>>> fetchActiveAds({
    String? videoCategory,
    List<String>? videoTags,
    List<String>? videoKeywords,
    String? userId,
  }) async {
    try {
      print(
          '🎯 ActiveAdsService: Fetching all active ads from $_baseUrl/api/ads/serve');

      // Include optional targeting params to match backend filters
      final Map<String, String> queryParams = {
        'platform': 'mobile',
      };

      if (userId != null && userId.isNotEmpty) {
        queryParams['userId'] = userId;
      }
      if (videoCategory != null && videoCategory.isNotEmpty) {
        queryParams['videoCategory'] = videoCategory;
      }
      if (videoTags != null && videoTags.isNotEmpty) {
        queryParams['videoTags'] = videoTags.join(',');
      }
      if (videoKeywords != null && videoKeywords.isNotEmpty) {
        queryParams['videoKeywords'] = videoKeywords.join(',');
      }

      final uri = Uri.parse('$_baseUrl/api/ads/serve')
          .replace(queryParameters: queryParams);

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

        String pick(Map<String, dynamic> m, List<String> keys) {
          for (final k in keys) {
            final v = m[k];
            if (v is String && v.trim().isNotEmpty) return v.trim();
          }
          return '';
        }

        String ensureAbsoluteUrl(String url) {
          if (url.isEmpty) return url;
          final u = url.trim();
          if (u.startsWith('http://') || u.startsWith('https://')) return u;
          if (u.startsWith('//')) return 'https:$u';
          if (u.startsWith('/')) return '${AppConfig.baseUrl}$u';
          // Fallback: assume https scheme
          return 'https://$u';
        }

        Map<String, dynamic> normalizeAd(Map<String, dynamic> ad) {
          final imageUrl = pick(ad, [
            'imageUrl',
            'imageURL',
            'image',
            'bannerImageUrl',
            'mediaUrl',
            'cloudinaryUrl',
            'thumbnail',
          ]);
          String link = pick(ad, [
            'link',
            'url',
            'ctaUrl',
            'callToActionUrl',
            'targetUrl',
          ]);

          // Also check nested callToAction.url shape (backend structure)
          if (link.isEmpty && ad['callToAction'] is Map) {
            final nested = (ad['callToAction'] as Map);
            final candidate = nested['url'] ?? nested['link'];
            if (candidate is String && candidate.trim().isNotEmpty) {
              link = candidate.trim();
            }
          }

          // Debug logging for ad normalization
          print('🔍 Normalizing ad: ${ad['_id'] ?? ad['id']}');
          print(
              '   Original imageUrl: ${ad['imageUrl'] ?? ad['cloudinaryUrl'] ?? ad['thumbnail']}');
          print('   Normalized imageUrl: ${ensureAbsoluteUrl(imageUrl)}');
          print('   Original link: ${ad['link'] ?? ad['callToAction']}');
          print('   Normalized link: ${ensureAbsoluteUrl(link)}');

          return {
            ...ad,
            'imageUrl': ensureAbsoluteUrl(imageUrl),
            'link': ensureAbsoluteUrl(link),
          };
        }

        for (final ad in ads) {
          if (ad is Map<String, dynamic>) {
            final originalAdType = ad['adType'];
            final adType = normalizeType(ad['adType']);

            // **DEBUG: Log ad type processing**
            print('🔍 ActiveAdsService: Processing ad:');
            print('   Original adType: $originalAdType');
            print('   Normalized adType: $adType');
            print('   Ad keys: ${ad.keys.toList()}');

            if (categorizedAds.containsKey(adType)) {
              categorizedAds[adType]!.add(normalizeAd(ad));
              print('   ✅ Added to $adType category');
            } else {
              print('   ❌ Unknown ad type: $adType');
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

  /// **NEW: Clear ads cache when ads are deleted**
  Future<void> clearAdsCache() async {
    try {
      print('🧹 ActiveAdsService: Clearing ads cache...');

      // Clear all ad-related cache keys
      final cacheKeys = [
        'active_ads_serve',
        'banner_ads',
        'carousel_ads',
        'video_feed_ads',
        'ads_serve_response',
      ];

      for (final key in cacheKeys) {
        // Clear cache by forcing refresh with null data
        await _cacheManager.get(
          key,
          fetchFn: () async => null as dynamic,
          cacheType: 'ads',
          maxAge: Duration.zero, // Force immediate expiration
          forceRefresh: true,
        );
        print('✅ ActiveAdsService: Cleared cache for key: $key');
      }

      print('✅ ActiveAdsService: All ads cache cleared successfully');
    } catch (e) {
      print('⚠️ ActiveAdsService: Error clearing ads cache: $e');
    }
  }
}
