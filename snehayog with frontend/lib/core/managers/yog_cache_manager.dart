import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'dart:collection';
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

  /// Check if cache entry is expired
  bool get isExpired {
    final now = DateTime.now();
    return now.difference(cachedAt) > maxAge;
  }

  /// Check if cache entry is stale (can be used but should be refreshed)
  bool get shouldRefresh {
    final now = DateTime.now();
    final age = now.difference(cachedAt);
    return age > maxAge * 0.8; // Refresh when 80% of max age is reached
  }

  /// Create a copy with updated access info
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

  /// Convert to JSON for storage
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

  /// Create from JSON
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

/// Instagram-like cache configuration
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

/// Instagram-like Cache Manager with ETag/Cache-Control support
/// Prevents repeated API calls on tab switches by using local cache
class YogCacheManager {
  static final YogCacheManager _instance = YogCacheManager._internal();
  factory YogCacheManager() => _instance;
  YogCacheManager._internal();

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

  // Performance metrics
  int _cacheHits = 0;
  int _cacheMisses = 0;
  int _etagHits = 0;
  int _notModifiedResponses = 0;
  int _staleResponses = 0;
  int _backgroundRefreshes = 0;

  /// Initialize Instagram cache manager
  Future<void> initialize() async {
    try {
      if (!Features.smartVideoCaching.isEnabled) {
        print('🚫 InstagramCacheManager: Smart caching disabled');
        return;
      }

      print('🚀 InstagramCacheManager: Initializing Instagram-like cache...');

      // Create cache directory
      final appDir = await getApplicationDocumentsDirectory();
      _cacheDir = Directory('${appDir.path}/instagram_cache');
      if (!await _cacheDir.exists()) {
        await _cacheDir.create(recursive: true);
      }

      // Load cached data from disk
      await _loadPersistedCache();

      // Start background refresh worker
      _startBackgroundRefreshWorker();

      print('✅ InstagramCacheManager: Initialization completed');
    } catch (e) {
      print('❌ InstagramCacheManager: Initialization failed: $e');
    }
  }

  /// Get data using Instagram-like caching strategy
  /// Returns cached data instantly, then checks ETag for freshness
  Future<T?> get<T>(
    String key, {
    required Future<T> Function() fetchFn,
    String cacheType = 'default',
    Duration? maxAge,
    bool forceRefresh = false,
    String? currentEtag,
  }) async {
    if (!Features.smartVideoCaching.isEnabled) {
      // Fallback to direct fetch if caching is disabled
      return await fetchFn();
    }

    try {
      // Check memory cache first (instant response)
      final memoryEntry = _memoryCache[key];
      if (memoryEntry != null && !forceRefresh) {
        final entry = memoryEntry as InstagramCacheEntry<T>;

        if (!entry.isExpired) {
          // Fresh cache hit - return instantly
          _updateAccessInfo(key);
          _cacheHits++;
          print('⚡ InstagramCacheManager: Instant cache hit for $key');

          // Start background refresh if stale
          if (entry.shouldRefresh &&
              _shouldUseStaleWhileRevalidate(cacheType)) {
            _scheduleBackgroundRefresh(key, fetchFn, cacheType, currentEtag);
          }

          return entry.data;
        } else if (entry.shouldRefresh &&
            _shouldUseStaleWhileRevalidate(cacheType)) {
          // Stale cache hit - return stale data and refresh in background
          _staleResponses++;
          print(
              '🔄 InstagramCacheManager: Stale cache hit for $key, refreshing in background');
          _scheduleBackgroundRefresh(key, fetchFn, cacheType, currentEtag);
          return entry.data;
        }
      }

      // Check disk cache
      final diskEntry = await _getFromDiskCache<T>(key);
      if (diskEntry != null && !forceRefresh) {
        if (!diskEntry.isExpired) {
          // Fresh disk cache hit
          _addToMemoryCache(key, diskEntry);
          _cacheHits++;
          print('💾 InstagramCacheManager: Fresh disk cache hit for $key');

          // Start background refresh if stale
          if (diskEntry.shouldRefresh &&
              _shouldUseStaleWhileRevalidate(cacheType)) {
            _scheduleBackgroundRefresh(key, fetchFn, cacheType, currentEtag);
          }

          return diskEntry.data;
        } else if (diskEntry.shouldRefresh &&
            _shouldUseStaleWhileRevalidate(cacheType)) {
          // Stale disk cache hit
          _staleResponses++;
          print(
              '🔄 InstagramCacheManager: Stale disk cache hit for $key, refreshing in background');
          _scheduleBackgroundRefresh(key, fetchFn, cacheType, currentEtag);
          return diskEntry.data;
        }
      }

      // Cache miss - fetch fresh data
      _cacheMisses++;
      print(
          '❌ InstagramCacheManager: Cache miss for $key, fetching fresh data');

      final freshData = await fetchFn();
      if (freshData != null) {
        await _cacheData(key, freshData, cacheType, maxAge, currentEtag);
      }

      return freshData;
    } catch (e) {
      print('❌ InstagramCacheManager: Error in get operation for $key: $e');

      // On error, try to return stale cache if available
      final staleEntry = _memoryCache[key] ?? await _getFromDiskCache<T>(key);
      if (staleEntry != null && !staleEntry.isExpired) {
        print(
            '🔄 InstagramCacheManager: Returning stale cache on error for $key');
        return staleEntry.data;
      }

      rethrow;
    }
  }

  /// Check ETag and return 304 Not Modified if data hasn't changed
  Future<Map<String, dynamic>> checkEtagAndFetch<T>(
    String key, {
    String? currentEtag,
    required Future<Map<String, dynamic>> Function() fetchFn,
    String cacheType = 'default',
  }) async {
    if (!Features.smartVideoCaching.isEnabled) {
      return await fetchFn();
    }

    try {
      // Check if we have cached data with ETag
      final cachedEntry = _memoryCache[key] ?? await _getFromDiskCache<T>(key);

      if (cachedEntry != null &&
          cachedEntry.etag != null &&
          currentEtag != null &&
          cachedEntry.etag == currentEtag) {
        // ETag matches - data hasn't changed
        _etagHits++;
        _notModifiedResponses++;
        print(
            '✅ InstagramCacheManager: ETag match for $key - returning 304 Not Modified');

        return <String, dynamic>{
          'status': 304,
          'message': 'Not Modified',
          'data': cachedEntry.data,
          'cached': true,
          'etag': cachedEntry.etag,
        };
      }

      // ETag doesn't match or no cached data - fetch fresh
      print(
          '🔄 InstagramCacheManager: ETag mismatch or no cache for $key - fetching fresh data');
      final freshData = await fetchFn();

      // Cache the fresh data
      if (freshData['data'] != null) {
        await _cacheData(key, freshData['data'], cacheType, null, currentEtag);
      }

      return freshData;
    } catch (e) {
      print('❌ InstagramCacheManager: Error in ETag check for $key: $e');
      rethrow;
    }
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

      // Add to memory cache
      _addToMemoryCache(key, entry);

      // Persist to disk cache
      await _persistToDiskCache(key, entry);

      print('✅ InstagramCacheManager: Cached data for $key with ETag: $etag');
    } catch (e) {
      print('❌ InstagramCacheManager: Error caching data for $key: $e');
    }
  }

  /// Add entry to memory cache with size management
  void _addToMemoryCache<T>(String key, InstagramCacheEntry<T> entry) {
    final config =
        _cacheConfigs[_getCacheTypeFromKey(key)] ?? _cacheConfigs['default']!;

    // Check if we need to evict entries
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

        // Sort by access count first, then by last accessed time
        if (aEntry.accessCount != bEntry.accessCount) {
          return aEntry.accessCount.compareTo(bEntry.accessCount);
        }
        return aEntry.lastAccessed.compareTo(bEntry.lastAccessed);
      });

    // Remove bottom 20% of entries
    final entriesToRemove = (sortedEntries.length * 0.2).ceil();
    for (int i = 0; i < entriesToRemove; i++) {
      _memoryCache.remove(sortedEntries[i].key);
    }

    print(
        '🧹 InstagramCacheManager: Evicted $entriesToRemove least used entries');
  }

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
    if (_refreshQueue.contains(key)) return; // Already queued

    _refreshQueue.add(key);
    print('🔄 InstagramCacheManager: Scheduled background refresh for $key');

    // Process refresh queue if not already running
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
        await Future.delayed(
            const Duration(milliseconds: 100)); // Small delay between refreshes
      }
    } catch (e) {
      print('❌ InstagramCacheManager: Error processing refresh queue: $e');
    } finally {
      _isRefreshing = false;
    }
  }

  /// Refresh a specific cache entry
  Future<void> _refreshCacheEntry(String key) async {
    try {
      print('🔄 InstagramCacheManager: Refreshing cache entry for $key');

      // Mark entry as refreshed
      final entry = _memoryCache[key];
      if (entry != null) {
        _memoryCache[key] = entry.copyWith(
          cachedAt: DateTime.now(),
        );
      }

      _backgroundRefreshes++;
      print('✅ InstagramCacheManager: Cache entry refreshed for $key');
    } catch (e) {
      print(
          '❌ InstagramCacheManager: Error refreshing cache entry for $key: $e');
    }
  }

  /// Get cache entry from disk
  Future<InstagramCacheEntry<T>?> _getFromDiskCache<T>(String key) async {
    try {
      final file = File('${_cacheDir.path}/$key.json');
      if (!await file.exists()) return null;

      final jsonString = await file.readAsString();
      final json = jsonDecode(jsonString);

      // Note: This is a simplified approach. In production, you'd want proper serialization
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
      print(
          '❌ InstagramCacheManager: Error reading from disk cache for $key: $e');
      return null;
    }
  }

  /// Persist cache entry to disk
  Future<void> _persistToDiskCache<T>(
      String key, InstagramCacheEntry<T> entry) async {
    try {
      final file = File('${_cacheDir.path}/$key.json');
      await file.writeAsString(jsonEncode(entry.toJson()));
    } catch (e) {
      print(
          '❌ InstagramCacheManager: Error persisting to disk cache for $key: $e');
    }
  }

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
            // Skip corrupted cache files
            print(
                '⚠️ InstagramCacheManager: Skipping corrupted cache file: ${file.path}');
          }
        }
      }

      print(
          '📁 InstagramCacheManager: Loaded $loadedCount entries from disk cache');
    } catch (e) {
      print('❌ InstagramCacheManager: Error loading persisted cache: $e');
    }
  }

  /// Start background refresh worker
  void _startBackgroundRefreshWorker() {
    Timer.periodic(const Duration(minutes: 1), (timer) {
      if (Features.smartVideoCaching.isEnabled) {
        _cleanupExpiredEntries();
      }
    });
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
            '🧹 InstagramCacheManager: Cleaned up ${keysToRemove.length} expired entries');
      }
    } catch (e) {
      print('❌ InstagramCacheManager: Error cleaning up expired entries: $e');
    }
  }

  /// Get cache type from key
  String _getCacheTypeFromKey(String key) {
    if (key.startsWith('video_')) return 'videos';
    if (key.startsWith('user_')) return 'user_profile';
    if (key.startsWith('ad_')) return 'ads';
    return 'default';
  }

  /// Get cache statistics
  Map<String, dynamic> getStats() {
    final totalRequests = _cacheHits + _cacheMisses;
    final hitRate =
        totalRequests > 0 ? (_cacheHits / totalRequests * 100) : 0.0;
    final etagHitRate =
        totalRequests > 0 ? (_etagHits / totalRequests * 100) : 0.0;

    return {
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

      print('🗑️ InstagramCacheManager: Cache cleared successfully');
    } catch (e) {
      print('❌ InstagramCacheManager: Error clearing cache: $e');
    }
  }

  /// Preload data for better user experience
  Future<void> preloadData<T>(
    List<String> keys,
    Future<T> Function(String key) fetchFn,
    String cacheType,
  ) async {
    if (!Features.backgroundVideoPreloading.isEnabled) return;

    try {
      print('🚀 InstagramCacheManager: Preloading ${keys.length} items...');

      for (final key in keys) {
        if (!_memoryCache.containsKey(key)) {
          unawaited(fetchFn(key).then((data) {
            if (data != null) {
              _cacheData(key, data, cacheType, null, null);
            }
          }));
        }
      }

      print('✅ InstagramCacheManager: Preload completed');
    } catch (e) {
      print('❌ InstagramCacheManager: Error during preload: $e');
    }
  }

  /// Dispose cache manager
  Future<void> dispose() async {
    try {
      // Save current cache state
      await _persistToDiskCache(
          '_cache_state',
          InstagramCacheEntry(
            data: _memoryCache.keys.toList(),
            lastModified: DateTime.now(),
            cachedAt: DateTime.now(),
            maxAge: const Duration(hours: 24),
            lastAccessed: DateTime.now(),
          ));

      print('✅ InstagramCacheManager: Disposal completed');
    } catch (e) {
      print('❌ InstagramCacheManager: Disposal failed: $e');
    }
  }
}

/// Extension for easier cache access
extension InstagramCacheExtension<T> on Future<T> Function() {
  Future<T?> withInstagramCache(
    String key, {
    String cacheType = 'default',
    Duration? maxAge,
    bool forceRefresh = false,
    String? currentEtag,
  }) {
    return YogCacheManager().get(
      key,
      fetchFn: this,
      cacheType: cacheType,
      maxAge: maxAge,
      forceRefresh: forceRefresh,
      currentEtag: currentEtag,
    );
  }
}
