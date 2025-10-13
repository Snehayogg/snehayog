import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:snehayog/model/carousel_ad_model.dart';
import 'package:snehayog/config/app_config.dart';

class CarouselAdService {
  static String get _baseUrl => AppConfig.baseUrl;

  /// Fetch carousel ads from the backend using multiple endpoints
  /// Try different endpoints to find carousel ads
  Future<List<CarouselAdModel>> fetchCarouselAds() async {
    try {
      print('🎯 CarouselAdService: Fetching carousel ads...');

      // Try multiple endpoints to find carousel ads
      final endpoints = [
        '$_baseUrl/api/ads/carousel', // Direct carousel endpoint
        '$_baseUrl/api/ads/serve?adType=carousel ads', // With space as backend expects
        '$_baseUrl/api/ads/serve?adType=carousel',
        '$_baseUrl/api/ads/active',
      ];

      for (final endpoint in endpoints) {
        try {
          print('🔍 CarouselAdService: Trying endpoint: $endpoint');

          final response = await http.get(
            Uri.parse(endpoint),
            headers: {
              'Content-Type': 'application/json',
            },
          ).timeout(const Duration(seconds: 10));

          print(
              '🔍 CarouselAdService: Response status: ${response.statusCode}');
          print('🔍 CarouselAdService: Response body: ${response.body}');

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

            print('🔍 CarouselAdService: Found ${rawAds.length} raw ads');

            // Filter carousel by adType tolerant of casing/spacing
            // For direct carousel endpoint, all ads are carousel ads
            List<dynamic> filteredAds;
            if (endpoint.contains('/carousel')) {
              filteredAds =
                  rawAds; // All ads from carousel endpoint are carousel ads
              print(
                  '🔍 CarouselAdService: Using all ads from carousel endpoint');
            } else {
              filteredAds = rawAds.where((ad) {
                final type = (ad as Map<String, dynamic>)['adType']
                        ?.toString()
                        .toLowerCase() ??
                    '';
                final isCarousel = type.contains('carousel');
                print('🔍 Ad type: $type, isCarousel: $isCarousel');
                return isCarousel;
              }).toList();
            }

            final carouselAds = filteredAds
                .map((adJson) =>
                    _convertToCarouselAdModel(adJson as Map<String, dynamic>))
                .where((model) => model.slides.isNotEmpty)
                .toList();

            print(
                '✅ CarouselAdService: Found ${carouselAds.length} carousel ads from $endpoint');

            if (carouselAds.isNotEmpty) {
              return carouselAds;
            }
          } else {
            print(
                '❌ Endpoint $endpoint failed with status: ${response.statusCode}');
          }
        } catch (e) {
          print('❌ Error with endpoint $endpoint: $e');
          continue; // Try next endpoint
        }
      }

      print('⚠️ CarouselAdService: No carousel ads found from any endpoint');
      return [];
    } catch (e) {
      print('❌ Exception fetching carousel ads: $e');
      return [];
    }
  }

  /// Convert AdCreative to CarouselAdModel
  CarouselAdModel _convertToCarouselAdModel(Map<String, dynamic> adJson) {
    print(
        '🔍 CarouselAdService: Converting ad to carousel model: ${adJson['title']}');

    // Accept either single media fields or an array of slides/media
    final List<CarouselSlide> slides = [];

    // Slides array on adJson
    final dynamic providedSlides =
        adJson['slides'] ?? adJson['media'] ?? adJson['carouselSlides'];
    if (providedSlides is List) {
      print('🔍 CarouselAdService: Found ${providedSlides.length} slides');
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
            print('🔍 CarouselAdService: Added slide with URL: $mediaUrl');
          }
        }
      }
    }

    // Fallback: single image or video fields
    final imageUrl =
        adJson['imageUrl'] ?? adJson['thumbnailUrl'] ?? adJson['cloudinaryUrl'];
    final videoUrl = adJson['videoUrl'];

    if (slides.isEmpty) {
      print(
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
        print('🔍 CarouselAdService: Added fallback image slide: $imageUrl');
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
        print('🔍 CarouselAdService: Added fallback video slide: $videoUrl');
      }
    }

    print('🔍 CarouselAdService: Final slides count: ${slides.length}');

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

    print(
        '✅ CarouselAdService: Created carousel ad: ${carouselAd.advertiserName} with ${carouselAd.slides.length} slides');
    return carouselAd;
  }

  /// Fetch a single carousel ad by ID
  Future<CarouselAdModel?> fetchCarouselAdById(String adId) async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/ads/carousel/$adId'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return CarouselAdModel.fromJson(data);
      } else {
        print('❌ Error fetching carousel ad $adId: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ Exception fetching carousel ad $adId: $e');
      return null;
    }
  }

  /// Track ad impression
  Future<bool> trackImpression(String adId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/ads/carousel/$adId/impression'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      print('❌ Exception tracking impression: $e');
      return false;
    }
  }

  /// Track ad click
  Future<bool> trackClick(String adId) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/ads/carousel/$adId/click'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      return response.statusCode == 200;
    } catch (e) {
      print('❌ Exception tracking click: $e');
      return false;
    }
  }
}
