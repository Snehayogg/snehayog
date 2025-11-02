import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/services/user_service.dart';
import 'package:vayu/services/video_service.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/utils/app_logger.dart';

/// **BACKGROUND PROFILE PRELOADER**
/// Preloads profile data in the background while user is on video feed (Yog tab)
/// This ensures instant profile screen loading when user navigates to it
class BackgroundProfilePreloader {
  static final BackgroundProfilePreloader _instance =
      BackgroundProfilePreloader._internal();
  factory BackgroundProfilePreloader() => _instance;
  BackgroundProfilePreloader._internal();

  final AuthService _authService = AuthService();
  final UserService _userService = UserService();
  final VideoService _videoService = VideoService();

  // Preloading state
  bool _isPreloading = false;
  bool _isProfilePreloaded = false;
  bool _areVideosPreloaded = false;
  DateTime? _lastPreloadTime;

  // Cache keys
  static const String _cacheKeyProfileData = 'preloaded_profile_data';
  static const String _cacheKeyUserVideos = 'preloaded_user_videos';
  static const String _cacheKeyPreloadTimestamp = 'preload_timestamp';

  // Preload configuration
  static const Duration _preloadInterval = Duration(minutes: 5);
  static const Duration _preloadDelay = Duration(seconds: 3);
  static const Duration _cacheExpiry = Duration(minutes: 15);

  Timer? _preloadTimer;

  /// **START BACKGROUND PRELOADING**
  /// Call this when video feed (Yog tab) becomes visible
  void startBackgroundPreloading() {
    AppLogger.log(
        '🚀 BackgroundProfilePreloader: Starting background preloading...');

    // Cancel any existing timer
    _preloadTimer?.cancel();

    // Start preloading after a short delay (to not interfere with video loading)
    _preloadTimer = Timer(_preloadDelay, () {
      _performBackgroundPreload();
    });
  }

  /// **STOP BACKGROUND PRELOADING**
  /// Call this when video feed (Yog tab) becomes hidden
  void stopBackgroundPreloading() {
    AppLogger.log(
        '⏸️ BackgroundProfilePreloader: Stopping background preloading...');
    _preloadTimer?.cancel();
  }

  /// **PERFORM BACKGROUND PRELOAD**
  Future<void> _performBackgroundPreload() async {
    // Don't preload if already preloading
    if (_isPreloading) {
      AppLogger.log(
          '⏳ BackgroundProfilePreloader: Already preloading, skipping...');
      return;
    }

    // Don't preload if recently preloaded (within interval)
    if (_lastPreloadTime != null &&
        DateTime.now().difference(_lastPreloadTime!) < _preloadInterval) {
      AppLogger.log(
          '⏳ BackgroundProfilePreloader: Recently preloaded, skipping...');
      return;
    }

    _isPreloading = true;
    AppLogger.log('🔄 BackgroundProfilePreloader: Starting preload...');

    try {
      // Get current user
      final userData = await _authService.getUserData();
      if (userData == null) {
        AppLogger.log(
            '⚠️ BackgroundProfilePreloader: No authenticated user, skipping preload');
        return;
      }

      final userId = userData['googleId'] ?? userData['id'];
      if (userId == null || userId.isEmpty) {
        AppLogger.log(
            '⚠️ BackgroundProfilePreloader: Invalid user ID, skipping preload');
        return;
      }

      AppLogger.log(
          '✅ BackgroundProfilePreloader: Preloading for user: $userId');

      // Preload profile data and videos in parallel
      await Future.wait([
        _preloadProfileData(userId),
        _preloadUserVideos(userId),
      ]);

      _lastPreloadTime = DateTime.now();
      _isProfilePreloaded = true;
      _areVideosPreloaded = true;

      AppLogger.log(
          '✅ BackgroundProfilePreloader: Preload completed successfully');
    } catch (e) {
      AppLogger.log('❌ BackgroundProfilePreloader: Error during preload: $e');
    } finally {
      _isPreloading = false;
    }
  }

  /// **PRELOAD PROFILE DATA**
  Future<void> _preloadProfileData(String userId) async {
    try {
      AppLogger.log(
          '📥 BackgroundProfilePreloader: Preloading profile data...');

      // Check if cache is still fresh
      final cachedData = await _getCachedProfileData();
      if (cachedData != null) {
        AppLogger.log(
            '⚡ BackgroundProfilePreloader: Profile data already cached and fresh');
        return;
      }

      // Fetch profile data from server
      final profileData = await _userService.getUserById(userId);

      // Cache the profile data
      await _cacheProfileData(profileData);
      AppLogger.log(
          '✅ BackgroundProfilePreloader: Profile data preloaded and cached');
    } catch (e) {
      AppLogger.log(
          '❌ BackgroundProfilePreloader: Error preloading profile data: $e');
    }
  }

  /// **PRELOAD USER VIDEOS**
  Future<void> _preloadUserVideos(String userId) async {
    try {
      AppLogger.log('📥 BackgroundProfilePreloader: Preloading user videos...');

      // Check if cache is still fresh
      final cachedVideos = await _getCachedUserVideos();
      if (cachedVideos != null && cachedVideos.isNotEmpty) {
        AppLogger.log(
            '⚡ BackgroundProfilePreloader: User videos already cached and fresh');
        return;
      }

      // Fetch user videos from server
      final videos = await _videoService.getUserVideos(userId);

      if (videos.isNotEmpty) {
        // Cache the videos
        await _cacheUserVideos(videos);
        AppLogger.log(
            '✅ BackgroundProfilePreloader: User videos preloaded and cached (${videos.length} videos)');
      }
    } catch (e) {
      AppLogger.log(
          '❌ BackgroundProfilePreloader: Error preloading user videos: $e');
    }
  }

  /// **CACHE PROFILE DATA**
  Future<void> _cacheProfileData(Map<String, dynamic> profileData) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Store profile data as JSON string using proper JSON encoding
      final profileJson = jsonEncode(profileData);
      await prefs.setString(_cacheKeyProfileData, profileJson);

      // Store timestamp
      await prefs.setInt(
          _cacheKeyPreloadTimestamp, DateTime.now().millisecondsSinceEpoch);

      AppLogger.log('💾 BackgroundProfilePreloader: Profile data cached');
    } catch (e) {
      AppLogger.log(
          '❌ BackgroundProfilePreloader: Error caching profile data: $e');
    }
  }

  /// **CACHE USER VIDEOS**
  Future<void> _cacheUserVideos(List<VideoModel> videos) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Convert videos to JSON and store using proper JSON encoding
      final videoJsonList = videos.map((video) => video.toJson()).toList();
      final videosJson = jsonEncode(videoJsonList);
      await prefs.setString(_cacheKeyUserVideos, videosJson);

      AppLogger.log(
          '💾 BackgroundProfilePreloader: User videos cached (${videos.length} videos)');
    } catch (e) {
      AppLogger.log(
          '❌ BackgroundProfilePreloader: Error caching user videos: $e');
    }
  }

  /// **GET CACHED PROFILE DATA**
  Future<Map<String, dynamic>?> _getCachedProfileData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if cache expired
      if (_isCacheExpired(prefs)) {
        AppLogger.log(
            '⏰ BackgroundProfilePreloader: Cache expired, clearing...');
        await clearCache();
        return null;
      }

      final profileJson = prefs.getString(_cacheKeyProfileData);
      if (profileJson != null && profileJson.isNotEmpty) {
        final profileData = jsonDecode(profileJson) as Map<String, dynamic>;
        AppLogger.log(
            '⚡ BackgroundProfilePreloader: Found cached profile data');
        return profileData;
      }
    } catch (e) {
      AppLogger.log(
          '❌ BackgroundProfilePreloader: Error getting cached profile data: $e');
    }
    return null;
  }

  /// **GET CACHED USER VIDEOS**
  Future<List<VideoModel>?> _getCachedUserVideos() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Check if cache expired
      if (_isCacheExpired(prefs)) {
        AppLogger.log(
            '⏰ BackgroundProfilePreloader: Cache expired, clearing...');
        await clearCache();
        return null;
      }

      final videosJson = prefs.getString(_cacheKeyUserVideos);
      if (videosJson != null && videosJson.isNotEmpty) {
        final videoJsonList = jsonDecode(videosJson) as List<dynamic>;
        final videos = videoJsonList
            .map((json) => VideoModel.fromJson(json as Map<String, dynamic>))
            .toList();
        AppLogger.log(
            '⚡ BackgroundProfilePreloader: Found cached user videos (${videos.length} videos)');
        return videos;
      }
    } catch (e) {
      AppLogger.log(
          '❌ BackgroundProfilePreloader: Error getting cached user videos: $e');
    }
    return null;
  }

  /// **CHECK IF CACHE IS EXPIRED**
  bool _isCacheExpired(SharedPreferences prefs) {
    final timestamp = prefs.getInt(_cacheKeyPreloadTimestamp);
    if (timestamp == null) return true;

    final cacheTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final age = now.difference(cacheTime);

    return age > _cacheExpiry;
  }

  /// **CLEAR CACHE**
  Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKeyProfileData);
      await prefs.remove(_cacheKeyUserVideos);
      await prefs.remove(_cacheKeyPreloadTimestamp);

      _isProfilePreloaded = false;
      _areVideosPreloaded = false;

      AppLogger.log('🧹 BackgroundProfilePreloader: Cache cleared');
    } catch (e) {
      AppLogger.log('❌ BackgroundProfilePreloader: Error clearing cache: $e');
    }
  }

  /// **PUBLIC: Get preloaded profile data (for ProfileScreen to use)**
  Future<Map<String, dynamic>?> getPreloadedProfileData() async {
    return await _getCachedProfileData();
  }

  /// **PUBLIC: Get preloaded user videos (for ProfileScreen to use)**
  Future<List<VideoModel>?> getPreloadedUserVideos() async {
    return await _getCachedUserVideos();
  }

  /// **CHECK IF DATA IS PRELOADED**
  bool get isPreloaded => _isProfilePreloaded && _areVideosPreloaded;

  /// **FORCE PRELOAD NOW**
  Future<void> forcePreload() async {
    _lastPreloadTime = null; // Reset to allow immediate preload
    await _performBackgroundPreload();
  }

  /// **DISPOSE: Clean up resources**
  void dispose() {
    _preloadTimer?.cancel();
    AppLogger.log('🧹 BackgroundProfilePreloader: Disposed');
  }
}
