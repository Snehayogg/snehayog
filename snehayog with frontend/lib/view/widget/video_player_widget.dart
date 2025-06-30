import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

class VideoPlayerWidget extends StatefulWidget {
  final String videoUrl;
  final bool isCurrentPage;

  const VideoPlayerWidget({
    Key? key,
    required this.videoUrl,
    required this.isCurrentPage,
  }) : super(key: key);

  @override
  _VideoPlayerWidgetState createState() => _VideoPlayerWidgetState();
}

class _VideoPlayerWidgetState extends State<VideoPlayerWidget> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;
  bool _isInitialized = false;
  bool _hasError = false;

  // Custom cache manager
  static final _cacheManager = CacheManager(
    Config(
      'customCacheKey',
      stalePeriod: const Duration(days: 7), // Cache videos for 7 days
      maxNrOfCacheObjects: 100, // Max 100 videos in cache
    ),
  );

  @override
  void initState() {
    super.initState();
    if (widget.isCurrentPage) {
      _initializePlayer();
    }
  }

  @override
  void didUpdateWidget(covariant VideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isCurrentPage && !_isInitialized && !_hasError) {
      _initializePlayer();
    } else if (!widget.isCurrentPage && _isInitialized) {
      _disposePlayer();
    }
  }

  Future<void> _initializePlayer() async {
    print("Initializing video with URL: ${widget.videoUrl}");
    if (widget.videoUrl.isEmpty) {
      if (mounted) setState(() => _hasError = true);
      return;
    }

    try {
      final fileInfo = await _cacheManager.getFileFromCache(widget.videoUrl);

      if (fileInfo == null) {
        // Not in cache, download and cache it
        print('Video not in cache. Downloading from ${widget.videoUrl}');
        final file = await _cacheManager.getSingleFile(widget.videoUrl);
        _videoPlayerController = VideoPlayerController.file(file);
      } else {
        // In cache, use the file directly
        print('Video found in cache: ${fileInfo.file.path}');
        _videoPlayerController = VideoPlayerController.file(fileInfo.file);
      }

      await _videoPlayerController!.initialize();
      _chewieController = ChewieController(
        videoPlayerController: _videoPlayerController!,
        autoPlay: true,
        looping: true,
        showControls: false,
        placeholder: Container(color: Colors.black),
      );
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _hasError = false;
        });
      }
    } catch (e) {
      print("Error initializing video player for URL ${widget.videoUrl}: $e");
      if (mounted) {
        setState(() {
          _isInitialized = false;
          _hasError = true;
        });
      }
    }
  }

  void _disposePlayer() {
    _videoPlayerController?.pause();
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    _chewieController = null;
    _videoPlayerController = null;
    _isInitialized = false;
    _hasError = false;
  }

  @override
  void dispose() {
    _disposePlayer();
    super.dispose();
  }

  void togglePlayPause() {
    if (_isInitialized && _videoPlayerController != null && !_hasError) {
      setState(() {
        if (_videoPlayerController!.value.isPlaying) {
          _videoPlayerController!.pause();
        } else {
          _videoPlayerController!.play();
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Icon(Icons.error, color: Colors.white, size: 40),
        ),
      );
    }

    if (_isInitialized && _chewieController != null) {
      return GestureDetector(
        onTap: togglePlayPause,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Chewie(controller: _chewieController!),
            if (!_videoPlayerController!.value.isPlaying)
              Icon(Icons.play_arrow,
                  size: 80, color: Colors.white.withOpacity(0.5)),
          ],
        ),
      );
    } else {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }
  }
}
