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
  void startBackgroundPreloading() {
    AppLogger.log('🚀 BackgroundProfilePreloader: Starting background preloading...');
    _preloadTimer?.cancel();
    _preloadTimer = Timer(_preloadDelay, () {
      _performBackgroundPreload();
    });
  }

  /// **STOP BACKGROUND PRELOADING**
  void stopBackgroundPreloading() {
    AppLogger.log('⏸️ BackgroundProfilePreloader: Stopping background preloading...');
    _preloadTimer?.cancel();
  }

  /// **PERFORM BACKGROUND PRELOAD**
  Future<void> _performBackgroundPreload() async {
    if (_isPreloading) return;
    if (_lastPreloadTime != null && DateTime.now().difference(_lastPreloadTime!) < _preloadInterval) return;

    _isPreloading = true;
    try {
      final userData = await _authService.getUserData();
      if (userData == null) return;

      final userId = userData['googleId'] ?? userData['id'];
      if (userId == null || userId.isEmpty) return;

      await Future.wait([
        _preloadProfileData(userId),
        _preloadUserVideos(userId),
      ]);

      _lastPreloadTime = DateTime.now();
      _isProfilePreloaded = true;
      _areVideosPreloaded = true;
    } catch (e) {
      AppLogger.log('❌ BackgroundProfilePreloader: Error during preload: $e');
    } finally {
      _isPreloading = false;
    }
  }

  /// **PRELOAD PROFILE DATA**
  Future<void> _preloadProfileData(String userId) async {
    try {
      final profileData = await _userService.getUserById(userId);
      await _cacheProfileData(profileData);
    } catch (e) {
      AppLogger.log('❌ BackgroundProfilePreloader: Error preloading profile data: $e');
    }
  }

  /// **PRELOAD USER VIDEOS**
  Future<void> _preloadUserVideos(String userId) async {
    try {
      final videos = await _videoService.getUserVideos(userId);
      if (videos.isNotEmpty) {
        await _cacheUserVideos(videos);
      }
    } catch (e) {
      AppLogger.log('❌ BackgroundProfilePreloader: Error preloading user videos: $e');
    }
  }

  /// **CACHE PROFILE DATA**
  Future<void> _cacheProfileData(Map<String, dynamic> profileData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sanitizedData = _sanitizeUserData(profileData);
      final profileJson = jsonEncode(sanitizedData);
      await prefs.setString(_cacheKeyProfileData, profileJson);
      await prefs.setInt(_cacheKeyPreloadTimestamp, DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      AppLogger.log('❌ BackgroundProfilePreloader: Error caching profile data: $e');
    }
  }

  /// **CACHE USER VIDEOS**
  Future<void> _cacheUserVideos(List<VideoModel> videos) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final List<Map<String, dynamic>> videoJsonList = videos.map((v) {
        final videoJson = v.toJson();
        videoJson['earnings'] = 0.0;
        if (videoJson['uploader'] is Map) {
          final uploader = Map<String, dynamic>.from(videoJson['uploader'] as Map);
          uploader['earnings'] = 0.0;
          videoJson['uploader'] = uploader;
        }
        return videoJson;
      }).toList();
      final videosJson = jsonEncode(videoJsonList);
      await prefs.setString(_cacheKeyUserVideos, videosJson);
    } catch (e) {
      AppLogger.log('❌ BackgroundProfilePreloader: Error caching user videos: $e');
    }
  }

  /// **GET CACHED PROFILE DATA**
  Future<Map<String, dynamic>?> _getCachedProfileData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_isCacheExpired(prefs)) return null;
      final profileJson = prefs.getString(_cacheKeyProfileData);
      if (profileJson != null && profileJson.isNotEmpty) {
        return jsonDecode(profileJson) as Map<String, dynamic>;
      }
    } catch (e) {}
    return null;
  }

  /// **GET CACHED USER VIDEOS**
  Future<List<VideoModel>?> _getCachedUserVideos() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_isCacheExpired(prefs)) return null;
      final videosJson = prefs.getString(_cacheKeyUserVideos);
      if (videosJson != null && videosJson.isNotEmpty) {
        final List<dynamic> jsonList = jsonDecode(videosJson);
        return jsonList.map((json) => VideoModel.fromJson(json as Map<String, dynamic>)).toList();
      }
    } catch (e) {}
    return null;
  }

  /// **CHECK IF CACHE IS EXPIRED**
  bool _isCacheExpired(SharedPreferences prefs) {
    final timestamp = prefs.getInt(_cacheKeyPreloadTimestamp);
    if (timestamp == null) return true;
    final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(timestamp));
    return age > _cacheExpiry;
  }

  /// **CLEAR CACHE**
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_cacheKeyProfileData);
    await prefs.remove(_cacheKeyUserVideos);
    await prefs.remove(_cacheKeyPreloadTimestamp);
    _isProfilePreloaded = false;
    _areVideosPreloaded = false;
  }

  /// **PUBLIC GETTERS**
  Future<Map<String, dynamic>?> getPreloadedProfileData() => _getCachedProfileData();
  Future<List<VideoModel>?> getPreloadedUserVideos() => _getCachedUserVideos();

  /// **Sanitize User Data to remove earnings**
  Map<String, dynamic> _sanitizeUserData(Map<String, dynamic> data) {
    final sanitized = Map<String, dynamic>.from(data);
    sanitized.remove('earnings');
    sanitized.remove('totalEarnings');
    sanitized.remove('pendingEarnings');
    sanitized.remove('withdrawableEarnings');
    if (sanitized['creatorStats'] is Map) {
       final stats = Map<String, dynamic>.from(sanitized['creatorStats'] as Map);
       stats.remove('earnings');
       stats.remove('revenue');
       sanitized['creatorStats'] = stats;
    }
    if (sanitized['videos'] is List) {
       final videosList = sanitized['videos'] as List;
       sanitized['videos'] = videosList.map((v) {
         if (v is Map) {
           final video = Map<String, dynamic>.from(v as Map);
           video['earnings'] = 0.0;
           if (video['uploader'] is Map) {
             final uploader = Map<String, dynamic>.from(video['uploader'] as Map);
             uploader['earnings'] = 0.0;
             video['uploader'] = uploader;
           }
           return video;
         }
         return v;
       }).toList();
    }
    return sanitized;
  }

  bool get isPreloaded => _isProfilePreloaded && _areVideosPreloaded;
  Future<void> forcePreload() async {
    _lastPreloadTime = null;
    await _performBackgroundPreload();
  }

  /// **DISPOSE: Clean up resources**
  void dispose() {
    _preloadTimer?.cancel();
    AppLogger.log('🧹 BackgroundProfilePreloader: Disposed');
  }
}
