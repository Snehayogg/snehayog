import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/core/services/video_player_config_service.dart';

/// Manages the state and logic for individual video players
class VideoPlayerStateManager extends ChangeNotifier {
  VideoPlayerController? _internalController;
  bool _hasError = false;
  String? _errorMessage;
  bool _isPlaying = false;
  bool _showPlayPauseOverlay = false;
  bool _isSeeking = false;
  bool _isHLS = false;
  bool _isMuted = true;
  double _volume = 0.0;
  bool _isBuffering = false;
  Timer? _overlayTimer;
  Timer? _seekingTimer;

  // Quality configuration
  late VideoQualityPreset _qualityPreset;
  late BufferingConfig _bufferingConfig;
  late PreloadingConfig _preloadingConfig;

  VideoPlayerStateManager() {
    // Initialize with reels feed quality preset by default
    _qualityPreset = VideoPlayerConfigService.getQualityPreset('reels_feed');
    _bufferingConfig =
        VideoPlayerConfigService.getBufferingConfig(_qualityPreset);
    _preloadingConfig =
        VideoPlayerConfigService.getPreloadingConfig(_qualityPreset);
  }

  // Getters
  VideoPlayerController? get internalController => _internalController;
  bool get hasError => _hasError;
  String? get errorMessage => _errorMessage;
  bool get isPlaying => _isPlaying;
  bool get showPlayPauseOverlay => _showPlayPauseOverlay;
  bool get isSeeking => _isSeeking;
  bool get isHLS => _isHLS;
  bool get isMuted => _isMuted; // Add getter for mute state
  double get volume => _volume; // Add getter for volume level
  bool get isBuffering => _isBuffering; // Add getter for buffering state

  // Quality configuration getters
  VideoQualityPreset get qualityPreset => _qualityPreset;
  BufferingConfig get bufferingConfig => _bufferingConfig;
  PreloadingConfig get preloadingConfig => _preloadingConfig;

  /// Update quality preset and related configurations
  void updateQualityPreset(String useCase) {
    _qualityPreset = VideoPlayerConfigService.getQualityPreset(useCase);
    _bufferingConfig =
        VideoPlayerConfigService.getBufferingConfig(_qualityPreset);
    _preloadingConfig =
        VideoPlayerConfigService.getPreloadingConfig(_qualityPreset);
    notifyListeners();
  }

  /// Get optimized video URL for current quality preset
  String getOptimizedVideoUrl(String originalUrl) {
    return VideoPlayerConfigService.getOptimizedVideoUrl(
        originalUrl, _qualityPreset);
  }

  /// Get optimized HTTP headers for current video
  Map<String, String> getOptimizedHeaders(String videoUrl) {
    return VideoPlayerConfigService.getOptimizedHeaders(videoUrl);
  }

  // Video player initialization
  Future<void> initializeController(String videoUrl, bool autoPlay) async {
    try {
      // Clear any previous errors
      clearError();

      // Use optimized video URL for better performance
      final optimizedUrl = getOptimizedVideoUrl(videoUrl);

      _internalController = VideoPlayerController.networkUrl(
        Uri.parse(optimizedUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
        httpHeaders: getOptimizedHeaders(optimizedUrl),
      );

      _internalController!.addListener(_onControllerStateChanged);

      // Add timeout for initialization
      await _internalController!.initialize().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Video initialization timed out');
        },
      );

      // Enhanced buffering optimization for 720p quality
      await _optimizeControllerForSmoothPlayback();

      // Always mute video by default (Instagram-style behavior)
      await _internalController!.setVolume(0.0);

      _initializeVideoController(_internalController!, autoPlay);

      if (autoPlay && _internalController!.value.isInitialized) {
        await _internalController!.play();
        _isPlaying = true;
        notifyListeners();
      }
    } on PlatformException catch (e) {
      print(
          '❌ PlatformException in video initialization: ${e.code} - ${e.message}');
      _handlePlatformException(e);
    } on TimeoutException catch (e) {
      print('❌ TimeoutException in video initialization: $e');
      _setError(
          'Video loading timed out. Please check your connection and try again.');
    } catch (e) {
      print('❌ Error in video initialization: $e');
      _setError(_getUserFriendlyErrorMessage(e.toString()));
    }
  }

  /// Enhanced buffering optimization for smooth playback
  Future<void> _optimizeControllerForSmoothPlayback() async {
    try {
      if (_internalController != null &&
          _internalController!.value.isInitialized) {
        // Pre-buffer the video by seeking to trigger buffering
        await _internalController!.seekTo(Duration.zero);

        // Set optimal playback speed for buffering
        await _internalController!.setPlaybackSpeed(1.0);

        // For HLS videos, add additional buffering
        if (_isHLS) {
          // Trigger HLS segment loading
          await _internalController!.seekTo(const Duration(milliseconds: 100));
          await _internalController!.seekTo(Duration.zero);
        }

        print(
            '🎬 VideoPlayerStateManager: Enhanced buffering optimization applied');
      }
    } catch (e) {
      print('⚠️ VideoPlayerStateManager: Buffering optimization failed: $e');
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
        httpHeaders: getOptimizedHeaders(videoUrl),
      );

      _internalController!.addListener(_onControllerStateChanged);

      await _internalController!.initialize();

      // Enhanced buffering optimization
      await _optimizeControllerForSmoothPlayback();

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
    if (_internalController == null) return;

    try {
      final controllerValue = _internalController!.value;

      // Update playing state
      final wasPlaying = _isPlaying;
      _isPlaying = controllerValue.isPlaying;

      // Update buffering state
      final wasBuffering = _isBuffering;
      _isBuffering = controllerValue.isBuffering;

      // Update error state with better error handling
      if (controllerValue.hasError) {
        final errorDesc =
            controllerValue.errorDescription ?? 'Video player error';
        print('❌ Video controller error: $errorDesc');

        // Check for specific error types
        if (errorDesc.contains('PlatformException')) {
          _setError('Video playback error. Please try again.');
        } else if (errorDesc.contains('network') ||
            errorDesc.contains('connection')) {
          _setError('Network error. Please check your connection.');
        } else if (errorDesc.contains('format') ||
            errorDesc.contains('codec')) {
          _setError(
              'Video format not supported. Please try a different video.');
        } else {
          _setError(errorDesc);
        }
      }

      // Notify listeners if any important state changed
      if (wasPlaying != _isPlaying || wasBuffering != _isBuffering) {
        notifyListeners();
      }
    } catch (e) {
      print('❌ Error in controller state change listener: $e');
      _setError(_getUserFriendlyErrorMessage(e.toString()));
    }
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
    print('🎬 VideoPlayerStateManager: play() called');

    if (_internalController == null) {
      print('❌ VideoPlayerStateManager: No internal controller for play');
      return;
    }

    if (!_internalController!.value.isInitialized) {
      print('❌ VideoPlayerStateManager: Controller not initialized for play');
      return;
    }

    try {
      print('🎬 VideoPlayerStateManager: Attempting to play video');
      await _internalController!.play();
      _isPlaying = true;
      print(
          '🎬 VideoPlayerStateManager: Video play successful, isPlaying: $_isPlaying');
      notifyListeners();
    } on PlatformException catch (e) {
      print('❌ PlatformException in play: ${e.code} - ${e.message}');
      _handlePlatformException(e);
    } catch (e) {
      print('❌ Error in play: $e');
      _setError(_getUserFriendlyErrorMessage(e.toString()));
    }
  }

  Future<void> pause() async {
    print('🎬 VideoPlayerStateManager: pause() called');

    if (_internalController == null) {
      print('❌ VideoPlayerStateManager: No internal controller for pause');
      return;
    }

    if (!_internalController!.value.isInitialized) {
      print('❌ VideoPlayerStateManager: Controller not initialized for pause');
      return;
    }

    try {
      print('🎬 VideoPlayerStateManager: Attempting to pause video');
      await _internalController!.pause();
      _isPlaying = false;
      print(
          '🎬 VideoPlayerStateManager: Video pause successful, isPlaying: $_isPlaying');
      notifyListeners();
    } on PlatformException catch (e) {
      print('❌ PlatformException in pause: ${e.code} - ${e.message}');
      _handlePlatformException(e);
    } catch (e) {
      print('❌ Error in pause: $e');
      _setError(_getUserFriendlyErrorMessage(e.toString()));
    }
  }

  Future<void> seekTo(Duration position) async {
    if (_internalController != null &&
        _internalController!.value.isInitialized) {
      try {
        await _internalController!.seekTo(position);
      } on PlatformException catch (e) {
        print('❌ PlatformException in seek: ${e.code} - ${e.message}');
        _handlePlatformException(e);
      } catch (e) {
        print('❌ Error in seek: $e');
        _setError(_getUserFriendlyErrorMessage(e.toString()));
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

  // Volume control
  Future<void> setVolume(double volume) async {
    if (_internalController != null &&
        _internalController!.value.isInitialized) {
      try {
        await _internalController!.setVolume(volume);
        _volume = volume;
        notifyListeners();
      } on PlatformException catch (e) {
        print('❌ PlatformException in setVolume: ${e.code} - ${e.message}');
        _handlePlatformException(e);
      } catch (e) {
        print('❌ Error in setVolume: $e');
        _setError(_getUserFriendlyErrorMessage(e.toString()));
      }
    }
  }

  Future<void> mute() async {
    if (_internalController != null &&
        _internalController!.value.isInitialized) {
      try {
        await _internalController!.setVolume(0.0);
        _isMuted = true;
        notifyListeners();
      } on PlatformException catch (e) {
        print('❌ PlatformException in mute: ${e.code} - ${e.message}');
        _handlePlatformException(e);
      } catch (e) {
        print('❌ Error in mute: $e');
        _setError(_getUserFriendlyErrorMessage(e.toString()));
      }
    }
  }

  Future<void> unmute() async {
    if (_internalController != null &&
        _internalController!.value.isInitialized) {
      try {
        await _internalController!.setVolume(1.0);
        _isMuted = false;
        _volume = 1.0;
        notifyListeners();
      } on PlatformException catch (e) {
        print('❌ PlatformException in unmute: ${e.code} - ${e.message}');
        _handlePlatformException(e);
      } catch (e) {
        print('❌ Error in unmute: $e');
        _setError(_getUserFriendlyErrorMessage(e.toString()));
      }
    }
  }

  /// Toggle mute/unmute state
  Future<void> toggleMute() async {
    if (_isMuted) {
      await unmute();
    } else {
      await mute();
    }
  }

  /// Toggle play/pause state
  Future<void> togglePlayPause() async {
    print(
        '🎬 VideoPlayerStateManager: togglePlayPause called, current state: $_isPlaying');

    if (_internalController == null) {
      print('❌ VideoPlayerStateManager: No internal controller available');
      return;
    }

    if (!_internalController!.value.isInitialized) {
      print('❌ VideoPlayerStateManager: Controller not initialized');
      return;
    }

    try {
      if (_isPlaying) {
        print('🎬 VideoPlayerStateManager: Pausing video');
        await pause();
      } else {
        print('🎬 VideoPlayerStateManager: Playing video');
        await play();
      }
    } catch (e) {
      print('❌ VideoPlayerStateManager: Error in togglePlayPause: $e');
    }
  }

  // Error handling
  void _setError(String message) {
    _hasError = true;
    _errorMessage = message;
    notifyListeners();
  }

  /// Public method to set error from external sources
  void setError(String message) {
    _setError(message);
  }

  void clearError() {
    _hasError = false;
    _errorMessage = null;
    notifyListeners();
  }

  /// Handle PlatformException errors with specific error codes
  void _handlePlatformException(PlatformException e) {
    String userMessage;

    switch (e.code) {
      case 'VideoError':
        userMessage = 'Video playback error. Please try again.';
        break;
      case 'NetworkError':
        userMessage = 'Network error. Please check your connection.';
        break;
      case 'FormatError':
        userMessage =
            'Video format not supported. Please try a different video.';
        break;
      case 'PermissionError':
        userMessage = 'Permission denied. Please check app permissions.';
        break;
      default:
        userMessage = 'Video error: ${e.message ?? 'Unknown error'}';
    }

    _setError(userMessage);
  }

  /// Convert technical error messages to user-friendly ones
  String _getUserFriendlyErrorMessage(String technicalError) {
    if (technicalError.contains('timeout')) {
      return 'Video loading timed out. Please check your connection.';
    } else if (technicalError.contains('network')) {
      return 'Network error. Please check your internet connection.';
    } else if (technicalError.contains('format')) {
      return 'Video format not supported. Please try a different video.';
    } else if (technicalError.contains('permission')) {
      return 'Permission denied. Please check app permissions.';
    } else if (technicalError.contains('not found')) {
      return 'Video not found. Please try again later.';
    } else if (technicalError.contains('server')) {
      return 'Server error. Please try again later.';
    } else {
      return 'Video error. Please try again.';
    }
  }

  /// Check if error is network-related and can be retried
  bool get isNetworkError {
    if (!_hasError || _errorMessage == null) return false;

    final error = _errorMessage!.toLowerCase();
    return error.contains('network') ||
        error.contains('connection') ||
        error.contains('timeout') ||
        error.contains('unreachable');
  }

  /// Check if error is recoverable (can be retried)
  bool get isRecoverableError {
    if (!_hasError || _errorMessage == null) return false;

    final error = _errorMessage!.toLowerCase();
    return !error.contains('format') &&
        !error.contains('codec') &&
        !error.contains('permission') &&
        !error.contains('not found');
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
