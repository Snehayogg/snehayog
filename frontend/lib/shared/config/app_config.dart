import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:vayu/shared/services/http_client_service.dart';

/// Optimized app configuration for better performonce andsmaller size
class AppConfig {
  // **NEW: API Version (Date-Based)**
  static const String kApiVersion = '2026-02-08';

  // **MANUAL: Development mode control*
  static const bool _isDevelopment =
      false; // Set to true for local testing, false for production

  // **NEW: Smart URL selection with fallback**
  static String? _cachedBaseUrl;

  // Find your IP: Windows: ipconfig | Linux/Mac: ifconfig or ip address
  // Make sure your phone/emulator is on the same Wi‑Fi network
  static const String _localIpBaseUrl = 'http://192.168.0.187:5001';

  // Local development server (localhost) - for web
  static const String _localWebBaseUrl = 'http://localhost:5001';

  // Primary production endpoints
  static const String _customDomainUrl = 'https://api.snehayog.site';
  static const String _flyUrl = 'https://vayug.fly.dev';

  // Backend API configuration with smart fallback
  static String get baseUrl {
    // **FIX: For web, always use localhost, not IP address**
    if (kIsWeb) {
      // Web ke liye localhost use karein (development me)
      if (_isDevelopment) {
        _cachedBaseUrl = _localWebBaseUrl;
        return _localWebBaseUrl;
      }
      // Production web ke liye
      if (_cachedBaseUrl != null) {
        return _cachedBaseUrl!;
      }
      // Prefer Fly.io for production
      return _flyUrl;
    }

    // In development mode, prioritize local server but allow cached fallback
    if (_isDevelopment) {
      if (_cachedBaseUrl != null) {
        return _cachedBaseUrl!;
      }
      return _localIpBaseUrl;
    }

    // Production mode: use cache if available
    if (_cachedBaseUrl != null) {
      // **FIX: Ensure cached URL doesn't have redundant /api suffix**
      if (_cachedBaseUrl!.endsWith('/api')) {
        _cachedBaseUrl = _cachedBaseUrl!.substring(0, _cachedBaseUrl!.length - 4);
      }
      return _cachedBaseUrl!;
    }

    _cachedBaseUrl = _flyUrl; // TEMPORARY: Using Fly.io until custom domain SSL is configured
    return _cachedBaseUrl!;
  }

  /// **OPTIMIZED: Check server connectivity (helper method for parallel checks)**
  static Future<String?> _checkServer(String url) async {
    try {
      final response = await httpClientService.get(
        Uri.parse('$url/api/health'),
        headers: {'Content-Type': 'application/json'},
        timeout: const Duration(seconds: 2),
      );

      if (response.statusCode == 200) {
        print('✅ AppConfig: Server accessible at $url');
        return url;
      }
    } catch (e) {
      print('❌ AppConfig: Server not accessible at $url: $e');
    }
    return null;
  }

  // **OPTIMIZED: Try all servers in parallel and return the FIRST successful one (Race Condition)**
  static Future<String> getBaseUrlWithFallback() async {
    return _findBestServerUrl(source: 'getBaseUrlWithFallback');
  }

  // **OPTIMIZED: Check server connectivity - parallel checks for faster response**
  static Future<String> checkAndUpdateServerUrl() async {
     return _findBestServerUrl(source: 'checkAndUpdateServerUrl');
  }

  // **NEW: Private helper to implement "Race to Success" pattern**
  static Future<String> _findBestServerUrl({required String source}) async {
    // **FIX: For web, always use localhost**
    if (kIsWeb) {
      if (_isDevelopment) {
        print('🌐 AppConfig.$source: WEB DEVELOPMENT MODE');
        print('🌐 Using: $_localWebBaseUrl');
        _cachedBaseUrl = _localWebBaseUrl;
        return _localWebBaseUrl;
      }
      if (_cachedBaseUrl != null) return _cachedBaseUrl!;
      return _flyUrl;
    }

    // Use cache if available (Even in Dev mode, once discovered, we use it)
    if (_cachedBaseUrl != null) {
      return _cachedBaseUrl!;
    }

    // Use cache if available
    if (_cachedBaseUrl != null) {
      return _cachedBaseUrl!;
    }

    print('🔍 AppConfig: Starting parallel "Race to Success" check...');
    
    const localServerUrl = kIsWeb ? _localWebBaseUrl : _localIpBaseUrl;
    
    // Create a completer to handle the "first success" logic
    final completer = Completer<String>();
    
    // Define the candidate servers
    final candidates = [
      if (_isDevelopment) localServerUrl,
      _flyUrl,
      _customDomainUrl,
      if (!_isDevelopment) localServerUrl, // Last resort if not in dev
    ];
    
    int completedCount = 0;
    
    // Launch all checks simultaneously
    for (final url in candidates) {
      _checkServer(url).then((verifiedUrl) {
        // If we found a valid URL and haven't finished yet, declare victory!
        if (verifiedUrl != null && !completer.isCompleted) {
          print('✅ AppConfig: FAST WINNER found: $verifiedUrl');
          completer.complete(verifiedUrl);
        }
      }).whenComplete(() {
        completedCount++;
        // If all checks finished and none succeeded, use fallback
        if (completedCount == candidates.length && !completer.isCompleted) {
          print('⚠️ AppConfig: All servers unreachable, using default fallback');
          completer.complete(_flyUrl);
        }
      });
    }

    // Wait for the winner (or default fallback)
    final winner = await completer.future;
    _cachedBaseUrl = winner;
    return winner;
  }

  // **NEW: Reset cached URL (useful for retry scenarios)**
  static void resetCachedUrl() {
    _cachedBaseUrl = null;
    print('🔄 AppConfig: Cached URL reset, will recheck on next request');
  }

  // **NEW: Fallback URLs - custom domain first for production**
  static const List<String> fallbackUrls = [
    _flyUrl,
    _customDomainUrl,
  ];

  // **NEW: Network timeout configurations**
  static const Duration authTimeout = Duration(seconds: 30);
  static const Duration apiTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(minutes: 10);

  static const int maxRetries = 3;
  static const Duration retryDelay = Duration(seconds: 2);

  // Ad configuration
  static const int minAdBudget = 1; // Minimum daily budget in dollars

  // **NEW: Fixed CPM for India market**
  static const double fixedCpm = 30.0;
  static const double bannerCpm = 10.0;

  static const double creatorRevenueShare = 0.80;
  static const double platformRevenueShare = 0.20;

  static const String razorpayKeyId = 'rzp_test_RBiIx4GqiPJgsc';
  static const String razorpayKeySecret = 'ZfJRn3obw6qAg3FkZuEN8CkD';
  static const String razorpayWebhookSecret = 'M_6mvVtUguwMwp3';

  static const List<String> supportedPaymentMethods = [
    'card',
    'netbanking',
    'wallet',
    'upi',
    'paytm',
    'phonepe',
    'amazonpay',
    'googlepay',
    'applepay',
  ];

  // **NEW: Ad Serving Rules**
  static const int adInsertionFrequency =
      2; // Every alternate screen (2nd screen)
  static const int maxAdsPerSession = 10; // Maximum ads shown per user session

  // **NEW: Enhanced Ad Serving Logic**
  static const Map<String, Map<String, dynamic>> adTypeConfig = {
    'banner': {
      'cpm': 10.0, // ₹10 per 1000 impressions
      'maxFileSize': 5 * 1024 * 1024, // 5MB
      'supportedFormats': ['jpg', 'jpeg', 'png', 'gif', 'webp'],
      'displayFrequency': 2, // Every 2nd screen
      'priority': 1, // Lower priority than video ads
      'estimatedImpressionsPerDay': 50000, // Based on user base
    },
    'carousel': {
      'cpm': 30.0, // ₹30 per 1000 impressions
      'maxFileSize': 10 * 1024 * 1024, // 10MB
      'supportedFormats': ['jpg', 'jpeg', 'png', 'gif', 'webp'],
      'displayFrequency': 3, // Every 3rd screen
      'priority': 2, // Medium priority
      'estimatedImpressionsPerDay': 25000,
    },
  };

  // **NEW: Campaign Duration & Budget Logic**
  static const Map<String, int> campaignDurationLimits = {
    'min_days': 1,
    'max_days': 365,
    'recommended_min_days': 7,
    'recommended_max_days': 90,
  };

  // **NEW: Budget & Impression Management**
  static const Map<String, dynamic> budgetConfig = {
    'min_daily_budget': 100.0, // ₹100 minimum
    'max_daily_budget': 10000.0, // ₹10,000 maximum
    'budget_multiplier': 1.0, // For campaign duration
    'impression_buffer': 0.1, // 10% buffer for over-delivery
  };

  // **NEW: Ad Serving Algorithm Parameters**
  static const Map<String, dynamic> servingConfig = {
    'impression_frequency_cap': 3, // Max impressions per user per day
    'session_frequency_cap': 5, // Max impressions per user session
    'quality_score_threshold': 0.7, // Minimum quality score for ad display
    'relevance_threshold': 0.6, // Minimum relevance score
    'competition_window': 300, // 5 minutes between competing ads
  };

  // **NEW: Calculate campaign metrics**
  static Map<String, dynamic> calculateCampaignMetrics({
    required double dailyBudget,
    required int campaignDays,
    required String adType,
  }) {
    final config = adTypeConfig[adType] ?? adTypeConfig['banner']!;
    final cpm = config['cpm'] as double;
    final estimatedDailyImpressions =
        config['estimatedImpressionsPerDay'] as int;

    // Calculate total budget
    final totalBudget = dailyBudget * campaignDays;

    // Calculate expected impressions
    final expectedImpressions = (totalBudget / cpm) * 1000;

    // Calculate daily impressions
    final dailyImpressions = (expectedImpressions / campaignDays).round();

    // Calculate actual campaign duration based on budget
    final actualDuration =
        (expectedImpressions / estimatedDailyImpressions).ceil();

    return {
      'totalBudget': totalBudget,
      'expectedImpressions': expectedImpressions,
      'dailyImpressions': dailyImpressions,
      'estimatedDuration': actualDuration,
      'cpm': cpm,
      'dailyBudget': dailyBudget,
      'campaignDays': campaignDays,
    };
  }

  // **NEW: Validate campaign parameters**
  static Map<String, dynamic> validateCampaign({
    required double dailyBudget,
    required int campaignDays,
    required String adType,
  }) {
    final errors = <String>[];
    final warnings = <String>[];

    // Budget validation
    if (dailyBudget < budgetConfig['min_daily_budget']) {
      errors.add(
          'Daily budget must be at least ₹${budgetConfig['min_daily_budget']}');
    }
    if (dailyBudget > budgetConfig['max_daily_budget']) {
      errors.add(
          'Daily budget cannot exceed ₹${budgetConfig['max_daily_budget']}');
    }

    // Duration validation
    if (campaignDays < campaignDurationLimits['min_days']!) {
      errors.add(
          'Campaign must run for at least ${campaignDurationLimits['min_days']} day');
    }
    if (campaignDays > campaignDurationLimits['max_days']!) {
      errors.add(
          'Campaign cannot exceed ${campaignDurationLimits['max_days']} days');
    }

    // Recommendations
    if (campaignDays < campaignDurationLimits['recommended_min_days']!) {
      warnings.add(
          'Consider running for at least ${campaignDurationLimits['recommended_min_days']} days for better results');
    }
    if (campaignDays > campaignDurationLimits['recommended_max_days']!) {
      warnings.add(
          'Long campaigns may have diminishing returns. Consider shorter, focused campaigns');
    }

    // Calculate metrics
    final metrics = calculateCampaignMetrics(
      dailyBudget: dailyBudget,
      campaignDays: campaignDays,
      adType: adType,
    );

    return {
      'isValid': errors.isEmpty,
      'errors': errors,
      'warnings': warnings,
      'metrics': metrics,
    };
  }

  // Media upload configuration
  static const int maxImageSize = 5 * 1024 * 1024;
  static const int maxVideoSize = 400 * 1024 * 1024;

  // **NEW: Cloudinary Configuration for HLS Streaming**
  // Note: API credentials should be fetched from backend for security
  static const String cloudinaryCloudName = 'dkklingts';

  // SECURITY WARNING: Never hardcode API secrets in frontend code!
  // These should be fetched from backend API endpoints
  static const String cloudinaryApiKey = ''; // Empty - fetch from backend
  static const String cloudinaryApiSecret =
      ''; // Empty - never store in frontend

  // Cloudinary streaming profiles - Cost optimized (720p max)
  static const Map<String, Map<String, dynamic>> streamingProfiles = {
    'portrait_reels': {
      'name': 'Portrait Reels',
      'aspect_ratio': '9:16',
      'quality_levels': [
        {
          'resolution': '720x1280',
          'bitrate': '1.8 Mbps',
          'profile': 'HD'
        }, // 720p as highest
        {'resolution': '480x854', 'bitrate': '0.9 Mbps', 'profile': 'SD'},
        {'resolution': '360x640', 'bitrate': '0.6 Mbps', 'profile': 'SD'},
        {'resolution': '240x427', 'bitrate': '0.3 Mbps', 'profile': 'LOW'},
      ],
      'segment_duration': 2,
      'keyframe_interval': 2,
      'optimized_for': 'Mobile Scrolling - Cost Optimized'
    },
    'landscape_standard': {
      'name': 'Landscape Standard',
      'aspect_ratio': '16:9',
      'quality_levels': [
        {
          'resolution': '1280x720',
          'bitrate': '2.0 Mbps',
          'profile': 'HD'
        }, // 720p as highest
        {'resolution': '854x480', 'bitrate': '1.0 Mbps', 'profile': 'SD'},
        {'resolution': '640x360', 'bitrate': '0.5 Mbps', 'profile': 'LOW'},
      ],
      'segment_duration': 2,
      'keyframe_interval': 2,
      'optimized_for': 'Standard Video - Cost Optimized'
    }
  };

  // HLS streaming configuration
  static const Map<String, dynamic> hlsConfig = {
    'segment_duration': 2, // 2 seconds per segment
    'keyframe_interval': 60, // 2 seconds at 30fps
    'abr_enabled': true, // Adaptive Bitrate enabled
    'buffer_size': 10, // 10 seconds buffer
    'hls_version': '3',
    'compatibility': 'modern'
  };

  // Ad types supported
  static const List<String> supportedAdTypes = [
    'banner',
    'interstitial',
    'rewarded',
    'native'
  ];

  // Ad statuses
  static const List<String> adStatuses = [
    'draft',
    'active',
    'paused',
    'completed'
  ];

  // Target audience options
  static const List<String> targetAudienceOptions = [
    'all',
    'youth',
    'professionals',
    'students',
    'parents',
    'seniors'
  ];

  // **NEW: Helper methods for revenue calculations**
  static double calculateCreatorRevenue(double adSpend) {
    return adSpend * creatorRevenueShare;
  }

  static double calculatePlatformRevenue(double adSpend) {
    return adSpend * platformRevenueShare;
  }

  static double calculateCpmFromBudget(double budget, int impressions) {
    if (impressions <= 0) return 0.0;
    return (budget / impressions) * 1000;
  }

  static int calculateImpressionsFromBudget(double budget) {
    return (budget / fixedCpm * 1000).round();
  }

  static int calculateImpressionsFromBudgetWithCpm(double budget, double cpm) {
    return (budget / cpm * 1000).round();
  }

  // **NEW: AdMob Configuration**
  // Delegates to AdMobConfig for modular approach
  static String? get adMobBannerAdUnitId {
    // Import and use AdMobConfig
    // This getter provides backward compatibility
    try {
      // Dynamic import to avoid circular dependencies
      // AdMobConfig will be imported where needed
      return null; // Will be resolved by AdMobConfig
    } catch (e) {
      return null;
    }
  }
}

/// Optimized network helper for better performance
class NetworkHelper {
  /// Get the appropriate server URL based on the environment
  static String getServerUrl() => AppConfig.baseUrl;

  /// Get the appropriate base URL for the current environment
  static String getBaseUrl() => AppConfig.baseUrl;

  /// Get base URL with automatic Railway first, local fallback (async version)
  static Future<String> getBaseUrlAsync() => AppConfig.getBaseUrlWithFallback();

  /// Get base URL with fallback: Custom Domain → Railway → Local Server
  static Future<String> getBaseUrlWithFallback() =>
      AppConfig.getBaseUrlWithFallback();

  /// API endpoints
  static String get apiBaseUrl {
    // **FIX: Robustly handle redundant /api prefixes using regex**
    // This strips all occurrences of /api and appends it once
    final base = AppConfig.baseUrl.replaceAll(RegExp(r'(/+api)+$'), '');
    return '$base/api';
  }

  static String get healthEndpoint => '$apiBaseUrl/health';
  static String get videosEndpoint => '$apiBaseUrl/videos';
  static String get authEndpoint => '$apiBaseUrl/auth';
  static String get usersEndpoint => '$apiBaseUrl/users';
  static String get adsEndpoint => '$apiBaseUrl/ads';

  /// Network timeout configurations - Increased for better remote connectivity
  static const Duration defaultTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(minutes: 5);
  static const Duration shortTimeout = Duration(seconds: 30);

  /// Retry configurations - Enhanced for better reliability
  static const int defaultMaxRetries = 3;
  static const Duration defaultRetryDelay = Duration(seconds: 2);

  /// File size limits
  static const int maxVideoFileSize = 400 * 1024 * 1024; // 400MB
  static const int maxImageFileSize = 5 * 1024 * 1024; // 5MB

  /// Valid file extensions
  static const List<String> validVideoExtensions = [
    'mp4',
    'avi',
    'mov',
    'wmv',
    'flv',
    'webm'
  ];

  static const List<String> validImageExtensions = [
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp'
  ];

  /// Validation methods
  static bool isValidVideoExtension(String extension) {
    return validVideoExtensions.contains(extension.toLowerCase());
  }

  static bool isValidImageExtension(String extension) {
    return validImageExtensions.contains(extension.toLowerCase());
  }

  /// File size formatting
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Check if file size is within limits
  static bool isFileSizeValid(int fileSize, {bool isVideo = true}) {
    final maxSize = isVideo ? maxVideoFileSize : maxImageFileSize;
    return fileSize <= maxSize;
  }

  /// **NEW: Check if custom domain is accessible**
  static Future<bool> isCustomDomainAccessible() async {
    try {
      print('🔍 NetworkHelper: Checking custom domain accessibility...');
      final response = await http.get(
        Uri.parse('${AppConfig._customDomainUrl}/api/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      final isAccessible = response.statusCode == 200;
      print('🔍 NetworkHelper: Custom domain accessible: $isAccessible');
      return isAccessible;
    } catch (e) {
      print('❌ NetworkHelper: Custom domain not accessible: $e');
      return false;
    }
  }

  /// **UPDATED: Get best available server URL - Custom Domain → Railway → Local Server**
  static Future<String> getBestServerUrl() async {
    // Use AppConfig's getBaseUrlWithFallback which prioritizes: Custom Domain → Railway → Local Server
    return await AppConfig.getBaseUrlWithFallback();
  }
}
