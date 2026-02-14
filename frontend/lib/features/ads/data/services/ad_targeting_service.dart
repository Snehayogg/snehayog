import 'dart:convert';
import 'package:vayu/shared/config/app_config.dart';
import 'package:vayu/shared/managers/smart_cache_manager.dart';
import 'package:vayu/features/video/video_model.dart';
import 'package:vayu/shared/services/http_client_service.dart';

import 'package:vayu/features/auth/data/services/authservices.dart';

/// Service for intelligent ad targeting based on video content
class AdTargetingService {
  static String get _baseUrl => AppConfig.baseUrl;
  final SmartCacheManager _cacheManager = SmartCacheManager();
  final AuthService _authService = AuthService();

  /// Get targeted ads for a specific video
  /// Analyzes video content and returns best-matching ads
  Future<Map<String, dynamic>> getTargetedAdsForVideo({
    required VideoModel video,
    int limit = 3,
    bool useFallback = true,
    String adType = 'banner',
  }) async {
    try {
      // Create cache key for this video
      // **FIX: Force refresh to prevent stale targeting**
      // Always fetch fresh ads to ensure proper per-video targeting
      // Cache was causing sequential ad display instead of targeted ads
      // Prepare video data for backend using available fields
      final videoData = {
        'id': video.id,
        'videoName': video.videoName,
        'description':
            video.description ?? '', // Keep for backward compatibility
        'videoType': video.videoType,
        'category': _extractCategoryFromVideo(video),
        'tags': _extractTagsFromVideo(video),
        'keywords': _extractKeywordsFromVideo(video),
      };

      // Call backend targeting endpoint

      final url = '$_baseUrl/api/ads/targeting/targeted-for-video';

      final token = (await _authService.getUserData())?['token'];

      final response = await httpClientService.post(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'videoData': videoData,
          'limit': limit,
          'useFallback': useFallback,
          'adType': adType,
        }),
      );





      if (response.statusCode == 200) {
        final result = json.decode(response.body) as Map<String, dynamic>;

        // **FIX: Don't cache targeted ads to prevent stale targeting**
        // Caching was causing ads to not refresh based on video content



        // Log which ads were returned for debugging


        return result;
      } else {

        throw Exception('Failed to get targeted ads: ${response.statusCode}');
      }
    } catch (e) {


      // Return fallback result
      return {
        'success': false,
        'ads': [],
        'insights': {
          'videoCategories': [],
          'videoInterests': [],
          'targetedAds': 0,
          'fallbackAds': 0,
          'error': e.toString(),
        },
        'isFallback': true,
      };
    }
  }

  /// Get targeted ads by categories and interests
  Future<Map<String, dynamic>> getTargetedAdsByCategory({
    required List<String> categories,
    int limit = 3,
    String adType = 'banner',
  }) async {
    try {
      print(
          '🎯 AdTargetingService: Getting targeted ads for categories: $categories');

      final token = (await _authService.getUserData())?['token'];

      final response = await httpClientService.post(
        Uri.parse('$_baseUrl/api/ads/targeting/targeted'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'categories': categories,
          'limit': limit,
          'targetingType': 'category',
          'adType': adType,
          'useFallback': true,
        }),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body) as Map<String, dynamic>;
        print(
            '✅ AdTargetingService: Found ${result['ads']?.length ?? 0} category-targeted ads');
        return result;
      } else {
        throw Exception(
            'Failed to get category-targeted ads: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ AdTargetingService: Error getting category-targeted ads: $e');
      return {
        'success': false,
        'ads': [],
        'totalAds': 0,
        'isFallback': true,
      };
    }
  }

  /// Get targeted ads by interests
  Future<Map<String, dynamic>> getTargetedAdsByInterests({
    required List<String> interests,
    int limit = 3,
    String adType = 'banner',
  }) async {
    try {
      print(
          '🎯 AdTargetingService: Getting targeted ads for interests: $interests');

      final token = (await _authService.getUserData())?['token'];

      final response = await httpClientService.post(
        Uri.parse('$_baseUrl/api/ads/targeting/targeted'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'interests': interests,
          'limit': limit,
          'targetingType': 'interest',
          'adType': adType,
          'useFallback': true,
        }),
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body) as Map<String, dynamic>;
        print(
            '✅ AdTargetingService: Found ${result['ads']?.length ?? 0} interest-targeted ads');
        return result;
      } else {
        throw Exception(
            'Failed to get interest-targeted ads: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ AdTargetingService: Error getting interest-targeted ads: $e');
      return {
        'success': false,
        'ads': [],
        'totalAds': 0,
        'isFallback': true,
      };
    }
  }

  /// Get fallback ads when targeting fails
  Future<Map<String, dynamic>> getFallbackAds({
    int limit = 3,
    String adType = 'banner',
  }) async {
    try {
      print('🔄 AdTargetingService: Getting fallback ads...');

      final token = (await _authService.getUserData())?['token'];

      final response = await httpClientService.get(
        Uri.parse(
            '$_baseUrl/api/ads/targeting/fallback?limit=$limit&adType=$adType'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body) as Map<String, dynamic>;
        print(
            '✅ AdTargetingService: Found ${result['ads']?.length ?? 0} fallback ads');
        return result;
      } else {
        throw Exception('Failed to get fallback ads: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ AdTargetingService: Error getting fallback ads: $e');
      return {
        'success': false,
        'ads': [],
        'totalAds': 0,
        'isFallback': true,
      };
    }
  }

  /// Get targeting categories available in the system
  Future<List<String>> getTargetingCategories() async {
    try {
      final token = (await _authService.getUserData())?['token'];

      final response = await httpClientService.get(
        Uri.parse('$_baseUrl/api/ads/targeting/categories'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body) as Map<String, dynamic>;
        final categories =
            (result['categories'] as List<dynamic>?)?.cast<String>() ?? [];
        print(
            '✅ AdTargetingService: Found ${categories.length} targeting categories');
        return categories;
      } else {
        throw Exception(
            'Failed to get targeting categories: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ AdTargetingService: Error getting targeting categories: $e');
      return [];
    }
  }

  /// Get targeting interests available in the system
  Future<List<String>> getTargetingInterests() async {
    try {
      final token = (await _authService.getUserData())?['token'];

      final response = await httpClientService.get(
        Uri.parse('$_baseUrl/api/ads/targeting/interests'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final result = json.decode(response.body) as Map<String, dynamic>;
        final interests =
            (result['interests'] as List<dynamic>?)?.cast<String>() ?? [];
        print(
            '✅ AdTargetingService: Found ${interests.length} targeting interests');
        return interests;
      } else {
        throw Exception(
            'Failed to get targeting interests: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ AdTargetingService: Error getting targeting interests: $e');
      return [];
    }
  }

  /// Clear targeting cache for a specific video
  Future<void> clearTargetingCache(String videoId) async {
    try {
      print(
          '🧹 AdTargetingService: Clearing targeting cache for video: $videoId');

      final cacheKeys = [
        'targeted_ads_${videoId}_banner',
        'targeted_ads_${videoId}_carousel',
        'targeted_ads_${videoId}_video feed ad',
      ];

      for (final key in cacheKeys) {
        await _cacheManager.get(
          key,
          fetchFn: () async => null as dynamic,
          cacheType: 'targeting',
          maxAge: Duration.zero,
          forceRefresh: true,
        );
      }

      print(
          '✅ AdTargetingService: Cleared targeting cache for video: $videoId');
    } catch (e) {
      print('⚠️ AdTargetingService: Error clearing targeting cache: $e');
    }
  }

  /// Clear all targeting cache
  Future<void> clearAllTargetingCache() async {
    try {
      print('🧹 AdTargetingService: Clearing all targeting cache...');

      // Clear all targeting-related cache entries
      final cacheKeys = [
        'targeting_categories',
        'targeting_interests',
        'targeted_ads_',
      ];

      for (final key in cacheKeys) {
        await _cacheManager.get(
          key,
          fetchFn: () async => null as dynamic,
          cacheType: 'targeting',
          maxAge: Duration.zero,
          forceRefresh: true,
        );
      }

      print('✅ AdTargetingService: Cleared all targeting cache');
    } catch (e) {
      print('⚠️ AdTargetingService: Error clearing all targeting cache: $e');
    }
  }

  /// **NEW: Extract category from video data**
  String _extractCategoryFromVideo(VideoModel video) {
    // Try to extract category from video name and type
    final videoName = video.videoName.toLowerCase();
    final videoType = video.videoType.toLowerCase();

    // Category mapping based on video name keywords
    if (videoName.contains('yoga') ||
        videoName.contains('meditation') ||
        videoName.contains('stretch') ||
        videoName.contains('breath')) {
      return 'yoga';
    }
    if (videoName.contains('fitness') ||
        videoName.contains('workout') ||
        videoName.contains('exercise') ||
        videoName.contains('gym')) {
      return 'fitness';
    }
    if (videoName.contains('cook') ||
        videoName.contains('recipe') ||
        videoName.contains('food') ||
        videoName.contains('kitchen')) {
      return 'cooking';
    }
    if (videoName.contains('dance') ||
        videoName.contains('music') ||
        videoName.contains('song') ||
        videoName.contains('dance')) {
      return 'entertainment';
    }
    // **UPDATED: Consolidated education category includes all academic subjects**
    if (videoName.contains('education') ||
        videoName.contains('learn') ||
        videoName.contains('tutorial') ||
        videoName.contains('course') ||
        videoName.contains('physics') ||
        videoName.contains('chemistry') ||
        videoName.contains('biology') ||
        videoName.contains('math') ||
        videoName.contains('science') ||
        videoName.contains('history') ||
        videoName.contains('geography') ||
        videoName.contains('english') ||
        videoName.contains('language') ||
        videoName.contains('study') ||
        videoName.contains('academic') ||
        videoName.contains('school') ||
        videoName.contains('college') ||
        videoName.contains('university')) {
      return 'education';
    }
    if (videoName.contains('travel') ||
        videoName.contains('tourism') ||
        videoName.contains('place') ||
        videoName.contains('visit')) {
      return 'travel';
    }
    if (videoName.contains('fashion') ||
        videoName.contains('beauty') ||
        videoName.contains('style') ||
        videoName.contains('makeup')) {
      return 'lifestyle';
    }
    if (videoName.contains('tech') ||
        videoName.contains('gadget') ||
        videoName.contains('phone') ||
        videoName.contains('computer')) {
      return 'technology';
    }
    if (videoName.contains('business') ||
        videoName.contains('money') ||
        videoName.contains('finance') ||
        videoName.contains('career') ||
        videoName.contains('trading') ||
        videoName.contains('stock') ||
        videoName.contains('investment') ||
        videoName.contains('crypto')) {
      return 'business';
    }
    if (videoName.contains('sport') ||
        videoName.contains('game') ||
        videoName.contains('football') ||
        videoName.contains('cricket')) {
      return 'sports';
    }

    // Default based on video type
    if (videoType == 'yog') return 'yoga';
    if (videoType == 'fitness') return 'fitness';
    if (videoType == 'cooking') return 'cooking';

    return 'others'; // Default fallback
  }

  /// **NEW: Extract tags from video data**
  List<String> _extractTagsFromVideo(VideoModel video) {
    final tags = <String>[];
    final videoName = video.videoName.toLowerCase();

    // Extract tags based on video name keywords
    final tagKeywords = {
      'yoga': ['yoga', 'meditation', 'stretch', 'breath', 'mindfulness', 'zen'],
      'fitness': [
        'fitness',
        'workout',
        'exercise',
        'gym',
        'cardio',
        'strength'
      ],
      'cooking': ['cook', 'recipe', 'food', 'kitchen', 'chef', 'baking'],
      'entertainment': ['dance', 'music', 'song', 'fun', 'comedy', 'party'],
      'education': ['learn', 'tutorial', 'course', 'study', 'knowledge'],
      'travel': ['travel', 'tourism', 'place', 'visit', 'adventure'],
      'lifestyle': ['fashion', 'beauty', 'style', 'makeup', 'tips'],
      'technology': ['tech', 'gadget', 'phone', 'computer', 'app'],
      'business': [
        'business',
        'money',
        'finance',
        'career',
        'startup',
        'trading',
        'stock',
        'investment',
        'crypto'
      ],
      'sports': ['sport', 'game', 'football', 'cricket', 'athlete'],
    };

    for (final category in tagKeywords.keys) {
      for (final keyword in tagKeywords[category]!) {
        if (videoName.contains(keyword)) {
          tags.add(category);
          break; // Add category only once
        }
      }
    }

    // Add video type as tag
    if (video.videoType.isNotEmpty) {
      tags.add(video.videoType.toLowerCase());
    }

    return tags.toSet().toList(); // Remove duplicates
  }

  /// **NEW: Extract keywords from video data**
  List<String> _extractKeywordsFromVideo(VideoModel video) {
    final keywords = <String>[];
    final videoName = video.videoName.toLowerCase();

    // Split video name into words and filter meaningful keywords
    final words = videoName
        .split(RegExp(r'[\s\-_]+'))
        .where((word) => word.length > 2) // Filter out short words
        .where((word) => !_isCommonWord(word)) // Filter out common words
        .toList();

    keywords.addAll(words);

    // Add video type as keyword
    if (video.videoType.isNotEmpty) {
      keywords.add(video.videoType.toLowerCase());
    }

    return keywords.toSet().toList(); // Remove duplicates
  }

  /// **NEW: Check if word is a common word (to filter out)**
  bool _isCommonWord(String word) {
    const commonWords = {
      'the',
      'and',
      'or',
      'but',
      'in',
      'on',
      'at',
      'to',
      'for',
      'of',
      'with',
      'by',
      'from',
      'up',
      'about',
      'into',
      'through',
      'during',
      'before',
      'after',
      'above',
      'below',
      'between',
      'among',
      'this',
      'that',
      'these',
      'those',
      'i',
      'you',
      'he',
      'she',
      'it',
      'we',
      'they',
      'me',
      'him',
      'her',
      'us',
      'them',
      'my',
      'your',
      'his',
      'its',
      'our',
      'their',
      'a',
      'an',
      'is',
      'are',
      'was',
      'were',
      'be',
      'been',
      'being',
      'have',
      'has',
      'had',
      'do',
      'does',
      'did',
      'will',
      'would',
      'could',
      'should',
      'may',
      'might',
      'must',
      'can',
      'shall',
      'how',
      'what',
      'when',
      'where',
      'why',
      'who',
      'which',
      'all',
      'any',
      'both',
      'each',
      'few',
      'more',
      'most',
      'other',
      'some',
      'such',
      'no',
      'nor',
      'not',
      'only',
      'own',
      'same',
      'so',
      'than',
      'too',
      'very',
      'just',
      'now',
      'here',
      'there',
      'then',
      'also',
      'back',
      'down',
      'off',
      'out',
      'over',
      'under',
      'again',
      'further',
      'once'
    };

    return commonWords.contains(word.toLowerCase());
  }
}
