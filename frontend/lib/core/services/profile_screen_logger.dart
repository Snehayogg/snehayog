import 'package:flutter/foundation.dart';

/// Comprehensive logging service for ProfileScreen operations
/// Follows the existing logging patterns in the codebase
class ProfileScreenLogger {
  static const String _tag = '👤';
  static const String _profileTag = '📋';
  static const String _videoTag = '🎬';
  static const String _authTag = '🔐';
  static const String _cacheTag = '💾';
  static const String _errorTag = '❌';
  static const String _successTag = '✅';
  static const String _warningTag = '⚠️';
  static const String _debugTag = '🔍';
  static const String _refreshTag = '🔄';
  static const String _paymentTag = '💰';
  static const String _apiTag = '🌐';

  // Profile initialization and lifecycle
  static void logProfileScreenInit() {
    if (kDebugMode) {
      print('$_tag ProfileScreen: Initializing...');
    }
  }

  static void logProfileScreenDispose() {
    if (kDebugMode) {
      print('$_tag ProfileScreen: Disposing...');
    }
  }

  static void logProfileLoad() {
    if (kDebugMode) {
      print('$_tag ProfileScreen: Loading profile data...');
    }
  }

  static void logProfileLoadSuccess({String? userId}) {
    if (kDebugMode) {
      if (userId != null) {
        print(
            '$_successTag ProfileScreen: Profile loaded successfully for user: $userId');
      } else {
        print('$_successTag ProfileScreen: Profile loaded successfully');
      }
    }
  }

  static void logProfileLoadError(String error) {
    if (kDebugMode) {
      print('$_errorTag ProfileScreen: Error loading profile: $error');
    }
  }

  // User data management
  static void logUserDataLoad({String? userId, String? source}) {
    if (kDebugMode) {
      final sourceInfo = source != null ? ' from $source' : '';
      final userInfo = userId != null ? ' for user: $userId' : '';
      print(
          '$_profileTag ProfileScreen: Loading user data$sourceInfo$userInfo');
    }
  }

  static void logUserDataSuccess({String? userId, int? dataCount}) {
    if (kDebugMode) {
      final userInfo = userId != null ? ' for user: $userId' : '';
      final countInfo = dataCount != null ? ' ($dataCount items)' : '';
      print(
          '$_successTag ProfileScreen: User data loaded successfully$userInfo$countInfo');
    }
  }

  static void logUserDataError(String error, {String? userId}) {
    if (kDebugMode) {
      final userInfo = userId != null ? ' for user: $userId' : '';
      print(
          '$_errorTag ProfileScreen: Error loading user data$userInfo: $error');
    }
  }

  // Video management
  static void logVideoLoad({String? userId, int? count}) {
    if (kDebugMode) {
      final userInfo = userId != null ? ' for user: $userId' : '';
      final countInfo = count != null ? ' ($count videos)' : '';
      print('$_videoTag ProfileScreen: Loading videos$userInfo$countInfo');
    }
  }

  static void logVideoLoadSuccess({required int count, String? source}) {
    if (kDebugMode) {
      final sourceInfo = source != null ? ' from $source' : '';
      print(
          '$_successTag ProfileScreen: Videos loaded successfully: $count videos$sourceInfo');
    }
  }

  static void logVideoLoadError(String error, {String? userId}) {
    if (kDebugMode) {
      final userInfo = userId != null ? ' for user: $userId' : '';
      print('$_errorTag ProfileScreen: Error loading videos$userInfo: $error');
    }
  }

  static void logVideoRefresh({String? userId}) {
    if (kDebugMode) {
      final userInfo = userId != null ? ' for user: $userId' : '';
      print('$_refreshTag ProfileScreen: Refreshing videos$userInfo');
    }
  }

  static void logVideoRefreshSuccess({required int count}) {
    if (kDebugMode) {
      print(
          '$_successTag ProfileScreen: Videos refreshed successfully: $count videos');
    }
  }

  static void logVideoRefreshError(String error) {
    if (kDebugMode) {
      print('$_errorTag ProfileScreen: Error refreshing videos: $error');
    }
  }

  static void logVideoSelection(
      {required String videoId, required bool isSelected}) {
    if (kDebugMode) {
      final action = isSelected ? 'selected' : 'deselected';
      print('$_videoTag ProfileScreen: Video $videoId $action');
    }
  }

  static void logVideoDeletion({required int count}) {
    if (kDebugMode) {
      print('$_videoTag ProfileScreen: Deleting $count videos...');
    }
  }

  static void logVideoDeletionSuccess({required int count}) {
    if (kDebugMode) {
      print('$_successTag ProfileScreen: Successfully deleted $count videos');
    }
  }

  static void logVideoDeletionError(String error) {
    if (kDebugMode) {
      print('$_errorTag ProfileScreen: Error deleting videos: $error');
    }
  }

  // Authentication
  static void logAuthCheck({bool? hasJwtToken, bool? hasFallbackUser}) {
    if (kDebugMode) {
      final jwtStatus =
          hasJwtToken != null ? (hasJwtToken ? 'Yes' : 'No') : 'Unknown';
      final fallbackStatus = hasFallbackUser != null
          ? (hasFallbackUser ? 'Yes' : 'No')
          : 'Unknown';
      print(
          '$_authTag ProfileScreen: Auth check - JWT: $jwtStatus, Fallback: $fallbackStatus');
    }
  }

  static void logGoogleSignIn() {
    if (kDebugMode) {
      print('$_authTag ProfileScreen: Initiating Google sign-in...');
    }
  }

  static void logGoogleSignInSuccess({String? userId}) {
    if (kDebugMode) {
      final userInfo = userId != null ? ' for user: $userId' : '';
      print('$_successTag ProfileScreen: Google sign-in successful$userInfo');
    }
  }

  static void logGoogleSignInError(String error) {
    if (kDebugMode) {
      print('$_errorTag ProfileScreen: Google sign-in failed: $error');
    }
  }

  static void logLogout() {
    if (kDebugMode) {
      print('$_authTag ProfileScreen: Logging out...');
    }
  }

  static void logLogoutSuccess() {
    if (kDebugMode) {
      print('$_successTag ProfileScreen: Logout successful');
    }
  }

  static void logLogoutError(String error) {
    if (kDebugMode) {
      print('$_errorTag ProfileScreen: Logout failed: $error');
    }
  }

  // Profile editing
  static void logProfileEditStart() {
    if (kDebugMode) {
      print('$_profileTag ProfileScreen: Starting profile edit...');
    }
  }

  static void logProfileEditCancel() {
    if (kDebugMode) {
      print('$_profileTag ProfileScreen: Profile edit cancelled');
    }
  }

  static void logProfileEditSave() {
    if (kDebugMode) {
      print('$_profileTag ProfileScreen: Saving profile changes...');
    }
  }

  static void logProfileEditSaveSuccess() {
    if (kDebugMode) {
      print('$_successTag ProfileScreen: Profile changes saved successfully');
    }
  }

  static void logProfileEditSaveError(String error) {
    if (kDebugMode) {
      print('$_errorTag ProfileScreen: Error saving profile changes: $error');
    }
  }

  // Profile photo management
  static void logProfilePhotoChange() {
    if (kDebugMode) {
      print('$_profileTag ProfileScreen: Changing profile photo...');
    }
  }

  static void logProfilePhotoChangeSuccess() {
    if (kDebugMode) {
      print('$_successTag ProfileScreen: Profile photo updated successfully');
    }
  }

  static void logProfilePhotoChangeError(String error) {
    if (kDebugMode) {
      print('$_errorTag ProfileScreen: Error changing profile photo: $error');
    }
  }

  // Payment setup
  static void logPaymentSetupCheck() {
    if (kDebugMode) {
      print('$_paymentTag ProfileScreen: Checking payment setup status...');
    }
  }

  static void logPaymentSetupFound({String? method}) {
    if (kDebugMode) {
      final methodInfo = method != null ? ' with method: $method' : '';
      print('$_successTag ProfileScreen: Payment setup found$methodInfo');
    }
  }

  static void logPaymentSetupNotFound() {
    if (kDebugMode) {
      print('$_warningTag ProfileScreen: No payment setup found');
    }
  }

  static void logPaymentSetupCheckError(String error) {
    if (kDebugMode) {
      print('$_errorTag ProfileScreen: Error checking payment setup: $error');
    }
  }

  // Cache management
  static void logCacheStats(Map<String, dynamic> stats) {
    if (kDebugMode) {
      print('$_cacheTag ProfileScreen: Cache stats: $stats');
    }
  }

  static void logCacheClear() {
    if (kDebugMode) {
      print('$_cacheTag ProfileScreen: Clearing cache...');
    }
  }

  static void logCacheClearSuccess() {
    if (kDebugMode) {
      print('$_successTag ProfileScreen: Cache cleared successfully');
    }
  }

  static void logCacheClearError(String error) {
    if (kDebugMode) {
      print('$_errorTag ProfileScreen: Error clearing cache: $error');
    }
  }

  // API operations
  static void logApiCall({required String endpoint, String? method}) {
    if (kDebugMode) {
      final methodInfo = method != null ? ' ($method)' : '';
      print('$_apiTag ProfileScreen: API call to $endpoint$methodInfo');
    }
  }

  static void logApiResponse(
      {required String endpoint, required int statusCode, String? body}) {
    if (kDebugMode) {
      final bodyInfo = body != null ? ' - Body: $body' : '';
      print(
          '$_apiTag ProfileScreen: API response from $endpoint - Status: $statusCode$bodyInfo');
    }
  }

  static void logApiError({required String endpoint, required String error}) {
    if (kDebugMode) {
      print('$_errorTag ProfileScreen: API error calling $endpoint: $error');
    }
  }

  // Debug operations
  static void logDebugState({Map<String, dynamic>? state}) {
    if (kDebugMode) {
      if (state != null) {
        print('$_debugTag ProfileScreen: Debug state: $state');
      } else {
        print('$_debugTag ProfileScreen: Debug state requested');
      }
    }
  }

  static void logDebugInfo(String info) {
    if (kDebugMode) {
      print('$_debugTag ProfileScreen: $info');
    }
  }

  static void logDebugWarning(String warning) {
    if (kDebugMode) {
      print('$_warningTag ProfileScreen: $warning');
    }
  }

  static void logDebugError(String error) {
    if (kDebugMode) {
      print('$_errorTag ProfileScreen: $error');
    }
  }

  // General info, success, warning, and error logging
  static void logInfo(String message) {
    if (kDebugMode) {
      print('$_tag ProfileScreen: $message');
    }
  }

  static void logSuccess(String message) {
    if (kDebugMode) {
      print('$_successTag ProfileScreen: $message');
    }
  }

  static void logWarning(String message) {
    if (kDebugMode) {
      print('$_warningTag ProfileScreen: $message');
    }
  }

  static void logError(String message) {
    if (kDebugMode) {
      print('$_errorTag ProfileScreen: $message');
    }
  }
}
