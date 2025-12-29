import 'dart:convert';
import 'package:vayu/core/services/http_client_service.dart';
import 'package:vayu/model/feedback_model.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/config/app_config.dart';

class FeedbackService {
  final AuthService _authService = AuthService();
  static String get baseUrl => NetworkHelper.getBaseUrl();

  /// Submit feedback to the server
  Future<bool> submitFeedback({
    required int rating,
    String? comments,
  }) async {
    try {
      // Get user data to extract email and ID
      final userData = await _authService.getUserData();
      if (userData == null) {
        throw Exception('User not authenticated');
      }

      final response = await httpClientService.post(
        Uri.parse('$baseUrl/api/feedback/submit'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'rating': rating,
          'comments': comments ?? '',
          'userEmail': userData['email'] ?? 'anonymous@example.com',
          'userId': userData['googleId'] ?? userData['id'],
        }),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        return responseData['success'] == true;
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

      final response = await httpClientService.get(
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
