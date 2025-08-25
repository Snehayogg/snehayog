import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/material.dart';
import 'package:http_parser/http_parser.dart';
import 'package:snehayog/config/app_config.dart';
import 'package:snehayog/model/ad_model.dart';
import 'package:snehayog/services/ad_service.dart';

/// Optimized VideoService for better performance and smaller app size
class VideoService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();
  final AuthService _authService = AuthService();
  final AdService _adService = AdService();

  // **NEW: Video tracking and navigation state management**
  int _currentVisibleVideoIndex = 0;
  bool _isVideoScreenActive = true;
  bool _isAppInForeground = true;
  final List<Function(int)> _videoIndexChangeListeners = [];
  final List<Function(bool)> _videoScreenStateListeners = [];

  static String get baseUrl => NetworkHelper.getBaseUrl();
  // Optimized constants
  static const int maxRetries = 2; // Reduced from 3
  static const int retryDelay = 1; // Reduced from 2
  static const int maxShortVideoDuration = 120;

  // **NEW: Getters for video tracking**
  int get currentVisibleVideoIndex => _currentVisibleVideoIndex;
  bool get isVideoScreenActive => _isVideoScreenActive;
  bool get isAppInForeground => _isAppInForeground;
  bool get shouldPlayVideos => _isVideoScreenActive && _isAppInForeground;

  // **NEW: Video tracking methods**
  /// Update the currently visible video index
  void updateCurrentVideoIndex(int newIndex) {
    if (_currentVisibleVideoIndex != newIndex) {
      final oldIndex = _currentVisibleVideoIndex;
      _currentVisibleVideoIndex = newIndex;
      print('🎬 VideoService: Video index changed from $oldIndex to $newIndex');

      // Notify listeners about video index change
      for (final listener in _videoIndexChangeListeners) {
        try {
          listener(newIndex);
        } catch (e) {
          print('❌ VideoService: Error in video index change listener: $e');
        }
      }
    }
  }

  /// Update video screen active state (called when switching tabs)
  void updateVideoScreenState(bool isActive) {
    if (_isVideoScreenActive != isActive) {
      _isVideoScreenActive = isActive;
      print(
          '🔄 VideoService: Video screen state changed to ${isActive ? "ACTIVE" : "INACTIVE"}');

      // Notify listeners about screen state change
      for (final listener in _videoScreenStateListeners) {
        try {
          listener(isActive);
        } catch (e) {
          print('❌ VideoService: Error in video screen state listener: $e');
        }
      }
    }
  }

  /// Update app foreground state
  void updateAppForegroundState(bool inForeground) {
    if (_isAppInForeground != inForeground) {
      _isAppInForeground = inForeground;
      print(
          '📱 VideoService: App foreground state changed to ${inForeground ? "FOREGROUND" : "BACKGROUND"}');
    }
  }

  /// Add listener for video index changes
  void addVideoIndexChangeListener(Function(int) listener) {
    if (!_videoIndexChangeListeners.contains(listener)) {
      _videoIndexChangeListeners.add(listener);
    }
  }

  /// Remove listener for video index changes
  void removeVideoIndexChangeListener(Function(int) listener) {
    _videoIndexChangeListeners.remove(listener);
  }

  /// Add listener for video screen state changes
  void addVideoScreenStateListener(Function(bool) listener) {
    if (!_videoScreenStateListeners.contains(listener)) {
      _videoScreenStateListeners.add(listener);
    }
  }

  /// Remove listener for video screen state changes
  void removeVideoScreenStateListener(Function(bool) listener) {
    _videoScreenStateListeners.remove(listener);
  }

  /// Get current video tracking info
  Map<String, dynamic> getVideoTrackingInfo() {
    return {
      'currentVisibleVideoIndex': _currentVisibleVideoIndex,
      'isVideoScreenActive': _isVideoScreenActive,
      'isAppInForeground': _isAppInForeground,
      'shouldPlayVideos': shouldPlayVideos,
      'timestamp': DateTime.now().toIso8601String(),
    };
  }

  /// Clear all listeners (call in dispose)
  void dispose() {
    _videoIndexChangeListeners.clear();
    _videoScreenStateListeners.clear();
    print('🗑️ VideoService: Disposed all listeners');
  }

  // Simplified server health check
  Future<bool> checkServerHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health')) // Use correct health endpoint
          .timeout(const Duration(seconds: 5)); // Reduced timeout
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Test method to check if videos have link field
  Future<void> testVideoLinkField() async {
    try {
      print('🔗 VideoService: Testing video link field...');
      final response =
          await http.get(Uri.parse('$baseUrl/api/videos?page=1&limit=5'));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final videos = data['videos'] as List;

        print('🔗 VideoService: Found ${videos.length} videos');

        for (int i = 0; i < videos.length; i++) {
          final video = videos[i];
          print('🔗 VideoService: Video $i:');
          print('🔗 VideoService:   - ID: ${video['_id']}');
          print('🔗 VideoService:   - Title: ${video['videoName']}');
          print(
              '🔗 VideoService:   - Has link field: ${video.containsKey('link')}');
          if (video.containsKey('link')) {
            print('🔗 VideoService:   - Link value: "${video['link']}"');
          }
          print('🔗 VideoService:   - All fields: ${video.keys.toList()}');
        }
      } else {
        print(
            '🔗 VideoService: Failed to fetch videos: ${response.statusCode}');
      }
    } catch (e) {
      print('🔗 VideoService: Error testing video link field: $e');
    }
  }

  /// Test method to check link field for a specific video
  Future<void> testSpecificVideoLink(String videoId) async {
    try {
      print('🔗 VideoService: Testing link field for video: $videoId');
      final response =
          await http.get(Uri.parse('$baseUrl/api/videos/$videoId'));

      if (response.statusCode == 200) {
        final video = json.decode(response.body);
        print('🔗 VideoService: Video data:');
        print('🔗 VideoService:   - ID: ${video['_id']}');
        print('🔗 VideoService:   - Title: ${video['videoName']}');
        print(
            '🔗 VideoService:   - Has link field: ${video.containsKey('link')}');
        if (video.containsKey('link')) {
          print('🔗 VideoService:   - Link value: "${video['link']}"');
          print('🔗 VideoService:   - Link type: ${video['link'].runtimeType}');
          print(
              '🔗 VideoService:   - Link is empty: ${video['link'].toString().isEmpty}');
        }
        print('🔗 VideoService:   - All fields: ${video.keys.toList()}');
      } else {
        print('🔗 VideoService: Failed to fetch video: ${response.statusCode}');
      }
    } catch (e) {
      print('🔗 VideoService: Error testing specific video link: $e');
    }
  }

  /// Test network configuration and connectivity
  Future<bool> testNetworkConfiguration() async {
    try {
      print('🌐 VideoService: Testing network configuration...');
      print('🌐 VideoService: Base URL: $baseUrl');

      // Test basic connectivity
      final response = await http
          .get(Uri.parse('$baseUrl/api/health'))
          .timeout(const Duration(seconds: 5));

      print('🌐 VideoService: Health check response: ${response.statusCode}');

      if (response.statusCode == 200) {
        print('✅ VideoService: Network configuration is working');
        return true;
      } else {
        print(
            '❌ VideoService: Network configuration returned status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ VideoService: Network configuration test failed: $e');
      return false;
    }
  }

  // Optimized HTTP request with retry logic
  Future<http.Response> _makeRequest(
    Future<http.Response> Function() requestFn, {
    int maxRetries = 2,
    Duration retryDelay = const Duration(seconds: 1),
    Duration timeout = const Duration(seconds: 15), // Reduced timeout
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

  /// Fetches a list of videos from the server
  /// Returns a map containing the list of VideoModel objects and pagination info
  Future<Map<String, dynamic>> getVideos({int page = 1, int limit = 10}) async {
    try {
      final url = '$baseUrl/api/videos?page=$page&limit=$limit';

      final response = await _makeRequest(
        () => http.get(Uri.parse(url)),
        timeout: const Duration(seconds: 15), // Reduced timeout for better UX
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);

        final List<dynamic> videoList = responseData['videos'];

        final videos = videoList.map((json) {
          // Debug: Print each video's JSON data
          print('🔗 VideoService: Processing video JSON: $json');
          print(
              '🔗 VideoService: json.containsKey("link") = ${json.containsKey('link')}');
          if (json.containsKey('link')) {
            print('🔗 VideoService: json["link"] = ${json['link']}');
          }

          // Debug: Check uploader data
          if (json.containsKey('uploader')) {
            print('🔗 VideoService: uploader data: ${json['uploader']}');
            if (json['uploader'] is Map<String, dynamic>) {
              print(
                  '🔗 VideoService: uploader.name: ${json['uploader']['name']}');
              print(
                  '🔗 VideoService: uploader.profilePic: ${json['uploader']['profilePic']}');
              print(
                  '🔗 VideoService: uploader.profilePic type: ${json['uploader']['profilePic'].runtimeType}');
            }
          }

          // Ensure URLs are complete if they're relative paths
          if (json['videoUrl'] != null &&
              !json['videoUrl'].toString().startsWith('http')) {
            json['videoUrl'] = '$baseUrl${json['videoUrl']}';
          }

          // Check if HLS URLs are available and use them for better streaming
          if (json['hlsPlaylistUrl'] != null &&
              json['hlsPlaylistUrl'].toString().isNotEmpty) {
            // Use HLS playlist URL for better streaming
            if (!json['hlsPlaylistUrl'].toString().startsWith('http')) {
              json['videoUrl'] = '$baseUrl${json['hlsPlaylistUrl']}';
            } else {
              json['videoUrl'] = json['hlsPlaylistUrl'];
            }
            print('🔗 VideoService: Using HLS URL: ${json['videoUrl']}');
          } else if (json['hlsMasterPlaylistUrl'] != null &&
              json['hlsMasterPlaylistUrl'].toString().isNotEmpty) {
            // Use HLS master playlist URL for adaptive streaming
            if (!json['hlsMasterPlaylistUrl'].toString().startsWith('http')) {
              json['videoUrl'] = '$baseUrl${json['hlsMasterPlaylistUrl']}';
            } else {
              json['videoUrl'] = json['hlsMasterPlaylistUrl'];
            }
            print('🔗 VideoService: Using HLS Master URL: ${json['videoUrl']}');
          } else {
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

  /// Fetches a specific video by its ID
  /// Parameters:
  /// - id: The unique identifier of the video
  /// Returns a VideoModel object
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

  /// Toggle like for a video
  /// Parameters:
  /// - videoId: The ID of the video to like/unlike
  /// - userId: The ID of the user performing the action
  /// Returns the updated VideoModel
  Future<VideoModel> toggleLike(String videoId, String userId) async {
    try {
      print(
          '🔍 VideoService: Starting toggleLike for video: $videoId, user: $userId');

      // Check authentication first
      final userData = await _authService.getUserData();

      if (userData == null) {
        print('❌ VideoService: User not authenticated');
        throw Exception('Please sign in to like videos');
      }

      print('🔍 VideoService: User authenticated, userData: $userData');
      print(
          '🔍 VideoService: Making API request to: $baseUrl/api/videos/$videoId/like');
      print(
          '🔍 VideoService: Request body: ${json.encode({'userId': userId})}');
      print('🔍 VideoService: Base URL: $baseUrl');

      final res = await http
          .post(
            Uri.parse('$baseUrl/api/videos/$videoId/like'),
            headers: {
              'Content-Type': 'application/json',
            },
            body: json.encode({'userId': userId}),
          )
          .timeout(const Duration(seconds: 15));

      print('🔍 VideoService: API response status: ${res.statusCode}');
      print('🔍 VideoService: API response body: ${res.body}');
      print('🔍 VideoService: API response headers: ${res.headers}');

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        print('✅ VideoService: Like toggle successful, response: $data');

        // Create VideoModel from the response
        final videoModel = VideoModel.fromJson(data);
        print('✅ VideoService: VideoModel created successfully');

        return videoModel;
      } else if (res.statusCode == 400) {
        print('❌ VideoService: Bad request - status: ${res.statusCode}');
        final error = json.decode(res.body);
        throw Exception(error['error'] ?? 'Bad request');
      } else if (res.statusCode == 401) {
        print('❌ VideoService: Unauthorized - user needs to sign in again');
        throw Exception('Please sign in again to like videos');
      } else if (res.statusCode == 404) {
        print('❌ VideoService: Video or user not found');
        final error = json.decode(res.body);
        throw Exception(error['error'] ?? 'Video not found');
      } else {
        print('❌ VideoService: Server error - status: ${res.statusCode}');
        final error = json.decode(res.body);
        throw Exception(error['error'] ?? 'Failed to like video');
      }
    } catch (e) {
      print('❌ VideoService: Error in toggleLike: $e');
      print('❌ VideoService: Error type: ${e.runtimeType}');
      print('❌ VideoService: Error details: ${e.toString()}');

      if (e is TimeoutException) {
        throw Exception('Request timed out. Please try again.');
      } else if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  /// Adds a comment to a video
  /// Parameters:
  /// - videoId: The ID of the video to comment on
  /// - text: The comment text
  /// - userId: The ID of the user making the comment
  /// Returns a list of all comments for the video
  Future<List<Comment>> addComment(
      String videoId, String text, String userId) async {
    try {
      // Check authentication first
      final userData = await _authService.getUserData();

      if (userData == null) {
        throw Exception('Please sign in to add comments');
      }

      final res = await http
          .post(
            Uri.parse('$baseUrl/api/videos/$videoId/comments'),
            headers: {
              'Content-Type':
                  'application/json', // Ensure backend can read JSON
            },
            body: json.encode({
              'userId': userId,
              'text': text,
            }),
          )
          .timeout(const Duration(seconds: 10));
      print('Response body: \\${res.body}');

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
      } else if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  /// Shares a video using the platform's share dialog
  /// Parameters:
  /// - videoId: The ID of the video to share
  /// - videoUrl: The URL of the video
  /// - description: The description of the video
  /// Returns the updated VideoModel with incremented share count
  Future<VideoModel> shareVideo(
      String videoId, String videoUrl, String description) async {
    try {
      final headers = await _getAuthHeaders();

      // Share the video using platform share dialog
      await Share.share(
        'Check out this video on Snehayog!\n\n$description\n\n$videoUrl',
        subject: 'Snehayog Video',
      );

      // Update share count on server
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

  /// Checks if a video is considered a long video (more than 2 minutes)
  /// Parameters:
  /// - videoPath: The local path to the video file
  /// Returns true if the video is longer than maxShortVideoDuration
  Future<bool> isLongVideo(String videoPath) async {
    try {
      final controller = VideoPlayerController.file(File(videoPath));
      await controller.initialize();
      final duration = controller.value.duration;
      await controller.dispose();
      return duration.inSeconds > maxShortVideoDuration;
    } catch (e) {
      print('Error checking video duration: $e');
      return false;
    }
  }

  /// Uploads a video to the server
  /// Parameters:
  /// - videoFile: The video file to upload
  /// - title: The title of the video
  /// - onProgress: Optional callback for upload progress
  /// Returns a map containing the uploaded video's data
  Future<Map<String, dynamic>> uploadVideo(File videoFile, String title,
      [String? description, String? link, Function(double)? onProgress]) async {
    try {
      print('Using server at: $baseUrl');

      // Check server health before upload
      final isHealthy = await checkServerHealth();
      if (!isHealthy) {
        throw Exception(
            'Server is not responding. Please check your connection and try again.');
      }

      final isLong = await isLongVideo(videoFile.path);

      // Get authentication data directly from AuthService
      final userData = await _authService.getUserData();

      if (userData == null) {
        throw Exception(
            'User not authenticated. Please sign in to upload videos.');
      }

      print('User data for upload: ${userData.toString()}');

      // Check file size before upload
      final fileSize = await videoFile.length();
      const maxSize = 100 * 1024 * 1024; // 100MB
      if (fileSize > maxSize) {
        throw Exception('File too large. Maximum size is 100MB');
      }

      // Create a multipart request
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/videos/upload'),
      );

      // Add authentication headers
      final headers = await _getAuthHeaders();
      request.headers.addAll(headers);

      // Add the video file
      request.files.add(
        await http.MultipartFile.fromPath(
          'video',
          videoFile.path,
          contentType: MediaType('video', 'mp4'),
        ),
      );

      // Add other fields (googleId is no longer needed - backend gets it from JWT token)
      request.fields['videoName'] = title;
      request.fields['description'] = description ?? ''; // Optional description
      request.fields['videoType'] = isLong ? 'yog' : 'sneha';
      if (link != null && link.isNotEmpty) {
        request.fields['link'] = link;
      }

      // Send the request with timeout
      final streamedResponse = await request.send().timeout(
        const Duration(
            minutes: 10), // Increased timeout for large video uploads
        onTimeout: () {
          throw TimeoutException(
              'Upload timed out. Please check your internet connection and try again.');
        },
      );

      // Get the response
      final responseBody = await streamedResponse.stream.bytesToString();
      final responseData = json.decode(responseBody);

      if (streamedResponse.statusCode == 201) {
        final videoData = responseData['video'];

        // Debug: Print the full video data response
        print('🔗 VideoService: Full video data response: $videoData');
        print(
            '🔗 VideoService: videoData.containsKey("link") = ${videoData.containsKey('link')}');
        if (videoData.containsKey('link')) {
          print('🔗 VideoService: videoData["link"] = ${videoData['link']}');
        }

        // Return the video data in the expected format
        // Cloudinary URLs are already full URLs, no need to prepend baseUrl
        return {
          'id': videoData['_id'],
          'title': videoData['videoName'],
          'videoUrl':
              videoData['videoUrl'], // Cloudinary URL is already complete
          'thumbnail':
              videoData['thumbnailUrl'], // Cloudinary URL is already complete
          'originalVideoUrl':
              videoData['originalVideoUrl'], // Add original video URL
          'duration': '0:00',
          'views': 0,
          'uploader': userData['name'],
          'uploadTime': 'Just now',
          'isLongVideo': isLong,
          'link': videoData['link'], // Include the link field
        };
      } else {
        // Handle specific error types
        if (responseData['error'] != null) {
          final errorMessage = responseData['error'].toString();

          if (errorMessage.contains('File too large')) {
            throw Exception('File too large. Maximum size is 100MB');
          } else if (errorMessage.contains('Invalid file type')) {
            throw Exception(
                'Invalid file type. Please upload a video file (MP4, AVI, MOV, WMV, FLV, WEBM)');
          } else if (errorMessage.contains('User not found')) {
            throw Exception('User not found. Please sign in again.');
          } else if (errorMessage.contains('Cloudinary upload failed')) {
            throw Exception(
                'Video upload service is temporarily unavailable. Please try again later.');
          } else if (errorMessage.contains('timeout')) {
            throw Exception(
                'Upload timed out. Please check your internet connection and try again.');
          } else {
            throw Exception(errorMessage);
          }
        }

        throw Exception('Failed to upload video. Please try again.');
      }
    } catch (e) {
      print('Error uploading video: $e');
      if (e is TimeoutException) {
        throw Exception(
            'Upload timed out. Please check your internet connection and try again.');
      } else if (e is SocketException) {
        throw Exception(
            'Could not connect to server. Please check if the server is running.');
      } else if (e is FormatException) {
        throw Exception('Invalid response from server. Please try again.');
      }
      rethrow;
    }
  }

  /// Gets all videos uploaded by a specific user
  /// Parameters:
  /// - userId: The ID of the user whose videos to fetch
  /// Returns a list of VideoModel objects
  Future<List<VideoModel>> getUserVideos(String userId) async {
    try {
      final url = '$baseUrl/api/videos/user/$userId';
      print('🔍 VideoService: Fetching user videos from: $url');
      print('🔍 VideoService: User ID type: ${userId.runtimeType}');
      print('🔍 VideoService: User ID value: $userId');
      print('🔍 VideoService: User ID length: ${userId.length}');

      final response = await _makeRequest(
        () => http.get(Uri.parse(url)),
        timeout: const Duration(seconds: 30),
      );

      print('🔍 VideoService: Response status code: ${response.statusCode}');
      print('🔍 VideoService: Response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final List<dynamic> videoList = json.decode(response.body);
          print(
              '✅ VideoService: Successfully decoded ${videoList.length} user videos');

          // Process each video to ensure URLs are complete
          final videos = videoList.map((json) {
            print('🔍 VideoService: Processing video: ${json['videoName']}');
            print('🔍 VideoService: Original videoUrl: ${json['videoUrl']}');
            print(
                '🔍 VideoService: Original thumbnailUrl: ${json['thumbnailUrl']}');

            // Ensure videoUrl has the base URL if it's a relative path
            if (json['videoUrl'] != null &&
                !json['videoUrl'].toString().startsWith('http')) {
              json['videoUrl'] = '$baseUrl${json['videoUrl']}';
            }

            // Ensure originalVideoUrl has the base URL if it's a relative path
            if (json['originalVideoUrl'] != null &&
                !json['originalVideoUrl'].toString().startsWith('http')) {
              json['originalVideoUrl'] = '$baseUrl${json['originalVideoUrl']}';
            }

            // Ensure thumbnailUrl has the base URL if it's a relative path
            if (json['thumbnailUrl'] != null &&
                !json['thumbnailUrl'].toString().startsWith('http')) {
              json['thumbnailUrl'] = '$baseUrl${json['thumbnailUrl']}';
            }

            print('🔍 VideoService: Final videoUrl: ${json['videoUrl']}');
            print(
                '🔍 VideoService: Final thumbnailUrl: ${json['thumbnailUrl']}');

            return VideoModel.fromJson(json);
          }).toList();

          return videos;
        } catch (e) {
          print('❌ VideoService: Error parsing JSON response: $e');
          throw Exception('Invalid response format from server');
        }
      } else if (response.statusCode == 404) {
        print('⚠️ VideoService: No videos found for user');
        return [];
      } else {
        print('❌ VideoService: Server error: ${response.statusCode}');
        print('❌ VideoService: Error response: ${response.body}');
        throw Exception('Failed to fetch user videos: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ VideoService: Error fetching user videos: $e');
      if (e is TimeoutException) {
        throw Exception(
            'Request timed out. Please check your internet connection and try again.');
      }
      rethrow;
    }
  }

  /// Fetches videos with integrated ads for the video feed
  /// Parameters:
  /// - page: Page number for pagination
  /// - limit: Number of videos per page
  /// - adInsertionFrequency: How often to insert ads (every Nth video)
  /// Returns a map with videos, ads, and pagination info
  Future<Map<String, dynamic>> getVideosWithAds({
    int page = 1,
    int limit = 10,
    int adInsertionFrequency = 3, // Insert ad every 3rd video
  }) async {
    try {
      print('🔍 VideoService: Fetching videos with ads...');
      print(
          '🔍 VideoService: Page: $page, Limit: $limit, Ad frequency: $adInsertionFrequency');

      // Always fetch videos first
      final videosResult = await getVideos(page: page, limit: limit);
      final videos = videosResult['videos'] as List<VideoModel>;

      // Try to fetch ads, but don't fail the whole feed if ads are unavailable
      List<AdModel> ads = const [];
      try {
        ads = await _adService.getActiveAds();
      } catch (adError) {
        print(
            '⚠️ VideoService: Failed to fetch ads, continuing without ads: $adError');
      }

      print(
          '🔍 VideoService: Fetched ${videos.length} videos and ${ads.length} ads');

      // Integrate ads into video feed safely
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

  /// Integrates ads into the video feed at specified intervals
  List<dynamic> _integrateAdsIntoFeed(
      List<VideoModel> videos, List<AdModel> ads, int frequency) {
    if (ads.isEmpty) return videos;

    final integratedFeed = <dynamic>[];
    int adIndex = 0;

    for (int i = 0; i < videos.length; i++) {
      // Add video
      integratedFeed.add(videos[i]);

      // Insert ad after every Nth video (but not after the last video)
      if ((i + 1) % frequency == 0 && i < videos.length - 1) {
        if (adIndex < ads.length) {
          // Convert AdModel to VideoModel-like structure for seamless integration
          final adAsVideo = _convertAdToVideoFormat(ads[adIndex]);
          integratedFeed.add(adAsVideo);
          adIndex++;
        }
      }
    }

    print('🔍 VideoService: Integrated $adIndex ads into feed');
    return integratedFeed;
  }

  /// Converts AdModel to a VideoModel-like structure for seamless feed integration
  Map<String, dynamic> _convertAdToVideoFormat(AdModel ad) {
    return {
      'id': 'ad_${ad.id}', // Unique ID for ads
      'videoName': ad.title,
      'videoUrl':
          ad.videoUrl ?? ad.imageUrl ?? '', // Use video or image as video
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
      'videoType': 'ad', // Mark as ad
      'comments': <Map<String, dynamic>>[],
      'link': ad.link,
      'isAd': true, // Flag to identify ads
      'adData': ad.toJson(), // Store original ad data
      'adType': ad.adType,
      'targetAudience': ad.targetAudience,
      'targetKeywords': ad.targetKeywords,
    };
  }

  /// Gets authentication headers for API requests
  /// Returns a map containing Content-Type and Authorization headers
  /// Throws an exception if user is not authenticated
  Future<Map<String, String>> _getAuthHeaders() async {
    final userData = await _authService.getUserData();

    if (userData == null) {
      throw Exception('User not authenticated');
    }

    if (userData['token'] == null) {
      throw Exception('Authentication token not found');
    }

    // Debug: Log token information
    print('🔍 VideoService: Token found in userData');
    print('🔍 VideoService: Token type: ${userData['token'].runtimeType}');
    print(
        '🔍 VideoService: Token length: ${userData['token'].toString().length}');
    print(
        '🔍 VideoService: Token preview: ${userData['token'].toString().substring(0, 20)}...');
    print('🔍 VideoService: User ID from userData: ${userData['id']}');
    print('🔍 VideoService: Google ID from userData: ${userData['googleId']}');

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${userData['token']}',
    };

    print('🔍 VideoService: Final headers: ${headers.keys.toList()}');
    print(
        '🔍 VideoService: Authorization header preview: ${headers['Authorization']?.substring(0, 30)}...');

    return headers;
  }

  /// Deletes a video from the server
  /// Parameters:
  /// - videoId: The ID of the video to delete
  /// Returns true if deletion was successful, false otherwise
  Future<bool> deleteVideo(String videoId) async {
    try {
      print('🗑️ VideoService: Attempting to delete video: $videoId');

      // Check authentication first
      final userData = await _authService.getUserData();

      if (userData == null) {
        throw Exception('Please sign in to delete videos');
      }

      // Get user ID (try multiple fields)
      final userId = userData['googleId'] ?? userData['id'] ?? userData['_id'];
      if (userId == null) {
        throw Exception('User ID not found');
      }

      // Get authentication headers
      final headers = await _getAuthHeaders();
      print('🗑️ VideoService: Using headers: ${headers.keys.toList()}');
      print('🗑️ VideoService: User ID: $userId');

      print(
          '🗑️ VideoService: Sending DELETE request to: $baseUrl/api/videos/$videoId');
      print('🗑️ VideoService: Request headers: $headers');
      print('🗑️ VideoService: Request body: {}');

      final res = await http
          .delete(
            Uri.parse('$baseUrl/api/videos/$videoId'),
            headers: headers,
            body: json.encode({
              // googleId is no longer needed - backend gets it from JWT token
            }),
          )
          .timeout(const Duration(seconds: 10));

      print('🗑️ VideoService: Delete response status: ${res.statusCode}');
      print('🗑️ VideoService: Delete response body: ${res.body}');

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
      } else if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  /// Deletes multiple videos from the server
  /// Parameters:
  /// - videoIds: List of video IDs to delete
  /// Returns true if all deletions were successful, false otherwise
  Future<bool> deleteVideos(List<String> videoIds) async {
    try {
      if (videoIds.isEmpty) {
        print('🗑️ VideoService: No videos to delete');
        return true;
      }

      print(
          '🗑️ VideoService: Attempting to delete ${videoIds.length} videos: $videoIds');

      // Check authentication first
      final userData = await _authService.getUserData();

      if (userData == null) {
        throw Exception('Please sign in to delete videos');
      }

      // Get user ID (try multiple fields)
      final userId = userData['googleId'] ?? userData['id'] ?? userData['_id'];
      if (userId == null) {
        throw Exception('User ID not found');
      }

      // Get authentication headers
      final headers = await _getAuthHeaders();
      print('🗑️ VideoService: Using headers: ${headers.keys.toList()}');
      print('🗑️ VideoService: User ID: $userId');

      // For bulk deletion, we'll use a POST request with the video IDs
      final res = await http
          .post(
            Uri.parse('$baseUrl/api/videos/bulk-delete'),
            headers: headers,
            body: json.encode({
              'videoIds': videoIds,
              // googleId is no longer needed - backend gets it from JWT token
              'deleteReason': 'user_requested',
              'timestamp': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 30));

      print('🗑️ VideoService: Bulk delete response status: ${res.statusCode}');
      print('🗑️ VideoService: Bulk delete response body: ${res.body}');

      if (res.statusCode == 200 || res.statusCode == 204) {
        print('✅ VideoService: All videos deleted successfully');
        return true;
      } else if (res.statusCode == 401) {
        throw Exception('Please sign in again to delete videos');
      } else if (res.statusCode == 403) {
        throw Exception('You do not have permission to delete these videos');
      } else if (res.statusCode == 404) {
        throw Exception('One or more videos were not found');
      } else if (res.statusCode == 400) {
        final error = json.decode(res.body);
        throw Exception(error['error'] ?? 'Invalid request for bulk deletion');
      } else {
        final error = json.decode(res.body);
        throw Exception(error['error'] ?? 'Failed to delete videos');
      }
    } catch (e) {
      print('❌ VideoService: Error in bulk video deletion: $e');
      if (e is TimeoutException) {
        throw Exception('Request timed out. Please try again.');
      } else if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  /// Deletes a single video with enhanced error handling and logging
  /// Parameters:
  /// - videoId: The ID of the video to delete
  /// - deleteReason: Optional reason for deletion (for analytics)
  /// Returns true if deletion was successful, false otherwise
  Future<bool> deleteVideoWithReason(String videoId,
      {String? deleteReason}) async {
    try {
      print('🗑️ VideoService: Attempting to delete video: $videoId');
      if (deleteReason != null) {
        print('🗑️ VideoService: Delete reason: $deleteReason');
      }

      // Check authentication first
      final userData = await _authService.getUserData();

      if (userData == null) {
        throw Exception('Please sign in to delete videos');
      }

      // Get authentication headers
      final headers = await _getAuthHeaders();
      print('🗑️ VideoService: Using headers: ${headers.keys.toList()}');

      // Prepare request body with deletion metadata
      final requestBody = {
        'deleteReason': deleteReason ?? 'user_requested',
        // deletedBy is no longer needed - backend gets it from JWT token
        'deletedAt': DateTime.now().toIso8601String(),
        'userAgent': 'Snehayog-Mobile-App',
      };

      final res = await http
          .delete(
            Uri.parse('$baseUrl/api/videos/$videoId'),
            headers: headers,
            body: json.encode(requestBody),
          )
          .timeout(const Duration(seconds: 15));

      print('🗑️ VideoService: Delete response status: ${res.statusCode}');
      print('🗑️ VideoService: Delete response body: ${res.body}');

      if (res.statusCode == 200 || res.statusCode == 204) {
        print('✅ VideoService: Video deleted successfully');

        // Log successful deletion for analytics
        _logVideoDeletion(
            videoId, userData['id'] ?? userData['googleId'], deleteReason);

        return true;
      } else if (res.statusCode == 401) {
        throw Exception('Please sign in again to delete videos');
      } else if (res.statusCode == 403) {
        throw Exception('You do not have permission to delete this video');
      } else if (res.statusCode == 404) {
        throw Exception('Video not found');
      } else if (res.statusCode == 409) {
        throw Exception('Video cannot be deleted at this time');
      } else {
        final error = json.decode(res.body);
        throw Exception(error['error'] ?? 'Failed to delete video');
      }
    } catch (e) {
      print('❌ VideoService: Error deleting video: $e');
      if (e is TimeoutException) {
        throw Exception('Request timed out. Please try again.');
      } else if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }

  /// Logs video deletion for analytics and monitoring
  void _logVideoDeletion(String videoId, String userId, String? deleteReason) {
    try {
      print('📊 VideoService: Logging video deletion for analytics');
      print('   Video ID: $videoId');
      print('   User ID: $userId');
      print('   Delete Reason: ${deleteReason ?? 'user_requested'}');
      print('   Timestamp: ${DateTime.now().toIso8601String()}');

      // In production, you would send this data to your analytics service
      // await _analyticsService.logVideoDeletion(videoId, userId, deleteReason);
    } catch (e) {
      print('❌ VideoService: Error logging video deletion: $e');
    }
  }
}
