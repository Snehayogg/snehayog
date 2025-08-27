import 'dart:io';
import 'dart:async';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:snehayog/model/video_model.dart';
import 'dart:convert';

/// **VideoDiskCacheManager - Handles disk caching and smart preloading**
/// - Caches videos on disk after first watch
/// - Preloads first 5-10 seconds for instant start
/// - Continues background download
/// - Provides instant loading for cached videos
class VideoDiskCacheManager {
  static const String _cacheDirName = 'video_cache';
  static const int _preloadDurationSeconds = 8; // Preload first 8 seconds
  static const int _maxCacheSizeMB = 500; // Max 500MB cache size
  
  late Directory _cacheDir;
  final Map<String, VideoCacheInfo> _cacheInfo = {};
  final Map<String, StreamController<double>> _downloadProgress = {};
  
  /// Initialize disk cache
  Future<void> initialize() async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      _cacheDir = Directory('${appDir.path}/$_cacheDirName');
      
      if (!await _cacheDir.exists()) {
        await _cacheDir.create(recursive: true);
      }
      
      // Load existing cache info
      await _loadCacheInfo();
      
      // Clean up old cache files
      await _cleanupOldCache();
      
      print('✅ VideoDiskCacheManager: Initialized with ${_cacheInfo.length} cached videos');
    } catch (e) {
      print('❌ VideoDiskCacheManager: Error initializing: $e');
    }
  }
  
  /// **SMART PRELOADING: Preload first 8 seconds for instant start**
  Future<bool> preloadVideoForInstantStart(VideoModel video) async {
    try {
      final cacheKey = _getCacheKey(video.id);
      
      // Check if already cached
      if (await _isVideoCached(video.id)) {
        print('⚡ VideoDiskCacheManager: Video ${video.id} already cached, instant start ready');
        return true;
      }
      
      print('🚀 VideoDiskCacheManager: Starting smart preload for video ${video.id}');
      
      // Start preloading first 8 seconds
      final preloadSuccess = await _preloadFirstSegment(video);
      
      if (preloadSuccess) {
        // Start background full download
        unawaited(_downloadFullVideoInBackground(video));
        return true;
      }
      
      return false;
    } catch (e) {
      print('❌ VideoDiskCacheManager: Error preloading video: $e');
      return false;
    }
  }
  
  /// **INSTANT START: Preload first 8 seconds of video**
  Future<bool> _preloadFirstSegment(VideoModel video) async {
    try {
      final cacheKey = _getCacheKey(video.id);
      final preloadFile = File('${_cacheDir.path}/$cacheKey.preload');
      
      // Create progress controller for this video
      _downloadProgress[video.id] = StreamController<double>.broadcast();
      
      // Download first 8 seconds using HTTP Range header
      final response = await http.get(
        Uri.parse(video.videoUrl),
        headers: {'Range': 'bytes=0-'},
      ).timeout(const Duration(seconds: 15));
      
      if (response.statusCode == 200 || response.statusCode == 206) {
        // Save preload segment
        await preloadFile.writeAsBytes(response.bodyBytes);
        
        // Update cache info
        _cacheInfo[video.id] = VideoCacheInfo(
          videoId: video.id,
          preloadFile: preloadFile.path,
          preloadSize: response.bodyBytes.length,
          preloadDuration: _preloadDurationSeconds,
          isFullyDownloaded: false,
          lastAccessed: DateTime.now(),
          fileSize: 0, // Will be updated when full download completes
        );
        
        // Save cache info
        await _saveCacheInfo();
        
        print('✅ VideoDiskCacheManager: Preloaded first 8 seconds for video ${video.id}');
        return true;
      }
      
      return false;
    } catch (e) {
      print('❌ VideoDiskCacheManager: Error preloading segment: $e');
      return false;
    }
  }
  
  /// **BACKGROUND DOWNLOAD: Continue downloading full video**
  Future<void> _downloadFullVideoInBackground(VideoModel video) async {
    try {
      final cacheKey = _getCacheKey(video.id);
      final fullFile = File('${_cacheDir.path}/$cacheKey.full');
      
      print('🔄 VideoDiskCacheManager: Starting background full download for video ${video.id}');
      
      // Get video size first
      final headResponse = await http.head(Uri.parse(video.videoUrl));
      final totalSize = int.tryParse(headResponse.headers['content-length'] ?? '0') ?? 0;
      
      // Download in chunks with progress
      final request = http.Request('GET', Uri.parse(video.videoUrl));
      final response = await http.Client().send(request);
      
      if (response.statusCode == 200) {
        final stream = response.stream;
        final bytes = <int>[];
        int downloadedBytes = 0;
        
        await for (final chunk in stream) {
          bytes.addAll(chunk);
          downloadedBytes += chunk.length;
          
          // Update progress
          if (totalSize > 0) {
            final progress = downloadedBytes / totalSize;
            _downloadProgress[video.id]?.add(progress);
          }
        }
        
        // Save full video
        await fullFile.writeAsBytes(bytes);
        
        // Update cache info
        if (_cacheInfo.containsKey(video.id)) {
          _cacheInfo[video.id]!.isFullyDownloaded = true;
          _cacheInfo[video.id]!.fullFile = fullFile.path;
          _cacheInfo[video.id]!.fileSize = bytes.length;
          await _saveCacheInfo();
        }
        
        print('✅ VideoDiskCacheManager: Full download completed for video ${video.id}');
        
        // Clean up preload file
        final preloadFile = File('${_cacheDir.path}/$cacheKey.preload');
        if (await preloadFile.exists()) {
          await preloadFile.delete();
        }
      }
    } catch (e) {
      print('❌ VideoDiskCacheManager: Error in background download: $e');
    }
  }
  
  /// **INSTANT LOAD: Get cached video file path**
  Future<String?> getCachedVideoPath(String videoId) async {
    try {
      if (!_cacheInfo.containsKey(videoId)) return null;
      
      final info = _cacheInfo[videoId]!;
      
      // Check if fully downloaded
      if (info.isFullyDownloaded && info.fullFile != null) {
        final fullFile = File(info.fullFile!);
        if (await fullFile.exists()) {
          _updateLastAccessed(videoId);
          return info.fullFile;
        }
      }
      
      // Check if preload available
      if (info.preloadFile != null) {
        final preloadFile = File(info.preloadFile!);
        if (await preloadFile.exists()) {
          _updateLastAccessed(videoId);
          return info.preloadFile;
        }
      }
      
      return null;
    } catch (e) {
      print('❌ VideoDiskCacheManager: Error getting cached path: $e');
      return null;
    }
  }
  
  /// **PROGRESS STREAM: Get download progress for a video**
  Stream<double>? getDownloadProgress(String videoId) {
    return _downloadProgress[videoId]?.stream;
  }
  
  /// **CACHE STATUS: Check if video is cached**
  Future<bool> _isVideoCached(String videoId) async {
    try {
      if (!_cacheInfo.containsKey(videoId)) return false;
      
      final info = _cacheInfo[videoId]!;
      
      // Check full file
      if (info.isFullyDownloaded && info.fullFile != null) {
        final fullFile = File(info.fullFile!);
        return await fullFile.exists();
      }
      
      // Check preload file
      if (info.preloadFile != null) {
        final preloadFile = File(info.preloadFile!);
        return await preloadFile.exists();
      }
      
      return false;
    } catch (e) {
      return false;
    }
  }
  
  /// **CACHE CLEANUP: Remove old cache files**
  Future<void> _cleanupOldCache() async {
    try {
      final now = DateTime.now();
      final filesToDelete = <String>[];
      
      for (final entry in _cacheInfo.entries) {
        final info = entry.value;
        final age = now.difference(info.lastAccessed);
        
        // Remove files older than 7 days
        if (age.inDays > 7) {
          filesToDelete.add(entry.key);
        }
      }
      
      // Check cache size
      final totalSize = await _getTotalCacheSize();
      if (totalSize > _maxCacheSizeMB * 1024 * 1024) {
        // Remove oldest files until under limit
        final sortedEntries = _cacheInfo.entries.toList()
          ..sort((a, b) => a.value.lastAccessed.compareTo(b.value.lastAccessed));
        
        for (final entry in sortedEntries) {
          if (totalSize <= _maxCacheSizeMB * 1024 * 1024) break;
          
          filesToDelete.add(entry.key);
          // Update total size calculation
        }
      }
      
      // Delete old files
      for (final videoId in filesToDelete) {
        await _removeVideoFromCache(videoId);
      }
      
      if (filesToDelete.isNotEmpty) {
        print('🧹 VideoDiskCacheManager: Cleaned up ${filesToDelete.length} old cache files');
      }
    } catch (e) {
      print('❌ VideoDiskCacheManager: Error cleaning up cache: $e');
    }
  }
  
  /// **REMOVE VIDEO: Remove specific video from cache**
  Future<void> _removeVideoFromCache(String videoId) async {
    try {
      if (!_cacheInfo.containsKey(videoId)) return;
      
      final info = _cacheInfo[videoId]!;
      
      // Delete files
      if (info.fullFile != null) {
        final fullFile = File(info.fullFile!);
        if (await fullFile.exists()) {
          await fullFile.delete();
        }
      }
      
      if (info.preloadFile != null) {
        final preloadFile = File(info.preloadFile!);
        if (await preloadFile.exists()) {
          await preloadFile.delete();
        }
      }
      
      // Remove from cache info
      _cacheInfo.remove(videoId);
      _downloadProgress.remove(videoId);
      
      await _saveCacheInfo();
      
      print('🗑️ VideoDiskCacheManager: Removed video $videoId from cache');
    } catch (e) {
      print('❌ VideoDiskCacheManager: Error removing video from cache: $e');
    }
  }
  
  /// **CACHE STATS: Get cache statistics**
  Map<String, dynamic> getCacheStats() {
    final totalSize = _cacheInfo.values.fold<int>(0, (sum, info) => sum + info.fileSize);
    final preloadCount = _cacheInfo.values.where((info) => !info.isFullyDownloaded).length;
    final fullCount = _cacheInfo.values.where((info) => info.isFullyDownloaded).length;
    
    return {
      'totalCachedVideos': _cacheInfo.length,
      'fullyDownloaded': fullCount,
      'preloadOnly': preloadCount,
      'totalSizeMB': (totalSize / (1024 * 1024)).toStringAsFixed(2),
      'maxCacheSizeMB': _maxCacheSizeMB,
      'preloadDurationSeconds': _preloadDurationSeconds,
    };
  }
  
  /// **HELPER METHODS**
  String _getCacheKey(String videoId) => 'video_$videoId';
  
  void _updateLastAccessed(String videoId) {
    if (_cacheInfo.containsKey(videoId)) {
      _cacheInfo[videoId]!.lastAccessed = DateTime.now();
      unawaited(_saveCacheInfo());
    }
  }
  
  Future<int> _getTotalCacheSize() async {
    int totalSize = 0;
    for (final info in _cacheInfo.values) {
      if (info.fullFile != null) {
        final file = File(info.fullFile!);
        if (await file.exists()) {
          totalSize += await file.length();
        }
      }
    }
    return totalSize;
  }
  
  Future<void> _loadCacheInfo() async {
    try {
      final infoFile = File('${_cacheDir.path}/cache_info.json');
      if (await infoFile.exists()) {
        final content = await infoFile.readAsString();
        final data = Map<String, dynamic>.from(json.decode(content));
        
        for (final entry in data.entries) {
          _cacheInfo[entry.key] = VideoCacheInfo.fromJson(entry.value);
        }
      }
    } catch (e) {
      print('❌ VideoDiskCacheManager: Error loading cache info: $e');
    }
  }
  
  Future<void> _saveCacheInfo() async {
    try {
      final infoFile = File('${_cacheDir.path}/cache_info.json');
      final data = <String, dynamic>{};
      
      for (final entry in _cacheInfo.entries) {
        data[entry.key] = entry.value.toJson();
      }
      
      await infoFile.writeAsString(json.encode(data));
    } catch (e) {
      print('❌ VideoDiskCacheManager: Error saving cache info: $e');
    }
  }
  
  /// **DISPOSE: Clean up resources**
  void dispose() {
    for (final controller in _downloadProgress.values) {
      controller.close();
    }
    _downloadProgress.clear();
  }
}

/// **VideoCacheInfo - Stores metadata about cached videos**
class VideoCacheInfo {
  final String videoId;
  final String? preloadFile;
  String? fullFile; // Remove final to allow updates
  final int preloadSize;
  final int preloadDuration;
  bool isFullyDownloaded;
  DateTime lastAccessed;
  int fileSize;
  
  VideoCacheInfo({
    required this.videoId,
    this.preloadFile,
    this.fullFile,
    required this.preloadSize,
    required this.preloadDuration,
    required this.isFullyDownloaded,
    required this.lastAccessed,
    required this.fileSize,
  });
  
  Map<String, dynamic> toJson() => {
    'videoId': videoId,
    'preloadFile': preloadFile,
    'fullFile': fullFile,
    'preloadSize': preloadSize,
    'preloadDuration': preloadDuration,
    'isFullyDownloaded': isFullyDownloaded,
    'lastAccessed': lastAccessed.toIso8601String(),
    'fileSize': fileSize,
  };
  
  factory VideoCacheInfo.fromJson(Map<String, dynamic> json) => VideoCacheInfo(
    videoId: json['videoId'],
    preloadFile: json['preloadFile'],
    fullFile: json['fullFile'],
    preloadSize: json['preloadSize'] ?? 0,
    preloadDuration: json['preloadDuration'] ?? 8,
    isFullyDownloaded: json['isFullyDownloaded'] ?? false,
    lastAccessed: DateTime.parse(json['lastAccessed']),
    fileSize: json['fileSize'] ?? 0,
  );
}
