import 'dart:async';
import 'dart:convert';
import 'package:vayu/shared/config/app_config.dart';
import 'package:vayu/features/auth/data/services/authservices.dart';
import 'package:vayu/shared/services/platform_id_service.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:vayu/shared/services/http_client_service.dart';
import 'package:vayu/shared/constants/app_constants.dart';

/// Handles 2-second view threshold for videos, repeat views (max 10 per user), self-view prevention, and API integration
class VideoViewTracker {
  static String get _baseUrl => AppConfig.baseUrl;
  final AuthService _authService = AuthService();

  // Track which videos have been viewed to prevent duplicate counts in same session
  final Set<String> _viewedVideos = <String>{};
  final Map<String, Timer> _viewTimers = <String, Timer>{};
  final Map<String, int> _userViewCounts = <String, int>{};

  // **NEW: Track recent views to prevent rapid repeat spam**
  final Map<String, DateTime> _recentViews = <String, DateTime>{};
  // **RELAXED**: Allow repeat views after a short cooldown instead of 1 minute
  static const Duration _minViewInterval =
      Duration(seconds: 10); // Minimum 10 seconds between views

  /// Increment view count for a video after 2 seconds of playback
  /// Returns true if view was counted, false if already at max or error
  Future<bool> incrementView(
    String videoId, {
    int? duration,
    String? videoUploaderId,
    String? videoHash, // **NEW: Accept videoHash**
  }) async {
    try {
      final effectiveDuration =
          duration ?? AppConstants.videoViewCountThreshold.inSeconds;

      AppLogger.log(
          '🎯 VideoViewTracker: Attempting to increment view for video $videoId (hash: $videoHash)');

      // **CRITICAL FIX: Watch tracking should work for BOTH authenticated AND anonymous users**
      // Get platformId first (always available, even for anonymous users)
      final platformIdService = PlatformIdService();
      final platformId = await platformIdService.getPlatformId();

      // Get auth token (may be null for anonymous users)
      final token = await AuthService.getToken();
      Map<String, String> headers = {
        'Content-Type': 'application/json',
      };
      
      // **FIX: Always add device ID header for consistent tracking**
      if (platformId.isNotEmpty) {
        headers['x-device-id'] = platformId;
      }

      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      // **BACKEND-FIRST: Track watch history FIRST (before userData check)**
      // This ensures watch tracking works for anonymous users too
      try {
        final watchUrl = Uri.parse('$_baseUrl/api/videos/$videoId/watch');
        final watchBody = <String, dynamic>{
          'duration': effectiveDuration,
          'completed':
              false, // Initial watch tracking - will be marked completed in increment-view
        };
        
        // **NEW: Send videoHash**
        if (videoHash != null) {
          watchBody['videoHash'] = videoHash;
        }

        // **BACKEND-FIRST: Always send platformId as fallback (even if token exists, it might be invalid)**
        // This ensures watch tracking works even if token verification fails
        if (platformId.isNotEmpty) {
          watchBody['platformId'] = platformId;
          AppLogger.log(
              '📱 VideoViewTracker: Sending platformId for watch tracking (platformId: ${platformId.substring(0, 8)}...)');
        } else {
          AppLogger.log(
              '⚠️ VideoViewTracker: No platformId available for watch tracking fallback');
        }

        AppLogger.log(
            '📡 VideoViewTracker: Calling watch tracking API: $watchUrl');
        AppLogger.log(
            '📡 VideoViewTracker: Request body: ${json.encode(watchBody)}');
        AppLogger.log(
            '📡 VideoViewTracker: Request headers: ${headers.keys.join(", ")}');
        AppLogger.log('📡 VideoViewTracker: Base URL: $_baseUrl');
        final watchResponse = await httpClientService.post(
          watchUrl,
          headers: headers,
          body: json.encode(watchBody),
        );

        AppLogger.log(
            '📡 VideoViewTracker: Watch tracking response status: ${watchResponse.statusCode}');
        AppLogger.log(
            '📡 VideoViewTracker: Watch tracking response body: ${watchResponse.body}');

        if (watchResponse.statusCode == 200) {
          AppLogger.log(
              '✅ VideoViewTracker: Watch history tracked successfully');
          final watchData = json.decode(watchResponse.body);
          AppLogger.log(
              '   Watch count: ${watchData['watchEntry']?['watchCount'] ?? 1}');
        } else {
          AppLogger.log(
              '⚠️ VideoViewTracker: Watch tracking failed (non-critical): ${watchResponse.statusCode}');
          AppLogger.log(
              '⚠️ VideoViewTracker: Response body: ${watchResponse.body}');
        }
      } catch (watchError) {
        AppLogger.log(
            '❌ VideoViewTracker: Error tracking watch (non-critical): $watchError');
        AppLogger.log(
            '❌ VideoViewTracker: Error stack: ${watchError is Error ? watchError.stackTrace : 'N/A'}');
        // Don't fail view tracking if watch tracking fails
      }

      // **FIXED: View increment requires authenticated user, but watch tracking already happened above**
      // Get current user data for view increment (only authenticated users can increment views)
      final userData = await _authService.getUserData();
      if (userData == null || userData['id'] == null) {
        AppLogger.log(
            'ℹ️ VideoViewTracker: No authenticated user found - watch tracking done, skipping view increment');
        // Watch tracking already happened above, so return true (watch was tracked)
        return true;
      }

      final userId = userData['id'];
      AppLogger.log('🎯 VideoViewTracker: User ID: $userId');

      // **RELAXED RULE**: Allow creators to test their own videos
      // Self-views will now be counted like normal views so creators
      // can verify that view counts are updating correctly.

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

      // Make API call to increment view (existing functionality)
      // **IMPROVED: Also send platformId so backend can mark video as watched for anonymous users too**
      final url = Uri.parse('$_baseUrl/api/videos/$videoId/increment-view');
      final incrementBody = <String, dynamic>{
        'userId': userId,
        'duration': effectiveDuration,
      };

      // Always send platformId for watch tracking support
      if (platformId.isNotEmpty) {
        incrementBody['platformId'] = platformId;
      }
      
      // **NEW: Send videoHash**
      if (videoHash != null) {
        incrementBody['videoHash'] = videoHash;
      }

      final response = await httpClientService.post(
        url,
        headers: headers,
        body: json.encode(incrementBody),
      );

      AppLogger.log(
          '🎯 VideoViewTracker: API response status: ${response.statusCode}');
      AppLogger.log('🎯 VideoViewTracker: API response body: ${response.body}');

      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        
        // **FIX: Safely handle null values from backend response**
        final bool maxViewsReached = responseData['maxViewsReached'] ?? false;
        final int totalViews = responseData['totalViews'] ?? responseData['views'] ?? 0;
        final int userViewCount = responseData['userViewCount'] ?? 0;

        // Update local view count tracking
        _userViewCounts['${videoId}_$userId'] = userViewCount;

        // **NEW: Update recent view time to prevent rapid repeat spam**
        _recentViews[viewKey] = DateTime.now();

        AppLogger.log('✅ VideoViewTracker: View incremented successfully');
        AppLogger.log('   Total views: $totalViews');
        AppLogger.log('   User view count: $userViewCount');
        AppLogger.log('   Max views reached: $maxViewsReached');

        return !maxViewsReached;
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

  /// Start tracking view for a video - will increment after 2 seconds
  void startViewTracking(String videoId, {String? videoUploaderId, String? videoHash}) {
    AppLogger.log(
        '🎯 VideoViewTracker: Starting view tracking for video $videoId');

    // Cancel any existing timer for this video
    _viewTimers[videoId]?.cancel();

    // Start new timer
    _viewTimers[videoId] =
        Timer(AppConstants.videoViewCountThreshold, () async {
      AppLogger.log(
        '⏰ VideoViewTracker: ${AppConstants.videoViewCountThreshold.inSeconds} seconds elapsed for video $videoId, incrementing view',
      );

      // Check if this video hasn't been counted yet in this session
      final viewKey = '${videoId}_current_session';
      if (!_viewedVideos.contains(viewKey)) {
        final success =
            await incrementView(videoId, videoUploaderId: videoUploaderId, videoHash: videoHash);
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

  /// **NEW: Track video completion for watch history**
  /// This should work for BOTH authenticated and anonymous users,
  /// matching the logic used in [incrementView] for /watch tracking.
  Future<void> trackVideoCompletion(String videoId, {int? duration, String? videoHash}) async {
    try {
      AppLogger.log(
          '📊 VideoViewTracker: Tracking video completion for $videoId (hash: $videoHash)');

      // Get platformId (works for anonymous + authenticated users)
      final platformIdService = PlatformIdService();
      final platformId = await platformIdService.getPlatformId();

      // Get auth token if available (optional)
      final token = await AuthService.getToken();

      final headers = <String, String>{
        'Content-Type': 'application/json',
      };
      
      if (platformId.isNotEmpty) {
        headers['x-device-id'] = platformId;
      }
      
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }

      final body = <String, dynamic>{
        'duration': duration ?? 0,
        'completed': true, // Mark as completed
      };
      
      // **NEW: Send videoHash**
      if (videoHash != null) {
        body['videoHash'] = videoHash;
      }

      // Always include platformId as fallback identity (same as incrementView)
      if (platformId.isNotEmpty) {
        body['platformId'] = platformId;
        AppLogger.log(
          '📱 VideoViewTracker: Sending platformId for completion tracking (platformId: ${platformId.substring(0, 8)}...)',
        );
      } else {
        AppLogger.log(
            '⚠️ VideoViewTracker: No platformId available for completion tracking');
      }

      final watchUrl = Uri.parse('$_baseUrl/api/videos/$videoId/watch');
      AppLogger.log(
          '📡 VideoViewTracker: Calling completion tracking API: $watchUrl');
      AppLogger.log('📡 VideoViewTracker: Request body: ${json.encode(body)}');

      final watchResponse = await httpClientService.post(
        watchUrl,
        headers: headers,
        body: json.encode(body),
      );

      AppLogger.log(
        '📡 VideoViewTracker: Completion tracking response status: ${watchResponse.statusCode}',
      );
      AppLogger.log(
        '📡 VideoViewTracker: Completion tracking response body: ${watchResponse.body}',
      );

      if (watchResponse.statusCode == 200) {
        AppLogger.log(
            '✅ VideoViewTracker: Video completion tracked successfully');
        final watchData = json.decode(watchResponse.body);
        AppLogger.log(
          '   Watch count: ${watchData['watchEntry']?['watchCount'] ?? 1}',
        );
        AppLogger.log(
          '   Completed: ${watchData['watchEntry']?['completed'] ?? false}',
        );
      } else {
        AppLogger.log(
          '⚠️ VideoViewTracker: Completion tracking failed: ${watchResponse.statusCode}',
        );
      }
    } catch (e) {
      AppLogger.log('❌ VideoViewTracker: Error tracking video completion: $e');
    }
  }

  /// Dispose of the service and clean up resources
  void dispose() {
    AppLogger.log('🎯 VideoViewTracker: Disposing service');
    clearViewTracking();
  }
}
