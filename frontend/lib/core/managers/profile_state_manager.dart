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
import 'package:vayu/services/payment_setup_service.dart';
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
  final PaymentSetupService _paymentSetupService = PaymentSetupService();

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
  bool _isVideosLoading = false;
  final Set<String> _selectedVideoIds = {};

  // Controllers
  final TextEditingController nameController = TextEditingController();

  final SmartCacheManager _smartCacheManager = SmartCacheManager();
  bool _smartCacheInitialized = false;

  // Cache configuration
  static const Duration _userProfileCacheTime = Duration(hours: 24);
  static const Duration _userVideosCacheTime = Duration(minutes: 45);

  Future<void> _ensureSmartCacheInitialized() async {
    if (_smartCacheInitialized) return;
    try {
      await _smartCacheManager.initialize();
      _smartCacheInitialized = _smartCacheManager.isInitialized;
      if (_smartCacheInitialized) {
        AppLogger.log(
            '✅ ProfileStateManager: SmartCacheManager ready for profile caching');
      } else {
        AppLogger.log(
            '⚠️ ProfileStateManager: SmartCacheManager initialization skipped or disabled');
      }
    } catch (e) {
      AppLogger.log(
          '⚠️ ProfileStateManager: SmartCacheManager init failed: $e');
      _smartCacheInitialized = false;
    }
  }

  // Getters
  List<VideoModel> get userVideos => _userVideos;
  bool get isLoading => _isLoading;
  String? get error => _error;
  Map<String, dynamic>? get userData => _userData;
  bool get isEditing => _isEditing;
  bool get isSelecting => _isSelecting;
  Set<String> get selectedVideoIds => _selectedVideoIds;
  bool get hasSelectedVideos => _selectedVideoIds.isNotEmpty;
  bool get isVideosLoading => _isVideosLoading;

  // Profile management
  Future<void> loadUserData(String? userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      AppLogger.log(
          '🔄 ProfileStateManager: Loading user data for userId: $userId');

      await _ensureSmartCacheInitialized();

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
        _error = 'No authentication data found';
        notifyListeners();
        return;
      }

      final cacheKey = _resolveProfileCacheKey(userId, loggedInUser);
      final bool isMyProfile = userId == null ||
          userId == loggedInUser['id'] ||
          userId == loggedInUser['googleId'];

      Map<String, dynamic>? userData;

      if (_smartCacheInitialized) {
        AppLogger.log(
            '🧠 ProfileStateManager: Attempting smart cache fetch for $cacheKey (isMyProfile: $isMyProfile)');

        // **ENHANCED: Use longer cache time for other users' profiles (7 days vs 24 hours)**
        final cacheTime = isMyProfile
            ? _userProfileCacheTime // 24 hours for own profile
            : Duration(days: 7); // 7 days for other users' profiles

        userData = await _smartCacheManager.get<Map<String, dynamic>>(
          cacheKey,
          cacheType: 'user_profile',
          maxAge: cacheTime,
          fetchFn: () async {
            final fetched =
                await _fetchProfileData(userId, loggedInUser, cacheKey);
            if (fetched == null) {
              throw Exception('Profile not found for $cacheKey');
            }
            return fetched;
          },
        );
      } else {
        userData = await _fetchProfileData(userId, loggedInUser, cacheKey);
      }

      if (userData == null) {
        AppLogger.log(
            '❌ ProfileStateManager: Profile data not found for cacheKey: $cacheKey');
        _error = 'Unable to load profile data.';
        _isLoading = false;
        notifyListeners();
        return;
      }

      _userData = Map<String, dynamic>.from(userData);
      nameController.text = _userData?['name']?.toString() ?? '';

      AppLogger.log('🔄 ProfileStateManager: Stored user data: $_userData');
      AppLogger.log(
          '🔄 ProfileStateManager: Stored user googleId: ${_userData?['googleId']}');
      AppLogger.log(
          '🔄 ProfileStateManager: Stored user id: ${_userData?['id']}');
      AppLogger.log(
          '🔄 ProfileStateManager: User data keys: ${_userData?.keys.toList()}');
      AppLogger.log(
          '🔄 ProfileStateManager: User data values: ${_userData?.values.toList()}');

      await _hydratePaymentDetailsIfNeeded();

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

  String _resolveProfileCacheKey(
      String? requestedUserId, Map<String, dynamic> loggedInUser) {
    final primaryId = requestedUserId?.trim();
    final fallbackId =
        (loggedInUser['googleId'] ?? loggedInUser['id'])?.toString();
    final resolvedId = (primaryId != null && primaryId.isNotEmpty)
        ? primaryId
        : (fallbackId != null && fallbackId.isNotEmpty ? fallbackId : 'self');
    return 'user_profile_$resolvedId';
  }

  Future<Map<String, dynamic>?> _fetchProfileData(String? requestedUserId,
      Map<String, dynamic> loggedInUser, String cacheKey) async {
    final bool isMyProfile = requestedUserId == null ||
        requestedUserId == loggedInUser['id'] ||
        requestedUserId == loggedInUser['googleId'];

    AppLogger.log('🔄 ProfileStateManager: Is my profile: $isMyProfile');
    AppLogger.log(
        '🔄 ProfileStateManager: userId parameter: $requestedUserId (cacheKey: $cacheKey)');
    AppLogger.log(
        '🔄 ProfileStateManager: loggedInUser id: ${loggedInUser['id']}');
    AppLogger.log(
        '🔄 ProfileStateManager: loggedInUser googleId: ${loggedInUser['googleId']}');

    Map<String, dynamic>? userData;
    if (isMyProfile) {
      final myId = loggedInUser['googleId'] ?? loggedInUser['id'];
      try {
        final backendUser =
            myId != null ? await _userService.getUserById(myId) : null;
        if (backendUser != null) {
          userData = Map<String, dynamic>.from(backendUser);
          AppLogger.log(
              '🔄 ProfileStateManager: Loaded own profile from backend: ${userData['name']}');

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
          userData = Map<String, dynamic>.from(loggedInUser);
        }
      } catch (e) {
        AppLogger.log(
            '⚠️ ProfileStateManager: Failed to fetch own profile from backend, using local: $e');
        userData = Map<String, dynamic>.from(loggedInUser);
      }
    } else {
      try {
        AppLogger.log(
            '🔄 ProfileStateManager: Fetching other user profile for ID: $requestedUserId');
        final otherUser = await _userService.getUserById(requestedUserId);
        userData = Map<String, dynamic>.from(otherUser);
        AppLogger.log(
            '🔄 ProfileStateManager: Other user profile loaded: ${userData['name']}');
      } catch (e) {
        AppLogger.log(
            '⚠️ ProfileStateManager: Failed to fetch other user profile: $e');
      }
    }

    return userData;
  }

  String _resolveVideoCacheKey(String userId) => 'video_profile_$userId';

  List<VideoModel> _deserializeCachedVideos(Map<String, dynamic> payload) {
    final rawVideos = payload['videos'];
    if (rawVideos is List) {
      return rawVideos
          .whereType<Map<dynamic, dynamic>>()
          .map((entry) => VideoModel.fromJson(
              entry.map((key, value) => MapEntry(key.toString(), value))))
          .toList();
    }
    return [];
  }

  Future<List<VideoModel>> _fetchVideosFromServer(
    String userId, {
    required bool isMyProfile,
  }) async {
    List<VideoModel> videos = [];
    try {
      videos = await _videoService.getUserVideos(userId);
    } catch (e) {
      AppLogger.log(
          '⚠️ ProfileStateManager: Primary id fetch failed for $userId: $e');
    }

    if (videos.isEmpty) {
      String? altId;
      if (_userData != null) {
        if (_userData!['googleId'] == userId) {
          altId = _userData!['id'];
        } else if (_userData!['id'] == userId) {
          altId = _userData!['googleId'];
        }
      }

      if ((altId == null || altId.isEmpty) && isMyProfile) {
        final fetchedId = (await _authService.getUserData())?['id']?.toString();
        if (fetchedId != null && fetchedId.isNotEmpty && fetchedId != userId) {
          altId = fetchedId;
        }
      }

      if (altId != null && altId.isNotEmpty) {
        AppLogger.log(
            '🔄 ProfileStateManager: Trying alternate id for fetch: $altId');
        try {
          videos = await _videoService.getUserVideos(altId);
        } catch (e) {
          AppLogger.log(
              '⚠️ ProfileStateManager: Alternate id fetch also failed: $e');
        }
      }
    }

    return videos;
  }

  Future<void> loadUserVideos(String? userId) async {
    AppLogger.log(
        '🔄 ProfileStateManager: loadUserVideos called with userId: $userId');

    _isVideosLoading = true;
    notifyListeners();

    try {
      final loggedInUser = await _authService.getUserData();
      final bool isMyProfile = userId == null ||
          userId == loggedInUser?['id'] ||
          userId == loggedInUser?['googleId'];

      // **FIXED: Properly check feature flag using FeatureFlags.instance**
      if (FeatureFlags.instance.isEnabled(Features.smartVideoCaching)) {
        await _loadUserVideosWithCaching(
          userId,
          isMyProfile: isMyProfile,
        );
      } else {
        await _loadUserVideosDirect(
          userId,
          isMyProfile: isMyProfile,
        );
      }

      // **FIXED: Ensure videos are loaded even if caching fails**
      if (_userVideos.isEmpty) {
        AppLogger.log(
            '⚠️ ProfileStateManager: No videos loaded, trying direct fallback');
        await _loadUserVideosDirect(
          userId,
          isMyProfile: isMyProfile,
        );
      }

      AppLogger.log(
          '✅ ProfileStateManager: loadUserVideos completed with ${_userVideos.length} videos');
    } catch (e) {
      AppLogger.log('❌ ProfileStateManager: Error in loadUserVideos: $e');
      final loggedInUser = await _authService.getUserData();
      final bool isMyProfile = userId == null ||
          userId == loggedInUser?['id'] ||
          userId == loggedInUser?['googleId'];
      // Fallback to direct loading
      await _loadUserVideosDirect(
        userId,
        isMyProfile: isMyProfile,
      );
    } finally {
      _isVideosLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadUserVideosWithCaching(
    String? userId, {
    required bool isMyProfile,
  }) async {
    try {
      AppLogger.log(
          '🔄 ProfileStateManager: Loading videos with smart caching for userId: $userId');

      final loggedInUser = await _authService.getUserData();
      String? resolvedId;
      if (isMyProfile) {
        resolvedId = loggedInUser?['googleId']?.toString();
        if (resolvedId == null || resolvedId.trim().isEmpty) {
          resolvedId = loggedInUser?['id']?.toString();
        }
      } else {
        resolvedId = userId;
      }
      final String targetUserId = resolvedId?.trim() ?? '';

      if (targetUserId.isEmpty) {
        AppLogger.log(
            '⚠️ ProfileStateManager: targetUserId is empty, cannot load videos');
        _userVideos = [];
        notifyListeners();
        return;
      }

      await _ensureSmartCacheInitialized();

      if (_smartCacheInitialized) {
        final smartCacheKey = _resolveVideoCacheKey(targetUserId);
        AppLogger.log(
            '🧠 ProfileStateManager: Fetching videos from smart cache: $smartCacheKey');

        final payload = await _smartCacheManager.get<Map<String, dynamic>>(
          smartCacheKey,
          cacheType: 'videos',
          maxAge: _userVideosCacheTime,
          fetchFn: () async {
            final videos = await _fetchVideosFromServer(
              targetUserId,
              isMyProfile: isMyProfile,
            );
            return {
              'videos':
                  videos.map((video) => video.toJson()).toList(growable: false),
              'fetchedAt': DateTime.now().toIso8601String(),
            };
          },
        );

        if (payload != null) {
          final hydratedVideos = _deserializeCachedVideos(payload);
          _userVideos = hydratedVideos;
          AppLogger.log(
              '⚡ ProfileStateManager: Smart cache served ${_userVideos.length} videos');
          notifyListeners();
          return;
        }
      }

      AppLogger.log(
          '📡 ProfileStateManager: Fetching fresh videos for $targetUserId');
      final videos = await _fetchVideosFromServer(
        targetUserId,
        isMyProfile: isMyProfile,
      );
      _userVideos = videos;
      notifyListeners();
    } catch (e) {
      AppLogger.log('❌ ProfileStateManager: Error in cached video loading: $e');
      await _loadUserVideosDirect(
        userId,
        isMyProfile: isMyProfile,
      );
    }
  }

  /// Load user videos directly without caching (fallback)
  Future<void> _loadUserVideosDirect(
    String? userId, {
    required bool isMyProfile,
  }) async {
    try {
      AppLogger.log(
          '🔄 ProfileStateManager: Loading videos directly for userId: $userId');

      final loggedInUser = await _authService.getUserData();
      AppLogger.log(
          '🔍 ProfileStateManager: Direct loading - isMyProfile: $isMyProfile');
      AppLogger.log(
          '🔍 ProfileStateManager: Direct loading - userId parameter: $userId');
      AppLogger.log(
          '🔍 ProfileStateManager: Direct loading - loggedInUser id: ${loggedInUser?['id']}');
      AppLogger.log(
          '🔍 ProfileStateManager: Direct loading - loggedInUser googleId: ${loggedInUser?['googleId']}');

      // Build a prioritized list of IDs to try (googleId then Mongo _id, then provided userId)
      final candidateIds = <String?>[
        if (isMyProfile) loggedInUser?['googleId']?.toString(),
        if (isMyProfile) loggedInUser?['id']?.toString(),
        if (!isMyProfile) userId?.toString(),
        if (!isMyProfile) _userData?['googleId']?.toString(),
        if (!isMyProfile) _userData?['id']?.toString(),
      ]
          .whereType<String>()
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toSet()
          .toList();

      AppLogger.log(
          '🔍 ProfileStateManager: Direct loading - idsToTry: $candidateIds');

      _userVideos = [];
      for (final candidateId in candidateIds) {
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
          await _ensureSmartCacheInitialized();
          if (_smartCacheInitialized) {
            await _smartCacheManager.invalidateVideoCache();
            AppLogger.log(
                '🗑️ ProfileStateManager: Invalidated SmartCacheManager video cache after deletion');

            if (_userData != null) {
              final userId =
                  (_userData!['googleId'] ?? _userData!['id'])?.toString();
              if (userId != null && userId.isNotEmpty) {
                final smartKey = _resolveVideoCacheKey(userId);
                await _smartCacheManager.clearCacheByPattern(smartKey);
                AppLogger.log(
                    '🧹 ProfileStateManager: Cleared SmartCache for videos after deletion');
              }
            }
          }
        } catch (e) {
          AppLogger.log(
              '⚠️ ProfileStateManager: Failed to invalidate cache: $e');
        }

        // Proactively refresh from server to ensure DB state is reflected immediately
        try {
          final refreshUserId = _userData?['googleId'] ?? _userData?['id'];
          if (refreshUserId != null && refreshUserId.toString().isNotEmpty) {
            await _loadUserVideosDirect(
              refreshUserId,
              isMyProfile: true,
            );
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

        // Clear smart cache to force fresh data fetch
        await _ensureSmartCacheInitialized();
        if (_smartCacheInitialized) {
          final smartKey = 'user_profile_$googleId';
          await _smartCacheManager.clearCacheByPattern(smartKey);
          AppLogger.log(
              '🧹 ProfileStateManager: Cleared SmartCache after profile update');
        }

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

      // **FIXED: Clear smart cache entries**
      await _ensureSmartCacheInitialized();
      if (_smartCacheInitialized) {
        await _smartCacheManager.clearCache();
      }

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

  bool get hasUpiId {
    final upi = _userData?['paymentDetails']?['upiId'];
    return upi is String && upi.trim().isNotEmpty;
  }

  Future<void> ensurePaymentDetailsHydrated() async {
    await _hydratePaymentDetailsIfNeeded();
  }

  Future<void> saveUpiIdQuick(String upiId) async {
    final sanitizedUpiId = upiId.trim().toLowerCase();
    if (sanitizedUpiId.isEmpty) {
      throw Exception('UPI ID cannot be empty');
    }

    await _paymentSetupService.updateUpiId(sanitizedUpiId);
    await _paymentSetupService.markPaymentSetupCompleted();

    _userData ??= {};
    final paymentDetails =
        Map<String, dynamic>.from(_userData?['paymentDetails'] ?? {});
    paymentDetails['upiId'] = sanitizedUpiId;
    _userData!['paymentDetails'] = paymentDetails;
    _userData!['preferredPaymentMethod'] = 'upi';
    notifyListeners();
  }

  Future<void> _hydratePaymentDetailsIfNeeded() async {
    try {
      if (_userData == null) return;
      final currentDetails = _userData?['paymentDetails'];
      if (currentDetails is Map<String, dynamic> &&
          (currentDetails['upiId']?.toString().isNotEmpty ?? false)) {
        return;
      }

      final profile = await _paymentSetupService.fetchPaymentProfile();
      if (profile == null) return;

      final paymentDetails = profile['paymentDetails'];
      if (paymentDetails is Map<String, dynamic>) {
        _userData!['paymentDetails'] =
            Map<String, dynamic>.from(paymentDetails);
        final preferredMethod =
            profile['creator']?['preferredPaymentMethod']?.toString();
        if (preferredMethod != null && preferredMethod.isNotEmpty) {
          _userData!['preferredPaymentMethod'] = preferredMethod;
        }
        notifyListeners();
      }
    } catch (e) {
      AppLogger.log(
          '⚠️ ProfileStateManager: Failed to hydrate payment details: $e');
    }
  }

  /// Force refresh videos only (for when new videos are uploaded)
  Future<void> refreshVideosOnly() async {
    _isVideosLoading = true;
    notifyListeners();

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
        final String resolvedUserId = targetUserId;
        final authUser = await _authService.getUserData();
        final bool refreshIsMyProfile =
            resolvedUserId == authUser?['id']?.toString() ||
                resolvedUserId == authUser?['googleId']?.toString();
        await _ensureSmartCacheInitialized();
        if (_smartCacheInitialized) {
          final smartKey = _resolveVideoCacheKey(resolvedUserId);
          await _smartCacheManager.clearCacheByPattern(smartKey);
          AppLogger.log(
              '🧹 ProfileStateManager: Cleared SmartCache for key: $smartKey');

          final payload = await _smartCacheManager.get<Map<String, dynamic>>(
            smartKey,
            cacheType: 'videos',
            maxAge: _userVideosCacheTime,
            fetchFn: () async {
              final videos = await _fetchVideosFromServer(
                resolvedUserId,
                isMyProfile: refreshIsMyProfile,
              );
              return {
                'videos': videos
                    .map((video) => video.toJson())
                    .toList(growable: false),
                'fetchedAt': DateTime.now().toIso8601String(),
              };
            },
          );

          if (payload != null) {
            _userVideos = _deserializeCachedVideos(payload);
            notifyListeners();
            AppLogger.log(
                '✅ ProfileStateManager: Videos refreshed via SmartCache. Count: ${_userVideos.length}');
            return;
          }
        }

        // Fallback: fetch directly and update state (SmartCache disabled or fetch failed)
        final videos = await _fetchVideosFromServer(
          resolvedUserId,
          isMyProfile: refreshIsMyProfile,
        );
        _userVideos = videos;
        notifyListeners();
        AppLogger.log(
            '✅ ProfileStateManager: Videos refreshed directly. Count: ${videos.length}');
      } else {
        AppLogger.log(
            '⚠️ ProfileStateManager: No valid user ID for video refresh');
      }
    } catch (e) {
      AppLogger.log('❌ ProfileStateManager: Error refreshing videos: $e');
      _error = 'Failed to refresh videos: ${e.toString()}';
      notifyListeners();
    } finally {
      _isVideosLoading = false;
      notifyListeners();
    }
  }

  /// Add a new video to the profile (called after successful upload)
  void addNewVideo(VideoModel video) {
    AppLogger.log(
        '➕ ProfileStateManager: Adding new video to profile: ${video.videoName}');
    _userVideos.insert(0, video); // Add to the beginning of the list

    if (_userData != null) {
      final userId = (_userData!['googleId'] ?? _userData!['id'])?.toString();
      if (userId != null && userId.isNotEmpty) {
        Future.microtask(() async {
          await _ensureSmartCacheInitialized();
          if (_smartCacheInitialized) {
            final smartKey = _resolveVideoCacheKey(userId);
            await _smartCacheManager.clearCacheByPattern(smartKey);
            AppLogger.log(
                '🧹 ProfileStateManager: Cleared SmartCache after adding new video');
          }
        });
      }
    }

    notifyListeners();
  }

  /// Remove a video from the profile
  void removeVideo(String videoId) {
    AppLogger.log(
        '➖ ProfileStateManager: Removing video from profile: $videoId');
    _userVideos.removeWhere((video) => video.id == videoId);

    if (_userData != null) {
      final userId = (_userData!['googleId'] ?? _userData!['id'])?.toString();
      if (userId != null && userId.isNotEmpty) {
        Future.microtask(() async {
          await _ensureSmartCacheInitialized();
          if (_smartCacheInitialized) {
            final smartKey = _resolveVideoCacheKey(userId);
            await _smartCacheManager.clearCacheByPattern(smartKey);
            AppLogger.log(
                '🧹 ProfileStateManager: Cleared SmartCache after removing video');
          }
        });
      }
    }

    notifyListeners();
  }

  // Cleanup
  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }
}
