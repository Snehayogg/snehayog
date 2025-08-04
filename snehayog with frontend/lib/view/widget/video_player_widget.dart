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

  VideoPlayerController? get _controller =>
      widget.controller ?? _internalController;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _initializeInternalController();
    }
  }

  void _initializeInternalController() {
    try {
      _internalController =
          VideoPlayerController.network(widget.video.videoUrl);
      
      // Add error listener
      _internalController!.addListener(() {
        if (_internalController!.value.hasError) {
          setState(() {
            _hasError = true;
            _errorMessage = _internalController!.value.errorDescription;
          });
          print('Video player error: ${_internalController!.value.errorDescription}');
        }
      });
      
      _initializeVideoPlayerFuture =
          _internalController!.initialize().then((_) {
        if (widget.play && mounted) {
          try {
            _internalController!.play();
            _internalController!.setLooping(true);
          } catch (e) {
            print('Error playing video: $e');
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
        print('Error initializing video: $error');
        if (mounted) {
          setState(() {
            _hasError = true;
            _errorMessage = 'Failed to load video: $error';
          });
        }
      });
    } catch (e) {
      print('Error creating video controller: $e');
      setState(() {
        _hasError = true;
        _errorMessage = 'Failed to create video player: $e';
      });
    }
  }

  @override
  void didUpdateWidget(covariant VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // Handle play/pause changes
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        if (widget.play && !_controller!.value.isPlaying) {
          _controller!.play();
        } else if (!widget.play && _controller!.value.isPlaying) {
          _controller!.pause();
        }
      } catch (e) {
        print('Error updating video playback state: $e');
      }
    }
    
    // Handle video URL changes
    if (oldWidget.video.videoUrl != widget.video.videoUrl && widget.controller == null) {
      // Reinitialize internal controller for new video
      _internalController?.dispose();
      _hasError = false;
      _errorMessage = null;
      _initializeInternalController();
    }
  }

  @override
  void dispose() {
    if (widget.controller == null && _internalController != null) {
      try {
        _internalController!.pause();
      } catch (_) {}
      try {
        _internalController!.dispose();
      } catch (_) {}
    }
    super.dispose();
  }

  void _togglePlayPause() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    
    try {
      setState(() {
        if (_controller!.value.isPlaying) {
          _controller!.pause();
        } else {
          _controller!.play();
        }
      });
    } catch (e) {
      print('Error toggling play/pause: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return _buildErrorWidget();
    }
    
    if (widget.controller != null) {
      // Parent-managed controller
      if (_controller == null || !_controller!.value.isInitialized) {
        return _buildLoadingWidget();
      }
      return _buildVideoPlayer();
    } else {
      // Internal controller (fallback)
      return FutureBuilder(
        future: _initializeVideoPlayerFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done &&
              _controller != null &&
              _controller!.value.isInitialized) {
            return _buildVideoPlayer();
          } else if (snapshot.hasError || _hasError) {
            return _buildErrorWidget();
          } else {
            return _buildLoadingWidget();
          }
        },
      );
    }
  }

  Widget _buildVideoPlayer() {
    return GestureDetector(
      onTap: _togglePlayPause,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AspectRatio(
            aspectRatio: _controller!.value.aspectRatio,
            child: VideoPlayer(_controller!),
          ),
          if (!_controller!.value.isPlaying)
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.3),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow,
                size: 80,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text(
            'Loading video...',
            style: TextStyle(color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage ?? 'Failed to load video',
            style: const TextStyle(color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _hasError = false;
                _errorMessage = null;
              });
              if (widget.controller == null) {
                _initializeInternalController();
              }
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
