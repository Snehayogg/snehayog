import 'dart:io';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:flutter/foundation.dart';

/// Network service with automatic fallback between local and production servers
class NetworkService {
  static NetworkService? _instance;
  static NetworkService get instance => _instance ??= NetworkService._();

  NetworkService._();

  // Server URLs in priority order
  static const List<String> _serverUrls = [
    'http://192.168.0.199:5001', // Local development server
    'https://snehayog-production.up.railway.app', // Production fallback
  ];

  String? _currentBaseUrl;
  int _currentIndex = 0;
  bool _isCheckingConnection = false;
  final Map<String, bool> _serverStatusCache = {};

  /// Get the current active base URL
  String get baseUrl {
    return _currentBaseUrl ?? _serverUrls.first;
  }

  /// Get all available server URLs
  List<String> get availableUrls => List.from(_serverUrls);

  /// Check if currently using local server
  bool get isUsingLocalServer =>
      _currentBaseUrl?.contains('192.168.0.199') ?? false;

  /// Check if currently using production server
  bool get isUsingProductionServer =>
      _currentBaseUrl?.contains('railway.app') ?? false;

  /// Initialize network service with connection testing
  Future<void> initialize() async {
    if (kDebugMode) {
      print('🌐 NetworkService: Initializing with fallback support...');
    }

    await _findWorkingServer();
  }

  /// Find the first working server from the list
  Future<void> _findWorkingServer() async {
    if (_isCheckingConnection) return;

    _isCheckingConnection = true;

    try {
      for (int i = 0; i < _serverUrls.length; i++) {
        final url = _serverUrls[i];

        if (kDebugMode) {
          print('🔍 NetworkService: Testing connection to $url');
        }

        // Check cache first
        if (_serverStatusCache[url] == false) {
          if (kDebugMode) {
            print('⏭️ NetworkService: Skipping $url (cached as offline)');
          }
          continue;
        }

        final isOnline = await _testConnection(url);
        _serverStatusCache[url] = isOnline;

        if (isOnline) {
          _currentBaseUrl = url;
          _currentIndex = i;

          if (kDebugMode) {
            print('✅ NetworkService: Connected to $url');
            print('📍 NetworkService: Current base URL: $baseUrl');
          }
          return;
        } else {
          if (kDebugMode) {
            print('❌ NetworkService: $url is offline');
          }
        }
      }

      // If no server is working, use the first one as fallback
      _currentBaseUrl = _serverUrls.first;
      _currentIndex = 0;

      if (kDebugMode) {
        print('⚠️ NetworkService: No servers online, using fallback: $baseUrl');
      }
    } finally {
      _isCheckingConnection = false;
    }
  }

  /// Test connection to a specific URL
  Future<bool> _testConnection(String baseUrl) async {
    try {
      final uri = Uri.parse('$baseUrl/health');

      final response = await http.get(
        uri,
        headers: {'Content-Type': 'application/json'},
      ).timeout(
        const Duration(seconds: 5),
        onTimeout: () => throw TimeoutException(
            'Connection timeout', const Duration(seconds: 5)),
      );

      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        print('❌ NetworkService: Connection test failed for $baseUrl: $e');
      }
      return false;
    }
  }

  /// Force reconnect and find working server
  Future<void> reconnect() async {
    if (kDebugMode) {
      print('🔄 NetworkService: Force reconnecting...');
    }

    _serverStatusCache.clear();
    _currentBaseUrl = null;
    _currentIndex = 0;

    await _findWorkingServer();
  }

  /// Try to switch to local server if available
  Future<bool> tryLocalServer() async {
    if (kDebugMode) {
      print('🏠 NetworkService: Attempting to connect to local server...');
    }

    final localUrl = _serverUrls.first;
    final isOnline = await _testConnection(localUrl);

    if (isOnline) {
      _currentBaseUrl = localUrl;
      _currentIndex = 0;
      _serverStatusCache[localUrl] = true;

      if (kDebugMode) {
        print('✅ NetworkService: Successfully switched to local server');
      }
      return true;
    } else {
      if (kDebugMode) {
        print('❌ NetworkService: Local server is not available');
      }
      return false;
    }
  }

  /// Switch to production server
  Future<void> switchToProduction() async {
    if (kDebugMode) {
      print('☁️ NetworkService: Switching to production server...');
    }

    _currentBaseUrl = _serverUrls.last;
    _currentIndex = _serverUrls.length - 1;

    if (kDebugMode) {
      print('✅ NetworkService: Switched to production server');
    }
  }

  /// Get connection status information
  Map<String, dynamic> getConnectionInfo() {
    return {
      'currentUrl': _currentBaseUrl,
      'currentIndex': _currentIndex,
      'isLocal': isUsingLocalServer,
      'isProduction': isUsingProductionServer,
      'availableUrls': _serverUrls,
      'serverStatus': Map.from(_serverStatusCache),
    };
  }

  /// Make HTTP request with automatic retry and fallback
  Future<http.Response> makeRequest(
    String Function(String baseUrl) urlBuilder, {
    Map<String, String>? headers,
    Object? body,
    http.Client? client,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final httpClient = client ?? http.Client();

    try {
      // Try current server first
      final url = urlBuilder(baseUrl);
      final uri = Uri.parse(url);

      final response = await httpClient
          .get(
            uri,
            headers: headers,
          )
          .timeout(timeout);

      if (response.statusCode == 200) {
        return response;
      }

      // If current server fails, try to find another working server
      await _findWorkingServer();

      // Retry with new server
      final retryUrl = urlBuilder(baseUrl);
      final retryUri = Uri.parse(retryUrl);

      return await httpClient
          .get(
            retryUri,
            headers: headers,
          )
          .timeout(timeout);
    } catch (e) {
      // If all else fails, try production server as last resort
      if (isUsingLocalServer) {
        if (kDebugMode) {
          print(
              '🔄 NetworkService: Request failed, trying production server...');
        }

        await switchToProduction();

        final fallbackUrl = urlBuilder(baseUrl);
        final fallbackUri = Uri.parse(fallbackUrl);

        return await httpClient
            .get(
              fallbackUri,
              headers: headers,
            )
            .timeout(timeout);
      }

      rethrow;
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }

  /// POST request with fallback
  Future<http.Response> makePostRequest(
    String Function(String baseUrl) urlBuilder, {
    Map<String, String>? headers,
    Object? body,
    http.Client? client,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final httpClient = client ?? http.Client();

    try {
      final url = urlBuilder(baseUrl);
      final uri = Uri.parse(url);

      return await httpClient
          .post(
            uri,
            headers: headers,
            body: body,
          )
          .timeout(timeout);
    } catch (e) {
      // For POST requests, we don't automatically fallback to avoid duplicate submissions
      if (kDebugMode) {
        print('❌ NetworkService: POST request failed: $e');
      }
      rethrow;
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }
}
