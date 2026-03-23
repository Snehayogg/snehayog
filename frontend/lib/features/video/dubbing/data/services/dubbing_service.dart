import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vayu/features/auth/data/services/authservices.dart';
import 'package:vayu/shared/config/app_config.dart';
import 'package:vayu/shared/utils/app_logger.dart';

/// Status of a dubbing job
enum DubbingStatus {
  idle,
  checking, // Checking if already dubbed / requesting
  queued,
  downloadingVideo,
  checkingContent, // Whisper speech pre-check
  extractingAudio,
  transcribing,
  translating,
  synthesizing,
  muxing,
  uploading,
  completed,
  notSuitable, // Music / dance / no speech
  failed,
}

class DubbingResult {
  final DubbingStatus status;
  final int progress; // 0–100
  final String? dubbedUrl;
  final String? language;
  final bool fromCache;
  final String? reason; // for notSuitable
  final String? error; // for failed

  const DubbingResult({
    required this.status,
    this.progress = 0,
    this.dubbedUrl,
    this.language,
    this.fromCache = false,
    this.reason,
    this.error,
  });

  bool get isDone =>
      status == DubbingStatus.completed ||
      status == DubbingStatus.notSuitable ||
      status == DubbingStatus.failed;

  String get statusLabel {
    switch (status) {
      case DubbingStatus.idle:
        return 'Smart Dub';
      case DubbingStatus.checking:
        return 'Checking...';
      case DubbingStatus.queued:
        return 'Starting...';
      case DubbingStatus.downloadingVideo:
        return 'Downloading...';
      case DubbingStatus.checkingContent:
        return 'Analysing...';
      case DubbingStatus.extractingAudio:
        return 'Processing audio...';
      case DubbingStatus.transcribing:
        return 'Transcribing...';
      case DubbingStatus.translating:
        return 'Translating...';
      case DubbingStatus.synthesizing:
        return 'Generating voice...';
      case DubbingStatus.muxing:
        return 'Finalizing...';
      case DubbingStatus.uploading:
        return 'Uploading...';
      case DubbingStatus.completed:
        return 'Play Dubbed';
      case DubbingStatus.notSuitable:
        return 'Not dub-able';
      case DubbingStatus.failed:
        return 'Failed';
    }
  }
}

class DubbingService {
  static final DubbingService _instance = DubbingService._internal();
  factory DubbingService() => _instance;
  DubbingService._internal();

  /// Active polling subscriptions keyed by videoId
  final Map<String, StreamController<DubbingResult>> _controllers = {};

  String get _baseUrl => NetworkHelper.apiBaseUrl;

  Future<Map<String, String>> _authHeaders() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  /// Returns the current cached dubbed URL for a video if available, else null.
  String? getCachedDubbedUrl(Map<String, String>? dubbedUrls, {String lang = 'english'}) {
    return dubbedUrls?[lang];
  }

  /// Request dubbing for [videoId]. Returns a stream of [DubbingResult] updates.
  /// - If already dubbed → emits [completed] immediately with the cached URL
  /// - If music/dance → emits [notSuitable]
  /// - Otherwise → starts polling and emits progress updates until done
  Stream<DubbingResult> requestDub(String videoId, {String targetLanguage = 'english'}) {
    // If already being processed, return existing stream
    if (_controllers.containsKey(videoId)) {
      return _controllers[videoId]!.stream;
    }

    final controller = StreamController<DubbingResult>.broadcast();
    _controllers[videoId] = controller;

    _startDubbing(controller, videoId, targetLanguage);
    return controller.stream;
  }

  void _startDubbing(
    StreamController<DubbingResult> controller,
    String videoId,
    String targetLanguage,
  ) async {
    try {
      controller.add(const DubbingResult(status: DubbingStatus.checking));

      final headers = await _authHeaders();
      final response = await http
          .post(
            Uri.parse('$_baseUrl/dubbing/request'),
            headers: headers,
            body: jsonEncode({'videoId': videoId, 'targetLanguage': targetLanguage}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200 && response.statusCode != 202) {
        controller.add(DubbingResult(
          status: DubbingStatus.failed,
          error: 'Server error: ${response.statusCode}',
        ));
        _cleanup(videoId);
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final status = data['status'] as String? ?? '';

      // Instant responses
      if (status == 'completed') {
        controller.add(DubbingResult(
          status: DubbingStatus.completed,
          progress: 100,
          dubbedUrl: data['dubbedUrl'] as String?,
          language: data['language'] as String?,
          fromCache: data['fromCache'] == true,
        ));
        _cleanup(videoId);
        return;
      }

      if (status == 'not_suitable') {
        controller.add(DubbingResult(
          status: DubbingStatus.notSuitable,
          reason: data['reason'] as String?,
        ));
        _cleanup(videoId);
        return;
      }

      // Background task — poll for progress
      final taskId = data['taskId'] as String?;
      if (taskId == null) {
        controller.add(const DubbingResult(
          status: DubbingStatus.failed,
          error: 'No task ID returned',
        ));
        _cleanup(videoId);
        return;
      }

      controller.add(const DubbingResult(status: DubbingStatus.queued, progress: 2));
      await _pollUntilDone(controller, videoId, taskId);
    } catch (e) {
      AppLogger.log('❌ DubbingService: Error requesting dub for $videoId: $e');
      controller.add(DubbingResult(
        status: DubbingStatus.failed,
        error: e.toString(),
      ));
      _cleanup(videoId);
    }
  }

  Future<void> _pollUntilDone(
    StreamController<DubbingResult> controller,
    String videoId,
    String taskId,
  ) async {
    const pollInterval = Duration(seconds: 4);
    const maxAttempts = 60; // 4s * 60 = 4 minutes max

    for (int i = 0; i < maxAttempts; i++) {
      if (controller.isClosed) return;
      await Future.delayed(pollInterval);

      try {
        final headers = await _authHeaders();
        final res = await http
            .get(Uri.parse('$_baseUrl/dubbing/status/$taskId'), headers: headers)
            .timeout(const Duration(seconds: 10));

        if (res.statusCode != 200) continue;

        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final serverStatus = data['status'] as String? ?? '';
        final progress = (data['progress'] as num?)?.toInt() ?? 0;

        final dubbingStatus = _parseStatus(serverStatus);
        controller.add(DubbingResult(
          status: dubbingStatus,
          progress: progress,
          dubbedUrl: data['dubbedUrl'] as String?,
          language: data['language'] as String?,
          fromCache: data['fromCache'] == true,
          reason: data['reason'] as String?,
          error: data['error'] as String?,
        ));

        if (dubbingStatus == DubbingStatus.completed ||
            dubbingStatus == DubbingStatus.notSuitable ||
            dubbingStatus == DubbingStatus.failed) {
          _cleanup(videoId);
          return;
        }
      } catch (e) {
        AppLogger.log('⚠️ DubbingService: Poll error for $taskId: $e');
        // Keep polling — transient network errors are common
      }
    }

    // Timeout
    controller.add(const DubbingResult(
      status: DubbingStatus.failed,
      error: 'Dubbing timed out. The video may be too long.',
    ));
    _cleanup(videoId);
  }

  DubbingStatus _parseStatus(String s) {
    switch (s) {
      case 'starting':
      case 'queued':
        return DubbingStatus.queued;
      case 'downloading':
        return DubbingStatus.downloadingVideo;
      case 'checking_content':
        return DubbingStatus.checkingContent;
      case 'extracting_audio':
        return DubbingStatus.extractingAudio;
      case 'transcribing':
        return DubbingStatus.transcribing;
      case 'translating':
        return DubbingStatus.translating;
      case 'synthesizing':
        return DubbingStatus.synthesizing;
      case 'muxing':
        return DubbingStatus.muxing;
      case 'uploading':
        return DubbingStatus.uploading;
      case 'completed':
        return DubbingStatus.completed;
      case 'not_suitable':
        return DubbingStatus.notSuitable;
      case 'failed':
        return DubbingStatus.failed;
      default:
        return DubbingStatus.queued;
    }
  }

  void _cleanup(String videoId) {
    final ctrl = _controllers.remove(videoId);
    ctrl?.close();
  }

  /// Cancel dubbing polling for a video
  void cancel(String videoId) => _cleanup(videoId);
}
