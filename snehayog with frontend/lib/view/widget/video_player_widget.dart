import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';

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
  VideoPlayerController? _internalController;
  Future<void>? _initializeVideoPlayerFuture;
  bool _hasError = false;
  String? _errorMessage;
  bool _isHLS = false;

  VideoPlayerController? get _controller =>
      widget.controller ?? _internalController;

  @override
  void initState() {
    super.initState();
    _checkIfShouldUseHLS();

    if (widget.controller == null) {
      _initializeInternalController();
    }
  }

  void _checkIfShouldUseHLS() {
    _isHLS = widget.video.isHLSEncoded == true ||
        widget.video.hlsMasterPlaylistUrl != null ||
        widget.video.hlsPlaylistUrl != null;
  }

  void _initializeInternalController() {
    try {
      // Use HLS URL if available, otherwise fall back to regular video URL
      String videoUrl = _getBestVideoUrl();

      print('🎬 Initializing video player with URL: $videoUrl');
      print('🎬 Is HLS: $_isHLS');

      _internalController = VideoPlayerController.networkUrl(
        Uri.parse(videoUrl),
        videoPlayerOptions: VideoPlayerOptions(
          mixWithOthers: false,
          allowBackgroundPlayback: false,
        ),
      );

      // Add error listener
      _internalController!.addListener(() {
        if (_internalController!.value.hasError) {
          setState(() {
            _hasError = true;
            _errorMessage = _internalController!.value.errorDescription;
          });
          print(
              '❌ Video player error: ${_internalController!.value.errorDescription}');
        }
      });

      _initializeVideoPlayerFuture =
          _internalController!.initialize().then((_) {
        print('✅ Video player initialized successfully');
        if (widget.play && mounted) {
          try {
            _internalController!.play();
            _internalController!.setLooping(true);
            print('▶️ Video started playing');
          } catch (e) {
            print('❌ Error playing video: $e');
            setState(() {
              _hasError = true;
              _errorMessage = 'Failed to play video: $e';
            });
          }
        }
        if (mounted) {
          setState(() {});
        }
      }).catchError((error) {
        print('❌ Error initializing video: $error');
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = 'Failed to load video: $error';
          });
        }
      });
    } catch (e) {
      print('❌ Error creating video controller: $e');
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to create video player: $e';
      });
    }
  }

  String _getBestVideoUrl() {
    // Priority: HLS Master Playlist > HLS Playlist > Regular Video URL
    if (widget.video.hlsMasterPlaylistUrl != null &&
        widget.video.hlsMasterPlaylistUrl!.isNotEmpty) {
      print(
          '🎬 Using HLS Master Playlist: ${widget.video.hlsMasterPlaylistUrl}');
      return _buildFullUrl(widget.video.hlsMasterPlaylistUrl!);
    }

    if (widget.video.hlsPlaylistUrl != null &&
        widget.video.hlsPlaylistUrl!.isNotEmpty) {
      print('🎬 Using HLS Playlist: ${widget.video.hlsPlaylistUrl}');
      return _buildFullUrl(widget.video.hlsPlaylistUrl!);
    }

    print('🎬 Using regular video URL: ${widget.video.videoUrl}');
    return widget.video.videoUrl;
  }

  String _buildFullUrl(String relativeUrl) {
    // Use your local network IP for development
    if (relativeUrl.startsWith('/uploads/hls/')) {
      final fullUrl = 'http://192.168.0.190:5000/api/videos${relativeUrl}';
      print('🔗 Built full URL: $fullUrl');
      return fullUrl;
    }
    return relativeUrl;
  }

  @override
  void didUpdateWidget(covariant VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // Handle play/pause changes
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        if (widget.play && !_controller!.value.isPlaying) {
          _controller!.play();
          print('▶️ Video resumed');
        } else if (!widget.play && _controller!.value.isPlaying) {
          _controller!.pause();
          print('⏸️ Video paused');
        }
      } catch (e) {
        print('❌ Error updating video player state: $e');
      }
    }
  }

  @override
  void dispose() {
    _internalController?.dispose();
    super.dispose();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.play_circle_outline,
              size: 64,
              color: Colors.white.withOpacity(0.7),
            ),
            SizedBox(height: 16),
            Text(
              'Tap to play',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 16,
              ),
            ),
            if (_isHLS) ...[
              SizedBox(height: 8),
              Text(
                'HLS Streaming',
                style: TextStyle(
                  color: Colors.blue.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorWidget(String errorMessage) {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red.withOpacity(0.7),
            ),
            SizedBox(height: 16),
            Text(
              'Playback Error',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: 8),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                errorMessage,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _hasError = false;
                  _errorMessage = null;
                });
                _initializeInternalController();
              },
              child: Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _buildErrorWidget(_errorMessage ?? 'Unknown error');
    }

    // Show video player
    if (_controller == null || !_controller!.value.isInitialized) {
      return _buildLoadingWidget();
    }

    return AspectRatio(
      aspectRatio: _controller!.value.aspectRatio,
      child: VideoPlayer(_controller!),
    );
  }

  Widget _buildLoadingWidget() {
    return Container(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            SizedBox(height: 16),
            Text(
              'Loading video...',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 16,
              ),
            ),
            if (_isHLS) ...[
              SizedBox(height: 8),
              Text(
                'HLS Streaming',
                style: TextStyle(
                  color: Colors.blue.withOpacity(0.7),
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
