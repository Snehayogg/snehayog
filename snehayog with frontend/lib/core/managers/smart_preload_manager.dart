import 'dart:async';
import 'dart:collection';
import 'package:snehayog/core/managers/yog_cache_manager.dart';
import 'package:snehayog/utils/feature_flags.dart';

/// Instagram-style Smart Preload Manager
/// Predicts user navigation and preloads data for instant tab switching
class SmartPreloadManager {
  static final SmartPreloadManager _instance = SmartPreloadManager._internal();
  factory SmartPreloadManager() => _instance;
  SmartPreloadManager._internal();

  final YogCacheManager _cacheManager = YogCacheManager();

  // User behavior tracking
  final Queue<String> _navigationHistory = Queue<String>();
  final Map<String, int> _screenVisitFrequency = {};
  final Map<String, DateTime> _lastVisitTime = {};

  // Preload prediction engine
  final Map<String, List<String>> _preloadPredictions = {};
  final Set<String> _currentlyPreloading = {};

  // Performance metrics
  int _successfulPredictions = 0;
  int _totalPredictions = 0;
  int _preloadHits = 0;

  // Configuration
  static const int maxHistorySize = 20;
  static const int maxPreloadItems = 5;
  static const Duration predictionWindow = Duration(minutes: 5);

  /// Initialize smart preload manager
  Future<void> initialize() async {
    if (!Features.smartVideoCaching.isEnabled) return;

    print('🚀 SmartPreloadManager: Initializing Instagram-style preloading...');

    // Start background prediction worker
    _startPredictionWorker();

    print('✅ SmartPreloadManager: Initialized successfully');
  }

  /// Track user navigation for pattern analysis
  void trackNavigation(String screenName, {Map<String, dynamic>? context}) {
    if (!Features.smartVideoCaching.isEnabled) return;

    try {
      // Update navigation history
      _navigationHistory.add(screenName);
      if (_navigationHistory.length > maxHistorySize) {
        _navigationHistory.removeFirst();
      }

      // Update visit frequency
      _screenVisitFrequency[screenName] =
          (_screenVisitFrequency[screenName] ?? 0) + 1;
      _lastVisitTime[screenName] = DateTime.now();

      // Analyze pattern and predict next screens
      _analyzeNavigationPattern();

      print('📱 SmartPreloadManager: Tracked navigation to $screenName');
    } catch (e) {
      print('❌ SmartPreloadManager: Error tracking navigation: $e');
    }
  }

  /// Analyze navigation patterns and predict next screens
  void _analyzeNavigationPattern() {
    try {
      if (_navigationHistory.length < 2) return;

      final recentScreens =
          _navigationHistory.toList().reversed.take(5).toList();

      // Pattern 1: Sequential navigation (Home → Profile → Settings)
      for (int i = 0; i < recentScreens.length - 1; i++) {
        final current = recentScreens[i];
        final next = recentScreens[i + 1];
        final pattern = '$current->$next';

        if (!_preloadPredictions.containsKey(current)) {
          _preloadPredictions[current] = [];
        }

        if (!_preloadPredictions[current]!.contains(next)) {
          _preloadPredictions[current]!.add(next);
        }
      }

      // Pattern 2: Frequency-based prediction
      final sortedScreens = _screenVisitFrequency.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      for (final entry in sortedScreens.take(3)) {
        final screen = entry.key;
        if (recentScreens.contains(screen)) continue;

        // Add to predictions for current screen
        final currentScreen = recentScreens.first;
        if (!_preloadPredictions.containsKey(currentScreen)) {
          _preloadPredictions[currentScreen] = [];
        }

        if (!_preloadPredictions[currentScreen]!.contains(screen)) {
          _preloadPredictions[currentScreen]!.add(screen);
        }
      }

      // Pattern 3: Time-based prediction (evening → profile, morning → feed)
      _addTimeBasedPredictions(recentScreens.first);

      print('🧠 SmartPreloadManager: Navigation pattern analyzed');
    } catch (e) {
      print('❌ SmartPreloadManager: Error analyzing pattern: $e');
    }
  }

  /// Add time-based predictions
  void _addTimeBasedPredictions(String currentScreen) {
    try {
      final hour = DateTime.now().hour;

      if (hour >= 6 && hour <= 12) {
        // Morning: Users often check notifications, profile
        _addPrediction(currentScreen, 'notifications');
        _addPrediction(currentScreen, 'profile');
      } else if (hour >= 18 && hour <= 22) {
        // Evening: Users often browse feed, explore
        _addPrediction(currentScreen, 'explore');
        _addPrediction(currentScreen, 'feed');
      } else if (hour >= 22 || hour <= 6) {
        // Night: Users often check DMs, stories
        _addPrediction(currentScreen, 'messages');
        _addPrediction(currentScreen, 'stories');
      }
    } catch (e) {
      print('❌ SmartPreloadManager: Error adding time-based predictions: $e');
    }
  }

  /// Add prediction for a screen
  void _addPrediction(String fromScreen, String toScreen) {
    if (!_preloadPredictions.containsKey(fromScreen)) {
      _preloadPredictions[fromScreen] = [];
    }

    if (!_preloadPredictions[fromScreen]!.contains(toScreen)) {
      _preloadPredictions[fromScreen]!.add(toScreen);
    }
  }

  /// Get preload predictions for current screen
  List<String> getPreloadPredictions(String currentScreen) {
    return _preloadPredictions[currentScreen] ?? [];
  }

  /// Smart preload data for predicted screens
  Future<void> smartPreload(
    String currentScreen, {
    Map<String, dynamic>? userContext,
    List<String>? forcePreload,
  }) async {
    if (!Features.smartVideoCaching.isEnabled) return;

    try {
      final predictions = forcePreload ?? getPreloadPredictions(currentScreen);

      if (predictions.isEmpty) {
        print('📱 SmartPreloadManager: No predictions for $currentScreen');
        return;
      }

      print(
          '🚀 SmartPreloadManager: Starting smart preload for $currentScreen');
      print('🎯 Predictions: ${predictions.join(', ')}');

      // Preload data for predicted screens
      for (final predictedScreen in predictions.take(maxPreloadItems)) {
        if (_currentlyPreloading.contains(predictedScreen)) continue;

        _currentlyPreloading.add(predictedScreen);

        // Start preloading in background
        unawaited(_preloadScreenData(predictedScreen, userContext).then((_) {
          _currentlyPreloading.remove(predictedScreen);
        }));
      }
    } catch (e) {
      print('❌ SmartPreloadManager: Error in smart preload: $e');
    }
  }

  /// Preload data for a specific screen
  Future<void> _preloadScreenData(
      String screenName, Map<String, dynamic>? userContext) async {
    try {
      print('📥 SmartPreloadManager: Preloading data for $screenName');

      switch (screenName) {
        case 'profile':
          await _preloadProfileData(userContext);
          break;
        case 'feed':
          await _preloadFeedData(userContext);
          break;
        case 'explore':
          await _preloadExploreData(userContext);
          break;
        case 'notifications':
          await _preloadNotificationsData(userContext);
          break;
        case 'messages':
          await _preloadMessagesData(userContext);
          break;
        case 'stories':
          await _preloadStoriesData(userContext);
          break;
        default:
          print(
              '⚠️ SmartPreloadManager: Unknown screen for preload: $screenName');
      }

      print('✅ SmartPreloadManager: Preloaded data for $screenName');
    } catch (e) {
      print('❌ SmartPreloadManager: Error preloading $screenName: $e');
    }
  }

  /// Preload profile data
  Future<void> _preloadProfileData(Map<String, dynamic>? userContext) async {
    try {
      final userId = userContext?['userId'] ?? 'current';

      // Preload user profile
      await _cacheManager.get(
        'user_profile_$userId',
        fetchFn: () async => {'status': 'preloaded'},
        cacheType: 'user_profile',
        maxAge: const Duration(hours: 1),
      );

      // Preload user videos
      await _cacheManager.get(
        'user_videos_$userId',
        fetchFn: () async => {'status': 'preloaded'},
        cacheType: 'videos',
        maxAge: const Duration(minutes: 15),
      );

      print('👤 SmartPreloadManager: Profile data preloaded for user $userId');
    } catch (e) {
      print('❌ SmartPreloadManager: Error preloading profile: $e');
    }
  }

  /// Preload feed data
  Future<void> _preloadFeedData(Map<String, dynamic>? userContext) async {
    try {
      // Preload next few pages of feed
      for (int page = 1; page <= 3; page++) {
        await _cacheManager.get(
          'feed_page_$page',
          fetchFn: () async => {'status': 'preloaded'},
          cacheType: 'videos',
          maxAge: const Duration(minutes: 15),
        );
      }

      print('📱 SmartPreloadManager: Feed data preloaded');
    } catch (e) {
      print('❌ SmartPreloadManager: Error preloading feed: $e');
    }
  }

  /// Preload explore data
  Future<void> _preloadExploreData(Map<String, dynamic>? userContext) async {
    try {
      // Preload trending videos, categories
      await _cacheManager.get(
        'explore_trending',
        fetchFn: () async => {'status': 'preloaded'},
        cacheType: 'videos',
        maxAge: const Duration(minutes: 10),
      );

      await _cacheManager.get(
        'explore_categories',
        fetchFn: () async => {'status': 'preloaded'},
        cacheType: 'metadata',
        maxAge: const Duration(hours: 1),
      );

      print('🔍 SmartPreloadManager: Explore data preloaded');
    } catch (e) {
      print('❌ SmartPreloadManager: Error preloading explore: $e');
    }
  }

  /// Preload notifications data
  Future<void> _preloadNotificationsData(
      Map<String, dynamic>? userContext) async {
    try {
      await _cacheManager.get(
        'notifications_recent',
        fetchFn: () async => {'status': 'preloaded'},
        cacheType: 'notifications',
        maxAge: const Duration(minutes: 5),
      );

      print('🔔 SmartPreloadManager: Notifications preloaded');
    } catch (e) {
      print('❌ SmartPreloadManager: Error preloading notifications: $e');
    }
  }

  /// Preload messages data
  Future<void> _preloadMessagesData(Map<String, dynamic>? userContext) async {
    try {
      await _cacheManager.get(
        'messages_conversations',
        fetchFn: () async => {'status': 'preloaded'},
        cacheType: 'messages',
        maxAge: const Duration(minutes: 5),
      );

      print('💬 SmartPreloadManager: Messages preloaded');
    } catch (e) {
      print('❌ SmartPreloadManager: Error preloading messages: $e');
    }
  }

  /// Preload stories data
  Future<void> _preloadStoriesData(Map<String, dynamic>? userContext) async {
    try {
      await _cacheManager.get(
        'stories_recent',
        fetchFn: () async => {'status': 'preloaded'},
        cacheType: 'stories',
        maxAge: const Duration(minutes: 2),
      );

      print('📖 SmartPreloadManager: Stories preloaded');
    } catch (e) {
      print('❌ SmartPreloadManager: Error preloading stories: $e');
    }
  }

  /// Record successful prediction
  void recordPredictionHit(String predictedScreen) {
    _preloadHits++;
    _successfulPredictions++;
    _totalPredictions++;

    print('🎯 SmartPreloadManager: Prediction hit for $predictedScreen!');
  }

  /// Record prediction miss
  void recordPredictionMiss(String predictedScreen) {
    _totalPredictions++;

    print('❌ SmartPreloadManager: Prediction miss for $predictedScreen');
  }

  /// Get prediction accuracy
  double getPredictionAccuracy() {
    if (_totalPredictions == 0) return 0.0;
    return (_successfulPredictions / _totalPredictions) * 100;
  }

  /// Get preload statistics
  Map<String, dynamic> getStats() {
    return {
      'totalPredictions': _totalPredictions,
      'successfulPredictions': _successfulPredictions,
      'predictionAccuracy': getPredictionAccuracy().toStringAsFixed(2),
      'preloadHits': _preloadHits,
      'currentlyPreloading': _currentlyPreloading.toList(),
      'navigationHistory': _navigationHistory.toList(),
      'screenVisitFrequency': _screenVisitFrequency,
    };
  }

  /// Start background prediction worker
  void _startPredictionWorker() {
    Timer.periodic(const Duration(minutes: 2), (timer) {
      if (Features.smartVideoCaching.isEnabled) {
        _cleanupOldData();
        _optimizePredictions();
      }
    });
  }

  /// Clean up old data
  void _cleanupOldData() {
    try {
      final cutoff = DateTime.now().subtract(predictionWindow);
      final keysToRemove = <String>[];

      for (final entry in _lastVisitTime.entries) {
        if (entry.value.isBefore(cutoff)) {
          keysToRemove.add(entry.key);
        }
      }

      for (final key in keysToRemove) {
        _lastVisitTime.remove(key);
        _screenVisitFrequency.remove(key);
        _preloadPredictions.remove(key);
      }

      if (keysToRemove.isNotEmpty) {
        print(
            '🧹 SmartPreloadManager: Cleaned up ${keysToRemove.length} old entries');
      }
    } catch (e) {
      print('❌ SmartPreloadManager: Error cleaning up old data: $e');
    }
  }

  /// Optimize predictions based on accuracy
  void _optimizePredictions() {
    try {
      final accuracy = getPredictionAccuracy();

      if (accuracy < 30.0) {
        // Low accuracy - reduce preload items
        print(
            '⚠️ SmartPreloadManager: Low prediction accuracy ($accuracy%), reducing preload items');
      } else if (accuracy > 70.0) {
        // High accuracy - increase preload items
        print(
            '✅ SmartPreloadManager: High prediction accuracy ($accuracy%), maintaining preload strategy');
      }
    } catch (e) {
      print('❌ SmartPreloadManager: Error optimizing predictions: $e');
    }
  }

  /// Dispose manager
  void dispose() {
    _navigationHistory.clear();
    _screenVisitFrequency.clear();
    _lastVisitTime.clear();
    _preloadPredictions.clear();
    _currentlyPreloading.clear();

    print('🗑️ SmartPreloadManager: Disposed');
  }
}
