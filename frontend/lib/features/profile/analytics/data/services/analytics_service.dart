import 'dart:convert';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import '../../domain/models/analytics_models.dart';


class AnalyticsService {

  static String get baseUrl => AppConfig.baseUrl;

  Future<CreatorAnalytics> getCreatorAnalytics(String userId) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final response = await httpClientService.get(
        Uri.parse('$baseUrl/api/videos/creator/analytics/$userId'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return CreatorAnalytics.fromJson(data);
      } else {
        AppLogger.log('❌ AnalyticsService: Failed to fetch analytics: ${response.body}');
        throw Exception('Failed to fetch analytics: ${response.body}');
      }
    } catch (e) {
      AppLogger.log('❌ AnalyticsService: Error in getCreatorAnalytics: $e');
      rethrow;
    }
  }
}
