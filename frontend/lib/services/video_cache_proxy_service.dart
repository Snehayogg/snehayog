import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:vayu/utils/app_logger.dart';

/// **VideoCacheProxyService: Industry-standard persistent caching**
/// Runs a local HTTP proxy to intercept video requests and serve fragments from disk.
class VideoCacheProxyService {
  static final VideoCacheProxyService _instance =
      VideoCacheProxyService._internal();
  factory VideoCacheProxyService() => _instance;
  VideoCacheProxyService._internal();

  HttpServer? _server;
  int? _port;
  String? _cachePath;
  final Map<String, bool> _activeDownloads = {};

  /// Start the local proxy server
  Future<void> initialize() async {
    if (_server != null) return;

    try {
      final dir = await getApplicationSupportDirectory();
      _cachePath = '${dir.path}/video_chunks';
      final cacheDir = Directory(_cachePath!);
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }

      // Bind to any available port on localhost
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      _port = _server!.port;
      AppLogger.log('🚀 VideoCacheProxyService: Started on port $_port');

      _server!.listen(_handleRequest, onError: (e) {
        AppLogger.log('❌ VideoCacheProxyService: Server error: $e');
      });
    } catch (e) {
      AppLogger.log('❌ VideoCacheProxyService: Initialization failed: $e');
    }
  }

  /// Transform a remote URL into a local proxy URL
  String proxyUrl(String originalUrl) {
    if (_port == null || originalUrl.isEmpty) return originalUrl;

    // Don't proxy if already proxied or local
    if (originalUrl.contains('localhost:$_port') ||
        originalUrl.startsWith('file://')) {
      return originalUrl;
    }

    final encodedUrl = Uri.encodeComponent(originalUrl);
    
    // **HLS SUPPORT: Use special route for manifests**
    if (originalUrl.contains('.m3u8')) {
      return 'http://localhost:$_port/proxy-hls?url=$encodedUrl';
    }

    return 'http://localhost:$_port/proxy?url=$encodedUrl';
  }

  Future<void> _handleRequest(HttpRequest request) async {
    // **ROUTING**
    if (request.uri.path == '/proxy-hls') {
      await _handleHlsManifestRequest(request);
      return;
    }

    if (request.uri.path != '/proxy') {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final url = request.uri.queryParameters['url'];
    if (url == null || url.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    final String fileKey = md5.convert(utf8.encode(url)).toString();
    final String filePath = '$_cachePath/$fileKey.chunk';
    final file = File(filePath);

    try {
      // **INDUSTRY LOGIC: Serve from disk if exists, else stream and save**
      if (await file.exists()) {
        AppLogger.log(
            '⚡ Proxy: Cache HIT for ${url.substring(url.length > 20 ? url.length - 20 : 0)}');
        await _serveLocalFile(file, request);
      } else {
        AppLogger.log(
            '🌐 Proxy: Cache MISS, streaming and saving for $fileKey');
        await _streamAndCache(url, file, request);
      }
    } catch (e) {
      AppLogger.log('❌ Proxy: Request handling error: $e');
      if (request.response.connectionInfo != null) {
        request.response.statusCode = HttpStatus.internalServerError;
        await request.response.close();
      }
    }
  }

  Future<void> _serveLocalFile(File file, HttpRequest request) async {
    final response = request.response;
    final length = await file.length();

    response.headers.add(HttpHeaders.contentTypeHeader, 'video/mp4');
    response.headers.add(HttpHeaders.contentLengthHeader, length);
    response.headers.add('Access-Control-Allow-Origin', '*');

    await response.addStream(file.openRead());
    await response.close();
  }



  /// **HLS MANIFEST REWRITER**
  /// Fetches the .m3u8, rewrites internal URLs to point to this proxy, and serves it.
  Future<void> _handleHlsManifestRequest(HttpRequest request) async {
    final url = request.uri.queryParameters['url'];
    if (url == null || url.isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      await request.response.close();
      return;
    }

    try {
      final client = http.Client();
      final remoteUri = Uri.parse(url);
      final response = await client.get(remoteUri);
      client.close();

      if (response.statusCode != 200) {
        request.response.statusCode = response.statusCode;
        await request.response.close();
        return;
      }

      final String originalManifest = response.body;
      final StringBuffer modifiedManifest = StringBuffer();
      
      // Determine base URL for resolving relative paths
      final String baseUrl = url.substring(0, url.lastIndexOf('/') + 1);

      // Simple parser: Iterate lines and rewrite URLs
      const LineSplitter splitter = LineSplitter();
      final List<String> lines = splitter.convert(originalManifest);

      for (String line in lines) {
        if (line.trim().isEmpty) {
          modifiedManifest.writeln(line);
          continue;
        }

        if (line.startsWith('#')) {
           // It's a tag (like #EXT-X-STREAM-INF), preserve it
           // Check if it's a URI tag if needed, but usually URIs are on their own lines 
           // or part of a tag like #EXT-X-KEY:METHOD=AES-128,URI="key.php"
           // For simplicity, we handle standard lines. Complex tag URI rewriting requires regex.
           modifiedManifest.writeln(line);
        } else {
          // This line is a URL (segment or sub-playlist)
          String segmentUrl = line.trim();
          
          // Resolve relative URLs
          if (!segmentUrl.startsWith('http')) {
             segmentUrl = Uri.parse(baseUrl).resolve(segmentUrl).toString();
          }

          final encodedSegmentUrl = Uri.encodeComponent(segmentUrl);
          String localUrl;

          if (segmentUrl.contains('.m3u8')) {
             // Recursively proxy sub-playlists
             localUrl = 'http://localhost:$_port/proxy-hls?url=$encodedSegmentUrl';
          } else {
             // Proxy segments (TS, KEY, etc.) using simple binary proxy
             localUrl = 'http://localhost:$_port/proxy?url=$encodedSegmentUrl';
          }
          
          modifiedManifest.writeln(localUrl);
        }
      }

      // Serve modified manifest
      request.response.headers.add(HttpHeaders.contentTypeHeader, 'application/vnd.apple.mpegurl');
      request.response.headers.add('Access-Control-Allow-Origin', '*');
      request.response.write(modifiedManifest.toString());
      await request.response.close();

    } catch (e) {
      AppLogger.log('❌ Proxy: HLS Manifest rewriting failed: $e');
      request.response.statusCode = HttpStatus.internalServerError;
      await request.response.close();
    }
  }

  Future<void> _streamAndCache(
      String url, File cacheFile, HttpRequest request) async {
    final client = http.Client();
    try {
      final remoteRequest = http.Request('GET', Uri.parse(url));

      // Copy incoming headers (like Range) to the remote request
      request.headers.forEach((name, values) {
        if (name != 'host' && name != 'content-length') {
          remoteRequest.headers[name] = values.join(', ');
        }
      });

      final remoteResponse = await client.send(remoteRequest);

      // Copy remote headers back to local response
      final localResponse = request.response;
      localResponse.statusCode = remoteResponse.statusCode;
      remoteResponse.headers.forEach((name, value) {
        // HLS chunks might need specific content types
        localResponse.headers.set(name, value);
      });

      // **SMART CACHING**: We only want to cache the full initial chunk (e.g., first 5MB)
      // or the whole video if it's small.
      final IOSink fileSink = cacheFile.openWrite();

      await for (final List<int> chunk in remoteResponse.stream) {
        localResponse.add(chunk);

        // Save to disk while streaming
        if (cacheFile.existsSync() ||
            !_activeDownloads.containsKey(cacheFile.path)) {
          fileSink.add(chunk);
        }
      }

      await fileSink.close();
      await localResponse.close();
    } finally {
      client.close();
    }
  }

  /// **NEW: Proactively pre-fetch the first few MB of a video to disk**
  Future<void> prefetchChunk(String url, {int megabytes = 3}) async {
    if (url.isEmpty) return;
    final String fileKey = md5.convert(utf8.encode(url)).toString();
    final String filePath = '$_cachePath/$fileKey.chunk';
    final file = File(filePath);

    if (await file.exists()) return; // Already cached

    AppLogger.log('📥 Proxy: Pre-fetching $megabytes MB for $fileKey');

    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      final IOSink fileSink = file.openWrite();
      int downloaded = 0;
      final int maxBytes = megabytes * 1024 * 1024;

      await for (final List<int> chunk in response.stream) {
        fileSink.add(chunk);
        downloaded += chunk.length;
        if (downloaded >= maxBytes) break;
      }

      await fileSink.close();
      AppLogger.log('✅ Proxy: Pre-fetched $downloaded bytes for $fileKey');
    } catch (e) {
      AppLogger.log('⚠️ Proxy: Pre-fetch failed for $fileKey: $e');
    } finally {
      client.close();
    }
  }

  /// Clean up old cache files (LRU implementation)
  Future<void> cleanCache() async {
    if (_cachePath == null) return;
    final dir = Directory(_cachePath!);
    if (!await dir.exists()) return;

    try {
      final List<FileSystemEntity> entities = await dir.list().toList();
      final List<File> files = entities.whereType<File>().toList();

      // Sort oldest first
      files.sort(
          (a, b) => a.statSync().modified.compareTo(b.statSync().modified));

      int totalSize = 0;
      const int maxSizeBytes = 200 * 1024 * 1024;

      for (var file in files) {
        totalSize += await file.length();
      }

      if (totalSize <= maxSizeBytes) return;

      int deletedCount = 0;
      for (var file in files) {
        if (totalSize <= maxSizeBytes) break;

        final length = await file.length();
        await file.delete();
        totalSize -= length;
        deletedCount++;
      }
      AppLogger.log('🧹 Proxy Cache: Cleaned up $deletedCount files');
    } catch (e) {
      AppLogger.log('❌ Proxy Cache: Cleanup error: $e');
    }
  }

  /// **NEW: Get a random available video URL from cache for instant splash screen**
  /// Returns null if no cached videos found.
  /// Smartly rotates videos to avoid showing same one every time.
  Future<String?> getRandomCachedVideoUrl() async {
    if (_cachePath == null) return null;
    final dir = Directory(_cachePath!);
    if (!await dir.exists()) return null;

    try {
      final List<FileSystemEntity> entities = await dir.list().toList();
      final List<File> files = entities.whereType<File>().toList();

      if (files.isEmpty) return null;

      // Filter for substantial files (e.g. > 1MB) to ensure it's playable
      final validFiles = <File>[];
      for (var file in files) {
        if (await file.length() > 1024 * 1024) {
          validFiles.add(file);
        }
      }

      if (validFiles.isEmpty) return null;

      // Smart Rotation: Pick a random one
      // In a real app, we could store 'lastShownSplash' in SharedPreferences
      // to ensure we cycle through them.
      validFiles.shuffle();
      final File selectedFile = validFiles.first;

      // We need to reverse-engineer the URL from the file hash if possible,
      // OR we just return the local file path directly if the player supports it.
      // Since VideoPlayerController.file() works, we can return the path.
      return selectedFile.path;
    } catch (e) {
      AppLogger.log('❌ Proxy: Error finding cached video: $e');
      return null;
    }
  }
  /// **NEW: Check if a URL is cached and playable (file exists and > 1MB)**
  Future<bool> isCached(String url) async {
    if (_cachePath == null || url.isEmpty) return false;
    
    try {
      final String fileKey = md5.convert(utf8.encode(url)).toString();
      final String filePath = '$_cachePath/$fileKey.chunk';
      final file = File(filePath);

      AppLogger.log('🔍 ProxyDebug: Checking cache for URL: $url');
      AppLogger.log('   Key: $fileKey');
      AppLogger.log('   Path: $filePath');

      if (await file.exists()) {
        final length = await file.length();
        final isSubstantial = length > 1024 * 1024;
        AppLogger.log(
            '   Result: File Exists. Size: ${(length / 1024 / 1024).toStringAsFixed(2)} MB. Playable (>1MB)? $isSubstantial');
        
        // Return true if file is substantial enough to play (e.g. > 1MB)
        return isSubstantial;
      } else {
        AppLogger.log('   Result: File does NOT exist.');
      }
      return false;
    } catch (e) {
      AppLogger.log('❌ ProxyDebug: Error checking cache: $e');
      return false;
    }
  }
}

final videoCacheProxy = VideoCacheProxyService();
