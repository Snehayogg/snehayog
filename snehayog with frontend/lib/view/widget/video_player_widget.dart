import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/core/managers/video_player_state_manager.dart';
import 'package:snehayog/core/services/video_url_service.dart';
import 'package:snehayog/view/widget/video_overlays/video_progress_bar.dart';
import 'package:snehayog/view/widget/video_overlays/video_play_pause_overlay.dart';
import 'package:snehayog/view/widget/video_overlays/video_seeking_indicator.dart';
import 'package:snehayog/core/constants/video_constants.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
  late final VideoPlayerStateManager _stateManager;
  VideoPlayerController? _externalController;

  VideoPlayerController? get _controller =>
      widget.controller ?? _stateManager.internalController;

  @override
  void initState() {
    super.initState();
    _stateManager = VideoPlayerStateManager();

    // Check HLS status
    final isHLS = VideoUrlService.shouldUseHLS(widget.video);
    _stateManager.updateHLSStatus(isHLS);

    if (widget.controller == null) {
      _initializeInternalController();
    } else {
      _externalController = widget.controller;
      _stateManager.initializeController(
        VideoUrlService.getBestVideoUrl(widget.video),
        widget.play,
      );
    }

    // Add listener for automatic error recovery
    _stateManager.addListener(_onStateManagerChanged);
  }

  @override
  void didUpdateWidget(VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Check if video data has changed and refresh HLS status
    if (oldWidget.video.id != widget.video.id ||
        oldWidget.video.isHLSEncoded != widget.video.isHLSEncoded ||
        oldWidget.video.hlsMasterPlaylistUrl !=
            widget.video.hlsMasterPlaylistUrl ||
        oldWidget.video.hlsPlaylistUrl != widget.video.hlsPlaylistUrl) {
      final isHLS = VideoUrlService.shouldUseHLS(widget.video);
      _stateManager.updateHLSStatus(isHLS);
    }

    // Handle play state changes
    if (oldWidget.play != widget.play &&
        _controller != null &&
        _controller!.value.isInitialized) {
      if (widget.play && !_stateManager.isPlaying) {
        _stateManager.play();
      } else if (!widget.play && _stateManager.isPlaying) {
        _stateManager.pause();
      }
    }
  }

  Future<void> _initializeInternalController() async {
    try {
      final videoUrl = VideoUrlService.getBestVideoUrl(widget.video);
      await _stateManager.initializeController(videoUrl, widget.play);
    } catch (e) {
      print('❌ Error initializing video controller: $e');

      // Try automatic retry with fallback URL
      await _tryFallbackVideoUrl();
    }
  }

  void _handleTap() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    // Toggle audio on tap (Instagram-style behavior)
    _stateManager.toggleMute();

    // Also toggle play/pause if video is not playing
    if (!_stateManager.isPlaying) {
      _stateManager.play();
    }

    _stateManager.displayPlayPauseOverlay();
  }

  void _handleDoubleTap(TapDownDetails details) {
    if (_controller == null || !_controller!.value.isInitialized) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final tapPosition = details.globalPosition.dx;
    final currentPosition = _controller!.value.position;

    if (tapPosition < screenWidth / 2) {
      // Left side - seek backward
      final newPosition = currentPosition - VideoConstants.seekDuration;
      if (newPosition.inMilliseconds > 0) {
        _stateManager.seekTo(newPosition);
      }
    } else {
      // Right side - seek forward
      final newPosition = currentPosition + VideoConstants.seekDuration;
      if (newPosition.inMilliseconds <
          _controller!.value.duration.inMilliseconds) {
        _stateManager.seekTo(newPosition);
      }
    }

    _stateManager.showSeekingIndicator();
  }

  @override
  void dispose() {
    _stateManager.removeListener(_onStateManagerChanged);
    _stateManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _stateManager,
      builder: (context, child) {
        if (_controller == null || !_controller!.value.isInitialized) {
          // Show thumbnail while video is initializing
          return _buildThumbnailWithLoading();
        }

        if (_stateManager.hasError) {
          return _buildErrorWidget();
        }

        return RepaintBoundary(
          child: Stack(
            children: [
              // Video player
              VideoPlayer(_controller!),

              // Thumbnail overlay (shown while buffering)
              if (_isVideoBuffering()) _buildThumbnailOverlay(),

              // Buffering indicator
              if (_isVideoBuffering())
                const Center(
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),

              // Touch overlay for play/pause
              GestureDetector(
                onTap: _handleTap,
                child: Container(
                  color: Colors.transparent,
                  width: double.infinity,
                  height: double.infinity,
                ),
              ),

              // Play/Pause overlay
              VideoPlayPauseOverlay(
                isVisible: _stateManager.showPlayPauseOverlay,
                isPlaying: _stateManager.isPlaying,
              ),

              VideoSeekingIndicator(isVisible: _stateManager.isSeeking),
              VideoProgressBar(controller: _controller!),

              // Audio control button
              Positioned(
                top: 16,
                right: 16,
                child: GestureDetector(
                  onTap: () {
                    _stateManager.toggleMute();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Icon(
                      _stateManager.isMuted
                          ? Icons.volume_off
                          : Icons.volume_up,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Build thumbnail with loading indicator while video initializes
  Widget _buildThumbnailWithLoading() {
    return Stack(
      children: [
        // Thumbnail background
        _buildThumbnailBackground(),

        // Loading indicator
        const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
              SizedBox(height: 16),
              Text(
                'Loading video...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Build thumbnail background
  Widget _buildThumbnailBackground() {
    // Try to get thumbnail from video model
    final thumbnailUrl = _getThumbnailUrl();

    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: thumbnailUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
        placeholder: (context, url) => Container(
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

  /// Build thumbnail overlay shown while buffering
  Widget _buildThumbnailOverlay() {
    return AnimatedOpacity(
      opacity: _isVideoBuffering() ? 0.7 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: Container(
        width: double.infinity,
        height: double.infinity,
        color: Colors.black,
        child: _buildThumbnailBackground(),
      ),
    );
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
    String errorMessage = 'Video playback error. Please try again.';
    String actionMessage =
        'This video requires HLS streaming format (.m3u8) to play.';

    if (_stateManager.errorMessage != null) {
      if (_stateManager.errorMessage!.contains('HLS')) {
        errorMessage = 'HLS Streaming Error';
        actionMessage =
            'This video failed to load in streaming format. Please re-upload the video.';
      } else if (_stateManager.errorMessage!.contains('not HLS encoded')) {
        errorMessage = 'Video Format Not Supported';
        actionMessage =
            'This video is not in streaming format (.m3u8). Only HLS videos are supported.';
      } else if (_stateManager.errorMessage!.contains('network')) {
        errorMessage = 'Network Error';
        actionMessage =
            'Failed to load video from network. Check your internet connection.';
      }
    }

    return Container(
      width: double.infinity,
      height: double.infinity,
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Error icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.error_outline,
                color: Colors.white,
                size: 48,
              ),
            ),

            const SizedBox(height: 24),

            // Error title
            Text(
              errorMessage,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: 16),

            // Error description
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                actionMessage,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 32),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Retry button
                ElevatedButton.icon(
                  onPressed: () {
                    _stateManager.clearError();
                    _initializeInternalController();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),

                const SizedBox(width: 16),

                // Alternative button
                ElevatedButton.icon(
                  onPressed: () {
                    // Try alternative video or show message
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'All videos must be in HLS streaming format (.m3u8)'),
                        duration: Duration(seconds: 3),
                      ),
                    );
                  },
                  icon: const Icon(Icons.arrow_forward),
                  label: const Text('Try Alternative'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Check if video is currently buffering
  bool _isVideoBuffering() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return false;
    }
    return _controller!.value.isBuffering;
  }

  /// Get thumbnail URL from video model
  String? _getThumbnailUrl() {
    try {
      // Try to get thumbnail from video model
      // This assumes your VideoModel has a thumbnail field
      // You may need to adjust this based on your actual model structure

      // Option 1: If you have a thumbnail field
      // return widget.video.thumbnail;

      // Option 2: Generate thumbnail from video URL (if supported)
      // return _generateThumbnailUrl(widget.video.videoUrl);

      // Option 3: Use a default thumbnail
      return null;
    } catch (e) {
      print('❌ Error getting thumbnail URL: $e');
      return null;
    }
  }

  /// Try alternative video URL if primary fails
  Future<void> _tryFallbackVideoUrl() async {
    try {
      print('🔄 Trying fallback video URL...');

      // Try different quality options
      String? fallbackUrl;

      // First try HLS if available
      if (widget.video.hlsPlaylistUrl != null &&
          widget.video.hlsPlaylistUrl!.isNotEmpty) {
        fallbackUrl = widget.video.hlsPlaylistUrl;
        print('🔄 Trying HLS playlist URL: $fallbackUrl');
      }
      // Then try original video URL
      else if (widget.video.videoUrl.isNotEmpty) {
        fallbackUrl = widget.video.videoUrl;
        print('🔄 Trying original video URL: $fallbackUrl');
      }

      if (fallbackUrl != null) {
        await _stateManager.initializeController(fallbackUrl, false);
      } else {
        print('❌ No fallback URL available');
        _stateManager.setError('No alternative video source available');
      }
    } catch (e) {
      print('❌ Error trying fallback URL: $e');
      _stateManager.setError('Failed to load alternative video source');
    }
  }

  /// Show video information for debugging
  void _showVideoInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Video Information'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Title: ${widget.video.videoName}'),
              Text('ID: ${widget.video.id}'),
              Text('Video URL: ${widget.video.videoUrl}'),
              if (widget.video.hlsPlaylistUrl != null)
                Text('HLS URL: ${widget.video.hlsPlaylistUrl}'),
              if (widget.video.hlsMasterPlaylistUrl != null)
                Text('HLS Master: ${widget.video.hlsMasterPlaylistUrl}'),
              Text('Is HLS: ${widget.video.isHLSEncoded}'),
              Text('Error: ${_stateManager.errorMessage ?? 'None'}'),
              const SizedBox(height: 16),
              const Text(
                'This information can help diagnose video playback issues.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Listener for state manager changes to handle automatic retries
  void _onStateManagerChanged() {
    if (_stateManager.hasError &&
        _stateManager.errorMessage == 'No alternative video source available') {
      // If the error is due to no fallback URL, try to initialize with the current URL
      // This assumes the current URL is the primary one that failed.
      // If the error message is more specific, you might need a different logic.
      final currentVideoUrl = VideoUrlService.getBestVideoUrl(widget.video);
      if (currentVideoUrl.isNotEmpty) {
        print('🔄 Attempting to retry with current URL: $currentVideoUrl');
        _stateManager.initializeController(currentVideoUrl, false);
      } else {
        print('❌ No current URL available for retry.');
      }
    }
  }
}
