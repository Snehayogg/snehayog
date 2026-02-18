import 'package:flutter/foundation.dart';
import 'package:vayu/features/profile/data/services/user_service.dart';
import 'package:vayu/features/auth/data/services/authservices.dart';
import 'package:vayu/features/auth/data/usermodel.dart';

class UserProvider extends ChangeNotifier {
  final UserService _userService = UserService();

  // Cache for follow status to avoid repeated API calls
  final Map<String, bool> _followStatusCache = {};
  final Set<String> _loadingFollowStatus = {};

  // Cache for user data including follower counts
  final Map<String, UserModel> _userDataCache = {};
  final Set<String> _loadingUserData = {};

  // Getters
  bool isFollowingUser(String userId) {
    final normalizedId = userId.trim();
    if (normalizedId.isEmpty || normalizedId == 'unknown') return false;
    return _followStatusCache[normalizedId] ?? false;
  }

  bool isLoadingFollowStatus(String userId) {
    final normalizedId = userId.trim();
    if (normalizedId.isEmpty || normalizedId == 'unknown') return false;
    return _loadingFollowStatus.contains(normalizedId);
  }

  UserModel? getUserData(String userId) {
    final normalizedId = userId.trim();
    if (normalizedId.isEmpty || normalizedId == 'unknown') return null;
    return _userDataCache[normalizedId];
  }

  bool isLoadingUserData(String userId) {
    final normalizedId = userId.trim();
    if (normalizedId.isEmpty || normalizedId == 'unknown') return false;
    return _loadingUserData.contains(normalizedId);
  }

  /// Check if current user is following another user
  Future<bool> checkFollowStatus(String userId,
      {bool forceRefresh = false}) async {
    final normalizedId = userId.trim();
    if (normalizedId.isEmpty || normalizedId == 'unknown') {
      return false;
    }

    // Return cached value if available (unless force refresh is requested)
    if (!forceRefresh && _followStatusCache.containsKey(normalizedId)) {
      return _followStatusCache[normalizedId]!;
    }

    // Mark as loading
    _loadingFollowStatus.add(normalizedId);
    notifyListeners();

    try {
      final isFollowing = await _userService.isFollowingUser(normalizedId);
      _followStatusCache[normalizedId] = isFollowing;
      print('🔍 UserProvider: Follow status for $normalizedId is $isFollowing');
      return isFollowing;
    } catch (e) {
      print('❌ UserProvider: Error checking follow status for $normalizedId: $e');
      return false;
    } finally {
      _loadingFollowStatus.remove(normalizedId);
      notifyListeners();
    }
  }

  /// Get user data including follower counts
  Future<UserModel?> getUserDataWithFollowers(String userId) async {
    final normalizedId = userId.trim();
    if (normalizedId.isEmpty || normalizedId == 'unknown') {
      return null;
    }

    // Return cached value if available
    if (_userDataCache.containsKey(normalizedId)) {
      return _userDataCache[normalizedId];
    }

    // Mark as loading
    _loadingUserData.add(normalizedId);
    notifyListeners();

    try {
      final userData = await _userService.getUserData(normalizedId);
      if (userData != null) {
        _userDataCache[normalizedId] = userData;
      }
      return userData;
    } catch (e) {

      return null;
    } finally {
      _loadingUserData.remove(normalizedId);
      notifyListeners();
    }
  }

  /// Follow a user
  Future<bool> followUser(String userId) async {
    final normalizedId = userId.trim();
    if (normalizedId.isEmpty || normalizedId == 'unknown') {
      return false;
    }

    try {
      print('🎯 UserProvider: Calling followUser for $normalizedId');
      final success = await _userService.followUser(normalizedId);
      if (success) {
        _followStatusCache[normalizedId] = true;

        // **FIXED: Update follower count in cache optimistically**
        if (_userDataCache.containsKey(normalizedId)) {
          final currentUser = _userDataCache[normalizedId]!;
          _userDataCache[normalizedId] = currentUser.copyWith(
            followersCount: currentUser.followersCount + 1,
            isFollowing: true,
          );
        } else {
          // **NEW: If user data not in cache, fetch it to get updated follower count**
          // This ensures the follower count is accurate even if cache was empty
          Future.microtask(() async {
            try {
              await getUserDataWithFollowers(normalizedId);

            } catch (_) {}
          });
        }

        notifyListeners();
        print('✅ UserProvider: Successfully followed $normalizedId');
      } else {
        print('❌ UserProvider: Failed to follow $normalizedId (API returned false)');
      }
      return success;
    } catch (e) {
      print('❌ UserProvider: Exception during followUser for $normalizedId: $e');
      return false;
    }
  }

  /// Unfollow a user
  Future<bool> unfollowUser(String userId) async {
    final normalizedId = userId.trim();
    if (normalizedId.isEmpty || normalizedId == 'unknown') {
      return false;
    }

    try {
      print('🎯 UserProvider: Calling unfollowUser for $normalizedId');
      final success = await _userService.unfollowUser(normalizedId);
      if (success) {
        _followStatusCache[normalizedId] = false;

        // **FIXED: Update follower count in cache optimistically**
        if (_userDataCache.containsKey(normalizedId)) {
          final currentUser = _userDataCache[normalizedId]!;
          _userDataCache[normalizedId] = currentUser.copyWith(
            followersCount: (currentUser.followersCount - 1)
                .clamp(0, double.infinity)
                .toInt(),
            isFollowing: false,
          );
        } else {
          // **NEW: If user data not in cache, fetch it to get updated follower count**
          // This ensures the follower count is accurate even if cache was empty
          Future.microtask(() async {
            try {
              await getUserDataWithFollowers(normalizedId);

            } catch (_) {}
          });
        }

        notifyListeners();
        print('✅ UserProvider: Successfully unfollowed $normalizedId');
      } else {
        print('❌ UserProvider: Failed to unfollow $normalizedId (API returned false)');
      }
      return success;
    } catch (e) {
      print('❌ UserProvider: Exception during unfollowUser for $normalizedId: $e');
      return false;
    }
  }

  /// Toggle follow status
  Future<bool> toggleFollow(String userId) async {
    final normalizedId = userId.trim();
    if (normalizedId.isEmpty || normalizedId == 'unknown') {
      return false;
    }

    final isCurrentlyFollowing = isFollowingUser(normalizedId);

    if (isCurrentlyFollowing) {
      return await unfollowUser(normalizedId);
    } else {
      return await followUser(normalizedId);
    }
  }

// Add this method to your existing UserProvider class
  Future<void> refreshUserData() async {
    try {
      final authService = AuthService();
      final userData = await authService.getUserData();

      if (userData != null && userData['id'] != null) {

        await getUserDataWithFollowers(userData['id']);
      } else {

      }
    } catch (e) {

    }
  }

  /// Refresh user data for a specific user ID (forces fresh fetch by clearing cache)
  Future<void> refreshUserDataForId(String userId) async {
    try {
      final normalizedId = userId.trim();
      if (normalizedId.isEmpty || normalizedId == 'unknown') {
        return;
      }

      print('🔄 UserProvider: Refreshing user data for $normalizedId');

      // **FIXED: Clear user data cache first to force fresh data fetch**
      _userDataCache.remove(normalizedId);
      // **SYNC FIX: Don't update follow status cache from user data refresh**
      // Follow status is refreshed separately using checkFollowStatus() API endpoint
      // This prevents overwriting optimistic updates with stale backend data

      // Mark as loading
      _loadingUserData.add(normalizedId);
      notifyListeners();

      try {
        final userData = await _userService.getUserData(normalizedId);
        if (userData != null) {
          _userDataCache[normalizedId] = userData;
          print('✅ UserProvider: Successfully refreshed user data for $normalizedId');
          // **NOTE: Follow status cache is NOT updated here**
          // It's refreshed separately using checkFollowStatus() which is more reliable

        } else {
          print('⚠️ UserProvider: No user data returned for $normalizedId');
        }
      } finally {
        _loadingUserData.remove(normalizedId);
        notifyListeners();
      }
    } catch (e) {
      print('❌ UserProvider: Error refreshing user data for $userId: $e');
    }
  }

  /// Clear follow status cache
  void clearFollowCache() {
    _followStatusCache.clear();
    notifyListeners();
  }

  /// Clear specific user's follow status
  void clearUserFollowStatus(String userId) {
    final normalizedId = userId.trim();
    if (normalizedId.isEmpty || normalizedId == 'unknown') return;
    _followStatusCache.remove(normalizedId);
    notifyListeners();
  }

  /// Clear user data cache
  void clearUserDataCache() {
    _userDataCache.clear();
    notifyListeners();
  }

  /// Clear specific user's data
  void clearUserData(String userId) {
    final normalizedId = userId.trim();
    if (normalizedId.isEmpty || normalizedId == 'unknown') return;
    _userDataCache.remove(normalizedId);
    notifyListeners();
  }

  /// **FIXED: Clear all caches and state on logout**
  void clearAllCaches() {

    _followStatusCache.clear();
    _loadingFollowStatus.clear();
    _userDataCache.clear();
    _loadingUserData.clear();

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
