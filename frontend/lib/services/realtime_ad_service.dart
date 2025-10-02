import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:snehayog/config/app_config.dart';

/// Service for real-time ad updates using Server-Sent Events (SSE)
class RealtimeAdService {
  static final RealtimeAdService _instance = RealtimeAdService._internal();
  factory RealtimeAdService() => _instance;
  RealtimeAdService._internal();

  static String get _baseUrl => AppConfig.baseUrl;

  StreamController<Map<String, dynamic>>? _adUpdateController;
  StreamSubscription<String>? _sseSubscription;
  bool _isConnected = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const int _maxReconnectAttempts = 5;

  /// Stream of ad updates
  Stream<Map<String, dynamic>> get adUpdates {
    _adUpdateController ??= StreamController<Map<String, dynamic>>.broadcast();
    return _adUpdateController!.stream;
  }

  /// Connect to real-time ad updates
  Future<void> connect() async {
    if (_isConnected) {
      print('📡 RealtimeAdService: Already connected');
      return;
    }

    try {
      print('📡 RealtimeAdService: Connecting to ad updates...');

      final request = http.Request('GET', Uri.parse('$_baseUrl/api/ads/ws'));
      request.headers['Accept'] = 'text/event-stream';
      request.headers['Cache-Control'] = 'no-cache';

      final client = http.Client();
      final streamedResponse = await client.send(request);

      if (streamedResponse.statusCode == 200) {
        _isConnected = true;
        _reconnectAttempts = 0;
        print('✅ RealtimeAdService: Connected to ad updates');

        _sseSubscription = streamedResponse.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .listen(
              _handleSSEMessage,
              onError: _handleConnectionError,
              onDone: _handleConnectionClosed,
            );
      } else {
        print(
            '❌ RealtimeAdService: Connection failed with status ${streamedResponse.statusCode}');
        _scheduleReconnect();
      }
    } catch (e) {
      print('❌ RealtimeAdService: Connection error: $e');
      _scheduleReconnect();
    }
  }

  /// Handle incoming SSE messages
  void _handleSSEMessage(String line) {
    if (line.startsWith('data: ')) {
      try {
        final jsonData = line.substring(6); // Remove 'data: ' prefix
        final Map<String, dynamic> data = json.decode(jsonData);

        print('📡 RealtimeAdService: Received update: ${data['type']}');
        _adUpdateController?.add(data);
      } catch (e) {
        print('❌ RealtimeAdService: Error parsing SSE message: $e');
      }
    }
  }

  /// Handle connection errors
  void _handleConnectionError(dynamic error) {
    print('❌ RealtimeAdService: Connection error: $error');
    _isConnected = false;
    _scheduleReconnect();
  }

  /// Handle connection closed
  void _handleConnectionClosed() {
    print('📡 RealtimeAdService: Connection closed');
    _isConnected = false;
    _scheduleReconnect();
  }

  /// Schedule reconnection attempt
  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) {
      print('❌ RealtimeAdService: Max reconnection attempts reached');
      return;
    }

    _reconnectAttempts++;
    final delay =
        Duration(seconds: _reconnectAttempts * 2); // Exponential backoff

    print(
        '🔄 RealtimeAdService: Reconnecting in ${delay.inSeconds}s (attempt $_reconnectAttempts/$_maxReconnectAttempts)');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      connect();
    });
  }

  /// Disconnect from real-time updates
  void disconnect() {
    print('📡 RealtimeAdService: Disconnecting...');

    _reconnectTimer?.cancel();
    _sseSubscription?.cancel();
    _adUpdateController?.close();

    _isConnected = false;
    _reconnectAttempts = 0;
    _adUpdateController = null;
    _sseSubscription = null;
  }

  /// Check if connected
  bool get isConnected => _isConnected;

  /// Dispose resources
  void dispose() {
    disconnect();
  }
}
