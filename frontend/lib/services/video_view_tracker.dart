import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vayu/config/app_config.dart';
import 'package:vayu/services/authservices.dart';

/// Service for managing video view tracking with Instagram Reels-style behavior
/// Handles 4-second view threshold, repeat views (max 10 per user), and API integration
class VideoViewTracker {
  static String get _baseUrl => AppConfig.baseUrl;
  final AuthService _authService = AuthService();

  // Track which videos have been viewed to prevent duplicate counts in same session
  final Set<String> _viewedVideos = <String>{};
  final Map<String, Timer> _viewTimers = <String, Timer>{};
  final Map<String, int> _userViewCounts = <String, int>{};

  /// Increment view count for a video after 4 seconds of playback
  /// Returns true if view was counted, false if already at max or error
  Future<bool> incrementView(String videoId, {int duration = 4}) async {
    try {
      print(
          '🎯 VideoViewTracker: Attempting to increment view for video $videoId');

      // Get current user data
      final userData = await _authService.getUserData();
      if (userData == null || userData['id'] == null) {
        print('❌ VideoViewTracker: No authenticated user found');
        return false;
      }

      final userId = userData['id'];
      print('🎯 VideoViewTracker: User ID: $userId');

      // Check if user has already reached max views for this video
      final userViewCount = _userViewCounts['${videoId}_$userId'] ?? 0;
      if (userViewCount >= 10) {
        print(
            '⚠️ VideoViewTracker: User has reached max view count (10) for video $videoId');
        return false;
      }

      // Make API call to increment view
      final url = Uri.parse('$_baseUrl/api/videos/$videoId/increment-view');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'userId': userId,
          'duration': duration,
        }),
      );

      print('🎯 VideoViewTracker: API response status: ${response.statusCode}');
      print('🎯 VideoViewTracker: API response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);

        // Update local view count tracking
        _userViewCounts['${videoId}_$userId'] =
            responseData['userViewCount'] ?? 0;

        print('✅ VideoViewTracker: View incremented successfully');
        print('   Total views: ${responseData['totalViews']}');
        print('   User view count: ${responseData['userViewCount']}');
        print('   Max views reached: ${responseData['maxViewsReached']}');

        return !responseData['maxViewsReached'];
      } else {
        print(
            '❌ VideoViewTracker: Failed to increment view - Status: ${response.statusCode}');
        print('❌ VideoViewTracker: Error response: ${response.body}');
        return false;
      }
    } catch (e) {
      print('❌ VideoViewTracker: Error incrementing view: $e');
      return false;
    }
  }

  /// Start tracking view for a video - will increment after 4 seconds
  void startViewTracking(String videoId) {
    print('🎯 VideoViewTracker: Starting view tracking for video $videoId');

    // Cancel any existing timer for this video
    _viewTimers[videoId]?.cancel();

    // Start new timer
    _viewTimers[videoId] = Timer(const Duration(seconds: 4), () async {
      print(
          '⏰ VideoViewTracker: 4 seconds elapsed for video $videoId, incrementing view');

      // Check if this video hasn't been counted yet in this session
      final viewKey = '${videoId}_current_session';
      if (!_viewedVideos.contains(viewKey)) {
        final success = await incrementView(videoId);
        if (success) {
          _viewedVideos.add(viewKey);
          print('✅ VideoViewTracker: View counted for video $videoId');
        } else {
          print(
              '⚠️ VideoViewTracker: View not counted for video $videoId (max reached or error)');
        }
      } else {
        print(
            '⚠️ VideoViewTracker: Video $videoId already counted in this session');
      }

      // Clean up timer
      _viewTimers.remove(videoId);
    });
  }

  /// Stop tracking view for a video (e.g., when user scrolls away)
  void stopViewTracking(String videoId) {
    print('🎯 VideoViewTracker: Stopping view tracking for video $videoId');

    _viewTimers[videoId]?.cancel();
    _viewTimers.remove(videoId);
  }

  /// Reset view tracking for a video (allows re-counting)
  void resetViewTracking(String videoId) {
    print('🎯 VideoViewTracker: Resetting view tracking for video $videoId');

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

  /// Clear all view tracking data
  void clearViewTracking() {
    print('🎯 VideoViewTracker: Clearing all view tracking data');

    // Cancel all active timers
    for (final timer in _viewTimers.values) {
      timer.cancel();
    }

    _viewTimers.clear();
    _viewedVideos.clear();
    _userViewCounts.clear();
  }

  /// Dispose of the service and clean up resources
  void dispose() {
    print('🎯 VideoViewTracker: Disposing service');
    clearViewTracking();
  }
}
