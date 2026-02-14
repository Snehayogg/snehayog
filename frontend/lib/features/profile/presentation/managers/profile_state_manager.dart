import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/features/video/presentation/managers/video_provider.dart';
import 'package:vayu/features/video/video_model.dart';
import 'package:vayu/features/auth/data/services/authservices.dart';
import 'package:vayu/shared/services/cloudflare_r2_service.dart';
import 'package:vayu/features/profile/data/services/user_service.dart';
import 'package:vayu/features/profile/data/services/payment_setup_service.dart';
import 'package:vayu/features/video/data/services/video_service.dart';
import 'package:vayu/features/ads/data/services/ad_service.dart';

import 'package:vayu/features/profile/data/datasources/profile_local_datasource.dart';
import 'package:vayu/shared/managers/smart_cache_manager.dart';
import 'package:vayu/shared/utils/app_logger.dart';

// Import for unawaited

class ProfileStateManager extends ChangeNotifier {
  final VideoService _videoService = VideoService();
  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  final PaymentSetupService _paymentSetupService = PaymentSetupService();
  final ProfileLocalDataSource _localDataSource = ProfileLocalDataSource();
  final SmartCacheManager _smartCacheManager = SmartCacheManager();
  bool _smartCacheInitialized = false;

  // BuildContext to access VideoProvider
  BuildContext? _context;

  // Set context when needed
  void setContext(BuildContext context) {
    if (_context == context) return;
    _context = context;
  }


  // State variables
  List<VideoModel> _userVideos = [];
  bool _isLoading = false;
  bool _isPhotoLoading = false;
  String? _error;
  Map<String, dynamic>? _userData;
  bool _isEditing = false;
  bool _isSelecting = false;
  bool _isVideosLoading = false;
  final Set<String> _selectedVideoIds = {};
  String? _requestedUserId;
  
  // Earnings state
  double _cachedEarnings = 0.0;
  bool _isEarningsLoading = false;


  // Controllers
  final TextEditingController nameController = TextEditingController();

  // Cache configuration removed

  // Cache configuration
  static const Duration _userProfileCacheTime = Duration(hours: 24);
  static const Duration _userVideosCacheTime = Duration(minutes: 30);


  // Video Stats
  int _totalVideoCount = 0;
  
  // Pagination State
  int _currentPage = 1;
  bool _isFetchingMore = false;
  bool _hasMoreVideos = true;
  static const int _pageSize = 1000;


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
  bool get isPhotoLoading => _isPhotoLoading;
  double get cachedEarnings => _cachedEarnings;
  bool get isEarningsLoading => _isEarningsLoading;
  int get totalVideoCount => _totalVideoCount;
  bool get isFetchingMore => _isFetchingMore;
  bool get hasMoreVideos => _hasMoreVideos;

  /// **NEW: Check if the current user is the owner of the viewed profile**
  bool get isOwner {
    if (_requestedUserId == null) return true; // null means own profile
    
    // Check if we have logged in user data to compare
    final myId = _authService.currentUserId; 
    if (myId == null) return false;
    
    return _requestedUserId == myId.toString();
  }


  // Profile management
  Future<void> loadUserData(String? userId,
      {bool forceRefresh = false, bool silent = false}) async {
    _requestedUserId = userId; // Store for isOwner check
    
    if (!silent) {
      _isLoading = true;
      _error = null;
      notifyListeners();
    }

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

      // **PARALLEL OPTIMIZATION: Start loading videos IMMEDIATELY**
      // Now that we have the loggedInUser, we can determine the correct ID and start video loading.
      // Don't wait for profile data to load. This eliminates the waterfall.
      if (userId != null) {
        // If we have an explicit userId (viewing other creator), start loading their videos now
        AppLogger.log('🚀 ProfileStateManager: Starting PARALLEL video load for $userId');
        loadUserVideos(userId, forceRefresh: forceRefresh, silent: silent).catchError((e) {
             AppLogger.log('⚠️ ProfileStateManager: Parallel video load error: $e');
        });
      } else if (loggedInUser != null) {
        // If viewing own profile, derive ID from logged in user
        final myId = loggedInUser['googleId'] ?? loggedInUser['id'];
        if (myId != null) {
           AppLogger.log('🚀 ProfileStateManager: Starting PARALLEL video load for own profile ($myId)');
           loadUserVideos(myId.toString(), forceRefresh: forceRefresh, silent: silent).catchError((e) {
              AppLogger.log('⚠️ ProfileStateManager: Parallel video load error: $e');
           });
        }
      }

      // **HIVE CACHE: Check for persistent data first**
      if (!forceRefresh) {
        final cachedData = await _localDataSource.getCachedUserData(userId ?? loggedInUser?['id'] ?? loggedInUser?['googleId'] ?? 'self');
        if (cachedData != null) {
          AppLogger.log('📦 ProfileStateManager: Found Hive cache for profile');
          _userData = _normalizeUserData(cachedData, userId);
          _totalVideoCount = _userData?['totalVideos'] ?? _userData?['videosCount'] ?? 0;
          nameController.text = _userData?['name']?.toString() ?? '';
          _isLoading = false;
          notifyListeners();
          
          // If cache is fresh enough, skip network fetch (silent refresh still happens below)
          // Profile caching is long-term, so we usually silent refresh.
        }
      }

      // **FIXED: Allow loading creator profiles without authentication**
      // Only require authentication for own profile (userId == null)
      final bool isMyProfile = userId == null ||
          (loggedInUser != null &&
              (userId == loggedInUser['id'] ||
                  userId == loggedInUser['googleId']));

      if (isMyProfile && loggedInUser == null) {
        AppLogger.log(
            '❌ ProfileStateManager: No authentication data available for own profile');
        _isLoading = false;
        _error = 'No authentication data found';
        notifyListeners();
        return;
      }

      // **FIXED: For creator profiles, use userId directly if no logged in user**
      final cacheKey = loggedInUser != null
          ? _resolveProfileCacheKey(userId, loggedInUser)
          : 'user_profile_${userId ?? 'unknown'}';

      Map<String, dynamic>? userData;

      // **SMART CACHE (Memory)**
      if (_smartCacheInitialized && !forceRefresh) {
        userData = await _smartCacheManager.get<Map<String, dynamic>>(
          cacheKey,
          cacheType: 'user_profile',
          maxAge: _userProfileCacheTime,
          fetchFn: () async {
            final userForFetch = loggedInUser ?? <String, dynamic>{};
            final data = await _fetchProfileData(userId, userForFetch, cacheKey);
            return data ?? <String, dynamic>{};
          },
        );
      } else {
        final userForFetch = loggedInUser ?? <String, dynamic>{};
        userData = await _fetchProfileData(userId, userForFetch, cacheKey);
      }

      if (userData == null || userData.isEmpty) {
        AppLogger.log(
            '❌ ProfileStateManager: Profile data not found for cacheKey: $cacheKey');
        if (_userData == null) {
          _error = 'Unable to load profile data.';
          _isLoading = false;
          notifyListeners();
        }
        return;
      }

      // **FIXED: Always normalize user data (even from cache)**
      // This ensures that preloaded data (cached by ProfilePreloader) has all required fields like googleId
      final normalizedData = _normalizeUserData(userData, userId ?? userData['googleId'] ?? userData['id']);
      _userData = Map<String, dynamic>.from(normalizedData);
      nameController.text = _userData?['name']?.toString() ?? '';

      // **HIVE SAVE: Persist profile for cold start**
      unawaited(_localDataSource.cacheUserData(userId ?? _userData!['googleId'] ?? _userData!['id'] ?? 'self', _userData!));
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

  /// **NEW: Resolve cache key for video list**
  String _resolveVideoCacheKey(String? userId) {
    final effectiveId = userId?.trim();
    if (effectiveId == null || effectiveId.isEmpty) {
      return 'user_videos_unknown';
    }
    return 'user_videos_$effectiveId';
  }

  Future<Map<String, dynamic>?> _fetchProfileData(String? requestedUserId,
      Map<String, dynamic> loggedInUser, String cacheKey) async {
    // **FIXED: Handle empty loggedInUser for creator profiles**
    final bool hasLoggedInUser = loggedInUser.isNotEmpty &&
        (loggedInUser.containsKey('id') ||
            loggedInUser.containsKey('googleId'));

    final bool isMyProfile = requestedUserId == null ||
        (hasLoggedInUser &&
            (requestedUserId == loggedInUser['id'] ||
                requestedUserId == loggedInUser['googleId']));

    AppLogger.log('🔄 ProfileStateManager: Is my profile: $isMyProfile');
    AppLogger.log(
        '🔄 ProfileStateManager: userId parameter: $requestedUserId (cacheKey: $cacheKey)');
    if (hasLoggedInUser) {
      AppLogger.log(
          '🔄 ProfileStateManager: loggedInUser id: ${loggedInUser['id']}');
      AppLogger.log(
          '🔄 ProfileStateManager: loggedInUser googleId: ${loggedInUser['googleId']}');
    } else {
      AppLogger.log(
          '🔄 ProfileStateManager: No logged in user (viewing creator profile)');
    }

    Map<String, dynamic>? userData;
    if (isMyProfile) {
      // **FIXED: Only access loggedInUser fields if user is logged in**
      if (!hasLoggedInUser) {
        AppLogger.log(
            '❌ ProfileStateManager: Cannot load own profile without authentication');
        return null;
      }

      final myId = loggedInUser['googleId'] ?? loggedInUser['id'];
      try {
        final backendUser =
            myId != null ? await _userService.getUserById(myId) : null;
        if (backendUser != null) {
          // **FIXED: getUserById returns Map, ensure all fields are present**
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
           // **FIX: If backend fetch returns null (e.g. 404), throw error instead of fallback**
           // This allows loadUserData to keep cached data instead of overwriting with basic auth data
           throw Exception('Backend returned null for user profile');
        }
      } catch (e) {
        AppLogger.log(
            '⚠️ ProfileStateManager: Failed to fetch own profile from backend: $e');
        // **CRITICAL FIX: Do NOT fall back to basic auth data here**
        // Rethrow so loadUserData knows the fetch failed and can preserve cached data
        rethrow;
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
        rethrow;
      }
    }

    return userData;
  }

  /// **NEW: Normalize user data fields for consistency**
  Map<String, dynamic> _normalizeUserData(Map<String, dynamic> data, String? requestedUserId) {
    final Map<String, dynamic> normalized = Map<String, dynamic>.from(data);

    // 1. Normalize Google ID (Backend returns it as 'id')
    final actualGoogleId = normalized['googleId'] ??
        normalized['id'] ??
        requestedUserId;
    normalized['googleId'] = actualGoogleId;

    if (!normalized.containsKey('id')) {
      normalized['id'] = actualGoogleId;
    }

    // 2. Normalize Follower Counts
    final followersCount = normalized['followersCount'] ?? normalized['followers'] ?? 0;
    normalized['followersCount'] = followersCount;
    normalized['followers'] = followersCount;

    final followingCount = normalized['followingCount'] ?? normalized['following'] ?? 0;
    normalized['followingCount'] = followingCount;
    normalized['following'] = followingCount;

    // 3. Normalize Rank
    final rank = normalized['rank'] ?? 0;
    normalized['rank'] = rank;

    return normalized;
  }



  Future<List<VideoModel>> _fetchVideosFromServer(
    String userId, {
    required bool isMyProfile,
    bool forceRefresh = false,
    int page = 1,
  }) async {
    List<VideoModel> videos = [];
    try {
      videos = await _videoService.getUserVideos(userId, forceRefresh: forceRefresh, page: page, limit: _pageSize);
    } catch (e) {
      AppLogger.log(
          '⚠️ ProfileStateManager: Primary id fetch failed for $userId: $e');
      // Rethrow to allow caller to handle error (and preserve cache)
      rethrow;
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
          videos = await _videoService.getUserVideos(altId, forceRefresh: forceRefresh, page: page, limit: _pageSize);
        } catch (e) {
          AppLogger.log(
              '⚠️ ProfileStateManager: Alternate id fetch also failed: $e');
        }
      }
    }

    return videos;
  }

  Future<void> loadMoreVideos() async {
    if (_isLoading || _isFetchingMore || !_hasMoreVideos) return;
    
    // Determine userId
    final userId = _userData?['googleId'] ?? _userData?['id'];
    if (userId == null) return;
    
    _isFetchingMore = true;
    notifyListeners();
    
    await loadUserVideos(userId, page: _currentPage + 1);
  }

  /// **NEW: Load all remaining videos in background**
  Future<void> loadAllVideosInBackground(String userId) async {
    if (!_hasMoreVideos || _isFetchingMore) return;
    
    AppLogger.log('🚀 ProfileStateManager: Starting recursive background load...');
    
    // We'll load in batches until exhausted
    int maxSafetyPages = 50; // Safety guard to prevent infinite loops (50 * 1000 = 50k videos)
    int pagesLoaded = 0;

    while (_hasMoreVideos && !isDisposed && pagesLoaded < maxSafetyPages) {
      try {
        await loadUserVideos(userId, page: _currentPage + 1, silent: true);
        pagesLoaded++;
        // Small delay to prevent hammering the server
        await Future.delayed(const Duration(milliseconds: 300));
      } catch (e) {
        AppLogger.log('⚠️ ProfileStateManager: Background load error: $e');
        _hasMoreVideos = false; // Stop loop on error
        break;
      }
    }
    
    if (pagesLoaded >= maxSafetyPages) {
       AppLogger.log('⚠️ ProfileStateManager: Hit safety guard limit (50 pages). Stopping.');
       _hasMoreVideos = false;
    }
    
    AppLogger.log('✅ ProfileStateManager: Background load finished. Total videos: ${_userVideos.length}');
  }

  // Track disposal for background tasks
  bool _isDisposed = false;
  bool get isDisposed => _isDisposed;

  Future<void> loadUserVideos(String? userId,
      {bool forceRefresh = false, bool silent = false, int page = 1}) async {
    AppLogger.log(
        '🔄 ProfileStateManager: loadUserVideos called with userId: $userId, page: $page, forceRefresh: $forceRefresh');

    if (page == 1) {
      _currentPage = 1;
      _hasMoreVideos = true;
      if (!silent) {
        _isVideosLoading = true;
        notifyListeners();
      }
    } else {
        _currentPage = page;
    }

    try {
      final loggedInUser = await _authService.getUserData();
      final bool isMyProfile = userId == null ||
          userId == loggedInUser?['id'] ||
          userId == loggedInUser?['googleId'];

      // **Always load videos fresh from API**
      await _loadUserVideosDirect(
        userId,
        isMyProfile: isMyProfile,
        silent: silent,
        page: page,
      );

      AppLogger.log(
          '✅ ProfileStateManager: loadUserVideos completed with ${_userVideos.length} videos');

      AppLogger.log(
          '✅ ProfileStateManager: loadUserVideos completed with ${_userVideos.length} videos');
    } catch (e) {
      AppLogger.log('❌ ProfileStateManager: Error in loadUserVideos: $e');
      
      // **FIX: Stop background loop on connection errors**
      final errorStr = e.toString().toLowerCase();
      final isNetworkError = errorStr.contains('socket') || 
                            errorStr.contains('network') || 
                            errorStr.contains('connection');
      if (isNetworkError) {
        _hasMoreVideos = false;
        AppLogger.log('🛑 ProfileStateManager: Network error detected. Stopping pagination.');
        if (_userVideos.isEmpty) {
           _error = 'Network error. Please check your connection.';
        }
      } else {
        // Fallback to direct loading only for non-network errors
        final loggedInUser = await _authService.getUserData();
        final bool isMyProfile = userId == null ||
            userId == loggedInUser?['id'] ||
            userId == loggedInUser?['googleId'];
        
        await _loadUserVideosDirect(
          userId,
          isMyProfile: isMyProfile,
          silent: silent,
          page: page,
        );
      }
    } finally {
      // Load earnings and update counts BEFORE turning off video loading
      // This ensures _isEarningsLoading becomes true before _isVideosLoading becomes false
      // preventing the UI from briefly showing "0" (Loading Gap)
      if (_userVideos.isNotEmpty) {
        // **FIX: Robust Total Video Count Logic**
        int? count;
        
        // 1. Try uploader.totalVideos from the video list (from aggregation)
        if (_userVideos.first.uploader.totalVideos != null && 
            _userVideos.first.uploader.totalVideos! > 0) {
          count = _userVideos.first.uploader.totalVideos;
        } 
        
        // 2. Try userData['videosCount'] or similar fields if #1 failed
        if (count == null && _userData != null) {
           final userVideoCount = _userData!['videosCount'] ?? 
                                 _userData!['totalVideos'] ?? 
                                 _userData!['videoCount'];
           if (userVideoCount is int && userVideoCount > 0) {
             count = userVideoCount;
           }
        }

        // 3. Fallback to list length if everything else fails
        _totalVideoCount = count ?? _userVideos.length;
        
        AppLogger.log(
              '📊 ProfileStateManager: Final Total Video Count: $_totalVideoCount (Source: ${count != null ? "Backend/User" : "List Length"})');

        // Ignore unawaited futures to allow UI to update while earnings load in background
        // ignore: unawaited_futures
        _loadEarnings(forceRefresh: forceRefresh);
      } else {
        // Even if videos are empty, check if userData has a count (e.g. all deleted but count not updated?)
        // Or just set to 0
        if (_userData != null) {
           final userVideoCount = _userData!['videosCount'] ?? 
                                 _userData!['totalVideos'] ?? 
                                 _userData!['videoCount'];
           if (userVideoCount is int) {
             _totalVideoCount = userVideoCount;
           } else {
             _totalVideoCount = 0;
           }
        } else {
          _totalVideoCount = 0;
        }
      }

      _isFetchingMore = false;
      if (_isVideosLoading) {
        _isVideosLoading = false;
        notifyListeners();
      }
    }
  }

  /// Load earnings for the current video set
  /// **UPDATED: Aligns with Admin Dashboard & Revenue Screen (Current Month Earnings)**
  Future<void> _loadEarnings({bool forceRefresh = false}) async {
    try {
      _isEarningsLoading = true;
      notifyListeners();

      if (_userVideos.isEmpty) {
        _cachedEarnings = 0.0;
        _isEarningsLoading = false;
        notifyListeners();
        return;
      }

      double earnings = 0.0;
      bool usedBackend = false;

      // 1. Determine if this is "my" profile
      final loggedInUser = await _authService.getUserData();
      bool isMyProfile = false;
      if (_userData != null && loggedInUser != null) {
        final profileId = _userData!['googleId']?.toString() ?? _userData!['id']?.toString();
        final myId = loggedInUser['googleId']?.toString() ?? loggedInUser['id']?.toString();
        // Loose comparison
        isMyProfile = (profileId != null && myId != null && profileId == myId);
      }

      // 2. Try fetching Monthly Summary from Backend (Only for own profile)
      // This matches CreatorRevenueScreen logic exactly
      if (isMyProfile) {
        try {
          final adService = AdService();
          final summary = await adService.getCreatorRevenueSummary(forceRefresh: forceRefresh);
          // Summary returns { 'thisMonth': double, 'lastMonth': double, ... }
          if (summary.containsKey('thisMonth')) {
             final thisMonth = summary['thisMonth'];
             if (thisMonth is num && thisMonth > 0) {
                 earnings = thisMonth.toDouble();
                 usedBackend = true;
                 AppLogger.log('💰 ProfileStateManager: Using AdService monthly earnings: ₹$earnings');
             }
          }
        } catch (e) {
          AppLogger.log('⚠️ ProfileStateManager: AdService fetch failed: $e');
        }
      }

      // 3. Fallback: REMOVED Client-Side Calculation
      // We rely solely on the backend. If backend fails or returns nothing, we show 0.
      // 3. Fallback: Check uploader.earnings (sent by backend for this profile)
      // This is the "Current Month Earnings" calculated by the backend for public display/profile header
      if (!usedBackend && _userVideos.isNotEmpty) {
          final uploaderEarnings = _userVideos.first.uploader.earnings;
          if (uploaderEarnings != null && uploaderEarnings > 0) {
             earnings = uploaderEarnings;
             usedBackend = true; // technically came from backend via video list
             AppLogger.log('💰 ProfileStateManager: Using uploader.earnings from video list: ₹$earnings');
          }
      }

      // 4. Fallback: Aggregate from per-video earnings if no summary
      if (!usedBackend) {
          double aggregated = 0.0;
          for (var video in _userVideos) {
            aggregated += video.earnings;
          }
          earnings = aggregated;
          AppLogger.log('💰 ProfileStateManager: Aggregated earnings from video list: ₹$earnings');
      }

      _cachedEarnings = earnings;
      _isEarningsLoading = false;
      notifyListeners();
    } catch (e) {
      AppLogger.log('⚠️ ProfileStateManager: Failed to calculate earnings: $e');
      _isEarningsLoading = false;
      notifyListeners();
    }
  }

  Future<void> _ensureSmartCacheInitialized() async {
    if (_smartCacheInitialized) return;
    try {
      await _smartCacheManager.initialize();
      _smartCacheInitialized = _smartCacheManager.isInitialized;
    } catch (e) {
      AppLogger.log('⚠️ ProfileStateManager: SmartCache init failed: $e');
      _smartCacheInitialized = false;
    }
  }




  /// Load user videos directly without caching (fallback)
  Future<void> _loadUserVideosDirect(
    String? userId, {
    required bool isMyProfile,
    bool silent = false,
    int page = 1,
  }) async {
    try {
      AppLogger.log(
          '📡 ProfileStateManager: Direct loading videos for $userId (Page $page)');

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
        return;
      }

      final videos = await _fetchVideosFromServer(
        targetUserId,
        isMyProfile: isMyProfile,
        forceRefresh: true,
        page: page,
      );

      if (page == 1) {
         _userVideos = videos;
      } else {
         _getAllVideosUnique(videos);
      }
      
      _hasMoreVideos = videos.length >= _pageSize;
      notifyListeners();
    } catch (e) {
      AppLogger.log('❌ ProfileStateManager: Error in direct video loading: $e');
      // **FIX: Stop background loop on failure**
      _hasMoreVideos = false;
      if (_userVideos.isEmpty) {
        _userVideos = [];
        _error = 'Failed to load videos directly.';
      }
      notifyListeners();
    }
  }

  void _getAllVideosUnique(List<VideoModel> newVideos) {
    if (newVideos.isEmpty) return;
    
    final existingIds = _userVideos.map((v) => v.id).toSet();
    for (var video in newVideos) {
      if (!existingIds.contains(video.id)) {
        _userVideos.add(video);
        existingIds.add(video.id);
      }
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
        _isLoading = true;
        notifyListeners();

        final newName = nameController.text.trim();
        await _saveProfileData(newName, _userData!['profilePic']);

        _userData!['name'] = newName;
        _isEditing = false;
        _isLoading = false;
        notifyListeners();

        nameController.clear();
        notifyListeners();
      } catch (e) {
        _isLoading = false;
        _error = 'Failed to save profile: ${e.toString()}';
        notifyListeners();
      }
    }
  }

  Future<void> updateProfilePhoto(String? profilePicPath) async {
    if (_userData != null && profilePicPath != null) {
      try {
        _isPhotoLoading = true;
        notifyListeners();

        // Check if it's already a URL (http/https)
        if (profilePicPath.startsWith('http')) {
          // Already a URL, just save it
          AppLogger.log(
              '✅ ProfileStateManager: Photo is already a URL, saving directly');
          await _saveProfileData(_userData!['name'], profilePicPath);
          _userData!['profilePic'] = profilePicPath;
          _isPhotoLoading = false;
          notifyListeners();
          return;
        }

        // It's a local file path, need to upload it first
        AppLogger.log(
            '📤 ProfileStateManager: Uploading local file to cloud storage...');
        final cloudinaryService = CloudflareR2Service();
        final uploadedUrl = await cloudinaryService.uploadImage(
          File(profilePicPath),
          folder: 'snehayog/profile',
        );

        AppLogger.log(
            '✅ ProfileStateManager: Photo uploaded successfully: $uploadedUrl');

        // Now save the URL to backend
        await _saveProfileData(_userData!['name'], uploadedUrl);
        _userData!['profilePic'] = uploadedUrl;
        _isPhotoLoading = false;
        notifyListeners();
        AppLogger.log(
            '✅ ProfileStateManager: Profile photo updated successfully');
      } catch (e) {
        _isPhotoLoading = false;
        AppLogger.log(
            '❌ ProfileStateManager: Error uploading profile photo: $e');
        notifyListeners();
        rethrow;
      }
    }
  }

  // Video selection management
  void toggleVideoSelection(String videoId) {
    if (!isOwner) return;
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
    if (!isOwner) return;
    AppLogger.log('🔍 enterSelectionMode called');
    _isSelecting = true;
    notifyListeners();
  }

  Future<void> deleteSelectedVideos() async {
    if (!isOwner || _selectedVideoIds.isEmpty) return;

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
    if (!isOwner) return false;
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
    final paymentDetails = _userData?['paymentDetails'];
    if (paymentDetails == null) return false;
    
    final upiId = paymentDetails['upiId'];
    return upiId is String && upiId.trim().isNotEmpty;
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

  List<VideoModel> _deserializeCachedVideos(Map<String, dynamic> payload) {
    try {
      if (payload.containsKey('videos')) {
        final videosList = payload['videos'] as List;
        return videosList
            .map((v) => VideoModel.fromJson(Map<String, dynamic>.from(v)))
            .toList();
      }
    } catch (e) {
      AppLogger.log('⚠️ ProfileStateManager: Error deserializing cached videos: $e');
    }
    return [];
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

  /// **NEW: Update follower count in userData (called when follow/unfollow happens)**
  void updateFollowerCount(String userId, {required bool increment}) {
    if (_userData == null) {
      AppLogger.log(
          '⚠️ ProfileStateManager: Cannot update follower count - userData is null');
      return;
    }

    final trimmedUserId = userId.trim();

    // Try multiple ID formats for comparison
    final profileGoogleId = _userData!['googleId']?.toString().trim();
    final profileId = _userData!['id']?.toString().trim();
    final profileMongoId = _userData!['_id']?.toString().trim();

    AppLogger.log(
        '🔄 ProfileStateManager: updateFollowerCount called for userId: $trimmedUserId');
    AppLogger.log(
        '🔄 ProfileStateManager: Profile googleId: $profileGoogleId, id: $profileId, _id: $profileMongoId');

    // Check if the userId matches any of the profile's IDs
    final isMatch = trimmedUserId == profileGoogleId ||
        trimmedUserId == profileId ||
        trimmedUserId == profileMongoId ||
        profileGoogleId == trimmedUserId ||
        profileId == trimmedUserId ||
        profileMongoId == trimmedUserId;

    if (!isMatch) {
      AppLogger.log(
          '⚠️ ProfileStateManager: UserId mismatch - skipping follower count update. Requested: $trimmedUserId, Profile: googleId=$profileGoogleId, id=$profileId, _id=$profileMongoId');
      return;
    }

    // Get current follower count
    final currentFollowersRaw =
        _userData!['followersCount'] ?? _userData!['followers'] ?? 0;
    final currentFollowers = currentFollowersRaw is int
        ? currentFollowersRaw
        : (int.tryParse(currentFollowersRaw.toString()) ?? 0);

    // Calculate new follower count
    final newFollowers = increment
        ? currentFollowers + 1
        : (currentFollowers - 1).clamp(0, double.infinity);

    // Update both fields to ensure consistency
    _userData!['followersCount'] = newFollowers;
    _userData!['followers'] = newFollowers;

    AppLogger.log(
        '✅ ProfileStateManager: Updated follower count for $trimmedUserId: $currentFollowers → $newFollowers (${increment ? 'increment' : 'decrement'})');

    notifyListeners();
  }

  // Cleanup
  @override
  void dispose() {
    _isDisposed = true; // Mark as disposed for background tasks
    
    
    nameController.dispose();
    super.dispose();
  }
}
