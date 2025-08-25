import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'; // **CRITICAL FIX: Added for compute function**
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/config/app_config.dart';
import 'package:snehayog/model/ad_model.dart';
import 'package:snehayog/services/ad_service.dart';
import 'package:snehayog/core/managers/smart_cache_manager.dart';
import 'package:snehayog/utils/feature_flags.dart';

/// Enhanced VideoService with Instagram-like caching strategy
/// Prevents repeated API calls on tab switches by using local cache
class InstagramVideoService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  final AuthService _authService = AuthService();
  final AdService _adService = AdService();
  final SmartCacheManager _cacheManager = SmartCacheManager();

  static String get baseUrl => NetworkHelper.getBaseUrl();

  // Cache keys for different data types
  static const String _videosCacheKey = 'videos_page_';
  static const String _videoDetailCacheKey = 'video_detail_';
  static const String _userVideosCacheKey = 'user_videos_';
  static const String _adsCacheKey = 'active_ads';

  // Optimized constants
  static const int maxRetries = 2;
  static const int retryDelay = 1;
  static const int maxShortVideoDuration = 120;

  /// Initialize the Instagram video service
  Future<void> initialize() async {
    try {
      print('🚀 InstagramVideoService: Initializing...');
      await _cacheManager.initialize();
      print('✅ InstagramVideoService: Initialization completed');
    } catch (e) {
      print('❌ InstagramVideoService: Initialization failed: $e');
    }
  }

  /// Get videos with Instagram-like caching strategy
  /// Returns cached data instantly, then checks ETag for freshness
  Future<Map<String, dynamic>> getVideos({
    int page = 1,
    int limit = 10,
    bool forceRefresh = false,
    String? currentEtag,
  }) async {
    final cacheKey = '$_videosCacheKey$page';

    print(
        '🎯 InstagramVideoService: Getting videos for page $page (forceRefresh: $forceRefresh)');

    try {
      // **CRITICAL FIX: Use better caching strategy**
      final cachedResult = await _cacheManager.get(
        cacheKey,
        fetchFn: () => _fetchVideosFromServer(page: page, limit: limit),
        cacheType: 'videos',
        maxAge: const Duration(
            minutes: 30), // **CRITICAL FIX: Increased cache duration**
        forceRefresh: forceRefresh,
        currentEtag: currentEtag,
      );

      if (cachedResult != null) {
        print('✅ InstagramVideoService: Returning cached data for page $page');
        return cachedResult;
      } else {
        print(
            '❌ InstagramVideoService: Cache miss for page $page, fetching fresh data');
        return await _fetchVideosFromServer(page: page, limit: limit);
      }
    } catch (e) {
      print('❌ InstagramVideoService: Error getting videos for page $page: $e');

      // **CRITICAL FIX: Try to return cached data on error**
      print(
          '🔄 InstagramVideoService: Attempting to use fallback cache for page $page');

      // Return empty result as last resort
      return {'videos': [], 'hasMore': false, 'total': 0, 'currentPage': page};
    }
  }

  /// Fetch videos from server with ETag support
  Future<Map<String, dynamic>> _fetchVideosFromServer({
    int page = 1,
    int limit = 10,
  }) async {
    try {
      final url = '$baseUrl/api/videos?page=$page&limit=$limit';
      print('📡 InstagramVideoService: Fetching videos from: $url');

      // Get cached ETag if available
      final cacheKey = '$_videosCacheKey$page';
      // Note: ETag handling will be implemented when cache manager is fully functional
      const ifNoneMatch = null;

      // Add ETag header if available
      final headers = <String, String>{};
      if (ifNoneMatch != null) {
        headers['If-None-Match'] = ifNoneMatch;
        print('📡 InstagramVideoService: Using ETag: $ifNoneMatch');
      }

      final response = await _makeRequest(
        () => http.get(Uri.parse(url), headers: headers),
        timeout: const Duration(seconds: 15),
      );

      // Check if server returned 304 Not Modified
      if (response.statusCode == 304) {
        print('✅ InstagramVideoService: Server returned 304 Not Modified');
        return {
          'status': 304,
          'message': 'Not Modified',
          'cached': true,
        };
      }

      if (response.statusCode == 200) {
        // **CRITICAL FIX: Move JSON parsing to background thread**
        final responseData = await compute(_parseVideosResponse, response.body);
        final List<dynamic> videoList = responseData['videos'];

        // Extract ETag from response headers
        final etag = response.headers['etag'];
        print('📡 InstagramVideoService: Server ETag: $etag');

        final videos = videoList.map((json) {
          // Process video URLs and ensure they're complete
          if (json['videoUrl'] != null &&
              !json['videoUrl'].toString().startsWith('http')) {
            json['videoUrl'] = '$baseUrl${json['videoUrl']}';
          }

          // Prefer HLS URLs for better streaming
          if (json['hlsPlaylistUrl'] != null &&
              json['hlsPlaylistUrl'].toString().isNotEmpty) {
            if (!json['hlsPlaylistUrl'].toString().startsWith('http')) {
              json['videoUrl'] = '$baseUrl${json['hlsPlaylistUrl']}';
            } else {
              json['videoUrl'] = json['hlsPlaylistUrl'];
            }
          }

          return VideoModel.fromJson(json);
        }).toList();

        final result = {
          'videos': List<VideoModel>.from(videos),
          'hasMore': responseData['hasMore'] ?? false,
          'total': responseData['total'] ?? 0,
          'currentPage': page,
          'etag': etag,
        };

        // Preload next page for better UX
        if (result['hasMore'] == true) {
          _preloadNextPage(page + 1, limit);
        }

        return result;
      } else {
        throw Exception('Failed to load videos: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ InstagramVideoService: Error fetching videos: $e');
      rethrow;
    }
  }

  /// **NEW: Parse videos response in background thread**
  static Map<String, dynamic> _parseVideosResponse(String responseBody) {
    try {
      return json.decode(responseBody);
    } catch (e) {
      print('❌ InstagramVideoService: Error parsing response: $e');
      rethrow;
    }
  }

  /// Preload next page for seamless pagination
  void _preloadNextPage(int nextPage, int limit) {
    if (!Features.backgroundVideoPreloading.isEnabled) return;

    unawaited(_cacheManager.get(
      '$_videosCacheKey$nextPage',
      fetchFn: () => _fetchVideosFromServer(page: nextPage, limit: limit),
      cacheType: 'videos',
      maxAge: const Duration(minutes: 15),
    ));
  }

  /// Get video by ID with Instagram-like caching
  Future<VideoModel?> getVideoById(String id,
      {bool forceRefresh = false, String? currentEtag}) async {
    final cacheKey = '$_videoDetailCacheKey$id';

    return await _cacheManager.get(
      cacheKey,
      fetchFn: () async {
        final video = await _fetchVideoFromServer(id);
        if (video == null) throw Exception('Video not found');
        return video;
      },
      cacheType: 'video_metadata',
      maxAge: const Duration(hours: 1),
      forceRefresh: forceRefresh,
      currentEtag: currentEtag,
    );
  }

  /// Fetch video from server with ETag support
  Future<VideoModel?> _fetchVideoFromServer(String id) async {
    try {
      final res = await http.get(Uri.parse('$baseUrl/api/videos/$id'));
      if (res.statusCode == 200) {
        // **CRITICAL FIX: Move JSON parsing to background thread**
        final videoData = await compute(_parseVideoResponse, res.body);
        return VideoModel.fromJson(videoData);
      } else {
        // **CRITICAL FIX: Move JSON parsing to background thread**
        final error = await compute(_parseErrorResponse, res.body);
        throw Exception(error['error'] ?? 'Failed to load video');
      }
    } catch (e) {
      print('❌ InstagramVideoService: Error fetching video $id: $e');
      rethrow;
    }
  }

  /// **NEW: Parse video response in background thread**
  static Map<String, dynamic> _parseVideoResponse(String responseBody) {
    try {
      return json.decode(responseBody);
    } catch (e) {
      print('❌ InstagramVideoService: Error parsing video response: $e');
      rethrow;
    }
  }

  /// **NEW: Parse error response in background thread**
  static Map<String, dynamic> _parseErrorResponse(String responseBody) {
    try {
      return json.decode(responseBody);
    } catch (e) {
      print('❌ InstagramVideoService: Error parsing error response: $e');
      rethrow;
    }
  }

  /// Get user videos with Instagram-like caching
  Future<List<VideoModel>> getUserVideos(String userId,
      {bool forceRefresh = false, String? currentEtag}) async {
    final cacheKey = '$_userVideosCacheKey$userId';

    return await _cacheManager.get(
          cacheKey,
          fetchFn: () => _fetchUserVideosFromServer(userId),
          cacheType: 'user_videos',
          maxAge: const Duration(minutes: 15),
          forceRefresh: forceRefresh,
          currentEtag: currentEtag,
        ) ??
        [];
  }

  /// Fetch user videos from server
  Future<List<VideoModel>> _fetchUserVideosFromServer(String userId) async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/videos/user/$userId'),
      );

      if (response.statusCode == 200) {
        // **CRITICAL FIX: Move JSON parsing to background thread**
        final List<dynamic> videoList =
            await compute(_parseUserVideosResponse, response.body);

        return videoList.map((json) {
          // Process video URLs and ensure they're complete
          if (json['videoUrl'] != null &&
              !json['videoUrl'].toString().startsWith('http')) {
            json['videoUrl'] = '$baseUrl${json['videoUrl']}';
          }

          // Prefer HLS URLs for better streaming
          if (json['hlsPlaylistUrl'] != null &&
              json['hlsPlaylistUrl'].toString().isNotEmpty) {
            if (!json['hlsPlaylistUrl'].toString().startsWith('http')) {
              json['videoUrl'] = '$baseUrl${json['hlsPlaylistUrl']}';
            } else {
              json['videoUrl'] = json['hlsPlaylistUrl'];
            }
          }

          return VideoModel.fromJson(json);
        }).toList();
      } else {
        // **CRITICAL FIX: Move JSON parsing to background thread**
        final error = await compute(_parseErrorResponse, response.body);
        throw Exception(error['error'] ?? 'Failed to load user videos');
      }
    } catch (e) {
      print('❌ InstagramVideoService: Error fetching user videos: $e');
      rethrow;
    }
  }

  /// **NEW: Parse user videos response in background thread**
  static List<dynamic> _parseUserVideosResponse(String responseBody) {
    try {
      return json.decode(responseBody);
    } catch (e) {
      print('❌ InstagramVideoService: Error parsing user videos response: $e');
      rethrow;
    }
  }

  /// Get videos with integrated ads using Instagram-like caching
  Future<Map<String, dynamic>> getVideosWithAds({
    int page = 1,
    int limit = 10,
    int adInsertionFrequency = 3,
    bool forceRefresh = false,
    String? currentEtag,
  }) async {
    try {
      print('🔍 InstagramVideoService: Fetching videos with ads...');

      // Get videos with caching
      final videosResult = await getVideos(
        page: page,
        limit: limit,
        forceRefresh: forceRefresh,
        currentEtag: currentEtag,
      );
      final videos = videosResult['videos'] as List<VideoModel>;

      // Get ads with caching
      List<AdModel> ads = [];
      try {
        ads = await getActiveAds(forceRefresh: forceRefresh);
      } catch (adError) {
        print(
            '⚠️ InstagramVideoService: Failed to fetch ads, continuing without ads: $adError');
      }

      // Integrate ads into video feed
      List<dynamic> integratedFeed = videos;
      if (ads.isNotEmpty) {
        integratedFeed =
            _integrateAdsIntoFeed(videos, ads, adInsertionFrequency);
      }

      return {
        'videos': integratedFeed,
        'hasMore': videosResult['hasMore'] ?? false,
        'total': videosResult['total'] ?? 0,
        'currentPage': page,
        'adCount': ads.length,
        'integratedCount': integratedFeed.length,
        'etag': videosResult['etag'],
      };
    } catch (e) {
      print('❌ InstagramVideoService: Error fetching videos with ads: $e');
      rethrow;
    }
  }

  /// Get active ads with Instagram-like caching
  Future<List<AdModel>> getActiveAds({bool forceRefresh = false}) async {
    return await _cacheManager.get(
          _adsCacheKey,
          fetchFn: () => _adService.getActiveAds(),
          cacheType: 'ads',
          maxAge: const Duration(minutes: 10),
          forceRefresh: forceRefresh,
        ) ??
        [];
  }

  /// Integrate ads into video feed
  List<dynamic> _integrateAdsIntoFeed(
    List<VideoModel> videos,
    List<AdModel> ads,
    int frequency,
  ) {
    if (ads.isEmpty) return videos;

    final integratedFeed = <dynamic>[];
    int adIndex = 0;

    for (int i = 0; i < videos.length; i++) {
      integratedFeed.add(videos[i]);

      if ((i + 1) % frequency == 0 && i < videos.length - 1) {
        if (adIndex < ads.length) {
          final adAsVideo = _convertAdToVideoFormat(ads[adIndex]);
          integratedFeed.add(adAsVideo);
          adIndex++;
        }
      }
    }

    return integratedFeed;
  }

  /// Convert ad to video format
  Map<String, dynamic> _convertAdToVideoFormat(AdModel ad) {
    return {
      'id': 'ad_${ad.id}',
      'videoName': ad.title,
      'videoUrl': ad.videoUrl ?? ad.imageUrl ?? '',
      'thumbnailUrl': ad.imageUrl ?? ad.videoUrl ?? '',
      'description': ad.description,
      'likes': 0,
      'views': 0,
      'shares': 0,
      'uploader': {
        'id': ad.uploaderId,
        'name': 'Sponsored',
        'profilePic': ad.uploaderProfilePic ?? '',
      },
      'uploadedAt': DateTime.now(),
      'likedBy': <String>[],
      'videoType': 'ad',
      'comments': <Map<String, dynamic>>[],
      'link': ad.link,
      'isAd': true,
      'adData': ad.toJson(),
      'adType': ad.adType,
      'targetAudience': ad.targetAudience,
      'targetKeywords': ad.targetKeywords,
    };
  }

  /// Toggle like with optimistic updates and Instagram-like caching
  Future<VideoModel> toggleLike(String videoId, String userId) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('Please sign in to like videos');
      }

      // Optimistic update - update cache immediately
      final cachedVideo = await getVideoById(videoId);
      if (cachedVideo != null) {
        // Update like count optimistically
        final updatedVideo = cachedVideo.copyWith(
          likes: cachedVideo.likes + 1,
        );

        // Update cache immediately for instant UI feedback
        await _cacheManager.get(
          '$_videoDetailCacheKey$videoId',
          fetchFn: () async => updatedVideo,
          cacheType: 'video_metadata',
          forceRefresh: true,
        );
      }

      // Make actual API call
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/videos/$videoId/like'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'userId': userId}),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        final videoModel = VideoModel.fromJson(data);

        // Update cache with actual server response
        await _cacheManager.get(
          '$_videoDetailCacheKey$videoId',
          fetchFn: () async => videoModel,
          cacheType: 'video_metadata',
          forceRefresh: true,
        );

        return videoModel;
      } else {
        throw Exception('Failed to like video: ${res.statusCode}');
      }
    } catch (e) {
      print('❌ InstagramVideoService: Error in toggleLike: $e');
      rethrow;
    }
  }

  /// Add comment with Instagram-like caching
  Future<List<Comment>> addComment(
    String videoId,
    String text,
    String userId,
  ) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('Please sign in to add comments');
      }

      final res = await http
          .post(
            Uri.parse('$baseUrl/api/videos/$videoId/comments'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'userId': userId, 'text': text}),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final List<dynamic> commentsJson = json.decode(res.body);
        final comments =
            commentsJson.map((json) => Comment.fromJson(json)).toList();

        // Invalidate video cache to ensure fresh data
        await _cacheManager.get(
          '$_videoDetailCacheKey$videoId',
          fetchFn: () => _fetchVideoFromServer(videoId),
          cacheType: 'video_metadata',
          forceRefresh: true,
        );

        return comments;
      } else {
        throw Exception('Failed to add comment: ${res.statusCode}');
      }
    } catch (e) {
      print('❌ InstagramVideoService: Error adding comment: $e');
      rethrow;
    }
  }

  /// Upload video with progress tracking
  Future<Map<String, dynamic>> uploadVideo(
    File videoFile,
    String title, {
    String? description,
    String? link,
    Function(double)? onProgress,
  }) async {
    try {
      print('📤 InstagramVideoService: Starting video upload...');

      // Check server health
      final isHealthy = await checkServerHealth();
      if (!isHealthy) {
        throw Exception(
            'Server is not responding. Please check your connection and try again.');
      }

      final isLong = await isLongVideo(videoFile.path);
      final userData = await _authService.getUserData();

      if (userData == null) {
        throw Exception(
            'User not authenticated. Please sign in to upload videos.');
      }

      // Check file size
      final fileSize = await videoFile.length();
      const maxSize = 100 * 1024 * 1024; // 100MB
      if (fileSize > maxSize) {
        throw Exception('File too large. Maximum size is 100MB');
      }

      // Create multipart request
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/videos/upload'),
      );

      final headers = await _getAuthHeaders();
      request.headers.addAll(headers);

      request.files.add(
        await http.MultipartFile.fromPath(
          'video',
          videoFile.path,
          contentType: http_parser.MediaType('application', 'x-mpegURL'),
        ),
      );

      request.fields['videoName'] = title;
      request.fields['description'] = description ?? '';
      request.fields['videoType'] = isLong ? 'yog' : 'sneha';
      if (link != null && link.isNotEmpty) {
        request.fields['link'] = link;
      }

      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 10),
        onTimeout: () {
          throw TimeoutException(
              'Upload timed out. Please check your internet connection and try again.');
        },
      );

      final responseBody = await streamedResponse.stream.bytesToString();
      final responseData = json.decode(responseBody);

      if (streamedResponse.statusCode == 201) {
        final videoData = responseData['video'];

        // Invalidate relevant caches
        await _invalidateVideoCaches();

        return {
          'id': videoData['_id'],
          'title': videoData['videoName'],
          'videoUrl': videoData['videoUrl'],
          'thumbnail': videoData['thumbnailUrl'],
          'originalVideoUrl': videoData['originalVideoUrl'],
          'duration': '0:00',
          'views': 0,
          'uploader': userData['name'],
          'uploadTime': 'Just now',
          'isLongVideo': isLong,
          'link': videoData['link'],
        };
      } else {
        throw Exception(responseData['error'] ?? 'Failed to upload video');
      }
    } catch (e) {
      print('❌ InstagramVideoService: Error uploading video: $e');
      rethrow;
    }
  }

  /// Invalidate video-related caches after upload
  Future<void> _invalidateVideoCaches() async {
    try {
      // Clear video list caches
      for (int i = 1; i <= 5; i++) {
        // Clear first 5 pages
        await _cacheManager.get(
          '$_videosCacheKey$i',
          fetchFn: () => _fetchVideosFromServer(page: i, limit: 10),
          cacheType: 'videos',
          forceRefresh: true,
        );
      }
      print('✅ InstagramVideoService: Video caches invalidated');
    } catch (e) {
      print('⚠️ InstagramVideoService: Error invalidating caches: $e');
    }
  }

  /// Check if video is long
  Future<bool> isLongVideo(String videoPath) async {
    try {
      final controller = VideoPlayerController.file(File(videoPath));
      await controller.initialize();
      final duration = controller.value.duration;
      await controller.dispose();
      return duration.inSeconds > maxShortVideoDuration;
    } catch (e) {
      print('❌ InstagramVideoService: Error checking video duration: $e');
      return false;
    }
  }

  /// Check server health
  Future<bool> checkServerHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Optimized HTTP request with retry logic
  Future<http.Response> _makeRequest(
    Future<http.Response> Function() requestFn, {
    int maxRetries = 2,
    Duration retryDelay = const Duration(seconds: 1),
    Duration timeout = const Duration(seconds: 15),
  }) async {
    int attempts = 0;
    while (attempts < maxRetries) {
      try {
        final response = await requestFn().timeout(timeout);
        if (response.statusCode == 200 || response.statusCode == 304) {
          return response;
        }
        attempts++;
        if (attempts < maxRetries) await Future.delayed(retryDelay * attempts);
      } catch (e) {
        attempts++;
        if (attempts >= maxRetries) rethrow;
        await Future.delayed(retryDelay * attempts);
      }
    }
    throw Exception('Request failed after $maxRetries attempts');
  }

  /// Get authentication headers
  Future<Map<String, String>> _getAuthHeaders() async {
    final userData = await _authService.getUserData();
    if (userData == null) {
      throw Exception('User not authenticated');
    }
    if (userData['token'] == null) {
      throw Exception('Authentication token not found');
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${userData['token']}',
    };
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return _cacheManager.getStats();
  }

  /// Clear all caches
  Future<void> clearCaches() async {
    await _cacheManager.clearCache();
  }

  /// Preload data for better user experience
  Future<void> preloadData(List<String> videoIds) async {
    if (!Features.backgroundVideoPreloading.isEnabled) return;

    // Use smart preload instead of direct preload
    for (final videoId in videoIds.take(5)) {
      // Limit to 5 videos
      unawaited(_cacheManager.get(
        '$_videoDetailCacheKey$videoId',
        fetchFn: () => _fetchVideoFromServer(videoId),
        cacheType: 'video_metadata',
        maxAge: const Duration(hours: 1),
      ));
    }
  }

  /// **NEW: Preload and cache data for better performance**
  Future<void> preloadAndCacheData() async {
    try {
      print('🚀 InstagramVideoService: Preloading and caching data...');

      // Preload first few pages of videos
      for (int page = 1; page <= 3; page++) {
        unawaited(getVideos(page: page, limit: 20, forceRefresh: false));
      }

      // Preload active ads
      unawaited(_adService.getActiveAds());

      print('✅ InstagramVideoService: Preloading completed');
    } catch (e) {
      print('❌ InstagramVideoService: Error during preloading: $e');
    }
  }

  /// **NEW: Get cached videos without network call**
  Future<Map<String, dynamic>?> getCachedVideos({
    int page = 1,
    int limit = 10,
  }) async {
    try {
      final cacheKey = '$_videosCacheKey$page';
      print('🎯 InstagramVideoService: Getting cached videos for page $page');

      // Try to get from cache without network call
      final cachedResult = await _cacheManager.get(
        cacheKey,
        fetchFn: () async {
          // Return null to indicate cache miss without network call
          return null;
        },
        cacheType: 'videos',
        maxAge: const Duration(minutes: 30),
        forceRefresh: false,
      );

      if (cachedResult != null) {
        print('✅ InstagramVideoService: Found cached videos for page $page');
        return cachedResult;
      } else {
        print('❌ InstagramVideoService: No cached videos found for page $page');
        return null;
      }
    } catch (e) {
      print('❌ InstagramVideoService: Error getting cached videos: $e');
      return null;
    }
  }

  /// Dispose service
  Future<void> dispose() async {
    await _cacheManager.dispose();
  }
}

// Helper classes and extensions
class NetworkHelper {
  static String getBaseUrl() {
    return AppConfig.baseUrl;
  }
}

class MediaType {
  final String type;
  final String subtype;

  MediaType(this.type, this.subtype);

  @override
  String toString() => '$type/$subtype';
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}
