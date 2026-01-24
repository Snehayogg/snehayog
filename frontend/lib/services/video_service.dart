import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:flutter/material.dart';
import 'package:http_parser/http_parser.dart';
import 'package:video_compress/video_compress.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/model/ad_model.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/services/ad_service.dart';
import 'package:vayu/services/platform_id_service.dart';
import 'package:vayu/config/app_config.dart';
import 'package:vayu/utils/app_logger.dart';
import 'package:vayu/services/connectivity_service.dart';
import 'package:vayu/core/services/http_client_service.dart';
import 'package:vayu/features/video/data/datasources/video_local_datasource.dart';

/// Eliminates code duplication and provides consistent API
class VideoService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  final AuthService _authService = AuthService();
  final AdService _adService = AdService();

  // Using httpClientService for connection pooling and better performance

  // **VIDEO TRACKING: State management for video playback**
  int _currentVisibleVideoIndex = 0;
  bool _isVideoScreenActive = true;
  bool _isAppInForeground = true;
  final List<Function(int)> _videoIndexChangeListeners = [];
  final List<Function(bool)> _videoScreenStateListeners = [];

  // **CONSTANTS: Optimized values for better performance**
  static String get baseUrl => NetworkHelper.getBaseUrl();

  // **NEW: Get base URL with Railway first, local fallback**
  static Future<String> getBaseUrlWithFallback() =>
      NetworkHelper.getBaseUrlWithFallback();
  static const int maxRetries = 2;
  static const int retryDelay = 1;
  static const int maxShortVideoDuration = 120;
  static const int maxFileSize = 100 * 1024 * 1024; // 100MB

  // **GETTERS: Video tracking state**
  int get currentVisibleVideoIndex => _currentVisibleVideoIndex;
  bool get isVideoScreenActive => _isVideoScreenActive;
  bool get isAppInForeground => _isAppInForeground;
  bool get shouldPlayVideos => _isVideoScreenActive && _isAppInForeground;

  // **VIDEO TRACKING METHODS**
  void updateCurrentVideoIndex(int newIndex) {
    if (_currentVisibleVideoIndex != newIndex) {
      final oldIndex = _currentVisibleVideoIndex;
      _currentVisibleVideoIndex = newIndex;
      /* AppLogger.log(
          '🎬 VideoService: Video index changed from $oldIndex to $newIndex'); */

      for (final listener in _videoIndexChangeListeners) {
        try {
          listener(newIndex);
        } catch (e) {
          AppLogger.log(
              '❌ VideoService: Error in video index change listener: $e');
        }
      }
    }
  }

  void updateVideoScreenState(bool isActive) {
    if (_isVideoScreenActive != isActive) {
      _isVideoScreenActive = isActive;
      /* AppLogger.log(
        '🔄 VideoService: Video screen state changed to ${isActive ? "ACTIVE" : "INACTIVE"}',
      ); */

      for (final listener in _videoScreenStateListeners) {
        try {
          listener(isActive);
        } catch (e) {
          AppLogger.log(
              '❌ VideoService: Error in video screen state listener: $e');
        }
      }
    }
  }

  void updateAppForegroundState(bool inForeground) {
    if (_isAppInForeground != inForeground) {
      _isAppInForeground = inForeground;
      /* AppLogger.log(
        '📱 VideoService: App foreground state changed to ${inForeground ? "FOREGROUND" : "BACKGROUND"}',
      ); */
    }
  }

  void addVideoIndexChangeListener(Function(int) listener) {
    if (!_videoIndexChangeListeners.contains(listener)) {
      _videoIndexChangeListeners.add(listener);
    }
  }

  void removeVideoIndexChangeListener(Function(int) listener) {
    _videoIndexChangeListeners.remove(listener);
  }

  void addVideoScreenStateListener(Function(bool) listener) {
    if (!_videoScreenStateListeners.contains(listener)) {
      _videoScreenStateListeners.add(listener);
    }
  }

  void removeVideoScreenStateListener(Function(bool) listener) {
    _videoScreenStateListeners.remove(listener);
  }

  Map<String, dynamic> getVideoTrackingInfo() {
    return {
      'currentVisibleVideoIndex': _currentVisibleVideoIndex,
      'isVideoScreenActive': _isVideoScreenActive,
      'isAppInForeground': _isAppInForeground,
      'shouldPlayVideos': shouldPlayVideos,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  // **CORE VIDEO METHODS - Merged from all services**

  /// **Get videos with pagination and HLS support**
  /// **NEW: Optional authentication for personalized feed**
  /// **NEW: Optional clearSession parameter to clear backend session state for fresh videos**
  Future<Map<String, dynamic>> getVideos({
    int page = 1,
    int limit = 15,
    String? videoType,
    bool clearSession = false,
  }) async {
    try {
      // Get base URL with Railway first, local fallback
      // AppLogger.log('🔍 VideoService: Using base URL: ${NetworkHelper.apiBaseUrl}');

      String url = '${NetworkHelper.apiBaseUrl}/videos?page=$page&limit=$limit';
      final normalizedType = videoType?.toLowerCase();
      // **FIXED: Use 'yog' consistently in both frontend and backend**
      String? apiVideoType = normalizedType;
      if (normalizedType == 'yog' || normalizedType == 'vayu') {
        url += '&videoType=$apiVideoType';
        // AppLogger.log('🔍 VideoService: Filtering by videoType: $apiVideoType');
      }

      // **BACKEND-FIRST: Get platformId for anonymous users**
      final platformIdService = PlatformIdService();
      final platformId = await platformIdService.getPlatformId();
      if (platformId.isNotEmpty) {
        url += '&platformId=$platformId';
        /* AppLogger.log(
            '📱 VideoService: Using platformId for personalized feed'); */
      }

      // **NEW: Add clearSession parameter to clear backend session state**
      if (clearSession) {
        url += '&clearSession=true';
        AppLogger.log(
            '🧹 VideoService: Clearing session state for fresh videos');
      }

      // **BACKEND-FIRST: Get auth token for authenticated users (optional - don't fail if missing)**
      Map<String, String> headers = {
        'Content-Type': 'application/json',
      };
      
      if (platformId.isNotEmpty) {
         headers['x-device-id'] = platformId;
         // AppLogger.log('📱 VideoService: Added x-device-id header: $platformId'); 
      } else {
         AppLogger.log('⚠️ VideoService: Platform ID is empty! Header not added.');
      }

      try {
        final token = await AuthService.getToken();
        if (token != null && token.isNotEmpty) {
          headers['Authorization'] = 'Bearer $token';
          /* AppLogger.log(
              '✅ VideoService: Using authenticated request for personalized feed'); */
        } else {
          // AppLogger.log('ℹ️ VideoService: No auth token - using regular feed');
        }
      } catch (e) {
        AppLogger.log(
            '⚠️ VideoService: Error getting auth token, using regular feed: $e');
      }

      final response = await httpClientService.get(
        Uri.parse(url),
        headers: headers,
        timeout: const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        final List<dynamic> videoList = responseData['videos'] ?? [];

        // **ENHANCED: Detailed logging for empty video list debugging**
        if (videoList.isEmpty) {
          AppLogger.log(
            '⚠️ VideoService: Empty video list received from API (page: $page, videoType: $videoType)',
          );
          AppLogger.log(
              '⚠️ VideoService: Response data keys: ${responseData.keys.toList()}');
          AppLogger.log(
              '⚠️ VideoService: Full response: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}');
          AppLogger.log(
              '⚠️ VideoService: Has more: ${responseData['hasMore']}, Total: ${responseData['total']}, Current page: ${responseData['currentPage']}');

          // **NEW: Check if backend has any videos at all**
          if (responseData['total'] != null && responseData['total'] == 0) {
            AppLogger.log(
                '⚠️ VideoService: Backend reports 0 total videos in database!');
          }
        } else {
          /* AppLogger.log(
              '✅ VideoService: Received ${videoList.length} videos from API (page: $page, videoType: $videoType)'); */
        }

        final videos = videoList.map((json) {
          // **DEBUG: Log all video data for debugging**
          /* AppLogger.log(
              '🔍 VideoService: Video data for ${json['videoName']}:');
          AppLogger.log('  - videoUrl: ${json['videoUrl']}');
          AppLogger.log('  - hlsPlaylistUrl: ${json['hlsPlaylistUrl']}');
          AppLogger.log(
              '  - hlsMasterPlaylistUrl: ${json['hlsMasterPlaylistUrl']}');
          AppLogger.log('  - isHLSEncoded: ${json['isHLSEncoded']}');
          AppLogger.log('  - hlsVariants: ${json['hlsVariants']?.length ?? 0}'); */

          // **HLS URL Priority**: Use HLS for better streaming
          if (json['hlsPlaylistUrl'] != null &&
              json['hlsPlaylistUrl'].toString().isNotEmpty) {
            String hlsUrl = json['hlsPlaylistUrl'].toString();
            if (!hlsUrl.startsWith('http')) {
              // Remove leading slash if present to avoid double slash
              if (hlsUrl.startsWith('/')) {
                hlsUrl = hlsUrl.substring(1);
              }
              json['videoUrl'] = '${NetworkHelper.apiBaseUrl}/$hlsUrl';
            } else {
              json['videoUrl'] = hlsUrl;
            }
            // AppLogger.log('🔗 VideoService: Using HLS Playlist URL: ${json['videoUrl']}');
          } else if (json['hlsMasterPlaylistUrl'] != null &&
              json['hlsMasterPlaylistUrl'].toString().isNotEmpty) {
            String masterUrl = json['hlsMasterPlaylistUrl'].toString();
            if (!masterUrl.startsWith('http')) {
              if (masterUrl.startsWith('/')) {
                masterUrl = masterUrl.substring(1);
              }
              json['videoUrl'] = '${NetworkHelper.apiBaseUrl}/$masterUrl';
            } else {
              json['videoUrl'] = masterUrl;
            }
            // AppLogger.log('🔗 VideoService: Using HLS Master URL: ${json['videoUrl']}');
          } else {
            // **Fallback**: Ensure relative URLs are complete
            if (json['videoUrl'] != null &&
                !json['videoUrl'].toString().startsWith('http')) {
              String videoUrl = json['videoUrl'].toString();
              // Remove leading slash if present to avoid double slash
              if (videoUrl.startsWith('/')) {
                videoUrl = videoUrl.substring(1);
              }
              json['videoUrl'] = '${NetworkHelper.apiBaseUrl}/$videoUrl';
            }
            /* AppLogger.log(
              '🔗 VideoService: Using original video URL: ${json['videoUrl']}',
            ); */
          }

          final video = VideoModel.fromJson(json);
          
          // **DEBUG: Check for empty IDs which cause PageView key collisions**
          if (video.id.isEmpty) {
            AppLogger.log('❌ VideoService: Critical Error - Parsed video with EMPTY ID! Name: ${video.videoName}');
            // Fallback: Generate a random ID to prevent key collision crashes
            // This is a band-aid; backend should fix the root cause.
            return video.copyWith(id: 'temp_${DateTime.now().microsecondsSinceEpoch}');
          }
          
          return video;
        }).toList();

        final result = {
          'videos': List<VideoModel>.from(videos),
          'hasMore': responseData['hasMore'] ?? false,
          'total': responseData['total'] ?? videos.length,
          'currentPage': responseData['currentPage'] ?? page,
          'totalPages': responseData['totalPages'] ?? 1,
        };

        // **CACHE: Save fresh videos to Hive**
        // We use unawaited to not block the UI return
        // ignore: unawaited_futures
        _cacheVideosIfApplicable(videos, videoType, page);

        return result;
      } else {
        // **ENHANCED: Better error handling for non-200 responses**
        AppLogger.log(
          '❌ VideoService: API returned status ${response.statusCode}',
        );
        AppLogger.log(
          '❌ VideoService: Response body: ${response.body.length > 500 ? response.body.substring(0, 500) : response.body}',
        );

        // **NEW: Try to parse error message from backend**
        String errorMessage = 'Failed to load videos: ${response.statusCode}';
        try {
          final errorData = json.decode(response.body);
          if (errorData['error'] != null) {
            errorMessage = errorData['error'].toString();
          } else if (errorData['message'] != null) {
            errorMessage = errorData['message'].toString();
          }
        } catch (_) {
          // Not JSON, use default message
        }

        throw Exception(errorMessage);
      }
    } catch (e) {
      AppLogger.log('❌ VideoService: Error in getVideos: $e');

      // **OFFLINE FALLBACK: Try Hive Cache**
      if (page == 1) {
        try {
          // Lazy load the data source to avoid circular dependency issues if any
          // Ideally passed via constructor but using direct instantiation for service patch
          // Imports are needed: import '../features/video/data/datasources/video_local_datasource.dart';

          final _localDataSource = VideoLocalDataSource();
          final videoTypeKey =
              videoType ?? 'yog'; // default to yog for cache key if null

          final cachedVideos =
              await _localDataSource.getCachedVideoFeed(videoTypeKey);

          if (cachedVideos != null && cachedVideos.isNotEmpty) {
            AppLogger.log(
                '✅ VideoService: Returning CACHED videos (Offline Mode)');
            return {
              'videos': cachedVideos,
              'hasMore': false,
              'total': cachedVideos.length,
              'currentPage': 1,
              'totalPages': 1,
              'isOffline': true,
            };
          }
        } catch (cacheError) {
          AppLogger.log('⚠️ VideoService: Cache fallback failed: $cacheError');
        }
      }

      // **FIX: Add device info for debugging**
      AppLogger.log(
        '❌ VideoService: Error details - page: $page, videoType: $videoType, limit: $limit',
      );
      rethrow;
    }
  }

  /// **Helper to cache videos (called after successful fetch)**
  Future<void> _cacheVideosIfApplicable(
      List<VideoModel> videos, String? videoType, int page) async {
    if (page == 1 && videos.isNotEmpty) {
      try {
        final _localDataSource = VideoLocalDataSource();
        final type = videoType ?? 'yog';
        if (type == 'yog' || type == 'vayu') {
          await _localDataSource.cacheVideoFeed(videos, type);
        }
      } catch (e) {
        AppLogger.log('⚠️ VideoService: Failed to cache videos: $e');
      }
    }
  }

  /// **Get video by ID - Enhanced with better error handling**
  Future<VideoModel> getVideoById(String id) async {
    try {
      // **VALIDATION: Ensure video ID is not empty**
      if (id.trim().isEmpty) {
        throw Exception('Video ID cannot be empty');
      }

      final videoId = id.trim();
      final url = '${NetworkHelper.apiBaseUrl}/videos/$videoId';

      // AppLogger.log('📡 VideoService: Fetching video by ID: $videoId');

      final res = await http
          .get(Uri.parse(url))
          .timeout(const Duration(seconds: 15), onTimeout: () {
        throw Exception('Request timed out. Please check your connection.');
      });

      if (res.statusCode == 200) {
        final videoData = json.decode(res.body);
        final video = VideoModel.fromJson(videoData);
        /* AppLogger.log(
          '✅ VideoService: Successfully fetched video: ${video.videoName} (ID: ${video.id})',
        ); */
        return video;
      } else if (res.statusCode == 404) {
        AppLogger.log('❌ VideoService: Video not found (404): $videoId');
        throw Exception('Video not found. It may have been deleted.');
      } else {
        final error = json.decode(res.body);
        final errorMessage = error['error'] ?? 'Failed to load video';
        AppLogger.log(
          '❌ VideoService: Error fetching video (${res.statusCode}): $errorMessage',
        );
        throw Exception(errorMessage);
      }
    } catch (e) {
      AppLogger.log('❌ VideoService: Exception fetching video by ID: $e');
      if (e is Exception) rethrow;
      throw Exception('Network error: $e');
    }
  }

  /// **Toggle like for a video (like/unlike)**
  Future<VideoModel> toggleLike(String videoId) async {
    // **CONNECTIVITY CHECK: Verify internet before like operation**
    final hasInternet = await ConnectivityService.hasInternetConnection();
    if (!hasInternet) {
      throw Exception(
        ConnectivityService.getNetworkErrorMessage(
          Exception('No internet connection'),
        ),
      );
    }

    try {
      AppLogger.log('🔄 VideoService: Toggling like for video: $videoId');

      // **FIX: Get user data and validate token before making request**
      final userData = await _authService.getUserData();
      if (userData == null) {
        AppLogger.log('❌ VideoService: User not authenticated for like');
        throw Exception('Please sign in to like videos');
      }

      // **FIX: Check if token exists and is valid**
      final token = userData['token'];
      if (token == null || token.toString().isEmpty) {
        AppLogger.log('❌ VideoService: No token found for like');
        throw Exception('Please sign in again to like videos');
      }

      // **FIX: Check if token is a fallback token (won't work with backend)**
      if (token.toString().startsWith('temp_')) {
        AppLogger.log(
            '❌ VideoService: Fallback token detected - cannot like videos');
        throw Exception(
            'Please sign in with your Google account to like videos. Fallback session does not support this feature.');
      }

      // **FIX: Validate token format (should be JWT) - wrap in try-catch**
      bool isTokenValid = false;
      try {
        isTokenValid = _authService.isTokenValid(token);
      } catch (e) {
        AppLogger.log(
            '❌ VideoService: Error validating token (may not be JWT): $e');
        isTokenValid = false;
      }

      if (!isTokenValid) {
        AppLogger.log('❌ VideoService: Token is invalid or expired');
        // Try to refresh
        try {
          final refreshedToken = await _authService.refreshTokenIfNeeded();
          if (refreshedToken == null) {
            throw Exception('Please sign in again to like videos');
          }
          AppLogger.log('✅ VideoService: Token refreshed before like request');
        } catch (e) {
          AppLogger.log('❌ VideoService: Token refresh failed: $e');
          throw Exception('Please sign in again to like videos');
        }
      } else {
        // **FIX: Try to refresh token if it might be expiring soon**
        try {
          final refreshedToken = await _authService.refreshTokenIfNeeded();
          if (refreshedToken != null && refreshedToken != token) {
            AppLogger.log(
                '✅ VideoService: Token refreshed before like request');
          }
        } catch (e) {
          AppLogger.log(
              '⚠️ VideoService: Token refresh failed (non-critical): $e');
        }
      }

      final headers = await _getAuthHeaders();
      headers['Content-Type'] = 'application/json';

      // **FIX: Log token info for debugging**
      final tokenForLog =
          headers['Authorization']?.toString().replaceAll('Bearer ', '') ??
              'No token';
      AppLogger.log(
          '🔍 VideoService: Like request - Token present: ${headers.containsKey('Authorization')}');
      AppLogger.log(
          '🔍 VideoService: Like request - Token length: ${tokenForLog.length}');
      AppLogger.log(
          '🔍 VideoService: Like request - Token starts with: ${tokenForLog.length > 20 ? tokenForLog.substring(0, 20) : tokenForLog}');

      // **FIX: Log user data for debugging**
      AppLogger.log(
          '🔍 VideoService: User data - googleId: ${userData['googleId']}');
      AppLogger.log('🔍 VideoService: User data - id: ${userData['id']}');
      AppLogger.log('🔍 VideoService: User data - email: ${userData['email']}');

      final resolvedBaseUrl = await getBaseUrlWithFallback();
      AppLogger.log(
          '🔍 VideoService: Like request URL: ${NetworkHelper.apiBaseUrl}/videos/$videoId/like');

      final res = await http
          .post(
            Uri.parse('${NetworkHelper.apiBaseUrl}/videos/$videoId/like'),
            headers: headers,
            body: json.encode({}),
          )
          .timeout(const Duration(seconds: 15));

      AppLogger.log('📡 VideoService: Like response status: ${res.statusCode}');
      AppLogger.log('📡 VideoService: Like response body: ${res.body}');

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        AppLogger.log('✅ VideoService: Like toggled successfully');
        return VideoModel.fromJson(data);
      } else if (res.statusCode == 401 || res.statusCode == 403) {
        AppLogger.log(
            '❌ VideoService: Authentication failed (${res.statusCode})');
        // **FIX: Clear invalid token**
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('jwt_token');
          AppLogger.log('⚠️ VideoService: Cleared invalid token');
        } catch (e) {
          AppLogger.log('⚠️ VideoService: Error clearing token: $e');
        }
        throw Exception('Please sign in again to like videos');
      } else if (res.statusCode == 400) {
        // **FIX: Handle 400 Bad Request (user not authenticated or missing googleId)**
        final errorBody = res.body;
        AppLogger.log(
            '❌ VideoService: Bad request (${res.statusCode}), Body: $errorBody');
        try {
          final error = json.decode(errorBody);
          final errorMsg = error['error'] ?? 'User not authenticated';
          if (errorMsg.toString().contains('not authenticated') ||
              errorMsg.toString().contains('User not found')) {
            throw Exception('Please sign in again to like videos');
          }
          throw Exception(errorMsg.toString());
        } catch (e) {
          if (e.toString().contains('sign in')) {
            rethrow;
          }
          throw Exception('Failed to like video: ${e.toString()}');
        }
      } else if (res.statusCode == 404) {
        // **FIX: Handle 404 (video not found or user not found)**
        final errorBody = res.body;
        AppLogger.log(
            '❌ VideoService: Not found (${res.statusCode}), Body: $errorBody');
        try {
          final error = json.decode(errorBody);
          final errorMsg = error['error'] ?? 'Video or user not found';
          if (errorMsg.toString().contains('User not found')) {
            throw Exception(
                'Please sign in again. Your account may not be registered.');
          }
          throw Exception(errorMsg.toString());
        } catch (e) {
          throw Exception('Failed to like video: ${e.toString()}');
        }
      } else {
        final errorBody = res.body;
        AppLogger.log(
            '❌ VideoService: Like failed - Status: ${res.statusCode}, Body: $errorBody');
        try {
          final error = json.decode(errorBody);
          final errorMsg =
              error['error'] ?? error['message'] ?? 'Failed to like video';
          throw Exception(errorMsg.toString());
        } catch (e) {
          if (e is FormatException) {
            // Response is not JSON, show raw error
            throw Exception(
                'Failed to like video: ${errorBody.length > 100 ? errorBody.substring(0, 100) : errorBody}');
          }
          throw Exception('Failed to like video (Status: ${res.statusCode})');
        }
      }
    } catch (e) {
      AppLogger.log('❌ VideoService: Error toggling like: $e');
      if (e is TimeoutException) {
        throw Exception('Request timed out. Please try again.');
      } else if (e.toString().contains('sign in') ||
          e.toString().contains('authenticated')) {
        rethrow; // Re-throw authentication errors as-is
      }
      throw Exception('Failed to like video: ${e.toString()}');
    }
  }

  /// **Like a video (for backward compatibility)**
  Future<VideoModel> likeVideo(String videoId) async {
    return await toggleLike(videoId);
  }

  /// **Unlike a video (for backward compatibility)**
  Future<VideoModel> unlikeVideo(String videoId) async {
    return await toggleLike(videoId);
  }

  /// **Add comment to a video**
  Future<List<Comment>> addComment(
    String videoId,
    String text,
    String userId,
  ) async {
    try {
      AppLogger.log('💬 VideoService: Adding comment to video: $videoId');

      // **FIX: Validate inputs**
      if (videoId.isEmpty) {
        throw Exception('Video ID is required');
      }
      if (text.trim().isEmpty) {
        throw Exception('Comment text cannot be empty');
      }
      if (userId.isEmpty) {
        throw Exception('User ID is required. Please sign in to comment.');
      }

      // **FIX: Get user data and validate authentication**
      final userData = await _authService.getUserData();
      if (userData == null) {
        AppLogger.log('❌ VideoService: User not authenticated for comment');
        throw Exception('Please sign in to comment');
      }

      // **FIX: Use googleId from userData if userId doesn't match**
      final googleId = userData['googleId'] ?? userData['id'];
      final finalUserId = userId == googleId ? userId : googleId;

      if (finalUserId == null || finalUserId.isEmpty) {
        AppLogger.log('❌ VideoService: User ID not found in user data');
        throw Exception('User ID not found. Please sign in again.');
      }

      AppLogger.log(
          '💬 VideoService: Comment - userId: ${finalUserId.substring(0, 8)}..., text length: ${text.length}');

      final headers = await _getAuthHeaders();
      headers['Content-Type'] = 'application/json';

      final resolvedBaseUrl = await getBaseUrlWithFallback();

      // **FIX: Log request details**
      AppLogger.log(
          '💬 VideoService: Comment request URL: ${NetworkHelper.apiBaseUrl}/videos/$videoId/comments');
      AppLogger.log(
          '💬 VideoService: Comment request - Auth header present: ${headers.containsKey('Authorization')}');
      final res = await http
          .post(
            Uri.parse('${NetworkHelper.apiBaseUrl}/videos/$videoId/comments'),
            headers: headers,
            body: json.encode({'userId': finalUserId, 'text': text.trim()}),
          )
          .timeout(const Duration(seconds: 15));

      AppLogger.log(
          '📡 VideoService: Comment response status: ${res.statusCode}');
      AppLogger.log(
          '📡 VideoService: Comment response body: ${res.body.length > 200 ? res.body.substring(0, 200) : res.body}');

      if (res.statusCode == 200) {
        try {
          final List<dynamic> commentsJson = json.decode(res.body);
          final comments =
              commentsJson.map((json) => Comment.fromJson(json)).toList();
          AppLogger.log(
              '✅ VideoService: Comment added successfully. Total comments: ${comments.length}');
          return comments;
        } catch (e) {
          AppLogger.log('❌ VideoService: Error parsing comment response: $e');
          throw Exception('Invalid response format from server');
        }
      } else if (res.statusCode == 401 || res.statusCode == 403) {
        AppLogger.log(
            '❌ VideoService: Authentication failed (${res.statusCode})');
        throw Exception('Please sign in again to add comments');
      } else if (res.statusCode == 400) {
        final errorBody = res.body;
        AppLogger.log(
            '❌ VideoService: Bad request (${res.statusCode}), Body: $errorBody');
        try {
          final error = json.decode(errorBody);
          final errorMsg = error['error'] ?? 'Invalid request';
          throw Exception(errorMsg.toString());
        } catch (e) {
          throw Exception(
              'Invalid request: ${errorBody.length > 100 ? errorBody.substring(0, 100) : errorBody}');
        }
      } else if (res.statusCode == 404) {
        final errorBody = res.body;
        AppLogger.log(
            '❌ VideoService: Not found (${res.statusCode}), Body: $errorBody');
        try {
          final error = json.decode(errorBody);
          final errorMsg = error['error'] ?? 'Video or user not found';
          if (errorMsg.toString().contains('User not found')) {
            throw Exception('User not found. Please sign in again.');
          }
          throw Exception(errorMsg.toString());
        } catch (e) {
          throw Exception('Video or user not found');
        }
      } else {
        final errorBody = res.body;
        AppLogger.log(
            '❌ VideoService: Comment failed - Status: ${res.statusCode}, Body: $errorBody');
        try {
          final error = json.decode(errorBody);
          final errorMsg =
              error['error'] ?? error['message'] ?? 'Failed to add comment';
          throw Exception(errorMsg.toString());
        } catch (e) {
          if (e is FormatException) {
            throw Exception(
                'Failed to add comment: ${errorBody.length > 100 ? errorBody.substring(0, 100) : errorBody}');
          }
          throw Exception('Failed to add comment (Status: ${res.statusCode})');
        }
      }
    } catch (e) {
      AppLogger.log('❌ VideoService: Error adding comment: $e');
      if (e is TimeoutException) {
        throw Exception('Request timed out. Please try again.');
      } else if (e.toString().contains('sign in') ||
          e.toString().contains('authenticated')) {
        rethrow; // Re-throw authentication errors as-is
      }
      rethrow;
    }
  }

  /// **Get comments for a video**
  Future<List<Comment>> getComments(
    String videoId, {
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final headers = await _getAuthHeaders();
      final resolvedBaseUrl = await getBaseUrlWithFallback();
      final res = await http
          .get(
            Uri.parse(
                '${NetworkHelper.apiBaseUrl}/videos/$videoId/comments?page=$page&limit=$limit'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final List<dynamic> commentsJson = json.decode(res.body);
        return commentsJson.map((json) => Comment.fromJson(json)).toList();
      } else if (res.statusCode == 404) {
        return [];
      } else {
        final error = json.decode(res.body);
        throw Exception(error['error'] ?? 'Failed to fetch comments');
      }
    } catch (e) {
      if (e is TimeoutException) {
        throw Exception('Request timed out. Please try again.');
      }
      rethrow;
    }
  }

  /// **Delete a comment**
  Future<List<Comment>> deleteComment(String videoId, String commentId) async {
    try {
      final headers = await _getAuthHeaders();

      // Get current user ID for the request
      final userData = await _authService.getUserData();
      if (userData == null || userData['googleId'] == null) {
        throw Exception('User not authenticated');
      }

      final resolvedBaseUrl = await getBaseUrlWithFallback();
      final res = await http
          .delete(
            Uri.parse(
                '${NetworkHelper.apiBaseUrl}/videos/$videoId/comments/$commentId'),
            headers: headers,
            body: json.encode({'userId': userData['googleId']}),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        // Return updated comments list
        final List<dynamic> commentsJson = json.decode(res.body);
        return commentsJson.map((json) => Comment.fromJson(json)).toList();
      } else if (res.statusCode == 401) {
        throw Exception('Please sign in to delete comments');
      } else if (res.statusCode == 403) {
        throw Exception('You can only delete your own comments');
      } else if (res.statusCode == 404) {
        throw Exception('Comment not found');
      } else {
        final error = json.decode(res.body);
        throw Exception(error['error'] ?? 'Failed to delete comment');
      }
    } catch (e) {
      if (e is TimeoutException) {
        throw Exception('Request timed out. Please try again.');
      }
      rethrow;
    }
  }

  /// **Like/unlike a comment**
  Future<Comment> likeComment(String videoId, String commentId) async {
    try {
      final headers = await _getAuthHeaders();
      final resolvedBaseUrl = await getBaseUrlWithFallback();
      final res = await http
          .post(
            Uri.parse(
                '$resolvedBaseUrl/api/videos/$videoId/comments/$commentId/like'),
            headers: headers,
            body: json.encode({}),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final commentJson = json.decode(res.body);
        return Comment.fromJson(commentJson);
      } else if (res.statusCode == 401) {
        throw Exception('Please sign in to like comments');
      } else if (res.statusCode == 404) {
        throw Exception('Comment not found');
      } else {
        final error = json.decode(res.body);
        throw Exception(error['error'] ?? 'Failed to like comment');
      }
    } catch (e) {
      if (e is TimeoutException) {
        throw Exception('Request timed out. Please try again.');
      }
      rethrow;
    }
  }

  /// **Get user videos**
  Future<List<VideoModel>> getUserVideos(String userId,
      {bool forceRefresh = false, int page = 1, int limit = 9}) async {
    try {
      // **FIXED: Validate userId before making request**
      if (userId.isEmpty) {
        throw Exception('User ID is empty. Please sign in again.');
      }

      final resolvedBaseUrl = await getBaseUrlWithFallback();
      String url = '$resolvedBaseUrl/api/videos/user/$userId?page=$page&limit=$limit';

      // **NEW: Append refresh=true if forceRefresh is requested**
      if (forceRefresh) {
        url += '&refresh=true';
      }

      AppLogger.log('📡 VideoService: Fetching videos for userId: $userId');
      AppLogger.log('📡 VideoService: URL: $url');

      final headers = await _getAuthHeaders();

      // **DEBUG: Log token presence (without exposing full token)**
      final hasToken = headers.containsKey('Authorization') &&
          headers['Authorization']?.isNotEmpty == true;
      AppLogger.log('📡 VideoService: Auth token present: $hasToken');

      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 30));

      AppLogger.log('📡 VideoService: Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final List<dynamic> videoList = json.decode(response.body);

        final videos = videoList.map((json) {
          // **HLS URL Priority**: Use HLS for better streaming
          if (json['hlsPlaylistUrl'] != null &&
              json['hlsPlaylistUrl'].toString().isNotEmpty) {
            String hlsUrl = json['hlsPlaylistUrl'].toString();
            if (!hlsUrl.startsWith('http')) {
              if (hlsUrl.startsWith('/')) {
                hlsUrl = hlsUrl.substring(1);
              }
              json['videoUrl'] = '$resolvedBaseUrl/$hlsUrl';
            } else {
              json['videoUrl'] = hlsUrl;
            }
            AppLogger.log(
                '🔗 VideoService: Using HLS Playlist URL: ${json['videoUrl']}');
          } else if (json['hlsMasterPlaylistUrl'] != null &&
              json['hlsMasterPlaylistUrl'].toString().isNotEmpty) {
            String masterUrl = json['hlsMasterPlaylistUrl'].toString();
            if (!masterUrl.startsWith('http')) {
              if (masterUrl.startsWith('/')) {
                masterUrl = masterUrl.substring(1);
              }
              json['videoUrl'] = '$resolvedBaseUrl/$masterUrl';
            } else {
              json['videoUrl'] = masterUrl;
            }
            AppLogger.log(
                '🔗 VideoService: Using HLS Master URL: ${json['videoUrl']}');
          } else {
            // **Fallback**: Ensure relative URLs are complete
            if (json['videoUrl'] != null &&
                !json['videoUrl'].toString().startsWith('http')) {
              String videoUrl = json['videoUrl'].toString();
              if (videoUrl.startsWith('/')) {
                videoUrl = videoUrl.substring(1);
              }
              json['videoUrl'] = '$resolvedBaseUrl/$videoUrl';
            }
          }

          // **Ensure other URLs are complete**
          if (json['originalVideoUrl'] != null &&
              !json['originalVideoUrl'].toString().startsWith('http')) {
            String originalUrl = json['originalVideoUrl'].toString();
            if (originalUrl.startsWith('/')) {
              originalUrl = originalUrl.substring(1);
            }
            json['originalVideoUrl'] = '$resolvedBaseUrl/$originalUrl';
          }
          if (json['thumbnailUrl'] != null &&
              !json['thumbnailUrl'].toString().startsWith('http')) {
            String thumbnailUrl = json['thumbnailUrl'].toString();
            if (thumbnailUrl.startsWith('/')) {
              thumbnailUrl = thumbnailUrl.substring(1);
            }
            json['thumbnailUrl'] = '$resolvedBaseUrl/$thumbnailUrl';
          }

          return VideoModel.fromJson(json);
        }).toList();

        return videos;
      } else if (response.statusCode == 404) {
        return [];
      } else if (response.statusCode == 401) {
        AppLogger.log(
            '❌ VideoService: 401 Unauthorized - Token may be expired or invalid');
        throw Exception(
            'Failed to fetch user videos: 401 - Please sign in again');
      } else {
        AppLogger.log(
            '❌ VideoService: Failed to fetch user videos - Status: ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to fetch user videos: ${response.statusCode}');
      }
    } catch (e) {
      if (e is TimeoutException) {
        throw Exception(
          'Request timed out. Please check your internet connection and try again.',
        );
      }
      rethrow;
    }
  }

  /// **Upload video with compression and validation**
  Future<Map<String, dynamic>> uploadVideo(
    File videoFile,
    String title, [
    String? description,
    String? link,
    Function(double)? onProgress,
  ]) async {
    try {
      AppLogger.log('🚀 VideoService: Starting video upload...');

      // **Check server health**
      final isHealthy = await checkServerHealth();
      if (!isHealthy) {
        throw Exception(
          'Server is not responding. Please check your connection and try again.',
        );
      }

      // **Check file size**
      final fileSize = await videoFile.length();
      if (fileSize > maxFileSize) {
        throw Exception('File too large. Maximum size is 100MB');
      }

      // **Check if video is too long**
      final isLong = await isLongVideo(videoFile.path);

      // **Get authentication**
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception(
          'User not authenticated. Please sign in to upload videos.',
        );
      }

      // **Compress video if needed**
      File? finalVideoFile = videoFile;
      if (fileSize > 50 * 1024 * 1024) {
        // Compress if > 50MB
        AppLogger.log('🔄 VideoService: Compressing large video...');
        final compressedFile = await compressVideo(videoFile);
        if (compressedFile != null) {
          finalVideoFile = compressedFile;
        }
      }

      // **Create multipart request**
      final resolvedBaseUrl = await getBaseUrlWithFallback();
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$resolvedBaseUrl/api/upload/video'),
      );

      final headers = await _getAuthHeaders();
      // Only forward Authorization; let MultipartRequest set its own Content-Type
      final authHeader = headers['Authorization'];
      if (authHeader != null) {
        request.headers['Authorization'] = authHeader;
      }

      // **Add video file**
      request.files.add(
        await http.MultipartFile.fromPath(
          'video',
          finalVideoFile.path,
          contentType: MediaType('video', 'mp4'),
        ),
      );

      // Do not attach a separate thumbnail file. Backend generates thumbnails after processing.

      // **Add fields**
      request.fields['videoName'] = title;
      // Description intentionally omitted from upload flow
      String resolvedVideoType = 'yog';
      if (link != null && link.isNotEmpty) {
        request.fields['link'] = link;
      }
      try {
        // Using Zone to retrieve optional metadata injected by caller
        final dynamic metadata = Zone.current['upload_metadata'];
        if (metadata is Map<String, dynamic>) {
          final String? category = metadata['category'] as String?;
          final List<String>? tags = (metadata['tags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList();
          if (category != null && category.isNotEmpty) {
            request.fields['category'] = category;
          }
          if (tags != null && tags.isNotEmpty) {
            request.fields['tags'] = json.encode(tags);
          }
          final String? metadataVideoType = metadata['videoType'] as String?;
          if (metadataVideoType != null && metadataVideoType.isNotEmpty) {
            resolvedVideoType = metadataVideoType;
          }
          final String? seriesId = metadata['seriesId'] as String?;
          if (seriesId != null && seriesId.isNotEmpty) {
            request.fields['seriesId'] = seriesId;
          }
          final int? episodeNumber = metadata['episodeNumber'] as int?;
          if (episodeNumber != null) {
            request.fields['episodeNumber'] = episodeNumber.toString();
          }
        }
      } catch (_) {}

      request.fields['videoType'] = resolvedVideoType;

      // **Send request**
      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 30),
        onTimeout: () {
          throw TimeoutException(
            'Upload likely failed or is taking too long (30m limit). Please check your internet connection.',
          );
        },
      );

      final responseBody = await streamedResponse.stream.bytesToString();

      // **FIX: Add response validation**
      if (responseBody.isEmpty) {
        throw Exception('Empty response from server');
      }

      AppLogger.log(
        '📡 VideoService: Upload response status: ${streamedResponse.statusCode}',
      );
      AppLogger.log(
          '📄 VideoService: Upload response body (first 500 chars): ${responseBody.length > 500 ? responseBody.substring(0, 500) : responseBody}');

      // **FIX: Handle non-JSON responses (e.g., HTML error pages from Cloudflare 524)**
      Map<String, dynamic> responseData;
      try {
        responseData = json.decode(responseBody);
      } catch (e) {
        // Check if it's a Cloudflare error page or HTML response
        if (responseBody.trim().startsWith('<') ||
            responseBody.contains('<!DOCTYPE') ||
            responseBody.contains('<html')) {
          // HTML error page (likely Cloudflare 524 timeout)
          if (streamedResponse.statusCode == 524 ||
              responseBody.contains('524')) {
            throw Exception(
              'Upload timed out on server (524). The video file may be too large or the server is busy. Please try again with a smaller video or wait a few minutes.',
            );
          } else if (streamedResponse.statusCode >= 500) {
            throw Exception(
              'Server error (${streamedResponse.statusCode}). Please try again later.',
            );
          } else {
            throw Exception(
              'Invalid response from server. Please try again.',
            );
          }
        } else {
          // Other non-JSON response
          throw Exception(
            'Invalid response format from server. Please try again.',
          );
        }
      }

      // responseData is guaranteed to be non-null here (json.decode would have thrown if invalid)

      if (streamedResponse.statusCode == 201) {
        final videoData = responseData['video'];

        // **FIX: Add null checks to prevent NoSuchMethodError**
        if (videoData == null) {
          AppLogger.log('❌ VideoService: Video data is null in response');
          throw Exception('Invalid response: Video data is missing');
        }

        return {
          'id': videoData['_id'] ?? videoData['id'] ?? '',
          'title': videoData['videoName'] ?? title,
          'videoUrl':
              videoData['videoUrl'] ?? videoData['hlsPlaylistUrl'] ?? '',
          'thumbnail': videoData['thumbnailUrl'] ?? '',
          'originalVideoUrl': videoData['originalVideoUrl'] ?? '',
          'duration': '0:00',
          'views': 0,
          'uploader': userData['name'] ?? 'Unknown',
          'uploadTime': 'Just now',
          'isLongVideo': isLong,
          'link': videoData['link'] ?? '',
          'processingStatus': videoData['processingStatus'] ?? 'pending',
        };
      } else {
        AppLogger.log(
          '❌ VideoService: Upload failed with status ${streamedResponse.statusCode}',
        );
        AppLogger.log(
            '❌ VideoService: Error details: ${responseData.toString()}');

        // **FIX: Handle specific error codes**
        if (streamedResponse.statusCode == 524) {
          throw Exception(
            'Upload timed out on server (524). The video file may be too large or the server is busy. Please try again with a smaller video or wait a few minutes.',
          );
        } else if (streamedResponse.statusCode == 413) {
          throw Exception(
            'File too large. Maximum size is 100MB.',
          );
        } else if (streamedResponse.statusCode == 401 ||
            streamedResponse.statusCode == 403) {
          throw Exception(
            'Authentication failed. Please sign in again.',
          );
        }

        final errorMessage = responseData['error']?.toString() ??
            responseData['details']?.toString() ??
            'Failed to upload video (Status: ${streamedResponse.statusCode})';
        throw Exception('❌ $errorMessage');
      }
    } catch (e) {
      AppLogger.log('❌ VideoService: Error uploading video: $e');
      if (e is TimeoutException) {
        throw Exception(
          'Upload timed out. Please check your internet connection and try again.',
        );
      } else if (e is SocketException) {
        throw Exception(
          'Could not connect to server. Please check if the server is running.',
        );
      } else if (e is FormatException) {
        // Already handled above, but catch here to provide user-friendly message
        throw Exception(
          'Invalid response from server. Please try again.',
        );
      }
      rethrow;
    }
  }

  /// **Delete video**
  Future<bool> deleteVideo(String videoId) async {
    try {
      AppLogger.log('🗑️ VideoService: Attempting to delete video: $videoId');

      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('Please sign in to delete videos');
      }

      final headers = await _getAuthHeaders();
      final resolvedBaseUrl = await getBaseUrlWithFallback();
      final res = await http
          .delete(Uri.parse('$resolvedBaseUrl/api/videos/$videoId'),
              headers: headers)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 || res.statusCode == 204) {
        AppLogger.log('✅ VideoService: Video deleted successfully');
        return true;
      } else if (res.statusCode == 401) {
        throw Exception('Please sign in again to delete videos');
      } else if (res.statusCode == 403) {
        throw Exception('You do not have permission to delete this video');
      } else if (res.statusCode == 404) {
        throw Exception('Video not found');
      } else {
        final error = json.decode(res.body);
        throw Exception(error['error'] ?? 'Failed to delete video');
      }
    } catch (e) {
      AppLogger.log('❌ VideoService: Error deleting video: $e');
      if (e is TimeoutException) {
        throw Exception('Request timed out. Please try again.');
      }
      rethrow;
    }
  }

  /// **Increment share count** (without showing share dialog)
  Future<void> incrementShares(String videoId) async {
    try {
      final headers = await _getAuthHeaders();
      final resolvedBaseUrl = await getBaseUrlWithFallback();
      final res = await httpClientService.post(
        Uri.parse('$resolvedBaseUrl/api/videos/$videoId/share'),
        headers: headers,
      );

      if (res.statusCode != 200) {
        AppLogger.log('⚠️ Failed to increment share count: ${res.statusCode}');
      }
    } catch (e) {
      AppLogger.log('⚠️ Error incrementing shares: $e');
      // Don't throw - sharing should work even if server tracking fails
    }
  }

  /// **Get video processing status**
  Future<Map<String, dynamic>?> getVideoProcessingStatus(String videoId) async {
    try {
      AppLogger.log(
          '🔄 VideoService: Getting processing status for video: $videoId');

      final headers = await _getAuthHeaders();
      final resolvedBaseUrl = await getBaseUrlWithFallback();
      final res = await http
          .get(Uri.parse('$resolvedBaseUrl/api/upload/video/$videoId/status'),
              headers: headers)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final responseData = json.decode(res.body);
        AppLogger.log(
            '✅ VideoService: Processing status retrieved successfully');
        return responseData;
      } else if (res.statusCode == 404) {
        AppLogger.log('⚠️ VideoService: Video not found for status check');
        return null;
      } else {
        AppLogger.log(
            '❌ VideoService: Failed to get processing status: ${res.statusCode}');
        return null;
      }
    } catch (e) {
      AppLogger.log('❌ VideoService: Error getting processing status: $e');
      return null;
    }
  }

  /// **Check server health**
  Future<bool> checkServerHealth() async {
    try {
      // Resolve base URL with local-first fallback
      final resolvedBaseUrl = await getBaseUrlWithFallback();
      final response = await http
          .get(Uri.parse('$resolvedBaseUrl/api/health'))
          .timeout(const Duration(seconds: 15));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// **Check if video is too long**
  Future<bool> isLongVideo(String videoPath) async {
    try {
      final controller = VideoPlayerController.file(File(videoPath));
      await controller.initialize();
      final duration = controller.value.duration;
      await controller.dispose();
      return duration.inSeconds > maxShortVideoDuration;
    } catch (e) {
      AppLogger.log('❌ VideoService: Error checking video duration: $e');
      return false;
    }
  }

  /// **Compress video while preserving display (resolution/aspect) as much as possible**
  /// Uses DefaultQuality so encoder mainly reduces bitrate, not dimensions.
  Future<File?> compressVideo(File videoFile) async {
    try {
      AppLogger.log(
          '🔄 VideoService: Compressing video (preserve resolution)...');

      final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
        videoFile.path,
        quality: VideoQuality.DefaultQuality,
        deleteOrigin: false,
      );

      if (mediaInfo?.file != null) {
        AppLogger.log(
          '✅ VideoService: Video compressed successfully. '
          'Original display (orientation/aspect ratio) should remain the same.',
        );
        return mediaInfo!.file;
      } else {
        AppLogger.log('❌ VideoService: Video compression failed');
        return null;
      }
    } catch (e) {
      AppLogger.log('❌ VideoService: Error compressing video: $e');
      return null;
    }
  }

  /// **Get authentication headers**
  Future<Map<String, String>> _getAuthHeaders() async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      // **CRITICAL FIX: Always get token using AuthService.getToken() (most reliable source)**
      String? token = await AuthService.getToken();

      // Fallback to userData token if AuthService doesn't have it
      if (token == null || token.isEmpty) {
        AppLogger.log(
            '⚠️ VideoService: Token not found via AuthService, checking userData...');
        token = userData['token'];
      }

      // Final check - if still no token, throw error
      if (token == null || token.isEmpty) {
        AppLogger.log(
            '❌ VideoService: No token found via AuthService or userData');
        throw Exception(
            'Authentication token not found. Please sign in again.');
      }

      AppLogger.log(
          '✅ VideoService: Token retrieved successfully (length: ${token.length})');

      return {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      };
    } catch (e) {
      AppLogger.log('❌ VideoService: Error getting auth headers: $e');
      rethrow;
    }
  }

  // **AD INTEGRATION METHODS - From original VideoService**

  /// **Get videos with integrated ads**
  Future<Map<String, dynamic>> getVideosWithAds({
    int page = 1,
    int limit = 15,
    int adInsertionFrequency = 3,
  }) async {
    try {
      AppLogger.log('🔍 VideoService: Fetching videos with ads...');

      final videosResult = await getVideos(page: page, limit: limit);
      final videos =
          (videosResult['videos'] as List<dynamic>).cast<VideoModel>();

      List<AdModel> ads = const [];
      try {
        ads = await _adService.getActiveAds();
      } catch (adError) {
        AppLogger.log(
            '⚠️ VideoService: Failed to fetch ads, continuing without ads: $adError');
      }

      List<dynamic> integratedFeed = videos;
      try {
        if (ads.isNotEmpty) {
          integratedFeed = _integrateAdsIntoFeed(
            videos,
            ads,
            adInsertionFrequency,
          );
        }
      } catch (integrationError) {
        AppLogger.log(
          '⚠️ VideoService: Failed to integrate ads, using videos only: $integrationError',
        );
        integratedFeed = videos;
      }

      return {
        'videos': integratedFeed,
        'hasMore': videosResult['hasMore'] ?? false,
        'total': videosResult['total'] ?? 0,
        'currentPage': page,
        'totalPages': videosResult['totalPages'] ?? 1,
        'adCount': ads.length,
        'integratedCount': integratedFeed.length,
      };
    } catch (e) {
      AppLogger.log('❌ VideoService: Error fetching videos with ads: $e');
      rethrow;
    }
  }

  /// **Integrate ads into video feed**
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

    AppLogger.log('🔍 VideoService: Integrated $adIndex ads into feed');
    return integratedFeed;
  }

  /// **Convert AdModel to VideoModel-like structure**
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

  /// **Upload video to server**
  Future<Map<String, dynamic>?> uploadVideoFile(
    File videoFile,
    String title, {
    String description = '',
    String link = '',
    String videoType = 'yog',
    String category = '',
    List<String> tags = const [],
  }) async {
    try {
      AppLogger.log('🚀 VideoService: Starting video upload...');
      AppLogger.log('📁 File: ${videoFile.path}');
      AppLogger.log('📝 Title: $title');
      AppLogger.log('🏷️ Category: $category');

      // Get auth headers
      final headers = await _getAuthHeaders();

      // Create multipart request
      final resolvedBaseUrl = await getBaseUrlWithFallback();
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$resolvedBaseUrl/api/videos/upload'),
      );

      // Add headers
      request.headers.addAll(headers);

      // Add video file
      request.files.add(
        await http.MultipartFile.fromPath(
          'video',
          videoFile.path,
          contentType: MediaType('video', 'mp4'),
        ),
      );

      // Add form fields
      request.fields['videoName'] = title;
      request.fields['description'] = description;
      request.fields['link'] = link;
      request.fields['videoType'] = videoType;
      request.fields['category'] = category;

      if (tags.isNotEmpty) {
        request.fields['tags'] = tags.join(',');
      }

      AppLogger.log('📤 VideoService: Sending upload request...');

      // Send request
      final response = await request.send().timeout(
            const Duration(minutes: 30),
          );

      final responseBody = await response.stream.bytesToString();
      final data = json.decode(responseBody);

      if (response.statusCode == 201) {
        AppLogger.log('✅ VideoService: Upload successful');
        return data;
      } else {
        AppLogger.log('❌ VideoService: Upload failed: ${response.statusCode}');
        throw Exception(data['error'] ?? 'Upload failed');
      }
    } catch (e) {
      AppLogger.log('❌ VideoService: Upload error: $e');
      rethrow;
    }
  }

  // **DISPOSE METHOD**
  void dispose() {
    _videoIndexChangeListeners.clear();
    _videoScreenStateListeners.clear();
    AppLogger.log('🗑️ VideoService: Disposed all listeners');
  }
}
