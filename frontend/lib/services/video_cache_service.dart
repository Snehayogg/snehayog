import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// **Video Cache Service - Optimized for First Video Instant Loading**
///
/// Features:
/// - Cache first video locally for instant playback
/// - Persist cache across app restarts
/// - Seamless integration with VideoPlayerController
/// - Automatic cache management and cleanup
class VideoCacheService {
  static const String _cacheKey = 'first_video_cache';
  static const String _cacheUrlKey = 'first_video_url';
  static const String _cacheTimestampKey = 'first_video_timestamp';
  static const int _maxCacheAge =
      7 * 24 * 60 * 60 * 1000; // 7 days in milliseconds

  static VideoCacheService? _instance;
  static VideoCacheService get instance => _instance ??= VideoCacheService._();

  VideoCacheService._();

  /// **Cache the first video for instant loading**
  Future<bool> cacheFirstVideo(String videoUrl, String videoId) async {
    try {
      print('🎬 VideoCacheService: Starting cache for first video: $videoId');

      // Check if already cached and valid
      if (await isVideoCached(videoUrl)) {
        print('✅ VideoCacheService: Video already cached and valid');
        return true;
      }

      // Get cache directory
      final cacheDir = await _getCacheDirectory();
      if (cacheDir == null) {
        print('❌ VideoCacheService: Failed to get cache directory');
        return false;
      }

      // Create cache file path
      final cacheFile = File('${cacheDir.path}/first_video_$videoId.mp4');

      // Download and cache video
      print('📥 VideoCacheService: Downloading video...');
      final response = await http.get(
        Uri.parse(videoUrl),
        headers: {
          'User-Agent': 'Snehayog/1.0',
          'Accept': 'video/mp4,video/*,*/*',
        },
      ).timeout(const Duration(minutes: 5));

      if (response.statusCode == 200) {
        // Save video to cache
        await cacheFile.writeAsBytes(response.bodyBytes);

        // Save cache metadata
        await _saveCacheMetadata(videoUrl, videoId, cacheFile.path);

        print('✅ VideoCacheService: Video cached successfully');
        print('📁 Cache file: ${cacheFile.path}');
        print(
            '📊 Cache size: ${(response.bodyBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');

        return true;
      } else {
        print(
            '❌ VideoCacheService: Failed to download video: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      print('❌ VideoCacheService: Error caching video: $e');
      return false;
    }
  }

  /// **Get cached video file path if available**
  Future<String?> getCachedVideoPath(String videoUrl) async {
    try {
      if (!await isVideoCached(videoUrl)) {
        return null;
      }

      final prefs = await SharedPreferences.getInstance();
      final cachePath = prefs.getString('${_cacheKey}_path');

      if (cachePath != null && await File(cachePath).exists()) {
        print('🎬 VideoCacheService: Found cached video: $cachePath');
        return cachePath;
      }

      return null;
    } catch (e) {
      print('❌ VideoCacheService: Error getting cached video path: $e');
      return null;
    }
  }

  /// **Check if video is cached and valid**
  Future<bool> isVideoCached(String videoUrl) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedUrl = prefs.getString(_cacheUrlKey);
      final cacheTimestamp = prefs.getInt(_cacheTimestampKey);
      final cachePath = prefs.getString('${_cacheKey}_path');

      // Check if URL matches and cache exists
      if (cachedUrl != videoUrl || cachePath == null) {
        return false;
      }

      // Check if cache file exists
      final cacheFile = File(cachePath);
      if (!await cacheFile.exists()) {
        print('🗑️ VideoCacheService: Cache file not found, clearing metadata');
        await clearCache();
        return false;
      }

      // Check cache age
      if (cacheTimestamp != null) {
        final cacheAge = DateTime.now().millisecondsSinceEpoch - cacheTimestamp;
        if (cacheAge > _maxCacheAge) {
          print('⏰ VideoCacheService: Cache expired, clearing');
          await clearCache();
          return false;
        }
      }

      print('✅ VideoCacheService: Video is cached and valid');
      return true;
    } catch (e) {
      print('❌ VideoCacheService: Error checking cache: $e');
      return false;
    }
  }

  /// **Get video URL for VideoPlayerController (cached or original)**
  Future<String> getVideoUrlForPlayer(
      String originalUrl, String videoId) async {
    try {
      // Try to get cached version first
      final cachedPath = await getCachedVideoPath(originalUrl);
      if (cachedPath != null) {
        print('🎬 VideoCacheService: Using cached video for instant playback');
        return cachedPath;
      }

      // Return original URL if not cached
      print('🌐 VideoCacheService: Using original URL');
      return originalUrl;
    } catch (e) {
      print('❌ VideoCacheService: Error getting video URL: $e');
      return originalUrl;
    }
  }

  /// **Pre-cache first video in background**
  Future<void> preCacheFirstVideo(String videoUrl, String videoId) async {
    try {
      print('🔄 VideoCacheService: Starting background pre-cache...');

      // Don't block the UI, cache in background
      Future.delayed(Duration.zero, () async {
        await cacheFirstVideo(videoUrl, videoId);
      });
    } catch (e) {
      print('❌ VideoCacheService: Error in pre-cache: $e');
    }
  }

  /// **Clear video cache**
  Future<void> clearCache() async {
    try {
      print('🧹 VideoCacheService: Clearing video cache...');

      final prefs = await SharedPreferences.getInstance();
      final cachePath = prefs.getString('${_cacheKey}_path');

      // Delete cache file
      if (cachePath != null) {
        final cacheFile = File(cachePath);
        if (await cacheFile.exists()) {
          await cacheFile.delete();
          print('🗑️ VideoCacheService: Deleted cache file');
        }
      }

      // Clear metadata
      await prefs.remove(_cacheKey);
      await prefs.remove(_cacheUrlKey);
      await prefs.remove(_cacheTimestampKey);
      await prefs.remove('${_cacheKey}_path');

      print('✅ VideoCacheService: Cache cleared successfully');
    } catch (e) {
      print('❌ VideoCacheService: Error clearing cache: $e');
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
      print('❌ VideoCacheService: Error getting cache directory: $e');
      return null;
    }
  }

  /// **Save cache metadata**
  Future<void> _saveCacheMetadata(
      String videoUrl, String videoId, String cachePath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheUrlKey, videoUrl);
      await prefs.setString('${_cacheKey}_path', cachePath);
      await prefs.setInt(
          _cacheTimestampKey, DateTime.now().millisecondsSinceEpoch);
      await prefs.setString(_cacheKey, videoId);
    } catch (e) {
      print('❌ VideoCacheService: Error saving cache metadata: $e');
    }
  }

  /// **Get cache info for debugging**
  Future<Map<String, dynamic>> getCacheInfo() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedUrl = prefs.getString(_cacheUrlKey);
      final cacheTimestamp = prefs.getInt(_cacheTimestampKey);
      final cachePath = prefs.getString('${_cacheKey}_path');

      int? cacheSize;
      if (cachePath != null) {
        final cacheFile = File(cachePath);
        if (await cacheFile.exists()) {
          cacheSize = await cacheFile.length();
        }
      }

      return {
        'cachedUrl': cachedUrl,
        'cacheTimestamp': cacheTimestamp,
        'cachePath': cachePath,
        'cacheSize': cacheSize,
        'cacheAge': cacheTimestamp != null
            ? DateTime.now().millisecondsSinceEpoch - cacheTimestamp
            : null,
        'isValid': await isVideoCached(cachedUrl ?? ''),
      };
    } catch (e) {
      print('❌ VideoCacheService: Error getting cache info: $e');
      return {};
    }
  }

  /// **Cleanup old cache files**
  Future<void> cleanupOldCache() async {
    try {
      print('🧹 VideoCacheService: Cleaning up old cache files...');

      final cacheDir = await _getCacheDirectory();
      if (cacheDir == null) return;

      final files = await cacheDir.list().toList();
      int deletedCount = 0;

      for (final file in files) {
        if (file is File) {
          final stat = await file.stat();
          final age = DateTime.now().millisecondsSinceEpoch -
              stat.modified.millisecondsSinceEpoch;

          if (age > _maxCacheAge) {
            await file.delete();
            deletedCount++;
          }
        }
      }

      print('✅ VideoCacheService: Cleaned up $deletedCount old cache files');
    } catch (e) {
      print('❌ VideoCacheService: Error cleaning up cache: $e');
    }
  }
}
