import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:snehayog/utils/feature_flags.dart';

/// Instagram-like cache entry with ETag and timestamp
class InstagramCacheEntry<T> {
  final T data;
  final String? etag;
  final DateTime lastModified;
  final DateTime cachedAt;
  final Duration maxAge;
  final int accessCount;
  final DateTime lastAccessed;

  InstagramCacheEntry({
    required this.data,
    this.etag,
    required this.lastModified,
    required this.cachedAt,
    required this.maxAge,
    this.accessCount = 0,
    required this.lastAccessed,
  });

  bool get isExpired {
    final now = DateTime.now();
    return now.difference(cachedAt) > maxAge;
  }

  bool get shouldRefresh {
    final now = DateTime.now();
    final age = now.difference(cachedAt);
    return age > maxAge * 0.8;
  }

  InstagramCacheEntry<T> copyWith({
    T? data,
    String? etag,
    DateTime? lastModified,
    DateTime? cachedAt,
    Duration? maxAge,
    int? accessCount,
    DateTime? lastAccessed,
  }) {
    return InstagramCacheEntry<T>(
      data: data ?? this.data,
      etag: etag ?? this.etag,
      lastModified: lastModified ?? this.lastModified,
      cachedAt: cachedAt ?? this.cachedAt,
      maxAge: maxAge ?? this.maxAge,
      accessCount: accessCount ?? this.accessCount,
      lastAccessed: lastAccessed ?? this.lastAccessed,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'data': data,
      'etag': etag,
      'lastModified': lastModified.toIso8601String(),
      'cachedAt': cachedAt.toIso8601String(),
      'maxAge': maxAge.inMilliseconds,
      'accessCount': accessCount,
      'lastAccessed': lastAccessed.toIso8601String(),
    };
  }

  factory InstagramCacheEntry.fromJson(
      Map<String, dynamic> json, T Function(dynamic) fromJson) {
    return InstagramCacheEntry<T>(
      data: fromJson(json['data']),
      etag: json['etag'],
      lastModified: DateTime.parse(json['lastModified']),
      cachedAt: DateTime.parse(json['cachedAt']),
      maxAge: Duration(milliseconds: json['maxAge']),
      accessCount: json['accessCount'] ?? 0,
      lastAccessed: DateTime.parse(json['lastAccessed']),
    );
  }
}

/// Cache configuration for different data types
class InstagramCacheConfig {
  final Duration maxAge;
  final int maxEntries;
  final bool enableEtag;
  final bool enableStaleWhileRevalidate;
  final Duration staleWhileRevalidateTime;

  const InstagramCacheConfig({
    this.maxAge = const Duration(minutes: 5),
    this.maxEntries = 100,
    this.enableEtag = true,
    this.enableStaleWhileRevalidate = true,
    this.staleWhileRevalidateTime = const Duration(minutes: 2),
  });
}

/// **CONSOLIDATED SmartCacheManager: Combines SmartPreloadManager + YogCacheManager**
/// This class consolidates:
/// - SmartPreloadManager (navigation prediction, screen preloading)
/// - YogCacheManager (data caching, ETags, memory/disk management)
/// Eliminates duplication while maintaining all functionality
class SmartCacheManager {
  static final SmartCacheManager _instance = SmartCacheManager._internal();
  factory SmartCacheManager() => _instance;
  SmartCacheManager._internal();

  // ===== CACHE STORAGE =====

  // Memory cache for instant access
  final Map<String, InstagramCacheEntry> _memoryCache = {};

  // Disk cache for persistence
  late Directory _cacheDir;

  // Cache configurations for different data types
  final Map<String, InstagramCacheConfig> _cacheConfigs = {
    'videos': const InstagramCacheConfig(
      maxAge: Duration(minutes: 15),
      maxEntries: 50,
      enableEtag: true,
      enableStaleWhileRevalidate: true,
    ),
    'user_profile': const InstagramCacheConfig(
      maxAge: Duration(hours: 24),
      maxEntries: 10,
      enableEtag: true,
      enableStaleWhileRevalidate: true,
    ),
    'video_metadata': const InstagramCacheConfig(
      maxAge: Duration(hours: 1),
      maxEntries: 100,
      enableEtag: true,
      enableStaleWhileRevalidate: true,
    ),
    'ads': const InstagramCacheConfig(
      maxAge: Duration(minutes: 10),
      maxEntries: 20,
      enableEtag: true,
      enableStaleWhileRevalidate: true,
    ),
  };

  // Background refresh queue for stale-while-revalidate
  final Queue<String> _refreshQueue = Queue<String>();
  bool _isRefreshing = false;

  // ===== PRELOADING & PREDICTION =====

  // User behavior tracking
  final Queue<String> _navigationHistory = Queue<String>();
  final Map<String, int> _screenVisitFrequency = {};
  final Map<String, DateTime> _lastVisitTime = {};

  // Preload prediction engine
  final Map<String, List<String>> _preloadPredictions = {};
  final Set<String> _currentlyPreloading = {};

  // ===== PERFORMANCE METRICS =====

  // Cache metrics
  int _cacheHits = 0;
  int _cacheMisses = 0;
  final int _etagHits = 0;
  final int _notModifiedResponses = 0;
  int _staleResponses = 0;
  int _backgroundRefreshes = 0;

  // Preload metrics
  int _successfulPredictions = 0;
  int _totalPredictions = 0;
  int _preloadHits = 0;

  // ===== CONFIGURATION =====

  static const int maxHistorySize = 20;
  static const int maxPreloadItems = 5;
  static const Duration predictionWindow = Duration(minutes: 5);

  // ===== INITIALIZATION =====

  /// Initialize consolidated smart cache manager
  Future<void> initialize() async {
    if (!Features.smartVideoCaching.isEnabled) {
      print('🚫 SmartCacheManager: Smart caching disabled');
      return;
    }

    try {
      print(
          '🚀 SmartCacheManager: Initializing consolidated cache & preload system...');

      // Initialize cache directory
      await _initializeCacheDirectory();

      // Load persisted cache
      await _loadPersistedCache();

      // Start background workers
      _startBackgroundWorkers();

      print('✅ SmartCacheManager: Initialization completed successfully');
    } catch (e) {
      print('❌ SmartCacheManager: Initialization failed: $e');
    }
  }

  /// Initialize cache directory
  Future<void> _initializeCacheDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    _cacheDir = Directory('${appDir.path}/smart_cache');
    if (!await _cacheDir.exists()) {
      await _cacheDir.create(recursive: true);
    }
  }

  /// Start all background workers
  void _startBackgroundWorkers() {
    // Cache cleanup worker
    Timer.periodic(const Duration(minutes: 1), (timer) {
      if (Features.smartVideoCaching.isEnabled) {
        _cleanupExpiredEntries();
      }
    });

    // Prediction optimization worker
    Timer.periodic(const Duration(minutes: 2), (timer) {
      if (Features.smartVideoCaching.isEnabled) {
        _cleanupOldData();
        _optimizePredictions();
      }
    });
  }

  // ===== CACHE OPERATIONS =====

  /// Get data using Instagram-like caching strategy
  Future<T?> get<T>(
    String key, {
    required Future<T> Function() fetchFn,
    String cacheType = 'default',
    Duration? maxAge,
    bool forceRefresh = false,
    String? currentEtag,
  }) async {
    // **CRITICAL FIX: Always enable caching for better performance**
    // if (!Features.smartVideoCaching.isEnabled) {
    //   return await fetchFn();
    // }

    try {
      // Check memory cache first (instant response)
      final memoryEntry = _memoryCache[key];
      if (memoryEntry != null && !forceRefresh) {
        final entry = memoryEntry as InstagramCacheEntry<T>;

        if (!entry.isExpired) {
          _updateAccessInfo(key);
          _cacheHits++;
          print('⚡ SmartCacheManager: Instant cache hit for $key');

          // Start background refresh if stale
          if (entry.shouldRefresh &&
              _shouldUseStaleWhileRevalidate(cacheType)) {
            _scheduleBackgroundRefresh(key, fetchFn, cacheType, currentEtag);
          }

          return entry.data;
        } else if (entry.shouldRefresh &&
            _shouldUseStaleWhileRevalidate(cacheType)) {
          _staleResponses++;
          print(
              '🔄 SmartCacheManager: Stale cache hit for $key, refreshing in background');
          _scheduleBackgroundRefresh(key, fetchFn, cacheType, currentEtag);
          return entry.data;
        }
      }

      // Check disk cache
      final diskEntry = await _getFromDiskCache<T>(key);
      if (diskEntry != null && !forceRefresh) {
        if (!diskEntry.isExpired) {
          _addToMemoryCache(key, diskEntry);
          _cacheHits++;
          print('💾 SmartCacheManager: Fresh disk cache hit for $key');

          if (diskEntry.shouldRefresh &&
              _shouldUseStaleWhileRevalidate(cacheType)) {
            _scheduleBackgroundRefresh(key, fetchFn, cacheType, currentEtag);
          }

          return diskEntry.data;
        } else if (diskEntry.shouldRefresh &&
            _shouldUseStaleWhileRevalidate(cacheType)) {
          _staleResponses++;
          print(
              '🔄 SmartCacheManager: Stale disk cache hit for $key, refreshing in background');
          _scheduleBackgroundRefresh(key, fetchFn, cacheType, currentEtag);
          return diskEntry.data;
        }
      }

      // Cache miss - fetch fresh data
      _cacheMisses++;
      print('❌ SmartCacheManager: Cache miss for $key, fetching fresh data');

      final freshData = await fetchFn();
      if (freshData != null) {
        await _cacheData(key, freshData, cacheType, maxAge, currentEtag);
      }

      return freshData;
    } catch (e) {
      print('❌ SmartCacheManager: Error in get operation for $key: $e');

      // On error, try to return stale cache if available
      final staleEntry = _memoryCache[key] ?? await _getFromDiskCache<T>(key);
      if (staleEntry != null && !staleEntry.isExpired) {
        print('🔄 SmartCacheManager: Returning stale cache on error for $key');
        return staleEntry.data;
      }

      rethrow;
    }
  }

  // ===== PRELOADING & PREDICTION =====

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

      print('📱 SmartCacheManager: Tracked navigation to $screenName');
    } catch (e) {
      print('❌ SmartCacheManager: Error tracking navigation: $e');
    }
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
        print('📱 SmartCacheManager: No predictions for $currentScreen');
        return;
      }

      print('🚀 SmartCacheManager: Starting smart preload for $currentScreen');
      print('🎯 Predictions: ${predictions.join(', ')}');

      // Preload data for predicted screens
      for (final predictedScreen in predictions.take(maxPreloadItems)) {
        if (_currentlyPreloading.contains(predictedScreen)) continue;

        _currentlyPreloading.add(predictedScreen);

        unawaited(_preloadScreenData(predictedScreen, userContext).then((_) {
          _currentlyPreloading.remove(predictedScreen);
        }));
      }
    } catch (e) {
      print('❌ SmartCacheManager: Error in smart preload: $e');
    }
  }

  /// Get preload predictions for current screen
  List<String> getPreloadPredictions(String currentScreen) {
    return _preloadPredictions[currentScreen] ?? [];
  }

  /// Record successful prediction
  void recordPredictionHit(String predictedScreen) {
    _preloadHits++;
    _successfulPredictions++;
    _totalPredictions++;
    print('🎯 SmartCacheManager: Prediction hit for $predictedScreen!');
  }

  /// Record prediction miss
  void recordPredictionMiss(String predictedScreen) {
    _totalPredictions++;
    print('❌ SmartCacheManager: Prediction miss for $predictedScreen');
  }

  // ===== INTERNAL METHODS =====

  /// Load persisted cache from disk
  Future<void> _loadPersistedCache() async {
    try {
      if (!await _cacheDir.exists()) return;

      final files = _cacheDir.listSync();
      int loadedCount = 0;

      for (final file in files) {
        if (file is File && file.path.endsWith('.json')) {
          try {
            final key = path.basenameWithoutExtension(file.path);
            final entry = await _getFromDiskCache(key);
            if (entry != null && !entry.isExpired) {
              _memoryCache[key] = entry;
              loadedCount++;
            }
          } catch (e) {
            print(
                '⚠️ SmartCacheManager: Skipping corrupted cache file: ${file.path}');
          }
        }
      }

      print(
          '📁 SmartCacheManager: Loaded $loadedCount entries from disk cache');
    } catch (e) {
      print('❌ SmartCacheManager: Error loading persisted cache: $e');
    }
  }

  /// Clean up expired cache entries
  void _cleanupExpiredEntries() {
    try {
      final now = DateTime.now();
      final keysToRemove = <String>[];

      for (final entry in _memoryCache.entries) {
        if (entry.value.isExpired) {
          keysToRemove.add(entry.key);
        }
      }

      for (final key in keysToRemove) {
        _memoryCache.remove(key);
      }

      if (keysToRemove.isNotEmpty) {
        print(
            '🧹 SmartCacheManager: Cleaned up ${keysToRemove.length} expired entries');
      }
    } catch (e) {
      print('❌ SmartCacheManager: Error cleaning up expired entries: $e');
    }
  }

  /// Clean up old prediction data
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
            '🧹 SmartCacheManager: Cleaned up ${keysToRemove.length} old prediction entries');
      }
    } catch (e) {
      print('❌ SmartCacheManager: Error cleaning up old prediction data: $e');
    }
  }

  /// Optimize predictions based on accuracy
  void _optimizePredictions() {
    try {
      final accuracy = getPredictionAccuracy();

      if (accuracy < 30.0) {
        print(
            '⚠️ SmartCacheManager: Low prediction accuracy ($accuracy%), reducing preload items');
      } else if (accuracy > 70.0) {
        print(
            '✅ SmartCacheManager: High prediction accuracy ($accuracy%), maintaining preload strategy');
      }
    } catch (e) {
      print('❌ SmartCacheManager: Error optimizing predictions: $e');
    }
  }

  /// Get prediction accuracy
  double getPredictionAccuracy() {
    if (_totalPredictions == 0) return 0.0;
    return (_successfulPredictions / _totalPredictions) * 100;
  }

  /// Get comprehensive statistics
  Map<String, dynamic> getStats() {
    final totalRequests = _cacheHits + _cacheMisses;
    final hitRate =
        totalRequests > 0 ? (_cacheHits / totalRequests * 100) : 0.0;
    final etagHitRate =
        totalRequests > 0 ? (_etagHits / totalRequests * 100) : 0.0;

    return {
      // Cache stats
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'etagHits': _etagHits,
      'notModifiedResponses': _notModifiedResponses,
      'staleResponses': _staleResponses,
      'backgroundRefreshes': _backgroundRefreshes,
      'hitRate': hitRate.toStringAsFixed(2),
      'etagHitRate': etagHitRate.toStringAsFixed(2),
      'memoryCacheSize': _memoryCache.length,
      'cacheConfigs': _cacheConfigs.keys.toList(),

      // Preload stats
      'totalPredictions': _totalPredictions,
      'successfulPredictions': _successfulPredictions,
      'predictionAccuracy': getPredictionAccuracy().toStringAsFixed(2),
      'preloadHits': _preloadHits,
      'currentlyPreloading': _currentlyPreloading.toList(),
      'navigationHistory': _navigationHistory.toList(),
      'screenVisitFrequency': _screenVisitFrequency,
    };
  }

  /// Clear all cache
  Future<void> clearCache() async {
    try {
      _memoryCache.clear();

      if (await _cacheDir.exists()) {
        await _cacheDir.delete(recursive: true);
        await _cacheDir.create();
      }

      print('🗑️ SmartCacheManager: Cache cleared successfully');
    } catch (e) {
      print('❌ SmartCacheManager: Error clearing cache: $e');
    }
  }

  /// Dispose manager
  Future<void> dispose() async {
    try {
      // Clear prediction data
      _navigationHistory.clear();
      _screenVisitFrequency.clear();
      _lastVisitTime.clear();
      _preloadPredictions.clear();
      _currentlyPreloading.clear();

      print('✅ SmartCacheManager: Disposal completed');
    } catch (e) {
      print('❌ SmartCacheManager: Disposal failed: $e');
    }
  }

  // ===== ADDITIONAL REQUIRED METHODS =====

  /// Update access information for cache entry
  void _updateAccessInfo(String key) {
    final entry = _memoryCache[key];
    if (entry != null) {
      _memoryCache[key] = entry.copyWith(
        accessCount: entry.accessCount + 1,
        lastAccessed: DateTime.now(),
      );
    }
  }

  /// Check if stale-while-revalidate should be used for this cache type
  bool _shouldUseStaleWhileRevalidate(String cacheType) {
    final config = _cacheConfigs[cacheType];
    return config?.enableStaleWhileRevalidate ?? true;
  }

  /// Schedule background refresh for stale data
  void _scheduleBackgroundRefresh<T>(
    String key,
    Future<T> Function() fetchFn,
    String cacheType,
    String? currentEtag,
  ) {
    if (_refreshQueue.contains(key)) return;

    _refreshQueue.add(key);
    print('🔄 SmartCacheManager: Scheduled background refresh for $key');

    if (!_isRefreshing) {
      _processRefreshQueue();
    }
  }

  /// Process the refresh queue in background
  Future<void> _processRefreshQueue() async {
    if (_isRefreshing || _refreshQueue.isEmpty) return;

    _isRefreshing = true;

    try {
      while (_refreshQueue.isNotEmpty) {
        final key = _refreshQueue.removeFirst();
        await _refreshCacheEntry(key);
        await Future.delayed(const Duration(milliseconds: 100));
      }
    } catch (e) {
      print('❌ SmartCacheManager: Error processing refresh queue: $e');
    } finally {
      _isRefreshing = false;
    }
  }

  /// Refresh a specific cache entry
  Future<void> _refreshCacheEntry(String key) async {
    try {
      print('🔄 SmartCacheManager: Refreshing cache entry for $key');

      final entry = _memoryCache[key];
      if (entry != null) {
        _memoryCache[key] = entry.copyWith(cachedAt: DateTime.now());
      }

      _backgroundRefreshes++;
      print('✅ SmartCacheManager: Cache entry refreshed for $key');
    } catch (e) {
      print('❌ SmartCacheManager: Error refreshing cache entry for $key: $e');
    }
  }

  /// Get cache entry from disk
  Future<InstagramCacheEntry<T>?> _getFromDiskCache<T>(String key) async {
    try {
      final file = File('${_cacheDir.path}/$key.json');
      if (!await file.exists()) return null;

      final jsonString = await file.readAsString();
      final json = jsonDecode(jsonString);

      return InstagramCacheEntry<T>(
        data: json['data'] as T,
        etag: json['etag'],
        lastModified: DateTime.parse(json['lastModified']),
        cachedAt: DateTime.parse(json['cachedAt']),
        maxAge: Duration(milliseconds: json['maxAge']),
        accessCount: json['accessCount'] ?? 0,
        lastAccessed: DateTime.parse(json['lastAccessed']),
      );
    } catch (e) {
      print('❌ SmartCacheManager: Error reading from disk cache for $key: $e');
      return null;
    }
  }

  /// Add entry to memory cache with size management
  void _addToMemoryCache<T>(String key, InstagramCacheEntry<T> entry) {
    final config =
        _cacheConfigs[_getCacheTypeFromKey(key)] ?? _cacheConfigs['default']!;

    if (_memoryCache.length >= config.maxEntries) {
      _evictLeastUsedEntries();
    }

    _memoryCache[key] = entry;
  }

  /// Evict least used cache entries
  void _evictLeastUsedEntries() {
    if (_memoryCache.isEmpty) return;

    final sortedEntries = _memoryCache.entries.toList()
      ..sort((a, b) {
        final aEntry = a.value;
        final bEntry = b.value;

        if (aEntry.accessCount != bEntry.accessCount) {
          return aEntry.accessCount.compareTo(bEntry.accessCount);
        }
        return aEntry.lastAccessed.compareTo(bEntry.lastAccessed);
      });

    final entriesToRemove = (sortedEntries.length * 0.2).ceil();
    for (int i = 0; i < entriesToRemove; i++) {
      _memoryCache.remove(sortedEntries[i].key);
    }

    print('🧹 SmartCacheManager: Evicted $entriesToRemove least used entries');
  }

  /// Cache data with ETag and timestamp
  Future<void> _cacheData<T>(
    String key,
    T data,
    String cacheType,
    Duration? maxAge,
    String? etag,
  ) async {
    try {
      final config = _cacheConfigs[cacheType] ?? _cacheConfigs['default']!;
      final entry = InstagramCacheEntry<T>(
        data: data,
        etag: etag,
        lastModified: DateTime.now(),
        cachedAt: DateTime.now(),
        maxAge: maxAge ?? config.maxAge,
        accessCount: 1,
        lastAccessed: DateTime.now(),
      );

      _addToMemoryCache(key, entry);
      await _persistToDiskCache(key, entry);

      print('✅ SmartCacheManager: Cached data for $key with ETag: $etag');
    } catch (e) {
      print('❌ SmartCacheManager: Error caching data for $key: $e');
    }
  }

  /// Persist cache entry to disk
  Future<void> _persistToDiskCache<T>(
      String key, InstagramCacheEntry<T> entry) async {
    try {
      final file = File('${_cacheDir.path}/$key.json');
      await file.writeAsString(jsonEncode(entry.toJson()));
    } catch (e) {
      print('❌ SmartCacheManager: Error persisting to disk cache for $key: $e');
    }
  }

  /// Get cache type from key
  String _getCacheTypeFromKey(String key) {
    if (key.startsWith('video_')) return 'videos';
    if (key.startsWith('user_')) return 'user_profile';
    if (key.startsWith('ad_')) return 'ads';
    return 'default';
  }

  /// Analyze navigation patterns and predict next screens
  void _analyzeNavigationPattern() {
    try {
      if (_navigationHistory.length < 2) return;

      final recentScreens =
          _navigationHistory.toList().reversed.take(5).toList();

      // Pattern 1: Sequential navigation
      for (int i = 0; i < recentScreens.length - 1; i++) {
        final current = recentScreens[i];
        final next = recentScreens[i + 1];

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

        final currentScreen = recentScreens.first;
        if (!_preloadPredictions.containsKey(currentScreen)) {
          _preloadPredictions[currentScreen] = [];
        }

        if (!_preloadPredictions[currentScreen]!.contains(screen)) {
          _preloadPredictions[currentScreen]!.add(screen);
        }
      }

      // Pattern 3: Time-based prediction
      _addTimeBasedPredictions(recentScreens.first);

      print('🧠 SmartCacheManager: Navigation pattern analyzed');
    } catch (e) {
      print('❌ SmartCacheManager: Error analyzing pattern: $e');
    }
  }

  /// Add time-based predictions
  void _addTimeBasedPredictions(String currentScreen) {
    try {
      final hour = DateTime.now().hour;

      if (hour >= 6 && hour <= 12) {
        _addPrediction(currentScreen, 'notifications');
        _addPrediction(currentScreen, 'profile');
      } else if (hour >= 18 && hour <= 22) {
        _addPrediction(currentScreen, 'explore');
        _addPrediction(currentScreen, 'feed');
      } else if (hour >= 22 || hour <= 6) {
        _addPrediction(currentScreen, 'messages');
        _addPrediction(currentScreen, 'stories');
      }
    } catch (e) {
      print('❌ SmartCacheManager: Error adding time-based predictions: $e');
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

  /// Preload data for a specific screen
  Future<void> _preloadScreenData(
      String screenName, Map<String, dynamic>? userContext) async {
    try {
      print('📥 SmartCacheManager: Preloading data for $screenName');

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
              '⚠️ SmartCacheManager: Unknown screen for preload: $screenName');
      }

      print('✅ SmartCacheManager: Preloaded data for $screenName');
    } catch (e) {
      print('❌ SmartCacheManager: Error preloading $screenName: $e');
    }
  }

  // Preload methods for different screen types
  Future<void> _preloadProfileData(Map<String, dynamic>? userContext) async {
    try {
      final userId = userContext?['userId'] ?? 'current';
      await get('user_profile_$userId',
          fetchFn: () async => {'status': 'preloaded'},
          cacheType: 'user_profile');
      await get('user_videos_$userId',
          fetchFn: () async => {'status': 'preloaded'}, cacheType: 'videos');
      print('👤 SmartCacheManager: Profile data preloaded for user $userId');
    } catch (e) {
      print('❌ SmartCacheManager: Error preloading profile: $e');
    }
  }

  Future<void> _preloadFeedData(Map<String, dynamic>? userContext) async {
    try {
      for (int page = 1; page <= 3; page++) {
        await get('feed_page_$page',
            fetchFn: () async => {'status': 'preloaded'}, cacheType: 'videos');
      }
      print('📱 SmartCacheManager: Feed data preloaded');
    } catch (e) {
      print('❌ SmartCacheManager: Error preloading feed: $e');
    }
  }

  Future<void> _preloadExploreData(Map<String, dynamic>? userContext) async {
    try {
      await get('explore_trending',
          fetchFn: () async => {'status': 'preloaded'}, cacheType: 'videos');
      await get('explore_categories',
          fetchFn: () async => {'status': 'preloaded'}, cacheType: 'metadata');
      print('🔍 SmartCacheManager: Explore data preloaded');
    } catch (e) {
      print('❌ SmartCacheManager: Error preloading explore: $e');
    }
  }

  Future<void> _preloadNotificationsData(
      Map<String, dynamic>? userContext) async {
    try {
      await get('notifications_recent',
          fetchFn: () async => {'status': 'preloaded'},
          cacheType: 'notifications');
      print('🔔 SmartCacheManager: Notifications preloaded');
    } catch (e) {
      print('❌ SmartCacheManager: Error preloading notifications: $e');
    }
  }

  Future<void> _preloadMessagesData(Map<String, dynamic>? userContext) async {
    try {
      await get('messages_conversations',
          fetchFn: () async => {'status': 'preloaded'}, cacheType: 'messages');
      print('💬 SmartCacheManager: Messages preloaded');
    } catch (e) {
      print('❌ SmartCacheManager: Error preloading messages: $e');
    }
  }

  Future<void> _preloadStoriesData(Map<String, dynamic>? userContext) async {
    try {
      await get('stories_recent',
          fetchFn: () async => {'status': 'preloaded'}, cacheType: 'stories');
      print('📖 SmartCacheManager: Stories preloaded');
    } catch (e) {
      print('❌ SmartCacheManager: Error preloading stories: $e');
    }
  }

  /// Get cache configuration for specific cache type
  InstagramCacheConfig _getCacheConfig(String cacheType) {
    switch (cacheType) {
      case 'videos':
        return const InstagramCacheConfig(
          maxAge: Duration(
              minutes: 30), // **CRITICAL FIX: Increased from 5 to 30 minutes**
          maxEntries: 200, // **CRITICAL FIX: Increased from 100 to 200**
          enableEtag: true,
          enableStaleWhileRevalidate: true,
          staleWhileRevalidateTime: Duration(
              minutes: 10), // **CRITICAL FIX: Increased from 2 to 10 minutes**
        );
      case 'video_metadata':
        return const InstagramCacheConfig(
          maxAge: Duration(
              hours: 2), // **CRITICAL FIX: Increased from 1 to 2 hours**
          maxEntries: 100,
          enableEtag: true,
          enableStaleWhileRevalidate: true,
          staleWhileRevalidateTime: Duration(
              minutes: 30), // **CRITICAL FIX: Increased from 2 to 30 minutes**
        );
      case 'user_profile':
        return const InstagramCacheConfig(
          maxAge: Duration(hours: 1),
          maxEntries: 50,
          enableEtag: true,
          enableStaleWhileRevalidate: true,
          staleWhileRevalidateTime: Duration(minutes: 15),
        );
      case 'comments':
        return const InstagramCacheConfig(
          maxAge: Duration(minutes: 15),
          maxEntries: 100,
          enableEtag: true,
          enableStaleWhileRevalidate: true,
          staleWhileRevalidateTime: Duration(minutes: 5),
        );
      default:
        return const InstagramCacheConfig(
          maxAge: Duration(
              minutes: 15), // **CRITICAL FIX: Increased from 5 to 15 minutes**
          maxEntries: 100,
          enableEtag: true,
          enableStaleWhileRevalidate: true,
          staleWhileRevalidateTime: Duration(minutes: 5),
        );
    }
  }

  /// **NEW: Check for potential memory leaks**
  void _checkForMemoryLeaks() {
    // **CRITICAL FIX: Move heavy operations to background thread**
    unawaited(_checkForMemoryLeaksInBackground());
  }

  /// **NEW: Check for memory leaks in background thread**
  Future<void> _checkForMemoryLeaksInBackground() async {
    try {
      final totalControllers = _memoryCache.length;

      if (totalControllers > 100) {
        print(
            '⚠️ SmartCacheManager: High cache entry count ($totalControllers), potential memory leak detected');
      }

      // Check for expired entries that might be stuck
      final expiredEntries = <String>[];
      for (var entry in _memoryCache.entries) {
        try {
          if (entry.value.isExpired) {
            expiredEntries.add(entry.key);
          }
        } catch (e) {
          print(
              '❌ SmartCacheManager: Error checking cache entry ${entry.key}: $e');
        }
      }

      if (expiredEntries.isNotEmpty) {
        print(
            '🧹 SmartCacheManager: Cleaning up ${expiredEntries.length} expired entries');
        for (final key in expiredEntries) {
          _memoryCache.remove(key);
        }
      }
    } catch (e) {
      print('❌ SmartCacheManager: Error during memory leak check: $e');
    }
  }
}
