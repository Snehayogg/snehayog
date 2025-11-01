import 'dart:convert';
// import 'dart:typed_data';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:flutter/material.dart';
import 'package:http_parser/http_parser.dart';
import 'package:video_compress/video_compress.dart';
import 'package:share_plus/share_plus.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/model/ad_model.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/services/ad_service.dart';
import 'package:vayu/config/app_config.dart';

/// **OPTIMIZED VideoService - Single source of truth for all video operations**
/// Merged from VideoService, BaseVideoService, and InstagramVideoService
/// Eliminates code duplication and provides consistent API
class VideoService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  final AuthService _authService = AuthService();
  final AdService _adService = AdService();

  // Reusable HTTP client to avoid new TLS handshakes per request
  final http.Client _client = http.Client();

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
      print('🎬 VideoService: Video index changed from $oldIndex to $newIndex');

      for (final listener in _videoIndexChangeListeners) {
        try {
          listener(newIndex);
        } catch (e) {
          print('❌ VideoService: Error in video index change listener: $e');
        }
      }
    }
  }

  void updateVideoScreenState(bool isActive) {
    if (_isVideoScreenActive != isActive) {
      _isVideoScreenActive = isActive;
      print(
        '🔄 VideoService: Video screen state changed to ${isActive ? "ACTIVE" : "INACTIVE"}',
      );

      for (final listener in _videoScreenStateListeners) {
        try {
          listener(isActive);
        } catch (e) {
          print('❌ VideoService: Error in video screen state listener: $e');
        }
      }
    }
  }

  void updateAppForegroundState(bool inForeground) {
    if (_isAppInForeground != inForeground) {
      _isAppInForeground = inForeground;
      print(
        '📱 VideoService: App foreground state changed to ${inForeground ? "FOREGROUND" : "BACKGROUND"}',
      );
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
  Future<Map<String, dynamic>> getVideos({
    int page = 1,
    int limit = 10,
    String? videoType,
  }) async {
    try {
      // Get base URL with Railway first, local fallback
      final baseUrl = await getBaseUrlWithFallback();
      print('🔍 VideoService: Using base URL: $baseUrl');

      String url = '$baseUrl/api/videos?page=$page&limit=$limit';
      // Map 'yug' (app label) to backend 'yog' filter
      final normalizedType = (videoType == 'yug') ? 'yog' : videoType;
      if (normalizedType != null &&
          (normalizedType == 'yog' || normalizedType == 'sneha')) {
        url += '&videoType=$normalizedType';
        print('🔍 VideoService: Filtering by videoType: $videoType');
      }
      final response = await _makeRequest(
        () => _client.get(Uri.parse(url)),
        timeout: const Duration(seconds: 15),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        final List<dynamic> videoList = responseData['videos'];

        final videos = videoList.map((json) {
          // **DEBUG: Log all video data for debugging**
          print('🔍 VideoService: Video data for ${json['videoName']}:');
          print('  - videoUrl: ${json['videoUrl']}');
          print('  - hlsPlaylistUrl: ${json['hlsPlaylistUrl']}');
          print('  - hlsMasterPlaylistUrl: ${json['hlsMasterPlaylistUrl']}');
          print('  - isHLSEncoded: ${json['isHLSEncoded']}');
          print('  - hlsVariants: ${json['hlsVariants']?.length ?? 0}');

          // **HLS URL Priority**: Use HLS for better streaming
          if (json['hlsPlaylistUrl'] != null &&
              json['hlsPlaylistUrl'].toString().isNotEmpty) {
            String hlsUrl = json['hlsPlaylistUrl'].toString();
            if (!hlsUrl.startsWith('http')) {
              // Remove leading slash if present to avoid double slash
              if (hlsUrl.startsWith('/')) {
                hlsUrl = hlsUrl.substring(1);
              }
              json['videoUrl'] = '$baseUrl/$hlsUrl';
            } else {
              json['videoUrl'] = hlsUrl;
            }
            print(
                '🔗 VideoService: Using HLS Playlist URL: ${json['videoUrl']}');
          } else if (json['hlsMasterPlaylistUrl'] != null &&
              json['hlsMasterPlaylistUrl'].toString().isNotEmpty) {
            String masterUrl = json['hlsMasterPlaylistUrl'].toString();
            if (!masterUrl.startsWith('http')) {
              if (masterUrl.startsWith('/')) {
                masterUrl = masterUrl.substring(1);
              }
              json['videoUrl'] = '$baseUrl/$masterUrl';
            } else {
              json['videoUrl'] = masterUrl;
            }
            print('🔗 VideoService: Using HLS Master URL: ${json['videoUrl']}');
          } else {
            // **Fallback**: Ensure relative URLs are complete
            if (json['videoUrl'] != null &&
                !json['videoUrl'].toString().startsWith('http')) {
              String videoUrl = json['videoUrl'].toString();
              // Remove leading slash if present to avoid double slash
              if (videoUrl.startsWith('/')) {
                videoUrl = videoUrl.substring(1);
              }
              json['videoUrl'] = '$baseUrl/$videoUrl';
            }
            print(
              '🔗 VideoService: Using original video URL: ${json['videoUrl']}',
            );
          }

          return VideoModel.fromJson(json);
        }).toList();

        return {
          'videos': List<VideoModel>.from(videos),
          'hasMore': responseData['hasMore'] ?? false,
        };
      } else {
        throw Exception('Failed to load videos: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// **Get video by ID**
  Future<VideoModel> getVideoById(String id) async {
    try {
      final resolvedBaseUrl = await getBaseUrlWithFallback();
      final res = await http.get(Uri.parse('$resolvedBaseUrl/api/videos/$id'));
      if (res.statusCode == 200) {
        return VideoModel.fromJson(json.decode(res.body));
      } else {
        final error = json.decode(res.body);
        throw Exception(error['error'] ?? 'Failed to load video');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Network error: $e');
    }
  }

  /// **Toggle like for a video (like/unlike)**
  Future<VideoModel> toggleLike(String videoId) async {
    try {
      print('🔄 VideoService: Toggling like for video: $videoId');

      final headers = await _getAuthHeaders();
      headers['Content-Type'] = 'application/json';

      final resolvedBaseUrl = await getBaseUrlWithFallback();
      final res = await http
          .post(
            Uri.parse('$resolvedBaseUrl/api/videos/$videoId/like'),
            headers: headers,
            body: json.encode({}),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return VideoModel.fromJson(data);
      } else if (res.statusCode == 401) {
        throw Exception('Please sign in to like videos');
      } else {
        final error = json.decode(res.body);
        throw Exception(error['error'] ?? 'Failed to toggle like');
      }
    } catch (e) {
      print('❌ VideoService: Error toggling like: $e');
      if (e is TimeoutException) {
        throw Exception('Request timed out. Please try again.');
      }
      rethrow;
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
      final headers = await _getAuthHeaders();
      final resolvedBaseUrl = await getBaseUrlWithFallback();
      final res = await http
          .post(
            Uri.parse('$resolvedBaseUrl/api/videos/$videoId/comments'),
            headers: headers,
            body: json.encode({'userId': userId, 'text': text}),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final List<dynamic> commentsJson = json.decode(res.body);
        return commentsJson.map((json) => Comment.fromJson(json)).toList();
      } else if (res.statusCode == 401) {
        throw Exception('Please sign in again to add comments');
      } else {
        final error = json.decode(res.body);
        throw Exception(error['error'] ?? 'Failed to add comment');
      }
    } catch (e) {
      if (e is TimeoutException) {
        throw Exception('Request timed out. Please try again.');
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
                '$resolvedBaseUrl/api/videos/$videoId/comments?page=$page&limit=$limit'),
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
                '$resolvedBaseUrl/api/videos/$videoId/comments/$commentId'),
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
  Future<List<VideoModel>> getUserVideos(String userId) async {
    try {
      final resolvedBaseUrl = await getBaseUrlWithFallback();
      final url = '$resolvedBaseUrl/api/videos/user/$userId';
      final headers = await _getAuthHeaders();

      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 30));

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
            print(
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
            print('🔗 VideoService: Using HLS Master URL: ${json['videoUrl']}');
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
      } else {
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
      print('🚀 VideoService: Starting video upload...');

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
        print('🔄 VideoService: Compressing large video...');
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
      request.fields['videoType'] = 'yog';
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
        }
      } catch (_) {}

      // **Send request**
      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 10),
        onTimeout: () {
          throw TimeoutException(
            'Upload timed out. Please check your internet connection and try again.',
          );
        },
      );

      final responseBody = await streamedResponse.stream.bytesToString();

      // **FIX: Add response validation**
      if (responseBody.isEmpty) {
        throw Exception('Empty response from server');
      }

      final responseData = json.decode(responseBody);

      print(
        '📡 VideoService: Upload response status: ${streamedResponse.statusCode}',
      );
      print('📄 VideoService: Upload response body: $responseBody');

      // **FIX: Validate response structure**
      if (responseData == null) {
        throw Exception('Invalid JSON response from server');
      }

      if (streamedResponse.statusCode == 201) {
        final videoData = responseData['video'];

        // **FIX: Add null checks to prevent NoSuchMethodError**
        if (videoData == null) {
          print('❌ VideoService: Video data is null in response');
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
        print(
          '❌ VideoService: Upload failed with status ${streamedResponse.statusCode}',
        );
        print('❌ VideoService: Error details: ${responseData.toString()}');

        final errorMessage = responseData['error']?.toString() ??
            responseData['details']?.toString() ??
            'Failed to upload video (Status: ${streamedResponse.statusCode})';
        throw Exception('❌ $errorMessage');
      }
    } catch (e) {
      print('❌ VideoService: Error uploading video: $e');
      if (e is TimeoutException) {
        throw Exception(
          'Upload timed out. Please check your internet connection and try again.',
        );
      } else if (e is SocketException) {
        throw Exception(
          'Could not connect to server. Please check if the server is running.',
        );
      }
      rethrow;
    }
  }

  /// **Delete video**
  Future<bool> deleteVideo(String videoId) async {
    try {
      print('🗑️ VideoService: Attempting to delete video: $videoId');

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
        print('✅ VideoService: Video deleted successfully');
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
      print('❌ VideoService: Error deleting video: $e');
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
      final res = await http.post(
        Uri.parse('$resolvedBaseUrl/api/videos/$videoId/share'),
        headers: headers,
      );

      if (res.statusCode != 200) {
        print('⚠️ Failed to increment share count: ${res.statusCode}');
      }
    } catch (e) {
      print('⚠️ Error incrementing shares: $e');
      // Don't throw - sharing should work even if server tracking fails
    }
  }

  /// **Get video processing status**
  Future<Map<String, dynamic>?> getVideoProcessingStatus(String videoId) async {
    try {
      print('🔄 VideoService: Getting processing status for video: $videoId');

      final headers = await _getAuthHeaders();
      final resolvedBaseUrl = await getBaseUrlWithFallback();
      final res = await http
          .get(Uri.parse('$resolvedBaseUrl/api/upload/video/$videoId/status'),
              headers: headers)
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final responseData = json.decode(res.body);
        print('✅ VideoService: Processing status retrieved successfully');
        return responseData;
      } else if (res.statusCode == 404) {
        print('⚠️ VideoService: Video not found for status check');
        return null;
      } else {
        print(
            '❌ VideoService: Failed to get processing status: ${res.statusCode}');
        return null;
      }
    } catch (e) {
      print('❌ VideoService: Error getting processing status: $e');
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
          .timeout(const Duration(seconds: 5));
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
      print('❌ VideoService: Error checking video duration: $e');
      return false;
    }
  }

  /// **Compress video**
  Future<File?> compressVideo(File videoFile) async {
    try {
      print('🔄 VideoService: Compressing video...');

      final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
        videoFile.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
      );

      if (mediaInfo?.file != null) {
        print('✅ VideoService: Video compressed successfully');
        return mediaInfo!.file;
      } else {
        print('❌ VideoService: Video compression failed');
        return null;
      }
    } catch (e) {
      print('❌ VideoService: Error compressing video: $e');
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
      if (userData['token'] == null) {
        throw Exception('Authentication token not found');
      }

      return {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${userData['token']}',
      };
    } catch (e) {
      print('❌ VideoService: Error getting auth headers: $e');
      rethrow;
    }
  }

  /// **Optimized HTTP request with retry logic**
  Future<http.Response> _makeRequest(
    Future<http.Response> Function() requestFn, {
    int maxRetries = maxRetries,
    Duration retryDelay = const Duration(seconds: retryDelay),
    Duration timeout = const Duration(seconds: 15),
  }) async {
    int attempts = 0;
    while (attempts < maxRetries) {
      try {
        final response = await requestFn().timeout(timeout);
        if (response.statusCode == 200) return response;
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

  // **AD INTEGRATION METHODS - From original VideoService**

  /// **Get videos with integrated ads**
  Future<Map<String, dynamic>> getVideosWithAds({
    int page = 1,
    int limit = 10,
    int adInsertionFrequency = 3,
  }) async {
    try {
      print('🔍 VideoService: Fetching videos with ads...');

      final videosResult = await getVideos(page: page, limit: limit);
      final videos =
          (videosResult['videos'] as List<dynamic>).cast<VideoModel>();

      List<AdModel> ads = const [];
      try {
        ads = await _adService.getActiveAds();
      } catch (adError) {
        print(
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
        print(
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
      print('❌ VideoService: Error fetching videos with ads: $e');
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

    print('🔍 VideoService: Integrated $adIndex ads into feed');
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
      print('🚀 VideoService: Starting video upload...');
      print('📁 File: ${videoFile.path}');
      print('📝 Title: $title');
      print('🏷️ Category: $category');

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

      print('📤 VideoService: Sending upload request...');

      // Send request
      final response = await request.send().timeout(
            const Duration(minutes: 10),
          );

      final responseBody = await response.stream.bytesToString();
      final data = json.decode(responseBody);

      if (response.statusCode == 201) {
        print('✅ VideoService: Upload successful');
        return data;
      } else {
        print('❌ VideoService: Upload failed: ${response.statusCode}');
        throw Exception(data['error'] ?? 'Upload failed');
      }
    } catch (e) {
      print('❌ VideoService: Upload error: $e');
      rethrow;
    }
  }

  // **DISPOSE METHOD**
  void dispose() {
    _videoIndexChangeListeners.clear();
    _videoScreenStateListeners.clear();
    print('🗑️ VideoService: Disposed all listeners');
  }
}
