import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:snehayog/config/app_config.dart';
import 'package:snehayog/services/authservices.dart';

class SignedUrlService {
  static final SignedUrlService _instance = SignedUrlService._internal();
  factory SignedUrlService() => _instance;
  SignedUrlService._internal();

  final AuthService _authService = AuthService();

  /// Normalize Cloudinary HLS/MP4 URLs to a canonical public_id-based URL
  String _normalizeCloudinaryUrl(String videoUrl) {
    try {
      if (!videoUrl.contains('res.cloudinary.com')) return videoUrl;
      final uri = Uri.parse(videoUrl);
      final segments = uri.pathSegments.toList();

      print('🔍 SignedUrlService: Original URL segments: $segments');

      // Find 'upload' index
      final uploadIdx = segments.indexOf('upload');
      if (uploadIdx == -1) return videoUrl;

      // **FIXED: Extract everything after 'upload' as the public_id path**
      // This handles both simple public_ids and folder-based public_ids
      final pathSegments = segments.sublist(uploadIdx + 1);
      if (pathSegments.isEmpty) return videoUrl;

      // Join all segments after 'upload' to get the full public_id path
      final fullPath = pathSegments.join('/');

      // Remove file extension to get the public_id
      final publicId = fullPath.replaceAll(
          RegExp(r'\.(m3u8|mp4)$', caseSensitive: false), '');
      print('🔍 SignedUrlService: Extracted public_id: $publicId');

      // Build clean canonical HLS URL
      const cloud = AppConfig.cloudinaryCloudName;
      final canonical =
          'https://res.cloudinary.com/$cloud/video/upload/$publicId.m3u8';
      print('🔍 SignedUrlService: Canonical URL: $canonical');
      return canonical;
    } catch (e) {
      print('❌ SignedUrlService: Error normalizing URL: $e');
      return videoUrl;
    }
  }

  /// Generate signed URL for HLS video stream
  Future<String?> generateSignedUrl(String videoUrl,
      {String quality = 'hd'}) async {
    try {
      // Skip signing for Cloudflare/R2 or already-public HLS served by our CDN/backend
      final lower = videoUrl.toLowerCase();
      final isR2 = lower.contains('r2.cloudflarestorage.com');
      final isCdn = lower.contains('cdn.snehayog.com');
      final isBackendHls = lower.contains('/hls/');
      if (isR2 || isCdn || isBackendHls) {
        print(
            '⚡ SignedUrlService: Skipping signing for Cloudflare/R2/backend HLS URL');
        return videoUrl;
      }

      final normalizedUrl = _normalizeCloudinaryUrl(videoUrl);
      print('🔐 SignedUrlService: Generating signed URL for $normalizedUrl');
      print('📊 Quality: $quality');

      // Get user authentication token
      final userData = await _authService.getUserData();
      if (userData == null) {
        print('❌ SignedUrlService: User not authenticated');
        return null;
      }

      print(
          '🌐 SignedUrlService: Making request to ${AppConfig.baseUrl}/api/videos/generate-signed-url');

      final response = await http
          .post(
        Uri.parse('${AppConfig.baseUrl}/api/videos/generate-signed-url'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${userData['token']}',
        },
        body: json.encode({
          'videoUrl': normalizedUrl,
          'quality': quality,
        }),
      )
          .timeout(
        const Duration(seconds: 5), // Shorter timeout
        onTimeout: () {
          print('⏰ SignedUrlService: Request timeout after 5 seconds');
          throw TimeoutException(
              'Signed URL request timeout', const Duration(seconds: 5));
        },
      );

      print(
          '📡 SignedUrlService: Response received - Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final signedUrl = data['signedUrl'];
          print('✅ SignedUrlService: Generated signed URL successfully');
          print('🔗 Signed URL: $signedUrl');
          return signedUrl;
        } else {
          print('❌ SignedUrlService: Backend error: ${data['error']}');
          return null;
        }
      } else {
        print('❌ SignedUrlService: HTTP error: ${response.statusCode}');
        print('📄 Response: ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ SignedUrlService: Error generating signed URL: $e');
      return null;
    }
  }

  /// Generate multiple quality signed URLs
  Future<Map<String, String?>> generateMultipleSignedUrls(
      String videoUrl) async {
    final Map<String, String?> urls = {};

    // Generate URLs for different qualities
    urls['hd'] = await generateSignedUrl(videoUrl, quality: 'hd');
    urls['sd'] = await generateSignedUrl(videoUrl, quality: 'sd');
    urls['auto'] = await generateSignedUrl(videoUrl, quality: 'auto');

    return urls;
  }

  /// Get the best available signed URL (fallback chain)
  Future<String?> getBestSignedUrl(String videoUrl) async {
    // Try HD first
    String? signedUrl = await generateSignedUrl(videoUrl, quality: 'hd');
    if (signedUrl != null) return signedUrl;

    // Try SD if HD fails
    signedUrl = await generateSignedUrl(videoUrl, quality: 'sd');
    if (signedUrl != null) return signedUrl;

    // Try auto if SD fails
    signedUrl = await generateSignedUrl(videoUrl, quality: 'auto');
    if (signedUrl != null) return signedUrl;

    // Return original URL as last resort
    print(
        '⚠️ SignedUrlService: All signed URL generation failed, using original URL');
    return videoUrl;
  }
}
