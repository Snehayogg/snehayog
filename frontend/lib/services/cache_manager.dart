import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snehayog/services/video_cache_service.dart';

/// **Cache Manager - Centralized cache management for the app**
///
/// Features:
/// - Automatic cache cleanup
/// - Cache size monitoring
/// - Cache persistence management
/// - Background cache maintenance
class CacheManager {
  static CacheManager? _instance;
  static CacheManager get instance => _instance ??= CacheManager._();

  CacheManager._();

  static const String _lastCleanupKey = 'last_cache_cleanup';
  static const int _cleanupIntervalDays = 3; // Cleanup every 3 days
  static const int _maxCacheSizeMB = 500; // Maximum cache size: 500MB

  /// **Initialize cache manager**
  Future<void> initialize() async {
    try {
      print('🧹 CacheManager: Initializing...');

      // Perform initial cleanup if needed
      await _performCleanupIfNeeded();

      // Cleanup old cache files
      await VideoCacheService.instance.cleanupOldCache();

      print('✅ CacheManager: Initialized successfully');
    } catch (e) {
      print('❌ CacheManager: Error during initialization: $e');
    }
  }

  /// **Perform cleanup if needed**
  Future<void> _performCleanupIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCleanup = prefs.getInt(_lastCleanupKey);
      final now = DateTime.now().millisecondsSinceEpoch;

      if (lastCleanup == null ||
          (now - lastCleanup) > (_cleanupIntervalDays * 24 * 60 * 60 * 1000)) {
        print('🧹 CacheManager: Performing scheduled cleanup...');
        await performFullCleanup();
        await prefs.setInt(_lastCleanupKey, now);
      }
    } catch (e) {
      print('❌ CacheManager: Error checking cleanup schedule: $e');
    }
  }

  /// **Perform full cache cleanup**
  Future<void> performFullCleanup() async {
    try {
      print('🧹 CacheManager: Starting full cache cleanup...');

      // Get cache directory
      final cacheDir = await _getCacheDirectory();
      if (cacheDir == null) return;

      // Get all cache files
      final files = await cacheDir.list().toList();
      int totalSize = 0;
      int deletedCount = 0;

      // Calculate total cache size
      for (final file in files) {
        if (file is File) {
          final stat = await file.stat();
          totalSize += stat.size;
        }
      }

      final totalSizeMB = totalSize / (1024 * 1024);
      print(
          '📊 CacheManager: Total cache size: ${totalSizeMB.toStringAsFixed(2)} MB');

      int currentSize =
          totalSize; // Initialize currentSize outside the if block

      // If cache is too large, delete oldest files
      if (totalSizeMB > _maxCacheSizeMB) {
        print('⚠️ CacheManager: Cache size exceeds limit, cleaning up...');

        // Sort files by modification time (oldest first)
        final fileList = files.whereType<File>().toList();
        final fileStats = <File, FileStat>{};

        // Get stats for all files first
        for (final file in fileList) {
          fileStats[file] = await file.stat();
        }

        // Sort synchronously using pre-fetched stats
        fileList.sort((a, b) {
          final statA = fileStats[a]!;
          final statB = fileStats[b]!;
          return statA.modified.compareTo(statB.modified);
        });

        // Delete oldest files until we're under the limit
        for (final file in fileList) {
          if (currentSize <= (_maxCacheSizeMB * 1024 * 1024 * 0.8)) {
            break; // Keep 80% of limit
          }

          final stat = await file.stat();
          await file.delete();
          currentSize -= stat.size;
          deletedCount++;
        }
      }

      // Clean up expired cache files
      await _cleanupExpiredFiles();

      print('✅ CacheManager: Cleanup completed');
      print('   Deleted files: $deletedCount');
      print(
          '   Final cache size: ${(currentSize / (1024 * 1024)).toStringAsFixed(2)} MB');
    } catch (e) {
      print('❌ CacheManager: Error during full cleanup: $e');
    }
  }

  /// **Clean up expired cache files**
  Future<void> _cleanupExpiredFiles() async {
    try {
      final cacheDir = await _getCacheDirectory();
      if (cacheDir == null) return;

      final files = await cacheDir.list().toList();
      int deletedCount = 0;

      for (final file in files) {
        if (file is File) {
          final stat = await file.stat();
          final age = DateTime.now().millisecondsSinceEpoch -
              stat.modified.millisecondsSinceEpoch;

          // Delete files older than 7 days
          if (age > (7 * 24 * 60 * 60 * 1000)) {
            await file.delete();
            deletedCount++;
          }
        }
      }

      if (deletedCount > 0) {
        print('🗑️ CacheManager: Deleted $deletedCount expired cache files');
      }
    } catch (e) {
      print('❌ CacheManager: Error cleaning expired files: $e');
    }
  }

  /// **Get cache directory**
  Future<Directory?> _getCacheDirectory() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${appDir.path}/video_cache');

      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      return cacheDir;
    } catch (e) {
      print('❌ CacheManager: Error getting cache directory: $e');
      return null;
    }
  }

  /// **Get cache statistics**
  Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final cacheDir = await _getCacheDirectory();
      if (cacheDir == null) return {};

      final files = await cacheDir.list().toList();
      int totalSize = 0;
      int fileCount = 0;
      DateTime? oldestFile;
      DateTime? newestFile;

      for (final file in files) {
        if (file is File) {
          final stat = await file.stat();
          totalSize += stat.size;
          fileCount++;

          if (oldestFile == null || stat.modified.isBefore(oldestFile)) {
            oldestFile = stat.modified;
          }
          if (newestFile == null || stat.modified.isAfter(newestFile)) {
            newestFile = stat.modified;
          }
        }
      }

      return {
        'totalSize': totalSize,
        'totalSizeMB': (totalSize / (1024 * 1024)).toStringAsFixed(2),
        'fileCount': fileCount,
        'oldestFile': oldestFile,
        'newestFile': newestFile,
        'maxSizeMB': _maxCacheSizeMB,
        'usagePercentage': ((totalSize / (1024 * 1024)) / _maxCacheSizeMB * 100)
            .toStringAsFixed(1),
      };
    } catch (e) {
      print('❌ CacheManager: Error getting cache stats: $e');
      return {};
    }
  }

  /// **Clear all cache**
  Future<void> clearAllCache() async {
    try {
      print('🧹 CacheManager: Clearing all cache...');

      // Clear video cache
      await VideoCacheService.instance.clearCache();

      // Clear cache directory
      final cacheDir = await _getCacheDirectory();
      if (cacheDir != null) {
        final files = await cacheDir.list().toList();
        for (final file in files) {
          if (file is File) {
            await file.delete();
          }
        }
      }

      // Clear cleanup timestamp
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_lastCleanupKey);

      print('✅ CacheManager: All cache cleared');
    } catch (e) {
      print('❌ CacheManager: Error clearing all cache: $e');
    }
  }

  /// **Force cleanup (for manual trigger)**
  Future<void> forceCleanup() async {
    try {
      print('🧹 CacheManager: Force cleanup triggered...');
      await performFullCleanup();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
          _lastCleanupKey, DateTime.now().millisecondsSinceEpoch);

      print('✅ CacheManager: Force cleanup completed');
    } catch (e) {
      print('❌ CacheManager: Error during force cleanup: $e');
    }
  }
}
