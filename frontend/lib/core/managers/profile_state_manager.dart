import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snehayog/core/providers/video_provider.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/services/user_service.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/services/background_profile_preloader.dart';
import 'package:snehayog/utils/feature_flags.dart';
import 'package:snehayog/core/constants/profile_constants.dart';

// Import for unawaited

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

        // Videos will be loaded separately when loadUserVideos is called
        return;
      }

      final loggedInUser = await _authService.getUserData();
      print('🔄 ProfileStateManager: Logged in user: ${loggedInUser?['id']}');
      print('🔄 ProfileStateManager: Logged in user data: $loggedInUser');
      print(
          '🔄 ProfileStateManager: Logged in user keys: ${loggedInUser?.keys.toList()}');
      print(
          '🔄 ProfileStateManager: Logged in user values: ${loggedInUser?.values.toList()}');

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
      print('🔄 ProfileStateManager: userId parameter: $userId');
      print('🔄 ProfileStateManager: loggedInUser id: ${loggedInUser['id']}');
      print(
          '🔄 ProfileStateManager: loggedInUser googleId: ${loggedInUser['googleId']}');
      print('🔄 ProfileStateManager: userId == null: ${userId == null}');
      print(
          '🔄 ProfileStateManager: userId == loggedInUser[id]: ${userId == loggedInUser['id']}');
      print(
          '🔄 ProfileStateManager: userId == loggedInUser[googleId]: ${userId == loggedInUser['googleId']}');

      Map<String, dynamic>? userData;
      if (isMyProfile) {
        final myId = loggedInUser['googleId'] ?? loggedInUser['id'];
        try {
          final backendUser =
              myId != null ? await _userService.getUserById(myId) : null;
          if (backendUser != null) {
            userData = backendUser;
            print(
                '🔄 ProfileStateManager: Loaded own profile from backend: ${userData['name']}');
            // Merge counts from previously working local source if backend lacks them
            final localFollowers =
                loggedInUser['followers'] ?? loggedInUser['followersCount'];
            final localFollowing =
                loggedInUser['following'] ?? loggedInUser['followingCount'];
            if ((userData['followers'] == null || userData['followers'] == 0) &&
                localFollowers != null) {
              userData['followers'] = localFollowers;
              userData['followersCount'] = localFollowers;
            }
            if ((userData['following'] == null || userData['following'] == 0) &&
                localFollowing != null) {
              userData['following'] = localFollowing;
              userData['followingCount'] = localFollowing;
            }
          } else {
            userData = loggedInUser;
          }
        } catch (e) {
          print(
              '⚠️ ProfileStateManager: Failed to fetch own profile from backend, using local: $e');
          userData = loggedInUser;
        }

        // Apply locally saved avatar if any (do not override backend name)
        final savedProfilePic = await _loadSavedProfilePic();
        if (savedProfilePic != null && savedProfilePic.isNotEmpty) {
          userData['profilePic'] = savedProfilePic;
        }
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
      print(
          '🔄 ProfileStateManager: User data keys: ${_userData?.keys.toList()}');
      print(
          '🔄 ProfileStateManager: User data values: ${_userData?.values.toList()}');

      _isLoading = false;
      notifyListeners();
      print(
          '🔄 ProfileStateManager: User data loaded successfully, videos will be loaded separately');
    } catch (e) {
      print('❌ ProfileStateManager: Error loading user data: $e');
      _error = 'Error loading user data: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadUserVideos(String? userId) async {
    print('🔄 ProfileStateManager: loadUserVideos called with userId: $userId');

    try {
      // **FIXED: Properly check feature flag using FeatureFlags.instance**
      if (FeatureFlags.instance.isEnabled(Features.smartVideoCaching)) {
        await _loadUserVideosWithCaching(userId);
      } else {
        await _loadUserVideosDirect(userId);
      }

      // **FIXED: Ensure videos are loaded even if caching fails**
      if (_userVideos.isEmpty) {
        print(
            '⚠️ ProfileStateManager: No videos loaded, trying direct fallback');
        await _loadUserVideosDirect(userId);
      }

      print(
          '✅ ProfileStateManager: loadUserVideos completed with ${_userVideos.length} videos');
    } catch (e) {
      print('❌ ProfileStateManager: Error in loadUserVideos: $e');
      // Fallback to direct loading
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
        // **IMPROVED: Always use googleId for consistency**
        targetUserId = loggedInUser?['googleId'] ?? '';
        print(
            '🔍 ProfileStateManager: My profile - using googleId: $targetUserId');
        print('🔍 ProfileStateManager: loggedInUser data: $loggedInUser');
        print(
            '🔍 ProfileStateManager: loggedInUser googleId: ${loggedInUser?['googleId']}');
      } else {
        targetUserId = userId;
        print(
            '🔍 ProfileStateManager: Other profile - targetUserId: $targetUserId');
      }

      if (targetUserId.isNotEmpty) {
        // Check cache first
        final cacheKey = 'user_videos_$targetUserId';
        final cachedData = _getFromCache(cacheKey);

        print(
            '🔍 ProfileStateManager: Cache data check - cachedData: $cachedData');
        print(
            '🔍 ProfileStateManager: Cache data type: ${cachedData.runtimeType}');
        print(
            '🔍 ProfileStateManager: Cache data isNotEmpty: ${cachedData.isNotEmpty}');

        if (cachedData != null && cachedData.isNotEmpty) {
          // **FIXED: Return cached data instantly and only refresh in background if stale**
          _userVideos = List<VideoModel>.from(cachedData);
          print(
              '⚡ ProfileStateManager: Instant cache hit for videos: ${_userVideos.length} videos');
          notifyListeners();

          // **FIXED: Only schedule background refresh if cache is stale, don't fetch immediately**
          if (_isCacheStale(cacheKey, _userVideosCacheTime)) {
            print(
                '🔄 ProfileStateManager: Cache is stale, scheduling background refresh...');
            _scheduleBackgroundRefresh(
                cacheKey, () => _fetchVideosFromServer(targetUserId));
          } else {
            print(
                '✅ ProfileStateManager: Cache is fresh, no background refresh needed');
          }
        } else {
          // **FIXED: Cache miss - fetch from server only if no cached data**
          print('📡 ProfileStateManager: Cache miss, fetching from server...');
          await _fetchAndCacheVideos(targetUserId, cacheKey);
        }
      } else {
        print(
            '⚠️ ProfileStateManager: targetUserId is empty, cannot load videos');
        print('⚠️ ProfileStateManager: loggedInUser: $loggedInUser');
        print('⚠️ ProfileStateManager: userId parameter: $userId');
        _userVideos = [];
        notifyListeners();
      }
    } catch (e) {
      print('❌ ProfileStateManager: Error in cached video loading: $e');
      // **FIXED: Only fallback to direct loading if caching completely fails**
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
      print(
          '🔍 ProfileStateManager: Direct loading - isMyProfile: $isMyProfile');
      print(
          '🔍 ProfileStateManager: Direct loading - userId parameter: $userId');
      print(
          '🔍 ProfileStateManager: Direct loading - loggedInUser id: ${loggedInUser?['id']}');
      print(
          '🔍 ProfileStateManager: Direct loading - loggedInUser googleId: ${loggedInUser?['googleId']}');

      // Build a prioritized list of IDs to try (googleId then Mongo _id, then provided userId)
      final idsToTry = <String?>[
        if (isMyProfile) loggedInUser?['googleId'] else null,
        if (isMyProfile) loggedInUser?['id'] else null,
        if (!isMyProfile) userId else null,
        // If we have already loaded userData for other profile, try both ids from it
        _userData?['googleId'],
        _userData?['id'],
      ]
          .where((e) => e != null && (e).isNotEmpty)
          .map((e) => e as String)
          .toList()
          .toSet()
          .toList();

      print('🔍 ProfileStateManager: Direct loading - idsToTry: $idsToTry');

      _userVideos = [];
      for (final candidateId in idsToTry) {
        try {
          print(
              '🔍 ProfileStateManager: Trying VideoService.getUserVideos with id: $candidateId');
          final videos = await _videoService.getUserVideos(candidateId);
          if (videos.isNotEmpty) {
            _userVideos = videos;
            print(
                '✅ ProfileStateManager: Loaded ${videos.length} videos using id: $candidateId');
            break;
          } else {
            print(
                'ℹ️ ProfileStateManager: No videos for id: $candidateId, trying next');
          }
        } catch (e) {
          print(
              '⚠️ ProfileStateManager: Error fetching videos for id $candidateId: $e');
        }
      }

      // Notify UI regardless
      notifyListeners();
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
      List<VideoModel> videos = [];
      // Try primary id first
      try {
        videos = await _videoService.getUserVideos(userId);
      } catch (e) {
        print('⚠️ ProfileStateManager: Primary id fetch failed: $e');
      }

      // If empty, try alternate id (switch between googleId and Mongo _id)
      if (videos.isEmpty) {
        String? altId;
        // Prefer switching based on available userData or logged in user
        if (_userData != null) {
          if (_userData!['googleId'] == userId) {
            altId = _userData!['id'];
          } else if (_userData!['id'] == userId) {
            altId = _userData!['googleId'];
          }
        }
        final fetchedId = (await _authService.getUserData())?['id'] as String?;
        if (fetchedId != null && fetchedId.isNotEmpty && fetchedId != userId) {
          altId = fetchedId;
          print(
              '🔄 ProfileStateManager: Trying alternate id for fetch: $altId');
          try {
            videos = await _videoService.getUserVideos(fetchedId);
          } catch (e) {
            print('⚠️ ProfileStateManager: Alternate id fetch also failed: $e');
          }
        }
      }

      print(
          '📡 ProfileStateManager: Videos fetched from server: ${videos.length}');
      print('📡 ProfileStateManager: Videos data: $videos');

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
      bool allDeleted = true;
      for (final videoId in videoIdsToDelete) {
        try {
          final success = await _videoService.deleteVideo(videoId);
          if (!success) {
            allDeleted = false;
            print('❌ ProfileStateManager: Failed to delete video: $videoId');
          }
        } catch (e) {
          allDeleted = false;
          print('❌ ProfileStateManager: Error deleting video $videoId: $e');
        }
      }

      if (allDeleted) {
        print(
            '✅ ProfileStateManager: All videos deleted successfully from backend');

        // Remove deleted videos from local list
        _userVideos.removeWhere((video) => videoIdsToDelete.contains(video.id));

        // Clear selection and exit selection mode
        exitSelectionMode();

        _isLoading = false;

        // Clear relevant caches when videos are deleted to avoid stale data on first refresh
        if (FeatureFlags.instance.isEnabled(Features.smartVideoCaching) &&
            _userData != null) {
          final userId = _userData!['googleId'] ?? _userData!['id'];
          if (userId != null) {
            final cacheKey = 'user_videos_$userId';
            _cache.remove(cacheKey);
            _cacheTimestamps.remove(cacheKey);
            _cacheEtags.remove(cacheKey);
            print(
                '🧹 ProfileStateManager: Cleared cache after deleting videos');
          }
        }

        // **FIX: Clear BackgroundProfilePreloader cache to prevent deleted videos from reappearing on app restart**
        try {
          final preloader = BackgroundProfilePreloader();
          await preloader.clearCache();
          print(
              '🧹 ProfileStateManager: Cleared BackgroundProfilePreloader cache after video deletion');
        } catch (e) {
          print(
              '⚠️ ProfileStateManager: Error clearing BackgroundProfilePreloader cache: $e');
        }

        // Proactively refresh from server to ensure DB state is reflected immediately
        try {
          final refreshUserId = _userData?['googleId'] ?? _userData?['id'];
          if (refreshUserId != null && refreshUserId.toString().isNotEmpty) {
            await _loadUserVideosDirect(refreshUserId);
            print('🔄 ProfileStateManager: Reloaded videos after deletion');
          }
        } catch (e) {
          print(
              '⚠️ ProfileStateManager: Silent refresh after deletion failed: $e');
        }

        // Ensure UI updates after successful flow
        notifyListeners();

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

        // **FIX: Clear BackgroundProfilePreloader cache to prevent deleted video from reappearing on app restart**
        try {
          final preloader = BackgroundProfilePreloader();
          await preloader.clearCache();
          print(
              '🧹 ProfileStateManager: Cleared BackgroundProfilePreloader cache after single video deletion');
        } catch (e) {
          print(
              '⚠️ ProfileStateManager: Error clearing BackgroundProfilePreloader cache: $e');
        }

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
      print('🚪 ProfileStateManager: Starting logout process...');

      await _authService.signOut();

      // **FIXED: Clear ALL user data and state**
      _userData = null;
      _userVideos = [];
      _isEditing = false;
      _isSelecting = false;
      _selectedVideoIds.clear();

      // **FIXED: Clear all caches**
      _cache.clear();
      _cacheTimestamps.clear();
      _cacheEtags.clear();

      // **FIXED: Reset all state variables**
      _isLoading = false;
      _error = null;

      print('✅ ProfileStateManager: Logout completed - All state cleared');
      notifyListeners();
    } catch (e) {
      print('❌ ProfileStateManager: Error during logout: $e');
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

  // Setter for user data (for cache loading)
  void setUserData(Map<String, dynamic>? userData) {
    _userData = userData;
    notifyListeners();
  }

  /// **NEW: Setter for user videos (for background preloading)**
  void setVideos(List<VideoModel> videos) {
    _userVideos = videos;
    notifyListeners();
    print(
        '✅ ProfileStateManager: Set ${videos.length} videos from external source');
  }

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
        if (FeatureFlags.instance.isEnabled(Features.smartVideoCaching)) {
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
    if (FeatureFlags.instance.isEnabled(Features.smartVideoCaching) &&
        _userData != null) {
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
    if (FeatureFlags.instance.isEnabled(Features.smartVideoCaching) &&
        _userData != null) {
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
    print('🔍 ProfileStateManager: Checking cache for key: $key');
    print(
        '🔍 ProfileStateManager: Cache contains key: ${_cache.containsKey(key)}');
    print(
        '🔍 ProfileStateManager: Cache timestamps contains key: ${_cacheTimestamps.containsKey(key)}');

    if (_cache.containsKey(key) && _cacheTimestamps.containsKey(key)) {
      final timestamp = _cacheTimestamps[key]!;
      final now = DateTime.now();
      final cachedData = _cache[key];

      // Use appropriate cache time based on key type
      Duration cacheTime = key.contains('user_profile')
          ? _userProfileCacheTime
          : _userVideosCacheTime;

      print(
          '🔍 ProfileStateManager: Cache data type: ${cachedData.runtimeType}');
      print('🔍 ProfileStateManager: Cache data: $cachedData');
      print('🔍 ProfileStateManager: Cache timestamp: $timestamp');
      print('🔍 ProfileStateManager: Current time: $now');
      print(
          '🔍 ProfileStateManager: Cache age: ${now.difference(timestamp).inMinutes} minutes');
      print(
          '🔍 ProfileStateManager: Cache time limit: ${cacheTime.inMinutes} minutes');

      if (now.difference(timestamp) < cacheTime) {
        print('⚡ ProfileStateManager: Cache hit for key: $key');
        return _cache[key];
      } else {
        print('🔄 ProfileStateManager: Cache expired for key: $key');
        _cache.remove(key);
        _cacheTimestamps.remove(key);
        _cacheEtags.remove(key);
      }
    } else {
      print('🔍 ProfileStateManager: Cache miss for key: $key');
    }
    return null;
  }

  /// Set data in cache
  void _setCache(String key, dynamic data, Duration maxAge) {
    print('💾 ProfileStateManager: Setting cache for key: $key');
    print('💾 ProfileStateManager: Data type: ${data.runtimeType}');
    print('💾 ProfileStateManager: Data: $data');
    print('💾 ProfileStateManager: Max age: ${maxAge.inMinutes} minutes');

    _cache[key] = data;
    _cacheTimestamps[key] = DateTime.now();
    print('💾 ProfileStateManager: Cached data for key: $key');
  }

  /// **FIXED: Enhanced cache validation to prevent unnecessary API calls**
  bool _isCacheStale(String key, Duration maxAge) {
    if (_cacheTimestamps.containsKey(key)) {
      final timestamp = _cacheTimestamps[key]!;
      final now = DateTime.now();
      final age = now.difference(timestamp);

      // **FIXED: Only consider cache stale after 90% of max age to prevent premature refreshes**
      final isStale = age > maxAge * 0.9;

      print(
          '🔍 ProfileStateManager: Cache age: ${age.inMinutes} minutes, max age: ${maxAge.inMinutes} minutes, is stale: $isStale');

      return isStale;
    }
    return false;
  }

  /// **FIXED: Enhanced background refresh to prevent duplicate API calls**
  void _scheduleBackgroundRefresh(
      String key, Future<List<VideoModel>> Function() fetchFn) {
    if (FeatureFlags.instance.isEnabled(Features.backgroundVideoPreloading)) {
      // **FIXED: Check if refresh is already scheduled to prevent duplicates**
      if (!_isRefreshScheduled(key)) {
        print(
            '🔄 ProfileStateManager: Scheduling background refresh for key: $key');
        _scheduleRefresh(key, fetchFn);
      } else {
        print(
            '⏳ ProfileStateManager: Background refresh already scheduled for key: $key');
      }
    }
  }

  // **NEW: Track scheduled refreshes to prevent duplicates**
  final Set<String> _scheduledRefreshes = {};

  /// **NEW: Check if refresh is already scheduled**
  bool _isRefreshScheduled(String key) {
    return _scheduledRefreshes.contains(key);
  }

  /// **NEW: Schedule refresh and track it**
  void _scheduleRefresh(
      String key, Future<List<VideoModel>> Function() fetchFn) {
    _scheduledRefreshes.add(key);

    unawaited(_refreshCacheInBackground(key, fetchFn).then((_) {
      _scheduledRefreshes.remove(key);
    }));
  }

  /// **FIXED: Enhanced background refresh with better error handling**
  Future<void> _refreshCacheInBackground(
      String key, Future<List<VideoModel>> Function() fetchFn) async {
    try {
      print(
          '🔄 ProfileStateManager: Starting background refresh for key: $key');

      // **FIXED: Add delay to avoid blocking UI and prevent rapid successive calls**
      await Future.delayed(const Duration(seconds: 3));

      final freshData = await fetchFn();

      if (freshData.isNotEmpty) {
        _setCache(key, freshData, _userVideosCacheTime);
        print(
            '✅ ProfileStateManager: Background refresh completed for key: $key');

        // **FIXED: Only update UI if this is the current user's data and cache is still valid**
        if (_userData != null &&
            key.contains(_userData!['googleId'] ?? _userData!['id']) &&
            _isCacheValid(key)) {
          _userVideos = freshData;
          notifyListeners();
          print(
              '✅ ProfileStateManager: UI updated with fresh data from background refresh');
        }
      } else {
        print(
            '⚠️ ProfileStateManager: Background refresh returned empty data for key: $key');
      }
    } catch (e) {
      print(
          '❌ ProfileStateManager: Background refresh failed for key: $key: $e');
    } finally {
      // **FIXED: Always remove from scheduled refreshes, even on error**
      _scheduledRefreshes.remove(key);
    }
  }

  /// **NEW: Check if cache is still valid (not manually cleared)**
  bool _isCacheValid(String key) {
    return _cache.containsKey(key) && _cacheTimestamps.containsKey(key);
  }

  /// **NEW: Force refresh videos by clearing cache and reloading**
  Future<void> forceRefreshVideos(String? userId) async {
    print(
        '🔄 ProfileStateManager: Force refreshing videos for userId: $userId');

    // Clear video cache
    final keysToRemove =
        _cache.keys.where((key) => key.contains('user_videos')).toList();
    for (final key in keysToRemove) {
      _cache.remove(key);
      _cacheTimestamps.remove(key);
      _cacheEtags.remove(key);
    }
    print('🧹 ProfileStateManager: Cleared video caches: $keysToRemove');

    // Reload videos directly
    await _loadUserVideosDirect(userId);
    print(
        '✅ ProfileStateManager: Force refresh completed with ${_userVideos.length} videos');
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
