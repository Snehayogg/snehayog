import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/core/providers/video_provider.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/services/cloudinary_service.dart';
import 'package:vayu/services/user_service.dart';
import 'package:vayu/services/video_service.dart';
import 'package:vayu/utils/feature_flags.dart';
import 'package:vayu/core/constants/profile_constants.dart';
import 'package:vayu/core/managers/smart_cache_manager.dart';
import 'package:vayu/utils/app_logger.dart';

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
      AppLogger.log(
          '🔄 ProfileStateManager: Loading user data for userId: $userId');

      // **OPTIMIZED: Check cache first for instant response**
      final cacheKey = 'user_profile_$userId';
      final cachedProfile = _getFromCache(cacheKey);

      if (cachedProfile != null &&
          !_isCacheStale(cacheKey, _userProfileCacheTime)) {
        AppLogger.log('⚡ ProfileStateManager: Cache hit for profile data');
        _userData = cachedProfile;
        _isLoading = false;
        notifyListeners();

        // Videos will be loaded separately when loadUserVideos is called
        return;
      }

      final loggedInUser = await _authService.getUserData();
      AppLogger.log(
          '🔄 ProfileStateManager: Logged in user: ${loggedInUser?['id']}');
      AppLogger.log(
          '🔄 ProfileStateManager: Logged in user data: $loggedInUser');
      AppLogger.log(
          '🔄 ProfileStateManager: Logged in user keys: ${loggedInUser?.keys.toList()}');
      AppLogger.log(
          '🔄 ProfileStateManager: Logged in user values: ${loggedInUser?.values.toList()}');

      // Check if we have any authentication data
      if (loggedInUser == null) {
        AppLogger.log(
            '❌ ProfileStateManager: No authentication data available');
        _isLoading = false;
        _error = 'No authentication data available. Please sign in.';
        notifyListeners();
        return;
      }

      final bool isMyProfile = userId == null ||
          userId == loggedInUser['id'] ||
          userId == loggedInUser['googleId'];
      AppLogger.log('🔄 ProfileStateManager: Is my profile: $isMyProfile');
      AppLogger.log('🔄 ProfileStateManager: userId parameter: $userId');
      AppLogger.log(
          '🔄 ProfileStateManager: loggedInUser id: ${loggedInUser['id']}');
      AppLogger.log(
          '🔄 ProfileStateManager: loggedInUser googleId: ${loggedInUser['googleId']}');
      AppLogger.log(
          '🔄 ProfileStateManager: userId == null: ${userId == null}');
      AppLogger.log(
          '🔄 ProfileStateManager: userId == loggedInUser[id]: ${userId == loggedInUser['id']}');
      AppLogger.log(
          '🔄 ProfileStateManager: userId == loggedInUser[googleId]: ${userId == loggedInUser['googleId']}');

      Map<String, dynamic>? userData;
      if (isMyProfile) {
        final myId = loggedInUser['googleId'] ?? loggedInUser['id'];
        try {
          final backendUser =
              myId != null ? await _userService.getUserById(myId) : null;
          if (backendUser != null) {
            userData = backendUser;
            AppLogger.log(
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
          AppLogger.log(
              '⚠️ ProfileStateManager: Failed to fetch own profile from backend, using local: $e');
          userData = loggedInUser;
        }

        // **REMOVED: Do not apply locally saved avatar - backend is source of truth**
        // The profile picture from backend should always be used to ensure permanent changes persist
      } else {
        // Fetch profile data for another user
        AppLogger.log(
            '🔄 ProfileStateManager: Fetching other user profile for ID: $userId');
        userData = await _userService.getUserById(userId);
        AppLogger.log(
            '🔄 ProfileStateManager: Other user profile loaded: ${userData['name']}');
      }

      // **OPTIMIZED: Cache the profile data**
      _setCache(cacheKey, userData, _userProfileCacheTime);

      _userData = userData;
      AppLogger.log('🔄 ProfileStateManager: Stored user data: $_userData');
      AppLogger.log(
          '🔄 ProfileStateManager: Stored user googleId: ${_userData?['googleId']}');
      AppLogger.log(
          '🔄 ProfileStateManager: Stored user id: ${_userData?['id']}');
      AppLogger.log(
          '🔄 ProfileStateManager: User data keys: ${_userData?.keys.toList()}');
      AppLogger.log(
          '🔄 ProfileStateManager: User data values: ${_userData?.values.toList()}');

      _isLoading = false;
      notifyListeners();
      AppLogger.log(
          '🔄 ProfileStateManager: User data loaded successfully, videos will be loaded separately');
    } catch (e) {
      AppLogger.log('❌ ProfileStateManager: Error loading user data: $e');
      _error = 'Error loading user data: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadUserVideos(String? userId) async {
    AppLogger.log(
        '🔄 ProfileStateManager: loadUserVideos called with userId: $userId');

    try {
      // **FIXED: Properly check feature flag using FeatureFlags.instance**
      if (FeatureFlags.instance.isEnabled(Features.smartVideoCaching)) {
        await _loadUserVideosWithCaching(userId);
      } else {
        await _loadUserVideosDirect(userId);
      }

      // **FIXED: Ensure videos are loaded even if caching fails**
      if (_userVideos.isEmpty) {
        AppLogger.log(
            '⚠️ ProfileStateManager: No videos loaded, trying direct fallback');
        await _loadUserVideosDirect(userId);
      }

      AppLogger.log(
          '✅ ProfileStateManager: loadUserVideos completed with ${_userVideos.length} videos');
    } catch (e) {
      AppLogger.log('❌ ProfileStateManager: Error in loadUserVideos: $e');
      // Fallback to direct loading
      await _loadUserVideosDirect(userId);
    }
  }

  /// Load user videos with Instagram-like caching strategy
  Future<void> _loadUserVideosWithCaching(String? userId) async {
    try {
      AppLogger.log(
          '🔄 ProfileStateManager: Loading videos with Instagram-like caching for userId: $userId');

      final loggedInUser = await _authService.getUserData();
      final bool isMyProfile = userId == null ||
          userId == loggedInUser?['id'] ||
          userId == loggedInUser?['googleId'];

      String targetUserId;
      if (isMyProfile) {
        // **IMPROVED: Always use googleId for consistency**
        targetUserId = loggedInUser?['googleId'] ?? '';
        AppLogger.log(
            '🔍 ProfileStateManager: My profile - using googleId: $targetUserId');
        AppLogger.log(
            '🔍 ProfileStateManager: loggedInUser data: $loggedInUser');
        AppLogger.log(
            '🔍 ProfileStateManager: loggedInUser googleId: ${loggedInUser?['googleId']}');
      } else {
        targetUserId = userId;
        AppLogger.log(
            '🔍 ProfileStateManager: Other profile - targetUserId: $targetUserId');
      }

      if (targetUserId.isNotEmpty) {
        // Check cache first
        final cacheKey = 'user_videos_$targetUserId';
        final cachedData = _getFromCache(cacheKey);

        AppLogger.log(
            '🔍 ProfileStateManager: Cache data check - cachedData: $cachedData');
        AppLogger.log(
            '🔍 ProfileStateManager: Cache data type: ${cachedData.runtimeType}');
        AppLogger.log(
            '🔍 ProfileStateManager: Cache data isNotEmpty: ${cachedData.isNotEmpty}');

        if (cachedData != null && cachedData.isNotEmpty) {
          // **FIXED: Return cached data instantly and only refresh in background if stale**
          _userVideos = List<VideoModel>.from(cachedData);
          AppLogger.log(
              '⚡ ProfileStateManager: Instant cache hit for videos: ${_userVideos.length} videos');
          notifyListeners();

          // **FIXED: Only schedule background refresh if cache is stale, don't fetch immediately**
          if (_isCacheStale(cacheKey, _userVideosCacheTime)) {
            AppLogger.log(
                '🔄 ProfileStateManager: Cache is stale, scheduling background refresh...');
            _scheduleBackgroundRefresh(
                cacheKey, () => _fetchVideosFromServer(targetUserId));
          } else {
            AppLogger.log(
                '✅ ProfileStateManager: Cache is fresh, no background refresh needed');
          }
        } else {
          // **FIXED: Cache miss - fetch from server only if no cached data**
          AppLogger.log(
              '📡 ProfileStateManager: Cache miss, fetching from server...');
          await _fetchAndCacheVideos(targetUserId, cacheKey);
        }
      } else {
        AppLogger.log(
            '⚠️ ProfileStateManager: targetUserId is empty, cannot load videos');
        AppLogger.log('⚠️ ProfileStateManager: loggedInUser: $loggedInUser');
        AppLogger.log('⚠️ ProfileStateManager: userId parameter: $userId');
        _userVideos = [];
        notifyListeners();
      }
    } catch (e) {
      AppLogger.log('❌ ProfileStateManager: Error in cached video loading: $e');
      // **FIXED: Only fallback to direct loading if caching completely fails**
      await _loadUserVideosDirect(userId);
    }
  }

  /// Load user videos directly without caching (fallback)
  Future<void> _loadUserVideosDirect(String? userId) async {
    try {
      AppLogger.log(
          '🔄 ProfileStateManager: Loading videos directly for userId: $userId');

      final loggedInUser = await _authService.getUserData();
      final bool isMyProfile = userId == null ||
          userId == loggedInUser?['id'] ||
          userId == loggedInUser?['googleId'];
      AppLogger.log(
          '🔍 ProfileStateManager: Direct loading - isMyProfile: $isMyProfile');
      AppLogger.log(
          '🔍 ProfileStateManager: Direct loading - userId parameter: $userId');
      AppLogger.log(
          '🔍 ProfileStateManager: Direct loading - loggedInUser id: ${loggedInUser?['id']}');
      AppLogger.log(
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

      AppLogger.log(
          '🔍 ProfileStateManager: Direct loading - idsToTry: $idsToTry');

      _userVideos = [];
      for (final candidateId in idsToTry) {
        try {
          AppLogger.log(
              '🔍 ProfileStateManager: Trying VideoService.getUserVideos with id: $candidateId');
          final videos = await _videoService.getUserVideos(candidateId);
          if (videos.isNotEmpty) {
            _userVideos = videos;
            AppLogger.log(
                '✅ ProfileStateManager: Loaded ${videos.length} videos using id: $candidateId');
            break;
          } else {
            AppLogger.log(
                'ℹ️ ProfileStateManager: No videos for id: $candidateId, trying next');
          }
        } catch (e) {
          AppLogger.log(
              '⚠️ ProfileStateManager: Error fetching videos for id $candidateId: $e');
        }
      }

      // Notify UI regardless
      notifyListeners();
    } catch (e) {
      AppLogger.log('❌ ProfileStateManager: Error in direct video loading: $e');
      _error = '${ProfileConstants.errorLoadingVideos}${e.toString()}';
      _userVideos = [];
      notifyListeners();
    }
  }

  /// Fetch videos from server and cache them
  Future<void> _fetchAndCacheVideos(String userId, String cacheKey) async {
    try {
      AppLogger.log(
          '📡 ProfileStateManager: Fetching videos from server for user: $userId');
      List<VideoModel> videos = [];
      // Try primary id first
      try {
        videos = await _videoService.getUserVideos(userId);
      } catch (e) {
        AppLogger.log('⚠️ ProfileStateManager: Primary id fetch failed: $e');
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
          AppLogger.log(
              '🔄 ProfileStateManager: Trying alternate id for fetch: $altId');
          try {
            videos = await _videoService.getUserVideos(fetchedId);
          } catch (e) {
            AppLogger.log(
                '⚠️ ProfileStateManager: Alternate id fetch also failed: $e');
          }
        }
      }

      AppLogger.log(
          '📡 ProfileStateManager: Videos fetched from server: ${videos.length}');
      AppLogger.log('📡 ProfileStateManager: Videos data: $videos');

      // Cache the videos
      _setCache(cacheKey, videos, _userVideosCacheTime);

      _userVideos = videos;
      AppLogger.log(
          '✅ ProfileStateManager: Fetched and cached ${videos.length} videos');
      notifyListeners();
    } catch (e) {
      AppLogger.log(
          '❌ ProfileStateManager: Error fetching videos from server: $e');
      rethrow;
    }
  }

  /// Fetch videos from server (for background refresh)
  Future<List<VideoModel>> _fetchVideosFromServer(String userId) async {
    try {
      return await _videoService.getUserVideos(userId);
    } catch (e) {
      AppLogger.log(
          '❌ ProfileStateManager: Error in background video fetch: $e');
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

  Future<void> updateProfilePhoto(String? profilePicPath) async {
    if (_userData != null && profilePicPath != null) {
      try {
        AppLogger.log(
            '📸 ProfileStateManager: Starting profile photo upload...');

        // Check if it's already a URL (http/https)
        if (profilePicPath.startsWith('http')) {
          // Already a URL, just save it
          AppLogger.log(
              '✅ ProfileStateManager: Photo is already a URL, saving directly');
          await _saveProfileData(_userData!['name'], profilePicPath);
          _userData!['profilePic'] = profilePicPath;
          notifyListeners();
          return;
        }

        // It's a local file path, need to upload it first
        AppLogger.log(
            '📤 ProfileStateManager: Uploading local file to cloud storage...');
        final cloudinaryService = CloudinaryService();
        final uploadedUrl = await cloudinaryService.uploadImage(
          File(profilePicPath),
          folder: 'snehayog/profile',
        );

        AppLogger.log(
            '✅ ProfileStateManager: Photo uploaded successfully: $uploadedUrl');

        // Now save the URL to backend
        await _saveProfileData(_userData!['name'], uploadedUrl);
        _userData!['profilePic'] = uploadedUrl;
        notifyListeners();
        AppLogger.log(
            '✅ ProfileStateManager: Profile photo updated successfully');
      } catch (e) {
        AppLogger.log(
            '❌ ProfileStateManager: Error uploading profile photo: $e');
        rethrow;
      }
    }
  }

  // Video selection management
  void toggleVideoSelection(String videoId) {
    AppLogger.log('🔍 toggleVideoSelection called with videoId: $videoId');
    AppLogger.log('🔍 Current selectedVideoIds: $_selectedVideoIds');

    if (_selectedVideoIds.contains(videoId)) {
      _selectedVideoIds.remove(videoId);
      AppLogger.log('🔍 Removed videoId: $videoId');
    } else {
      _selectedVideoIds.add(videoId);
      AppLogger.log('🔍 Added videoId: $videoId');
    }

    AppLogger.log('🔍 Updated selectedVideoIds: $_selectedVideoIds');
    notifyListeners();
  }

  void clearSelection() {
    AppLogger.log('🔍 clearSelection called');
    _selectedVideoIds.clear();
    notifyListeners();
  }

  void exitSelectionMode() {
    AppLogger.log('🔍 exitSelectionMode called');
    _isSelecting = false;
    _selectedVideoIds.clear();
    notifyListeners();
  }

  void enterSelectionMode() {
    AppLogger.log('🔍 enterSelectionMode called');
    _isSelecting = true;
    notifyListeners();
  }

  Future<void> deleteSelectedVideos() async {
    if (_selectedVideoIds.isEmpty) return;

    try {
      AppLogger.log(
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
            AppLogger.log(
                '❌ ProfileStateManager: Failed to delete video: $videoId');
          }
        } catch (e) {
          allDeleted = false;
          AppLogger.log(
              '❌ ProfileStateManager: Error deleting video $videoId: $e');
        }
      }

      if (allDeleted) {
        AppLogger.log(
            '✅ ProfileStateManager: All videos deleted successfully from backend');

        // Remove deleted videos from local list
        _userVideos.removeWhere((video) => videoIdsToDelete.contains(video.id));

        // Clear selection and exit selection mode
        exitSelectionMode();

        _isLoading = false;

        // **NEW: Invalidate SmartCacheManager video cache to prevent deleted videos from showing**
        try {
          final smartCacheManager = SmartCacheManager();
          // Invalidate all video caches for all video types (yog, reel, etc)
          await smartCacheManager.invalidateVideoCache();
          AppLogger.log(
              '🗑️ ProfileStateManager: Invalidated SmartCacheManager video cache after deletion');
        } catch (e) {
          AppLogger.log(
              '⚠️ ProfileStateManager: Failed to invalidate cache: $e');
        }

        // Clear relevant caches when videos are deleted to avoid stale data on first refresh
        if (FeatureFlags.instance.isEnabled(Features.smartVideoCaching) &&
            _userData != null) {
          final userId = _userData!['googleId'] ?? _userData!['id'];
          if (userId != null) {
            final cacheKey = 'user_videos_$userId';
            _cache.remove(cacheKey);
            _cacheTimestamps.remove(cacheKey);
            _cacheEtags.remove(cacheKey);
            AppLogger.log(
                '🧹 ProfileStateManager: Cleared cache after deleting videos');
          }
        }

        // Proactively refresh from server to ensure DB state is reflected immediately
        try {
          final refreshUserId = _userData?['googleId'] ?? _userData?['id'];
          if (refreshUserId != null && refreshUserId.toString().isNotEmpty) {
            await _loadUserVideosDirect(refreshUserId);
            AppLogger.log(
                '🔄 ProfileStateManager: Reloaded videos after deletion');
          }
        } catch (e) {
          AppLogger.log(
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
            AppLogger.log(
                '✅ ProfileStateManager: Notified VideoProvider of deleted videos');
          } catch (e) {
            AppLogger.log(
                '⚠️ ProfileStateManager: Could not notify VideoProvider: $e');
            // Try to refresh the video feed as fallback
            try {
              final videoProvider =
                  Provider.of<VideoProvider>(_context!, listen: false);
              videoProvider.refreshVideos();
              AppLogger.log(
                  '🔄 ProfileStateManager: Refreshed VideoProvider as fallback');
            } catch (refreshError) {
              AppLogger.log(
                  '❌ ProfileStateManager: Could not refresh VideoProvider: $refreshError');
            }
          }
        } else {
          AppLogger.log(
              '⚠️ ProfileStateManager: Context not available, cannot notify VideoProvider');
        }

        AppLogger.log(
            '✅ ProfileStateManager: Local state updated after successful deletion');
      } else {
        throw Exception('Backend deletion failed');
      }
    } catch (e) {
      AppLogger.log('❌ ProfileStateManager: Error deleting videos: $e');

      _isLoading = false;
      _error = _getUserFriendlyErrorMessage(e);
      notifyListeners();
    }
  }

  /// Deletes a single video with enhanced error handling
  Future<bool> deleteSingleVideo(String videoId) async {
    try {
      AppLogger.log('🗑️ ProfileStateManager: Deleting single video: $videoId');

      _isLoading = true;
      _error = null;

      // Delete from backend
      final deletionSuccess = await _videoService.deleteVideo(videoId);

      if (deletionSuccess) {
        AppLogger.log(
            '✅ ProfileStateManager: Single video deleted successfully');

        // Remove from local list
        _userVideos.removeWhere((video) => video.id == videoId);

        _isLoading = false;

        // Notify VideoProvider to update the main video feed
        if (_context != null) {
          try {
            final videoProvider =
                Provider.of<VideoProvider>(_context!, listen: false);
            videoProvider.removeVideoFromList(videoId);
            AppLogger.log(
                '✅ ProfileStateManager: Notified VideoProvider of deleted video');
          } catch (e) {
            AppLogger.log(
                '⚠️ ProfileStateManager: Could not notify VideoProvider: $e');
          }
        }

        return true;
      } else {
        throw Exception('Backend deletion failed');
      }
    } catch (e) {
      AppLogger.log('❌ ProfileStateManager: Error deleting single video: $e');

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

  // **REMOVED: Utility methods for loading saved name/profilePic**
  // These were removed because backend is now the source of truth and
  // we don't want to override backend data with old SharedPreferences values

  Future<void> _saveProfileData(String name, String? profilePic) async {
    try {
      AppLogger.log(
          '💾 ProfileStateManager: Saving profile data to backend...');

      // Get googleId from user data (with fallback to 'id')
      final googleId = _userData?['googleId'] ?? _userData?['id'];
      if (googleId == null) {
        AppLogger.log(
            '❌ ProfileStateManager: No user ID found in user data: $_userData');
        throw Exception('User ID not found');
      }

      AppLogger.log('✅ ProfileStateManager: Using googleId: $googleId');

      // Save to backend via API
      final success = await _userService.updateProfile(
        googleId: googleId,
        name: name,
        profilePic: profilePic,
      );

      if (success) {
        AppLogger.log(
            '✅ ProfileStateManager: Profile saved to backend successfully');

        // **FIXED: Update SharedPreferences fallback_user with new profile data**
        try {
          final prefs = await SharedPreferences.getInstance();
          final updatedFallbackData = {
            'id': googleId,
            'googleId': googleId,
            'name': name,
            'email': _userData?['email'] ?? '',
            'profilePic': profilePic ?? _userData?['profilePic'] ?? '',
          };
          await prefs.setString(
              'fallback_user', jsonEncode(updatedFallbackData));
          AppLogger.log(
              '✅ ProfileStateManager: Updated fallback_user with new profile data');
        } catch (e) {
          AppLogger.log(
              '⚠️ ProfileStateManager: Failed to update fallback_user: $e');
        }

        // Clear cache to force fresh data fetch
        final cacheKey = 'user_profile_$googleId';
        _cache.remove(cacheKey);
        _cacheTimestamps.remove(cacheKey);
        _cacheEtags.remove(cacheKey);
        AppLogger.log(
            '🧹 ProfileStateManager: Cleared cache after profile update');

        // Update local state immediately
        _userData?['name'] = name;
        if (profilePic != null) {
          _userData?['profilePic'] = profilePic;
        }
        notifyListeners();
        AppLogger.log('✅ ProfileStateManager: Local state updated');
      } else {
        throw Exception('Failed to update profile on server');
      }
    } catch (e) {
      AppLogger.log('❌ ProfileStateManager: Error saving profile data: $e');
      rethrow;
    }
  }

  // Custom setState method removed - use notifyListeners() directly

  // Error handling
  void clearError() {
    _error = null;
    notifyListeners();
  }

  /// **Clear all user data (used when user signs out)**
  void clearData() {
    _userData = null;
    _userVideos = [];
    _isEditing = false;
    _isSelecting = false;
    _selectedVideoIds.clear();
    _error = null;
    _isLoading = false;
    notifyListeners();
  }

  // Authentication methods
  Future<void> handleLogout() async {
    try {
      AppLogger.log('🚪 ProfileStateManager: Starting logout process...');

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

      AppLogger.log(
          '✅ ProfileStateManager: Logout completed - All state cleared');
      notifyListeners();
    } catch (e) {
      AppLogger.log('❌ ProfileStateManager: Error during logout: $e');
      _error = 'Failed to logout: ${e.toString()}';
      notifyListeners();
    }
  }

  // Getter for user data
  Map<String, dynamic>? getUserData() => _userData;

  // Setter for user data (for cache loading)
  void setUserData(Map<String, dynamic>? userData) {
    _userData = userData;
    notifyListeners();
  }

  /// **NEW: Public method to get logged in user data for fallback loading**
  Future<Map<String, dynamic>?> getLoggedInUserData() async {
    try {
      return await _authService.getUserData();
    } catch (e) {
      AppLogger.log(
          '❌ ProfileStateManager: Error getting logged in user data: $e');
      return null;
    }
  }

  /// **NEW: Setter for user videos (for background preloading)**
  void setVideos(List<VideoModel> videos) {
    _userVideos = videos;
    notifyListeners();
    AppLogger.log(
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
        AppLogger.log(
            '🔄 ProfileStateManager: Refreshing data for user with googleId: $targetUserId');
      } else if (_userData != null && _userData!['id'] != null) {
        // Fallback to MongoDB _id if googleId not available
        targetUserId = _userData!['id'];
        AppLogger.log(
            '🔄 ProfileStateManager: Refreshing data for user with MongoDB _id: $targetUserId');
      } else {
        final loggedInUser = await _authService.getUserData();
        // **FIXED: Prioritize googleId over MongoDB _id**
        targetUserId = loggedInUser?['googleId'] ?? loggedInUser?['id'];
        AppLogger.log(
            '🔄 ProfileStateManager: Refreshing data for logged in user: $targetUserId');
      }

      // Reload user data and videos
      await loadUserData(targetUserId);

      _isLoading = false;
      notifyListeners();

      AppLogger.log('✅ ProfileStateManager: Data refreshed successfully');
    } catch (e) {
      _isLoading = false;
      _error = 'Failed to refresh data: ${e.toString()}';
      notifyListeners();
      AppLogger.log('❌ ProfileStateManager: Error refreshing data: $e');
    }
  }

  /// Force refresh videos only (for when new videos are uploaded)
  Future<void> refreshVideosOnly() async {
    try {
      AppLogger.log('🔄 ProfileStateManager: Force refreshing user videos...');

      // Get the current user ID from userData or logged in user
      String? targetUserId;
      if (_userData != null && _userData!['googleId'] != null) {
        targetUserId = _userData!['googleId'];
        AppLogger.log(
            '🔄 ProfileStateManager: Refreshing videos for user with googleId: $targetUserId');
      } else if (_userData != null && _userData!['id'] != null) {
        targetUserId = _userData!['id'];
        AppLogger.log(
            '🔄 ProfileStateManager: Refreshing videos for user with MongoDB _id: $targetUserId');
      } else {
        final loggedInUser = await _authService.getUserData();
        targetUserId = loggedInUser?['googleId'] ?? loggedInUser?['id'];
        AppLogger.log(
            '🔄 ProfileStateManager: Refreshing videos for logged in user: $targetUserId');
      }

      if (targetUserId != null && targetUserId.isNotEmpty) {
        if (FeatureFlags.instance.isEnabled(Features.smartVideoCaching)) {
          // Clear cache and reload with fresh data
          final cacheKey = 'user_videos_$targetUserId';
          _cache.remove(cacheKey);
          _cacheTimestamps.remove(cacheKey);
          _cacheEtags.remove(cacheKey);
          AppLogger.log(
              '🧹 ProfileStateManager: Cleared cache for key: $cacheKey');

          // Reload with fresh data
          await _fetchAndCacheVideos(targetUserId, cacheKey);
        } else {
          // Direct refresh without caching
          final videos = await _videoService.getUserVideos(targetUserId);
          _userVideos = videos;
          notifyListeners();
          AppLogger.log(
              '✅ ProfileStateManager: Videos refreshed directly. Count: ${videos.length}');
        }
      } else {
        AppLogger.log(
            '⚠️ ProfileStateManager: No valid user ID for video refresh');
      }
    } catch (e) {
      AppLogger.log('❌ ProfileStateManager: Error refreshing videos: $e');
      _error = 'Failed to refresh videos: ${e.toString()}';
      notifyListeners();
    }
  }

  /// Add a new video to the profile (called after successful upload)
  void addNewVideo(VideoModel video) {
    AppLogger.log(
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
        AppLogger.log(
            '🧹 ProfileStateManager: Cleared cache after adding new video');
      }
    }

    notifyListeners();
  }

  /// Remove a video from the profile
  void removeVideo(String videoId) {
    AppLogger.log(
        '➖ ProfileStateManager: Removing video from profile: $videoId');
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
        AppLogger.log(
            '🧹 ProfileStateManager: Cleared cache after removing video');
      }
    }

    notifyListeners();
  }

  // Instagram-like caching methods
  /// Get data from cache
  dynamic _getFromCache(String key) {
    AppLogger.log('🔍 ProfileStateManager: Checking cache for key: $key');
    AppLogger.log(
        '🔍 ProfileStateManager: Cache contains key: ${_cache.containsKey(key)}');
    AppLogger.log(
        '🔍 ProfileStateManager: Cache timestamps contains key: ${_cacheTimestamps.containsKey(key)}');

    if (_cache.containsKey(key) && _cacheTimestamps.containsKey(key)) {
      final timestamp = _cacheTimestamps[key]!;
      final now = DateTime.now();
      final cachedData = _cache[key];

      // Use appropriate cache time based on key type
      Duration cacheTime = key.contains('user_profile')
          ? _userProfileCacheTime
          : _userVideosCacheTime;

      AppLogger.log(
          '🔍 ProfileStateManager: Cache data type: ${cachedData.runtimeType}');
      AppLogger.log('🔍 ProfileStateManager: Cache data: $cachedData');
      AppLogger.log('🔍 ProfileStateManager: Cache timestamp: $timestamp');
      AppLogger.log('🔍 ProfileStateManager: Current time: $now');
      AppLogger.log(
          '🔍 ProfileStateManager: Cache age: ${now.difference(timestamp).inMinutes} minutes');
      AppLogger.log(
          '🔍 ProfileStateManager: Cache time limit: ${cacheTime.inMinutes} minutes');

      if (now.difference(timestamp) < cacheTime) {
        AppLogger.log('⚡ ProfileStateManager: Cache hit for key: $key');
        return _cache[key];
      } else {
        AppLogger.log('🔄 ProfileStateManager: Cache expired for key: $key');
        _cache.remove(key);
        _cacheTimestamps.remove(key);
        _cacheEtags.remove(key);
      }
    } else {
      AppLogger.log('🔍 ProfileStateManager: Cache miss for key: $key');
    }
    return null;
  }

  /// Set data in cache
  void _setCache(String key, dynamic data, Duration maxAge) {
    AppLogger.log('💾 ProfileStateManager: Setting cache for key: $key');
    AppLogger.log('💾 ProfileStateManager: Data type: ${data.runtimeType}');
    AppLogger.log('💾 ProfileStateManager: Data: $data');
    AppLogger.log(
        '💾 ProfileStateManager: Max age: ${maxAge.inMinutes} minutes');

    _cache[key] = data;
    _cacheTimestamps[key] = DateTime.now();
    AppLogger.log('💾 ProfileStateManager: Cached data for key: $key');
  }

  /// **FIXED: Enhanced cache validation to prevent unnecessary API calls**
  bool _isCacheStale(String key, Duration maxAge) {
    if (_cacheTimestamps.containsKey(key)) {
      final timestamp = _cacheTimestamps[key]!;
      final now = DateTime.now();
      final age = now.difference(timestamp);

      // **FIXED: Only consider cache stale after 90% of max age to prevent premature refreshes**
      final isStale = age > maxAge * 0.9;

      AppLogger.log(
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
        AppLogger.log(
            '🔄 ProfileStateManager: Scheduling background refresh for key: $key');
        _scheduleRefresh(key, fetchFn);
      } else {
        AppLogger.log(
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
      AppLogger.log(
          '🔄 ProfileStateManager: Starting background refresh for key: $key');

      // **FIXED: Add delay to avoid blocking UI and prevent rapid successive calls**
      await Future.delayed(const Duration(seconds: 3));

      final freshData = await fetchFn();

      if (freshData.isNotEmpty) {
        _setCache(key, freshData, _userVideosCacheTime);
        AppLogger.log(
            '✅ ProfileStateManager: Background refresh completed for key: $key');

        // **FIXED: Only update UI if this is the current user's data and cache is still valid**
        if (_userData != null &&
            key.contains(_userData!['googleId'] ?? _userData!['id']) &&
            _isCacheValid(key)) {
          _userVideos = freshData;
          notifyListeners();
          AppLogger.log(
              '✅ ProfileStateManager: UI updated with fresh data from background refresh');
        }
      } else {
        AppLogger.log(
            '⚠️ ProfileStateManager: Background refresh returned empty data for key: $key');
      }
    } catch (e) {
      AppLogger.log(
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
    AppLogger.log(
        '🔄 ProfileStateManager: Force refreshing videos for userId: $userId');

    // Clear video cache
    final keysToRemove =
        _cache.keys.where((key) => key.contains('user_videos')).toList();
    for (final key in keysToRemove) {
      _cache.remove(key);
      _cacheTimestamps.remove(key);
      _cacheEtags.remove(key);
    }
    AppLogger.log(
        '🧹 ProfileStateManager: Cleared video caches: $keysToRemove');

    // Reload videos directly
    await _loadUserVideosDirect(userId);
    AppLogger.log(
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
