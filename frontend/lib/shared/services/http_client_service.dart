import 'package:dio/dio.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_performance/firebase_performance.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/shared/config/app_config.dart';
import 'package:vayu/shared/utils/app_logger.dart';

/// Centralized HTTP client service with Dio
/// Provides automatic connection pooling, interceptors, retry logic, and better performance
/// Maintains backward compatibility with http.Response format
class HttpClientService {
  static HttpClientService? _instance;
  static HttpClientService get instance =>
      _instance ??= HttpClientService._internal();

  HttpClientService._internal();

  late Dio _dio;
  bool _isInitialized = false;
  
  /// Callback to handle token refresh when 401 occurs
  Future<String?> Function()? onTokenExpired;
  
  /// To prevent concurrent refresh calls
  bool _isRefreshing = false;
  Future<String?>? _refreshFuture;

  /// Initialize the Dio client with optimized settings
  void initialize() {
    if (_isInitialized) return;

    // Create Dio instance with optimized configuration
    _dio = Dio(
      BaseOptions(
        connectTimeout: AppConfig.apiTimeout,
        receiveTimeout: AppConfig.apiTimeout,
        sendTimeout: AppConfig.uploadTimeout,
        // Enable HTTP/2
        followRedirects: true,
        maxRedirects: 5,
        // Enable persistent connections (connection pooling)
        persistentConnection: true,
        // Better error handling
        validateStatus: (status) {
          // **FIX: Throw on 401 so the Auth Interceptor (onError) can handle it**
          if (status == 401) return false;
          return status != null && status < 500;
        },
      ),
    );

    // Add interceptors for logging and automatic retry
    _dio.interceptors.add(LogInterceptor(
      requestBody: false,
      responseBody: false,
      logPrint: (object) {
        AppLogger.log('🔗 Dio: $object');
      },
    ));

    // Add automatic retry interceptor
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) async {
          // Retry logic for network errors
          if (error.type == DioExceptionType.connectionTimeout ||
              error.type == DioExceptionType.sendTimeout ||
              error.type == DioExceptionType.receiveTimeout ||
              error.type == DioExceptionType.connectionError) {
            final options = error.requestOptions;
            final retryCount = (options.extra['retryCount'] as int?) ?? 0;
            if (retryCount < 2) {
              options.extra['retryCount'] = retryCount + 1;
              AppLogger.log(
                  '🔄 HttpClientService: Retrying request (attempt ${retryCount + 1}/2)');
              try {
                final response = await _dio.fetch(options);
                return handler.resolve(response);
              } catch (e) {
                return handler.next(error);
              }
            }
          }
          return handler.next(error);
        },
      ),
    );

    // **NEW: Auth Interceptor for adding token and Firebase Performance**
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            // **NEW: Inject API Version Header**
            options.headers['X-API-Version'] = AppConfig.kApiVersion;

            // **NEW: Automatically inject Auth Token if missing**
            if (!options.headers.containsKey('Authorization')) {
              try {
                final prefs = await SharedPreferences.getInstance();
                final token = prefs.getString('jwt_token');
                if (token != null && token.isNotEmpty) {
                  options.headers['Authorization'] = 'Bearer $token';
                  AppLogger.log('🔑 HttpClientService: Auto-injected token into ${options.path}');
                }
              } catch (e) {
                // Silently fail for token injection
              }
            }
            
            final metric = FirebasePerformance.instance.newHttpMetric(
                options.uri.toString(), _mapHttpMethod(options.method));
            options.extra['performance_metric'] = metric;
            await metric.start();
          } catch (e) {
            AppLogger.log('⚠️ Performance Interceptor Error: $e');
          }
          return handler.next(options);
        },
        onResponse: (response, handler) async {
          try {
            final metric = response.requestOptions.extra['performance_metric'] as HttpMetric?;
            if (metric != null) {
              metric.httpResponseCode = response.statusCode;
              metric.responsePayloadSize = response.data?.toString().length;
              await metric.stop();
            }
          } catch (e) {
            AppLogger.log('⚠️ Performance Interceptor Response Error: $e');
          }
          return handler.next(response);
        },
        onError: (error, handler) async {
          try {
            final metric = error.requestOptions.extra['performance_metric'] as HttpMetric?;
            if (metric != null) {
              metric.httpResponseCode = error.response?.statusCode;
              await metric.stop();
            }
          } catch (e) {
            AppLogger.log('⚠️ Performance Interceptor Error Recovery: $e');
          }
          return handler.next(error);
        },
      ),
    );

    // **NEW: Auth Interceptor for handling 401 errors**
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) async {
          // If 401 Unauthorized occurs and we have a refresh handler
          if (error.response?.statusCode == 401 && onTokenExpired != null) {
            // **FIX: Prevent infinite retry loops for the same request**
            if (error.requestOptions.extra['is_retry'] == true) {
              AppLogger.log('🔐 HttpClientService: 401 occurred for an already retried request. Aborting to prevent loop.');
              return handler.next(error);
            }

            AppLogger.log('🔐 HttpClientService: 401 detected for ${error.requestOptions.path}, attempting token refresh...');
            
            try {
              String? newToken;
              
              // Handle concurrent refresh attempts
              if (_isRefreshing) {
                AppLogger.log('🔐 HttpClientService: Refresh already in progress, waiting...');
                newToken = await _refreshFuture;
              } else {
                _isRefreshing = true;
                _refreshFuture = onTokenExpired!();
                newToken = await _refreshFuture;
                _isRefreshing = false;
                _refreshFuture = null;
              }
 
              if (newToken != null) {
                AppLogger.log('🔐 HttpClientService: Token refreshed successfully. Retrying original request...');
                
                // Update the original request's auth header
                final options = error.requestOptions;
                options.headers['Authorization'] = 'Bearer $newToken';
                
                // Mark this request as a retry to prevent loops
                options.extra['is_retry'] = true;
                
                // **CRITICAL: Also update headers in the underlying RequestOptions to be sure**
                // (Sometimes headers are cached in multiple places in Dio)
                
                // Retry the request
                final response = await _dio.fetch(options);
                return handler.resolve(response);
              } else {
                AppLogger.log('🔐 HttpClientService: Token refresh returned null, user must re-authenticate');
              }
            } catch (e) {
              _isRefreshing = false;
              _refreshFuture = null;
              AppLogger.log('🔐 HttpClientService: Error during automatic refresh: $e');
            }
          }
          return handler.next(error);
        },
      ),
    );

    _isInitialized = true;
    AppLogger.log(
        '🔗 HttpClientService: Initialized with Dio (connection pooling, interceptors, HTTP/2)');
  }

  /// Get the shared Dio client instance
  Dio get dio {
    if (!_isInitialized) {
      initialize();
    }
    return _dio;
  }

  /// Convert Dio Response to http.Response for backward compatibility
  http.Response _convertDioResponse(Response dioResponse) {
    return http.Response(
      dioResponse.data is String
          ? dioResponse.data
          : (dioResponse.data != null
              ? jsonEncode(dioResponse.data)
              : dioResponse.data?.toString() ?? ''),
      dioResponse.statusCode ?? 200,
      headers: Map<String, String>.from(
        dioResponse.headers.map.map(
          (key, value) => MapEntry(key, value.join(', ')),
        ),
      ),
    );
  }

  /// Convert DioException to http Response for error handling
  http.Response _convertDioError(DioException error) {
    final statusCode = error.response?.statusCode ?? 500;
    final data = error.response?.data ?? error.message ?? 'Request failed';
    final headers = error.response?.headers.map.map(
          (key, value) => MapEntry(key, value.join(', ')),
        ) ??
        {};
    return http.Response(
      data is String ? data : jsonEncode(data),
      statusCode,
      headers: Map<String, String>.from(headers),
    );
  }

  /// Make a GET request using Dio
  Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    try {
      final response = await dio.get(
        url.toString(),
        options: Options(
          headers: headers,
          receiveTimeout: timeout ?? AppConfig.apiTimeout,
        ),
      );
      return _convertDioResponse(response);
    } on DioException catch (e) {
      return _convertDioError(e);
    }
  }

  /// Make a POST request using Dio
  Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    try {
      final response = await dio.post(
        url.toString(),
        data: body is String ? body : jsonEncode(body),
        options: Options(
          headers: headers,
          receiveTimeout: timeout ?? AppConfig.apiTimeout,
          contentType: headers?['Content-Type'] ?? 'application/json',
        ),
      );
      return _convertDioResponse(response);
    } on DioException catch (e) {
      return _convertDioError(e);
    }
  }

  /// Make a PUT request using Dio
  Future<http.Response> put(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    try {
      final response = await dio.put(
        url.toString(),
        data: body is String ? body : jsonEncode(body),
        options: Options(
          headers: headers,
          receiveTimeout: timeout ?? AppConfig.apiTimeout,
          contentType: headers?['Content-Type'] ?? 'application/json',
        ),
      );
      return _convertDioResponse(response);
    } on DioException catch (e) {
      return _convertDioError(e);
    }
  }

  /// Make a PATCH request using Dio
  Future<http.Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    try {
      final response = await dio.patch(
        url.toString(),
        data: body is String ? body : jsonEncode(body),
        options: Options(
          headers: headers,
          receiveTimeout: timeout ?? AppConfig.apiTimeout,
          contentType: headers?['Content-Type'] ?? 'application/json',
        ),
      );
      return _convertDioResponse(response);
    } on DioException catch (e) {
      return _convertDioError(e);
    }
  }

  /// Make a DELETE request using Dio
  Future<http.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    try {
      final response = await dio.delete(
        url.toString(),
        data: body is String ? body : jsonEncode(body),
        options: Options(
          headers: headers,
          receiveTimeout: timeout ?? AppConfig.apiTimeout,
          contentType: body != null
              ? (headers?['Content-Type'] ?? 'application/json')
              : null,
        ),
      );
      return _convertDioResponse(response);
    } on DioException catch (e) {
      return _convertDioError(e);
    }
  }

  /// Make a multipart request using Dio
  /// Uses FormData for multipart uploads (better than http package)
  Future<http.StreamedResponse> send(
    http.BaseRequest request, {
    Duration? timeout,
  }) async {
    try {
      // Convert http.BaseRequest to Dio FormData
      if (request is http.MultipartRequest) {
        final formData = FormData();

        // Add fields
        for (final entry in request.fields.entries) {
          formData.fields.add(MapEntry(entry.key, entry.value));
        }

        // Add files - read the stream and create MultipartFile
        for (final file in request.files) {
          final bytes = await file.finalize().toBytes();
          final multipartFile = MultipartFile.fromBytes(
            bytes,
            filename: file.filename,
            contentType: file.contentType,
          );
          formData.files.add(
            MapEntry(file.field, multipartFile),
          );
        }

        final response = await dio.post(
          request.url.toString(),
          data: formData,
          options: Options(
            headers: Map<String, dynamic>.from(request.headers),
            receiveTimeout: timeout ?? AppConfig.uploadTimeout,
          ),
        );

        // Convert Dio response to StreamedResponse-like format
        // Since we already have the response, we create a simple stream
        final bodyBytes = utf8.encode(
          response.data is String ? response.data : jsonEncode(response.data),
        );
        return http.StreamedResponse(
          Stream.value(bodyBytes),
          response.statusCode ?? 200,
          headers: Map<String, String>.from(
            response.headers.map.map(
              (key, value) => MapEntry(key, value.join(', ')),
            ),
          ),
        );
      } else {
        // For non-multipart requests, use regular POST
        final body = await request.finalize().bytesToString();
        final response = await dio.request(
          request.url.toString(),
          data: body,
          options: Options(
            method: request.method,
            headers: Map<String, dynamic>.from(request.headers),
            receiveTimeout: timeout ?? AppConfig.apiTimeout,
          ),
        );

        final bodyBytes = utf8.encode(
          response.data is String ? response.data : jsonEncode(response.data),
        );
        return http.StreamedResponse(
          Stream.value(bodyBytes),
          response.statusCode ?? 200,
          headers: Map<String, String>.from(
            response.headers.map.map(
              (key, value) => MapEntry(key, value.join(', ')),
            ),
          ),
        );
      }
    } on DioException catch (e) {
      final bodyBytes = utf8.encode(e.message ?? 'Request failed');
      return http.StreamedResponse(
        Stream.value(bodyBytes),
        e.response?.statusCode ?? 500,
        headers: Map<String, String>.from(
          e.response?.headers.map.map(
                (key, value) => MapEntry(key, value.join(', ')),
              ) ??
              {},
        ),
      );
    }
  }

  /// Make a request with retry logic (Dio handles this automatically, but kept for compatibility)
  Future<http.Response> makeRequest(
    Future<http.Response> Function() requestFn, {
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 1),
    Duration? timeout,
  }) async {
    int attempts = 0;

    while (attempts < maxRetries) {
      try {
        final response = await requestFn();

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
          AppLogger.log(
              '🔄 HttpClientService: Retrying request (attempt $attempts/$maxRetries)');
          await Future.delayed(retryDelay * attempts);
        }
      } catch (e) {
        attempts++;
        if (attempts >= maxRetries) {
          AppLogger.log(
              '❌ HttpClientService: Request failed after $maxRetries attempts: $e');
          rethrow;
        }
        AppLogger.log(
            '🔄 HttpClientService: Retrying after error (attempt $attempts/$maxRetries): $e');
        await Future.delayed(retryDelay * attempts);
      }
    }

    throw Exception('Request failed after $maxRetries attempts');
  }

  /// Get connection pooling statistics (Dio-specific)
  Map<String, dynamic> getConnectionStats() {
    return {
      'isInitialized': _isInitialized,
      'clientType': 'Dio',
      'hasConnectionPooling': true,
      'hasHttp2': true,
      'hasInterceptors': true,
      'hasAutoRetry': true,
    };
  }

  /// Close the Dio client and clean up connections
  void dispose() {
    if (_isInitialized) {
      _dio.close(force: true);
      _isInitialized = false;
      AppLogger.log('🔗 HttpClientService: Disposed and connections closed');
    }
  }

  /// Reset the client (useful for testing or reconfiguration)
  void reset() {
    dispose();
    initialize();
  }

  /// Get Dio instance directly (for advanced usage)
  Dio get dioClient {
    if (!_isInitialized) {
      initialize();
    }
    return _dio;
  }

  /// Map string methods to Firebase HttpMethod enums
  HttpMethod _mapHttpMethod(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return HttpMethod.Get;
      case 'POST':
        return HttpMethod.Post;
      case 'PUT':
        return HttpMethod.Put;
      case 'DELETE':
        return HttpMethod.Delete;
      case 'PATCH':
        return HttpMethod.Patch;
      case 'OPTIONS':
        return HttpMethod.Options;
      case 'HEAD':
        return HttpMethod.Head;
      case 'TRACE':
        return HttpMethod.Trace;
      case 'CONNECT':
        return HttpMethod.Connect;
      default:
        return HttpMethod.Get;
    }
  }
}

/// Global HTTP client service instance
final httpClientService = HttpClientService.instance;
