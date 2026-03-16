import 'dart:convert';
import 'dart:async';
import 'package:vayu/shared/services/http_client_service.dart';
import 'package:vayu/shared/config/app_config.dart';
import 'package:vayu/features/auth/data/services/authservices.dart';

class SignedUrlService {
  static final SignedUrlService _instance = SignedUrlService._internal();
  factory SignedUrlService() => _instance;
  SignedUrlService._internal();

  final AuthService _authService = AuthService();

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
        return videoUrl;
      }

      // Get user authentication token
      final userData = await _authService.getUserData();
      if (userData == null) {
        print('❌ SignedUrlService: User not authenticated');
        return null;
      }

      print(
          '🌐 SignedUrlService: Making request to ${AppConfig.baseUrl}/api/videos/generate-signed-url');

      final response = await httpClientService.post(
        Uri.parse('${NetworkHelper.apiBaseUrl}/videos/generate-signed-url'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${userData['token']}',
        },
        body: json.encode({
          'videoUrl': videoUrl,
          'quality': quality,
        }),
        timeout: const Duration(seconds: 5), // Shorter timeout
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
          return null;
        }
      } else {
        return null;
      }
    } catch (e) {
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
    return videoUrl;
  }
}
