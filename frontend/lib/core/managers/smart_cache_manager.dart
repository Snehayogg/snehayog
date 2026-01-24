import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path_provider/path_provider.dart';
import 'package:vayu/utils/feature_flags.dart';
import 'package:vayu/utils/app_logger.dart';

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
}

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
/// - YogCacheManager (data caching, ETags, memory management)
/// **OPTIMIZED: Memory-only operation (uses Hive for long-term storage)**
class SmartCacheManager {
  static final SmartCacheManager _instance = SmartCacheManager._internal();
  factory SmartCacheManager() => _instance;
  SmartCacheManager._internal();

  // ===== CACHE STORAGE =====

  // Memory cache for instant access
  final Map<String, InstagramCacheEntry> _memoryCache = {};

  // Initialization state
  bool _isInitialized = false;

  /// Check if cache manager is initialized
  bool get isInitialized => _isInitialized;

  // Cache configurations for different data types
  final Map<String, InstagramCacheConfig> _cacheConfigs = {
    'default': const InstagramCacheConfig(
      maxAge: Duration(minutes: 10),
      maxEntries: 50,
      enableEtag: true,
      enableStaleWhileRevalidate: true,
    ),
    'videos': const InstagramCacheConfig(
      maxAge: Duration(minutes: 60),
      maxEntries: 150,
      enableEtag: true,
      enableStaleWhileRevalidate: true,
    ),
    'user_profile': const InstagramCacheConfig(
      maxAge: Duration(hours: 24),
      maxEntries: 40,
      enableEtag: true,
      enableStaleWhileRevalidate: true,
    ),
    'video_metadata': const InstagramCacheConfig(
      maxAge: Duration(hours: 2),
      maxEntries: 200,
      enableEtag: true,
      enableStaleWhileRevalidate: true,
    ),
    'ads': const InstagramCacheConfig(
      maxAge: Duration(minutes: 30),
      maxEntries: 60,
      enableEtag: true,
      enableStaleWhileRevalidate: true,
    ),
  };

  // Background refresh queue for stale-while-revalidate
  final Queue<_RefreshTask> _refreshQueue = Queue<_RefreshTask>();
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

  static const int maxHistorySize = 20;
  static const int maxPreloadItems = 5;
  static const Duration predictionWindow = Duration(minutes: 5);

  // **NEW: Cache size limits**
  static const int maxMemoryCacheSize = 50; // Limit memory cache entries

  /// Initialize consolidated smart cache manager
  Future<void> initialize() async {
    if (!Features.smartVideoCaching.isEnabled) {
      AppLogger.log('🚫 SmartCacheManager: Smart caching disabled');
      return;
    }

    try {
      AppLogger.log(
        '🚀 SmartCacheManager: Initializing consolidated cache (MEMORY ONLY)...',
      );

      // **CLEANUP: Clean up old disk cache if it exists**
      if (!kIsWeb) {
        _cleanupOldDiskCache();
      }

      // Start background workers
      _startBackgroundWorkers();

      _isInitialized = true;
      AppLogger.log(
          '✅ SmartCacheManager: Initialization completed successfully (Memory Only)');
    } catch (e) {
      AppLogger.log('❌ SmartCacheManager: Initialization failed: $e');
      _isInitialized = false;
    }
  }

  /// **NEW: Cleanup old disk cache directory**
  Future<void> _cleanupOldDiskCache() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${appDir.path}/smart_cache');
      if (await cacheDir.exists()) {
        AppLogger.log(
            '🧹 SmartCacheManager: Found old disk cache, deleting to save space...');
        await cacheDir.delete(recursive: true);
        AppLogger.log('✅ SmartCacheManager: Old disk cache deleted');
      }
    } catch (e) {
      AppLogger.log(
          '⚠️ SmartCacheManager: Error cleaning up old disk cache: $e');
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
    try {
      // Check memory cache first (instant response)
      final memoryEntry = _memoryCache[key];
      if (memoryEntry != null && !forceRefresh) {
        final entry = memoryEntry as InstagramCacheEntry<T>;

        if (!entry.isExpired) {
          _updateAccessInfo(key);
          _cacheHits++;
          AppLogger.log('⚡ SmartCacheManager: Instant cache hit for $key');
          AppLogger.log(
            '📊 Cache Stats - Hits: $_cacheHits, Misses: $_cacheMisses, Stale: $_staleResponses',
          );

          // Start background refresh if stale
          if (entry.shouldRefresh &&
              _shouldUseStaleWhileRevalidate(cacheType)) {
            _scheduleBackgroundRefresh(key, fetchFn, cacheType, currentEtag);
          }

          return entry.data;
        } else if (entry.shouldRefresh &&
            _shouldUseStaleWhileRevalidate(cacheType)) {
          _staleResponses++;
          AppLogger.log(
            '🔄 SmartCacheManager: Stale cache hit for $key, refreshing in background',
          );
          _scheduleBackgroundRefresh(key, fetchFn, cacheType, currentEtag);
          return entry.data;
        }
      }

      // Cache miss - fetch fresh data
      _cacheMisses++;
      AppLogger.log(
          '❌ SmartCacheManager: Cache miss for $key, fetching fresh data');
      AppLogger.log(
        '📊 Cache Stats - Hits: $_cacheHits, Misses: $_cacheMisses, Stale: $_staleResponses',
      );

      final freshData = await fetchFn();

      // **FIX: Don't cache empty video lists (prevents stale empty cache)**
      if (freshData != null) {
        // Check if this is a video list that's empty
        if (cacheType == 'videos' && freshData is Map) {
          final videos = freshData['videos'];
          if (videos is List && videos.isEmpty) {
            AppLogger.log(
              '⚠️ SmartCacheManager: Empty video list received, NOT caching to prevent stale empty data',
            );
            // Invalidate any existing cache for this key
            _memoryCache.remove(key);
            return freshData; // Return but don't cache
          }
        }

        await _cacheData(key, freshData, cacheType, maxAge, currentEtag);
      }

      return freshData;
    } catch (e) {
      AppLogger.log('❌ SmartCacheManager: Error in get operation for $key: $e');

      // On error, try to return stale cache if available
      final staleEntry = _memoryCache[key];
      if (staleEntry != null && !staleEntry.isExpired) {
        AppLogger.log(
            '🔄 SmartCacheManager: Returning stale cache on error for $key');
        return staleEntry.data as T;
      }

      rethrow;
    }
  }

  /// Peek cache without affecting hit/miss counters or triggering fetches.
  Future<T?> peek<T>(
    String key, {
    String cacheType = 'default',
    bool allowStale = true,
  }) async {
    if (!Features.smartVideoCaching.isEnabled) {
      return null;
    }

    final memoryEntry = _memoryCache[key];
    if (memoryEntry != null) {
      final entry = memoryEntry as InstagramCacheEntry<T>;
      final isFresh = !entry.isExpired;
      if (isFresh) {
        return entry.data;
      }
      if (allowStale && _shouldUseStaleWhileRevalidate(cacheType)) {
        return entry.data;
      }
    }

    return null;
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

      AppLogger.log('📱 SmartCacheManager: Tracked navigation to $screenName');
    } catch (e) {
      AppLogger.log('❌ SmartCacheManager: Error tracking navigation: $e');
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
        AppLogger.log(
            '📱 SmartCacheManager: No predictions for $currentScreen');
        return;
      }

      AppLogger.log(
          '🚀 SmartCacheManager: Starting smart preload for $currentScreen');
      AppLogger.log('🎯 Predictions: ${predictions.join(', ')}');

      // Preload data for predicted screens
      for (final predictedScreen in predictions.take(maxPreloadItems)) {
        if (_currentlyPreloading.contains(predictedScreen)) continue;

        _currentlyPreloading.add(predictedScreen);

        unawaited(
          _preloadScreenData(predictedScreen, userContext).then((_) {
            _currentlyPreloading.remove(predictedScreen);
          }),
        );
      }
    } catch (e) {
      AppLogger.log('❌ SmartCacheManager: Error in smart preload: $e');
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
    AppLogger.log('🎯 SmartCacheManager: Prediction hit for $predictedScreen!');
  }

  /// Record prediction miss
  void recordPredictionMiss(String predictedScreen) {
    _totalPredictions++;
    AppLogger.log('❌ SmartCacheManager: Prediction miss for $predictedScreen');
  }

  // ===== INTERNAL METHODS =====

  /// Clean up expired cache entries
  void _cleanupExpiredEntries() {
    try {
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
        AppLogger.log(
          '🧹 SmartCacheManager: Cleaned up ${keysToRemove.length} expired entries',
        );
      }
    } catch (e) {
      AppLogger.log(
          '❌ SmartCacheManager: Error cleaning up expired entries: $e');
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
        AppLogger.log(
          '🧹 SmartCacheManager: Cleaned up ${keysToRemove.length} old prediction entries',
        );
      }
    } catch (e) {
      AppLogger.log(
          '❌ SmartCacheManager: Error cleaning up old prediction data: $e');
    }
  }

  /// Optimize predictions based on accuracy
  void _optimizePredictions() {
    try {
      final accuracy = getPredictionAccuracy();

      if (accuracy < 30.0) {
        AppLogger.log(
          '⚠️ SmartCacheManager: Low prediction accuracy ($accuracy%), reducing preload items',
        );
      } else if (accuracy > 70.0) {
        AppLogger.log(
          '✅ SmartCacheManager: High prediction accuracy ($accuracy%), maintaining preload strategy',
        );
      }
    } catch (e) {
      AppLogger.log('❌ SmartCacheManager: Error optimizing predictions: $e');
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
      AppLogger.log('🗑️ SmartCacheManager: Cache cleared successfully');
    } catch (e) {
      AppLogger.log('❌ SmartCacheManager: Error clearing cache: $e');
    }
  }

  /// **NEW: Clear cache entries matching a specific pattern (e.g., 'videos_page_*')**
  Future<void> clearCacheByPattern(String pattern) async {
    try {
      final keysToRemove = <String>[];

      // Find all keys matching the pattern
      for (final key in _memoryCache.keys) {
        if (key.contains(pattern)) {
          keysToRemove.add(key);
        }
      }

      // Remove from memory cache
      for (final key in keysToRemove) {
        _memoryCache.remove(key);
      }

      if (keysToRemove.isNotEmpty) {
        AppLogger.log(
          '🗑️ SmartCacheManager: Cleared ${keysToRemove.length} cache entries matching pattern "$pattern"',
        );
      }
    } catch (e) {
      AppLogger.log(
        '❌ SmartCacheManager: Error clearing cache by pattern "$pattern": $e',
      );
    }
  }

  /// **NEW: Invalidate video cache for a specific video type (used when videos are deleted)**
  /// **UPDATED: Now handles cache keys with platformId: videos_page_${page}_${type}_${platformId}**
  Future<void> invalidateVideoCache({String? videoType}) async {
    try {
      AppLogger.log(
        '🗑️ SmartCacheManager: Invalidating video cache${videoType != null ? ' for type: $videoType' : ''}',
      );

      if (videoType != null) {
        // **FIX: Pattern matches new cache key format with platformId**
        // New format: videos_page_${page}_${type}_${platformId}
        // Match by type substring: _${videoType}_
        final normalizedType = videoType.toLowerCase();
        await clearCacheByPattern('_${normalizedType}_');
      } else {
        // Invalidate all video caches (matches all keys starting with videos_page_)
        await clearCacheByPattern('videos_page_');
      }

      AppLogger.log(
          '✅ SmartCacheManager: Video cache invalidated successfully');
    } catch (e) {
      AppLogger.log('❌ SmartCacheManager: Error invalidating video cache: $e');
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

      AppLogger.log('✅ SmartCacheManager: Disposal completed');
    } catch (e) {
      AppLogger.log('❌ SmartCacheManager: Disposal failed: $e');
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
    // Check if a refresh for this key is already in the queue
    for (final task in _refreshQueue) {
      if (task.key == key) return;
    }

    _refreshQueue.add(_RefreshTask(
      key: key,
      fetchFn: fetchFn,
      cacheType: cacheType,
      etag: currentEtag,
    ));
    AppLogger.log(
        '🔄 SmartCacheManager: Scheduled background refresh for $key');

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
        final task = _refreshQueue.removeFirst();
        await _refreshCacheEntry(task);
        // Small delay between refreshes to avoid hammering
        await Future.delayed(const Duration(milliseconds: 200));
      }
    } catch (e) {
      AppLogger.log('❌ SmartCacheManager: Error processing refresh queue: $e');
    } finally {
      _isRefreshing = false;
    }
  }

  /// Refresh a specific cache entry by fetching fresh data
  Future<void> _refreshCacheEntry(_RefreshTask task) async {
    try {
      AppLogger.log('🔄 SmartCacheManager: Background refreshing cache entry for ${task.key}');

      // Fetch fresh data using the stored fetch function
      final freshData = await task.fetchFn();

      if (freshData != null) {
        // Check if this is a video list that's empty
        if (task.cacheType == 'videos' && freshData is Map) {
          final videos = freshData['videos'];
          if (videos is List && videos.isEmpty) {
             AppLogger.log('⚠️ SmartCacheManager: Background refresh returned empty videos, skipping update');
             return;
          }
        }

        // Update the cache with fresh data
        await _cacheData(
          task.key,
          freshData,
          task.cacheType,
          null, // Use default maxAge
          task.etag,
        );
        
        _backgroundRefreshes++;
        AppLogger.log('✅ SmartCacheManager: Cache entry background refreshed for ${task.key}');
      }
    } catch (e) {
      AppLogger.log(
          '❌ SmartCacheManager: Error background refreshing cache entry for ${task.key}: $e');
    }
  }

  /// Add entry to memory cache with size management
  void _addToMemoryCache<T>(String key, InstagramCacheEntry<T> entry) {
    // **FIX: Enforce strict memory cache size limit**
    if (_memoryCache.length >= maxMemoryCacheSize) {
      _evictLeastUsedEntries();
    }

    _memoryCache[key] = entry;
  }

  /// Evict least used cache entries (more aggressive - 30% instead of 20%)
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

    // **FIX: Evict 30% instead of 20% for more aggressive cleanup**
    final entriesToRemove = (sortedEntries.length * 0.3).ceil();
    for (int i = 0; i < entriesToRemove; i++) {
        _memoryCache.remove(sortedEntries[i].key);
    }

    AppLogger.log(
        '🧹 SmartCacheManager: Evicted $entriesToRemove least used entries (30% aggressive eviction)');
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
      // **REMOVED: Disk persistence**
      // await _persistToDiskCache(key, entry);

      AppLogger.log(
          '✅ SmartCacheManager: Cached data for $key (Memory Only)');
    } catch (e) {
      AppLogger.log('❌ SmartCacheManager: Error caching data for $key: $e');
    }
  }

  // ===== REMOVED DISK METHODS but kept place method bodies required by other parts of the system if any? No. =====
  
  // Navigation analysis placeholder
  void _analyzeNavigationPattern() {
    // Simple placeholder for prediction logic
    // In a real implementation, this would analyze `_navigationHistory`
  }
  
  // Preload screen data placeholder
  Future<void> _preloadScreenData(String screenName, Map<String, dynamic>? userContext) async {
    // Placeholder for actual data preloading logic
    // This would fetch data relevant to the screen and cache it
  }
}

/// **INTERNAL: Task for background cache refresh**
class _RefreshTask {
  final String key;
  final Future<dynamic> Function() fetchFn;
  final String cacheType;
  final String? etag;

  _RefreshTask({
    required this.key,
    required this.fetchFn,
    required this.cacheType,
    this.etag,
  });
}
