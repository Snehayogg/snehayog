import 'dart:async';
import 'package:flutter/material.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/core/managers/video_disk_cache_manager.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/utils/feature_flags.dart';

class VideoCacheManager extends ChangeNotifier {
  final VideoService _videoService = VideoService();
  final VideoDiskCacheManager _diskCacheManager = VideoDiskCacheManager();

  final Map<String, dynamic> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Map<String, String> _cacheEtags = {};
  final Map<String, String> _cacheLastModified =
      {}; // **NEW: Track Last-Modified for CDN**

  // Cache configuration
  static const Duration _videosCacheTime = Duration(minutes: 15);
  static const Duration _staleWhileRevalidateTime = Duration(minutes: 5);
  static const Duration _cdnCacheTime =
      Duration(minutes: 5); // **NEW: CDN cache time**

  // Cache keys
  static const String _videosCacheKey = 'videos_page_';
  static const String _videoDetailCacheKey = 'video_detail_';

  /// Get videos with CDN edge caching for optimal performance
  Future<Map<String, dynamic>> getVideos({
    int page = 1,
    int limit = 10,
    bool forceRefresh = false,
    String? currentEtag,
  }) async {
    final cacheKey = '$_videosCacheKey$page';

    print(
        '🎯 VideoCacheManager: Getting videos for page $page (forceRefresh: $forceRefresh)');
    print('🔍 VideoCacheManager: Cache key: $cacheKey');
    print('🔍 VideoCacheManager: Current cache size: ${_cache.length}');
    print('🔍 VideoCacheManager: Cache keys: ${_cache.keys.toList()}');

    try {
      // **NEW: CDN Edge Caching Strategy**
      if (!forceRefresh) {
        // Check if we have cached data with ETag
        final cachedData = _getFromCache(cacheKey);
        if (cachedData != null) {
          final cachedEtag = _cacheEtags[cacheKey];
          final cachedLastModified = _cacheLastModified[cacheKey];

          print(
              '🔍 VideoCacheManager: Found cached data, using conditional request');
          print('🔍 VideoCacheManager: Cached ETag: $cachedEtag');
          print(
              '🔍 VideoCacheManager: Cached Last-Modified: $cachedLastModified');
          try {
            final response = await _videoService.getVideos(
              page: page,
              limit: limit,
            );

            // Check if we have fresh data
            if (response['videos'] != null && response['videos'].isNotEmpty) {
              print('✅ VideoCacheManager: Fresh data from CDN, updating cache');
              // Update cache with new data
              _updateCacheWithCDNData(cacheKey, response);
              return response;
            } else {
              print('✅ VideoCacheManager: CDN cache hit (no new data)');
              // Return cached data since nothing changed
              return cachedData;
            }
          } catch (e) {
            print(
                '⚠️ VideoCacheManager: CDN conditional request failed, using cached data: $e');
            // Fallback to cached data if CDN request fails
            return cachedData;
          }
        }
      }

      print('📡 VideoCacheManager: Fetching fresh data from CDN');
      try {
        final freshData = await _videoService.getVideos(
          page: page,
          limit: limit,
        );
        _updateCacheWithCDNData(cacheKey, freshData);
        return freshData;
      } catch (e) {
        print(
            '⚠️ VideoCacheManager: CDN request failed, trying fallback method: $e');

        // **FALLBACK: Try the regular getVideos method if CDN method fails**
        try {
          final fallbackData = await _videoService.getVideos(
            page: page,
            limit: limit,
          );

          print('✅ VideoCacheManager: Fallback method succeeded');
          _updateCacheWithCDNData(cacheKey, fallbackData);
          return fallbackData;
        } catch (fallbackError) {
          print(
              '❌ VideoCacheManager: Both CDN and fallback methods failed: $fallbackError');
          rethrow;
        }
      }
    } catch (e) {
      print('❌ VideoCacheManager: Error getting videos for page $page: $e');

      // **FALLBACK: Try to return cached data on error**
      final cachedData = _getFromCache(cacheKey);
      if (cachedData != null) {
        print('🔄 VideoCacheManager: Using fallback cache for page $page');
        return Map<String, dynamic>.from(cachedData);
      }

      // Return empty result as last resort
      return {
        'videos': [],
        'hasMore': false,
        'total': 0,
        'currentPage': page,
        'status': 500,
        'error': e.toString()
      };
    }
  }

  /// **NEW: Update cache with CDN response data and headers**
  void _updateCacheWithCDNData(String cacheKey, Map<String, dynamic> response) {
    // Store the response data
    _cache[cacheKey] = response;
    _cacheTimestamps[cacheKey] = DateTime.now();

    // Store CDN cache headers
    if (response['cdnCache'] != null) {
      final cdnCache = response['cdnCache'] as Map<String, dynamic>;
      _cacheEtags[cacheKey] = cdnCache['etag'] ?? '';
      _cacheLastModified[cacheKey] = cdnCache['lastModified'] ?? '';

      print('💾 VideoCacheManager: Updated cache with CDN headers');
      print('  - ETag: ${cdnCache['etag']}');
      print('  - Last-Modified: ${cdnCache['lastModified']}');
      print('  - Cache Status: ${cdnCache['cacheStatus']}');
      print('  - Is From CDN: ${cdnCache['isFromCDN']}');
    }

    print('💾 VideoCacheManager: Cached data for key: $cacheKey');
    print('🔍 VideoCacheManager: Total cache size now: ${_cache.length}');
  }

  /// Get cached videos for instant return (used when switching tabs)
  Map<String, dynamic>? getCachedVideos({int page = 1, int limit = 10}) {
    final cacheKey = '$_videosCacheKey$page';
    return _getFromCache(cacheKey);
  }

  /// Check if we have cached videos for a specific page
  bool hasCachedVideos({int page = 1}) {
    final cacheKey = '$_videosCacheKey$page';
    return _cache.containsKey(cacheKey) &&
        _cacheTimestamps.containsKey(cacheKey) &&
        !_isCacheStale(cacheKey, _videosCacheTime);
  }

  /// Get cache statistics
  Map<String, dynamic> getCacheStats() {
    final diskStats = _diskCacheManager.getCacheStats();

    return {
      'memoryCacheSize': _cache.length,
      'memoryCacheKeys': _cache.keys.toList(),
      'videosCacheTime': _videosCacheTime.inMinutes,
      'staleWhileRevalidateTime': _staleWhileRevalidateTime.inMinutes,
      'cdnCacheTime': _cdnCacheTime.inMinutes, // **NEW: CDN cache time**
      'totalCachedPages':
          _cache.keys.where((key) => key.startsWith(_videosCacheKey)).length,
      // **NEW: CDN Cache Statistics**
      'cdnCacheStats': {
        'totalEtags': _cacheEtags.length,
        'totalLastModified': _cacheLastModified.length,
        'cdnOptimizedRequests':
            _cacheEtags.values.where((etag) => etag.isNotEmpty).length,
        'conditionalRequestsSupported': _cacheEtags.isNotEmpty,
      },
      // Disk cache stats
      'diskCacheStats': diskStats,
      'totalCachedVideos': diskStats['totalCachedVideos'],
      'fullyDownloadedVideos': diskStats['fullyDownloaded'],
      'preloadOnlyVideos': diskStats['preloadOnly'],
      'diskCacheSizeMB': diskStats['totalSizeMB'],
    };
  }

  /// Clear all caches
  void clearAllCaches() {
    _cache.clear();
    _cacheTimestamps.clear();
    _cacheEtags.clear();
    _cacheLastModified.clear(); // **NEW: Clear CDN headers**
    print('🧹 VideoCacheManager: All caches cleared (including CDN headers)');
    notifyListeners();
  }

  /// Clear cache for specific page
  void clearPageCache(int page) {
    final cacheKey = '$_videosCacheKey$page';
    _cache.remove(cacheKey);
    _cacheTimestamps.remove(cacheKey);
    _cacheEtags.remove(cacheKey);
    print('🧹 VideoCacheManager: Cleared cache for page $page');
    notifyListeners();
  }

  /// Initialize cache manager with disk cache
  Future<void> initialize() async {
    try {
      print('🚀 VideoCacheManager: Initializing with disk cache...');
      await _diskCacheManager.initialize();
      print('✅ VideoCacheManager: Initialized successfully');
    } catch (e) {
      print('❌ VideoCacheManager: Error initializing: $e');
    }
  }

  /// **SMART PRELOADING: Preload videos for instant start**
  Future<void> preloadVideosForInstantStart(List<VideoModel> videos) async {
    if (!Features.smartVideoCaching.isEnabled) return;

    try {
      print(
          '🚀 VideoCacheManager: Starting smart preloading for ${videos.length} videos...');

      // Preload first 8 seconds of each video for instant start
      for (final video in videos) {
        unawaited(_diskCacheManager.preloadVideoForInstantStart(video));
      }

      print(
          '✅ VideoCacheManager: Smart preloading started for ${videos.length} videos');
    } catch (e) {
      print('❌ VideoCacheManager: Error in smart preloading: $e');
    }
  }

  /// **GET CACHED VIDEO PATH: Get local file path for instant loading**
  Future<String?> getCachedVideoPath(String videoId) async {
    try {
      return await _diskCacheManager.getCachedVideoPath(videoId);
    } catch (e) {
      print('❌ VideoCacheManager: Error getting cached video path: $e');
      return null;
    }
  }

  /// **DOWNLOAD PROGRESS: Get progress stream for video download**
  Stream<double>? getDownloadProgress(String videoId) {
    return _diskCacheManager.getDownloadProgress(videoId);
  }

  /// Preload and cache data for better performance
  Future<void> preloadAndCacheData() async {
    if (!Features.smartVideoCaching.isEnabled) return;

    try {
      print('🚀 VideoCacheManager: Preloading and caching data...');

      // Preload first few pages
      for (int page = 1; page <= 3; page++) {
        if (!hasCachedVideos(page: page)) {
          unawaited(_preloadPage(page));
        }
      }

      print('✅ VideoCacheManager: Preloading completed');
    } catch (e) {
      print('❌ VideoCacheManager: Error preloading data: $e');
    }
  }

  /// Preload a specific page in background
  Future<void> _preloadPage(int page) async {
    try {
      print('🔄 VideoCacheManager: Preloading page $page...');
      final data = await _fetchVideosFromServer(page: page, limit: 20);
      final cacheKey = '$_videosCacheKey$page';
      _setCache(cacheKey, data, _videosCacheTime);
      print('✅ VideoCacheManager: Preloaded page $page');
    } catch (e) {
      print('❌ VideoCacheManager: Error preloading page $page: $e');
    }
  }

  // Instagram-like caching methods (same as ProfileStateManager)
  /// Get data from cache
  dynamic _getFromCache(String key) {
    print('🔍 VideoCacheManager: _getFromCache called for key: $key');
    print(
        '🔍 VideoCacheManager: _cache contains key: ${_cache.containsKey(key)}');
    print(
        '🔍 VideoCacheManager: _cacheTimestamps contains key: ${_cacheTimestamps.containsKey(key)}');

    if (_cache.containsKey(key) && _cacheTimestamps.containsKey(key)) {
      final timestamp = _cacheTimestamps[key]!;
      final now = DateTime.now();
      final age = now.difference(timestamp);
      const maxAge = _videosCacheTime;

      print(
          '🔍 VideoCacheManager: Cache age: ${age.inMinutes} minutes, max age: ${maxAge.inMinutes} minutes');

      if (age < maxAge) {
        print('⚡ VideoCacheManager: Cache hit for key: $key');
        return _cache[key];
      } else {
        print('🔄 VideoCacheManager: Cache expired for key: $key');
        _cache.remove(key);
        _cacheTimestamps.remove(key);
        _cacheEtags.remove(key);
      }
    } else {
      print('🔍 VideoCacheManager: Key not found in cache or timestamps');
    }
    return null;
  }

  /// Set data in cache
  void _setCache(String key, dynamic data, Duration maxAge) {
    print('💾 VideoCacheManager: _setCache called for key: $key');
    print('🔍 VideoCacheManager: Data type: ${data.runtimeType}');
    print(
        '🔍 VideoCacheManager: Data contains videos: ${data is Map && data.containsKey('videos')}');
    if (data is Map && data.containsKey('videos')) {
      print(
          '🔍 VideoCacheManager: Videos count: ${(data['videos'] as List).length}');
    }

    _cache[key] = data;
    _cacheTimestamps[key] = DateTime.now();

    // **NEW: Extract and store CDN headers if available**
    if (data is Map && data.containsKey('cdnCache')) {
      final cdnCache = data['cdnCache'] as Map<String, dynamic>;
      _cacheEtags[key] = cdnCache['etag'] ?? '';
      _cacheLastModified[key] = cdnCache['lastModified'] ?? '';

      print('💾 VideoCacheManager: Stored CDN headers:');
      print('  - ETag: ${cdnCache['etag']}');
      print('  - Last-Modified: ${cdnCache['lastModified']}');
    }

    print('💾 VideoCacheManager: Cached data for key: $key');
    print('🔍 VideoCacheManager: Total cache size now: ${_cache.length}');
  }

  /// Check if cache is stale (can be used but should be refreshed)
  bool _isCacheStale(String key, Duration maxAge) {
    if (_cacheTimestamps.containsKey(key)) {
      final timestamp = _cacheTimestamps[key]!;
      final now = DateTime.now();
      final age = now.difference(timestamp);
      return age > maxAge * 0.8; // Refresh when 80% of max age is reached
    }
    return false;
  }

  /// Schedule background refresh for stale data
  void _scheduleBackgroundRefresh(
      String key, Future<Map<String, dynamic>> Function() fetchFn) {
    if (Features.backgroundVideoPreloading.isEnabled) {
      print(
          '🔄 VideoCacheManager: Scheduling background refresh for key: $key');
      unawaited(_refreshCacheInBackground(key, fetchFn));
    }
  }

  /// Refresh cache in background
  Future<void> _refreshCacheInBackground(
      String key, Future<Map<String, dynamic>> Function() fetchFn) async {
    try {
      await Future.delayed(
          const Duration(seconds: 2)); // Small delay to avoid blocking UI
      final freshData = await fetchFn();

      if (freshData['videos'] != null && freshData['videos'].isNotEmpty) {
        _setCache(key, freshData, _videosCacheTime);
        print(
            '✅ VideoCacheManager: Background refresh completed for key: $key');
        notifyListeners();
      }
    } catch (e) {
      print('❌ VideoCacheManager: Background refresh failed for key: $key: $e');
    }
  }

  /// Fetch videos from server
  Future<Map<String, dynamic>> _fetchVideosFromServer({
    int page = 1,
    int limit = 10,
  }) async {
    try {
      print('📡 VideoCacheManager: Fetching videos from CDN for page $page');

      // **NEW: Use CDN-optimized method instead of direct API call**
      final response = await _videoService.getVideos(
        page: page,
        limit: limit,
      );

      print(
          '✅ VideoCacheManager: Fetched ${response['videos']?.length ?? 0} videos from CDN');
      print('🔍 VideoCacheManager: CDN Response status: ${response['status']}');

      // Log CDN cache information
      if (response['cdnCache'] != null) {
        final cdnCache = response['cdnCache'] as Map<String, dynamic>;
        print('🔍 VideoCacheManager: CDN Cache Info:');
        print('  - ETag: ${cdnCache['etag']}');
        print('  - Last-Modified: ${cdnCache['lastModified']}');
        print('  - Cache Status: ${cdnCache['cacheStatus']}');
        print('  - Is From CDN: ${cdnCache['isFromCDN']}');
      }

      return response;
    } catch (e) {
      print('❌ VideoCacheManager: Error fetching videos from CDN: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    print('🔄 VideoCacheManager: Disposing...');
    _diskCacheManager.dispose();
    super.dispose();
  }
}
