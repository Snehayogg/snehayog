import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:video_player/video_player.dart';
import 'package:flutter/material.dart';
import 'package:http_parser/http_parser.dart';
import 'package:video_compress/video_compress.dart';
import 'package:share_plus/share_plus.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/model/ad_model.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/services/ad_service.dart';
import 'package:snehayog/config/app_config.dart';

/// **OPTIMIZED VideoService - Single source of truth for all video operations**
/// Merged from VideoService, BaseVideoService, and InstagramVideoService
/// Eliminates code duplication and provides consistent API
class VideoService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  final AuthService _authService = AuthService();
  final AdService _adService = AdService();

  // **VIDEO TRACKING: State management for video playback**
  int _currentVisibleVideoIndex = 0;
  bool _isVideoScreenActive = true;
  bool _isAppInForeground = true;
  final List<Function(int)> _videoIndexChangeListeners = [];
  final List<Function(bool)> _videoScreenStateListeners = [];

  // **CONSTANTS: Optimized values for better performance**
  static String get baseUrl => NetworkHelper.getBaseUrl();
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
          '🔄 VideoService: Video screen state changed to ${isActive ? "ACTIVE" : "INACTIVE"}');

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
          '📱 VideoService: App foreground state changed to ${inForeground ? "FOREGROUND" : "BACKGROUND"}');
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
  Future<Map<String, dynamic>> getVideos(
      {int page = 1, int limit = 10, String? videoType}) async {
    try {
      String url = '$baseUrl/api/videos?page=$page&limit=$limit';
      if (videoType != null && (videoType == 'yog' || videoType == 'sneha')) {
        url += '&videoType=$videoType';
        print('🔍 VideoService: Filtering by videoType: $videoType');
      }
      final response = await _makeRequest(
        () => http.get(Uri.parse(url)),
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
            if (!json['hlsPlaylistUrl'].toString().startsWith('http')) {
              json['videoUrl'] = '$baseUrl${json['hlsPlaylistUrl']}';
            } else {
              json['videoUrl'] = json['hlsPlaylistUrl'];
            }
            print('🔗 VideoService: Using HLS URL: ${json['videoUrl']}');
          } else if (json['hlsMasterPlaylistUrl'] != null &&
              json['hlsMasterPlaylistUrl'].toString().isNotEmpty) {
            if (!json['hlsMasterPlaylistUrl'].toString().startsWith('http')) {
              json['videoUrl'] = '$baseUrl${json['hlsMasterPlaylistUrl']}';
            } else {
              json['videoUrl'] = json['hlsMasterPlaylistUrl'];
            }
            print('🔗 VideoService: Using HLS Master URL: ${json['videoUrl']}');
          } else {
            // **Fallback**: Ensure relative URLs are complete
            if (json['videoUrl'] != null &&
                !json['videoUrl'].toString().startsWith('http')) {
              json['videoUrl'] = '$baseUrl${json['videoUrl']}';
            }
            print(
                '🔗 VideoService: Using original video URL: ${json['videoUrl']}');
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
      final res = await http.get(Uri.parse('$baseUrl/api/videos/$id'));
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

      final res = await http
          .post(
            Uri.parse('$baseUrl/api/videos/$videoId/like'),
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
      String videoId, String text, String userId) async {
    try {
      final headers = await _getAuthHeaders();
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/videos/$videoId/comments'),
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

  /// **Get user videos**
  Future<List<VideoModel>> getUserVideos(String userId) async {
    try {
      final url = '$baseUrl/api/videos/user/$userId';
      final headers = await _getAuthHeaders();

      final response = await http
          .get(Uri.parse(url), headers: headers)
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> videoList = json.decode(response.body);

        final videos = videoList.map((json) {
          // **Ensure URLs are complete**
          if (json['videoUrl'] != null &&
              !json['videoUrl'].toString().startsWith('http')) {
            json['videoUrl'] = '$baseUrl${json['videoUrl']}';
          }
          if (json['originalVideoUrl'] != null &&
              !json['originalVideoUrl'].toString().startsWith('http')) {
            json['originalVideoUrl'] = '$baseUrl${json['originalVideoUrl']}';
          }
          if (json['thumbnailUrl'] != null &&
              !json['thumbnailUrl'].toString().startsWith('http')) {
            json['thumbnailUrl'] = '$baseUrl${json['thumbnailUrl']}';
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
            'Request timed out. Please check your internet connection and try again.');
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
            'Server is not responding. Please check your connection and try again.');
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
            'User not authenticated. Please sign in to upload videos.');
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
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/videos/upload'),
      );

      final headers = await _getAuthHeaders();
      request.headers.addAll(headers);

      // **Add video file**
      request.files.add(
        await http.MultipartFile.fromPath(
          'video',
          finalVideoFile.path,
          contentType: MediaType('video', 'mp4'),
        ),
      );

      // **Add fields**
      request.fields['videoName'] = title;
      request.fields['description'] = description ?? '';
      request.fields['videoType'] = isLong ? 'sneha' : 'yog';
      if (link != null && link.isNotEmpty) {
        request.fields['link'] = link;
      }

      // **Send request**
      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 10),
        onTimeout: () {
          throw TimeoutException(
              'Upload timed out. Please check your internet connection and try again.');
        },
      );

      final responseBody = await streamedResponse.stream.bytesToString();
      final responseData = json.decode(responseBody);

      print(
          '📡 VideoService: Upload response status: ${streamedResponse.statusCode}');
      print('📄 VideoService: Upload response body: $responseBody');

      if (streamedResponse.statusCode == 201) {
        final videoData = responseData['video'];
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
        print(
            '❌ VideoService: Upload failed with status ${streamedResponse.statusCode}');
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
            'Upload timed out. Please check your internet connection and try again.');
      } else if (e is SocketException) {
        throw Exception(
            'Could not connect to server. Please check if the server is running.');
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
      final res = await http
          .delete(
            Uri.parse('$baseUrl/api/videos/$videoId'),
            headers: headers,
          )
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

  /// **Share video**
  Future<VideoModel> shareVideo(
      String videoId, String videoUrl, String description) async {
    try {
      // Get the proper URL for sharing
      String shareUrl = videoUrl;

      // If it's a custom scheme URL, convert it to web URL
      if (videoUrl.startsWith('snehayog://')) {
        shareUrl = 'https://snehayog.app/video/$videoId';
      }

      // If it's an HLS URL, use it directly
      if (videoUrl.contains('.m3u8')) {
        shareUrl = videoUrl;
      }

      // **Share using platform dialog**
      await Share.share(
        '🎬 Check out this video on Snehayog!\n\n📹 $description\n\n🔗 Watch on Snehayog: $shareUrl\n🌐 Web version: https://snehayog.app/video/$videoId\n\n#Snehayog #Video',
        subject: 'Snehayog Video',
      );

      // **Update share count on server**
      final headers = await _getAuthHeaders();
      final res = await http.post(
        Uri.parse('$baseUrl/api/videos/$videoId/share'),
        headers: headers,
      );

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return VideoModel.fromJson(data);
      } else {
        final error = json.decode(res.body);
        throw Exception(error['error'] ?? 'Failed to share video');
      }
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Network error: $e');
    }
  }

  // **UTILITY METHODS - Merged from BaseVideoService**

  /// **Check server health**
  Future<bool> checkServerHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/health'))
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
          integratedFeed =
              _integrateAdsIntoFeed(videos, ads, adInsertionFrequency);
        }
      } catch (integrationError) {
        print(
            '⚠️ VideoService: Failed to integrate ads, using videos only: $integrationError');
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
      List<VideoModel> videos, List<AdModel> ads, int frequency) {
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
        'id': ad.uploaderId ?? 'advertiser',
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

  // **DISPOSE METHOD**
  void dispose() {
    _videoIndexChangeListeners.clear();
    _videoScreenStateListeners.clear();
    print('🗑️ VideoService: Disposed all listeners');
  }
}
