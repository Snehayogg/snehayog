import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vayu/services/authservices.dart';
import 'package:vayu/services/video_service.dart';
import 'package:vayu/model/usermodel.dart';
import 'package:vayu/utils/app_logger.dart';
import 'package:vayu/core/services/http_client_service.dart';

class UserService {
  final AuthService _authService = AuthService();

  Future<Map<String, dynamic>> getUserById(String id) async {
    final token = (await _authService.getUserData())?['token'];
    if (token == null) {
      throw Exception('Not authenticated');
    }

    final response = await httpClientService.get(
      Uri.parse('${VideoService.baseUrl}/api/users/$id'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      AppLogger.log(
          'Failed to load user. Status code: ${response.statusCode}, Body: ${response.body}');
      throw Exception('Failed to load user');
    }
  }

  /// Follow a user
  Future<bool> followUser(String userIdToFollow) async {
    try {
      final token = (await _authService.getUserData())?['token'];
      AppLogger.log(
          '🔍 Follow API Debug: Token retrieved: ${token != null ? 'Yes' : 'No'}');

      if (token == null) {
        AppLogger.log('❌ Follow API Error: No authentication token found');
        throw Exception('Not authenticated');
      }

      AppLogger.log(
          '🔍 Follow API Debug: Making request to follow user: $userIdToFollow');
      AppLogger.log(
          '🔍 Follow API Debug: Using token: ${token.substring(0, 10)}...');

      final response = await httpClientService.post(
        Uri.parse('${VideoService.baseUrl}/api/users/follow'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'userIdToFollow': userIdToFollow,
        }),
      );

      AppLogger.log(
          '🔍 Follow API Debug: Response status: ${response.statusCode}');
      AppLogger.log('🔍 Follow API Debug: Response body: ${response.body}');

      if (response.statusCode == 200) {
        AppLogger.log('✅ Follow API Success: User followed successfully');
        return true;
      } else {
        AppLogger.log(
            '❌ Follow API Error: Status code ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to follow user: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.log('❌ Follow API Exception: $e');
      throw Exception('Failed to follow user: $e');
    }
  }

  /// Unfollow a user
  Future<bool> unfollowUser(String userIdToUnfollow) async {
    try {
      final token = (await _authService.getUserData())?['token'];
      AppLogger.log(
          '🔍 Unfollow API Debug: Token retrieved: ${token != null ? 'Yes' : 'No'}');

      if (token == null) {
        AppLogger.log('❌ Unfollow API Error: No authentication token found');
        throw Exception('Not authenticated');
      }

      AppLogger.log(
          '🔍 Unfollow API Debug: Making request to unfollow user: $userIdToUnfollow');

      final response = await httpClientService.post(
        Uri.parse('${VideoService.baseUrl}/api/users/unfollow'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'userIdToUnfollow': userIdToUnfollow,
        }),
      );

      AppLogger.log(
          '🔍 Unfollow API Debug: Response status: ${response.statusCode}');
      AppLogger.log('🔍 Unfollow API Debug: Response body: ${response.body}');

      if (response.statusCode == 200) {
        AppLogger.log('✅ Unfollow API Success: User unfollowed successfully');
        return true;
      } else {
        AppLogger.log(
            '❌ Unfollow API Error: Status code ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to unfollow user: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.log('❌ Unfollow API Exception: $e');
      throw Exception('Failed to unfollow user: $e');
    }
  }

  /// Check if current user is following another user
  Future<bool> isFollowingUser(String userIdToCheck) async {
    try {
      final token = (await _authService.getUserData())?['token'];
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final response = await httpClientService.get(
        Uri.parse(
            '${VideoService.baseUrl}/api/users/isfollowing/$userIdToCheck'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['isFollowing'] ?? false;
      } else {
        AppLogger.log(
            'Failed to check follow status. Status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      AppLogger.log('Error checking follow status: $e');
      return false;
    }
  }

  /// Update user profile information
  Future<bool> updateProfile({
    required String googleId,
    required String name,
    String? profilePic,
  }) async {
    final response = await httpClientService.post(
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
      AppLogger.log(
          'Failed to update profile. Status code: ${response.statusCode}, Body: ${response.body}');
      throw Exception('Failed to update profile on server');
    }
  }

  /// Get user data including follower counts
  Future<UserModel?> getUserData(String userId) async {
    try {
      AppLogger.log('🔍 UserService: Getting user data for userId: $userId');
      AppLogger.log('🔍 UserService: userId type: ${userId.runtimeType}');
      AppLogger.log('🔍 UserService: userId length: ${userId.length}');

      final token = (await _authService.getUserData())?['token'];
      AppLogger.log(
          '🔍 UserService: Token retrieved: ${token != null ? 'Yes' : 'No'}');
      if (token != null) {
        AppLogger.log(
            '🔍 UserService: Token (first 20 chars): ${token.substring(0, 20)}...');
        AppLogger.log('🔍 UserService: Token length: ${token.length}');
      }

      if (token == null) {
        throw Exception('Not authenticated');
      }

      final url = '${VideoService.baseUrl}/api/users/$userId';
      AppLogger.log('🔍 UserService: Making request to: $url');
      AppLogger.log(
          '🔍 UserService: Headers: Authorization: Bearer ${token.substring(0, 20)}...');

      final response = await httpClientService.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      AppLogger.log('🔍 UserService: Response status: ${response.statusCode}');
      AppLogger.log('🔍 UserService: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Also check follow status for current user
        bool isFollowing = false;
        try {
          isFollowing = await isFollowingUser(userId);
        } catch (e) {
          AppLogger.log('Error checking follow status: $e');
        }

        // Create UserModel with all available data
        return UserModel(
          id: data['googleId'] ?? data['id'] ?? data['_id'] ?? '',
          name: data['name'] ?? '',
          email: data['email'] ?? '',
          profilePic: data['profilePic'] ?? '',
          videos: List<String>.from(data['videos'] ?? []),
          followersCount: data['followersCount'] ?? data['followers'] ?? 0,
          followingCount: data['followingCount'] ?? data['following'] ?? 0,
          isFollowing: isFollowing,
          createdAt: data['createdAt'] != null
              ? DateTime.parse(data['createdAt'])
              : null,
          bio: data['bio'],
          location: data['location'],
        );
      } else {
        AppLogger.log(
            'Failed to load user data. Status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      AppLogger.log('Error getting user data: $e');
      return null;
    }
  }
}

/// **NEW: FollowManager for better follow state management**
class FollowManager {
  static final Map<String, bool> _followCache = {};
  static final Map<String, int> _followerCountCache = {};

  /// Check if user is following another user (with caching)
  static Future<bool> isFollowing(String userIdToCheck) async {
    // Return cached value if available
    if (_followCache.containsKey(userIdToCheck)) {
      return _followCache[userIdToCheck]!;
    }

    // Fetch from service and cache
    try {
      final userService = UserService();
      final isFollowing = await userService.isFollowingUser(userIdToCheck);
      _followCache[userIdToCheck] = isFollowing;
      return isFollowing;
    } catch (e) {
      AppLogger.log('Error checking follow status: $e');
      return false;
    }
  }

  /// Update follow status in cache
  static void updateFollowStatus(String userId, bool isFollowing) {
    _followCache[userId] = isFollowing;
  }

  /// Update follower count in cache
  static void updateFollowerCount(String userId, int count) {
    _followerCountCache[userId] = count;
  }

  /// Get cached follower count
  static int getFollowerCount(String userId) {
    return _followerCountCache[userId] ?? 0;
  }

  /// Clear cache for a specific user
  static void clearUserCache(String userId) {
    _followCache.remove(userId);
    _followerCountCache.remove(userId);
  }

  /// Clear all cache
  static void clearAllCache() {
    _followCache.clear();
    _followerCountCache.clear();
  }
}
