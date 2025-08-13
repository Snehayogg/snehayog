import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/google_auth_service.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter/material.dart';
import 'package:snehayog/config/app_config.dart';
import 'package:http_parser/http_parser.dart';

/// Optimized VideoService for better performance and smaller app size
class VideoService {
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static String get baseUrl => NetworkHelper.getBaseUrl();

  // Optimized constants
  static const int maxRetries = 2; // Reduced from 3
  static const int retryDelay = 1; // Reduced from 2
  static const int maxShortVideoDuration = 120;

  // Simplified server health check
  Future<bool> checkServerHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/api/health'))
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

          // Ensure URLs are complete if they're relative paths
          if (json['videoUrl'] != null &&
              !json['videoUrl'].toString().startsWith('http')) {
            json['videoUrl'] = '$baseUrl${json['videoUrl']}';
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
      print('🔍 VideoService: Starting toggleLike for video: $videoId, user: $userId');
      
      // Check authentication first
      final googleAuthService = GoogleAuthService();
      final userData = await googleAuthService.getUserData();

      if (userData == null) {
        print('❌ VideoService: User not authenticated');
        throw Exception('Please sign in to like videos');
      }

      print('🔍 VideoService: User authenticated, making API request...');

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

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        print('✅ VideoService: Like toggle successful, response: $data');
        
        // Create VideoModel from the response
        final videoModel = VideoModel.fromJson(data);
        print('✅ VideoService: VideoModel created successfully');
        
        return videoModel;
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
      final googleAuthService = GoogleAuthService();
      final userData = await googleAuthService.getUserData();

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
  /// - description: The description of the video
  /// - onProgress: Optional callback for upload progress
  /// Returns a map containing the uploaded video's data
  Future<Map<String, dynamic>> uploadVideo(
      File videoFile, String title, String description,
      [String? link, Function(double)? onProgress]) async {
    try {
      print('Using server at: $baseUrl');

      // Check server health before upload
      final isHealthy = await checkServerHealth();
      if (!isHealthy) {
        throw Exception(
            'Server is not responding. Please check your connection and try again.');
      }

      final isLong = await isLongVideo(videoFile.path);

      // Get authentication data directly from GoogleAuthService
      final googleAuthService = GoogleAuthService();
      final userData = await googleAuthService.getUserData();

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

      // Add the video file
      request.files.add(
        await http.MultipartFile.fromPath(
          'video',
          videoFile.path,
          contentType: MediaType('video', 'mp4'),
        ),
      );

      // Add other fields
      request.fields['googleId'] = userData['id'];
      request.fields['videoName'] = title;
      request.fields['description'] = description;
      request.fields['videoType'] = isLong ? 'yog' : 'sneha';
      if (link != null && link.isNotEmpty) {
        request.fields['link'] = link;
      }

      // Send the request with timeout
      final streamedResponse = await request.send().timeout(
        const Duration(minutes: 5),
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
          'description': videoData['description'],
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
      print('Fetching user videos from: $url');

      final response = await _makeRequest(
        () => http.get(Uri.parse(url)),
        timeout: const Duration(seconds: 30),
      );

      print('Response status code: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        try {
          final List<dynamic> videoList = json.decode(response.body);
          print('Successfully decoded ${videoList.length} user videos');

          // Process each video to ensure URLs are complete
          final videos = videoList.map((json) {
            print('Processing video: ${json['videoName']}');
            print('Original videoUrl: ${json['videoUrl']}');
            print('Original thumbnailUrl: ${json['thumbnailUrl']}');

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

            print('Final videoUrl: ${json['videoUrl']}');
            print('Final thumbnailUrl: ${json['thumbnailUrl']}');

            return VideoModel.fromJson(json);
          }).toList();

          return videos;
        } catch (e) {
          print('Error parsing JSON response: $e');
          throw Exception('Invalid response format from server');
        }
      } else if (response.statusCode == 404) {
        print('No videos found for user');
        return [];
      } else {
        print('Server error: ${response.statusCode}');
        print('Error response: ${response.body}');
        throw Exception('Failed to fetch user videos: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching user videos: $e');
      if (e is TimeoutException) {
        throw Exception(
            'Request timed out. Please check your internet connection and try again.');
      }
      rethrow;
    }
  }

  /// Gets authentication headers for API requests
  /// Returns a map containing Content-Type and Authorization headers
  /// Throws an exception if user is not authenticated
  Future<Map<String, String>> _getAuthHeaders() async {
    final googleAuthService = GoogleAuthService();
    final userData = await googleAuthService.getUserData();

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

  /// Deletes a video from the server
  /// Parameters:
  /// - videoId: The ID of the video to delete
  /// Returns true if deletion was successful, false otherwise
  Future<bool> deleteVideo(String videoId) async {
    try {
      // Check authentication first
      final googleAuthService = GoogleAuthService();
      final userData = await googleAuthService.getUserData();

      if (userData == null) {
        throw Exception('Please sign in to delete videos');
      }

      final res = await http.delete(
        Uri.parse('$baseUrl/api/videos/$videoId'),
        headers: {
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 || res.statusCode == 204) {
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
      if (e is TimeoutException) {
        throw Exception('Request timed out. Please try again.');
      } else if (e is Exception) {
        rethrow;
      }
      throw Exception('Network error: $e');
    }
  }
}
