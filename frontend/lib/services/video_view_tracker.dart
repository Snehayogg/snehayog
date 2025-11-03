import 'dart:async';
import 'dart:convert';
import 'package:vayu/config/app_config.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/utils/app_logger.dart';
import 'package:vayu/core/services/http_client_service.dart';

/// Handles 4-second view threshold, repeat views (max 10 per user), self-view prevention, and API integration
class VideoViewTracker {
  static String get _baseUrl => AppConfig.baseUrl;
  final AuthService _authService = AuthService();

  // Track which videos have been viewed to prevent duplicate counts in same session
  final Set<String> _viewedVideos = <String>{};
  final Map<String, Timer> _viewTimers = <String, Timer>{};
  final Map<String, int> _userViewCounts = <String, int>{};

  // **NEW: Track recent views to prevent rapid repeat spam**
  final Map<String, DateTime> _recentViews = <String, DateTime>{};
  static const Duration _minViewInterval =
      Duration(minutes: 1); // Minimum 1 minute between views

  /// Increment view count for a video after 4 seconds of playback
  /// Returns true if view was counted, false if already at max or error
  Future<bool> incrementView(String videoId,
      {int duration = 4, String? videoUploaderId}) async {
    try {
      AppLogger.log(
          '🎯 VideoViewTracker: Attempting to increment view for video $videoId');

      // Get current user data
      final userData = await _authService.getUserData();
      if (userData == null || userData['id'] == null) {
        AppLogger.log('❌ VideoViewTracker: No authenticated user found');
        return false;
      }

      final userId = userData['id'];
      AppLogger.log('🎯 VideoViewTracker: User ID: $userId');

      // **NEW: Prevent self-view counting**
      if (videoUploaderId != null && videoUploaderId == userId) {
        AppLogger.log(
            '🚫 VideoViewTracker: User is viewing their own video - view not counted');
        AppLogger.log(
            '🚫 VideoViewTracker: Video uploader: $videoUploaderId, Current user: $userId');
        return false;
      }

      // **NEW: Check for rapid repeat spam**
      final viewKey = '${videoId}_$userId';
      final lastViewTime = _recentViews[viewKey];
      if (lastViewTime != null) {
        final timeSinceLastView = DateTime.now().difference(lastViewTime);
        if (timeSinceLastView < _minViewInterval) {
          AppLogger.log(
              '🚫 VideoViewTracker: Rapid repeat view detected - too soon since last view');
          AppLogger.log(
              '🚫 VideoViewTracker: Time since last view: ${timeSinceLastView.inSeconds}s, minimum: ${_minViewInterval.inSeconds}s');
          return false;
        }
      }

      // Check if user has already reached max views for this video
      final userViewCount = _userViewCounts['${videoId}_$userId'] ?? 0;
      if (userViewCount >= 10) {
        AppLogger.log(
            '⚠️ VideoViewTracker: User has reached max view count (10) for video $videoId');
        return false;
      }

      // Make API call to increment view
      final url = Uri.parse('$_baseUrl/api/videos/$videoId/increment-view');
      final response = await httpClientService.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'userId': userId,
          'duration': duration,
        }),
      );

      AppLogger.log(
          '🎯 VideoViewTracker: API response status: ${response.statusCode}');
      AppLogger.log('🎯 VideoViewTracker: API response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        // Update local view count tracking
        _userViewCounts['${videoId}_$userId'] =
            responseData['userViewCount'] ?? 0;

        // **NEW: Update recent view time to prevent rapid repeat spam**
        _recentViews[viewKey] = DateTime.now();

        AppLogger.log('✅ VideoViewTracker: View incremented successfully');
        AppLogger.log('   Total views: ${responseData['totalViews']}');
        AppLogger.log('   User view count: ${responseData['userViewCount']}');
        AppLogger.log(
            '   Max views reached: ${responseData['maxViewsReached']}');

        return !responseData['maxViewsReached'];
      } else {
        AppLogger.log(
            '❌ VideoViewTracker: Failed to increment view - Status: ${response.statusCode}');
        AppLogger.log('❌ VideoViewTracker: Error response: ${response.body}');
        return false;
      }
    } catch (e) {
      AppLogger.log('❌ VideoViewTracker: Error incrementing view: $e');
      return false;
    }
  }

  /// Start tracking view for a video - will increment after 4 seconds
  void startViewTracking(String videoId, {String? videoUploaderId}) {
    AppLogger.log(
        '🎯 VideoViewTracker: Starting view tracking for video $videoId');

    // Cancel any existing timer for this video
    _viewTimers[videoId]?.cancel();

    // Start new timer
    _viewTimers[videoId] = Timer(const Duration(seconds: 4), () async {
      AppLogger.log(
          '⏰ VideoViewTracker: 4 seconds elapsed for video $videoId, incrementing view');

      // Check if this video hasn't been counted yet in this session
      final viewKey = '${videoId}_current_session';
      if (!_viewedVideos.contains(viewKey)) {
        final success =
            await incrementView(videoId, videoUploaderId: videoUploaderId);
        if (success) {
          _viewedVideos.add(viewKey);
          AppLogger.log('✅ VideoViewTracker: View counted for video $videoId');
        } else {
          AppLogger.log(
              '⚠️ VideoViewTracker: View not counted for video $videoId (self-view, max reached or error)');
        }
      } else {
        AppLogger.log(
            '⚠️ VideoViewTracker: Video $videoId already counted in this session');
      }

      // Clean up timer
      _viewTimers.remove(videoId);
    });
  }

  /// Stop tracking view for a video (e.g., when user scrolls away)
  void stopViewTracking(String videoId) {
    AppLogger.log(
        '🎯 VideoViewTracker: Stopping view tracking for video $videoId');

    _viewTimers[videoId]?.cancel();
    _viewTimers.remove(videoId);
  }

  /// Reset view tracking for a video (allows re-counting)
  void resetViewTracking(String videoId) {
    AppLogger.log(
        '🎯 VideoViewTracker: Resetting view tracking for video $videoId');

    stopViewTracking(videoId);
    _viewedVideos.removeWhere((key) => key.startsWith('${videoId}_'));
  }

  /// Get user's view count for a specific video
  int getUserViewCount(String videoId, String userId) {
    return _userViewCounts['${videoId}_$userId'] ?? 0;
  }

  /// Check if user has reached max views for a video
  bool hasReachedMaxViews(String videoId, String userId) {
    return getUserViewCount(videoId, userId) >= 10;
  }

  /// **NEW: Check if user is viewing their own video**
  bool isViewingOwnVideo(String videoUploaderId, String userId) {
    return videoUploaderId == userId;
  }

  /// **NEW: Check if view is too soon (rapid repeat spam)**
  bool isViewTooSoon(String videoId, String userId) {
    final viewKey = '${videoId}_$userId';
    final lastViewTime = _recentViews[viewKey];
    if (lastViewTime == null) return false;

    final timeSinceLastView = DateTime.now().difference(lastViewTime);
    return timeSinceLastView < _minViewInterval;
  }

  /// Clear all view tracking data
  void clearViewTracking() {
    AppLogger.log('🎯 VideoViewTracker: Clearing all view tracking data');

    // Cancel all active timers
    for (final timer in _viewTimers.values) {
      timer.cancel();
    }

    _viewTimers.clear();
    _viewedVideos.clear();
    _userViewCounts.clear();
    _recentViews.clear(); // **NEW: Clear recent views tracking**
  }

  /// Dispose of the service and clean up resources
  void dispose() {
    AppLogger.log('🎯 VideoViewTracker: Disposing service');
    clearViewTracking();
  }
}
