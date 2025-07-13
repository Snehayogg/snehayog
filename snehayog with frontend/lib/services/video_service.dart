import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/controller/google_sign_in_controller.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';
import 'package:snehayog/config/app_config.dart';

/// VideoService class handles all video-related operations including:
/// - Fetching videos
/// - Uploading videos
/// - Managing video interactions (likes, comments, shares)
/// - Video search functionality
class VideoService {
  // Global key for accessing the navigator context
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // Base URL for API endpoints
  static String get baseUrl {
    return NetworkHelper.getBaseUrl();
  }

  // Maximum number of retry attempts for failed requests
  static const int maxRetries = 3;

  // Delay between retries (in seconds)
  static const int retryDelay = 2;

  // Maximum duration for short videos (in seconds)
  static const int maxShortVideoDuration = 120; // 2 minutes

  // Add server health check method
  Future<bool> checkServerHealth() async {
    try {
      print('Checking server health at: $baseUrl/api/test');
      final response = await http.get(Uri.parse('$baseUrl/api/test')).timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          print('Server health check timed out');
          throw TimeoutException('Server health check timed out');
        },
      );

      print('Server health check response: ${response.statusCode}');
      print('Server health check body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Server is healthy: ${data['message']}');
        return true;
      }
      return false;
    } catch (e) {
      print('Server health check failed: $e');
      if (e is SocketException) {
        print('Socket exception - server might be down or unreachable');
      } else if (e is TimeoutException) {
        print('Timeout exception - server is not responding');
      }
      return false;
    }
  }

  // Add method to make HTTP requests with retry logic
  Future<http.Response> _makeRequest(
    Future<http.Response> Function() requestFn, {
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 2),
    Duration timeout = const Duration(seconds: 30),
  }) async {
    int attempts = 0;
    while (attempts < maxRetries) {
      try {
        // Check server health before making request
        final isHealthy = await checkServerHealth();
        if (!isHealthy) {
          print(
              'Server health check failed, retrying in ${retryDelay * (attempts + 1)} seconds...');
          await Future.delayed(retryDelay * (attempts + 1));
          attempts++;
          continue;
        }

        final response = await requestFn().timeout(
          timeout,
          onTimeout: () {
            throw TimeoutException('Request timed out. Please try again.');
          },
        );

        if (response.statusCode == 200) {
          return response;
        }

        // If we get here, the request failed but didn't throw an exception
        attempts++;
        if (attempts < maxRetries) {
          print(
              'Request failed with status ${response.statusCode}, retrying in ${retryDelay * attempts} seconds...');
          await Future.delayed(retryDelay * attempts); // Exponential backoff
        }
      } catch (e) {
        print('Request failed (Attempt ${attempts + 1}/$maxRetries): $e');
        attempts++;
        if (attempts >= maxRetries) {
          if (e is SocketException) {
            throw Exception(
                'Cannot connect to server. Please check if the server is running and accessible.');
          } else if (e is TimeoutException) {
            throw Exception(
                'Server is not responding. Please check your internet connection and try again.');
          }
          rethrow;
        }
        print('Retrying in ${retryDelay * attempts} seconds...');
        await Future.delayed(retryDelay * attempts); // Exponential backoff
      }
    }
    throw Exception(
        'Failed to connect to server after $maxRetries attempts. Please check if the server is running.');
  }

  /// Fetches a list of videos from the server
  /// Returns a map containing the list of VideoModel objects and pagination info
  Future<Map<String, dynamic>> getVideos({int page = 1, int limit = 10}) async {
    try {
      final url = '$baseUrl/api/videos?page=$page&limit=$limit';
      print('Fetching videos from: $url');

      final response = await _makeRequest(
        () => http.get(Uri.parse(url)),
        timeout: const Duration(seconds: 30),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        final List<dynamic> videoList = responseData['videos'];

        final videos = videoList.map((json) {
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
      print('Error in getVideos: $e');
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

  /// Toggles the like status of a video for a specific user
  /// Parameters:
  /// - videoId: The ID of the video to like/unlike
  /// - userId: The ID of the user performing the action
  /// Returns the updated VideoModel
  Future<VideoModel> toggleLike(String videoId, String userId) async {
    try {
      final headers = await _getAuthHeaders();

      final res = await http
          .post(
            Uri.parse('$baseUrl/api/videos/$videoId/like'),
            headers: headers,
            body: json.encode({'userId': userId}),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return VideoModel.fromJson(data);
      } else if (res.statusCode == 401) {
        throw Exception('Please sign in again to like videos');
      } else {
        final error = json.decode(res.body);
        throw Exception(error['error'] ?? 'Failed to like video');
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

  /// Adds a comment to a video
  /// Parameters:
  /// - videoId: The ID of the video to comment on
  /// - text: The comment text
  /// - userId: The ID of the user making the comment
  /// Returns a list of all comments for the video
  Future<List<Comment>> addComment(
      String videoId, String text, String userId) async {
    try {
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
      {Function(double)? onProgress}) async {
    try {
      print('Using server at: $baseUrl');

      // Check server health before upload
      final isHealthy = await checkServerHealth();
      if (!isHealthy) {
        throw Exception(
            'Server is not responding. Please check your connection and try again.');
      }

      final isLong = await isLongVideo(videoFile.path);
      final authController = Provider.of<GoogleSignInController>(
        navigatorKey.currentContext!,
        listen: false,
      );

      if (!authController.isSignedIn) {
        throw Exception('User not authenticated');
      }

      final userData = authController.userData;
      if (userData == null) {
        throw Exception('User data not found');
      }

      print('User data for upload: ${userData.toString()}');

      // Check file size before upload
      final fileSize = await videoFile.length();
      final maxSize = 100 * 1024 * 1024; // 100MB
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
          videoFile.path, // Upload the original file
        ),
      );

      // Add other fields
      request.fields['googleId'] = userData['id'];
      request.fields['videoName'] = title;
      request.fields['description'] = description;
      request.fields['videoType'] = isLong ? 'yog' : 'sneha';

      print('Uploading video with fields: ${request.fields}');

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

      print('Upload response: $responseData');

      if (streamedResponse.statusCode == 201) {
        final videoData = responseData['video'];

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
        };
      } else {
        print('Upload failed with status: ${streamedResponse.statusCode}');
        print('Upload error: $responseData');

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
    final authController = Provider.of<GoogleSignInController>(
      navigatorKey.currentContext!,
      listen: false,
    );

    if (!authController.isSignedIn) {
      throw Exception('User not authenticated');
    }

    final userData = authController.userData;
    if (userData == null || userData['token'] == null) {
      throw Exception('Authentication token not found');
    }

    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer ${userData['token']}',
    };
  }
}
