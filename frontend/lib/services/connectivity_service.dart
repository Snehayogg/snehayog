import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import 'package:vayu/utils/app_logger.dart';

/// **CONNECTIVITY SERVICE - Proactive internet connection checking**
///
/// Features:
/// - Real-time connectivity monitoring
/// - Proactive internet connection verification
/// - Network status streaming
class ConnectivityService {
  static final Connectivity _connectivity = Connectivity();
  static List<ConnectivityResult>? _lastKnownResult;

  /// **Check if device has active internet connection**
  /// This performs both connectivity check and actual network request verification
  static Future<bool> hasInternetConnection() async {
    try {
      // First check connectivity status
      final connectivityResults = await _connectivity.checkConnectivity();
      _lastKnownResult = connectivityResults;

      // If no connectivity at all, return false immediately
      if (connectivityResults.contains(ConnectivityResult.none) ||
          connectivityResults.isEmpty) {
        AppLogger.log('📡 ConnectivityService: No connectivity detected');
        return false;
      }

      // Double-check with actual network request (connectivity_plus can give false positives)
      try {
        final response = await http
            .get(Uri.parse('https://www.google.com'))
            .timeout(const Duration(seconds: 3));

        final hasInternet = response.statusCode == 200;
        AppLogger.log(
          '📡 ConnectivityService: Internet check result: $hasInternet',
        );
        return hasInternet;
      } catch (e) {
        AppLogger.log('📡 ConnectivityService: Internet check failed: $e');
        return false;
      }
    } catch (e) {
      AppLogger.log('📡 ConnectivityService: Error checking connectivity: $e');
      return false;
    }
  }

  /// **Check if device has any network connectivity (WiFi/Mobile)**
  /// This doesn't verify actual internet access, just network interface status
  static Future<bool> hasNetworkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _lastKnownResult = results;
      return !results.contains(ConnectivityResult.none) && results.isNotEmpty;
    } catch (e) {
      AppLogger.log('📡 ConnectivityService: Error checking network: $e');
      return false;
    }
  }

  /// **Get current connectivity results**
  static Future<List<ConnectivityResult>> getConnectivityResults() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _lastKnownResult = results;
      return results;
    } catch (e) {
      AppLogger.log('📡 ConnectivityService: Error getting connectivity: $e');
      return [ConnectivityResult.none];
    }
  }

  /// **Check if currently offline (no connectivity)**
  static bool isOffline(List<ConnectivityResult>? results) {
    if (results == null) {
      final lastKnown = _lastKnownResult;
      if (lastKnown == null) return true;
      return lastKnown.contains(ConnectivityResult.none) || lastKnown.isEmpty;
    }
    return results.contains(ConnectivityResult.none) || results.isEmpty;
  }

  /// **Stream of connectivity changes**
  /// Listen to this to react to connectivity changes in real-time
  static Stream<List<ConnectivityResult>> get connectivityStream =>
      _connectivity.onConnectivityChanged;

  /// **Get last known connectivity results (cached)**
  static List<ConnectivityResult>? get lastKnownResult => _lastKnownResult;

  /// **Check if specific error indicates no internet**
  static bool isNetworkError(dynamic error) {
    if (error == null) return false;

    final errorString = error.toString().toLowerCase();

    // Check for SocketException
    if (error is SocketException) return true;

    // Check for common network error strings
    if (errorString.contains('socketexception') ||
        errorString.contains('failed host lookup') ||
        errorString.contains('network is unreachable') ||
        errorString.contains('connection refused') ||
        errorString.contains('connection timed out') ||
        errorString.contains('no internet') ||
        errorString.contains('networkerror')) {
      return true;
    }

    return false;
  }

  /// **Get user-friendly message for network error**
  static String getNetworkErrorMessage(dynamic error) {
    if (error == null) {
      return 'Network error occurred';
    }

    final errorString = error.toString().toLowerCase();

    if (error is SocketException || errorString.contains('socketexception')) {
      return 'No internet connection. Please check your network settings.';
    }

    if (errorString.contains('failed host lookup') ||
        errorString.contains('network is unreachable')) {
      return 'Cannot reach server. Please check your internet connection.';
    }

    if (errorString.contains('connection refused')) {
      return 'Server connection refused. Please try again later.';
    }

    if (errorString.contains('connection timed out') ||
        errorString.contains('timeout')) {
      return 'Connection timed out. Please check your internet and try again.';
    }

    if (errorString.contains('no internet') ||
        errorString.contains('networkerror')) {
      return 'No internet connection. Please check your network.';
    }

    return 'Network error occurred. Please check your internet connection.';
  }
}
