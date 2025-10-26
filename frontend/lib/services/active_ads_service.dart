import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vayu/config/app_config.dart';
import 'package:vayu/core/managers/smart_cache_manager.dart';
import 'package:vayu/services/ad_targeting_service.dart';
import 'package:vayu/model/video_model.dart';

/// Service to fetch all types of active ads (banner, carousel, video feed)
class ActiveAdsService {
  static String get _baseUrl => AppConfig.baseUrl;
  final SmartCacheManager _cacheManager = SmartCacheManager();
  final AdTargetingService _adTargetingService = AdTargetingService();

  /// Fetch all active ads from backend
  /// Optionally pass contextual signals to improve targeting
  Future<Map<String, List<Map<String, dynamic>>>> fetchActiveAds({
    String? videoCategory,
    List<String>? videoTags,
    List<String>? videoKeywords,
    String? userId,
    VideoModel? videoData, // NEW: Support for video-based targeting
  }) async {
    try {
      // NEW: If videoData is provided, use intelligent targeting
      if (videoData != null) {
        print(
            '🎯 ActiveAdsService: Using intelligent targeting for video: ${videoData.id}');
        return await _fetchTargetedAdsForVideo(videoData);
      }

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

  /// **NEW: Fetch targeted ads for a specific video using intelligent targeting**
  Future<Map<String, List<Map<String, dynamic>>>> _fetchTargetedAdsForVideo(
      VideoModel video) async {
    try {
      print(
          '🎯 ActiveAdsService: Fetching targeted ads for video: ${video.id}');

      // Get targeted ads for banner, carousel, and video feed ad types
      final bannerResult = await _adTargetingService.getTargetedAdsForVideo(
        video: video,
        limit: 5,
        adType: 'banner',
      );

      final carouselResult = await _adTargetingService.getTargetedAdsForVideo(
        video: video,
        limit: 3,
        adType: 'carousel',
      );

      final videoFeedResult = await _adTargetingService.getTargetedAdsForVideo(
        video: video,
        limit: 3,
        adType: 'video feed ad',
      );

      // Process and categorize the results
      final Map<String, List<Map<String, dynamic>>> categorizedAds = {
        'banner': _processTargetedAds(bannerResult['ads']),
        'carousel': _processTargetedAds(carouselResult['ads']),
        'video feed ad': _processTargetedAds(videoFeedResult['ads']),
      };

      // Log targeting insights
      if (bannerResult['insights'] != null) {
        final insights = bannerResult['insights'] as Map<String, dynamic>;
        print('🎯 Targeting Insights:');
        print('   Video Categories: ${insights['videoCategories']}');
        print('   Video Interests: ${insights['videoInterests']}');
        print('   Targeted Ads: ${insights['targetedAds']}');
        print('   Fallback Ads: ${insights['fallbackAds']}');
      }

      print('✅ ActiveAdsService: Found targeted ads:');
      print('   Banner: ${categorizedAds['banner']!.length}');
      print('   Carousel: ${categorizedAds['carousel']!.length}');
      print('   Video Feed: ${categorizedAds['video feed ad']!.length}');

      return categorizedAds;
    } catch (e) {
      print('❌ ActiveAdsService: Error fetching targeted ads: $e');

      // Fall back to random ads if targeting fails
      print('🔄 ActiveAdsService: Falling back to random ads...');
      return await _fetchFallbackAds();
    }
  }

  /// **NEW: Process targeted ads from backend response**
  List<Map<String, dynamic>> _processTargetedAds(dynamic adsData) {
    if (adsData == null || adsData is! List) {
      return [];
    }

    return (adsData)
        .map((ad) {
          if (ad is Map<String, dynamic>) {
            return _normalizeAd(ad);
          }
          return <String, dynamic>{};
        })
        .where((ad) => ad.isNotEmpty)
        .toList();
  }

  /// **NEW: Normalize ad data for consistent format**
  Map<String, dynamic> _normalizeAd(Map<String, dynamic> ad) {
    // Extract image URL from various possible fields
    final imageUrl = _extractImageUrl(ad);

    // Extract link from various possible fields
    final link = _extractLink(ad);

    return {
      ...ad,
      'imageUrl': _ensureAbsoluteUrl(imageUrl),
      'link': _ensureAbsoluteUrl(link),
    };
  }

  /// **NEW: Extract image URL from ad data**
  String _extractImageUrl(Map<String, dynamic> ad) {
    final candidates = [
      'imageUrl',
      'imageURL',
      'image',
      'bannerImageUrl',
      'mediaUrl',
      'cloudinaryUrl',
      'thumbnail',
    ];

    for (final key in candidates) {
      final value = ad[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    return '';
  }

  /// **NEW: Extract link from ad data**
  String _extractLink(Map<String, dynamic> ad) {
    // Try direct link fields first
    final directCandidates = [
      'link',
      'url',
      'ctaUrl',
      'callToActionUrl',
      'targetUrl'
    ];
    for (final key in directCandidates) {
      final value = ad[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }

    // Try nested callToAction structure
    if (ad['callToAction'] is Map) {
      final callToAction = ad['callToAction'] as Map;
      final url = callToAction['url'] ?? callToAction['link'];
      if (url is String && url.trim().isNotEmpty) {
        return url.trim();
      }
    }

    return '';
  }

  /// **NEW: Ensure URL is absolute**
  String _ensureAbsoluteUrl(String url) {
    if (url.isEmpty) return url;
    final trimmed = url.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    if (trimmed.startsWith('//')) {
      return 'https:$trimmed';
    }
    if (trimmed.startsWith('/')) {
      return '${AppConfig.baseUrl}$trimmed';
    }
    return 'https://$trimmed';
  }

  /// **NEW: Fetch fallback ads when targeting fails**
  Future<Map<String, List<Map<String, dynamic>>>> _fetchFallbackAds() async {
    try {
      print('🔄 ActiveAdsService: Fetching fallback ads...');

      final response = await http.get(
        Uri.parse('$_baseUrl/api/ads/serve'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final dynamic decoded = json.decode(response.body);
        final List<dynamic> ads = decoded is List
            ? decoded
            : (decoded is Map ? (decoded['ads'] as List?) ?? [] : []);

        // Categorize fallback ads
        final Map<String, List<Map<String, dynamic>>> categorizedAds = {
          'banner': [],
          'carousel': [],
          'video feed ad': [],
        };

        for (final ad in ads) {
          if (ad is Map<String, dynamic>) {
            final adType = _normalizeAdType(ad['adType']?.toString());
            if (categorizedAds.containsKey(adType)) {
              categorizedAds[adType]!.add(_normalizeAd(ad));
            }
          }
        }

        print('✅ ActiveAdsService: Found fallback ads:');
        print('   Banner: ${categorizedAds['banner']!.length}');
        print('   Carousel: ${categorizedAds['carousel']!.length}');
        print('   Video Feed: ${categorizedAds['video feed ad']!.length}');

        return categorizedAds;
      } else {
        throw Exception('Failed to fetch fallback ads: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ ActiveAdsService: Error fetching fallback ads: $e');
      return {
        'banner': [],
        'carousel': [],
        'video feed ad': [],
      };
    }
  }

  /// **NEW: Normalize ad type for consistent categorization**
  String _normalizeAdType(String? adType) {
    if (adType == null) return 'unknown';
    final normalized = adType.toLowerCase().trim();

    if (normalized.contains('carousel')) return 'carousel';
    if (normalized.contains('video') && normalized.contains('feed')) {
      return 'video feed ad';
    }
    if (normalized.contains('banner')) return 'banner';

    return normalized;
  }
}
