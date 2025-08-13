import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/network/network_helper.dart';
import '../../../../core/exceptions/app_exceptions.dart';
import '../models/video_model.dart';
import '../models/comment_model.dart';

/// Remote data source for video operations
/// Handles all HTTP requests to the video API
class VideoRemoteDataSource {
  final http.Client _httpClient;

  VideoRemoteDataSource({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// Fetches a paginated list of videos from the server
  Future<Map<String, dynamic>> getVideos({
    int page = 1,
    int limit = 10,
  }) async {
    try {
      final url = '${NetworkHelper.videosEndpoint}?page=$page&limit=$limit';

      final response = await _makeRequest(
        () => _httpClient.get(Uri.parse(url)),
        timeout: NetworkHelper.defaultTimeout,
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = json.decode(response.body);
        final List<dynamic> videoList = responseData['videos'];

        final videos = videoList.map((json) {
          // Ensure URLs are complete if they're relative paths
          if (json['videoUrl'] != null &&
              !json['videoUrl'].toString().startsWith('http')) {
            json['videoUrl'] = '${NetworkHelper.baseUrl}${json['videoUrl']}';
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
      final response = await _makeRequest(
        () => _httpClient.get(Uri.parse('${NetworkHelper.videosEndpoint}/$id')),
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
      final url = '${NetworkHelper.videosEndpoint}/user/$userId';

      final response = await _makeRequest(
        () => _httpClient.get(Uri.parse(url)),
        timeout: NetworkHelper.defaultTimeout,
      );

      if (response.statusCode == 200) {
        final List<dynamic> videoList = json.decode(response.body);

        return videoList.map((json) {
          // Ensure URLs are complete if they're relative paths
          if (json['videoUrl'] != null &&
              !json['videoUrl'].toString().startsWith('http')) {
            json['videoUrl'] = '${NetworkHelper.baseUrl}${json['videoUrl']}';
          }
          if (json['thumbnailUrl'] != null &&
              !json['thumbnailUrl'].toString().startsWith('http')) {
            json['thumbnailUrl'] =
                '${NetworkHelper.baseUrl}${json['thumbnailUrl']}';
          }
          return VideoModel.fromJson(json);
        }).toList();
      } else if (response.statusCode == 404) {
        return [];
      } else {
        throw ServerException(
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
      request.fields['videoType'] = isLong ? 'yog' : 'sneha';
      if (link != null && link.isNotEmpty) {
        request.fields['link'] = link;
      }

      // Send the request with timeout
      final streamedResponse = await request.send().timeout(
        NetworkHelper.uploadTimeout,
        onTimeout: () {
          throw const TimeoutException(
            'Upload timed out. Please check your internet connection and try again.',
          );
        },
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
      final response = await _makeRequest(
        () => _httpClient.post(
          Uri.parse('${NetworkHelper.videosEndpoint}/$videoId/like'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'userId': userId}),
        ),
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
      final response = await _makeRequest(
        () => _httpClient.post(
          Uri.parse('${NetworkHelper.videosEndpoint}/$videoId/comments'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'userId': userId,
            'text': text,
          }),
        ),
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
      final response = await _httpClient
          .get(Uri.parse(NetworkHelper.healthEndpoint))
          .timeout(NetworkHelper.shortTimeout);
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

  /// Makes an HTTP request with retry logic
  Future<http.Response> _makeRequest(
    Future<http.Response> Function() requestFn, {
    int maxRetries = NetworkHelper.defaultMaxRetries,
    Duration retryDelay = NetworkHelper.defaultRetryDelay,
    Duration timeout = NetworkHelper.defaultTimeout,
  }) async {
    int attempts = 0;
    while (attempts < maxRetries) {
      try {
        final response = await requestFn().timeout(timeout);
        if (response.statusCode == 200 || response.statusCode == 201) {
          return response;
        }
        attempts++;
        if (attempts < maxRetries) {
          await Future.delayed(retryDelay * attempts);
        }
      } catch (e) {
        attempts++;
        if (attempts >= maxRetries) rethrow;
        await Future.delayed(retryDelay * attempts);
      }
    }
    throw Exception('Request failed after $maxRetries attempts');
  }

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
