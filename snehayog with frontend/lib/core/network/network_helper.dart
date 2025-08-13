import 'package:flutter/foundation.dart';

/// Centralized network configuration and helper methods
class NetworkHelper {
  static const String _devBaseUrl = 'http://10.0.2.2:3000';
  static const String _prodBaseUrl = 'https://your-production-url.com';
  
  /// Returns the appropriate base URL based on build configuration
  static String get baseUrl {
    if (kDebugMode) {
      return _devBaseUrl;
    }
    return _prodBaseUrl;
  }
  
  /// Returns the API base URL
  static String get apiBaseUrl => '$baseUrl/api';
  
  /// Returns the health check endpoint
  static String get healthEndpoint => '$baseUrl/api/health';
  
  /// Returns the videos endpoint
  static String get videosEndpoint => '$apiBaseUrl/videos';
  
  /// Returns the auth endpoint
  static String get authEndpoint => '$apiBaseUrl/auth';
  
  /// Returns the users endpoint
  static String get usersEndpoint => '$apiBaseUrl/users';
  
  /// Network timeout configurations
  static const Duration defaultTimeout = Duration(seconds: 15);
  static const Duration uploadTimeout = Duration(minutes: 5);
  static const Duration shortTimeout = Duration(seconds: 5);
  
  /// Retry configurations
  static const int defaultMaxRetries = 2;
  static const Duration defaultRetryDelay = Duration(seconds: 1);
  
  /// File size limits
  static const int maxVideoFileSize = 100 * 1024 * 1024; // 100MB
  static const int maxThumbnailFileSize = 5 * 1024 * 1024; // 5MB
  
  /// Valid video file extensions
  static const List<String> validVideoExtensions = [
    'mp4', 'avi', 'mov', 'wmv', 'flv', 'webm'
  ];
  
  /// Valid image file extensions
  static const List<String> validImageExtensions = [
    'jpg', 'jpeg', 'png', 'gif', 'webp'
  ];
  
  /// Checks if a file extension is valid for videos
  static bool isValidVideoExtension(String extension) {
    return validVideoExtensions.contains(extension.toLowerCase());
  }
  
  /// Checks if a file extension is valid for images
  static bool isValidImageExtension(String extension) {
    return validImageExtensions.contains(extension.toLowerCase());
  }
  
  /// Formats file size for display
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
