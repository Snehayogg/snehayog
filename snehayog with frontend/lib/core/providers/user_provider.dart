import 'package:flutter/foundation.dart';
import 'package:snehayog/services/user_service.dart';

class UserProvider extends ChangeNotifier {
  final UserService _userService = UserService();

  // Cache for follow status to avoid repeated API calls
  final Map<String, bool> _followStatusCache = {};
  final Set<String> _loadingFollowStatus = {};

  // Getters
  bool isFollowingUser(String userId) => _followStatusCache[userId] ?? false;
  bool isLoadingFollowStatus(String userId) =>
      _loadingFollowStatus.contains(userId);

  /// Check if current user is following another user
  Future<bool> checkFollowStatus(String userId) async {
    // Return cached value if available
    if (_followStatusCache.containsKey(userId)) {
      return _followStatusCache[userId]!;
    }

    // Mark as loading
    _loadingFollowStatus.add(userId);
    notifyListeners();

    try {
      final isFollowing = await _userService.isFollowingUser(userId);
      _followStatusCache[userId] = isFollowing;
      return isFollowing;
    } catch (e) {
      print('Error checking follow status: $e');
      return false;
    } finally {
      _loadingFollowStatus.remove(userId);
      notifyListeners();
    }
  }

  /// Follow a user
  Future<bool> followUser(String userId) async {
    try {
      final success = await _userService.followUser(userId);
      if (success) {
        _followStatusCache[userId] = true;
        notifyListeners();
      }
      return success;
    } catch (e) {
      print('Error following user: $e');
      return false;
    }
  }

  /// Unfollow a user
  Future<bool> unfollowUser(String userId) async {
    try {
      final success = await _userService.unfollowUser(userId);
      if (success) {
        _followStatusCache[userId] = false;
        notifyListeners();
      }
      return success;
    } catch (e) {
      print('Error unfollowing user: $e');
      return false;
    }
  }

  /// Toggle follow status
  Future<bool> toggleFollow(String userId) async {
    final isCurrentlyFollowing = isFollowingUser(userId);

    if (isCurrentlyFollowing) {
      return await unfollowUser(userId);
    } else {
      return await followUser(userId);
    }
  }

  /// Clear follow status cache
  void clearFollowCache() {
    _followStatusCache.clear();
    notifyListeners();
  }

  /// Clear specific user's follow status
  void clearUserFollowStatus(String userId) {
    _followStatusCache.remove(userId);
    notifyListeners();
  }

  @override
  void dispose() {
    _followStatusCache.clear();
    _loadingFollowStatus.clear();
    super.dispose();
  }
}
