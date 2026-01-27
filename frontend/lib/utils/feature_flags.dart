import 'package:flutter/material.dart';

/// Feature flags system to safely roll out new features
/// This helps prevent regressions by allowing gradual feature releases
class FeatureFlags {
  // Private constructor for singleton pattern
  FeatureFlags._();
  static final FeatureFlags _instance = FeatureFlags._();
  static FeatureFlags get instance => _instance;

  // Feature flag storage
  final Map<String, bool> _flags = {
    // Video features
    'enhanced_video_controls': false,
    'video_quality_selector': false,
    'offline_video_download': false,
    'video_analytics': true,

    // NEW: Fast Video Delivery System
    'fast_video_delivery': true, // Main feature flag
    'background_video_preloading': true, // Preload next videos
    'smart_video_caching': false, // Smart caching strategy
    'instant_video_playback': true, // Zero loading time
    'video_memory_optimization': true, // Memory management

    // Profile features
    'enhanced_profile_loading': true, // NEW: Control new profile loading logic
    'profile_video_playback_fix':
        true, // NEW: Control video playback fix - ENABLED FOR TESTING

    // UI features
    'new_ui_theme': false,
    'dark_mode': true,
    'improved_navigation': false,

    // Performance features
    'lazy_loading_optimization': true,
    'image_caching_v2': false,
    'background_video_processing': false,

    // Social features
    'comment_reactions': false,
    'live_streaming': false,
    'user_stories': false,

    // Experimental features
    'ai_content_moderation': false,
    'real_time_notifications': false,
    'advanced_search': false,
  };

  /// Check if a feature is enabled
  bool isEnabled(String featureName) {
    return _flags[featureName] ?? false;
  }

  /// Enable a feature (for testing or gradual rollout)
  void enable(String featureName) {
    _flags[featureName] = true;
  }

  /// Disable a feature (for quick rollback)
  void disable(String featureName) {
    _flags[featureName] = false;
  }

  /// Get all feature flags (for admin/debug purposes)
  Map<String, bool> getAllFlags() {
    return Map.unmodifiable(_flags);
  }

  /// Load feature flags from remote config (implement as needed)
  Future<void> loadRemoteFlags() async {
    // TODO: Implement remote config loading
    // This could load from Firebase Remote Config, custom API, etc.
    try {
      // Example: await FirebaseRemoteConfig.instance.fetchAndActivate();
      // Update _flags based on remote values
    } catch (e) {
      print('Failed to load remote feature flags: $e');
      // Fall back to default values
    }
  }

  /// Update flags for specific user segments (A/B testing)
  void updateForUserSegment(String userId, Map<String, bool> segmentFlags) {
    // Apply user-specific or segment-specific flags
    _flags.addAll(segmentFlags);
  }
}

/// Extension to make feature flag checking more convenient
extension FeatureFlagContext on String {
  bool get isEnabled => FeatureFlags.instance.isEnabled(this);
}

/// Commonly used feature flags as constants
class Features {
  static const String enhancedVideoControls = 'enhanced_video_controls';
  static const String videoQualitySelector = 'video_quality_selector';
  static const String offlineVideoDownload = 'offline_video_download';
  static const String videoAnalytics = 'video_analytics';

  // NEW: Fast Video Delivery System
  static const String fastVideoDelivery = 'fast_video_delivery';
  static const String backgroundVideoPreloading = 'background_video_preloading';
  static const String smartVideoCaching = 'smart_video_caching';
  static const String instantVideoPlayback = 'instant_video_playback';
  static const String videoMemoryOptimization = 'video_memory_optimization';

  // NEW: Profile features
  static const String enhancedProfileLoading = 'enhanced_profile_loading';
  static const String profileVideoPlaybackFix = 'profile_video_playback_fix';

  static const String newUITheme = 'new_ui_theme';
  static const String darkMode = 'dark_mode';
  static const String improvedNavigation = 'improved_navigation';
  static const String lazyLoadingOptimization = 'lazy_loading_optimization';
  static const String imageCachingV2 = 'image_caching_v2';
  static const String backgroundVideoProcessing = 'background_video_processing';
  static const String commentReactions = 'comment_reactions';
  static const String liveStreaming = 'live_streaming';
  static const String userStories = 'user_stories';
  static const String aiContentModeration = 'ai_content_moderation';
  static const String realTimeNotifications = 'real_time_notifications';
  static const String advancedSearch = 'advanced_search';
}

/// Widget wrapper for feature-flagged content

class FeatureGate extends StatelessWidget {
  final String featureName;
  final Widget child;
  final Widget? fallback;

  const FeatureGate({
    Key? key,
    required this.featureName,
    required this.child,
    this.fallback,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (FeatureFlags.instance.isEnabled(featureName)) {
      return child;
    }
    return fallback ?? const SizedBox.shrink();
  }
}
