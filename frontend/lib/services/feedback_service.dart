import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:snehayog/model/feedback_model.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/config/app_config.dart';

class FeedbackService {
  final AuthService _authService = AuthService();
  static String get baseUrl => NetworkHelper.getBaseUrl();

  /// Submit feedback to the server
  Future<bool> submitFeedback({
    required String feedbackType,
    required String message,
    required int rating,
    String? deviceInfo,
    String? appVersion,
  }) async {
    try {
      final token = await _authService.refreshTokenIfNeeded();
      if (token == null) {
        throw Exception('User not authenticated');
      }

      final response = await http.post(
        Uri.parse('$baseUrl/api/feedback'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'feedbackType': feedbackType,
          'message': message,
          'rating': rating,
          'deviceInfo': deviceInfo,
          'appVersion': appVersion,
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        print(
            'Error submitting feedback: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      print('Error in submitFeedback: $e');
      return false;
    }
  }

  /// Get user's feedback history
  Future<List<FeedbackModel>> getFeedbackHistory() async {
    try {
      final token = await _authService.refreshTokenIfNeeded();
      if (token == null) {
        throw Exception('User not authenticated');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/api/feedback/history'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList.map((json) => FeedbackModel.fromJson(json)).toList();
      } else {
        print('Error fetching feedback history: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('Error in getFeedbackHistory: $e');
      return [];
    }
  }
}
