import 'package:flutter/foundation.dart';
import 'network_service.dart';

/// Service to initialize the app with network fallback
class AppInitializationService {
  static bool _isInitialized = false;

  /// Initialize the app services
  static Future<void> initialize() async {
    if (_isInitialized) {
      if (kDebugMode) {
        print('🔄 AppInitializationService: Already initialized');
      }
      return;
    }

    if (kDebugMode) {
      print('🚀 AppInitializationService: Starting initialization...');
    }

    try {
      // Initialize network service with fallback support
      await NetworkService.instance.initialize();

      if (kDebugMode) {
        final networkInfo = NetworkService.instance.getConnectionInfo();
        print('✅ AppInitializationService: Network service initialized');
        print(
            '📍 AppInitializationService: Using server: ${networkInfo['currentUrl']}');
        print(
            '🏠 AppInitializationService: Is local server: ${networkInfo['isLocal']}');
      }

      _isInitialized = true;
    } catch (e) {
      if (kDebugMode) {
        print('❌ AppInitializationService: Initialization failed: $e');
      }
      rethrow;
    }
  }

  /// Get initialization status
  static bool get isInitialized => _isInitialized;

  /// Reset initialization (for testing)
  static void reset() {
    _isInitialized = false;
  }
}
