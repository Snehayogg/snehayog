import 'package:http/http.dart' as http;
import '../../config/app_config.dart';

/// Centralized HTTP client service with connection pooling
/// This service manages a single HTTP client instance with optimized settings
/// for connection reuse and performance
class HttpClientService {
  static HttpClientService? _instance;
  static HttpClientService get instance =>
      _instance ??= HttpClientService._internal();

  HttpClientService._internal();

  late http.Client _client;
  bool _isInitialized = false;

  /// Initialize the HTTP client with connection pooling settings
  void initialize() {
    if (_isInitialized) return;

    // Create HTTP client with connection pooling configuration
    _client = http.Client();
    _isInitialized = true;

    print('🔗 HttpClientService: Initialized with connection pooling');
  }

  /// Get the shared HTTP client instance
  http.Client get client {
    if (!_isInitialized) {
      initialize();
    }
    return _client;
  }

  /// Make a GET request using the shared client
  Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    return await client
        .get(
          url,
          headers: headers,
        )
        .timeout(timeout ?? AppConfig.apiTimeout);
  }

  /// Make a POST request using the shared client
  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    return await client
        .post(
          url,
          headers: headers,
          body: body,
        )
        .timeout(timeout ?? AppConfig.apiTimeout);
  }

  /// Make a PUT request using the shared client
  Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    return await client
        .put(
          url,
          headers: headers,
          body: body,
        )
        .timeout(timeout ?? AppConfig.apiTimeout);
  }

  /// Make a PATCH request using the shared client
  Future<http.Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    return await client
        .patch(
          url,
          headers: headers,
          body: body,
        )
        .timeout(timeout ?? AppConfig.apiTimeout);
  }

  /// Make a DELETE request using the shared client
  Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    return await client
        .delete(
          url,
          headers: headers,
        )
        .timeout(timeout ?? AppConfig.apiTimeout);
  }

  /// Make a multipart request using the shared client
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return await client.send(request);
  }

  /// Make a request with retry logic and connection pooling
  Future<http.Response> makeRequest(
    Future<http.Response> Function() requestFn, {
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 1),
    Duration? timeout,
  }) async {
    int attempts = 0;

    while (attempts < maxRetries) {
      try {
        final response =
            await requestFn().timeout(timeout ?? AppConfig.apiTimeout);

        // Return successful responses immediately
        if (response.statusCode >= 200 && response.statusCode < 300) {
          return response;
        }

        // For client errors (4xx), don't retry
        if (response.statusCode >= 400 && response.statusCode < 500) {
          return response;
        }

        // For server errors (5xx), retry
        attempts++;
        if (attempts < maxRetries) {
          print(
              '🔄 HttpClientService: Retrying request (attempt $attempts/$maxRetries)');
          await Future.delayed(retryDelay * attempts);
        }
      } catch (e) {
        attempts++;
        if (attempts >= maxRetries) {
          print(
              '❌ HttpClientService: Request failed after $maxRetries attempts: $e');
          rethrow;
        }
        print(
            '🔄 HttpClientService: Retrying after error (attempt $attempts/$maxRetries): $e');
        await Future.delayed(retryDelay * attempts);
      }
    }

    throw Exception('Request failed after $maxRetries attempts');
  }

  /// Get connection pooling statistics (for debugging)
  Map<String, dynamic> getConnectionStats() {
    return {
      'isInitialized': _isInitialized,
      'clientType': _client.runtimeType.toString(),
      'hasConnectionPooling': true,
    };
  }

  /// Close the HTTP client and clean up connections
  void dispose() {
    if (_isInitialized) {
      _client.close();
      _isInitialized = false;
      print('🔗 HttpClientService: Disposed and connections closed');
    }
  }

  /// Reset the client (useful for testing or reconfiguration)
  void reset() {
    dispose();
    initialize();
  }
}

/// Global HTTP client service instance
final httpClientService = HttpClientService.instance;
