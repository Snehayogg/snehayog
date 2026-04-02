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
      if (token == null) throw Exception('Not authenticated');

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

  Future<List<RemovedVideo>> getRemovedVideos() async {
    try {
      final token = await AuthService.getToken();
      if (token == null) throw Exception('Not authenticated');

      final response = await httpClientService.get(
        Uri.parse('$baseUrl/api/videos/removed'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final List<RemovedVideo> result = [];
        for (var v in data) {
          try {
            result.add(RemovedVideo.fromJson(v));
          } catch (e) {
            AppLogger.log('❌ AnalyticsService: JSON Parsing Error: $e');
            AppLogger.log('❌ Raw Item: $v');
          }
        }
        return result;
      } else {
        AppLogger.log('❌ AnalyticsService: Server Error ${response.statusCode}: ${response.body}');
        return [];
      }
    } catch (e) {
      AppLogger.log('❌ AnalyticsService: Error in getRemovedVideos: $e');
      return [];
    }
  }
}
