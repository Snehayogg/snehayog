import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/config/app_config.dart';

class ReportService {
  final AuthService _authService = AuthService();
  static String get baseUrl => NetworkHelper.getBaseUrl();

  Future<bool> submitReport({
    required String targetType, // e.g., 'video' or 'user'
    required String targetId,
    required String reason, // e.g., 'spam', 'abuse', 'copyright'
    String? details,
  }) async {
    try {
      final token = await _authService.refreshTokenIfNeeded();
      if (token == null) {
        throw Exception('User not authenticated');
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/report'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'targetType': targetType,
          'targetId': targetId,
          'reason': reason,
          'details': details,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      }

      return false;
    } catch (e) {
      return false;
    }
  }
}
