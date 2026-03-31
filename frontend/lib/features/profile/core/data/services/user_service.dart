import 'dart:convert';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/features/auth/data/usermodel.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/services/http_client_service.dart';

class UserService {
  final AuthService _authService = AuthService();

  // **REQUEST DEDUPLICATION: Track in-flight requests to prevent duplicate API calls**
  static final Map<String, Future<Map<String, dynamic>>> _pendingRequests = {};

  Future<Map<String, dynamic>> getUserById(String id) async {
    // **OPTIMIZATION: If a request for this user ID is already in-flight, reuse it**
    if (_pendingRequests.containsKey(id)) {
      AppLogger.log(
          '♻️ UserService: Reusing in-flight request for user: $id');
      try {
        return await _pendingRequests[id]!;
      } catch (e) {
        // If the request failed, remove it so we can retry
        _pendingRequests.remove(id);
        rethrow;
      }
    }

    // **FIXED: Make authentication optional for creator profiles**
    // Backend /api/users/:id endpoint doesn't require authentication
    final token = (await _authService.getUserData())?['token'];

    // **FIXED: Only include Authorization header if token exists**
    final headers = <String, String>{
      'Content-Type': 'application/json',
    };
    if (token != null) {
      headers['Authorization'] = 'Bearer $token';
    }

    // **DEDUPLICATION: Create and store the future before making the request**
    final requestFuture = _fetchUserById(id, headers);
    _pendingRequests[id] = requestFuture;

    try {
      final result = await requestFuture;
      // **CLEANUP: Remove from pending requests after successful completion**
      _pendingRequests.remove(id);
      return result;
    } catch (e) {
      // **CLEANUP: Remove from pending requests on error so it can be retried**
      _pendingRequests.remove(id);
      rethrow;
    }
  }

  /// **PRIVATE: Internal method to actually fetch user data from backend**
  Future<Map<String, dynamic>> _fetchUserById(
      String id, Map<String, String> headers) async {
    final response = await httpClientService.get(
      Uri.parse('${NetworkHelper.usersEndpoint}/$id'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      AppLogger.log('✅ UserService: Successfully loaded user: $id');
      return jsonDecode(response.body);
    } else if (response.statusCode == 404) {
      AppLogger.log('❌ UserService: User not found: $id');
      throw Exception('User not found');
    } else {
      AppLogger.log(
          'Failed to load user. Status code: ${response.statusCode}, Body: ${response.body}');
      throw Exception('Failed to load user (Status: ${response.statusCode})');
    }
  }

  /// Follow a user
  Future<bool> followUser(String userIdToFollow) async {
    final trimmedUserId = userIdToFollow.trim();
    if (trimmedUserId.isEmpty || trimmedUserId == 'unknown') {
      AppLogger.log('❌ Follow API Error: Invalid user ID provided');
      throw Exception('Invalid user ID');
    }

    try {
      final token = (await _authService.getUserData())?['token'];
      AppLogger.log(
          '🔍 Follow API Debug: Token retrieved: ${token != null ? 'Yes' : 'No'}');

      if (token == null) {
        AppLogger.log('❌ Follow API Error: No authentication token found');
        throw Exception('Not authenticated');
      }

      AppLogger.log(
          '🔍 Follow API Debug: Making request to follow user: $trimmedUserId');
      AppLogger.log(
          '🔍 Follow API Debug: Using token: ${token.substring(0, 10)}...');

      final response = await httpClientService.post(
        Uri.parse('${NetworkHelper.usersEndpoint}/follow'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'userIdToFollow': trimmedUserId}),
      );

      AppLogger.log(
          '🔍 Follow API Debug: Response status: ${response.statusCode}');
      AppLogger.log('🔍 Follow API Debug: Response body: ${response.body}');

      if (response.statusCode == 200) {
        AppLogger.log('✅ Follow API Success: User followed successfully');
        return true;
      } else if (response.statusCode == 400) {
        // Some backends return 400 with "Already following this user" if the
        // relationship already exists. Treat that as a logical success so the
        // UI can still move to the "Subscribed" state instead of failing.
        try {
          final body = jsonDecode(response.body);
          final errorMessage = body['error']?.toString() ?? '';
          if (errorMessage.toLowerCase().contains('already following')) {
            AppLogger.log(
                '✅ Follow API Logical Success: Already following $trimmedUserId');
            return true;
          }
        } catch (_) {
          // If parsing fails, fall through to generic error handling below.
        }

        AppLogger.log(
            '❌ Follow API Error: Status code ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to follow user: ${response.statusCode}');
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
    final trimmedUserId = userIdToUnfollow.trim();
    if (trimmedUserId.isEmpty || trimmedUserId == 'unknown') {
      AppLogger.log('❌ Unfollow API Error: Invalid user ID provided');
      throw Exception('Invalid user ID');
    }

    try {
      final token = (await _authService.getUserData())?['token'];
      AppLogger.log(
          '🔍 Unfollow API Debug: Token retrieved: ${token != null ? 'Yes' : 'No'}');

      if (token == null) {
        AppLogger.log('❌ Unfollow API Error: No authentication token found');
        throw Exception('Not authenticated');
      }

      AppLogger.log(
          '🔍 Unfollow API Debug: Making request to unfollow user: $trimmedUserId');

      final response = await httpClientService.post(
        Uri.parse('${NetworkHelper.usersEndpoint}/unfollow'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'userIdToUnfollow': trimmedUserId}),
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
    final trimmedUserId = userIdToCheck.trim();
    if (trimmedUserId.isEmpty || trimmedUserId == 'unknown') {
      return false;
    }

    try {
      final token = (await _authService.getUserData())?['token'];
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.usersEndpoint}/isfollowing/$trimmedUserId'),
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

  /// **OPTIMIZED: Batch check follow status for multiple users in 1 API call**
  Future<Map<String, bool>> batchCheckFollowStatus(List<String> userIds) async {
    if (userIds.isEmpty) return {};

    try {
      final token = (await _authService.getUserData())?['token'];
      if (token == null) return {};

      final response = await httpClientService.post(
        Uri.parse('${NetworkHelper.usersEndpoint}/isfollowing/batch'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'userIds': userIds}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final statuses = data['statuses'] as Map<String, dynamic>? ?? {};
        return statuses.map((key, value) => MapEntry(key, value as bool));
      }

      return {};
    } catch (e) {
      AppLogger.log('❌ Error batch checking follow status: $e');
      return {};
    }
  }

  /// Update user profile information
  Future<bool> updateProfile({
    required String googleId,
    required String name,
    String? profilePic,
    String? websiteUrl,
  }) async {
    final response = await httpClientService.post(
      Uri.parse('${NetworkHelper.usersEndpoint}/update-profile'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'googleId': googleId,
        'name': name,
        if (profilePic != null) 'profilePic': profilePic,
        if (websiteUrl != null) 'websiteUrl': websiteUrl,
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

      final url = '${NetworkHelper.usersEndpoint}/$userId';
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
          websiteUrl: data['websiteUrl']?.toString(),
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

  /// Get YouTube auth URL
  Future<String?> getYouTubeAuthUrl() async {
    try {
      final userData = await _authService.getUserData();
      final token = userData?['token'];
      if (token == null) {
        throw Exception('Not authenticated');
      }

      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.apiBaseUrl}/auth/youtube'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['authUrl'];
      } else {
        AppLogger.log(
            'Failed to get YouTube auth URL. Status: ${response.statusCode}, Body: ${response.body}');
        throw Exception('Failed to get YouTube auth URL');
      }
    } catch (e) {
      AppLogger.log('Error getting YouTube auth URL: $e');
      rethrow;
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
