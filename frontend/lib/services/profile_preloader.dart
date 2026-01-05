import 'dart:async';
import 'package:vayu/services/user_service.dart';
import 'package:vayu/services/video_service.dart';
import 'package:vayu/utils/app_logger.dart';
import 'package:vayu/core/managers/smart_cache_manager.dart';

/// **PROFILE PRELOADER**
/// Preloads profile data for any user (especially other creators)
/// This ensures instant profile screen loading when user navigates to it
/// **OPTIMIZED: Uses SmartCacheManager for unified caching with ProfileStateManager**
class ProfilePreloader {
  static final ProfilePreloader _instance = ProfilePreloader._internal();
  factory ProfilePreloader() => _instance;
  ProfilePreloader._internal();

  final UserService _userService = UserService();
  final VideoService _videoService = VideoService();
  final SmartCacheManager _cacheManager = SmartCacheManager();
  bool _cacheInitialized = false;

  // Track preloading state to avoid duplicate requests
  final Set<String> _preloadingProfiles = {};
  final Set<String> _preloadedProfiles = {};

  /// **INITIALIZE CACHE MANAGER**
  Future<void> _ensureCacheInitialized() async {
    if (_cacheInitialized) return;
    try {
      await _cacheManager.initialize();
      _cacheInitialized = _cacheManager.isInitialized;
      if (_cacheInitialized) {
        AppLogger.log('✅ ProfilePreloader: SmartCacheManager initialized');
      }
    } catch (e) {
      AppLogger.log('⚠️ ProfilePreloader: Cache init failed: $e');
      _cacheInitialized = false;
    }
  }

  /// **PRELOAD PROFILE: Preload any user's profile data**
  /// This is called when user views a video or taps on creator name
  /// **OPTIMIZED: Uses SmartCacheManager for unified caching**
  Future<void> preloadProfile(String userId) async {
    if (userId.isEmpty || userId == 'unknown') {
      AppLogger.log('⚠️ ProfilePreloader: Invalid userId, skipping preload');
      return;
    }

    final trimmedUserId = userId.trim();

    // Skip if already preloading or recently preloaded
    if (_preloadingProfiles.contains(trimmedUserId) ||
        _preloadedProfiles.contains(trimmedUserId)) {
      AppLogger.log(
          '⏳ ProfilePreloader: Profile $trimmedUserId already preloading/preloaded, skipping');
      return;
    }

    await _ensureCacheInitialized();

    // **OPTIMIZED: Check SmartCacheManager cache (same as ProfileStateManager)**
    if (_cacheInitialized) {
      final cacheKey = 'user_profile_$trimmedUserId';
      try {
        // **OPTIMIZATION: Use peek() to check cache without triggering fetch**
        final cachedProfile = await _cacheManager.peek<Map<String, dynamic>>(
          cacheKey,
          cacheType: 'user_profile',
          allowStale: true, // Allow stale cache for preload check
        );

        if (cachedProfile != null) {
          AppLogger.log(
              '⚡ ProfilePreloader: Profile $trimmedUserId already cached in SmartCache, skipping preload');
          _preloadedProfiles.add(trimmedUserId);
          return;
        }
      } catch (e) {
        AppLogger.log('⚠️ ProfilePreloader: Error checking cache: $e');
      }
    }

    // Mark as preloading
    _preloadingProfiles.add(trimmedUserId);

    // Preload in background (non-blocking)
    Future.microtask(() async {
      try {
        AppLogger.log(
            '🔄 ProfilePreloader: Preloading profile for user: $trimmedUserId');

        // Fetch profile data
        final profileData = await _userService.getUserById(trimmedUserId);

        // **OPTIMIZED: Cache in SmartCacheManager via get() with fetchFn**
        // get() will check cache first, and if not cached, call fetchFn which returns our data
        if (_cacheInitialized) {
          final cacheKey = 'user_profile_$trimmedUserId';
          await _cacheManager.get<Map<String, dynamic>>(
            cacheKey,
            cacheType: 'user_profile',
            maxAge: const Duration(days: 7),
            fetchFn: () async =>
                profileData, // Return already fetched data to cache it
          );
          AppLogger.log(
              '✅ ProfilePreloader: Cached profile in SmartCacheManager for user: $trimmedUserId');
        }

        // **OPTIMIZED: Also preload videos in parallel (not sequential)**
        Future.microtask(() async {
          try {
            final videos = await _videoService.getUserVideos(trimmedUserId);
            if (videos.isNotEmpty && _cacheInitialized) {
              final videoCacheKey = 'video_profile_$trimmedUserId';
              final videosPayload = {
                'videos': videos.map((v) => v.toJson()).toList(growable: false),
                'fetchedAt': DateTime.now().toIso8601String(),
              };
              // **OPTIMIZATION: Cache via get() with fetchFn**
              await _cacheManager.get<Map<String, dynamic>>(
                videoCacheKey,
                cacheType: 'videos',
                maxAge: const Duration(minutes: 45),
                fetchFn: () async =>
                    videosPayload, // Return already fetched data to cache it
              );
              AppLogger.log(
                  '✅ ProfilePreloader: Preloaded and cached ${videos.length} videos for user: $trimmedUserId');
            }
          } catch (e) {
            AppLogger.log('⚠️ ProfilePreloader: Failed to preload videos: $e');
          }
        });
      } catch (e) {
        AppLogger.log(
            '❌ ProfilePreloader: Failed to preload profile for $trimmedUserId: $e');
      } finally {
        _preloadingProfiles.remove(trimmedUserId);
        _preloadedProfiles.add(trimmedUserId);

        // Remove from preloaded set after 5 minutes to allow refresh
        Future.delayed(const Duration(minutes: 5), () {
          _preloadedProfiles.remove(trimmedUserId);
        });
      }
    });
  }

  /// **PRELOAD PROFILE ON TAP: Preload before navigation**
  /// Call this when user taps on creator name/avatar
  /// **OPTIMIZED: Checks cache first for instant navigation**
  Future<void> preloadProfileOnTap(String userId) async {
    if (userId.isEmpty || userId == 'unknown') return;

    final trimmedUserId = userId.trim();
    await _ensureCacheInitialized();

    // **OPTIMIZATION: Check SmartCacheManager first for instant navigation**
    if (_cacheInitialized) {
      final cacheKey = 'user_profile_$trimmedUserId';
      try {
        // **OPTIMIZATION: Use peek() to check cache without triggering fetch**
        final cachedProfile = await _cacheManager.peek<Map<String, dynamic>>(
          cacheKey,
          cacheType: 'user_profile',
          allowStale: true, // Allow stale cache for instant navigation check
        );

        if (cachedProfile != null) {
          AppLogger.log(
              '⚡ ProfilePreloader: Using cached profile for instant navigation: $trimmedUserId');
          // Cache exists - navigation will be instant
          return;
        }
      } catch (e) {
        AppLogger.log('⚠️ ProfilePreloader: Error checking cache: $e');
      }
    }

    // **OPTIMIZATION: Start preloading in background (non-blocking)**
    // Navigation will happen, ProfileScreen will load from cache or fetch
    preloadProfile(userId);

    // Small delay to allow preload to start
    await Future.delayed(const Duration(milliseconds: 50));
  }

  /// **CHECK IF PROFILE IS CACHED**
  /// **OPTIMIZED: Uses SmartCacheManager**
  Future<bool> isProfileCached(String userId) async {
    if (userId.isEmpty || userId == 'unknown') return false;

    try {
      await _ensureCacheInitialized();
      if (!_cacheInitialized) return false;

      final cacheKey = 'user_profile_${userId.trim()}';
      // **OPTIMIZATION: Use peek() to check cache without triggering fetch**
      final cachedProfile = await _cacheManager.peek<Map<String, dynamic>>(
        cacheKey,
        cacheType: 'user_profile',
        allowStale: true, // Allow stale cache
      );

      return cachedProfile != null;
    } catch (e) {
      return false;
    }
  }

  /// **CLEAR PRELOADED STATE** (for testing or manual refresh)
  void clearPreloadedState(String userId) {
    _preloadingProfiles.remove(userId.trim());
    _preloadedProfiles.remove(userId.trim());
  }
}
