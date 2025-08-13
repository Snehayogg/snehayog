import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:snehayog/services/google_auth_service.dart';
import 'package:snehayog/services/video_service.dart';

class UserService {
  final GoogleAuthService _authService = GoogleAuthService();

  Future<Map<String, dynamic>> getUserById(String id) async {
    final token = (await _authService.getUserData())?['token'];
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final response = await http.get(
      Uri.parse('${VideoService.baseUrl}/api/users/$id'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      print(
          'Failed to load user. Status code: ${response.statusCode}, Body: ${response.body}');
      throw Exception('Failed to load user');
    }
  }

  /// Follow a user
  Future<bool> followUser(String userIdToFollow) async {
    try {
      final token = (await _authService.getUserData())?['token'];
      print(
          '🔍 Follow API Debug: Token retrieved: ${token != null ? 'Yes' : 'No'}');

      if (token == null) {
        print('❌ Follow API Error: No authentication token found');
        throw Exception('Not authenticated');
      }

      print(
          '🔍 Follow API Debug: Making request to follow user: $userIdToFollow');
      print('🔍 Follow API Debug: Using token: ${token.substring(0, 10)}...');

      final response = await http.post(
        Uri.parse('${VideoService.baseUrl}/api/users/follow'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'userIdToFollow': userIdToFollow,
        }),
      );

      print('🔍 Follow API Debug: Response status: ${response.statusCode}');
      print('🔍 Follow API Debug: Response body: ${response.body}');

      if (response.statusCode == 200) {
        print('✅ Follow API Success: User followed successfully');
        return true;
      } else {
        print(
            '❌ Follow API Error: Status code ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to follow user: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Follow API Exception: $e');
      throw Exception('Failed to follow user: $e');
    }
  }

  /// Unfollow a user
  Future<bool> unfollowUser(String userIdToUnfollow) async {
    try {
      final token = (await _authService.getUserData())?['token'];
      print(
          '🔍 Unfollow API Debug: Token retrieved: ${token != null ? 'Yes' : 'No'}');

      if (token == null) {
        print('❌ Unfollow API Error: No authentication token found');
        throw Exception('Not authenticated');
      }

      print(
          '🔍 Unfollow API Debug: Making request to unfollow user: $userIdToUnfollow');

      final response = await http.post(
        Uri.parse('${VideoService.baseUrl}/api/users/unfollow'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'userIdToUnfollow': userIdToUnfollow,
        }),
      );

      print('🔍 Unfollow API Debug: Response status: ${response.statusCode}');
      print('🔍 Unfollow API Debug: Response body: ${response.body}');

      if (response.statusCode == 200) {
        print('✅ Unfollow API Success: User unfollowed successfully');
        return true;
      } else {
        print(
            '❌ Unfollow API Error: Status code ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to unfollow user: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Unfollow API Exception: $e');
      throw Exception('Failed to unfollow user: $e');
    }
  }

  /// Check if current user is following another user
  Future<bool> isFollowingUser(String userIdToCheck) async {
    try {
      final token = (await _authService.getUserData())?['token'];
      print(
          '🔍 IsFollowing API Debug: Token retrieved: ${token != null ? 'Yes' : 'No'}');

      if (token == null) {
        print('❌ IsFollowing API Error: No authentication token found');
        return false;
      }

      print(
          '🔍 IsFollowing API Debug: Checking if following user: $userIdToCheck');

      final response = await http.get(
        Uri.parse(
            '${VideoService.baseUrl}/api/users/isfollowing/$userIdToCheck'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print(
          '🔍 IsFollowing API Debug: Response status: ${response.statusCode}');
      print('🔍 IsFollowing API Debug: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final isFollowing = data['isFollowing'] ?? false;
        print('🔍 IsFollowing API Debug: Result: $isFollowing');
        return isFollowing;
      } else {
        print(
            '❌ IsFollowing API Error: Status code ${response.statusCode}, Body: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ IsFollowing API Exception: $e');
      return false;
    }
  }

  /// Update user profile information
  Future<bool> updateProfile({
    required String googleId,
    required String name,
    String? profilePic,
  }) async {
    final response = await http.post(
      Uri.parse('${VideoService.baseUrl}/api/users/update-profile'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'googleId': googleId,
        'name': name,
        if (profilePic != null) 'profilePic': profilePic,
      }),
    );

    if (response.statusCode == 200) {
      return true;
    } else {
      print(
          'Failed to update profile. Status code: ${response.statusCode}, Body: ${response.body}');
      throw Exception('Failed to update profile on server');
    }
  }
}
