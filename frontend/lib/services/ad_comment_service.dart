import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:snehayog/config/app_config.dart';
import 'package:snehayog/services/authservices.dart';

class AdCommentService {
  final String _baseUrl = AppConfig.baseUrl;
  final AuthService _authService = AuthService();

  /// **GET AD COMMENTS: Fetch comments for a specific ad**
  Future<Map<String, dynamic>> getAdComments({
    required String adId,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final token = await _getUserToken();
      if (token == null) {
        throw Exception('User not authenticated');
      }

      final response = await http.get(
        Uri.parse('$_baseUrl/api/ads/comments/$adId?page=$page&limit=$limit'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to fetch ad comments');
      }
    } catch (e) {
      print('❌ Error fetching ad comments: $e');
      rethrow;
    }
  }

  /// **POST AD COMMENT: Add comment to an ad**
  Future<Map<String, dynamic>> addAdComment({
    required String adId,
    required String content,
  }) async {
    try {
      final token = await _getUserToken();
      if (token == null) {
        throw Exception('User not authenticated');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/ads/comments/$adId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: json.encode({
          'content': content,
        }),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        return data;
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to add comment');
      }
    } catch (e) {
      print('❌ Error adding ad comment: $e');
      rethrow;
    }
  }

  /// **DELETE AD COMMENT: Delete a comment**
  Future<Map<String, dynamic>> deleteAdComment({
    required String adId,
    required String commentId,
  }) async {
    try {
      final token = await _getUserToken();
      if (token == null) {
        throw Exception('User not authenticated');
      }

      final response = await http.delete(
        Uri.parse('$_baseUrl/api/ads/comments/$adId/$commentId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to delete comment');
      }
    } catch (e) {
      print('❌ Error deleting ad comment: $e');
      rethrow;
    }
  }

  /// **LIKE AD COMMENT: Like/unlike a comment**
  Future<Map<String, dynamic>> likeAdComment({
    required String adId,
    required String commentId,
  }) async {
    try {
      final token = await _getUserToken();
      if (token == null) {
        throw Exception('User not authenticated');
      }

      final response = await http.post(
        Uri.parse('$_baseUrl/api/ads/comments/$adId/$commentId/like'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data;
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to like comment');
      }
    } catch (e) {
      print('❌ Error liking ad comment: $e');
      rethrow;
    }
  }

  /// **GET USER TOKEN: Helper method for authentication**
  Future<String?> _getUserToken() async {
    try {
      final userData = await _authService.getUserData();
      return userData?['token']?.toString();
    } catch (e) {
      print('❌ Error getting user token: $e');
      return null;
    }
  }
}
