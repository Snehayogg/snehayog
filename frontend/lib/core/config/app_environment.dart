enum AppEnvironment { development, staging, production }

/// Centralized environment configuration for the Vayu app
class AppEnvironmentConfig {
  static AppEnvironment _currentEnvironment = AppEnvironment.development;

  /// Get the current app environment
  static AppEnvironment get current => _currentEnvironment;

  /// Set the current app environment
  static void setEnvironment(AppEnvironment environment) {
    _currentEnvironment = environment;
  }

  /// Check if the app is running in development mode
  static bool get isDevelopment =>
      _currentEnvironment == AppEnvironment.development;

  /// Check if the app is running in staging mode
  static bool get isStaging => _currentEnvironment == AppEnvironment.staging;

  /// Check if the app is running in production mode
  static bool get isProduction =>
      _currentEnvironment == AppEnvironment.production;

  /// Get environment-specific configuration
  static Map<String, dynamic> get config {
    switch (_currentEnvironment) {
      case AppEnvironment.development:
        return _developmentConfig;
      case AppEnvironment.staging:
        return _stagingConfig;
      case AppEnvironment.production:
        return _productionConfig;
    }
  }

  /// Development environment configuration
  static const Map<String, dynamic> _developmentConfig = {
    'apiBaseUrl': 'https://snehayog-production.up.railway.app',
    'enableLogging': true,
    'enableDebugMode': true,
    'videoCacheSize': 100 * 1024 * 1024,
    'maxVideoDuration': Duration(minutes: 10),
    'enableHLS': true,
    'enableAds': false,
    'enableAnalytics': false,
  };

  /// Staging environment configuration
  static const Map<String, dynamic> _stagingConfig = {
    'apiBaseUrl': 'https://staging-api.snehayog.com',
    'enableLogging': true,
    'enableDebugMode': false,
    'videoCacheSize': 200 * 1024 * 1024, // 200MB
    'maxVideoDuration': Duration(minutes: 15),
    'enableHLS': true,
    'enableAds': true,
    'enableAnalytics': true,
  };

  /// Production environment configuration
  static const Map<String, dynamic> _productionConfig = {
    'apiBaseUrl': 'https://snehayog-production.up.railway.app',
    'enableLogging': false,
    'enableDebugMode': false,
    'videoCacheSize': 500 * 1024 * 1024, // 500MB
    'maxVideoDuration': Duration(minutes: 20),
    'enableHLS': true,
    'enableAds': true,
    'enableAnalytics': true,
  };

  /// Get a specific configuration value
  static T getValue<T>(String key, {T? defaultValue}) {
    final value = config[key];
    if (value is T) return value;

    if (defaultValue != null) return defaultValue;

    throw ArgumentError('Configuration key "$key" not found or has wrong type');
  }

  /// Get the API base URL for the current environment
  static String get apiBaseUrl => getValue<String>('apiBaseUrl');

  /// Check if logging is enabled for the current environment
  static bool get enableLogging => getValue<bool>('enableLogging');

  /// Check if debug mode is enabled for the current environment
  static bool get enableDebugMode => getValue<bool>('enableDebugMode');

  /// Get video cache size for the current environment
  static int get videoCacheSize => getValue<int>('videoCacheSize');

  /// Get maximum video duration for the current environment
  static Duration get maxVideoDuration =>
      getValue<Duration>('maxVideoDuration');

  /// Check if HLS is enabled for the current environment
  static bool get enableHLS => getValue<bool>('enableHLS');

  /// Check if ads are enabled for the current environment
  static bool get enableAds => getValue<bool>('enableAds');

  /// Check if analytics are enabled for the current environment
  static bool get enableAnalytics => getValue<bool>('enableAnalytics');
}
