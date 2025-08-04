/// App configuration for different environments
class AppConfig {
  // Base URL for API endpoints
  static String baseUrl = "http://192.168.0.190:5000";

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

  /// Get the appropriate base URL for the current environment
  static String getBaseUrl() {
    return AppConfig.baseUrl;
  }
}
