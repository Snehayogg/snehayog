import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/core/services/video_url_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'package:snehayog/services/ad_impression_service.dart';

class VideoPlayerWidget extends StatefulWidget {
  final VideoModel video;
  final bool play;
  final VideoPlayerController? controller;

  const VideoPlayerWidget({
    Key? key,
    required this.video,
    required this.play,
    this.controller,
  }) : super(key: key);

  @override
  State<VideoPlayerWidget> createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isMuted = false;
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _loopCheckTimer;
  bool _showTapFeedback = false;
  Timer? _feedbackTimer;
  final AdImpressionService _adImpressionService = AdImpressionService();

  // **NEW: Add retry counter to prevent infinite loops**
  int _retryCount = 0;
  static const int _maxRetries = 3;

  /// **NEW: Check if widget is still mounted and valid**
  bool get _isWidgetValid => mounted && !_isDisposed;

  bool _isDisposed = false;

  @override
  void initState() {
    super.initState();
    print(
        '🎬 VideoPlayerWidget: Initializing for video: ${widget.video.videoName}');

    // DEBUG: Add this to see what's happening
    print(
        '🎬 VideoPlayerWidget: Controller provided: ${widget.controller != null}');
    print('🎬 VideoPlayerWidget: Video URL: ${widget.video.videoUrl}');
    print('🎬 VideoPlayerWidget: HLS URL: ${widget.video.hlsPlaylistUrl}');

    if (widget.controller == null) {
      print(
          '🎬 VideoPlayerWidget: No controller provided, initializing new one...');
      _initializeController();
    } else {
      print('🎬 VideoPlayerWidget: Using provided controller...');
      _controller = widget.controller;
      _setupController();
    }
  }

  /// **NEW: Reset retry counter when initialization succeeds**
  void _resetRetryCounter() {
    _retryCount = 0;
    print('✅ VideoPlayerWidget: Retry counter reset to 0');
  }

  /// **NEW: Enhanced initialization with better error handling and fallbacks**
  Future<void> _initializeController() async {
    try {
      print(
          '🎬 VideoPlayerWidget: Starting enhanced controller initialization...');

      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final videoUrl = VideoUrlService.getBestVideoUrl(widget.video);
      print('🎬 VideoPlayerWidget: Best video URL: $videoUrl');

      // **NEW: Validate video URL before creating controller**
      if (videoUrl.isEmpty) {
        throw Exception('Invalid video URL: URL is empty');
      }

      // **CRITICAL FIX: Clear any existing controller first**
      if (_controller != null) {
        await _safeDisposeController();
      }

      // **CRITICAL FIX: Create controller with timeout protection**
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      print('🎬 VideoPlayerWidget: Controller created, setting up...');

      // **NEW: Add timeout for initialization to prevent hanging**
      await _setupControllerWithTimeout();

      // **CRITICAL FIX: Reset retry counter on success**
      _resetRetryCounter();

      setState(() {
        _isLoading = false;
      });

      print('✅ VideoPlayerWidget: Enhanced initialization complete!');
    } catch (e) {
      print('❌ VideoPlayerWidget: Enhanced initialization failed: $e');

      // **CRITICAL FIX: Clear controller on error to prevent null access**
      if (_controller != null) {
        await _safeDisposeController();
      }

      // **NEW: Enhanced retry logic with exponential backoff - but prevent infinite loops**
      if (_errorMessage == null &&
          _isWidgetValid &&
          _retryCount < _maxRetries) {
        _retryCount++;
        print(
            '🔄 VideoPlayerWidget: First initialization failed, retrying with backoff... (Attempt $_retryCount/$_maxRetries)');
        await _retryInitializationWithBackoff();
      } else if (_isWidgetValid) {
        setState(() {
          _errorMessage =
              'Failed to initialize video after $_retryCount attempts: $e';
          _isLoading = false;
        });
        print(
            '❌ VideoPlayerWidget: Max retries reached, showing error to user');
      }
    }
  }

  /// **NEW: Setup controller with timeout protection**
  Future<void> _setupControllerWithTimeout() async {
    if (_controller == null) {
      print('❌ VideoPlayerWidget: Cannot setup null controller');
      return;
    }

    try {
      // Add listener for state changes
      _controller!.addListener(_onControllerStateChanged);

      // **NEW: Add timeout for initialization to prevent hanging**
      final initializationFuture = _controller!.initialize();
      final timeoutFuture = Future.delayed(const Duration(seconds: 10));

      await Future.any([initializationFuture, timeoutFuture]);

      // **CRITICAL FIX: Check if controller is still valid after initialization**
      if (_controller == null) {
        throw Exception('Controller was disposed during initialization');
      }

      // Check if initialization actually completed
      if (!_controller!.value.isInitialized) {
        throw Exception('Video initialization timed out');
      }

      // Set looping - this should work but let's also add manual completion handling
      _controller!.setLooping(true);

      // Add completion listener to manually restart video if looping fails
      _controller!.addListener(_onVideoCompleted);

      // **CRITICAL: Set initial volume to 0 to prevent audio leaks**
      _controller!.setVolume(0.0);

      // Auto-play if requested
      if (widget.play && _controller != null) {
        await _controller!.play();
        _isPlaying = true;
        // **CRITICAL: Unmute only after successful play**
        _controller!.setVolume(1.0);
      }

      setState(() {
        _isInitialized = true;
        _isLoading = false;
      });

      // Start periodic loop checking as backup
      _startLoopCheckTimer();

      print('✅ VideoPlayerWidget: Controller setup completed successfully');
    } catch (e) {
      print('❌ VideoPlayerWidget: Controller setup failed: $e');

      // **CRITICAL FIX: Clear controller on setup failure**
      if (_controller != null) {
        await _safeDisposeController();
      }

      rethrow;
    }
  }

  /// **NEW: Retry initialization with exponential backoff**
  Future<void> _retryInitializationWithBackoff() async {
    try {
      print('🔄 VideoPlayerWidget: Retrying with exponential backoff...');

      // **CRITICAL FIX: Check if widget is still valid**
      if (!_isWidgetValid) {
        print('❌ VideoPlayerWidget: Widget disposed, stopping retry');
        return;
      }

      // **CRITICAL FIX: Wait longer between retries to prevent rapid failures**
      final delay = Duration(milliseconds: 1000 * _retryCount);
      print(
          '🔄 VideoPlayerWidget: Waiting ${delay.inMilliseconds}ms before retry...');
      await Future.delayed(delay);

      // **CRITICAL FIX: Check again if widget is still valid after delay**
      if (!_isWidgetValid) {
        print(
            '❌ VideoPlayerWidget: Widget disposed during delay, stopping retry');
        return;
      }

      // **CRITICAL FIX: Ensure controller is completely cleared before retry**
      if (_controller != null) {
        await _safeDisposeController();
      }

      // **CRITICAL FIX: Reset state before retry**
      if (_isWidgetValid) {
        setState(() {
          _isLoading = true;
          _errorMessage = null;
        });
      }

      // Try initialization again - but prevent infinite loops
      if (_isWidgetValid) {
        await _initializeController();
      }
    } catch (e) {
      print('❌ VideoPlayerWidget: Retry with backoff failed: $e');

      // **CRITICAL FIX: Clear controller on retry failure**
      if (_controller != null) {
        await _safeDisposeController();
      }

      if (_isWidgetValid) {
        setState(() {
          _errorMessage = 'Failed to initialize video after retry: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _setupController() async {
    if (_controller == null) {
      print('❌ VideoPlayerWidget: Cannot setup null controller');
      return;
    }

    try {
      // Add listener for state changes
      _controller!.addListener(_onControllerStateChanged);

      // **NEW: Add timeout for initialization to prevent hanging**
      final initializationFuture = _controller!.initialize();
      final timeoutFuture = Future.delayed(const Duration(seconds: 10));

      await Future.any([initializationFuture, timeoutFuture]);

      // **CRITICAL FIX: Check if controller is still valid after initialization**
      if (_controller == null) {
        throw Exception('Controller was disposed during initialization');
      }

      // Check if initialization actually completed
      if (!_controller!.value.isInitialized) {
        throw Exception('Video initialization timed out');
      }

      // Set looping - this should work but let's also add manual completion handling
      _controller!.setLooping(true);

      // Add completion listener to manually restart video if looping fails
      _controller!.addListener(_onVideoCompleted);

      // Set initial volume - videos start with sound (unmuted)
      _controller!.setVolume(1.0);

      // Auto-play if requested
      if (widget.play) {
        await _controller!.play();
        _isPlaying = true;
      }

      setState(() {
        _isInitialized = true;
        _isLoading = false;
      });

      // Start periodic loop checking as backup
      _startLoopCheckTimer();

      print(
          '🎬 VideoPlayerWidget: Controller setup complete with looping enabled');
    } catch (e) {
      print('❌ VideoPlayerWidget: Error in setup: $e');

      // **CRITICAL FIX: Clear controller on setup failure**
      if (_controller != null) {
        await _safeDisposeController();
      }

      // **NEW: Handle setup errors with retry logic**
      if (_errorMessage == null && _retryCount < _maxRetries) {
        print('🔄 VideoPlayerWidget: Setup failed, retrying...');
        await _retryInitializationWithBackoff();
      } else {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  /// **NEW: Enhanced resource cleanup to prevent memory leaks**
  void _cleanupResources() {
    print('🧹 VideoPlayerWidget: Cleaning up resources...');

    // Cancel all timers
    _loopCheckTimer?.cancel();
    _feedbackTimer?.cancel();
    _loopCheckTimer = null;
    _feedbackTimer = null;

    // Clear controller safely
    if (_controller != null) {
      _safeDisposeController();
    }

    // Reset all state variables
    _isInitialized = false;
    _isPlaying = false;
    _isMuted = false;
    _isLoading = false;
    _showTapFeedback = false;
    _errorMessage = null;

    print('✅ VideoPlayerWidget: Resources cleaned up');
  }

  /// **NEW: Optimized loop check timer with better performance**
  void _startLoopCheckTimer() {
    // Cancel existing timer first
    _loopCheckTimer?.cancel();

    // **CRITICAL FIX: Use longer interval to reduce CPU usage**
    _loopCheckTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      // **CRITICAL FIX: Check if widget is still valid before processing**
      if (!_isWidgetValid || _controller == null) {
        timer.cancel();
        return;
      }

      try {
        if (_controller!.value.isInitialized && _controller!.value.isPlaying) {
          final remainingTime =
              _controller!.value.duration - _controller!.value.position;
          if (remainingTime.inMilliseconds <= 500) {
            // Increased threshold
            print(
                '🎬 VideoPlayerWidget: Timer detected video near end, restarting...');
            _restartVideo();
          }
        }
      } catch (e) {
        print('❌ VideoPlayerWidget: Error in loop check timer: $e');
        timer.cancel(); // Stop timer on error
      }
    });
  }

  void _restartVideo() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    print('🎬 VideoPlayerWidget: Restarting video from beginning');
    _controller!.seekTo(Duration.zero);

    Future.delayed(const Duration(milliseconds: 100), () {
      if (_controller != null && _controller!.value.isInitialized) {
        _controller!.play();
        _isPlaying = true;
        setState(() {});
        print('🎬 VideoPlayerWidget: Video restarted successfully via timer');
      }
    });
  }

  void _onControllerStateChanged() {
    if (_controller == null) return;

    final wasPlaying = _isPlaying;
    _isPlaying = _controller!.value.isPlaying;

    if (wasPlaying != _isPlaying) {
      setState(() {});
      print('🎬 VideoPlayerWidget: Play state changed to: $_isPlaying');
    }
  }

  /// **NEW: Handle video completion safely**
  void _onVideoCompleted() {
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        // Check if video has reached the end
        if (_controller!.value.position >= _controller!.value.duration) {
          print('🎬 VideoPlayerWidget: Video completed, restarting...');

          // Restart video from beginning
          _controller!.seekTo(Duration.zero);

          // Small delay to ensure seek completes
          Future.delayed(const Duration(milliseconds: 50), () {
            if (_controller != null && _controller!.value.isInitialized) {
              _controller!.play();
              _isPlaying = true;
              setState(() {});
              print('🎬 VideoPlayerWidget: Video restarted successfully');
            }
          });
        }
      } catch (e) {
        print('❌ VideoPlayerWidget: Error handling video completion: $e');
      }
    }
  }

  /// **NEW: Toggle play/pause with visual feedback**
  void _togglePlayPause() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      if (_isPlaying) {
        _controller!.pause();
        _isPlaying = false;
      } else {
        _controller!.play();
        _isPlaying = true;
      }

      // Show tap feedback
      setState(() {
        _showTapFeedback = true;
      });

      // Hide feedback after animation
      _feedbackTimer?.cancel();
      _feedbackTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          setState(() {
            _showTapFeedback = false;
          });
        }
      });

      print('🎬 VideoPlayerWidget: Play state toggled to: $_isPlaying');
    } catch (e) {
      print('❌ VideoPlayerWidget: Error toggling play/pause: $e');
    }
  }

  void _showTapFeedbackIndicator() {
    setState(() {
      _showTapFeedback = true;
    });

    // Cancel previous timer if exists
    _feedbackTimer?.cancel();

    // Hide feedback after 1 second
    _feedbackTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _showTapFeedback = false;
        });
      }
    });
  }

  void _toggleMute() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    setState(() {
      if (_isMuted) {
        // Unmute - set volume to 1.0
        _controller!.setVolume(1.0);
        _isMuted = false;
        print('🎬 VideoPlayerWidget: Video unmuted');
      } else {
        // Mute - set volume to 0.0
        _controller!.setVolume(0.0);
        _isMuted = true;
        print('🎬 VideoPlayerWidget: Video muted');
      }
    });
  }

  @override
  void dispose() {
    print(
        '🗑️ VideoPlayerWidget: Disposing widget for video: ${widget.video.videoName}');

    _isDisposed = true;

    // **CRITICAL FIX: Use comprehensive cleanup method**
    _cleanupResources();

    super.dispose();
    print('✅ VideoPlayerWidget: Disposal completed');
  }

  /// **NEW: Safe controller disposal method**
  Future<void> _safeDisposeController() async {
    if (_controller != null) {
      try {
        // Remove listeners first to prevent memory leaks
        _controller!.removeListener(_onControllerStateChanged);
        _controller!.removeListener(_onVideoCompleted);

        // Pause and dispose
        if (_controller!.value.isInitialized) {
          await _controller!.pause();
        }
        await _controller!.dispose();
        print('✅ VideoPlayerWidget: Controller disposed safely');
      } catch (e) {
        print(
            '⚠️ VideoPlayerWidget: Error during safe controller disposal: $e');
      } finally {
        _controller = null;
      }
    }
  }

  @override
  void didUpdateWidget(VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // **CRITICAL: Handle play state changes to prevent audio leaks**
    if (oldWidget.play != widget.play) {
      _handlePlayStateChange();
    }

    // **CRITICAL: Handle controller changes to prevent memory leaks**
    if (oldWidget.controller != widget.controller) {
      _handleControllerChange();
    }
  }

  /// **NEW: Handle play state changes to prevent audio leaks**
  void _handlePlayStateChange() {
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        if (widget.play) {
          // **CRITICAL: Unmute before playing to ensure audio works**
          _controller!.setVolume(1.0);
          _controller!.play();
          _isPlaying = true;
          print('🎬 VideoPlayerWidget: Video started playing');
        } else {
          // **CRITICAL: Pause and mute to prevent audio leaks**
          _controller!.pause();
          _controller!.setVolume(0.0);
          _isPlaying = false;
          print('🎬 VideoPlayerWidget: Video paused and muted');
        }

        setState(() {});
      } catch (e) {
        print('❌ VideoPlayerWidget: Error handling play state change: $e');
      }
    }
  }

  /// **NEW: Handle controller changes to prevent memory leaks**
  void _handleControllerChange() {
    // **CRITICAL: Clean up old controller if it was created by this widget**
    if (widget.controller == null && _controller != null) {
      try {
        _safeDisposeController();
        print('🗑️ VideoPlayerWidget: Old controller disposed due to change');
      } catch (e) {
        print('❌ VideoPlayerWidget: Error disposing old controller: $e');
      }
    }

    // **CRITICAL: Set up new controller**
    if (widget.controller != null) {
      _controller = widget.controller;
      _setupController();
    } else {
      _initializeController();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // **CRITICAL FIX: Handle app lifecycle to prevent memory leaks**
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        print('🛑 VideoPlayerWidget: App going to background, pausing video');
        if (_controller != null && _controller!.value.isInitialized) {
          try {
            _controller!.pause();
            _controller!.setVolume(0.0); // Mute to prevent audio leaks
            _isPlaying = false;
          } catch (e) {
            print('❌ VideoPlayerWidget: Error pausing video on background: $e');
          }
        }
        break;

      case AppLifecycleState.resumed:
        print('👁️ VideoPlayerWidget: App resumed, checking video state');
        // Don't auto-play, let the parent control this
        break;
    }
  }

  /// **NEW: Handle widget lifecycle changes to prevent memory leaks**
  void _handleWidgetLifecycleChange() {
    if (!_isWidgetValid) {
      print('❌ VideoPlayerWidget: Widget not valid, cleaning up resources');
      _cleanupResources();
      return;
    }

    // **CRITICAL FIX: Check if controller is still valid**
    if (_controller != null && !_controller!.value.isInitialized) {
      print('⚠️ VideoPlayerWidget: Controller not initialized, cleaning up');
      _cleanupResources();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return _buildErrorWidget();
    }

    if (_isLoading) {
      return _buildLoadingWidget();
    }

    if (!_isInitialized || _controller == null) {
      return _buildInitializingWidget();
    }

    return _buildVideoPlayer();
  }

  /// **NEW: Error widget with retry functionality**
  Widget _buildErrorWidget() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            const Text(
              'Video Playback Error',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                _errorMessage ?? 'Unknown error occurred',
                style: TextStyle(
                  color: Colors.grey[300],
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _errorMessage = null;
                  _isLoading = true;
                });
                _retryInitializationWithBackoff();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () {
                // Try to use original video URL as fallback
                setState(() {
                  _errorMessage = null;
                  _isLoading = true;
                });
                _tryFallbackUrl();
              },
              icon: const Icon(Icons.link),
              label: const Text('Try Original URL'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.blue[300],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// **NEW: Try fallback URL when HLS conversion fails**
  Future<void> _tryFallbackUrl() async {
    try {
      print('🔄 VideoPlayerWidget: Trying fallback URL...');

      // Clear existing controller
      if (_controller != null) {
        try {
          await _controller!.dispose();
        } catch (e) {
          print('⚠️ VideoPlayerWidget: Error disposing controller: $e');
        }
        _controller = null;
      }

      // Try using original video URL directly
      _controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.video.videoUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      await _setupController();
    } catch (e) {
      print('❌ VideoPlayerWidget: Fallback URL also failed: $e');
      setState(() {
        _errorMessage = 'Both HLS and original URL failed: $e';
        _isLoading = false;
      });
    }
  }

  /// **NEW: Loading widget with progress indicator**
  Widget _buildLoadingWidget() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black87,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            SizedBox(height: 16),
            Text(
              'Loading Video...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// **NEW: Initializing widget for when controller is being set up**
  Widget _buildInitializingWidget() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
            ),
            const SizedBox(height: 16),
            const Text(
              'Preparing Video...',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Setting up video player...',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// **NEW: Main video player widget**
  Widget _buildVideoPlayer() {
    return Stack(
      children: [
        // Video player
        VideoPlayer(_controller!),

        // Touch overlay for play/pause - YouTube Shorts style
        GestureDetector(
          onTap: _togglePlayPause,
          child: Container(
            color: Colors.transparent,
            width: double.infinity,
            height: double.infinity,
          ),
        ),

        // Tap feedback indicator (YouTube Shorts style)
        if (_showTapFeedback)
          Center(
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 50,
              ),
            ),
          ),

        // Mute button - positioned at top left
        Positioned(
          top: 16,
          left: 16,
          child: _buildMuteButton(),
        ),
      ],
    );
  }

  /// Build thumbnail with loading indicator while video initializes
  Widget _buildThumbnailWithLoading() {
    return Stack(
      children: [
        // Thumbnail background
        _buildThumbnailBackground(),

        // Loading indicator overlay
        Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black.withOpacity(0.3),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
                SizedBox(height: 16),
                Text(
                  'Loading Video...',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Build thumbnail background
  Widget _buildThumbnailBackground() {
    if (widget.video.thumbnailUrl.isNotEmpty == true) {
      return CachedNetworkImage(
        imageUrl: widget.video.thumbnailUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (context, url) => Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black,
          child: const Center(
            child: Icon(
              Icons.image,
              color: Colors.white54,
              size: 48,
            ),
          ),
        ),
        errorWidget: (context, url, error) => _buildFallbackThumbnail(),
      );
    }

    return _buildFallbackThumbnail();
  }

  /// Build fallback thumbnail when no thumbnail URL is available
  Widget _buildFallbackThumbnail() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.video_library,
              color: Colors.white54,
              size: 64,
            ),
            SizedBox(height: 16),
            Text(
              'Video Loading',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build mute button - 35% smaller and more professional
  Widget _buildMuteButton() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: IconButton(
        onPressed: _toggleMute,
        icon: Icon(
          _isMuted ? Icons.volume_off : Icons.volume_up,
          color: Colors.white,
          size: 12,
        ),
        iconSize: 12,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(
          minWidth: 24,
          minHeight: 24,
        ),
      ),
    );
  }

  // Add this to your video player widget
  void _trackBannerAdImpression() {
    _adImpressionService.trackBannerAdImpression(
      videoId: widget.video.id,
      adId: 'banner_${widget.video.id}',
      userId: _getCurrentUserId(),
    );
  }

  // Track carousel ad impression when user scrolls
  void _trackCarouselAdImpression(int scrollPosition) {
    _adImpressionService.trackCarouselAdImpression(
      videoId: widget.video.id,
      adId: 'carousel_${widget.video.id}',
      userId: _getCurrentUserId(),
      scrollPosition: scrollPosition,
    );
  }

  String _getCurrentUserId() {
    // In a real app, you'd get the user ID from AuthService
    // For now, return a placeholder
    return 'user_${DateTime.now().millisecondsSinceEpoch}';
  }
}
