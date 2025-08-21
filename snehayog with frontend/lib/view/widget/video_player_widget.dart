import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/core/managers/video_player_state_manager.dart';
import 'package:snehayog/core/services/video_url_service.dart';
import 'package:snehayog/view/widget/video_overlays/video_progress_bar.dart';
import 'package:snehayog/view/widget/video_overlays/video_play_pause_overlay.dart';
import 'package:snehayog/view/widget/video_overlays/video_seeking_indicator.dart';
import 'package:snehayog/view/widget/video_overlays/video_error_widget.dart';
import 'package:snehayog/view/widget/video_overlays/video_loading_widget.dart';
import 'package:snehayog/core/constants/video_constants.dart';

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
    final videoUrl = VideoUrlService.getBestVideoUrl(widget.video);
    await _stateManager.initializeController(videoUrl, widget.play);
  }

  void _handleTap() {
    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_stateManager.isPlaying) {
      _stateManager.pause();
    } else {
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
    _stateManager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _stateManager,
      builder: (context, child) {
        if (_stateManager.hasError) {
          return VideoErrorWidget(
            errorMessage: _stateManager.errorMessage ?? 'Unknown error',
            onRetry: () {
              _stateManager.clearError();
              _initializeInternalController();
            },
          );
        }

        if (_stateManager.internalController == null ||
            !_stateManager.internalController!.value.isInitialized) {
          return VideoLoadingWidget(isHLS: _stateManager.isHLS);
        }

        return RepaintBoundary(
          child: Stack(
            children: [
              // Video player
              Positioned.fill(
                child: VideoPlayer(
                  _stateManager.internalController!,
                ),
              ),

              // Touch overlay
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _handleTap,
                  onDoubleTapDown: _handleDoubleTap,
                  child: Container(
                    color: Colors.transparent,
                    width: double.infinity,
                    height: double.infinity,
                  ),
                ),
              ),

              // Overlays
              VideoPlayPauseOverlay(
                isVisible: _stateManager.showPlayPauseOverlay,
                isPlaying: _stateManager.isPlaying,
              ),
              VideoSeekingIndicator(isVisible: _stateManager.isSeeking),
              VideoProgressBar(controller: _controller!),
            ],
          ),
        );
      },
    );
  }
}
