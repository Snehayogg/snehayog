import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/config/app_config.dart';

/// **AD TARGETING SERVICE**
/// Handles intelligent ad-video matching based on interests and categories
/// with fallback system for limited content
class AdTargetingService {
  final String _baseUrl = AppConfig.baseUrl;

  // **TARGETING CATEGORIES**
  static const Map<String, List<String>> _categoryMapping = {
    'yoga': [
      'yoga',
      'meditation',
      'wellness',
      'fitness',
      'mindfulness',
      'spiritual',
      'health'
    ],
    'fitness': [
      'fitness',
      'workout',
      'exercise',
      'gym',
      'training',
      'strength',
      'cardio'
    ],
    'cooking': [
      'cooking',
      'recipe',
      'food',
      'kitchen',
      'chef',
      'baking',
      'nutrition'
    ],
    'education': [
      'education',
      'learning',
      'tutorial',
      'course',
      'study',
      'knowledge',
      'skill'
    ],
    'entertainment': [
      'entertainment',
      'fun',
      'comedy',
      'music',
      'dance',
      'art',
      'creative'
    ],
    'lifestyle': [
      'lifestyle',
      'fashion',
      'beauty',
      'travel',
      'home',
      'decor',
      'tips'
    ],
    'technology': [
      'technology',
      'tech',
      'gadgets',
      'software',
      'programming',
      'innovation'
    ],
    'business': [
      'business',
      'entrepreneur',
      'finance',
      'marketing',
      'startup',
      'career'
    ],
    'sports': [
      'sports',
      'football',
      'cricket',
      'basketball',
      'tennis',
      'athletics'
    ],
    'travel': [
      'travel',
      'tourism',
      'adventure',
      'exploration',
      'vacation',
      'places'
    ],
  };

  // **INTEREST KEYWORDS**
  static const Map<String, List<String>> _interestKeywords = {
    'health_wellness': [
      'health',
      'wellness',
      'medical',
      'doctor',
      'hospital',
      'medicine',
      'therapy'
    ],
    'fitness_sports': [
      'fitness',
      'sports',
      'gym',
      'workout',
      'training',
      'athlete',
      'exercise'
    ],
    'food_cooking': [
      'food',
      'cooking',
      'recipe',
      'restaurant',
      'chef',
      'kitchen',
      'nutrition'
    ],
    'education_learning': [
      'education',
      'school',
      'college',
      'university',
      'learning',
      'study',
      'course'
    ],
    'entertainment_media': [
      'entertainment',
      'movie',
      'music',
      'dance',
      'comedy',
      'fun',
      'party'
    ],
    'technology_gadgets': [
      'technology',
      'tech',
      'gadgets',
      'smartphone',
      'computer',
      'software'
    ],
    'fashion_beauty': [
      'fashion',
      'beauty',
      'style',
      'makeup',
      'clothing',
      'shopping',
      'trends'
    ],
    'travel_tourism': [
      'travel',
      'tourism',
      'vacation',
      'adventure',
      'exploration',
      'places'
    ],
    'business_finance': [
      'business',
      'finance',
      'money',
      'investment',
      'entrepreneur',
      'startup'
    ],
    'lifestyle_home': [
      'lifestyle',
      'home',
      'decor',
      'interior',
      'family',
      'parenting',
      'tips'
    ],
  };

  /// **GET TARGETED ADS FOR VIDEO**
  /// Returns ads that match the video's category and interests
  Future<List<Map<String, dynamic>>> getTargetedAdsForVideo(
    VideoModel video, {
    int limit = 3,
    bool useFallback = true,
  }) async {
    try {
      print(
          '🎯 AdTargetingService: Getting targeted ads for video: ${video.id}');

      // Extract video categories and interests
      final videoCategories = _extractVideoCategories(video);
      final videoInterests = _extractVideoInterests(video);

      print('🎯 Video categories: $videoCategories');
      print('🎯 Video interests: $videoInterests');

      // Try to get targeted ads first
      final targetedAds = await _getTargetedAds(
        categories: videoCategories,
        interests: videoInterests,
        limit: limit,
      );

      if (targetedAds.isNotEmpty) {
        print('✅ Found ${targetedAds.length} targeted ads');
        return targetedAds;
      }

      // Fallback: Get any available ads if no targeted ads found
      if (useFallback) {
        print('🔄 No targeted ads found, using fallback system');
        final fallbackAds = await _getFallbackAds(limit: limit);
        print('✅ Found ${fallbackAds.length} fallback ads');
        return fallbackAds;
      }

      return [];
    } catch (e) {
      print('❌ Error getting targeted ads: $e');
      return [];
    }
  }

  /// **GET TARGETED ADS BY CATEGORY**
  /// Returns ads that match specific categories
  Future<List<Map<String, dynamic>>> getTargetedAdsByCategory(
    List<String> categories, {
    int limit = 5,
  }) async {
    try {
      print('🎯 Getting targeted ads for categories: $categories');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/ads/targeted'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'categories': categories,
          'limit': limit,
          'targetingType': 'category',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['ads'] ?? []);
      }

      return [];
    } catch (e) {
      print('❌ Error getting targeted ads by category: $e');
      return [];
    }
  }

  /// **GET TARGETED ADS BY INTERESTS**
  /// Returns ads that match specific interests
  Future<List<Map<String, dynamic>>> getTargetedAdsByInterests(
    List<String> interests, {
    int limit = 5,
  }) async {
    try {
      print('🎯 Getting targeted ads for interests: $interests');

      final response = await http.post(
        Uri.parse('$_baseUrl/api/ads/targeted'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'interests': interests,
          'limit': limit,
          'targetingType': 'interest',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['ads'] ?? []);
      }

      return [];
    } catch (e) {
      print('❌ Error getting targeted ads by interests: $e');
      return [];
    }
  }

  /// **EXTRACT VIDEO CATEGORIES**
  /// Analyzes video content to determine categories
  List<String> _extractVideoCategories(VideoModel video) {
    final categories = <String>[];

    // Analyze video name
    final videoName = video.videoName.toLowerCase();
    for (final category in _categoryMapping.keys) {
      if (_categoryMapping[category]!
          .any((keyword) => videoName.contains(keyword.toLowerCase()))) {
        categories.add(category);
      }
    }

    // Analyze description
    if (video.description != null) {
      final description = video.description!.toLowerCase();
      for (final category in _categoryMapping.keys) {
        if (_categoryMapping[category]!
            .any((keyword) => description.contains(keyword.toLowerCase()))) {
          if (!categories.contains(category)) {
            categories.add(category);
          }
        }
      }
    }

    // Default to 'entertainment' if no categories found
    if (categories.isEmpty) {
      categories.add('entertainment');
    }

    return categories;
  }

  /// **EXTRACT VIDEO INTERESTS**
  /// Analyzes video content to determine interests
  List<String> _extractVideoInterests(VideoModel video) {
    final interests = <String>[];

    // Analyze video name
    final videoName = video.videoName.toLowerCase();
    for (final interest in _interestKeywords.keys) {
      if (_interestKeywords[interest]!
          .any((keyword) => videoName.contains(keyword.toLowerCase()))) {
        interests.add(interest);
      }
    }

    // Analyze description
    if (video.description != null) {
      final description = video.description!.toLowerCase();
      for (final interest in _interestKeywords.keys) {
        if (_interestKeywords[interest]!
            .any((keyword) => description.contains(keyword.toLowerCase()))) {
          if (!interests.contains(interest)) {
            interests.add(interest);
          }
        }
      }
    }

    // Default to 'entertainment_media' if no interests found
    if (interests.isEmpty) {
      interests.add('entertainment_media');
    }

    return interests;
  }

  /// **GET TARGETED ADS**
  /// Fetches ads that match the specified categories and interests
  Future<List<Map<String, dynamic>>> _getTargetedAds({
    required List<String> categories,
    required List<String> interests,
    required int limit,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/ads/targeted'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'categories': categories,
          'interests': interests,
          'limit': limit,
          'targetingType': 'both',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['ads'] ?? []);
      }

      return [];
    } catch (e) {
      print('❌ Error getting targeted ads: $e');
      return [];
    }
  }

  /// **GET FALLBACK ADS**
  /// Returns any available ads when no targeted ads are found
  Future<List<Map<String, dynamic>>> _getFallbackAds({
    required int limit,
  }) async {
    try {
      print('🔄 Getting fallback ads...');

      final response = await http.get(
        Uri.parse('$_baseUrl/api/ads/fallback?limit=$limit'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return List<Map<String, dynamic>>.from(data['ads'] ?? []);
      }

      return [];
    } catch (e) {
      print('❌ Error getting fallback ads: $e');
      return [];
    }
  }

  /// **GET AD TARGETING SCORE**
  /// Calculates how well an ad matches a video (0-100)
  double getTargetingScore(
    Map<String, dynamic> ad,
    VideoModel video,
  ) {
    final videoCategories = _extractVideoCategories(video);
    final videoInterests = _extractVideoInterests(video);

    double score = 0.0;

    // Check category match (40% weight)
    final adCategories = List<String>.from(ad['categories'] ?? []);
    final categoryMatches =
        videoCategories.where((cat) => adCategories.contains(cat)).length;
    score += (categoryMatches / videoCategories.length) * 40;

    // Check interest match (40% weight)
    final adInterests = List<String>.from(ad['interests'] ?? []);
    final interestMatches = videoInterests
        .where((interest) => adInterests.contains(interest))
        .length;
    score += (interestMatches / videoInterests.length) * 40;

    // Check ad performance (20% weight)
    final impressions = ad['impressions'] ?? 0;
    final clicks = ad['clicks'] ?? 0;
    final ctr = impressions > 0 ? (clicks / impressions) * 100 : 0;
    score += (ctr / 10) * 20; // Normalize CTR to 0-20

    return score.clamp(0.0, 100.0);
  }

  /// **GET TARGETING INSIGHTS**
  /// Returns insights about ad-video matching
  Map<String, dynamic> getTargetingInsights(
    List<Map<String, dynamic>> ads,
    VideoModel video,
  ) {
    final videoCategories = _extractVideoCategories(video);
    final videoInterests = _extractVideoInterests(video);

    final insights = <String, dynamic>{
      'videoCategories': videoCategories,
      'videoInterests': videoInterests,
      'totalAds': ads.length,
      'targetedAds': 0,
      'fallbackAds': 0,
      'averageScore': 0.0,
      'topCategories': <String, int>{},
      'topInterests': <String, int>{},
    };

    if (ads.isEmpty) return insights;

    double totalScore = 0.0;

    for (final ad in ads) {
      final score = getTargetingScore(ad, video);
      totalScore += score;

      if (score > 50) {
        insights['targetedAds']++;
      } else {
        insights['fallbackAds']++;
      }

      // Count categories and interests
      final adCategories = List<String>.from(ad['categories'] ?? []);
      final adInterests = List<String>.from(ad['interests'] ?? []);

      for (final category in adCategories) {
        insights['topCategories'][category] =
            (insights['topCategories'][category] ?? 0) + 1;
      }

      for (final interest in adInterests) {
        insights['topInterests'][interest] =
            (insights['topInterests'][interest] ?? 0) + 1;
      }
    }

    insights['averageScore'] = totalScore / ads.length;

    return insights;
  }
}
