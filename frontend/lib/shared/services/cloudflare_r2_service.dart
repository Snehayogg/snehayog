import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/shared/utils/app_logger.dart';

/// Unified media upload service backed by Cloudflare R2 (via your backend APIs).
/// Replaces the old "CloudinaryService" naming which was confusing.
class CloudflareR2Service {
  static final CloudflareR2Service _instance =
      CloudflareR2Service._internal();
  factory CloudflareR2Service() => _instance;
  CloudflareR2Service._internal();

  /// Get direct upload URL from Worker
  Future<Map<String, dynamic>> _getUploadUrl(String fileName, String folder) async {
    final authService = AuthService();
    final userData = await authService.getUserData();
    if (userData == null) throw Exception('User not authenticated');

    final response = await http.get(
      Uri.parse('${NetworkHelper.uploadUrlEndpoint}?filename=$fileName&folder=$folder'),
      headers: {
        'Authorization': 'Bearer ${userData['token']}',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to get upload URL: ${response.body}');
    }
  }

  /// Perform binary PUT upload to R2
  Future<void> _binaryPutUpload(String uploadUrl, File file) async {
    final bytes = await file.readAsBytes();
    final response = await http.put(
      Uri.parse(uploadUrl),
      body: bytes,
      headers: {
        'Content-Type': 'application/octet-stream',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('Binary upload failed: ${response.statusCode} - ${response.body}');
    }
  }

  /// Upload image via Worker + Direct-to-R2.
  Future<String> uploadImage(File imageFile, {String? folder}) async {
    try {
      if (!await imageFile.exists()) throw Exception('Image file does not exist');
      
      final fileName = imageFile.path.split('/').last.toLowerCase();
      final targetFolder = folder ?? 'snehayog/ads/images';
      
      AppLogger.log('🔍 CloudflareR2Service: Getting signed URL for image...');
      final uploadData = await _getUploadUrl(fileName, targetFolder);
      final uploadUrl = uploadData['uploadUrl'];
      final publicUrl = uploadData['publicUrl'];

      AppLogger.log('🔍 CloudflareR2Service: Uploading image to R2...');
      await _binaryPutUpload(uploadUrl, imageFile);

      AppLogger.log('✅ CloudflareR2Service: Image uploaded successfully to $publicUrl');
      return publicUrl;
    } catch (e) {
      AppLogger.log('❌ CloudflareR2Service: Error uploading image: $e');
      throw Exception('Error uploading image: $e');
    }
  }

  /// Upload video for user content via Worker + Direct-to-R2 + Backend Registration.
  Future<Map<String, dynamic>> uploadVideo(
    File videoFile, {
    String? videoName,
    String? description,
    String? folder,
    String profile = 'portrait_reels',
    bool enableHLS = true,
  }) async {
    try {
      final fileName = videoFile.path.split('/').last.toLowerCase();
      final targetFolder = folder ?? 'snehayog/videos';

      AppLogger.log('🔍 CloudflareR2Service: Getting signed URL for video...');
      final uploadData = await _getUploadUrl(fileName, targetFolder);
      final uploadUrl = uploadData['uploadUrl'];
      final r2Key = uploadData['key'];

      AppLogger.log('🔍 CloudflareR2Service: Uploading video to R2...');
      await _binaryPutUpload(uploadUrl, videoFile);

      AppLogger.log('🔍 CloudflareR2Service: Registering upload with backend...');
      final authService = AuthService();
      final userData = await authService.getUserData();
      
      final response = await http.post(
        Uri.parse('${NetworkHelper.apiBaseUrl}/videos/register-upload'),
        headers: {
          'Authorization': 'Bearer ${userData!['token']}',
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'videoName': videoName ?? fileName,
          'description': description ?? '',
          'r2Key': r2Key,
          'videoType': profile.contains('portrait') ? 'yog' : 'vayu',
          'mimeType': 'video/mp4', // Fallback
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to register upload with backend: ${response.body}');
      }
    } catch (e) {
      AppLogger.log('❌ CloudflareR2Service: Error in direct video upload flow: $e');
      throw Exception('Error uploading video: $e');
    }
  }

  /// Upload video specifically for ads via Worker (simplified).
  Future<Map<String, dynamic>> uploadVideoForAd(File videoFile) async {
    // Re-use uploadVideo logic but with ads folder
    return await uploadVideo(videoFile, folder: 'snehayog/ads/videos');
  }
}


