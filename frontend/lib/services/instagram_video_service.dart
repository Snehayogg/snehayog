import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:video_compress/video_compress.dart';

/// **SIMPLIFIED InstagramVideoService - Only essential methods kept**
/// All caching functionality has been moved to VideoCacheManager
class InstagramVideoService {
  final AuthService _authService = AuthService();
  // Use a default URL or get from environment
  final String baseUrl =
      'http://192.168.0.190:5001'; // Default local network IP

  /// **ESSENTIAL: Toggle like functionality**
  Future<VideoModel> toggleLike(String videoId, String userId) async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('Please sign in to like videos');
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
        return videoModel;
      } else {
        throw Exception('Failed to like video: ${res.statusCode}');
      }
    } catch (e) {
      print('❌ InstagramVideoService: Error in toggleLike: $e');
      rethrow;
    }
  }

  /// **ESSENTIAL: Add comment functionality**
  Future<List<Map<String, dynamic>>> addComment(
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
        return commentsJson.cast<Map<String, dynamic>>();
      } else {
        throw Exception('Failed to add comment: ${res.statusCode}');
      }
    } catch (e) {
      print('❌ InstagramVideoService: Error in addComment: $e');
      rethrow;
    }
  }

  /// **ESSENTIAL: Upload video functionality**
  Future<Map<String, dynamic>> uploadVideo(
    File videoFile,
    String videoName,
    String? description,
    String userId,
  ) async {
    try {
      print('🚀 InstagramVideoService: Starting video upload...');

      // Check if video is too long
      final isLong = await isLongVideo(videoFile.path);
      if (isLong) {
        throw Exception('Video is too long. Please upload a shorter video.');
      }

      // Compress video
      final compressedFile = await _compressVideo(videoFile);
      if (compressedFile == null) {
        throw Exception('Failed to compress video');
      }

      // Create multipart request
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/videos/upload'),
      );

      // Add headers
      request.headers['Content-Type'] = 'multipart/form-data';
      final authHeaders = await _getAuthHeaders();
      request.headers.addAll(authHeaders);

      // Add fields
      request.fields['videoName'] = videoName;
      if (description != null) {
        request.fields['description'] = description;
      }
      request.fields['userId'] = userId;

      // Add video file
      final videoStream = http.ByteStream(compressedFile.openRead());
      final videoLength = await compressedFile.length();
      final videoMultipart = http.MultipartFile(
        'video',
        videoStream,
        videoLength,
        filename: 'video.mp4',
      );
      request.files.add(videoMultipart);

      // Send request
      final response = await request.send().timeout(const Duration(minutes: 5));
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final data = json.decode(responseBody);
        print('✅ InstagramVideoService: Video uploaded successfully');
        return data;
      } else {
        throw Exception(
            'Upload failed: ${response.statusCode} - $responseBody');
      }
    } catch (e) {
      print('❌ InstagramVideoService: Error uploading video: $e');
      rethrow;
    }
  }

  /// **ESSENTIAL: Get video by ID (for individual video details)**
  Future<VideoModel?> getVideoById(String id,
      {bool forceRefresh = false}) async {
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/api/videos/$id'),
            headers: await _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        return VideoModel.fromJson(data);
      } else if (res.statusCode == 404) {
        return null;
      } else {
        throw Exception('Failed to get video: ${res.statusCode}');
      }
    } catch (e) {
      print('❌ InstagramVideoService: Error getting video by ID: $e');
      rethrow;
    }
  }

  /// **ESSENTIAL: Get videos with pagination (for VideoCacheManager)**
  Future<Map<String, dynamic>> getVideos({
    int page = 1,
    int limit = 10,
    bool forceRefresh = false,
  }) async {
    try {
      print(
          '🔍 InstagramVideoService: Fetching videos from: $baseUrl/api/videos?page=$page&limit=$limit');

      // **NEW: CDN Edge Caching Headers for videoScreen**
      final headers = await _getAuthHeaders();
      headers.addAll({
        'Accept': 'application/json',
        'Accept-Encoding':
            'gzip, deflate', // **FIXED: Remove 'br' to avoid Brotli compression issues**
        'Cache-Control': forceRefresh
            ? 'no-cache'
            : 'max-age=300', // 5 minutes for CDN edge caching
        'X-Requested-With': 'XMLHttpRequest',
        'X-Client-Version': '1.0.0',
        'X-Screen-Type': 'videoScreen', // Identify this is for videoScreen
      });

      final res = await http
          .get(
            Uri.parse('$baseUrl/api/videos?page=$page&limit=$limit'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));

      print('🔍 InstagramVideoService: Response status: ${res.statusCode}');
      print('🔍 InstagramVideoService: Response headers: ${res.headers}');

      // **NEW: Check CDN caching headers**
      final cacheControl = res.headers['cache-control'];
      final etag = res.headers['etag'];
      final lastModified = res.headers['last-modified'];

      print('🔍 InstagramVideoService: CDN Cache Headers:');
      print('  - Cache-Control: $cacheControl');
      print('  - ETag: $etag');
      print('  - Last-Modified: $lastModified');

      if (res.statusCode == 200) {
        // **FIXED: Use robust response body decoding**
        final responseBody = _decodeResponseBody(res);
        print(
            '🔍 InstagramVideoService: Response body length: ${responseBody.length}');

        final data = json.decode(responseBody);
        print('🔍 InstagramVideoService: Raw response data: $data');

        final List<dynamic> videosJson = data['videos'] ?? [];
        print('🔍 InstagramVideoService: Videos JSON array: $videosJson');
        print(
            '🔍 InstagramVideoService: Videos JSON type: ${videosJson.runtimeType}');

        final videos = videosJson.map((json) {
          print('🔍 InstagramVideoService: Parsing video JSON: $json');
          return VideoModel.fromJson(json);
        }).toList();

        print(
            '🔍 InstagramVideoService: Parsed ${videos.length} videos successfully');

        return {
          'videos': videos,
          'hasMore': data['hasMore'] ?? false,
          'total': data['total'] ?? videos.length,
          'currentPage': page,
          'status': 200,
          // **NEW: Include CDN caching metadata**
          'cdnCache': {
            'etag': etag,
            'lastModified': lastModified,
            'cacheControl': cacheControl,
            'isFromCDN': _isResponseFromCDN(res.headers),
          },
        };
      } else {
        throw Exception('Failed to get videos: ${res.statusCode}');
      }
    } catch (e) {
      print('❌ InstagramVideoService: Error getting videos: $e');
      print('❌ InstagramVideoService: Error type: ${e.runtimeType}');
      if (e is SocketException) {
        print(
            '❌ InstagramVideoService: Network error - check if backend is running on $baseUrl');
      }
      rethrow;
    }
  }

  /// **NEW: Get videos with conditional requests for optimal CDN caching**
  Future<Map<String, dynamic>> getVideosWithConditionalRequest({
    int page = 1,
    int limit = 10,
    String? etag,
    String? lastModified,
    bool forceRefresh = false,
  }) async {
    try {
      print(
          '🔍 InstagramVideoService: Conditional request for videos - Page: $page, ETag: $etag');

      // **NEW: Conditional request headers for CDN optimization**
      final headers = await _getAuthHeaders();
      headers.addAll({
        'Accept': 'application/json',
        'Accept-Encoding':
            'gzip, deflate', // **FIXED: Remove 'br' to avoid Brotli compression issues**
        'Cache-Control': forceRefresh ? 'no-cache' : 'max-age=300',
        'X-Requested-With': 'XMLHttpRequest',
        'X-Client-Version': '1.0.0',
        'X-Screen-Type': 'videoScreen',
      });

      // Add conditional request headers if available
      if (etag != null && !forceRefresh) {
        headers['If-None-Match'] = etag;
        print('🔍 InstagramVideoService: Using If-None-Match: $etag');
      }

      if (lastModified != null && !forceRefresh) {
        headers['If-Modified-Since'] = lastModified;
        print(
            '🔍 InstagramVideoService: Using If-Modified-Since: $lastModified');
      }

      final res = await http
          .get(
            Uri.parse('$baseUrl/api/videos?page=$page&limit=$limit'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));

      print(
          '🔍 InstagramVideoService: Conditional response status: ${res.statusCode}');

      // Handle 304 Not Modified (CDN cache hit)
      if (res.statusCode == 304) {
        print('✅ InstagramVideoService: 304 Not Modified - CDN cache hit!');
        return {
          'videos': [],
          'hasMore': false,
          'total': 0,
          'currentPage': page,
          'status': 304,
          'cdnCache': {
            'etag': etag,
            'lastModified': lastModified,
            'cacheControl': res.headers['cache-control'],
            'isFromCDN': _isResponseFromCDN(res.headers),
            'cacheStatus': 'HIT',
          },
        };
      }

      if (res.statusCode == 200) {
        // **FIXED: Use robust response body decoding**
        final responseBody = _decodeResponseBody(res);
        print(
            '🔍 InstagramVideoService: Conditional response body length: ${responseBody.length}');

        final data = json.decode(responseBody);
        final List<dynamic> videosJson = data['videos'] ?? [];
        final videos =
            videosJson.map((json) => VideoModel.fromJson(json)).toList();

        // Extract new cache headers
        final newEtag = res.headers['etag'];
        final newLastModified = res.headers['last-modified'];
        final cacheControl = res.headers['cache-control'];

        print(
            '✅ InstagramVideoService: Fresh data received - ${videos.length} videos');
        print('🔍 InstagramVideoService: New ETag: $newEtag');
        print('🔍 InstagramVideoService: New Last-Modified: $newLastModified');

        return {
          'videos': videos,
          'hasMore': data['hasMore'] ?? false,
          'total': data['total'] ?? videos.length,
          'currentPage': page,
          'status': 200,
          'cdnCache': {
            'etag': newEtag,
            'lastModified': newLastModified,
            'cacheControl': cacheControl,
            'isFromCDN': _isResponseFromCDN(res.headers),
            'cacheStatus': 'MISS',
          },
        };
      }

      throw Exception('Failed to get videos: ${res.statusCode}');
    } catch (e) {
      print('❌ InstagramVideoService: Error in conditional request: $e');
      rethrow;
    }
  }

  /// **NEW: Robust response body decoding with fallback methods**
  String _decodeResponseBody(http.Response response) {
    try {
      // First try: Direct string decoding
      final body = response.body;
      if (body.isNotEmpty) {
        print(
            '🔍 InstagramVideoService: Successfully decoded response as string (length: ${body.length})');
        return body;
      }
    } catch (e) {
      print('⚠️ InstagramVideoService: String decoding failed: $e');
    }

    try {
      // Second try: UTF-8 byte decoding
      final decoded = utf8.decode(response.bodyBytes);
      print(
          '🔍 InstagramVideoService: Successfully decoded response as UTF-8 bytes (length: ${decoded.length})');
      return decoded;
    } catch (e) {
      print('⚠️ InstagramVideoService: UTF-8 decoding failed: $e');
    }

    try {
      // Third try: Latin-1 decoding (fallback for binary data)
      final decoded = latin1.decode(response.bodyBytes);
      print(
          '🔍 InstagramVideoService: Successfully decoded response as Latin-1 (length: ${decoded.length})');
      return decoded;
    } catch (e) {
      print('⚠️ InstagramVideoService: Latin-1 decoding failed: $e');
    }

    // Last resort: Try to extract readable content
    try {
      final bytes = response.bodyBytes;
      final readableBytes =
          bytes.where((byte) => byte >= 32 && byte <= 126).toList();
      final decoded = String.fromCharCodes(readableBytes);
      print(
          '🔍 InstagramVideoService: Extracted readable content (length: ${decoded.length})');
      return decoded;
    } catch (e) {
      print('❌ InstagramVideoService: All decoding methods failed: $e');
      throw Exception('Failed to decode response body: All methods exhausted');
    }
  }

  /// **NEW: Check if response is from CDN edge cache**
  bool _isResponseFromCDN(Map<String, String> headers) {
    // Check for CDN-specific headers
    final cdnHeaders = [
      'cf-cache-status', // Cloudflare
      'x-cache', // Various CDNs
      'x-amz-cf-pop', // AWS CloudFront
      'x-vercel-cache', // Vercel
      'x-fastly', // Fastly
      'x-cdn-cache', // Generic CDN
    ];

    for (final header in cdnHeaders) {
      if (headers.containsKey(header)) {
        print(
            '🔍 InstagramVideoService: CDN header detected: $header = ${headers[header]}');
        return true;
      }
    }

    // Check for Cloudinary-specific headers
    if (headers.containsKey('x-request-id') &&
        headers['x-request-id']!.contains('cloudinary')) {
      print('🔍 InstagramVideoService: Cloudinary CDN detected');
      return true;
    }

    return false;
  }

  /// **ESSENTIAL: Get user videos (for profile screen)**
  Future<List<VideoModel>> getUserVideos(String userId,
      {bool forceRefresh = false}) async {
    try {
      final res = await http
          .get(
            Uri.parse('$baseUrl/api/videos/user/$userId'),
            headers: await _getAuthHeaders(),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final List<dynamic> videosJson = json.decode(res.body);
        return videosJson.map((json) => VideoModel.fromJson(json)).toList();
      } else {
        throw Exception('Failed to get user videos: ${res.statusCode}');
      }
    } catch (e) {
      print('❌ InstagramVideoService: Error getting user videos: $e');
      rethrow;
    }
  }

  /// **ESSENTIAL: Check server health**
  Future<bool> checkServerHealth() async {
    try {
      print(
          '🔍 InstagramVideoService: Checking server health at: $baseUrl/api/health');
      final res = await http
          .get(Uri.parse('$baseUrl/api/health'))
          .timeout(const Duration(seconds: 5));
      print(
          '🔍 InstagramVideoService: Health check response: ${res.statusCode}');
      return res.statusCode == 200;
    } catch (e) {
      print('❌ InstagramVideoService: Server health check failed: $e');
      print('❌ InstagramVideoService: Error type: ${e.runtimeType}');
      if (e is SocketException) {
        print(
            '❌ InstagramVideoService: Network error - backend not accessible at $baseUrl');
      }
      return false;
    }
  }

  /// **HELPER: Check if video is too long**
  Future<bool> isLongVideo(String videoPath) async {
    try {
      final file = File(videoPath);
      if (!await file.exists()) return false;

      final fileSize = await file.length();
      const maxSize = 100 * 1024 * 1024; // 100MB
      return fileSize > maxSize;
    } catch (e) {
      print('❌ InstagramVideoService: Error checking video length: $e');
      return false;
    }
  }

  /// **HELPER: Compress video**
  Future<File?> _compressVideo(File videoFile) async {
    try {
      print('🔄 InstagramVideoService: Compressing video...');

      final MediaInfo? mediaInfo = await VideoCompress.compressVideo(
        videoFile.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
      );

      if (mediaInfo?.file != null) {
        print('✅ InstagramVideoService: Video compressed successfully');
        return mediaInfo!.file;
      } else {
        print('❌ InstagramVideoService: Video compression failed');
        return null;
      }
    } catch (e) {
      print('❌ InstagramVideoService: Error compressing video: $e');
      return null;
    }
  }

  /// **HELPER: Get authentication headers**
  Future<Map<String, String>> _getAuthHeaders() async {
    try {
      final userData = await _authService.getUserData();
      if (userData != null && userData['token'] != null) {
        return {'Authorization': 'Bearer ${userData['token']}'};
      }
      return {};
    } catch (e) {
      print('❌ InstagramVideoService: Error getting auth headers: $e');
      return {};
    }
  }

  /// **DISPOSE: Clean up resources**
  void dispose() {
    print('🔄 InstagramVideoService: Disposing...');
    // No specific cleanup needed for this simplified version
  }
}
