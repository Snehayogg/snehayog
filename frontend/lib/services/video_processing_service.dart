import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'network_service.dart';

/// Service to track video processing progress
class VideoProcessingService {
  static VideoProcessingService? _instance;
  static VideoProcessingService get instance =>
      _instance ??= VideoProcessingService._();

  VideoProcessingService._();

  final NetworkService _networkService = NetworkService.instance;
  final Map<String, StreamController<VideoProcessingStatus>>
      _statusControllers = {};

  /// Get processing status for a video
  Future<VideoProcessingStatus> getProcessingStatus(String videoId) async {
    try {
      final token = await _getAuthToken();
      if (token == null) {
        throw Exception('User not authenticated');
      }

      final response = await _networkService.makeRequest(
        (baseUrl) => '$baseUrl/api/upload/video/$videoId/status',
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return VideoProcessingStatus.fromJson(data);
      } else {
        throw Exception(
            'Failed to get processing status: ${response.statusCode}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('❌ VideoProcessingService: Error getting status: $e');
      }
      rethrow;
    }
  }

  /// Stream processing progress for a video
  Stream<VideoProcessingStatus> pollProgress(String videoId) {
    // Return existing stream if available
    if (_statusControllers.containsKey(videoId)) {
      return _statusControllers[videoId]!.stream;
    }

    // Create new stream controller
    final controller = StreamController<VideoProcessingStatus>.broadcast();
    _statusControllers[videoId] = controller;

    // Start polling
    _startPolling(videoId, controller);

    return controller.stream;
  }

  /// Start polling for processing status
  void _startPolling(
      String videoId, StreamController<VideoProcessingStatus> controller) {
    Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final status = await getProcessingStatus(videoId);

        if (!controller.isClosed) {
          controller.add(status);
        }

        // Stop polling when processing is complete or failed
        if (status.processingStatus == 'completed' ||
            status.processingStatus == 'failed') {
          timer.cancel();
          controller.close();
          _statusControllers.remove(videoId);
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ VideoProcessingService: Polling error: $e');
        }
        // Continue polling even on error
      }
    });
  }

  /// Stop polling for a specific video
  void stopPolling(String videoId) {
    final controller = _statusControllers[videoId];
    if (controller != null && !controller.isClosed) {
      controller.close();
      _statusControllers.remove(videoId);
    }
  }

  /// Stop all polling
  void stopAllPolling() {
    for (final controller in _statusControllers.values) {
      if (!controller.isClosed) {
        controller.close();
      }
    }
    _statusControllers.clear();
  }

  /// Get auth token
  Future<String?> _getAuthToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('jwt_token');
    } catch (e) {
      if (kDebugMode) {
        print('❌ VideoProcessingService: Error getting token: $e');
      }
      return null;
    }
  }

  /// Dispose resources
  void dispose() {
    stopAllPolling();
  }
}

/// Video processing status model
class VideoProcessingStatus {
  final String processingStatus;
  final int processingProgress;
  final String? processingError;
  final bool hasMultipleQualities;
  final int qualitiesGenerated;

  VideoProcessingStatus({
    required this.processingStatus,
    required this.processingProgress,
    this.processingError,
    required this.hasMultipleQualities,
    required this.qualitiesGenerated,
  });

  factory VideoProcessingStatus.fromJson(Map<String, dynamic> json) {
    final video = json['video'] as Map<String, dynamic>? ?? {};

    return VideoProcessingStatus(
      processingStatus: video['processingStatus'] as String? ?? 'unknown',
      processingProgress: video['processingProgress'] as int? ?? 0,
      processingError: video['processingError'] as String?,
      hasMultipleQualities: video['hasMultipleQualities'] as bool? ?? false,
      qualitiesGenerated: video['qualitiesGenerated'] as int? ?? 0,
    );
  }

  bool get isProcessing => processingStatus == 'processing';
  bool get isCompleted => processingStatus == 'completed';
  bool get isFailed => processingStatus == 'failed';
  bool get isPending => processingStatus == 'pending';

  @override
  String toString() {
    return 'VideoProcessingStatus(status: $processingStatus, progress: $processingProgress%)';
  }
}
