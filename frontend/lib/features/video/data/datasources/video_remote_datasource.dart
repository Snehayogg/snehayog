import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import '../../../../core/services/http_client_service.dart';
import 'package:video_player/video_player.dart';
import '../../../../config/app_config.dart';
import '../../../../core/exceptions/app_exceptions.dart';
import '../../../../model/video_model.dart';
import '../models/comment_model.dart';
import '../../../../services/authservices.dart';
import '../../../../services/platform_id_service.dart';

/// Remote data source for video operations
/// Handles all HTTP requests to the video API
class VideoRemoteDataSource {
  // Using httpClientService for better performance and connection pooling

  /// Fetches a paginated list of videos from the server
  Future<Map<String, dynamic>> getVideos({
    int page = 1,
    int limit = 10,
    bool clearSession = false,
    String videoType = 'yog', // **NEW: Support video type filtering**
  }) async {
    try {
      // **FIXED: Send platform ID and Auth Token for session persistence**
      // This ensures previously watched/shown videos are excluded
      final platformId = await PlatformIdService().getPlatformId();

      // Get auth token if available
      String? token;
      try {
        final authData = await AuthService().getUserData();
        token = authData?['token'];
      } catch (_) {
        // Ignore auth errors - proceed as anonymous
      }

      // Add platformId and videoType to query params
      final url =
          '${NetworkHelper.videosEndpoint}?page=$page&limit=$limit&videoType=$videoType&platformId=$platformId${clearSession ? '&clearSession=true' : ''}';

      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
        if (platformId.isNotEmpty) 'x-device-id': platformId,
      };

      final response = await httpClientService.get(
        Uri.parse(url),
        headers: headers,
        timeout: NetworkHelper.defaultTimeout,
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        final List<dynamic> videoList = responseData['videos'];

        final videos = videoList.map((json) {
          // Ensure URLs are complete if they're relative paths
          if (json['videoUrl'] != null &&
              !json['videoUrl'].toString().startsWith('http')) {
            json['videoUrl'] =
                '${NetworkHelper.getBaseUrl()}/${json['videoUrl']}';
          }
          if (json['thumbnailUrl'] != null &&
              !json['thumbnailUrl'].toString().startsWith('http')) {
            json['thumbnailUrl'] =
                '${NetworkHelper.getBaseUrl()}/${json['thumbnailUrl']}';
          }
          return VideoModel.fromJson(json);
        }).toList();

        return {
          'videos': videos,
          'hasMore': responseData['hasMore'] ?? false,
        };
      } else {
        throw ServerException(
          'Failed to load videos: ${response.statusCode}',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      _handleError(e);
    }
  }

  /// Fetches a specific video by its ID
  Future<VideoModel> getVideoById(String id) async {
    try {
      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.videosEndpoint}/$id'),
        timeout: NetworkHelper.defaultTimeout,
      );

      if (response.statusCode == 200) {
        return VideoModel.fromJson(json.decode(response.body));
      } else if (response.statusCode == 404) {
        throw const DataException('Video not found');
      } else {
        final error = json.decode(response.body);
        throw ServerException(
          error['error'] ?? 'Failed to load video',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      _handleError(e);
    }
  }

  /// Fetches all videos uploaded by a specific user
  Future<List<VideoModel>> getUserVideos(String userId) async {
    try {
      // **FIXED: Add authentication headers - backend endpoint requires verifyToken**
      final auth = AuthService();
      final userData = await auth.getUserData();
      if (userData == null || userData['token'] == null) {
        throw const UnauthorizedException(
            'Please sign in to view creator videos');
      }

      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${userData['token']}',
      };

      final url = '${NetworkHelper.videosEndpoint}/user/$userId';

      final response = await httpClientService.get(
        Uri.parse(url),
        headers: headers,
        timeout: NetworkHelper.defaultTimeout,
      );

      if (response.statusCode == 200) {
        final List<dynamic> videoList = json.decode(response.body);

        return videoList.map((json) {
          // Ensure URLs are complete if they're relative paths
          if (json['videoUrl'] != null &&
              !json['videoUrl'].toString().startsWith('http')) {
            json['videoUrl'] =
                '${NetworkHelper.getBaseUrl()}/${json['videoUrl']}';
          }
          if (json['thumbnailUrl'] != null &&
              !json['thumbnailUrl'].toString().startsWith('http')) {
            json['thumbnailUrl'] =
                '${NetworkHelper.getBaseUrl()}/${json['thumbnailUrl']}';
          }
          return VideoModel.fromJson(json);
        }).toList();
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        // **FIXED: Handle authentication errors properly**
        throw const UnauthorizedException(
            'Please sign in to view creator videos');
      } else if (response.statusCode == 404) {
        return [];
      } else {
        final error = json.decode(response.body);
        throw ServerException(
          error['error'] ??
              'Failed to fetch user videos: ${response.statusCode}',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      _handleError(e);
    }
  }

  /// Uploads a new video to the server
  Future<Map<String, dynamic>> uploadVideo({
    required String videoPath,
    required String title,
    required String description,
    String? link,
    Function(double)? onProgress,
  }) async {
    try {
      // final videoFile = File(videoPath); // Unused variable
      final isLong = await _isLongVideo(videoPath);

      // Create a multipart request
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('${NetworkHelper.videosEndpoint}/upload'),
      );

      // Add the video file
      request.files.add(
        await http.MultipartFile.fromPath(
          'video',
          videoPath,
          contentType: MediaType('video', 'mp4'),
        ),
      );

      // Add other fields
      request.fields['videoName'] = title;
      request.fields['description'] = description;
      request.fields['videoType'] = 'yog';
      if (link != null && link.isNotEmpty) {
        request.fields['link'] = link;
      }

      // Send the request with timeout using httpClientService
      final streamedResponse = await httpClientService.send(
        request,
        timeout: NetworkHelper.uploadTimeout,
      );

      // Get the response
      final responseBody = await streamedResponse.stream.bytesToString();
      final responseData = json.decode(responseBody);

      if (streamedResponse.statusCode == 201) {
        final videoData = responseData['video'];

        return {
          'id': videoData['_id'],
          'title': videoData['videoName'],
          'description': videoData['description'],
          'videoUrl': videoData['videoUrl'],
          'thumbnail': videoData['thumbnailUrl'],
          'originalVideoUrl': videoData['originalVideoUrl'],
          'duration': '0:00',
          'views': 0,
          'uploader': 'Current User', // This will be set by the use case
          'uploadTime': 'Just now',
          'isLongVideo': isLong,
          'link': videoData['link'],
        };
      } else {
        _handleUploadError(responseData);
      }
    } catch (e) {
      _handleError(e);
    }
  }

  /// Toggles the like status of a video
  Future<VideoModel> toggleLike(String videoId, String userId) async {
    try {
      // Use auth token as backend reads userId from token
      final auth = AuthService();
      final userData = await auth.getUserData();
      if (userData == null || userData['token'] == null) {
        throw const UnauthorizedException(
            'Please sign in again to like videos');
      }
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${userData['token']}',
      };
      final response = await httpClientService.post(
        Uri.parse('${NetworkHelper.videosEndpoint}/$videoId/like'),
        headers: headers,
        body: json.encode({}), // backend derives user from token
        timeout: NetworkHelper.defaultTimeout,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return VideoModel.fromJson(data);
      } else if (response.statusCode == 401) {
        throw const UnauthorizedException(
            'Please sign in again to like videos');
      } else if (response.statusCode == 404) {
        final error = json.decode(response.body);
        throw DataException(error['error'] ?? 'Video not found');
      } else {
        final error = json.decode(response.body);
        throw ServerException(
          error['error'] ?? 'Failed to like video',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      _handleError(e);
    }
  }

  /// Adds a comment to a video
  Future<List<CommentModel>> addComment({
    required String videoId,
    required String text,
    required String userId,
  }) async {
    try {
      final response = await httpClientService.post(
        Uri.parse('${NetworkHelper.videosEndpoint}/$videoId/comments'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'userId': userId,
          'text': text,
        }),
        timeout: NetworkHelper.defaultTimeout,
      );

      if (response.statusCode == 200) {
        final List<dynamic> commentsJson = json.decode(response.body);
        return commentsJson.map((json) => CommentModel.fromJson(json)).toList();
      } else if (response.statusCode == 401) {
        throw const UnauthorizedException(
            'Please sign in again to add comments');
      } else {
        final error = json.decode(response.body);
        throw ServerException(
          error['error'] ?? 'Failed to add comment',
          code: response.statusCode.toString(),
        );
      }
    } catch (e) {
      _handleError(e);
    }
  }

  /// Checks if the server is healthy
  Future<bool> checkServerHealth() async {
    try {
      final response = await httpClientService.get(
        Uri.parse(NetworkHelper.healthEndpoint),
        timeout: NetworkHelper.shortTimeout,
      );
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  /// Checks if a video is considered long (more than 2 minutes)
  Future<bool> _isLongVideo(String videoPath) async {
    try {
      final controller = VideoPlayerController.file(File(videoPath));
      await controller.initialize();
      final duration = controller.value.duration;
      await controller.dispose();
      return duration.inSeconds > 120; // 2 minutes
    } catch (e) {
      return false;
    }
  }

  // _makeRequest method removed - using httpClientService which handles retries automatically

  /// Handles upload-specific errors
  Never _handleUploadError(Map<String, dynamic> responseData) {
    if (responseData['error'] != null) {
      final errorMessage = responseData['error'].toString();

      if (errorMessage.contains('File too large')) {
        throw const FileSizeException('File too large. Maximum size is 100MB');
      } else if (errorMessage.contains('Invalid file type')) {
        throw const FileTypeException(
          'Invalid file type. Please upload a video file (MP4, AVI, MOV, WMV, FLV, WEBM)',
        );
      } else if (errorMessage.contains('User not found')) {
        throw const AuthenticationException(
            'User not found. Please sign in again.');
      } else if (errorMessage.contains('Cloudinary upload failed')) {
        throw const ServerException(
          'Video upload service is temporarily unavailable. Please try again later.',
        );
      } else {
        throw ServerException(errorMessage);
      }
    }
    throw const ServerException('Failed to upload video. Please try again.');
  }

  /// Handles general errors and converts them to appropriate exceptions
  Never _handleError(dynamic error) {
    if (error is AppException) {
      throw error; // Changed from rethrow to throw
    } else if (error is TimeoutException) {
      throw const TimeoutException(
        'Request timed out. Please try again.',
      );
    } else if (error is SocketException) {
      throw const NetworkException(
        'Could not connect to server. Please check if the server is running.',
      );
    } else if (error is FormatException) {
      throw const DataException(
          'Invalid response from server. Please try again.');
    }
    throw NetworkException('Network error: $error');
  }
}
