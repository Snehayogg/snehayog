import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'network_monitor.dart';

class ProgressiveVideoCacheManager {
  static final ProgressiveVideoCacheManager _instance =
      ProgressiveVideoCacheManager._internal();
  factory ProgressiveVideoCacheManager() => _instance;
  ProgressiveVideoCacheManager._internal();

  final NetworkMonitor _networkMonitor = NetworkMonitor();
  final Map<String, StreamController<Uint8List>> _activeStreams = {};
  final Map<String, int> _bytesReceived = {};
  final Map<String, Timer?> _qualityAdjustmentTimers = {};
  final Map<String, File> _cachedFiles = {};

  // Cache directory
  Directory? _cacheDir;

  // Initialize cache directory
  Future<void> initialize() async {
    _cacheDir = await getTemporaryDirectory();
    final videoCacheDir = Directory('${_cacheDir!.path}/video_cache');
    if (!await videoCacheDir.exists()) {
      await videoCacheDir.create(recursive: true);
    }
  }

  // Get progressive stream for video
  Stream<Uint8List> getProgressiveStream(String videoUrl) {
    if (_activeStreams.containsKey(videoUrl)) {
      return _activeStreams[videoUrl]!.stream;
    }

    final controller = StreamController<Uint8List>();
    _activeStreams[videoUrl] = controller;
    _bytesReceived[videoUrl] = 0;

    // Start adaptive streaming
    _startAdaptiveStreaming(videoUrl, controller);

    return controller.stream;
  }

  // Start adaptive streaming based on network quality
  Future<void> _startAdaptiveStreaming(
      String videoUrl, StreamController<Uint8List> controller) async {
    try {
      final chunkSize = _networkMonitor.getChunkSize();
      final initialBufferSize = _networkMonitor.getInitialBufferSize();

      print('🚀 Starting progressive streaming for: $videoUrl');
      print('📊 Network Quality: ${_networkMonitor.currentQuality}');
      print('📦 Chunk Size: ${chunkSize ~/ 1024}KB');
      print('💾 Initial Buffer: ${initialBufferSize ~/ 1024}KB');

      // Check if file is already cached
      final cachedFile = await _getCachedFile(videoUrl);
      if (cachedFile != null && await cachedFile.exists()) {
        print('✅ Using cached file: ${cachedFile.path}');
        await _streamFromFile(cachedFile, controller, chunkSize);
        return;
      }

      // Stream from network with adaptive chunking
      await _streamWithAdaptiveChunking(
          videoUrl, controller, chunkSize, initialBufferSize);
    } catch (e) {
      print('❌ Error in progressive streaming: $e');
      controller.addError(e);
    }
  }

  // Stream with adaptive chunking based on network conditions
  Future<void> _streamWithAdaptiveChunking(
    String videoUrl,
    StreamController<Uint8List> controller,
    int initialChunkSize,
    int initialBufferSize,
  ) async {
    final client = HttpClient();
    final request = await client.getUrl(Uri.parse(videoUrl));

    // Add range request header for chunked download
    request.headers.add('Range', 'bytes=0-');

    final response = await request.close();

    if (response.statusCode != 206 && response.statusCode != 200) {
      throw Exception('Failed to start streaming: ${response.statusCode}');
    }

    final contentLength = response.contentLength;
    final totalBytes = contentLength > 0 ? contentLength : 0;

    print('📹 Video size: ${totalBytes ~/ (1024 * 1024)}MB');

    int bytesRead = 0;
    int currentChunkSize = initialChunkSize;
    final buffer = BytesBuilder();

    // Start quality monitoring
    _monitorQualityAdjustment(
        videoUrl, () => _adjustChunkSize(videoUrl, currentChunkSize));

    await for (final chunk in response) {
      buffer.add(chunk);
      bytesRead += chunk.length;
      _bytesReceived[videoUrl] = bytesRead;

      // Send data when buffer reaches chunk size
      if (buffer.length >= currentChunkSize) {
        controller.add(Uint8List.fromList(buffer.takeBytes()));

        // Adjust chunk size based on current network quality
        currentChunkSize = _networkMonitor.getChunkSize();

        // Cache the data
        await _cacheChunk(videoUrl, buffer.toBytes());
      }

      // Check if we have enough initial buffer to start playback
      if (bytesRead >= initialBufferSize && !controller.isClosed) {
        print('🎬 Initial buffer ready, starting playback');
        // Continue streaming in background
      }
    }

    // Send remaining data
    if (buffer.isNotEmpty) {
      controller.add(Uint8List.fromList(buffer.takeBytes()));
    }

    controller.close();
    client.close();

    print('✅ Progressive streaming completed for: $videoUrl');
  }

  // Stream from cached file
  Future<void> _streamFromFile(
      File file, StreamController<Uint8List> controller, int chunkSize) async {
    final randomAccessFile = await file.open();
    final buffer = BytesBuilder();

    try {
      while (true) {
        final chunk = await randomAccessFile.read(chunkSize);
        if (chunk.isEmpty) break;

        buffer.add(chunk);
        if (buffer.length >= chunkSize) {
          controller.add(Uint8List.fromList(buffer.takeBytes()));
        }
      }

      // Send remaining data
      if (buffer.isNotEmpty) {
        controller.add(Uint8List.fromList(buffer.takeBytes()));
      }

      controller.close();
    } finally {
      await randomAccessFile.close();
    }
  }

  // Monitor and adjust quality
  void _monitorQualityAdjustment(String videoUrl, VoidCallback adjustCallback) {
    _qualityAdjustmentTimers[videoUrl] = Timer.periodic(
      const Duration(seconds: 5),
      (timer) {
        if (_activeStreams.containsKey(videoUrl)) {
          adjustCallback();
        } else {
          timer.cancel();
        }
      },
    );
  }

  // Adjust chunk size based on network quality
  void _adjustChunkSize(String videoUrl, int currentChunkSize) {
    final newChunkSize = _networkMonitor.getChunkSize();
    if (newChunkSize != currentChunkSize) {
      print(
          '🔄 Adjusting chunk size: ${currentChunkSize ~/ 1024}KB → ${newChunkSize ~/ 1024}KB');
    }
  }

  // Cache chunk data
  Future<void> _cacheChunk(String videoUrl, Uint8List data) async {
    try {
      final file = await _getOrCreateCacheFile(videoUrl);
      await file.writeAsBytes(data, mode: FileMode.append);
    } catch (e) {
      print('⚠️ Failed to cache chunk: $e');
    }
  }

  // Get cached file if exists
  Future<File?> _getCachedFile(String videoUrl) async {
    final fileName = _getFileNameFromUrl(videoUrl);
    final file = File('${_cacheDir!.path}/video_cache/$fileName');

    if (await file.exists()) {
      _cachedFiles[videoUrl] = file;
      return file;
    }

    return null;
  }

  // Get or create cache file
  Future<File> _getOrCreateCacheFile(String videoUrl) async {
    if (_cachedFiles.containsKey(videoUrl)) {
      return _cachedFiles[videoUrl]!;
    }

    final fileName = _getFileNameFromUrl(videoUrl);
    final file = File('${_cacheDir!.path}/video_cache/$fileName');
    _cachedFiles[videoUrl] = file;

    return file;
  }

  // Get file name from URL
  String _getFileNameFromUrl(String url) {
    final uri = Uri.parse(url);
    final segments = uri.pathSegments;
    final fileName = segments.isNotEmpty
        ? segments.last
        : 'video_${DateTime.now().millisecondsSinceEpoch}';
    return fileName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  // Stop streaming for specific video
  void stopStreaming(String videoUrl) {
    _activeStreams[videoUrl]?.close();
    _activeStreams.remove(videoUrl);
    _bytesReceived.remove(videoUrl);
    _qualityAdjustmentTimers[videoUrl]?.cancel();
    _qualityAdjustmentTimers.remove(videoUrl);
  }

  // Get streaming progress
  double getStreamingProgress(String videoUrl) {
    final bytesReceived = _bytesReceived[videoUrl] ?? 0;
    // This is a rough estimation since we don't know total size during streaming
    return bytesReceived > 0 ? 1.0 : 0.0;
  }

  // Clear all streams and cache
  Future<void> clearAll() async {
    // Close all active streams
    for (final controller in _activeStreams.values) {
      controller.close();
    }
    _activeStreams.clear();
    _bytesReceived.clear();

    // Cancel all timers
    for (final timer in _qualityAdjustmentTimers.values) {
      timer?.cancel();
    }
    _qualityAdjustmentTimers.clear();

    // Clear cached files
    _cachedFiles.clear();

    // Clear cache directory
    if (_cacheDir != null) {
      final videoCacheDir = Directory('${_cacheDir!.path}/video_cache');
      if (await videoCacheDir.exists()) {
        await videoCacheDir.delete(recursive: true);
        await videoCacheDir.create(recursive: true);
      }
    }
  }

  // Dispose
  void dispose() {
    clearAll();
  }
}
