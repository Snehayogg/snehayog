import 'dart:async';
import 'dart:convert';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as p;

/// Lightweight HLS warm-up to reduce first-play latency.
/// - Caches the manifest (.m3u8) persistently
/// - Prefetches first few TS/MP4 segment chunks
class HlsWarmupService {
  static final HlsWarmupService _instance = HlsWarmupService._internal();
  factory HlsWarmupService() => _instance;
  HlsWarmupService._internal();

  // Persistent cache manager (kept small to avoid storage bloat)
  static final CacheManager _cache = CacheManager(
    Config(
      'hls_warmup_cache',
      stalePeriod: const Duration(hours: 6),
      maxNrOfCacheObjects: 200,
      repo: JsonCacheInfoRepository(databaseName: 'hls_warmup_cache_db'),
      fileService: HttpFileService(),
    ),
  );

  /// Public API: Warm up a playlist URL
  Future<void> warmUp(String manifestUrl,
      {int segmentPrefetchCount = 5}) async {
    try {
      if (!manifestUrl.toLowerCase().contains('.m3u8')) {
        print('⚠️ HlsWarmupService: Not an HLS URL, skipping: $manifestUrl');
        return;
      }

      print('🔥 HlsWarmupService: Starting HLS warm-up for $manifestUrl');
      final manifestFile = await _safeDownload(manifestUrl);
      if (manifestFile == null) {
        print('❌ HlsWarmupService: Failed to download manifest');
        return;
      }

      print('✅ HlsWarmupService: Manifest cached successfully');
      final manifestContent = await manifestFile.file.readAsString();
      final segmentUrls = _extractSegmentUrls(manifestUrl, manifestContent);
      print(
          '📊 HlsWarmupService: Found ${segmentUrls.length} segments, prefetching $segmentPrefetchCount');

      // Prefetch first few segments to warm CDN + local cache
      final futures = <Future>[];
      for (final url in segmentUrls.take(segmentPrefetchCount)) {
        futures.add(_safeDownload(url));
      }
      await Future.wait(futures);
      print('✅ HlsWarmupService: HLS warm-up completed successfully');
    } catch (e) {
      print('❌ HlsWarmupService: HLS warm-up failed: $e');
      // Best-effort warm-up; ignore errors
    }
  }

  Future<FileInfo?> _safeDownload(String url) async {
    try {
      return await _cache.downloadFile(
        url,
        key: url,
        force: false,
      );
    } catch (_) {
      return null;
    }
  }

  List<String> _extractSegmentUrls(String manifestUrl, String manifest) {
    final lines = const LineSplitter().convert(manifest);
    final base = _baseUrl(manifestUrl);
    final urls = <String>[];
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      if (_isAbsoluteUrl(trimmed)) {
        urls.add(trimmed);
      } else {
        urls.add(p.normalize('$base/$trimmed'));
      }
    }
    return urls;
  }

  bool _isAbsoluteUrl(String s) {
    return s.startsWith('http://') || s.startsWith('https://');
  }

  String _baseUrl(String url) {
    final idx = url.lastIndexOf('/');
    return idx > 0 ? url.substring(0, idx) : url;
  }
}
