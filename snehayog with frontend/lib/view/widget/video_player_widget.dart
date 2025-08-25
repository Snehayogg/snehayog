import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/core/services/video_url_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:async';
import 'package:snehayog/services/ad_impression_service.dart';
import 'package:snehayog/utils/feature_flags.dart';
import 'package:snehayog/core/managers/video_cache_manager.dart';

class VideoPlayerWidget extends StatefulWidget {
  final VideoModel video;
  final bool play;
  final VideoPlayerController? controller;
  final VideoCacheManager? cacheManager; // Add cache manager

  const VideoPlayerWidget({
    Key? key,
    required this.video,
    required this.play,
    this.controller,
    this.cacheManager,
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

  // Fast video delivery integration
  bool _isPreloading = false;
  double _preloadProgress = 0.0;
  bool _isCached = false;

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
    print(
        '🎬 VideoPlayerWidget: Cache manager provided: ${widget.cacheManager != null}');

    // Check cache status if fast video delivery is enabled
    if (Features.fastVideoDelivery.isEnabled && widget.cacheManager != null) {
      _checkCacheStatus();
    }

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

  /// Check cache status for fast video delivery
  Future<void> _checkCacheStatus() async {
    if (widget.cacheManager == null) {
      print(
          '⚠️ VideoPlayerWidget: No cache manager provided for video: ${widget.video.videoName}');
      return;
    }

    try {
      _isCached = widget.cacheManager!.isVideoCached(widget.video.id);
      _isPreloading = widget.cacheManager!.isPreloading(widget.video.id);
      _preloadProgress =
          widget.cacheManager!.getPreloadProgress(widget.video.id);

      if (mounted) {
        setState(() {});
      }

      print(
          '🔍 VideoPlayerWidget: Cache status for "${widget.video.videoName}" - Cached: $_isCached, Preloading: $_isPreloading, Progress: ${(_preloadProgress * 100).toStringAsFixed(1)}%');
      print(
          '🔍 VideoPlayerWidget: Video ID: ${widget.video.id}, URL: ${widget.video.videoUrl}');
    } catch (e) {
      print('❌ VideoPlayerWidget: Error checking cache status: $e');
    }
  }

  Future<void> _initializeController() async {
    try {
      print('🎬 VideoPlayerWidget: Starting controller initialization...');

      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      final videoUrl = VideoUrlService.getBestVideoUrl(widget.video);
      print('🎬 VideoPlayerWidget: Best video URL: $videoUrl');

      _controller = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      print('🎬 VideoPlayerWidget: Controller created, setting up...');
      await _setupController();

      setState(() {
        _isLoading = false;
      });

      print('🎬 VideoPlayerWidget: Initialization complete!');
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

        // Touch overlay for play/pause - YouTube Shorts style (BELOW buttons)
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

        // Mute button - positioned at top left, ABOVE gesture detector
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
              const Text(
                'Video playback error. Please try again.',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
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

  /// Build cache status indicator for fast video delivery
  Widget _buildCacheStatusIndicator() {
    if (!Features.fastVideoDelivery.isEnabled) return const SizedBox.shrink();

    Color indicatorColor;
    IconData indicatorIcon;
    String statusText;

    if (_isCached) {
      indicatorColor = Colors.green;
      indicatorIcon = Icons.check_circle;
      statusText = 'Cached';
    } else if (_isPreloading) {
      indicatorColor = Colors.blue;
      indicatorIcon = Icons.download;
      statusText = 'Preloading';
    } else {
      indicatorColor = Colors.grey;
      indicatorIcon = Icons.cloud_download;
      statusText = 'Not Cached';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: indicatorColor.withOpacity(0.9),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            indicatorIcon,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            statusText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
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
