import 'dart:io';
import 'dart:collection';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:snehayog/utils/feature_flags.dart';
import 'package:snehayog/model/video_model.dart';
import 'dart:async';

/// Video cache information for smart management
class VideoCacheInfo {
  final String videoId;
  final DateTime cachedAt;
  final int fileSize;
  int accessCount;
  DateTime lastAccessed;

  VideoCacheInfo({
    required this.videoId,
    required this.cachedAt,
    required this.fileSize,
    this.accessCount = 0,
    required this.lastAccessed,
  });
}

/// Enhanced Video Cache Manager with Fast Video Delivery System
/// Implements background preloading and smart caching for instant video playback
class VideoCacheManager {
  static const int _maxCacheSizeMB = 500; // 500MB threshold
  static const int _maxPreloadVideos = 3; // Preload next 3 videos

  // Cache for video metadata and preload status
  final Map<String, VideoCacheInfo> _videoCacheInfo = {};
  final Map<String, File> _cachedVideos = {};
  final Set<String> _preloadingVideos = {};

  // Preload queue management
  final Queue<String> _preloadQueue = Queue<String>();
  bool _isPreloading = false;

  // Performance metrics
  int _cacheHits = 0;
  int _cacheMisses = 0;
  DateTime _lastCacheCleanup = DateTime.now();

  /// Enhanced pre-cache videos with smart preloading strategy
  Future<void> preCacheVideos(List<VideoModel> videos, int currentIndex) async {
    if (!Features.fastVideoDelivery.isEnabled) {
      print(
          '🚫 VideoCacheManager: Fast video delivery disabled, skipping preload');
      return;
    }

    print(
        '🚀 VideoCacheManager: Starting smart preload for ${videos.length} videos');
    print(
        '🚀 VideoCacheManager: Current index: $currentIndex, Videos to preload: ${_calculatePreloadIndices(currentIndex, videos.length)}');

    // Calculate which videos to preload
    final preloadIndices =
        _calculatePreloadIndices(currentIndex, videos.length);

    for (final index in preloadIndices) {
      if (index < videos.length) {
        final video = videos[index];
        print(
            '🚀 VideoCacheManager: Preloading video at index $index: ${video.videoName} (ID: ${video.id})');
        await _preloadVideo(video);
      }
    }

    print(
        '✅ VideoCacheManager: Smart preload completed for ${preloadIndices.length} videos');
  }

  /// Calculate which video indices to preload based on current position
  List<int> _calculatePreloadIndices(int currentIndex, int totalVideos) {
    final indices = <int>{};

    // Always preload next video
    if (currentIndex + 1 < totalVideos) {
      indices.add(currentIndex + 1);
    }

    // Preload next 2-3 videos for smooth experience
    for (int i = 2;
        i <= _maxPreloadVideos && currentIndex + i < totalVideos;
        i++) {
      indices.add(currentIndex + i);
    }

    // Also preload previous video for back navigation
    if (currentIndex > 0) {
      indices.add(currentIndex - 1);
    }

    return indices.toList()..sort();
  }

  /// Preload a specific video with priority
  Future<void> _preloadVideo(VideoModel video) async {
    if (_preloadingVideos.contains(video.id) ||
        _cachedVideos.containsKey(video.id)) {
      print(
          '⏭️ VideoCacheManager: Skipping ${video.videoName} - already preloading or cached');
      return; // Already preloading or cached
    }

    _preloadingVideos.add(video.id);
    print('📥 VideoCacheManager: Preloading video: ${video.videoName}');
    print('📥 VideoCacheManager: Video URL: ${video.videoUrl}');

    try {
      // Start background preload
      print(
          '📥 VideoCacheManager: Starting download for ${video.videoName}...');
      final file = await DefaultCacheManager().getSingleFile(video.videoUrl);

      _cachedVideos[video.id] = file;
      _videoCacheInfo[video.id] = VideoCacheInfo(
        videoId: video.id,
        cachedAt: DateTime.now(),
        fileSize: await file.length(),
        accessCount: 0,
        lastAccessed: DateTime.now(),
      );

      print(
          '✅ VideoCacheManager: Preloaded video: ${video.videoName} (${(await file.length() / 1024 / 1024).toStringAsFixed(2)}MB)');
      print(
          '✅ VideoCacheManager: Cache map now contains ${_cachedVideos.length} videos');
    } catch (e) {
      print(
          '❌ VideoCacheManager: Failed to preload video ${video.videoName}: $e');
      print('❌ VideoCacheManager: Error details: ${e.toString()}');
    } finally {
      _preloadingVideos.remove(video.id);
    }
  }

  /// Get cached video file with instant access
  Future<File?> getCachedVideo(String videoId, String videoUrl) async {
    if (!Features.instantVideoPlayback.isEnabled) {
      return null; // Feature disabled
    }

    // Check memory cache first (fastest)
    if (_cachedVideos.containsKey(videoId)) {
      final file = _cachedVideos[videoId]!;
      if (await file.exists()) {
        _updateAccessInfo(videoId);
        _cacheHits++;
        print('⚡ VideoCacheManager: Instant cache hit for video: $videoId');
        return file;
      } else {
        // File was deleted, remove from cache
        _cachedVideos.remove(videoId);
        _videoCacheInfo.remove(videoId);
      }
    }

    // Check disk cache
    try {
      final file = await DefaultCacheManager().getSingleFile(videoUrl);
      if (await file.exists()) {
        // Add to memory cache for faster future access
        _cachedVideos[videoId] = file;
        _videoCacheInfo[videoId] = VideoCacheInfo(
          videoId: videoId,
          cachedAt: DateTime.now(),
          fileSize: await file.length(),
          accessCount: 1,
          lastAccessed: DateTime.now(),
        );

        _cacheHits++;
        print('💾 VideoCacheManager: Disk cache hit for video: $videoId');
        return file;
      }
    } catch (e) {
      print('❌ VideoCacheManager: Error accessing disk cache: $e');
    }

    _cacheMisses++;
    print('❌ VideoCacheManager: Cache miss for video: $videoId');
    return null;
  }

  /// Update video access information for smart cache management
  void _updateAccessInfo(String videoId) {
    final info = _videoCacheInfo[videoId];
    if (info != null) {
      info.accessCount++;
      info.lastAccessed = DateTime.now();
    }
  }

  /// Smart cache management with memory optimization
  Future<void> smartCacheManagement(
      int videoCount, int activeVideoIndex) async {
    if (!Features.videoMemoryOptimization.isEnabled) {
      return;
    }

    try {
      print('🧠 VideoCacheManager: Running smart cache management...');

      // Clean up old cache if we have too many videos
      if (videoCount > 50 || _cachedVideos.length > 20) {
        await _cleanupOldCache();
      }

      // Optimize memory usage
      await _optimizeMemoryUsage();

      // Update cleanup timestamp
      _lastCacheCleanup = DateTime.now();

      print('✅ VideoCacheManager: Smart cache management completed');
    } catch (e) {
      print('❌ VideoCacheManager: Smart cache management failed: $e');
    }
  }

  /// Clean up old and unused cached videos
  Future<void> _cleanupOldCache() async {
    try {
      final now = DateTime.now();
      final videosToRemove = <String>[];

      for (final entry in _videoCacheInfo.entries) {
        final videoId = entry.key;
        final info = entry.value;

        // Remove videos older than 1 hour and accessed less than 2 times
        if (now.difference(info.cachedAt) > const Duration(hours: 1) &&
            info.accessCount < 2) {
          videosToRemove.add(videoId);
        }
      }

      for (final videoId in videosToRemove) {
        await _removeCachedVideo(videoId);
      }

      if (videosToRemove.isNotEmpty) {
        print(
            '🧹 VideoCacheManager: Cleaned up ${videosToRemove.length} old cached videos');
      }
    } catch (e) {
      print('❌ VideoCacheManager: Error cleaning old cache: $e');
    }
  }

  /// Optimize memory usage by keeping only essential videos in memory
  Future<void> _optimizeMemoryUsage() async {
    try {
      // Keep only recently accessed videos in memory cache
      final videosToKeep = <String>[];

      // Sort by access count and recency
      final sortedVideos = _videoCacheInfo.entries.toList()
        ..sort((a, b) {
          if (a.value.accessCount != b.value.accessCount) {
            return b.value.accessCount.compareTo(a.value.accessCount);
          }
          return b.value.lastAccessed.compareTo(a.value.lastAccessed);
        });

      // Keep top 10 most accessed videos in memory
      for (int i = 0; i < sortedVideos.length && i < 10; i++) {
        videosToKeep.add(sortedVideos[i].key);
      }

      // Remove videos not in keep list from memory cache
      final videosToRemove =
          _cachedVideos.keys.where((id) => !videosToKeep.contains(id)).toList();

      for (final videoId in videosToRemove) {
        _cachedVideos.remove(videoId);
        // Keep metadata for disk cache access
      }

      if (videosToRemove.isNotEmpty) {
        print(
            '💾 VideoCacheManager: Optimized memory usage, removed ${videosToRemove.length} videos from memory cache');
      }
    } catch (e) {
      print('❌ VideoCacheManager: Error optimizing memory usage: $e');
    }
  }

  /// Remove a specific cached video
  Future<void> _removeCachedVideo(String videoId) async {
    try {
      final file = _cachedVideos.remove(videoId);
      _videoCacheInfo.remove(videoId);

      if (file != null && await file.exists()) {
        await file.delete();
        print('🗑️ VideoCacheManager: Removed cached video: $videoId');
      }
    } catch (e) {
      print('❌ VideoCacheManager: Error removing cached video $videoId: $e');
    }
  }

  /// Get cache performance statistics
  Map<String, dynamic> getCacheStats() {
    final totalRequests = _cacheHits + _cacheMisses;
    final hitRate =
        totalRequests > 0 ? (_cacheHits / totalRequests * 100) : 0.0;

    return {
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'hitRate': hitRate.toStringAsFixed(2),
      'cachedVideos': _cachedVideos.length,
      'preloadingVideos': _preloadingVideos.length,
      'cacheSize': _videoCacheInfo.length,
      'lastCleanup': _lastCacheCleanup.toIso8601String(),
    };
  }

  /// Check if video is currently being preloaded
  bool isPreloading(String videoId) {
    return _preloadingVideos.contains(videoId);
  }

  /// Check if video is cached and ready for instant playback
  bool isVideoCached(String videoId) {
    final isCached = _cachedVideos.containsKey(videoId);
    print(
        '🔍 VideoCacheManager: Checking cache for video $videoId - Cached: $isCached');
    print('🔍 VideoCacheManager: Total cached videos: ${_cachedVideos.length}');
    if (isCached) {
      print('🔍 VideoCacheManager: Cache keys: ${_cachedVideos.keys.toList()}');
    }
    return isCached;
  }

  /// Get preload progress for a video
  double getPreloadProgress(String videoId) {
    if (_cachedVideos.containsKey(videoId)) {
      return 1.0; // Fully cached
    } else if (_preloadingVideos.contains(videoId)) {
      return 0.5; // Currently preloading
    }
    return 0.0; // Not started
  }

  /// Clear video cache to free up disk space
  Future<void> clearVideoCache() async {
    try {
      print('🗑️ VideoCacheManager: Clearing video cache...');
      await DefaultCacheManager().emptyCache();
      print('✅ VideoCacheManager: Video cache cleared successfully');
    } catch (e) {
      print('❌ Error clearing video cache: $e');
    }
  }

  /// Get cache info (size, file count)
  Future<Map<String, dynamic>> getCacheInfo() async {
    try {
      print('📊 VideoCacheManager: Getting cache info...');

      final cacheDir =
          Directory('${Directory.systemTemp.path}/libCachedImageData');
      if (await cacheDir.exists()) {
        final cacheSize = await _getDirectorySize(cacheDir);
        final fileCount = await _getFileCount(cacheDir);

        return {
          'size': cacheSize,
          'sizeMB': (cacheSize / (1024 * 1024)).toStringAsFixed(2),
          'fileCount': fileCount,
          'exists': true,
        };
      } else {
        return {
          'size': 0,
          'sizeMB': '0.00',
          'fileCount': 0,
          'exists': false,
        };
      }
    } catch (e) {
      print('❌ Error getting cache info: $e');
      return {
        'size': 0,
        'sizeMB': '0.00',
        'fileCount': 0,
        'exists': false,
        'error': e.toString(),
      };
    }
  }

  Future<void> initialize() async {
    try {
      print('�� VideoCacheManager: Initializing cache manager...');

      // Create cache directory if it doesn't exist
      final cacheDir = await getTemporaryDirectory();
      final videoCacheDir = Directory('${cacheDir.path}/video_cache');

      if (!await videoCacheDir.exists()) {
        await videoCacheDir.create(recursive: true);
        print(
            '�� VideoCacheManager: Created cache directory: ${videoCacheDir.path}');
      }

      // Clear old cached files (older than 7 days)
      await _cleanOldCache(videoCacheDir);

      print('✅ VideoCacheManager: Initialization completed');
    } catch (e) {
      print('❌ VideoCacheManager: Initialization failed: $e');
    }
  }

  Future<void> _cleanOldCache(Directory cacheDir) async {
    try {
      final files = cacheDir.listSync();
      final now = DateTime.now();
      const maxAge = Duration(days: 7);

      for (final file in files) {
        if (file is File) {
          final stat = await file.stat();
          if (now.difference(stat.modified) > maxAge) {
            await file.delete();
            print(
                '��️ VideoCacheManager: Deleted old cache file: ${file.path}');
          }
        }
      }
    } catch (e) {
      print('⚠️ VideoCacheManager: Failed to clean old cache: $e');
    }
  }

  /// Automated cache cleanup - frees up disk space when needed
  Future<void> automatedCacheCleanup() async {
    try {
      print('🤖 VideoCacheManager: Running automated cache cleanup...');

      final cacheInfo = await getCacheInfo();
      if (cacheInfo['exists'] == true) {
        final cacheSize = cacheInfo['size'] as int;
        final cacheSizeMB = cacheInfo['sizeMB'] as String;

        print('📊 VideoCacheManager: Current cache size: $cacheSizeMB MB');

        // If cache is larger than threshold, clean it automatically
        if (cacheSize > _maxCacheSizeMB * 1024 * 1024) {
          print(
              '⚠️ VideoCacheManager: Cache size exceeds ${_maxCacheSizeMB}MB, cleaning automatically...');
          await clearVideoCache();
          print('✅ VideoCacheManager: Automated cache cleanup completed');
        } else {
          print(
              '✅ VideoCacheManager: Cache size is within limits, no cleanup needed');
        }
      } else {
        print('📁 VideoCacheManager: Cache directory does not exist yet');
      }
    } catch (e) {
      print('❌ Error in automated cache cleanup: $e');
    }
  }

  /// Get directory size in bytes
  Future<int> _getDirectorySize(Directory dir) async {
    try {
      int totalSize = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      print('❌ Error getting directory size: $e');
      return 0;
    }
  }

  /// Get file count in directory
  Future<int> _getFileCount(Directory dir) async {
    try {
      int count = 0;
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          count++;
        }
      }
      return count;
    } catch (e) {
      print('❌ Error getting file count: $e');
      return 0;
    }
  }

  /// Check if cache is healthy
  Future<bool> isCacheHealthy() async {
    try {
      final cacheInfo = await getCacheInfo();
      if (cacheInfo['exists'] == true) {
        final cacheSize = cacheInfo['size'] as int;
        return cacheSize <= _maxCacheSizeMB * 1024 * 1024;
      }
      return true; // No cache directory means healthy
    } catch (e) {
      print('❌ Error checking cache health: $e');
      return false;
    }
  }

  /// Dispose and clean up resources
  Future<void> dispose() async {
    try {
      print('🗑️ VideoCacheManager: Disposing cache manager...');

      // Clear all cached files
      await clearVideoCache();

      print('✅ VideoCacheManager: Disposal completed');
    } catch (e) {
      print('❌ VideoCacheManager: Disposal failed: $e');
    }
  }
}
