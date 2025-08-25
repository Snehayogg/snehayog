import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/model/usermodel.dart';

class UserService {
  final AuthService _authService = AuthService();

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
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final response = await http.get(
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
        print('Failed to check follow status. Status: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('Error checking follow status: $e');
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

  /// Get user data including follower counts
  Future<UserModel?> getUserData(String userId) async {
    try {
      print('🔍 UserService: Getting user data for userId: $userId');
      print('🔍 UserService: userId type: ${userId.runtimeType}');
      print('🔍 UserService: userId length: ${userId.length}');

      final token = (await _authService.getUserData())?['token'];
      print('🔍 UserService: Token retrieved: ${token != null ? 'Yes' : 'No'}');
      if (token != null) {
        print(
            '🔍 UserService: Token (first 20 chars): ${token.substring(0, 20)}...');
        print('🔍 UserService: Token length: ${token.length}');
      }

      if (token == null) {
        throw Exception('Not authenticated');
      }

      final url = '${VideoService.baseUrl}/api/users/$userId';
      print('🔍 UserService: Making request to: $url');
      print(
          '🔍 UserService: Headers: Authorization: Bearer ${token.substring(0, 20)}...');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      print('🔍 UserService: Response status: ${response.statusCode}');
      print('🔍 UserService: Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Also check follow status for current user
        bool isFollowing = false;
        try {
          isFollowing = await isFollowingUser(userId);
        } catch (e) {
          print('Error checking follow status: $e');
        }

        // Create UserModel with all available data
        return UserModel(
          id: data['_id'] ?? data['id'] ?? data['googleId'] ?? '',
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
        print('Failed to load user data. Status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Error getting user data: $e');
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
      print('Error checking follow status: $e');
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
