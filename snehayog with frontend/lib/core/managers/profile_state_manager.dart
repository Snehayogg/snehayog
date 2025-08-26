import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/services/user_service.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/core/constants/profile_constants.dart';
import 'package:snehayog/core/providers/video_provider.dart';
import 'package:snehayog/utils/feature_flags.dart';

class ProfileStateManager extends ChangeNotifier {
  final VideoService _videoService = VideoService();
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();

  // BuildContext to access VideoProvider
  BuildContext? _context;

  // Set context when needed
  void setContext(BuildContext context) {
    _context = context;
  }

  // State variables
  List<VideoModel> _userVideos = [];
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _userData;
  bool _isEditing = false;
  bool _isSelecting = false;
  final Set<String> _selectedVideoIds = {};

  // Controllers
  final TextEditingController nameController = TextEditingController();

  // Instagram-like caching
  final Map<String, dynamic> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Map<String, String> _cacheEtags = {};

  // Cache configuration
  static const Duration _userProfileCacheTime = Duration(hours: 24);
  static const Duration _userVideosCacheTime = Duration(minutes: 15);
  static const Duration _staleWhileRevalidateTime = Duration(minutes: 5);

  // Getters
  List<VideoModel> get userVideos => _userVideos;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, dynamic>? get userData => _userData;
  bool get isEditing => _isEditing;
  bool get isSelecting => _isSelecting;
  Set<String> get selectedVideoIds => _selectedVideoIds;
  bool get hasSelectedVideos => _selectedVideoIds.isNotEmpty;

  // Profile management
  Future<void> loadUserData(String? userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      print('🔄 ProfileStateManager: Loading user data for userId: $userId');

      // **OPTIMIZED: Check cache first for instant response**
      final cacheKey = 'user_profile_$userId';
      final cachedProfile = _getFromCache(cacheKey);

      if (cachedProfile != null &&
          !_isCacheStale(cacheKey, _userProfileCacheTime)) {
        print('⚡ ProfileStateManager: Cache hit for profile data');
        _userData = cachedProfile;
        _isLoading = false;
        notifyListeners();

        // Load videos in background
        loadUserVideos(userId).catchError((e) {
          print('⚠️ Background video load failed: $e');
        });
        return;
      }

      final loggedInUser = await _authService.getUserData();
      print('🔄 ProfileStateManager: Logged in user: ${loggedInUser?['id']}');

      // Check if we have any authentication data
      if (loggedInUser == null) {
        print('❌ ProfileStateManager: No authentication data available');
        _isLoading = false;
        _error = 'No authentication data available. Please sign in.';
        notifyListeners();
        return;
      }

      final bool isMyProfile = userId == null ||
          userId == loggedInUser['id'] ||
          userId == loggedInUser['googleId'];
      print('🔄 ProfileStateManager: Is my profile: $isMyProfile');

      Map<String, dynamic>? userData;
      if (isMyProfile) {
        // Load own profile data
        userData = loggedInUser;
        // Load saved profile data for the logged-in user
        final savedName = await _loadSavedName();
        final savedProfilePic = await _loadSavedProfilePic();
        userData['name'] = savedName ?? userData['name'];
        userData['profilePic'] = savedProfilePic ?? userData['profilePic'];
        print(
            '🔄 ProfileStateManager: Loaded own profile data: ${userData['name']}');
      } else {
        // Fetch profile data for another user
        print(
            '🔄 ProfileStateManager: Fetching other user profile for ID: $userId');
        userData = await _userService.getUserById(userId);
        print(
            '🔄 ProfileStateManager: Other user profile loaded: ${userData['name']}');
      }

      // **OPTIMIZED: Cache the profile data**
      _setCache(cacheKey, userData, _userProfileCacheTime);

      _userData = userData;
      print('🔄 ProfileStateManager: Stored user data: $_userData');
      print(
          '🔄 ProfileStateManager: Stored user googleId: ${_userData?['googleId']}');
      print('🔄 ProfileStateManager: Stored user id: ${_userData?['id']}');

      _isLoading = false;
      notifyListeners();
      print(
          '🔄 ProfileStateManager: User data loaded successfully, now loading videos');

      // **OPTIMIZED: Load videos in parallel with profile data**
      loadUserVideos(userId).catchError((e) {
        print('⚠️ Background video load failed: $e');
      });
    } catch (e) {
      print('❌ ProfileStateManager: Error loading user data: $e');
      _error = 'Error loading user data: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadUserVideos(String? userId) async {
    if (Features.smartVideoCaching.isEnabled) {
      await _loadUserVideosWithCaching(userId);
    } else {
      await _loadUserVideosDirect(userId);
    }
  }

  /// Load user videos with Instagram-like caching strategy
  Future<void> _loadUserVideosWithCaching(String? userId) async {
    try {
      print(
          '🔄 ProfileStateManager: Loading videos with Instagram-like caching for userId: $userId');

      final loggedInUser = await _authService.getUserData();
      final bool isMyProfile = userId == null ||
          userId == loggedInUser?['id'] ||
          userId == loggedInUser?['googleId'];

      String targetUserId;
      if (isMyProfile) {
        targetUserId = loggedInUser?['googleId'] ?? loggedInUser?['id'] ?? '';
      } else {
        targetUserId = userId ?? '';
      }

      if (targetUserId.isNotEmpty) {
        // Check cache first
        final cacheKey = 'user_videos_$targetUserId';
        final cachedData = _getFromCache(cacheKey);

        if (cachedData != null) {
          // Return cached data instantly
          _userVideos = List<VideoModel>.from(cachedData);
          print(
              '⚡ ProfileStateManager: Instant cache hit for videos: ${_userVideos.length} videos');
          notifyListeners();

          // Start background refresh if data is stale
          if (_isCacheStale(cacheKey, _userVideosCacheTime)) {
            _scheduleBackgroundRefresh(
                cacheKey, () => _fetchVideosFromServer(targetUserId));
          }
        } else {
          // Cache miss - fetch from server
          await _fetchAndCacheVideos(targetUserId, cacheKey);
        }
      } else {
        _userVideos = [];
        notifyListeners();
      }
    } catch (e) {
      print('❌ ProfileStateManager: Error in cached video loading: $e');
      // Fallback to direct loading
      await _loadUserVideosDirect(userId);
    }
  }

  /// Load user videos directly without caching (fallback)
  Future<void> _loadUserVideosDirect(String? userId) async {
    try {
      print(
          '🔄 ProfileStateManager: Loading videos directly for userId: $userId');

      final loggedInUser = await _authService.getUserData();
      final bool isMyProfile = userId == null ||
          userId == loggedInUser?['id'] ||
          userId == loggedInUser?['googleId'];

      String targetUserId;
      if (isMyProfile) {
        targetUserId = loggedInUser?['googleId'] ?? loggedInUser?['id'] ?? '';
      } else {
        targetUserId = userId ?? '';
      }

      if (targetUserId.isNotEmpty) {
        final videos = await _videoService.getUserVideos(targetUserId);
        _userVideos = videos;
        print('✅ ProfileStateManager: Directly loaded ${videos.length} videos');
        notifyListeners();
      } else {
        _userVideos = [];
        notifyListeners();
      }
    } catch (e) {
      print('❌ ProfileStateManager: Error in direct video loading: $e');
      _error = '${ProfileConstants.errorLoadingVideos}${e.toString()}';
      _userVideos = [];
      notifyListeners();
    }
  }

  /// Fetch videos from server and cache them
  Future<void> _fetchAndCacheVideos(String userId, String cacheKey) async {
    try {
      print(
          '📡 ProfileStateManager: Fetching videos from server for user: $userId');
      final videos = await _videoService.getUserVideos(userId);

      // Cache the videos
      _setCache(cacheKey, videos, _userVideosCacheTime);

      _userVideos = videos;
      print(
          '✅ ProfileStateManager: Fetched and cached ${videos.length} videos');
      notifyListeners();
    } catch (e) {
      print('❌ ProfileStateManager: Error fetching videos from server: $e');
      rethrow;
    }
  }

  /// Fetch videos from server (for background refresh)
  Future<List<VideoModel>> _fetchVideosFromServer(String userId) async {
    try {
      return await _videoService.getUserVideos(userId);
    } catch (e) {
      print('❌ ProfileStateManager: Error in background video fetch: $e');
      return [];
    }
  }

  // Profile editing
  void startEditing() {
    if (_userData != null) {
      _isEditing = true;
      nameController.text = _userData!['name'] ?? '';
      notifyListeners();
    }
  }

  void cancelEditing() {
    _isEditing = false;
    nameController.clear();
    notifyListeners();
  }

  Future<void> saveProfile() async {
    if (_userData != null && nameController.text.isNotEmpty) {
      try {
        final newName = nameController.text.trim();
        await _saveProfileData(newName, _userData!['profilePic']);

        _userData!['name'] = newName;
        _isEditing = false;
        notifyListeners();

        nameController.clear();
        notifyListeners();
      } catch (e) {
        _error = 'Failed to save profile: ${e.toString()}';
        notifyListeners();
      }
    }
  }

  Future<void> updateProfilePhoto(String? profilePic) async {
    if (_userData != null) {
      await _saveProfileData(_userData!['name'], profilePic);
      _userData!['profilePic'] = profilePic;
      notifyListeners();
      notifyListeners();
    }
  }

  // Video selection management
  void toggleVideoSelection(String videoId) {
    print('🔍 toggleVideoSelection called with videoId: $videoId');
    print('🔍 Current selectedVideoIds: $_selectedVideoIds');

    if (_selectedVideoIds.contains(videoId)) {
      _selectedVideoIds.remove(videoId);
      print('🔍 Removed videoId: $videoId');
    } else {
      _selectedVideoIds.add(videoId);
      print('🔍 Added videoId: $videoId');
    }

    print('🔍 Updated selectedVideoIds: $_selectedVideoIds');
    notifyListeners();
  }

  void clearSelection() {
    print('🔍 clearSelection called');
    _selectedVideoIds.clear();
    notifyListeners();
  }

  void exitSelectionMode() {
    print('🔍 exitSelectionMode called');
    _isSelecting = false;
    _selectedVideoIds.clear();
    notifyListeners();
  }

  void enterSelectionMode() {
    print('🔍 enterSelectionMode called');
    _isSelecting = true;
    notifyListeners();
  }

  Future<void> deleteSelectedVideos() async {
    if (_selectedVideoIds.isEmpty) return;

    try {
      print(
          '🗑️ ProfileStateManager: Starting deletion of ${_selectedVideoIds.length} videos');

      _isLoading = true;
      _error = null;
      notifyListeners();

      // Create a copy of selected IDs for processing
      final videoIdsToDelete = List<String>.from(_selectedVideoIds);

      // Attempt to delete videos from the backend
      final deletionSuccess =
          await _videoService.deleteVideos(videoIdsToDelete);

      if (deletionSuccess) {
        print(
            '✅ ProfileStateManager: All videos deleted successfully from backend');

        // Remove deleted videos from local list
        _userVideos.removeWhere((video) => videoIdsToDelete.contains(video.id));

        // Clear selection and exit selection mode
        exitSelectionMode();

        _isLoading = false;

        // Notify VideoProvider to update the main video feed
        if (_context != null) {
          try {
            final videoProvider =
                Provider.of<VideoProvider>(_context!, listen: false);
            videoProvider.removeVideosFromList(videoIdsToDelete);
            print(
                '✅ ProfileStateManager: Notified VideoProvider of deleted videos');
          } catch (e) {
            print('⚠️ ProfileStateManager: Could not notify VideoProvider: $e');
          }
        }

        print(
            '✅ ProfileStateManager: Local state updated after successful deletion');
      } else {
        throw Exception('Backend deletion failed');
      }
    } catch (e) {
      print('❌ ProfileStateManager: Error deleting videos: $e');

      _isLoading = false;
      _error = _getUserFriendlyErrorMessage(e);
      notifyListeners();
    }
  }

  /// Deletes a single video with enhanced error handling
  Future<bool> deleteSingleVideo(String videoId) async {
    try {
      print('🗑️ ProfileStateManager: Deleting single video: $videoId');

      _isLoading = true;
      _error = null;

      // Delete from backend
      final deletionSuccess = await _videoService.deleteVideo(videoId);

      if (deletionSuccess) {
        print('✅ ProfileStateManager: Single video deleted successfully');

        // Remove from local list
        _userVideos.removeWhere((video) => video.id == videoId);

        _isLoading = false;

        // Notify VideoProvider to update the main video feed
        if (_context != null) {
          try {
            final videoProvider =
                Provider.of<VideoProvider>(_context!, listen: false);
            videoProvider.removeVideoFromList(videoId);
            print(
                '✅ ProfileStateManager: Notified VideoProvider of deleted video');
          } catch (e) {
            print('⚠️ ProfileStateManager: Could not notify VideoProvider: $e');
          }
        }

        return true;
      } else {
        throw Exception('Backend deletion failed');
      }
    } catch (e) {
      print('❌ ProfileStateManager: Error deleting single video: $e');

      _isLoading = false;
      _error = _getUserFriendlyErrorMessage(e);
      notifyListeners();
      return false;
    }
  }

  /// Converts technical error messages to user-friendly messages
  String _getUserFriendlyErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('timeout')) {
      return 'Request timed out. Please check your connection and try again.';
    } else if (errorString.contains('network')) {
      return 'Network error. Please check your internet connection.';
    } else if (errorString.contains('unauthorized') ||
        errorString.contains('sign in')) {
      return 'Please sign in again to delete videos.';
    } else if (errorString.contains('permission') ||
        errorString.contains('forbidden')) {
      return 'You do not have permission to delete these videos.';
    } else if (errorString.contains('not found')) {
      return 'One or more videos were not found.';
    } else if (errorString.contains('conflict')) {
      return 'Videos cannot be deleted at this time. Please try again later.';
    } else {
      return 'Failed to delete videos. Please try again.';
    }
  }

  // Utility methods
  Future<String?> _loadSavedName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_name');
  }

  Future<String?> _loadSavedProfilePic() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_profile_pic');
  }

  Future<void> _saveProfileData(String name, String? profilePic) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_name', name);
    if (profilePic != null) {
      await prefs.setString('user_profile_pic', profilePic);
    }
  }

  // Custom setState method removed - use notifyListeners() directly

  // Error handling
  void clearError() {
    _error = null;
    notifyListeners();
  }

  // Authentication methods
  Future<void> handleLogout() async {
    try {
      await _authService.signOut();
      _userData = null;
      _userVideos = [];
      _isEditing = false;
      _isSelecting = false;
      _selectedVideoIds.clear();
      notifyListeners();
    } catch (e) {
      _error = 'Failed to logout: ${e.toString()}';
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>?> handleGoogleSignIn() async {
    try {
      final userData = await _authService.signInWithGoogle();
      print(
          '🔄 ProfileStateManager: Google sign-in returned user data: $userData');
      print(
          '🔄 ProfileStateManager: Google sign-in returned googleId: ${userData?['googleId']}');
      print(
          '🔄 ProfileStateManager: Google sign-in returned id: ${userData?['id']}');

      if (userData != null) {
        _userData = userData;
        _isLoading = false;
        _error = null;
        notifyListeners();
        await loadUserVideos(null); // Load videos for the signed-in user
      }
      return userData;
    } catch (e) {
      _error = 'Failed to sign in: ${e.toString()}';
      notifyListeners();
      return null;
    }
  }

  // Getter for user data
  Map<String, dynamic>? getUserData() => _userData;

  /// Refreshes user data and videos
  Future<void> refreshData() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      // Get the current user ID from userData or logged in user
      String? targetUserId;
      if (_userData != null && _userData!['googleId'] != null) {
        // **FIXED: Prioritize googleId over MongoDB _id**
        targetUserId = _userData!['googleId'];
        print(
            '🔄 ProfileStateManager: Refreshing data for user with googleId: $targetUserId');
      } else if (_userData != null && _userData!['id'] != null) {
        // Fallback to MongoDB _id if googleId not available
        targetUserId = _userData!['id'];
        print(
            '🔄 ProfileStateManager: Refreshing data for user with MongoDB _id: $targetUserId');
      } else {
        final loggedInUser = await _authService.getUserData();
        // **FIXED: Prioritize googleId over MongoDB _id**
        targetUserId = loggedInUser?['googleId'] ?? loggedInUser?['id'];
        print(
            '🔄 ProfileStateManager: Refreshing data for logged in user: $targetUserId');
      }

      // Reload user data and videos
      await loadUserData(targetUserId);

      _isLoading = false;
      notifyListeners();

      print('✅ ProfileStateManager: Data refreshed successfully');
    } catch (e) {
      _isLoading = false;
      _error = 'Failed to refresh data: ${e.toString()}';
      notifyListeners();
      print('❌ ProfileStateManager: Error refreshing data: $e');
    }
  }

  /// Force refresh videos only (for when new videos are uploaded)
  Future<void> refreshVideosOnly() async {
    try {
      print('🔄 ProfileStateManager: Force refreshing user videos...');

      // Get the current user ID from userData or logged in user
      String? targetUserId;
      if (_userData != null && _userData!['googleId'] != null) {
        targetUserId = _userData!['googleId'];
        print(
            '🔄 ProfileStateManager: Refreshing videos for user with googleId: $targetUserId');
      } else if (_userData != null && _userData!['id'] != null) {
        targetUserId = _userData!['id'];
        print(
            '🔄 ProfileStateManager: Refreshing videos for user with MongoDB _id: $targetUserId');
      } else {
        final loggedInUser = await _authService.getUserData();
        targetUserId = loggedInUser?['googleId'] ?? loggedInUser?['id'];
        print(
            '🔄 ProfileStateManager: Refreshing videos for logged in user: $targetUserId');
      }

      if (targetUserId != null && targetUserId.isNotEmpty) {
        if (Features.smartVideoCaching.isEnabled) {
          // Clear cache and reload with fresh data
          final cacheKey = 'user_videos_$targetUserId';
          _cache.remove(cacheKey);
          _cacheTimestamps.remove(cacheKey);
          _cacheEtags.remove(cacheKey);
          print('🧹 ProfileStateManager: Cleared cache for key: $cacheKey');

          // Reload with fresh data
          await _fetchAndCacheVideos(targetUserId, cacheKey);
        } else {
          // Direct refresh without caching
          final videos = await _videoService.getUserVideos(targetUserId);
          _userVideos = videos;
          notifyListeners();
          print(
              '✅ ProfileStateManager: Videos refreshed directly. Count: ${videos.length}');
        }
      } else {
        print('⚠️ ProfileStateManager: No valid user ID for video refresh');
      }
    } catch (e) {
      print('❌ ProfileStateManager: Error refreshing videos: $e');
      _error = 'Failed to refresh videos: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Add a new video to the profile (called after successful upload)
  void addNewVideo(VideoModel video) {
    print(
        '➕ ProfileStateManager: Adding new video to profile: ${video.videoName}');
    _userVideos.insert(0, video); // Add to the beginning of the list

    // Clear relevant caches when new video is added
    if (Features.smartVideoCaching.isEnabled && _userData != null) {
      final userId = _userData!['googleId'] ?? _userData!['id'];
      if (userId != null) {
        final cacheKey = 'user_videos_$userId';
        _cache.remove(cacheKey);
        _cacheTimestamps.remove(cacheKey);
        _cacheEtags.remove(cacheKey);
        print('🧹 ProfileStateManager: Cleared cache after adding new video');
      }
    }

    notifyListeners();
  }

  /// Remove a video from the profile
  void removeVideo(String videoId) {
    print('➖ ProfileStateManager: Removing video from profile: $videoId');
    _userVideos.removeWhere((video) => video.id == videoId);

    // Clear relevant caches when video is removed
    if (Features.smartVideoCaching.isEnabled && _userData != null) {
      final userId = _userData!['googleId'] ?? _userData!['id'];
      if (userId != null) {
        final cacheKey = 'user_videos_$userId';
        _cache.remove(cacheKey);
        _cacheTimestamps.remove(cacheKey);
        _cacheEtags.remove(cacheKey);
        print('🧹 ProfileStateManager: Cleared cache after removing video');
      }
    }

    notifyListeners();
  }

  // Instagram-like caching methods
  /// Get data from cache
  dynamic _getFromCache(String key) {
    if (_cache.containsKey(key) && _cacheTimestamps.containsKey(key)) {
      final timestamp = _cacheTimestamps[key]!;
      final now = DateTime.now();

      // Use appropriate cache time based on key type
      Duration cacheTime = key.contains('user_profile')
          ? _userProfileCacheTime
          : _userVideosCacheTime;

      if (now.difference(timestamp) < cacheTime) {
        print('⚡ ProfileStateManager: Cache hit for key: $key');
        return _cache[key];
      } else {
        print('🔄 ProfileStateManager: Cache expired for key: $key');
        _cache.remove(key);
        _cacheTimestamps.remove(key);
        _cacheEtags.remove(key);
      }
    }
    return null;
  }

  /// Set data in cache
  void _setCache(String key, dynamic data, Duration maxAge) {
    _cache[key] = data;
    _cacheTimestamps[key] = DateTime.now();
    print('💾 ProfileStateManager: Cached data for key: $key');
  }

  /// Check if cache is stale (can be used but should be refreshed)
  bool _isCacheStale(String key, Duration maxAge) {
    if (_cacheTimestamps.containsKey(key)) {
      final timestamp = _cacheTimestamps[key]!;
      final now = DateTime.now();
      final age = now.difference(timestamp);
      return age > maxAge * 0.8; // Refresh when 80% of max age is reached
    }
    return false;
  }

  /// Schedule background refresh for stale data
  void _scheduleBackgroundRefresh(
      String key, Future<List<VideoModel>> Function() fetchFn) {
    if (Features.backgroundVideoPreloading.isEnabled) {
      print(
          '🔄 ProfileStateManager: Scheduling background refresh for key: $key');
      unawaited(_refreshCacheInBackground(key, fetchFn));
    }
  }

  /// Refresh cache in background
  Future<void> _refreshCacheInBackground(
      String key, Future<List<VideoModel>> Function() fetchFn) async {
    try {
      await Future.delayed(
          const Duration(seconds: 2)); // Small delay to avoid blocking UI
      final freshData = await fetchFn();

      if (freshData.isNotEmpty) {
        _setCache(key, freshData, _userVideosCacheTime);
        print(
            '✅ ProfileStateManager: Background refresh completed for key: $key');

        // Update UI if this is the current user's data
        if (_userData != null &&
            key.contains(_userData!['googleId'] ?? _userData!['id'])) {
          _userVideos = freshData;
          notifyListeners();
        }
      }
    } catch (e) {
      print(
          '❌ ProfileStateManager: Background refresh failed for key: $key: $e');
    }
  }

  /// Clear all caches
  void _clearAllCaches() {
    _cache.clear();
    _cacheTimestamps.clear();
    _cacheEtags.clear();
    print('🧹 ProfileStateManager: All caches cleared');
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    return {
      'cacheSize': _cache.length,
      'cacheKeys': _cache.keys.toList(),
      'userProfileCacheTime': _userProfileCacheTime.inMinutes,
      'userVideosCacheTime': _userVideosCacheTime.inMinutes,
      'staleWhileRevalidateTime': _staleWhileRevalidateTime.inMinutes,
    };
  }

  // Cleanup
  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }
}
