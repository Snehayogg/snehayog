import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snehayog/config/app_config.dart';
import 'package:snehayog/model/feedback_model.dart';

class FeedbackService {
  static const String _baseUrl = '/api/feedback';

  // Get authorization headers
  Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('jwt_token');

    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Create new feedback
  Future<FeedbackModel> createFeedback(FeedbackCreationRequest request) async {
    try {
      print('📝 Creating feedback: ${request.title}');

      final headers = await _getHeaders();
      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}$_baseUrl'),
            headers: headers,
            body: jsonEncode(request.toJson()),
          )
          .timeout(const Duration(seconds: 30));

      print('📡 Feedback creation response: ${response.statusCode}');

      if (response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          final feedback = FeedbackModel.fromJson(responseData['data']);
          print('✅ Feedback created successfully: ${feedback.id}');
          return feedback;
        } else {
          throw Exception(
              responseData['message'] ?? 'Failed to create feedback');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to create feedback');
      }
    } catch (e) {
      print('❌ Error creating feedback: $e');
      rethrow;
    }
  }

  /// Get feedback by ID
  Future<FeedbackModel> getFeedbackById(String id) async {
    try {
      print('🔍 Getting feedback: $id');

      final headers = await _getHeaders();
      final response = await http
          .get(
            Uri.parse('${AppConfig.baseUrl}$_baseUrl/$id'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      print('📡 Get feedback response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          return FeedbackModel.fromJson(responseData['data']);
        } else {
          throw Exception(responseData['message'] ?? 'Failed to get feedback');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to get feedback');
      }
    } catch (e) {
      print('❌ Error getting feedback: $e');
      rethrow;
    }
  }

  /// Get feedback list with filters and pagination
  Future<Map<String, dynamic>> getFeedbackList({
    int page = 1,
    int limit = 10,
    String? status,
    String? type,
    String? category,
    String? priority,
    String? user,
    DateTime? dateFrom,
    DateTime? dateTo,
    String? sortBy,
    String? sortOrder,
  }) async {
    try {
      print('📋 Getting feedback list (page: $page, limit: $limit)');

      final headers = await _getHeaders();
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        if (status != null) 'status': status,
        if (type != null) 'type': type,
        if (category != null) 'category': category,
        if (priority != null) 'priority': priority,
        if (user != null) 'user': user,
        if (dateFrom != null) 'dateFrom': dateFrom.toIso8601String(),
        if (dateTo != null) 'dateTo': dateTo.toIso8601String(),
        if (sortBy != null) 'sortBy': sortBy,
        if (sortOrder != null) 'sortOrder': sortOrder,
      };

      final uri = Uri.parse('${AppConfig.baseUrl}$_baseUrl').replace(
        queryParameters: queryParams,
      );

      final response = await http
          .get(
            uri,
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      print('📡 Get feedback list response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          final feedbackList = (responseData['data'] as List)
              .map((item) => FeedbackModel.fromJson(item))
              .toList();

          return {
            'feedback': feedbackList,
            'pagination': responseData['pagination'],
          };
        } else {
          throw Exception(
              responseData['message'] ?? 'Failed to get feedback list');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to get feedback list');
      }
    } catch (e) {
      print('❌ Error getting feedback list: $e');
      rethrow;
    }
  }

  /// Get user's feedback history
  Future<List<FeedbackModel>> getUserFeedback(String userId,
      {int limit = 10}) async {
    try {
      print('👤 Getting feedback for user: $userId');

      final headers = await _getHeaders();
      final response = await http
          .get(
            Uri.parse(
                '${AppConfig.baseUrl}$_baseUrl/user/$userId?limit=$limit'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      print('📡 Get user feedback response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          return (responseData['data'] as List)
              .map((item) => FeedbackModel.fromJson(item))
              .toList();
        } else {
          throw Exception(
              responseData['message'] ?? 'Failed to get user feedback');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to get user feedback');
      }
    } catch (e) {
      print('❌ Error getting user feedback: $e');
      rethrow;
    }
  }

  /// Search feedback
  Future<List<FeedbackModel>> searchFeedback(
    String query, {
    String? status,
    String? type,
  }) async {
    try {
      print('🔍 Searching feedback: $query');

      final headers = await _getHeaders();
      final queryParams = <String, String>{
        'q': query,
        if (status != null) 'status': status,
        if (type != null) 'type': type,
      };

      final uri = Uri.parse('${AppConfig.baseUrl}$_baseUrl/search').replace(
        queryParameters: queryParams,
      );

      final response = await http
          .get(
            uri,
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      print('📡 Search feedback response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          return (responseData['data'] as List)
              .map((item) => FeedbackModel.fromJson(item))
              .toList();
        } else {
          throw Exception(
              responseData['message'] ?? 'Failed to search feedback');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to search feedback');
      }
    } catch (e) {
      print('❌ Error searching feedback: $e');
      rethrow;
    }
  }

  /// Update feedback status (Admin only)
  Future<FeedbackModel> updateFeedbackStatus(
    String id,
    String status, {
    String? adminNotes,
    String? assignedTo,
  }) async {
    try {
      print('📝 Updating feedback status: $id -> $status');

      final headers = await _getHeaders();
      final body = {
        'status': status,
        if (adminNotes != null) 'adminNotes': adminNotes,
        if (assignedTo != null) 'assignedTo': assignedTo,
      };

      final response = await http
          .patch(
            Uri.parse('${AppConfig.baseUrl}$_baseUrl/$id/status'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));

      print('📡 Update feedback status response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          return FeedbackModel.fromJson(responseData['data']);
        } else {
          throw Exception(
              responseData['message'] ?? 'Failed to update feedback status');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(
            errorData['message'] ?? 'Failed to update feedback status');
      }
    } catch (e) {
      print('❌ Error updating feedback status: $e');
      rethrow;
    }
  }

  /// Get feedback statistics (Admin only)
  Future<FeedbackStats> getFeedbackStats() async {
    try {
      print('📊 Getting feedback statistics');

      final headers = await _getHeaders();
      final response = await http
          .get(
            Uri.parse('${AppConfig.baseUrl}$_baseUrl/stats/overview'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      print('📡 Get feedback stats response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          return FeedbackStats.fromJson(responseData['data']);
        } else {
          throw Exception(
              responseData['message'] ?? 'Failed to get feedback stats');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to get feedback stats');
      }
    } catch (e) {
      print('❌ Error getting feedback stats: $e');
      rethrow;
    }
  }

  /// Delete feedback (Admin only)
  Future<void> deleteFeedback(String id) async {
    try {
      print('🗑️ Deleting feedback: $id');

      final headers = await _getHeaders();
      final response = await http
          .delete(
            Uri.parse('${AppConfig.baseUrl}$_baseUrl/$id'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 15));

      print('📡 Delete feedback response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        if (responseData['success'] == true) {
          print('✅ Feedback deleted successfully');
        } else {
          throw Exception(
              responseData['message'] ?? 'Failed to delete feedback');
        }
      } else {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to delete feedback');
      }
    } catch (e) {
      print('❌ Error deleting feedback: $e');
      rethrow;
    }
  }
}
