import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:vayu/shared/config/app_config.dart';
import 'package:vayu/shared/services/http_client_service.dart';
import 'package:vayu/features/auth/data/services/authservices.dart';
import 'package:vayu/shared/utils/app_logger.dart';

/// Unified media upload service backed by Cloudflare R2 (via your backend APIs).
/// Replaces the old "CloudinaryService" naming which was confusing.
class CloudflareR2Service {
  static final CloudflareR2Service _instance =
      CloudflareR2Service._internal();
  factory CloudflareR2Service() => _instance;
  CloudflareR2Service._internal();

  /// Internal helper copied from the original service to sanity‑check files.
  Future<bool> _testFileBeforeUpload(File file) async {
    try {
      if (!await file.exists()) {
        AppLogger.log(
            '❌ CloudflareR2Service: File does not exist: ${file.path}');
        return false;
      }

      final fileSize = await file.length();
      if (fileSize == 0) {
        AppLogger.log(
            '❌ CloudflareR2Service: File is empty: ${file.path}');
        return false;
      }

      final bytes = await file.openRead(0, 1).first;
      if (bytes.isEmpty) {
        AppLogger.log(
            '❌ CloudflareR2Service: Cannot read file: ${file.path}');
        return false;
      }

      AppLogger.log(
        '✅ CloudflareR2Service: File test passed - size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB',
      );
      return true;
    } catch (e) {
      AppLogger.log('❌ CloudflareR2Service: File test failed: $e');
      return false;
    }
  }

  /// Upload image via backend `/api/upload/image` (Cloudflare R2 under the hood).
  Future<String> uploadImage(File imageFile, {String? folder}) async {
    try {
      if (!await imageFile.exists()) {
        throw Exception('Image file does not exist');
      }
      final fileSize = await imageFile.length();
      if (fileSize == 0) {
        throw Exception('Image file is empty');
      }
      if (fileSize > 10 * 1024 * 1024) {
        throw Exception('Image file size must be less than 10MB');
      }

      final fileName = imageFile.path.split('/').last.toLowerCase();
      final isSupported = fileName.endsWith('.jpg') ||
          fileName.endsWith('.jpeg') ||
          fileName.endsWith('.png') ||
          fileName.endsWith('.gif') ||
          fileName.endsWith('.webp') ||
          fileName.endsWith('.heic') ||
          fileName.endsWith('.heif') ||
          fileName.endsWith('.avif') ||
          fileName.endsWith('.bmp');
      if (!isSupported) {
        throw Exception(
          'Invalid image file type. Supported: JPG, PNG, GIF, WebP, HEIC/HEIF, AVIF, BMP',
        );
      }

      AppLogger.log('🔍 CloudflareR2Service: Starting image upload...');
      AppLogger.log('   File path: ${imageFile.path}');
      AppLogger.log('   File name: $fileName');
      AppLogger.log(
        '   File size: ${(fileSize / 1024 / 1024).toStringAsFixed(2)} MB',
      );
      AppLogger.log('   Folder: ${folder ?? 'snehayog/ads/images'}');

      if (!await _testFileBeforeUpload(imageFile)) {
        throw Exception(
          'File validation failed - file may be corrupted or inaccessible',
        );
      }

      final authService = AuthService();
      final userData = await authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${NetworkHelper.apiBaseUrl}/upload/image'),
      );
      request.headers['Authorization'] = 'Bearer ${userData['token']}';
      request.headers['Content-Type'] = 'multipart/form-data';

      String mimeType = 'image/jpeg';
      if (fileName.endsWith('.png')) {
        mimeType = 'image/png';
      } else if (fileName.endsWith('.gif')) {
        mimeType = 'image/gif';
      } else if (fileName.endsWith('.webp')) {
        mimeType = 'image/webp';
      } else if (fileName.endsWith('.heic') || fileName.endsWith('.heif')) {
        mimeType = 'image/heic';
      } else if (fileName.endsWith('.avif')) {
        mimeType = 'image/avif';
      } else if (fileName.endsWith('.bmp')) {
        mimeType = 'image/bmp';
      } else if (fileName.endsWith('.jpg') || fileName.endsWith('.jpeg')) {
        mimeType = 'image/jpeg';
      }

      AppLogger.log('🔍 CloudflareR2Service: Using MIME type: $mimeType');

      final multipartFile = await http.MultipartFile.fromPath(
        'image',
        imageFile.path,
        contentType: MediaType.parse(mimeType),
      );

      request.files.add(multipartFile);
      if (folder != null) {
        request.fields['folder'] = folder;
      }

      AppLogger.log('🔍 CloudflareR2Service: Sending request to backend...');
      final streamedResponse = await httpClientService.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      AppLogger.log(
        '🔍 CloudflareR2Service: Backend response status: ${response.statusCode}',
      );
      AppLogger.log(
        '🔍 CloudflareR2Service: Backend response body: ${response.body}',
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final url = data['url'] ?? '';
          AppLogger.log('✅ CloudflareR2Service: Image uploaded: $url');
          return url;
        }
        throw Exception('Upload failed: ${data['error'] ?? 'Unknown error'}');
      } else {
        final errorData = json.decode(response.body);
        final errorMessage =
            errorData['error'] ?? errorData['details'] ?? response.body;
        AppLogger.log(
          '❌ CloudflareR2Service: Backend error: $errorMessage',
        );
        throw Exception('Failed to upload image. Please try again.');
      }
    } catch (e) {
      AppLogger.log('❌ CloudflareR2Service: Error uploading image: $e');
      throw Exception('Error uploading image: $e');
    }
  }

  /// Upload video for user content via `/api/videos/upload`.
  Future<Map<String, dynamic>> uploadVideo(
    File videoFile, {
    String? folder,
    String profile = 'portrait_reels',
    bool enableHLS = true,
  }) async {
    try {
      final authService = AuthService();
      final userData = await authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      const endpoint = '/videos/upload';
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${NetworkHelper.apiBaseUrl}$endpoint'),
      );
      request.headers['Authorization'] = 'Bearer ${userData['token']}';

      String mimeType = 'video/mp4';
      final fileName = videoFile.path.split('/').last.toLowerCase();
      if (fileName.endsWith('.webm')) {
        mimeType = 'video/webm';
      } else if (fileName.endsWith('.avi')) {
        mimeType = 'video/avi';
      } else if (fileName.endsWith('.mov')) {
        mimeType = 'video/mov';
      } else if (fileName.endsWith('.mkv')) {
        mimeType = 'video/mkv';
      }

      AppLogger.log(
        '🔍 CloudflareR2Service: Using video MIME type: $mimeType',
      );

      final videoPart = await http.MultipartFile.fromPath(
        'video',
        videoFile.path,
        contentType: MediaType.parse(mimeType),
      );
      request.files.add(videoPart);

      request.fields['profile'] = profile;
      request.fields['enableHLS'] = enableHLS.toString();
      if (folder != null) {
        request.fields['folder'] = folder;
      }

      final streamedResponse = await httpClientService.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body) as Map<String, dynamic>;
        return data;
      } else {
        final errorData = json.decode(response.body);
        final errorMessage =
            errorData['error'] ?? errorData['details'] ?? response.body;
        throw Exception(
          'Video upload failed: $errorMessage',
        );
      }
    } catch (e) {
      AppLogger.log('❌ CloudflareR2Service: Error uploading video: $e');
      throw Exception('Error uploading video: $e');
    }
  }

  /// Upload video specifically for ads via `/api/upload/video`.
  Future<Map<String, dynamic>> uploadVideoForAd(File videoFile) async {
    try {
      final authService = AuthService();
      final userData = await authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${NetworkHelper.apiBaseUrl}/upload/video'),
      );
      request.headers['Authorization'] = 'Bearer ${userData['token']}';

      String mimeType = 'video/mp4';
      final fileName = videoFile.path.split('/').last.toLowerCase();
      if (fileName.endsWith('.webm')) {
        mimeType = 'video/webm';
      } else if (fileName.endsWith('.avi')) {
        mimeType = 'video/avi';
      } else if (fileName.endsWith('.mov')) {
        mimeType = 'video/mov';
      } else if (fileName.endsWith('.mkv')) {
        mimeType = 'video/mkv';
      }

      AppLogger.log(
        '🔍 CloudflareR2Service: Using video MIME type for ad: $mimeType',
      );

      final videoPart = await http.MultipartFile.fromPath(
        'video',
        videoFile.path,
        contentType: MediaType.parse(mimeType),
      );
      request.files.add(videoPart);

      final streamedResponse = await httpClientService.send(request);
      final response = await http.Response.fromStream(streamedResponse);

      AppLogger.log(
        '🔍 CloudflareR2Service: Video upload response status: ${response.statusCode}',
      );
      AppLogger.log(
        '🔍 CloudflareR2Service: Video upload response body: ${response.body}',
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = json.decode(response.body);
        if (data is Map<String, dynamic>) {
          AppLogger.log(
            '✅ CloudflareR2Service: Video uploaded successfully for ad',
          );
          return data;
        }
        throw Exception('Unexpected response format from server');
      } else {
        final errorData = json.decode(response.body);
        final errorMsg =
            errorData['error'] ?? errorData['details'] ?? response.body;
        AppLogger.log(
          '❌ CloudflareR2Service: Video upload failed: $errorMsg',
        );
        throw Exception('Video upload failed: $errorMsg');
      }
    } catch (e) {
      AppLogger.log(
        '❌ CloudflareR2Service: Error uploading video for ad: $e',
      );
      throw Exception('Error uploading video for ad: $e');
    }
  }
}


