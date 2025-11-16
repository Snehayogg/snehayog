import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/services/user_service.dart';
import 'package:vayu/services/video_service.dart';
import 'package:vayu/utils/app_logger.dart';

/// **PROFILE PRELOADER**
/// Preloads profile data for any user (especially other creators)
/// This ensures instant profile screen loading when user navigates to it
class ProfilePreloader {
  static final ProfilePreloader _instance = ProfilePreloader._internal();
  factory ProfilePreloader() => _instance;
  ProfilePreloader._internal();

  final UserService _userService = UserService();
  final VideoService _videoService = VideoService();

  // Track preloading state to avoid duplicate requests
  final Set<String> _preloadingProfiles = {};
  final Set<String> _preloadedProfiles = {};

  /// **PRELOAD PROFILE: Preload any user's profile data**
  /// This is called when user views a video or taps on creator name
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

    // Check if already cached
    final prefs = await SharedPreferences.getInstance();
    final cachedData = prefs.getString('profile_cache_$trimmedUserId');
    final cachedTimestamp =
        prefs.getInt('profile_cache_timestamp_$trimmedUserId');

    // If cache exists and is less than 1 hour old, skip preload
    if (cachedData != null && cachedData.isNotEmpty) {
      if (cachedTimestamp != null) {
        final cacheTime = DateTime.fromMillisecondsSinceEpoch(cachedTimestamp);
        final age = DateTime.now().difference(cacheTime);
        if (age.inHours < 1) {
          AppLogger.log(
              '⚡ ProfilePreloader: Profile $trimmedUserId already cached (${age.inMinutes}m old), skipping preload');
          _preloadedProfiles.add(trimmedUserId);
          return;
        }
      } else {
        // Cache exists but no timestamp - assume it's fresh enough
        AppLogger.log(
            '⚡ ProfilePreloader: Profile $trimmedUserId already cached (no timestamp), skipping preload');
        _preloadedProfiles.add(trimmedUserId);
        return;
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

        // Cache profile data
        await prefs.setString(
          'profile_cache_$trimmedUserId',
          json.encode(profileData),
        );
        await prefs.setInt(
          'profile_cache_timestamp_$trimmedUserId',
          DateTime.now().millisecondsSinceEpoch,
        );

        AppLogger.log(
            '✅ ProfilePreloader: Preloaded and cached profile for user: $trimmedUserId');

        // Also preload videos in background (non-blocking)
        Future.microtask(() async {
          try {
            final videos = await _videoService.getUserVideos(trimmedUserId);
            if (videos.isNotEmpty) {
              final videosJson = videos.map((v) => v.toJson()).toList();
              await prefs.setString(
                'profile_videos_cache_$trimmedUserId',
                json.encode(videosJson),
              );
              await prefs.setInt(
                'profile_videos_cache_timestamp_$trimmedUserId',
                DateTime.now().millisecondsSinceEpoch,
              );
              AppLogger.log(
                  '✅ ProfilePreloader: Preloaded ${videos.length} videos for user: $trimmedUserId');
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
  Future<void> preloadProfileOnTap(String userId) async {
    if (userId.isEmpty || userId == 'unknown') return;

    // Start preloading immediately
    preloadProfile(userId);

    // Small delay to allow preload to start
    await Future.delayed(const Duration(milliseconds: 50));
  }

  /// **CHECK IF PROFILE IS CACHED**
  Future<bool> isProfileCached(String userId) async {
    if (userId.isEmpty || userId == 'unknown') return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString('profile_cache_${userId.trim()}');
      return cachedData != null && cachedData.isNotEmpty;
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
