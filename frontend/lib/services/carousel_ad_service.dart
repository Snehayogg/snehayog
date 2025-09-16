import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:snehayog/model/carousel_ad_model.dart';

class CarouselAdService {
  static const String _baseUrl = 'http://192.168.0.190:5001/api';

  /// Fetch carousel ads from the backend
  Future<List<CarouselAdModel>> fetchCarouselAds() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/ads/carousel'),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => CarouselAdModel.fromJson(json)).toList();
      } else {
        print('❌ Error fetching carousel ads: ${response.statusCode}');
        print('Response body: ${response.body}');
        return [];
      }
    } catch (e) {
      print('❌ Exception fetching carousel ads: $e');
      return [];
    }
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

  /// Get dummy carousel ad for testing (matching the image)
  CarouselAdModel getDummyCarouselAd() {
    return CarouselAdModel(
      id: 'dummy_carousel_ad_001',
      campaignId: 'dummy_campaign_001',
      advertiserName: 'Sanjeev Yadav',
      advertiserProfilePic:
          'https://via.placeholder.com/150/4CAF50/FFFFFF?text=SY',
      slides: [
        CarouselSlide(
          id: 'slide_1',
          mediaUrl:
              'https://via.placeholder.com/400x800/424242/FFFFFF?text=Amazing+Product',
          mediaType: 'image',
          aspectRatio: '9:16',
          title: 'Amazing Product',
          description:
              'amazing product that will change your life!\nbest way earn profits in share market',
        ),
        CarouselSlide(
          id: 'slide_2',
          mediaUrl:
              'https://via.placeholder.com/400x800/2196F3/FFFFFF?text=Special+Features',
          mediaType: 'image',
          aspectRatio: '9:16',
          title: 'Special Features',
          description:
              'Learn about the special features that make us unique and profitable.',
        ),
        CarouselSlide(
          id: 'slide_3',
          mediaUrl:
              'https://via.placeholder.com/400x800/FF9800/FFFFFF?text=Customer+Reviews',
          mediaType: 'image',
          aspectRatio: '9:16',
          title: 'Customer Reviews',
          description:
              'See what our happy customers are saying about us and their profits.',
        ),
      ],
      callToActionLabel: 'Visit Now >',
      callToActionUrl: 'https://example.com',
      isActive: true,
      createdAt: DateTime.now(),
      impressions: 0,
      clicks: 0,
    );
  }
}
