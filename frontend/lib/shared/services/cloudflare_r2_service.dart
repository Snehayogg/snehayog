import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart' as dio;
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:path/path.dart' as p;
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/utils/app_logger.dart';

/// Unified media upload service backed by Cloudflare R2 (via your backend APIs).
class CloudflareR2Service {
  final AuthService authService = AuthService();

  static final CloudflareR2Service _instance =
      CloudflareR2Service._internal();
  factory CloudflareR2Service() => _instance;
  CloudflareR2Service._internal();

  /// Get direct upload URL from Worker
  Future<Map<String, dynamic>> _getUploadUrl(String fileName, String folder) async {
    final userData = await authService.getUserData(forceRefresh: true); // Force fresh token
    if (userData == null) throw Exception('User not authenticated');

    final token = userData['token'] as String?;
    if (token == null) throw Exception('No authentication token found');

    // **DIAGNOSTIC: Log token structure without revealing secret parts**
    final segments = token.split('.');
    AppLogger.log('🔍 CloudflareR2Service: Token segment count: ${segments.length}');
    if (segments.length == 3) {
      AppLogger.log('🔍 CloudflareR2Service: Token appears to be a valid JWT format');
      AppLogger.log('🔍 CloudflareR2Service: Token prefix: ${token.substring(0, min(10, token.length))}...');
    } else {
      AppLogger.log('⚠️ CloudflareR2Service: Token is NOT a 3-part JWT! This will fail at the Worker.');
    }

    final response = await httpClientService.get(
      Uri.parse('${NetworkHelper.uploadUrlEndpoint}?filename=${Uri.encodeComponent(fileName)}&folder=${Uri.encodeComponent(folder)}'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      AppLogger.log('❌ CloudflareR2Service: Worker rejected token!');
      AppLogger.log('❌ Status Code: ${response.statusCode}');
      AppLogger.log('❌ Response Body: ${response.body}');
      
      if (response.body.contains('Invalid Token')) {
        AppLogger.log('💡 TIP: "Invalid Token" from Worker means the signature verification failed.');
        AppLogger.log('💡 TIP: Ensure your backend JWT_SECRET matches the Worker\'s JWT_SECRET.');
      }
      
      throw Exception('Failed to get upload URL: ${response.body}');
    }
  }

  Future<void> _binaryPutUpload(String uploadUrl, File file, String mimeType) async {
    final bytes = await file.readAsBytes();
    final uri = Uri.parse(uploadUrl);
    
    // **FIX: Use a clean HttpClient for the final R2 PUT**
    // Centralized clients often inject extra headers (User-Agent, etc.) 
    // which invalidates the S3 signature on Cloudflare R2, causing 500 errors.
    final client = HttpClient();
    try {
      final request = await client.putUrl(uri);
      
      // Set ONLY the required headers
      request.headers.set('Content-Type', mimeType);
      request.headers.contentLength = bytes.length;
      
      AppLogger.log('📡 CloudflareR2Service: Sending PUT to ${uri.host} with Type: $mimeType');
      
      // Send raw bytes
      request.add(bytes);
      
      final response = await request.close();
      
      if (response.statusCode != 200 && response.statusCode != 201) {
        final responseBody = await response.transform(utf8.decoder).join();
        throw Exception('Binary upload failed: ${response.statusCode} - $responseBody');
      }
    } finally {
      client.close();
    }
  }

  String _getMimeType(String filePath) {
    final extension = p.extension(filePath).toLowerCase();
    switch (extension) {
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.png':
        return 'image/png';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.webm':
        return 'video/webm';
      case '.heic':
        return 'image/heic';
      default:
        // Use standard binary stream if unknown
        return 'application/octet-stream';
    }
  }

  /// Upload image via Worker + Direct-to-R2.
  Future<String> uploadImage(File imageFile, {String? folder}) async {
    try {
      if (!await imageFile.exists()) throw Exception('Image file does not exist');
      
      final fileName = p.basename(imageFile.path).toLowerCase();
      // **TEST: Use the successful video folder to see if it bypasses the 500/Handshake error**
      final targetFolder = folder ?? 'snehayog/videos'; 
      
      AppLogger.log('🔍 CloudflareR2Service: Getting signed URL for image in folder: $targetFolder');
      final uploadData = await _getUploadUrl(fileName, targetFolder);
      final uploadUrl = uploadData['uploadUrl'];
      final publicUrl = uploadData['publicUrl'];

      AppLogger.log('🔍 CloudflareR2Service: Uploading image to R2...');
      AppLogger.log('🔗 CloudflareR2Service: Target URL: ${uploadUrl.split('?')[0]}'); // Log domain/path without secret params
      final mimeType = _getMimeType(imageFile.path);
      await _binaryPutUpload(uploadUrl, imageFile, mimeType);

      AppLogger.log('✅ CloudflareR2Service: Image uploaded successfully to $publicUrl');
      return publicUrl;
    } catch (e) {
      AppLogger.log('⚠️ CloudflareR2Service: Cloudflare upload failed, trying Backend Fallback... ($e)');
      try {
        return await uploadImageToBackend(imageFile);
      } catch (fallbackError) {
        AppLogger.log('❌ CloudflareR2Service: Both Cloudflare and Backend upload failed!');
        throw Exception('Error uploading image: $fallbackError');
      }
    }
  }

  /// NEW: Direct upload to your Node.js backend (Bypasses Worker & Cloudflare)
  Future<String> uploadImageToBackend(File imageFile) async {
    try {
      AppLogger.log('🔍 CloudflareR2Service: Uploading image DIRECTLY to backend...');
      final userData = await authService.getUserData();
      final token = userData?['token'];
      
      // Use standard multipart upload (Dio compatible)
      final response = await httpClientService.postMultipart(
        '${NetworkHelper.apiBaseUrl}/ads/upload-manual',
        files: [
          MapEntry('media', await dio.MultipartFile.fromFile(imageFile.path)),
        ],
        fields: {}, 
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = response.data is String ? json.decode(response.data) : response.data;
        final url = data['publicUrl'] ?? data['url'];
        AppLogger.log('✅ CloudflareR2Service: Image uploaded directly to backend: $url');
        return url;
      } else {
        throw Exception('Backend upload failed: ${response.statusCode} - ${response.data}');
      }
    } catch (e) {
      AppLogger.log('❌ CloudflareR2Service: Error in backend upload: $e');
      rethrow;
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
      final fileName = p.basename(videoFile.path).toLowerCase();
      final targetFolder = folder ?? 'snehayog/videos';

      AppLogger.log('🔍 CloudflareR2Service: Getting signed URL for video...');
      final uploadData = await _getUploadUrl(fileName, targetFolder);
      final uploadUrl = uploadData['uploadUrl'];
      final r2Key = uploadData['key'];

      AppLogger.log('🔍 CloudflareR2Service: Uploading video to R2...');
      final mimeType = _getMimeType(videoFile.path);
      await _binaryPutUpload(uploadUrl, videoFile, mimeType);

      AppLogger.log('🔍 CloudflareR2Service: Registering upload with backend...');
      final authService = AuthService();
      final userData = await authService.getUserData();
      
      final response = await httpClientService.post(
        Uri.parse('${NetworkHelper.apiBaseUrl}/videos/register-upload'),
        headers: {
          'Authorization': 'Bearer ${userData!['token']}',
          'Content-Type': 'application/json',
        },
        body: {
          'videoName': videoName ?? fileName,
          'description': description ?? '',
          'r2Key': r2Key,
          'videoType': profile.contains('portrait') ? 'yog' : 'vayu',
          'mimeType': 'video/mp4', // Fallback
        },
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


