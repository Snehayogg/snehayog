import 'dart:convert';

import 'package:vayu/shared/services/http_client_service.dart';
import 'package:vayu/shared/config/app_config.dart';
import 'package:vayu/features/video/video_model.dart';
import 'package:vayu/features/auth/data/usermodel.dart';
import 'package:vayu/shared/utils/app_logger.dart';

/// Simple search service to search videos and creators.
class SearchService {
  // **FIX: Cache base URL to avoid repeated network checks**
  String? _cachedBaseUrl;

  SearchService();

  // **FIX: Get base URL with caching**
  Future<String> _getBaseUrl() async {
    if (_cachedBaseUrl != null) {
      return _cachedBaseUrl!;
    }
    _cachedBaseUrl = await AppConfig.getBaseUrlWithFallback();
    return _cachedBaseUrl!;
  }

  Future<List<VideoModel>> searchVideos(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    // **FIX: Use cached base URL**
    final baseUrl = await _getBaseUrl();
    final uri = Uri.parse('$baseUrl/api/search/videos').replace(
      queryParameters: <String, String>{
        'q': trimmed,
        'limit': '20',
      },
    );

    AppLogger.log('🔍 SearchService: searchVideos q="$trimmed" url=$uri');

    try {
      final res = await httpClientService.get(
        uri,
        headers: const {'Content-Type': 'application/json'},
        timeout: const Duration(seconds: 10),
      );

      AppLogger.log(
        '📡 SearchService: searchVideos response status=${res.statusCode}',
      );

      if (res.statusCode != 200) {
        AppLogger.log(
          '❌ SearchService: searchVideos failed '
          'status=${res.statusCode} body=${res.body}',
        );
        // Fail gracefully: return empty list instead of throwing
        return <VideoModel>[];
      }

      final Map<String, dynamic> data =
          json.decode(res.body) as Map<String, dynamic>;
      final List<dynamic> list =
          data['videos'] as List<dynamic>? ?? <dynamic>[];

      AppLogger.log(
        '✅ SearchService: searchVideos found ${list.length} videos',
      );

      return list
          .map(
            (dynamic e) => VideoModel.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(growable: false);
    } catch (e) {
      AppLogger.log('❌ SearchService: searchVideos exception: $e');
      return <VideoModel>[];
    }
  }

  Future<List<UserModel>> searchCreators(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];

    // **FIX: Use cached base URL**
    final baseUrl = await _getBaseUrl();
    final uri = Uri.parse('$baseUrl/api/search/creators').replace(
      queryParameters: <String, String>{
        'q': trimmed,
        'limit': '20',
      },
    );

    AppLogger.log('🔍 SearchService: searchCreators q="$trimmed" url=$uri');

    try {
      final res = await httpClientService.get(
        uri,
        headers: const {'Content-Type': 'application/json'},
        timeout: const Duration(seconds: 10),
      );

      AppLogger.log(
        '📡 SearchService: searchCreators response status=${res.statusCode}',
      );

      if (res.statusCode != 200) {
        AppLogger.log(
          '❌ SearchService: searchCreators failed '
          'status=${res.statusCode} body=${res.body}',
        );
        // Fail gracefully: return empty list instead of throwing
        return <UserModel>[];
      }

      final Map<String, dynamic> data =
          json.decode(res.body) as Map<String, dynamic>;
      final List<dynamic> list =
          data['creators'] as List<dynamic>? ?? <dynamic>[];

      AppLogger.log(
        '✅ SearchService: searchCreators found ${list.length} creators',
      );

      return list
          .map(
            (dynamic e) => UserModel.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(growable: false);
    } catch (e) {
      AppLogger.log('❌ SearchService: searchCreators exception: $e');
      return <UserModel>[];
    }
  }

  /// **NEW: Get search suggestions (autocomplete) - returns top creators and videos**
  Future<Map<String, dynamic>> getSuggestions(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || trimmed.length < 2) {
      return <String, dynamic>{
        'creators': <UserModel>[],
        'videos': <VideoModel>[],
      };
    }

    // **FIX: Use cached base URL**
    final baseUrl = await _getBaseUrl();
    final uri = Uri.parse('$baseUrl/api/search/creators').replace(
      queryParameters: <String, String>{
        'q': trimmed,
        'limit': '5', // Limit suggestions to 5 for faster UX
      },
    );

    try {
      final res = await httpClientService.get(
        uri,
        headers: const {'Content-Type': 'application/json'},
        timeout: const Duration(seconds: 5),
      );

      if (res.statusCode != 200) {
        return <String, dynamic>{
          'creators': <UserModel>[],
          'videos': <VideoModel>[],
        };
      }

      final Map<String, dynamic> data =
          json.decode(res.body) as Map<String, dynamic>;
      final List<dynamic> creatorsList =
          data['creators'] as List<dynamic>? ?? <dynamic>[];

      final creators = creatorsList
          .map(
            (dynamic e) => UserModel.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(growable: false);

      // Also get a few video suggestions
      final videosUri = Uri.parse('$baseUrl/api/search/videos').replace(
        queryParameters: <String, String>{
          'q': trimmed,
          'limit': '3', // Just 3 video suggestions
        },
      );

      List<VideoModel> videos = <VideoModel>[];
      try {
        final videosRes = await httpClientService.get(
          videosUri,
          headers: const {'Content-Type': 'application/json'},
          timeout: const Duration(seconds: 5),
        );

        if (videosRes.statusCode == 200) {
          final videosData =
              json.decode(videosRes.body) as Map<String, dynamic>;
          final videosList =
              videosData['videos'] as List<dynamic>? ?? <dynamic>[];

          videos = videosList
              .map(
                (dynamic e) => VideoModel.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList(growable: false);
        }
      } catch (e) {
        // Ignore video suggestions errors
        AppLogger.log('⚠️ SearchService: Error getting video suggestions: $e');
      }

      return <String, dynamic>{
        'creators': creators,
        'videos': videos,
      };
    } catch (e) {
      AppLogger.log('❌ SearchService: getSuggestions exception: $e');
      return <String, dynamic>{
        'creators': <UserModel>[],
        'videos': <VideoModel>[],
      };
    }
  }
}
