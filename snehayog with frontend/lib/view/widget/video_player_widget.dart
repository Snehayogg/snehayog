import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/core/services/video_url_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';

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

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isMuted = false; // Changed from true to false - videos start unmuted
  bool _isLoading = true;
  String? _errorMessage;
  Timer? _loopCheckTimer;
  bool _showTapFeedback = false;
  Timer? _feedbackTimer;

  @override
  void initState() {
    super.initState();
    print(
        '🎬 VideoPlayerWidget: Initializing for video: ${widget.video.videoName}');

    if (widget.controller == null) {
      _initializeController();
    } else {
      _controller = widget.controller;
      _setupController();
    }
  }

  Future<void> _initializeController() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final videoUrl = VideoUrlService.getBestVideoUrl(widget.video);
      print('🎬 VideoPlayerWidget: Video URL: $videoUrl');

      _controller = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      await _setupController();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      print('❌ VideoPlayerWidget: Error initializing controller: $e');
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _setupController() async {
    if (_controller == null) return;

    try {
      // Add listener for state changes
      _controller!.addListener(_onControllerStateChanged);

      // Initialize controller
      await _controller!.initialize();

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
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  void _startLoopCheckTimer() {
    // Check every 500ms if video needs to be restarted
    _loopCheckTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_controller != null &&
          _controller!.value.isInitialized &&
          _controller!.value.isPlaying) {
        final remainingTime =
            _controller!.value.duration - _controller!.value.position;
        if (remainingTime.inMilliseconds <= 200) {
          print(
              '🎬 VideoPlayerWidget: Timer detected video near end, restarting...');
          _restartVideo();
        }
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

  void _onVideoCompleted() {
    if (_controller == null) return;

    // Check if video is near the end (within 100ms) for smoother looping
    final remainingTime =
        _controller!.value.duration - _controller!.value.position;
    if (remainingTime.inMilliseconds <= 100) {
      print(
          '🎬 VideoPlayerWidget: Video near completion (${remainingTime.inMilliseconds}ms remaining), restarting...');

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
  }

  void _togglePlayPause() {
    if (_controller == null || !_controller!.value.isInitialized) {
      print('❌ VideoPlayerWidget: Controller not ready for play/pause');
      return;
    }

    print('🎬 VideoPlayerWidget: Screen tapped, toggling play/pause');

    setState(() {
      if (_isPlaying) {
        _controller!.pause();
        _isPlaying = false;
        print('🎬 VideoPlayerWidget: Video paused via screen tap');
      } else {
        _controller!.play();
        _isPlaying = true;
        print('🎬 VideoPlayerWidget: Video playing via screen tap');
      }
    });

    // Show visual feedback
    _showTapFeedbackIndicator();
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

  /// Get a user-friendly error message based on the error type
  String _getErrorMessage() {
    if (_errorMessage == null) {
      return 'Video playback error. Please try again.';
    }

    final errorLower = _errorMessage!.toLowerCase();
    
    if (errorLower.contains('not hls encoded')) {
      return 'This video needs to be converted to streaming format.\nPlease contact support.';
    } else if (errorLower.contains('network') || errorLower.contains('connection')) {
      return 'Network error. Please check your internet connection.';
    } else if (errorLower.contains('format') || errorLower.contains('codec')) {
      return 'Unsupported video format. Only streaming videos (.m3u8) are supported.';
    } else if (errorLower.contains('timeout')) {
      return 'Video loading timed out. Please try again.';
    } else if (errorLower.contains('404') || errorLower.contains('not found')) {
      return 'Video not found. It may have been removed.';
    } else if (errorLower.contains('permission') || errorLower.contains('forbidden')) {
      return 'Access denied. You may not have permission to view this video.';
    } else {
      // For any other error, show a generic message with a hint
      return 'Video playback error.\nPlease try refreshing or contact support if the issue persists.';
    }
  }

  @override
  void dispose() {
    // Cancel all timers
    _loopCheckTimer?.cancel();
    _feedbackTimer?.cancel();

    if (_controller != null && widget.controller == null) {
      // Remove all listeners before disposing
      _controller!.removeListener(_onControllerStateChanged);
      _controller!.removeListener(_onVideoCompleted);
      _controller!.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print(
        '🎬 VideoPlayerWidget: Building widget, isInitialized: $_isInitialized, isLoading: $_isLoading, controller: ${_controller != null}');

    if (_isLoading) {
      return _buildThumbnailWithLoading();
    }

    if (_errorMessage != null) {
      return _buildErrorWidget();
    }

    if (_controller == null || !_controller!.value.isInitialized) {
      return _buildThumbnailWithLoading();
    }

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

        // Audio control button - ALWAYS VISIBLE
        Positioned(
          top: 16,
          right: 16,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.9),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(color: Colors.white, width: 3),
            ),
            child: IconButton(
              onPressed: _toggleMute,
              icon: Icon(
                _isMuted ? Icons.volume_off : Icons.volume_up,
                color: Colors.white,
                size: 24,
              ),
              iconSize: 24,
              padding: const EdgeInsets.all(12),
            ),
          ),
        ),

        // Debug info overlay (temporary for testing)
        Positioned(
          top: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.9),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white, width: 2),
            ),
            child: Text(
              'Playing: $_isPlaying\nMuted: $_isMuted\nReady: ${_controller?.value.isInitialized}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),

        // Progress bar at bottom
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            height: 4,
            child: VideoProgressIndicator(
              _controller!,
              allowScrubbing: true,
              colors: VideoProgressColors(
                playedColor: Colors.red,
                bufferedColor: Colors.grey,
                backgroundColor: Colors.black54,
              ),
            ),
          ),
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
    if (widget.video.thumbnailUrl?.isNotEmpty == true) {
      return CachedNetworkImage(
        imageUrl: widget.video.thumbnailUrl!,
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

  /// Build error widget when video fails to load
  Widget _buildErrorWidget() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.red,
                size: 64,
              ),
              const SizedBox(height: 16),
              Text(
                _getErrorMessage(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _errorMessage = null;
                  });
                  _initializeController();
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
