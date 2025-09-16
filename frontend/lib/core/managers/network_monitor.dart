import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';

enum NetworkQuality {
  high, // > 5 Mbps
  medium, // 1-5 Mbps
  low, // 0.5-1 Mbps
  veryLow // < 0.5 Mbps
}

class NetworkMonitor {
  static final NetworkMonitor _instance = NetworkMonitor._internal();
  factory NetworkMonitor() => _instance;
  NetworkMonitor._internal();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  NetworkQuality _currentQuality = NetworkQuality.high;
  double _currentSpeedMbps = 10.0; // Default to high speed
  bool _isMonitoring = false;

  // Quality thresholds
  static const double highThreshold = 5.0; // Mbps
  static const double mediumThreshold = 1.0; // Mbps
  static const double lowThreshold = 0.5; // Mbps

  // Getters
  NetworkQuality get currentQuality => _currentQuality;
  double get currentSpeedMbps => _currentSpeedMbps;
  bool get isSlowNetwork =>
      _currentQuality == NetworkQuality.low ||
      _currentQuality == NetworkQuality.veryLow;
  bool get shouldShowLoadingIndicator =>
      _currentQuality == NetworkQuality.veryLow;

  // Start monitoring network
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;

    _isMonitoring = true;
    _connectivitySubscription = _connectivity.onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      _handleConnectivityChange(results);
    });

    // Initial speed test
    await _testNetworkSpeed();
  }

  // Stop monitoring
  void stopMonitoring() {
    _isMonitoring = false;
    _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
  }

  // Handle connectivity changes
  void _handleConnectivityChange(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.none)) {
      _currentQuality = NetworkQuality.veryLow;
      _currentSpeedMbps = 0.0;
    } else {
      // Test speed when connectivity changes
      _testNetworkSpeed();
    }
  }

  // Test network speed
  Future<void> _testNetworkSpeed() async {
    try {
      final stopwatch = Stopwatch()..start();

      // Use a small test file or endpoint
      final client = HttpClient();
      final request = await client
          .getUrl(Uri.parse('https://httpbin.org/bytes/1024')); // 1KB test
      final response = await request.close();

      stopwatch.stop();

      if (response.statusCode == 200) {
        // Calculate speed (rough estimation)
        final durationMs = stopwatch.elapsedMilliseconds;
        final bytesPerSecond = 1024 / (durationMs / 1000);
        _currentSpeedMbps =
            (bytesPerSecond * 8) / (1024 * 1024); // Convert to Mbps

        _updateNetworkQuality();
      }

      client.close();
    } catch (e) {
      // If speed test fails, assume slow network
      _currentSpeedMbps = 0.1;
      _currentQuality = NetworkQuality.veryLow;
    }
  }

  // Update network quality based on speed
  void _updateNetworkQuality() {
    if (_currentSpeedMbps >= highThreshold) {
      _currentQuality = NetworkQuality.high;
    } else if (_currentSpeedMbps >= mediumThreshold) {
      _currentQuality = NetworkQuality.medium;
    } else if (_currentSpeedMbps >= lowThreshold) {
      _currentQuality = NetworkQuality.low;
    } else {
      _currentQuality = NetworkQuality.veryLow;
    }
  }

  // Get chunk size based on network quality
  int getChunkSize() {
    switch (_currentQuality) {
      case NetworkQuality.high:
        return 1024 * 1024; // 1MB chunks
      case NetworkQuality.medium:
        return 512 * 1024; // 512KB chunks
      case NetworkQuality.low:
        return 256 * 1024; // 256KB chunks
      case NetworkQuality.veryLow:
        return 128 * 1024; // 128KB chunks
    }
  }

  // Get initial buffer size
  int getInitialBufferSize() {
    switch (_currentQuality) {
      case NetworkQuality.high:
        return 2 * 1024 * 1024; // 2MB buffer
      case NetworkQuality.medium:
        return 1024 * 1024; // 1MB buffer
      case NetworkQuality.low:
        return 512 * 1024; // 512KB buffer
      case NetworkQuality.veryLow:
        return 256 * 1024; // 256KB buffer
    }
  }

  // Dispose
  void dispose() {
    stopMonitoring();
  }
}
