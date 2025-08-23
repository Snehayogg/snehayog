import 'dart:io';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path_provider/path_provider.dart';

/// Manages video caching for optimal performance and storage
class VideoCacheManager {
  static const int _maxCacheSizeMB = 500; // 500MB threshold

  /// Pre-cache videos for instant playback
  Future<void> preCacheVideos(List<String> urls) async {
    print('📦 VideoCacheManager: Pre-caching ${urls.length} videos');

    for (final url in urls) {
      try {
        // Start caching in background
        DefaultCacheManager().getSingleFile(url).then((file) {
          print('✅ VideoCacheManager: Pre-cached video: ${file.path}');
        }).catchError((e) {
          print('❌ Error pre-caching video: $e');
        });
      } catch (e) {
        print('❌ Error starting pre-cache for video: $e');
      }
    }
  }

  /// Get cached video file
  Future<File?> getCachedVideo(String url) async {
    try {
      final file = await DefaultCacheManager().getSingleFile(url);
      return file;
    } catch (e) {
      print('❌ Error getting cached video: $e');
      return null;
    }
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

  /// Smart cache management based on video count and usage
  Future<void> smartCacheManagement(
      int videoCount, int activeVideoIndex) async {
    try {
      print('🧠 VideoCacheManager: Running smart cache management...');

      // If we have too many videos loaded, clean up old cache
      if (videoCount > 50) {
        print(
            '📊 VideoCacheManager: Large video list detected, cleaning old cache...');
        await clearVideoCache();
        print('🧠 VideoCacheManager: Smart cache cleanup completed');
      }
    } catch (e) {
      print('❌ Error in smart cache management: $e');
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
