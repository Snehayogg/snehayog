/// App configuration for different environments
class AppConfig {
  // Server configuration
  static const String serverIP =
      '192.168.0.195'; // Change this to your computer's IP
  static const int serverPort = 5000;

  // Base URL for API endpoints
  static String get baseUrl => 'http://$serverIP:$serverPort';

  // App settings
  static const String appName = 'Snehayog';
  static const String appVersion = '1.0.0';

  // Video settings
  static const int maxVideoDuration = 120; // 2 minutes in seconds
  static const int maxFileSize = 100 * 1024 * 1024; // 100MB in bytes

  // Network settings
  static const int requestTimeout = 30; // seconds
  static const int uploadTimeout = 300; // 5 minutes for uploads

  // Debug settings
  static const bool enableDebugLogs = true;
  static const bool enableNetworkLogs = true;
}

/// Helper class for network operations
class NetworkHelper {
  /// Get the appropriate server URL based on the environment
  static String getServerUrl() {
    return AppConfig.baseUrl;
  }

  /// Check if running on physical device
  static bool isPhysicalDevice() {
    // This is a simple check - you might want to implement more sophisticated detection
    return true; // Assume physical device for now
  }

  /// Get the appropriate base URL for the current environment
  static String getBaseUrl() {
    if (isPhysicalDevice()) {
      // For physical device, use computer's IP address
      return AppConfig.baseUrl;
    } else {
      // For emulator, use 10.0.2.2
      return 'http://10.0.2.2:${AppConfig.serverPort}';
    }
  }
}
