import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vayu/services/authservices.dart';
import 'package:vayu/config/app_config.dart';
import 'package:vayu/utils/app_logger.dart';

class ReportService {
  final AuthService _authService = AuthService();

  Future<bool> submitReport({
    required String targetType, // e.g., 'video' or 'user'
    required String targetId,
    required String reason, // e.g., 'spam', 'abuse', 'copyright'
    String? details,
  }) async {
    try {
      // Get base URL with fallback (async)
      final baseUrl = await AppConfig.getBaseUrlWithFallback();

      // Try to get token, but don't fail if user is not authenticated (reports can be anonymous)
      String? token;
      try {
        token = await _authService.refreshTokenIfNeeded();
      } catch (e) {
        AppLogger.log(
            '⚠️ ReportService: User not authenticated, submitting anonymous report');
      }

      final headers = <String, String>{
        'Content-Type': 'application/json',
      };

      // Add auth header only if token is available
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      AppLogger.log(
          '📡 ReportService: Submitting report - targetType: $targetType, targetId: $targetId, reason: $reason');
      AppLogger.log('📡 ReportService: URL: $baseUrl/api/report');

      final response = await http
          .post(
        Uri.parse('$baseUrl/api/report'),
        headers: headers,
        body: jsonEncode({
          'targetType': targetType,
          'targetId': targetId,
          'reason': reason,
          'details': details,
        }),
      )
          .timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw Exception('Request timed out');
        },
      );

      AppLogger.log(
          '📡 ReportService: Response status: ${response.statusCode}');
      AppLogger.log('📡 ReportService: Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        AppLogger.log('✅ ReportService: Report submitted successfully');
        return true;
      }

      // Log error response
      try {
        final errorData = json.decode(response.body);
        AppLogger.log('❌ ReportService: Error response: $errorData');
      } catch (_) {
        AppLogger.log(
            '❌ ReportService: Error response (not JSON): ${response.body}');
      }

      return false;
    } catch (e) {
      AppLogger.log('❌ ReportService: Exception submitting report: $e');
      return false;
    }
  }
}
