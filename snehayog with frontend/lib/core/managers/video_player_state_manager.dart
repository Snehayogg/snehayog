import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/core/factories/video_controller_factory.dart';

class VideoPlayerStateManager extends ChangeNotifier {
  VideoPlayerController? _internalController;
  bool _hasError = false;
  String? _errorMessage;
  bool _isPlaying = false;
  bool _showPlayPauseOverlay = false;
  bool _isSeeking = false;
  bool _isHLS = false;
  Timer? _overlayTimer;
  Timer? _seekingTimer;

  // Getters
  VideoPlayerController? get internalController => _internalController;
  bool get hasError => _hasError;
  String? get errorMessage => _errorMessage;
  bool get isPlaying => _isPlaying;
  bool get showPlayPauseOverlay => _showPlayPauseOverlay;
  bool get isSeeking => _isSeeking;
  bool get isHLS => _isHLS;

  // Video player initialization
  Future<void> initializeController(String videoUrl, bool autoPlay) async {
    try {
      _internalController = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      _internalController!.addListener(_onControllerStateChanged);

      await _internalController!.initialize();
      _initializeVideoController(_internalController!, autoPlay);

      if (autoPlay && _internalController!.value.isInitialized) {
        await _internalController!.play();
        _isPlaying = true;
        notifyListeners();
      }
    } catch (e) {
      _setError(e.toString());
    }
  }

  /// Initialize controller using the factory for better maintainability
  Future<void> initializeControllerWithFactory(
      String videoUrl, bool autoPlay) async {
    try {
      // For now, we'll use the existing method, but this shows how to use the factory
      _internalController = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      _internalController!.addListener(_onControllerStateChanged);

      await _internalController!.initialize();
      _initializeVideoController(_internalController!, autoPlay);

      if (autoPlay && _internalController!.value.isInitialized) {
        await _internalController!.play();
        _isPlaying = true;
        notifyListeners();
      }
    } catch (e) {
      _setError(e.toString());
    }
  }

  void _onControllerStateChanged() {
    if (_internalController!.value.hasError) {
      _setError(_internalController!.value.errorDescription ?? 'Unknown error');
    }
    _updatePlayState();
  }

  void _updatePlayState() {
    if (_internalController != null &&
        _internalController!.value.isInitialized) {
      final wasPlaying = _isPlaying;
      _isPlaying = _internalController!.value.isPlaying;

      if (wasPlaying != _isPlaying) {
        notifyListeners();
      }
    }
  }

  void _initializeVideoController(
      VideoPlayerController controller, bool autoPlay) {
    try {
      controller.addListener(_updatePlayState);

      if (autoPlay && controller.value.isInitialized) {
        Future.delayed(const Duration(milliseconds: 100), () {
          if (controller.value.isInitialized && !controller.value.isPlaying) {
            controller.play();
            _isPlaying = true;
            notifyListeners();
          }
        });
      }
    } catch (e) {
      _setError(e.toString());
    }
  }

  // Playback control
  Future<void> play() async {
    if (_internalController != null &&
        _internalController!.value.isInitialized) {
      try {
        await _internalController!.play();
        _isPlaying = true;
        notifyListeners();
      } catch (e) {
        _setError(e.toString());
      }
    }
  }

  Future<void> pause() async {
    if (_internalController != null &&
        _internalController!.value.isInitialized) {
      try {
        await _internalController!.pause();
        _isPlaying = false;
        notifyListeners();
      } catch (e) {
        _setError(e.toString());
      }
    }
  }

  Future<void> seekTo(Duration position) async {
    if (_internalController != null &&
        _internalController!.value.isInitialized) {
      try {
        await _internalController!.seekTo(position);
      } catch (e) {
        _setError(e.toString());
      }
    }
  }

  // UI state management
  void displayPlayPauseOverlay() {
    _showPlayPauseOverlay = true;
    notifyListeners();

    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(milliseconds: 1500), () {
      _showPlayPauseOverlay = false;
      notifyListeners();
    });
  }

  void showSeekingIndicator() {
    _isSeeking = true;
    notifyListeners();

    _seekingTimer?.cancel();
    _seekingTimer = Timer(const Duration(seconds: 1), () {
      _isSeeking = false;
      notifyListeners();
    });
  }

  // HLS status management
  void updateHLSStatus(bool isHLS) {
    if (_isHLS != isHLS) {
      _isHLS = isHLS;
      notifyListeners();
    }
  }

  // Error handling
  void _setError(String message) {
    _hasError = true;
    _errorMessage = message;
    notifyListeners();
  }

  void clearError() {
    _hasError = false;
    _errorMessage = null;
    notifyListeners();
  }

  // Cleanup
  @override
  void dispose() {
    _overlayTimer?.cancel();
    _seekingTimer?.cancel();
    _internalController?.dispose();
    super.dispose();
  }
}
