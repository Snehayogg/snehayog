import 'dart:convert';
import 'package:vayug/features/ads/data/carousel_ad_model.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CarouselAdService {
  static String get _baseUrl => AppConfig.baseUrl;
  final AuthService _authService = AuthService();
  
  static const String _kCachedCarouselAdsKey = 'cached_carousel_ads_data';
  static const String _kCachedCarouselAdsTimestampKey = 'cached_carousel_ads_timestamp';

  /// Fetch carousel ads from the backend using multiple endpoints
  /// Try different endpoints to find carousel ads
  Future<List<CarouselAdModel>> fetchCarouselAds() async {
    try {
      AppLogger.log('🎯 CarouselAdService: Fetching carousel ads...');

      // Get base URL with Railway first, local fallback
      final baseUrl = await AppConfig.getBaseUrlWithFallback();
      AppLogger.log('🎯 CarouselAdService: Using base URL: $baseUrl');

      // Try multiple endpoints to find carousel ads
      final endpoints = [
        '$baseUrl/api/ads/carousel', // Direct carousel endpoint
        '$baseUrl/api/ads/serve?adType=carousel', // Serve endpoint with carousel filter
        '$baseUrl/api/ads/serve', // General ads endpoint
      ];

      // Get token for authentication
      final token = (await _authService.getUserData())?['token'];

      for (final endpoint in endpoints) {
        try {
          AppLogger.log('🔍 CarouselAdService: Trying endpoint: $endpoint');

          final response = await httpClientService.get(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
              if (token != null) 'Authorization': 'Bearer $token',
            },
          ).timeout(const Duration(seconds: 10));

          AppLogger.log(
              '🔍 CarouselAdService: Response status: ${response.statusCode}');
          AppLogger.log(
              '🔍 CarouselAdService: Response body: ${response.body}');

          if (response.statusCode == 200) {
            final dynamic decoded = json.decode(response.body);
            List<dynamic> rawAds;

            if (decoded is List) {
              rawAds = decoded;
            } else if (decoded is Map<String, dynamic>) {
              rawAds = (decoded['ads'] as List<dynamic>?) ??
                  (decoded['data'] as List<dynamic>?) ??
                  (decoded['carouselAds'] as List<dynamic>?) ??
                  [];
            } else {
              rawAds = [];
            }

            AppLogger.log(
                '🔍 CarouselAdService: Found ${rawAds.length} raw ads');

            // Filter carousel by adType tolerant of casing/spacing
            // For direct carousel endpoint, all ads are carousel ads
            List<dynamic> filteredAds;
            if (endpoint.contains('/carousel')) {
              filteredAds =
                  rawAds; // All ads from carousel endpoint are carousel ads
              AppLogger.log(
                  '🔍 CarouselAdService: Using all ads from carousel endpoint');
            } else {
              filteredAds = rawAds.where((ad) {
                final type = (ad as Map<String, dynamic>)['adType']
                        ?.toString()
                        .toLowerCase() ??
                    '';
                final isCarousel = type.contains('carousel');
                AppLogger.log('🔍 Ad type: $type, isCarousel: $isCarousel');
                return isCarousel;
              }).toList();
            }

            final carouselAds = filteredAds
                .map((adJson) =>
                    _convertToCarouselAdModel(adJson as Map<String, dynamic>))
                .where((model) => model.slides.isNotEmpty)
                .toList();

            AppLogger.log(
                '✅ CarouselAdService: Found ${carouselAds.length} carousel ads from $endpoint');

            if (carouselAds.isNotEmpty) {
              // **NEW: Cache the successful response**
              _saveCarouselAdsToCache(decoded);
              return carouselAds;
            }
          } else {
            AppLogger.log(
                '❌ Endpoint $endpoint failed with status: ${response.statusCode}');
          }
        } catch (e) {
          AppLogger.log('❌ Error with endpoint $endpoint: $e');
          continue; // Try next endpoint
        }
      }

      AppLogger.log(
          '⚠️ CarouselAdService: No carousel ads found from any endpoint, falling back to cache...');
      return await _loadCachedCarouselAds();
    } catch (e) {
      AppLogger.log('❌ Exception fetching carousel ads: $e, falling back to cache...');
      return await _loadCachedCarouselAds();
    }
  }

  /// **NEW: Save carousel ads to local cache**
  Future<void> _saveCarouselAdsToCache(dynamic adsData) async {
    try {
      if (adsData == null) return;
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kCachedCarouselAdsKey, json.encode(adsData));
      await prefs.setInt(_kCachedCarouselAdsTimestampKey, DateTime.now().millisecondsSinceEpoch);
      AppLogger.log('💾 CarouselAdService: Carousel ads cached successfully');
    } catch (e) {
      AppLogger.log('⚠️ CarouselAdService: Error caching carousel ads: $e');
    }
  }

  /// **NEW: Load carousel ads from local cache**
  Future<List<CarouselAdModel>> _loadCachedCarouselAds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedString = prefs.getString(_kCachedCarouselAdsKey);
      
      if (cachedString == null) {
        AppLogger.log('⚠️ CarouselAdService: No cached carousel ads found');
        return [];
      }

      final dynamic decoded = json.decode(cachedString);
      List<dynamic> rawAds;

      if (decoded is List) {
        rawAds = decoded;
      } else if (decoded is Map<String, dynamic>) {
        rawAds = (decoded['ads'] as List<dynamic>?) ??
            (decoded['data'] as List<dynamic>?) ??
            (decoded['carouselAds'] as List<dynamic>?) ??
            [];
      } else {
        rawAds = [];
      }

      final carouselAds = rawAds
          .map((adJson) =>
              _convertToCarouselAdModel(adJson as Map<String, dynamic>))
          .where((model) => model.slides.isNotEmpty)
          .toList();

      AppLogger.log('✅ CarouselAdService: Loaded ${carouselAds.length} carousel ads from cache');
      return carouselAds;
    } catch (e) {
      AppLogger.log('❌ CarouselAdService: Error loading cached carousel ads: $e');
      return [];
    }
  }

  /// Convert AdCreative to CarouselAdModel
  CarouselAdModel _convertToCarouselAdModel(Map<String, dynamic> adJson) {
    AppLogger.log(
        '🔍 CarouselAdService: Converting ad to carousel model: ${adJson['title']}');

    // Accept either single media fields or an array of slides/media
    final List<CarouselSlide> slides = [];

    // Slides array on adJson
    final dynamic providedSlides =
        adJson['slides'] ?? adJson['media'] ?? adJson['carouselSlides'];
    if (providedSlides is List) {
      AppLogger.log(
          '🔍 CarouselAdService: Found ${providedSlides.length} slides');
      for (final s in providedSlides) {
        if (s is Map<String, dynamic>) {
          final mediaUrl =
              s['mediaUrl'] ?? s['cloudinaryUrl'] ?? s['url'] ?? s['imageUrl'];
          if (mediaUrl != null && mediaUrl.toString().isNotEmpty) {
            slides.add(CarouselSlide(
              id: s['_id']?.toString() ?? s['id']?.toString() ?? 'slide',
              mediaUrl: mediaUrl,
              mediaType: (s['mediaType'] ?? s['type'] ?? 'image').toString(),
              aspectRatio: (s['aspectRatio'] ?? '9:16').toString(),
              title: s['title']?.toString(),
              description: s['description']?.toString(),
              durationSec:
                  s['durationSec'] is int ? s['durationSec'] as int : null,
            ));
            AppLogger.log(
                '🔍 CarouselAdService: Added slide with URL: $mediaUrl');
          }
        }
      }
    }

    // Fallback: single image or video fields
    final imageUrl =
        adJson['imageUrl'] ?? adJson['thumbnailUrl'] ?? adJson['cloudinaryUrl'];
    final videoUrl = adJson['videoUrl'];

    if (slides.isEmpty) {
      AppLogger.log(
          '🔍 CarouselAdService: No slides found, trying fallback single media');

      if (imageUrl != null && imageUrl.toString().isNotEmpty) {
        slides.add(CarouselSlide(
          id: 'slide_image',
          mediaUrl: imageUrl,
          mediaType: 'image',
          aspectRatio: '9:16',
          title: adJson['title']?.toString(),
          description: adJson['description']?.toString(),
        ));
        AppLogger.log(
            '🔍 CarouselAdService: Added fallback image slide: $imageUrl');
      }

      if (videoUrl != null && videoUrl.toString().isNotEmpty) {
        slides.add(CarouselSlide(
          id: 'slide_video',
          mediaUrl: videoUrl,
          mediaType: 'video',
          aspectRatio: '9:16',
          title: adJson['title']?.toString(),
          description: adJson['description']?.toString(),
        ));
        AppLogger.log(
            '🔍 CarouselAdService: Added fallback video slide: $videoUrl');
      }
    }

    AppLogger.log('🔍 CarouselAdService: Final slides count: ${slides.length}');

    final carouselAd = CarouselAdModel(
      id: adJson['_id']?.toString() ?? adJson['id']?.toString() ?? 'unknown',
      campaignId: adJson['campaignId']?.toString() ?? 'unknown',
      advertiserName: adJson['uploaderName']?.toString() ??
          adJson['advertiserName']?.toString() ??
          'Unknown Advertiser',
      advertiserProfilePic: adJson['uploaderProfilePic']?.toString() ??
          adJson['advertiserProfilePic']?.toString() ??
          '',
      slides: slides,
      callToActionLabel:
          adJson['callToActionLabel']?.toString() ?? 'Learn More',
      callToActionUrl: adJson['link']?.toString() ??
          adJson['callToActionUrl']?.toString() ??
          '',
      isActive: (adJson['isActive'] == true) || (adJson['status'] == 'active'),
      impressions:
          (adJson['impressions'] is int) ? adJson['impressions'] as int : 0,
      clicks: (adJson['clicks'] is int) ? adJson['clicks'] as int : 0,
      createdAt: DateTime.tryParse((adJson['createdAt'] ?? '').toString()) ??
          DateTime.now(),
    );

    AppLogger.log(
        '✅ CarouselAdService: Created carousel ad: ${carouselAd.advertiserName} with ${carouselAd.slides.length} slides');
    return carouselAd;
  }

  /// Fetch a single carousel ad by ID
  Future<CarouselAdModel?> fetchCarouselAdById(String adId) async {
    try {
      final response = await httpClientService.get(
        Uri.parse('$_baseUrl/ads/carousel/$adId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return CarouselAdModel.fromJson(data);
      } else {
        AppLogger.log(
            '❌ Error fetching carousel ad $adId: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      AppLogger.log('❌ Exception fetching carousel ad $adId: $e');
      return null;
    }
  }

  /// Track ad impression
  Future<bool> trackImpression(String adId) async {
    try {
      final response = await httpClientService.post(
        Uri.parse('$_baseUrl/ads/carousel/$adId/impression'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({}), // Send empty JSON object to avoid null parsing error
      );

      return response.statusCode == 200;
    } catch (e) {
      AppLogger.log('❌ Exception tracking impression: $e');
      return false;
    }
  }

  /// Track ad click
  Future<bool> trackClick(String adId) async {
    try {
      final response = await httpClientService.post(
        Uri.parse('$_baseUrl/ads/carousel/$adId/click'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({}), // Send empty JSON object to avoid null parsing error
      );

      return response.statusCode == 200;
    } catch (e) {
      AppLogger.log('❌ Exception tracking click: $e');
      return false;
    }
  }

  /// Like carousel ad
  Future<bool> likeAd(String adId, String userId) async {
    try {
      final response = await httpClientService.post(
        Uri.parse('$_baseUrl/ads/carousel/$adId/like'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({'userId': userId}),
      );

      return response.statusCode == 200;
    } catch (e) {
      AppLogger.log('❌ Exception liking ad: $e');
      return false;
    }
  }

  /// Unlike carousel ad
  Future<bool> unlikeAd(String adId, String userId) async {
    try {
      final response = await httpClientService.post(
        Uri.parse('$_baseUrl/ads/carousel/$adId/unlike'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({'userId': userId}),
      );

      return response.statusCode == 200;
    } catch (e) {
      AppLogger.log('❌ Exception unliking ad: $e');
      return false;
    }
  }

  /// Share carousel ad
  Future<bool> shareAd(String adId, String userId) async {
    try {
      final response = await httpClientService.post(
        Uri.parse('$_baseUrl/ads/carousel/$adId/share'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({'userId': userId}),
      );

      return response.statusCode == 200;
    } catch (e) {
      AppLogger.log('❌ Exception sharing ad: $e');
      return false;
    }
  }

  /// Comment on carousel ad
  Future<bool> commentOnAd(String adId, String userId, String comment) async {
    try {
      final response = await httpClientService.post(
        Uri.parse('$_baseUrl/ads/carousel/$adId/comment'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'userId': userId,
          'comment': comment,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      AppLogger.log('❌ Exception commenting on ad: $e');
      return false;
    }
  }
}
