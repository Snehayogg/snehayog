import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:snehayog/config/app_config.dart';
import 'package:snehayog/services/authservices.dart';

class CloudinaryService {
  static final CloudinaryService _instance = CloudinaryService._internal();
  factory CloudinaryService() => _instance;
  CloudinaryService._internal();

  /// Upload image through your backend (which handles Cloudinary)
  Future<String> uploadImage(File imageFile, {String? folder}) async {
    try {
      // Get user data for authentication
      final authService = AuthService();
      final userData = await authService.getUserData();

      if (userData == null) {
        throw Exception('User not authenticated');
      }

      // Create multipart request to your backend
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.baseUrl}/api/upload/image'),
      );

      // Add authorization header
      request.headers['Authorization'] = 'Bearer ${userData['token']}';

      // Add the image file
      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );

      // Add folder if specified
      if (folder != null) {
        request.fields['folder'] = folder;
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data['url'] ?? '';
        } else {
          throw Exception('Upload failed: ${data['error'] ?? 'Unknown error'}');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(
            'Failed to upload image: ${errorData['error'] ?? response.body}');
      }
    } catch (e) {
      throw Exception('Error uploading image: $e');
    }
  }

  /// Upload video through your backend (which handles Cloudinary)
  Future<String> uploadVideo(File videoFile, {String? folder}) async {
    try {
      // Get user data for authentication
      final authService = AuthService();
      final userData = await authService.getUserData();

      if (userData == null) {
        throw Exception('User not authenticated');
      }

      // Create multipart request to your backend
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${AppConfig.baseUrl}/api/upload/video'),
      );

      // Add authorization header
      request.headers['Authorization'] = 'Bearer ${userData['token']}';

      // Add the video file
      request.files.add(
        await http.MultipartFile.fromPath('video', videoFile.path),
      );

      // Add folder if specified
      if (folder != null) {
        request.fields['folder'] = folder;
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          return data['url'] ?? '';
        } else {
          throw Exception('Upload failed: ${data['error'] ?? 'Unknown error'}');
        }
      } else {
        final errorData = json.decode(response.body);
        throw Exception(
            'Failed to upload video: ${errorData['error'] ?? response.body}');
      }
    } catch (e) {
      throw Exception('Error uploading video: $e');
    }
  }

  /// Delete media through your backend
  Future<bool> deleteMedia(String publicId, String resourceType) async {
    try {
      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/upload/delete'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'public_id': publicId,
          'resource_type': resourceType,
        }),
      );

      return response.statusCode == 200;
    } catch (e) {
      print('Error deleting media: $e');
      return false;
    }
  }

  /// Get optimized URL for different screen sizes
  String getOptimizedUrl(String originalUrl, {int? width, int? height}) {
    if (originalUrl.isEmpty) return originalUrl;

    // If it's a Cloudinary URL, apply transformations
    if (originalUrl.contains('cloudinary.com')) {
      final uri = Uri.parse(originalUrl);
      final pathSegments = List<String>.from(uri.pathSegments);

      if (pathSegments.length >= 3 && pathSegments[1] == 'upload') {
        // Insert transformation before 'upload'
        String transformation = 'f_auto,q_auto';
        if (width != null) transformation += ',w_$width';
        if (height != null) transformation += ',h_$height';
        transformation += ',c_fill';

        pathSegments.insert(2, transformation);
        return uri.replace(pathSegments: pathSegments).toString();
      }
    }

    return originalUrl;
  }

  /// Get thumbnail URL for videos
  String getVideoThumbnailUrl(String videoUrl) {
    if (videoUrl.isEmpty) return videoUrl;

    // If it's a Cloudinary URL, apply thumbnail transformation
    if (videoUrl.contains('cloudinary.com')) {
      final uri = Uri.parse(videoUrl);
      final pathSegments = List<String>.from(uri.pathSegments);

      if (pathSegments.length >= 3 && pathSegments[1] == 'upload') {
        // Insert thumbnail transformation
        pathSegments.insert(2, 'f_jpg,w_400,h_600,c_fill');
        return uri.replace(pathSegments: pathSegments).toString();
      }
    }

    return videoUrl;
  }

  /// **NEW: Check if backend upload endpoints are available**
  Future<bool> isBackendUploadAvailable() async {
    try {
      final response = await http
          .get(
            Uri.parse('${AppConfig.baseUrl}/api/upload/health'),
          )
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
