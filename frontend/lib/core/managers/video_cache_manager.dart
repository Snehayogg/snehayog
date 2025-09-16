import 'dart:io';
import 'dart:async';
import 'dart:collection';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'network_monitor.dart';
import 'package:snehayog/services/signed_url_service.dart';

class VideoCacheManager {
  static final VideoCacheManager _instance = VideoCacheManager._internal();
  factory VideoCacheManager() => _instance;
  VideoCacheManager._internal();

  // **PROGRESSIVE STREAMING**: Stream controllers for instant playback
  final Map<String, StreamController<List<int>>> _streamControllers = {};
  final Map<String, bool> _isStreaming = {};
  final Map<String, int> _bytesReceived = {};
  final Map<String, Timer?> _qualityTimers = {};
  // Short-lived retention for quick scroll-back reuse
  final Map<String, Timer?> _retentionTimers = {};
  static const Duration _retentionDuration = Duration(seconds: 8);

  // **NETWORK MONITORING**
  Timer? _speedTestTimer;
  double _currentSpeed = 0.0; // KB/s
  NetworkQuality _currentQuality = NetworkQuality.high;
  bool _isSlowNetwork = false;

  // **QUALITY THRESHOLDS** (like YouTube)
  static const double HIGH_SPEED_THRESHOLD = 1000.0; // KB/s
  static const double MEDIUM_SPEED_THRESHOLD = 500.0; // KB/s
  static const double LOW_SPEED_THRESHOLD = 100.0; // KB/s

  // **ADAPTIVE CHUNK SIZES** based on network quality
  static const Map<NetworkQuality, int> CHUNK_SIZES = {
    NetworkQuality.high: 128 * 1024, // 128KB chunks
    NetworkQuality.medium: 64 * 1024, // 64KB chunks
    NetworkQuality.low: 32 * 1024, // 32KB chunks
    NetworkQuality.veryLow: 16 * 1024, // 16KB chunks
  };

  // **INITIAL BUFFER SIZES** based on network quality
  static const Map<NetworkQuality, int> INITIAL_BUFFER_SIZES = {
    NetworkQuality.high: 512 * 1024, // 512KB initial buffer
    NetworkQuality.medium: 256 * 1024, // 256KB initial buffer
    NetworkQuality.low: 128 * 1024, // 128KB initial buffer
    NetworkQuality.veryLow: 64 * 1024, // 64KB initial buffer
  };

  // **LEGACY CACHE** (keeping for compatibility)
  final Map<String, File> _memoryCache = {};
  final Queue<String> _order = Queue();
  final int maxMemoryItems = 5;
  late Directory _cacheDir;

  /// **INITIALIZE**: Start network monitoring and cache directory
  Future<void> init() async {
    // **NETWORK MONITORING**: Start speed testing
    _startNetworkMonitoring();

    // **LEGACY CACHE**: Initialize disk cache
    _cacheDir = await getTemporaryDirectory();
    final dir = Directory('${_cacheDir.path}/video_cache');
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    _cacheDir = dir;
  }

  /// **NETWORK MONITORING**: Start monitoring network speed
  void _startNetworkMonitoring() {
    _speedTestTimer?.cancel();
    _speedTestTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _testNetworkSpeed();
    });
  }

  /// **SPEED TEST**: Measure current network speed
  Future<void> _testNetworkSpeed() async {
    try {
      final stopwatch = Stopwatch()..start();

      // **SPEED TEST**: Download small chunk to measure speed
      final client = HttpClient();
      final request = await client.getUrl(
        Uri.parse('https://httpbin.org/bytes/1024'),
      ); // 1KB test
      final response = await request.close();

      int bytesReceived = 0;
      await for (final chunk in response) {
        bytesReceived += chunk.length;
      }

      stopwatch.stop();
      final duration = stopwatch.elapsedMilliseconds / 1000.0; // seconds
      _currentSpeed = (bytesReceived / 1024) / duration; // KB/s

      // **UPDATE QUALITY**: Adjust quality based on speed
      _updateNetworkQuality();

      print(
        '🌐 VideoCacheManager: Speed: ${_currentSpeed.toStringAsFixed(1)} KB/s, Quality: $_currentQuality',
      );
    } catch (e) {
      print('❌ VideoCacheManager: Speed test failed: $e');
      _currentQuality = NetworkQuality.veryLow;
      _isSlowNetwork = true;
    }
  }

  /// **UPDATE QUALITY**: Adjust video quality based on network speed
  void _updateNetworkQuality() {
    if (_currentSpeed >= HIGH_SPEED_THRESHOLD) {
      _currentQuality = NetworkQuality.high;
      _isSlowNetwork = false;
    } else if (_currentSpeed >= MEDIUM_SPEED_THRESHOLD) {
      _currentQuality = NetworkQuality.medium;
      _isSlowNetwork = false;
    } else if (_currentSpeed >= LOW_SPEED_THRESHOLD) {
      _currentQuality = NetworkQuality.low;
      _isSlowNetwork = true;
    } else {
      _currentQuality = NetworkQuality.veryLow;
      _isSlowNetwork = true;
    }
  }

  /// **PROGRESSIVE STREAMING**: Start adaptive streaming (YouTube/Reels style)
  Future<Stream<List<int>>> getProgressiveStream(String url) async {
    if (_streamControllers.containsKey(url)) {
      final existing = _streamControllers[url]!;
      // If we still have a live controller, reuse it
      if (!existing.isClosed) {
        // Cancel any pending teardown since we are reusing
        _retentionTimers[url]?.cancel();
        _retentionTimers.remove(url);
        // Ensure streaming flag is on
        _isStreaming[url] = true;
        return existing.stream;
      }
      // If closed, drop it so we can recreate
      _streamControllers.remove(url);
    }

    final controller = StreamController<List<int>>();
    _streamControllers[url] = controller;
    _isStreaming[url] = true;
    _bytesReceived[url] = 0;

    // **SIGNED URL**: Always obtain a backend-signed HLS URL first
    String finalUrl = url;
    try {
      if (url.contains('.m3u8')) {
        print('🔍 VideoCacheManager: Original URL: $url');
        final signedService = SignedUrlService();
        // Try best quality chain with short timeout at service level
        final signed = await signedService.getBestSignedUrl(url);
        if (signed != null && signed.isNotEmpty) {
          finalUrl = signed;
          print('✅ VideoCacheManager: Using signed HLS URL for streaming');
          print('🔗 VideoCacheManager: Signed URL: $finalUrl');
        } else {
          print('⚠️ VideoCacheManager: Signed URL unavailable, using original');
          print('🔗 VideoCacheManager: Original URL: $finalUrl');
        }
      }
    } catch (e) {
      print('❌ VideoCacheManager: Signed URL fetch failed: $e');
      print('🔗 VideoCacheManager: Falling back to original URL: $finalUrl');
    }

    // **ADAPTIVE**: Start streaming with current network quality
    _startAdaptiveStreaming(finalUrl, controller);

    return controller.stream;
  }

  void _scheduleRetention(String url) {
    _retentionTimers[url]?.cancel();
    _retentionTimers[url] = Timer(_retentionDuration, () {
      // Final teardown after grace period
      _forceTeardown(url);
    });
  }

  void _forceTeardown(String url) {
    // Cancel retention and quality timers
    _retentionTimers[url]?.cancel();
    _retentionTimers.remove(url);
    _qualityTimers[url]?.cancel();
    _qualityTimers.remove(url);

    // Reset streaming state and counters
    _isStreaming[url] = false;
    _bytesReceived.remove(url);

    // Close and remove controller if exists
    try {
      _streamControllers[url]?.close();
    } catch (_) {}
    _streamControllers.remove(url);
  }

  /// **ADAPTIVE STREAMING**: Adjust quality based on network conditions
  Future<void> _startAdaptiveStreaming(
    String url,
    StreamController<List<int>> controller,
  ) async {
    try {
      final client = http.Client();
      final request = http.Request('GET', Uri.parse(url));
      request.headers['Range'] = 'bytes=0-'; // Enable range requests
      request.headers['User-Agent'] = 'Snehayog/1.0 (Mobile)'; // Add user agent
      request.headers['Accept'] =
          'application/vnd.apple.mpegurl, application/x-mpegURL, application/octet-stream, */*'; // HLS support

      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode == 206 ||
          streamedResponse.statusCode == 200) {
        // **ADAPTIVE CHUNKING**: Use different chunk sizes based on network
        await _streamWithAdaptiveChunking(
          url,
          streamedResponse.stream,
          controller,
        );

        controller.close();
        print('✅ VideoCacheManager: Adaptive streaming completed for $url');
      } else if (streamedResponse.statusCode == 401) {
        // Handle authentication error
        print('❌ VideoCacheManager: HTTP 401 - Authentication failed for $url');
        print('🔄 VideoCacheManager: Trying fallback URL...');

        final fallbackUrl = _getFallbackUrl(url);
        if (fallbackUrl != url) {
          await _startAdaptiveStreaming(fallbackUrl, controller);
          return;
        }

        throw Exception('HTTP 401 - Authentication failed');
      } else if (streamedResponse.statusCode == 400) {
        // Handle bad request error - try fallback URL
        print('❌ VideoCacheManager: HTTP 400 - Bad request for $url');
        print('🔄 VideoCacheManager: Trying fallback URL...');

        final fallbackUrl = _getFallbackUrl(url);
        if (fallbackUrl != url) {
          await _startAdaptiveStreaming(fallbackUrl, controller);
          return;
        }

        // If no fallback available, try direct Cloudinary URL
        final directUrl = _getDirectCloudinaryUrl(url);
        if (directUrl != url) {
          print('🔄 VideoCacheManager: Trying direct Cloudinary URL...');
          await _startAdaptiveStreaming(directUrl, controller);
          return;
        }

        // Final fallback: try with basic quality parameters
        final basicUrl = _getBasicQualityUrl(url);
        if (basicUrl != url) {
          print('🔄 VideoCacheManager: Trying basic quality URL...');
          await _startAdaptiveStreaming(basicUrl, controller);
          return;
        }

        throw Exception('HTTP 400 - Bad request, no fallback available');
      } else {
        print(
            '❌ VideoCacheManager: HTTP ${streamedResponse.statusCode} for $url');
        throw Exception('HTTP ${streamedResponse.statusCode}');
      }
    } catch (e) {
      print('❌ VideoCacheManager: Error in adaptive streaming $url: $e');
      print('🔍 VideoCacheManager: Error type: ${e.runtimeType}');
      print('🔍 VideoCacheManager: Error details: $e');

      // Add more specific error handling
      if (e.toString().contains('HTTP 404')) {
        print(
            '❌ VideoCacheManager: Video not found - check if video exists in Cloudinary');
      } else if (e.toString().contains('HTTP 400')) {
        print(
            '❌ VideoCacheManager: Bad request - check URL format and transformations');
      } else if (e.toString().contains('HTTP 401')) {
        print(
            '❌ VideoCacheManager: Authentication failed - check Cloudinary credentials');
      } else if (e.toString().contains('TimeoutException')) {
        print(
            '❌ VideoCacheManager: Request timeout - check network connection');
      }

      controller.addError(e);
    } finally {
      _cleanup(url);
    }
  }

  /// **ADAPTIVE CHUNKING**: Stream with quality-aware chunk sizes
  Future<void> _streamWithAdaptiveChunking(
    String url,
    Stream<List<int>> responseStream,
    StreamController<List<int>> controller,
  ) async {
    final buffer = <int>[];
    final initialBufferSize = INITIAL_BUFFER_SIZES[_currentQuality]!;

    await for (final chunk in responseStream) {
      if (!_isStreaming[url]!) break;

      buffer.addAll(chunk);
      _bytesReceived[url] = _bytesReceived[url]! + chunk.length;

      // **ADAPTIVE CHUNKING**: Send chunks based on current network quality
      final chunkSize = CHUNK_SIZES[_currentQuality]!;

      while (buffer.length >= chunkSize) {
        final chunkToSend = buffer.sublist(0, chunkSize);
        buffer.removeRange(0, chunkSize);
        controller.add(chunkToSend);
      }

      // **INSTANT PLAY**: Start playing after initial buffer
      if (_bytesReceived[url]! >= initialBufferSize && _isStreaming[url]!) {
        print(
          '🎬 VideoCacheManager: Initial buffer ready for $url (${_bytesReceived[url]} bytes)',
        );
        print('🌐 VideoCacheManager: Network quality: $_currentQuality');
      }

      // **QUALITY MONITORING**: Check if we need to adjust quality
      _monitorQualityAdjustment(url);
    }

    // **FINAL CHUNK**: Send remaining buffer
    if (buffer.isNotEmpty) {
      controller.add(buffer);
    }
  }

  /// **QUALITY MONITORING**: Adjust streaming quality based on network changes
  void _monitorQualityAdjustment(String url) {
    _qualityTimers[url]?.cancel();
    _qualityTimers[url] = Timer(const Duration(seconds: 2), () {
      if (_isStreaming[url]! && _isSlowNetwork) {
        print(
          '🔄 VideoCacheManager: Network degraded, adjusting quality for $url',
        );
        // Quality adjustment logic can be added here
      }
    });
  }

  /// **CLEANUP**: Remove completed streams
  void _cleanup(String url) {
    _isStreaming[url] = false;
    _qualityTimers[url]?.cancel();
    _qualityTimers.remove(url);
    // Defer teardown to allow quick reuse when user scrolls back
    _scheduleRetention(url);
  }

  /// **STOP STREAMING**: Cancel ongoing streams
  void stopStreaming(String url) {
    if (_isStreaming.containsKey(url)) {
      _isStreaming[url] = false;
      // Do not close immediately; keep for short-lived reuse
      _scheduleRetention(url);
    }
  }

  /// **LEGACY METHODS** (keeping for compatibility)
  Future<File> getFile(String url) async {
    final filename = Uri.parse(url).pathSegments.last;
    final filePath = '${_cacheDir.path}/$filename';

    // 1. Check memory cache
    if (_memoryCache.containsKey(url)) {
      return _memoryCache[url]!;
    }

    // 2. Check disk cache
    final file = File(filePath);
    if (await file.exists()) {
      _addToMemoryCache(url, file);
      return file;
    }

    // 3. Download & save
    final downloadedFile = await _downloadFile(url, filePath);
    _addToMemoryCache(url, downloadedFile);
    return downloadedFile;
  }

  /// **PROGRESSIVE PRELOAD**: Use progressive streaming instead of full download
  Future<void> preloadFile(String url) async {
    // **PROGRESSIVE**: Start streaming instead of downloading full file
    try {
      await getProgressiveStream(url);
      print('🚀 VideoCacheManager: Progressive preload started for $url');
    } catch (e) {
      print('❌ VideoCacheManager: Progressive preload failed for $url: $e');
    }
  }

  /// **LEGACY DOWNLOAD**: Keep for compatibility
  Future<File> _downloadFile(String url, String path) async {
    final response = await http.get(Uri.parse(url));
    final file = File(path);
    await file.writeAsBytes(response.bodyBytes);
    return file;
  }

  /// **MANAGE MEMORY CACHE**: LRU eviction
  void _addToMemoryCache(String url, File file) {
    if (_memoryCache.containsKey(url)) return;

    _memoryCache[url] = file;
    _order.addLast(url);

    if (_memoryCache.length > maxMemoryItems) {
      final oldUrl = _order.removeFirst();
      _memoryCache.remove(oldUrl);
    }
  }

  /// **CLEAR ALL**: Stop all streams and clear caches
  Future<void> clear() async {
    // **STOP STREAMING**: Cancel all progressive streams
    for (final url in List<String>.from(_streamControllers.keys)) {
      _forceTeardown(url);
    }

    // **CLEAR LEGACY CACHE**
    _memoryCache.clear();
    _order.clear();
    if (await _cacheDir.exists()) {
      await _cacheDir.delete(recursive: true);
      await _cacheDir.create(recursive: true);
    }
  }

  /// **CLEANUP**: Stop monitoring and clear resources
  void dispose() {
    _speedTestTimer?.cancel();
    clear();
  }

  // **COMPATIBILITY METHODS** - For existing code
  Future<void> clearAllCaches() async {
    await clear();
  }

  Future<void> clearInstanceCache() async {
    _memoryCache.clear();
    _order.clear();
  }

  /// **ENHANCED STATS**: Include progressive streaming stats
  Map<String, dynamic> getCacheStats() {
    return {
      'memoryCacheSize': _memoryCache.length,
      'maxMemoryItems': maxMemoryItems,
      'cacheDir': _cacheDir.path,
      'activeStreams': _streamControllers.length,
      'isStreaming': _isStreaming.values.where((v) => v).length,
      'totalBytesReceived': _bytesReceived.values.fold(
        0,
        (sum, bytes) => sum + bytes,
      ),
      'networkQuality': _currentQuality.toString(),
      'networkSpeed': _currentSpeed,
      'isSlowNetwork': _isSlowNetwork,
    };
  }

  // **NETWORK QUALITY GETTERS**
  double get currentSpeed => _currentSpeed;
  NetworkQuality get currentQuality => _currentQuality;
  bool get isSlowNetwork => _isSlowNetwork;
  bool get shouldShowLoadingIndicator =>
      _currentQuality == NetworkQuality.veryLow;

  // **COMPATIBILITY METHODS** (keeping existing interface)
  void updateVideoLoadingState(int index, bool isLoading) {
    // Compatibility method - no implementation needed
  }

  bool isVideoLoading(int index) {
    return false; // Compatibility method
  }

  void updateVideoBufferingState(int index, bool isBuffering) {
    // Compatibility method - no implementation needed
  }

  bool isVideoBuffering(int index) {
    return false; // Compatibility method
  }

  void updateBufferedPosition(int index, Duration position) {
    // Compatibility method - no implementation needed
  }

  Duration getBufferedPosition(int index) {
    return Duration.zero; // Compatibility method
  }

  void saveVideoPosition(int index, Duration position) {
    // Compatibility method - no implementation needed
  }

  Duration? getSavedVideoPosition(int index) {
    return null; // Compatibility method
  }

  void updateBufferDuration(int index, Duration duration) {
    // Compatibility method - no implementation needed
  }

  Duration getBufferDuration(int index) {
    return Duration.zero; // Compatibility method
  }

  void updateVideoQualityUrl(int index, String url) {
    // Compatibility method - no implementation needed
  }

  String? getVideoQualityUrl(int index) {
    return null; // Compatibility method
  }

  void markVideoAsDownloaded(int index) {
    // Compatibility method - no implementation needed
  }

  bool isVideoDownloaded(int index) {
    return false; // Compatibility method
  }

  void clearVideoCache(int index) {
    // Compatibility method - no implementation needed
  }

  void clearAllData() {
    clear(); // Compatibility method
  }

  /// Get fallback URL for HLS streams
  String _getFallbackUrl(String originalUrl) {
    if (!originalUrl.contains('.m3u8')) return originalUrl;

    try {
      // Try different Cloudinary streaming profiles
      if (originalUrl.contains('sp_hd')) {
        // Try SD profile instead of HD
        return originalUrl.replaceAll('sp_hd', 'sp_sd');
      } else if (originalUrl.contains('sp_sd')) {
        // Try basic streaming profile
        return originalUrl.replaceAll('sp_sd', 'sp_auto');
      } else if (originalUrl.contains('sp_auto')) {
        // Try without streaming profile
        return originalUrl.replaceAll(RegExp(r'sp_[^,]+,'), '');
      } else if (originalUrl.contains('q_auto:best')) {
        return originalUrl.replaceAll('q_auto:best', 'q_auto:good');
      } else if (originalUrl.contains('q_auto:good')) {
        return originalUrl.replaceAll('q_auto:good', 'q_auto:eco');
      } else if (originalUrl.contains('q_auto:eco')) {
        return originalUrl.replaceAll('q_auto:eco', 'q_auto:low');
      }
    } catch (e) {
      print('❌ VideoCacheManager: Error generating fallback URL: $e');
    }

    return originalUrl;
  }

  /// Get direct Cloudinary URL without transformations
  String _getDirectCloudinaryUrl(String originalUrl) {
    if (!originalUrl.contains('cloudinary.com')) return originalUrl;

    try {
      final uri = Uri.parse(originalUrl);
      final pathSegments = uri.pathSegments;

      // Find the video ID in the path - improved logic
      String? videoId;
      bool foundUpload = false;

      for (int i = 0; i < pathSegments.length; i++) {
        if (pathSegments[i] == 'upload') {
          foundUpload = true;
          // Look for the actual video ID after upload
          for (int j = i + 1; j < pathSegments.length; j++) {
            final segment = pathSegments[j];
            // Skip transformation segments
            if (segment.startsWith('s--') ||
                segment.startsWith('q_') ||
                segment.startsWith('v') ||
                segment.contains('auto') ||
                segment.length < 10) {
              continue;
            }
            // Found the video ID
            if (segment.length > 10 &&
                !segment.contains('--') &&
                !segment.contains(':')) {
              videoId = segment.replaceAll(
                  RegExp(r'\.(m3u8|mp4)$', caseSensitive: false), '');
              break;
            }
          }
          break;
        }
      }

      if (videoId != null && foundUpload) {
        // Construct direct URL without transformations
        final directUrl =
            'https://res.cloudinary.com/dkklingts/video/upload/$videoId';
        print('🔄 VideoCacheManager: Generated direct URL: $directUrl');
        return directUrl;
      }
    } catch (e) {
      print('❌ VideoCacheManager: Error generating direct URL: $e');
    }

    return originalUrl;
  }

  /// Get basic quality URL as final fallback
  String _getBasicQualityUrl(String originalUrl) {
    if (!originalUrl.contains('cloudinary.com')) return originalUrl;

    try {
      final uri = Uri.parse(originalUrl);
      final pathSegments = uri.pathSegments;

      // Find the video ID in the path
      String? videoId;
      bool foundUpload = false;

      for (int i = 0; i < pathSegments.length; i++) {
        if (pathSegments[i] == 'upload') {
          foundUpload = true;
          // Look for the actual video ID after upload
          for (int j = i + 1; j < pathSegments.length; j++) {
            final segment = pathSegments[j];
            // Skip transformation segments
            if (segment.startsWith('s--') ||
                segment.startsWith('q_') ||
                segment.startsWith('v') ||
                segment.contains('auto') ||
                segment.length < 10) {
              continue;
            }
            // Found the video ID
            if (segment.length > 10 &&
                !segment.contains('--') &&
                !segment.contains(':')) {
              videoId = segment.replaceAll(
                  RegExp(r'\.(m3u8|mp4)$', caseSensitive: false), '');
              break;
            }
          }
          break;
        }
      }

      if (videoId != null && foundUpload) {
        // Construct basic quality URL with minimal transformations
        final basicUrl =
            'https://res.cloudinary.com/dkklingts/video/upload/q_auto:low,f_auto/$videoId.m3u8';
        print('🔄 VideoCacheManager: Generated basic quality URL: $basicUrl');
        return basicUrl;
      }
    } catch (e) {
      print('❌ VideoCacheManager: Error generating basic quality URL: $e');
    }

    return originalUrl;
  }
}
