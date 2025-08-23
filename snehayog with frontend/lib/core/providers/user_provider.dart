import 'package:flutter/foundation.dart';
import 'package:snehayog/services/user_service.dart';
import 'package:snehayog/model/usermodel.dart';

class UserProvider extends ChangeNotifier {
  final UserService _userService = UserService();

  // Cache for follow status to avoid repeated API calls
  final Map<String, bool> _followStatusCache = {};
  final Set<String> _loadingFollowStatus = {};
  
  // Cache for user data including follower counts
  final Map<String, UserModel> _userDataCache = {};
  final Set<String> _loadingUserData = {};

  // Getters
  bool isFollowingUser(String userId) => _followStatusCache[userId] ?? false;
  bool isLoadingFollowStatus(String userId) =>
      _loadingFollowStatus.contains(userId);
      
  UserModel? getUserData(String userId) => _userDataCache[userId];
  bool isLoadingUserData(String userId) => _loadingUserData.contains(userId);

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

  /// Get user data including follower counts
  Future<UserModel?> getUserDataWithFollowers(String userId) async {
    // Return cached value if available
    if (_userDataCache.containsKey(userId)) {
      return _userDataCache[userId];
    }

    // Mark as loading
    _loadingUserData.add(userId);
    notifyListeners();

    try {
      final userData = await _userService.getUserData(userId);
      if (userData != null) {
        _userDataCache[userId] = userData;
      }
      return userData;
    } catch (e) {
      print('Error getting user data: $e');
      return null;
    } finally {
      _loadingUserData.remove(userId);
      notifyListeners();
    }
  }

  /// Follow a user
  Future<bool> followUser(String userId) async {
    try {
      final success = await _userService.followUser(userId);
      if (success) {
        _followStatusCache[userId] = true;
        
        // Update follower count in cache
        if (_userDataCache.containsKey(userId)) {
          final currentUser = _userDataCache[userId]!;
          _userDataCache[userId] = currentUser.copyWith(
            followersCount: currentUser.followersCount + 1,
            isFollowing: true,
          );
        }
        
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
        
        // Update follower count in cache
        if (_userDataCache.containsKey(userId)) {
          final currentUser = _userDataCache[userId]!;
          _userDataCache[userId] = currentUser.copyWith(
            followersCount: (currentUser.followersCount - 1).clamp(0, double.infinity).toInt(),
            isFollowing: false,
          );
        }
        
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

  /// Refresh user data (useful for profile screen updates)
  Future<void> refreshUserData(String userId) async {
    _userDataCache.remove(userId);
    _followStatusCache.remove(userId);
    await getUserDataWithFollowers(userId);
    await checkFollowStatus(userId);
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

  /// Clear user data cache
  void clearUserDataCache() {
    _userDataCache.clear();
    notifyListeners();
  }

  /// Clear specific user's data
  void clearUserData(String userId) {
    _userDataCache.remove(userId);
    notifyListeners();
  }

  @override
  void dispose() {
    _followStatusCache.clear();
    _loadingFollowStatus.clear();
    _userDataCache.clear();
    _loadingUserData.clear();
    super.dispose();
  }
}
