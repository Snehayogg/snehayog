import 'dart:convert';
import 'package:vayu/shared/config/app_config.dart';
import 'package:vayu/shared/managers/smart_cache_manager.dart';
import 'package:vayu/features/ads/data/services/ad_targeting_service.dart';
import 'package:vayu/features/video/video_model.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:vayu/shared/services/http_client_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/features/auth/data/services/authservices.dart';

/// Service to fetch all types of active ads (banner, carousel, video feed)
class ActiveAdsService {
  static String get _baseUrl => AppConfig.baseUrl;
  final SmartCacheManager _cacheManager = SmartCacheManager();
  final AdTargetingService _adTargetingService = AdTargetingService();
  final AuthService _authService = AuthService();
  
  static const String _kCachedAdsKey = 'cached_active_ads_data';
  static const String _kCachedAdsTimestampKey = 'cached_active_ads_timestamp';

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
        AppLogger.log(
            '🎯 ActiveAdsService: Using intelligent targeting for video: ${videoData.id}');
        return await _fetchTargetedAdsForVideo(videoData);
      }

      // **FIX: Use getBaseUrlWithFallback() to try local server first**
      final baseUrl = await AppConfig.getBaseUrlWithFallback();
      AppLogger.log(
          '🎯 ActiveAdsService: Fetching all active ads from $baseUrl/api/ads/serve');

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

      final uri = Uri.parse('$baseUrl/api/ads/serve')
          .replace(queryParameters: queryParams);

      final token = (await _authService.getUserData())?['token'];
      
      final response = await httpClientService.get(uri, headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      });

      AppLogger.log(
          '🔍 ActiveAdsService: Response status: ${response.statusCode}');
      AppLogger.log('🔍 ActiveAdsService: Response body: ${response.body}');

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
          AppLogger.log('🔍 Normalizing ad: ${ad['_id'] ?? ad['id']}');
          AppLogger.log(
              '   Original imageUrl: ${ad['imageUrl'] ?? ad['cloudinaryUrl'] ?? ad['thumbnail']}');
          AppLogger.log(
              '   Normalized imageUrl: ${ensureAbsoluteUrl(imageUrl)}');
          AppLogger.log(
              '   Original link: ${ad['link'] ?? ad['callToAction']}');
          AppLogger.log('   Normalized link: ${ensureAbsoluteUrl(link)}');

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
            AppLogger.log('🔍 ActiveAdsService: Processing ad:');
            AppLogger.log('   Original adType: $originalAdType');
            AppLogger.log('   Normalized adType: $adType');
            AppLogger.log('   Ad keys: ${ad.keys.toList()}');

            if (categorizedAds.containsKey(adType)) {
              categorizedAds[adType]!.add(normalizeAd(ad));
              AppLogger.log('   ✅ Added to $adType category');
            } else {
              AppLogger.log('   ❌ Unknown ad type: $adType');
            }
          }
        }

        AppLogger.log('✅ ActiveAdsService: Found ads:');
        AppLogger.log('   Banner ads: ${categorizedAds['banner']!.length}');
        AppLogger.log('   Carousel ads: ${categorizedAds['carousel']!.length}');
        AppLogger.log(
            '   Video feed ads: ${categorizedAds['video feed ad']!.length}');

        // **DEBUG: Log each banner ad with full details**
        if (categorizedAds['banner']!.isNotEmpty) {
          AppLogger.log('📋 Banner Ads Details:');
          for (int i = 0; i < categorizedAds['banner']!.length; i++) {
            final bannerAd = categorizedAds['banner']![i];
            AppLogger.log('   Banner Ad $i:');
            AppLogger.log('      ID: ${bannerAd['id']}');
            AppLogger.log('      Title: ${bannerAd['title']}');
            AppLogger.log('      AdType: ${bannerAd['adType']}');
            AppLogger.log('      ImageUrl: ${bannerAd['imageUrl']}');
            AppLogger.log('      IsActive: ${bannerAd['isActive']}');
            AppLogger.log('      ReviewStatus: ${bannerAd['reviewStatus']}');
          }
        }

        // **NEW: Cache the successful response**
        await _saveAdsToCache(decoded);

        return categorizedAds;
      } else {
        AppLogger.log('❌ Error fetching active ads: ${response.statusCode}');
        AppLogger.log('Response body: ${response.body}');
        
        // **NEW: Fallback to cached ads on failure**
        AppLogger.log('🔄 ActiveAdsService: Attempting to load cached ads...');
        return await _loadCachedAds();
      }
    } catch (e) {
      AppLogger.log('❌ Exception fetching active ads: $e');
      // **NEW: Fallback to cached ads on exception**
      AppLogger.log('🔄 ActiveAdsService: Attempting to load cached ads...');
      return await _loadCachedAds();
    }
  }

  /// **NEW: Save ads to local cache**
  Future<void> _saveAdsToCache(dynamic adsData) async {
    try {
      // **FIX: Only cache if at least one ad category is present and not empty**
      // This prevents overwriting a 'good' cache with a failed or empty response
      bool hasData = false;
      if (adsData is Map && adsData['ads'] is List) {
        hasData = (adsData['ads'] as List).isNotEmpty;
      } else if (adsData is List) {
        hasData = adsData.isNotEmpty;
      }

      if (!hasData) {
        AppLogger.log('⚠️ ActiveAdsService: Not caching empty or invalid ad data');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCachedAdsKey, json.encode(adsData));
      await prefs.setInt(_kCachedAdsTimestampKey, DateTime.now().millisecondsSinceEpoch);
      AppLogger.log('💾 ActiveAdsService: Ads cached successfully');
    } catch (e) {
      AppLogger.log('⚠️ ActiveAdsService: Error caching ads: $e');
    }
  }

  /// **NEW: Load ads from local cache**
  Future<Map<String, List<Map<String, dynamic>>>> _loadCachedAds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedString = prefs.getString(_kCachedAdsKey);
      
      if (cachedString == null) {
        AppLogger.log('⚠️ ActiveAdsService: No cached ads found');
         return {
          'banner': [],
          'carousel': [],
          'video feed ad': [],
        };
      }

      final timestamp = prefs.getInt(_kCachedAdsTimestampKey);
      if (timestamp != null) {
        final cachedTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
        final age = DateTime.now().difference(cachedTime);
        AppLogger.log('💾 ActiveAdsService: Loaded cached ads (Age: ${age.inMinutes} mins)');
      }

      final dynamic decoded = json.decode(cachedString);
      final List<dynamic> ads = decoded is List
            ? decoded
            : (decoded is Map<String, dynamic>
                ? (decoded['ads'] as List<dynamic>? ?? [])
                : []);

        // Categorize cached ads (reuse logic)
        final Map<String, List<Map<String, dynamic>>> categorizedAds = {
          'banner': [],
          'carousel': [],
          'video feed ad': [],
        };

        // Reuse normalization helpers
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

          if (link.isEmpty && ad['callToAction'] is Map) {
            final nested = (ad['callToAction'] as Map);
            final candidate = nested['url'] ?? nested['link'];
            if (candidate is String && candidate.trim().isNotEmpty) {
              link = candidate.trim();
            }
          }

          return {
            ...ad,
            'imageUrl': ensureAbsoluteUrl(imageUrl),
            'link': ensureAbsoluteUrl(link),
          };
        }

        for (final ad in ads) {
          if (ad is Map<String, dynamic>) {
            final adType = normalizeType(ad['adType']);
            if (categorizedAds.containsKey(adType)) {
              categorizedAds[adType]!.add(normalizeAd(ad));
            }
          }
        }
        
        AppLogger.log('✅ ActiveAdsService: Successfully loaded ${categorizedAds['banner']?.length ?? 0} banner ads from cache');
        return categorizedAds;

    } catch (e) {
      AppLogger.log('❌ ActiveAdsService: Error loading cached ads: $e');
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
      AppLogger.log('📊 ActiveAdsService: Tracking impression for ad: $adId');

      final response = await httpClientService.post(
        Uri.parse('$_baseUrl/api/ads/track-impression/$adId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      AppLogger.log('🔍 Impression tracking response: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      AppLogger.log('❌ Exception tracking impression: $e');
      return false;
    }
  }

  /// Track ad click
  Future<bool> trackClick(String adId, {String? userId}) async {
    try {
      AppLogger.log('🖱️ ActiveAdsService: Tracking click for ad: $adId');

      final response = await httpClientService.post(
        Uri.parse('$_baseUrl/api/ads/track-click/$adId'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'userId': userId,
          'platform': 'mobile',
        }),
      );

      AppLogger.log('🔍 Click tracking response: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      AppLogger.log('❌ Exception tracking click: $e');
      return false;
    }
  }

  /// **NEW: Clear ads cache when ads are deleted**
  Future<void> clearAdsCache() async {
    try {
      AppLogger.log('🧹 ActiveAdsService: Clearing ads cache...');

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
        AppLogger.log('✅ ActiveAdsService: Cleared cache for key: $key');
      }

      AppLogger.log('✅ ActiveAdsService: All ads cache cleared successfully');
    } catch (e) {
      AppLogger.log('⚠️ ActiveAdsService: Error clearing ads cache: $e');
    }
  }

  /// **NEW: Fetch targeted ads for a specific video using intelligent targeting**
  Future<Map<String, List<Map<String, dynamic>>>> _fetchTargetedAdsForVideo(
      VideoModel video) async {
    try {
      AppLogger.log(
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
        AppLogger.log('🎯 Targeting Insights:');
        AppLogger.log('   Video Categories: ${insights['videoCategories']}');
        AppLogger.log('   Video Interests: ${insights['videoInterests']}');
        AppLogger.log('   Targeted Ads: ${insights['targetedAds']}');
        AppLogger.log('   Fallback Ads: ${insights['fallbackAds']}');
      }

      AppLogger.log('✅ ActiveAdsService: Found targeted ads:');
      AppLogger.log('   Banner: ${categorizedAds['banner']!.length}');
      AppLogger.log('   Carousel: ${categorizedAds['carousel']!.length}');
      AppLogger.log(
          '   Video Feed: ${categorizedAds['video feed ad']!.length}');

      return categorizedAds;
    } catch (e) {
      AppLogger.log('❌ ActiveAdsService: Error fetching targeted ads: $e');

      // Fall back to random ads if targeting fails
      AppLogger.log('🔄 ActiveAdsService: Falling back to random ads...');
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
      AppLogger.log('🔄 ActiveAdsService: Fetching fallback ads...');

      // **FIX: Use getBaseUrlWithFallback() to try local server first**
      final baseUrl = await AppConfig.getBaseUrlWithFallback();
      final token = (await _authService.getUserData())?['token'];
      final response = await httpClientService.get(
        Uri.parse('$baseUrl/api/ads/serve'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
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

        AppLogger.log('✅ ActiveAdsService: Found fallback ads:');
        AppLogger.log('   Banner: ${categorizedAds['banner']!.length}');
        AppLogger.log('   Carousel: ${categorizedAds['carousel']!.length}');
        AppLogger.log(
            '   Video Feed: ${categorizedAds['video feed ad']!.length}');

        return categorizedAds;
      } else {
        throw Exception('Failed to fetch fallback ads: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.log('❌ ActiveAdsService: Error fetching fallback ads: $e');
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
