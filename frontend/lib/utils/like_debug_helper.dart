/// **LIKE DEBUG HELPER**
///
/// This helper provides utilities to debug like requests.
/// Use this to check if like requests are being sent and received.
///
/// Usage:
/// ```dart
/// LikeDebugHelper.logLikeAttempt(videoId, userId);
/// LikeDebugHelper.logLikeResponse(videoId, success, response);
/// ```

import 'package:vayu/utils/app_logger.dart';

class LikeDebugHelper {
  /// Log when user attempts to like a video
  static void logLikeAttempt(String videoId, String? userId) {
    AppLogger.log('🔴 ========== LIKE ATTEMPT ==========');
    AppLogger.log('🔴 Video ID: $videoId');
    AppLogger.log('🔴 User ID: ${userId ?? "NULL"}');
    AppLogger.log('🔴 Timestamp: ${DateTime.now().toIso8601String()}');
  }

  /// Log when like request is sent to backend
  static void logLikeRequestSent(String videoId, String url) {
    AppLogger.log('🔴 Like Request SENT to: $url');
    AppLogger.log('🔴 Video ID: $videoId');
    AppLogger.log('🔴 Timestamp: ${DateTime.now().toIso8601String()}');
  }

  /// Log when like response is received from backend
  static void logLikeResponse(
    String videoId,
    bool success,
    int? statusCode,
    Map<String, dynamic>? response,
  ) {
    AppLogger.log('🔴 ========== LIKE RESPONSE ==========');
    AppLogger.log('🔴 Video ID: $videoId');
    AppLogger.log('🔴 Success: $success');
    AppLogger.log('🔴 Status Code: ${statusCode ?? "NULL"}');
    if (response != null) {
      AppLogger.log('🔴 Response Likes: ${response['likes'] ?? "NULL"}');
      AppLogger.log(
          '🔴 Response LikedBy Length: ${(response['likedBy'] as List?)?.length ?? "NULL"}');
    }
    AppLogger.log('🔴 Timestamp: ${DateTime.now().toIso8601String()}');
  }

  /// Log when like request fails
  static void logLikeError(String videoId, dynamic error) {
    AppLogger.log('🔴 ========== LIKE ERROR ==========');
    AppLogger.log('🔴 Video ID: $videoId');
    AppLogger.log('🔴 Error: $error');
    AppLogger.log('🔴 Error Type: ${error.runtimeType}');
    AppLogger.log('🔴 Timestamp: ${DateTime.now().toIso8601String()}');
  }

  /// Log when optimistic update is applied
  static void logOptimisticUpdate(String videoId, bool wasLiked, int newLikes) {
    AppLogger.log('🔴 Optimistic Update - Video: $videoId');
    AppLogger.log('🔴 Action: ${wasLiked ? "UNLIKE" : "LIKE"}');
    AppLogger.log('🔴 New Likes Count: $newLikes');
  }

  /// Log when state is synced with backend
  static void logStateSync(String videoId, int likes, int likedByLength) {
    AppLogger.log('🔴 State Synced - Video: $videoId');
    AppLogger.log('🔴 Likes: $likes');
    AppLogger.log('🔴 LikedBy Length: $likedByLength');
    if (likes != likedByLength) {
      AppLogger.log(
          '⚠️ WARNING: Likes count ($likes) does not match likedBy length ($likedByLength)!',
          isError: true);
    } else {
      AppLogger.log('✅ Likes count matches likedBy length');
    }
  }

  /// Generate a debug summary
  static void printDebugSummary({
    required String videoId,
    required String? userId,
    required bool requestSent,
    required bool requestReceived,
    required int? statusCode,
    required int? likes,
    required int? likedByLength,
  }) {
    AppLogger.log('\n🔴 ========== LIKE DEBUG SUMMARY ==========');
    AppLogger.log('🔴 Video ID: $videoId');
    AppLogger.log('🔴 User ID: ${userId ?? "NULL"}');
    AppLogger.log('🔴 Request Sent: ${requestSent ? "✅ YES" : "❌ NO"}');
    AppLogger.log('🔴 Request Received: ${requestReceived ? "✅ YES" : "❌ NO"}');
    AppLogger.log('🔴 Status Code: ${statusCode ?? "NULL"}');
    AppLogger.log('🔴 Final Likes: ${likes ?? "NULL"}');
    AppLogger.log('🔴 Final LikedBy Length: ${likedByLength ?? "NULL"}');

    if (likes != null && likedByLength != null && likes != likedByLength) {
      AppLogger.log(
          '⚠️ MISMATCH: Likes ($likes) != LikedBy Length ($likedByLength)',
          isError: true);
    }

    AppLogger.log('🔴 ==========================================\n');
  }
}
