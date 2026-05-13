import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/video/core/presentation/widgets/quiz_overlay.dart';
import 'package:vayug/features/video/vayu/presentation/widgets/vayu_video_progress_bar.dart';
import 'dart:ui';


enum GestureType { none, horizontal, vertical, scale }

class VayuFeedItem extends ConsumerStatefulWidget {
  final int index;
  final VideoModel video;
  final VideoPlayerController? controller;
  final ChewieController? chewie;
  final bool isCurrent;
  final bool isFullScreenManual;
  final ValueNotifier<bool> showControlsVN;
  final ValueNotifier<bool> isControlsLockedVN;
  final ValueNotifier<bool> showScrubbingOverlayVN;
  final VoidCallback onToggleFullScreen;
  final VoidCallback onOpenExternalPlayer;
  final VoidCallback onHandleTap;
  final void Function(TapDownDetails) onDoubleTapToSeek;
  final VoidCallback onHorizontalDragEnd;
  final void Function(double, Offset) onVerticalDragUpdate;
  final VoidCallback onVerticalDragEnd;
  final void Function(double) onUnifiedHorizontalDrag;
  final void Function(bool) onScrollingLock;
  final void Function(String) onShowSnackBar;
  final Widget Function(int) buildAdSection;
  final Widget Function(int) buildVideoInfo; // Legacy support or direct call
  final Widget Function(int) buildChannelRow; // Legacy support or direct call
  final Widget Function() buildScrubbingOverlay;
  final Widget Function(int) buildCustomControls; // Legacy support or direct call
  final Widget Function(int) buildDubbingProgress; // Legacy support or direct call
  final String Function(Duration) formatDuration;
  final QuizModel? activeQuiz;
  final VoidCallback onQuizDismiss;
  final VoidCallback? onQuizBack;

  // New component-based callbacks/widgets passed from parent
  final Widget metadataSection;
  final Widget channelInfo;
  final Widget playerOverlay;
  final Widget dubbingOverlay;

  const VayuFeedItem({
    super.key,
    required this.index,
    required this.video,
    this.controller,
    this.chewie,
    required this.isCurrent,
    required this.isFullScreenManual,
    required this.showControlsVN,
    required this.isControlsLockedVN,
    required this.showScrubbingOverlayVN,
    required this.onToggleFullScreen,
    required this.onHandleTap,
    required this.onDoubleTapToSeek,
    required this.onHorizontalDragEnd,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
    required this.onUnifiedHorizontalDrag,
    required this.onScrollingLock,
    required this.onShowSnackBar,
    required this.buildAdSection,
    required this.buildVideoInfo,
    required this.buildChannelRow,
    required this.buildScrubbingOverlay,
    required this.buildCustomControls,
    required this.buildDubbingProgress,
    required this.formatDuration,
    required this.onOpenExternalPlayer,
    this.activeQuiz,
    this.onQuizBack,
    required this.onQuizDismiss,
    required this.metadataSection,
    required this.channelInfo,
    required this.playerOverlay,
    required this.dubbingOverlay,
  });

  @override
  ConsumerState<VayuFeedItem> createState() => _VayuFeedItemState();
}

class _VayuFeedItemState extends ConsumerState<VayuFeedItem> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _baseScale = 1.0;
  int _pointers = 0;
  bool _isScaling = false;

  // Gesture tracking
  GestureType _activeGesture = GestureType.none;
  double _dragHorizontalDeltaAccumulated = 0;
  double _dragVerticalDeltaAccumulated = 0;
  static const double _gestureThreshold = 12.0;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final orientation = MediaQuery.of(context).orientation;
    final isFull = orientation == Orientation.landscape || widget.isFullScreenManual;
    final lateralPadding = orientation == Orientation.landscape ? 60.0 : 14.0;

    // We use a Stack as the root to maintain widget tree stability across orientation changes
    return Stack(
      children: [
        // ── LAYER 1: Ambient blurred thumbnail (Portrait & Landscape) ──────────
        if (widget.video.thumbnailUrl.isNotEmpty)
          Positioned.fill(
            child: RepaintBoundary(
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32, tileMode: TileMode.clamp),
                child: Image.network(
                  widget.video.thumbnailUrl,
                  fit: BoxFit.cover,
                  cacheWidth: 180,
                  errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.transparent),
                ),
              ),
            ),
          )
        else
          const Positioned.fill(child: ColoredBox(color: Colors.transparent)),

        // ── LAYER 2: Dark / Gradient overlay — keeps foreground content readable ──────────
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: isFull 
                ? const LinearGradient(
                    colors: [Color.fromRGBO(0, 0, 0, 0.4), Color.fromRGBO(0, 0, 0, 0.6)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  )
                : LinearGradient(
                    colors: [
                      Colors.black.withValues(alpha: 0.3),
                      Colors.black.withValues(alpha: 0.8),
                      Colors.black,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.0, 0.4, 0.7],
                  ),
            ),
          ),
        ),

        // Stable Video + Metadata Column
        Column(
          children: [
            _buildVideoSection(orientation),
            // Preserve metadata state even in full screen to avoid "reloading"
            Expanded(
              flex: isFull ? 0 : 1,
              child: Visibility(
                visible: !isFull,
                maintainState: true,
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: [
                        widget.buildAdSection(widget.index),
                        widget.metadataSection,
                        widget.channelInfo,
                        if (widget.activeQuiz != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: QuizOverlay(
                              quiz: widget.activeQuiz!,
                              onDismiss: widget.onQuizDismiss,
                              onBack: (widget.onQuizBack != null) ? widget.onQuizBack : null,
                              onAnswered: (idx) {},
                            ),
                          ),
                        widget.dubbingOverlay,
                        const SizedBox(height: 48),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        // Overlays that appear in BOTH modes (landscape specific positions)
        if (isFull) ...[
          if (widget.activeQuiz != null)
            Positioned(
              bottom: 80,
              left: lateralPadding,
              right: lateralPadding,
              child: QuizOverlay(
                quiz: widget.activeQuiz!,
                onDismiss: widget.onQuizDismiss,
                onBack: widget.onQuizBack,
                onAnswered: (idx) {},
              ),
            ),
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: widget.dubbingOverlay,
          ),
        ],
      ],
    );
  }

  Widget _buildVideoSection(Orientation orientation) {
    final size = MediaQuery.of(context).size;
    final controller = widget.controller;
    final chewie = widget.chewie;

    bool controllerIsHealthy = false;
    bool isPlaying = false;
    try {
      if (controller != null) {
        controllerIsHealthy = controller.value.isInitialized;
        isPlaying = controller.value.isPlaying;
      }
    } catch (_) {
      controllerIsHealthy = false;
    }

    final isFull = orientation == Orientation.landscape || widget.isFullScreenManual;
    final isPortrait = orientation == Orientation.portrait;
    // Asymmetric offsets for landscape to clear system navigation buttons while staying compact on the left
    final leftPadding = orientation == Orientation.landscape ? 24.0 : 14.0;
    final rightPadding = orientation == Orientation.landscape ? 64.0 : 14.0;

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.passthrough,
        children: [
          // Background handled at the root build level. 
          // Layer 3: Actual video container + all overlays
          SizedBox(
            width: size.width,
            height: isFull ? size.height : size.width * (9 / 16),
            child: Stack(
              children: [
                // 1. THUMBNAIL PLACEHOLDER (Visible until video starts)
                // Wrapped in AspectRatio to prevent it from covering the blurred background on the sides in full-screen
                Positioned.fill(
                  child: Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Image.network(
                        widget.video.thumbnailUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black),
                      ),
                    ),
                  ),
                ),

                // 2. VIDEO LAYER with Cross-Fade
                if (controllerIsHealthy && chewie != null)
                  Positioned.fill(
                    child: AnimatedOpacity(
                      opacity: controllerIsHealthy ? 1.0 : 0.0,
                      duration: controllerIsHealthy ? Duration.zero : const Duration(milliseconds: 400),
                      child: Center(
                        child: ClipRect(
                          child: Transform.translate(
                            offset: _offset,
                            child: Transform.scale(
                              scale: _scale,
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: Chewie(controller: chewie),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                // 2. PAUSE OVERLAY (Black semi-transparent layer when paused)
                if (controllerIsHealthy && controller != null)
                  Positioned.fill(
                    child: ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: controller,
                      builder: (context, value, _) {
                        return IgnorePointer(
                          child: AnimatedOpacity(
                            opacity: (!value.isPlaying && value.isInitialized) ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOut,
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.55),
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                // 3. CONTROLS OVERLAY (Provides contrast for icons when controls are visible)
                Positioned.fill(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: widget.showControlsVN,
                    builder: (context, showControls, _) {
                      return IgnorePointer(
                        child: AnimatedOpacity(
                          opacity: showControls ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 250),
                          child: Container(
                            color: Colors.black.withValues(alpha: 0.45),
                          ),
                        ),
                      );
                    }
                  ),
                ),

          // 2. GESTURE LAYER
          Positioned.fill(
            child: Listener(
              onPointerDown: (event) => _pointers++,
              onPointerUp: (event) {
                _pointers--;
                if (_pointers <= 0) {
                  _pointers = 0;
                  if (_isScaling) {
                    setState(() {
                      _isScaling = false;
                      _scale = 1.0;
                      _offset = Offset.zero;
                    });
                    widget.onScrollingLock(false);
                  }
                  // Let GestureDetector handle the drag ends, but reset state here just in case
                  _activeGesture = GestureType.none;
                  _dragHorizontalDeltaAccumulated = 0;
                  _dragVerticalDeltaAccumulated = 0;
                }
              },
              onPointerCancel: (event) {
                _pointers = 0;
                if (_isScaling) {
                  setState(() {
                    _isScaling = false;
                    _scale = 1.0;
                    _offset = Offset.zero;
                  });
                  widget.onScrollingLock(false);
                }
                if (_activeGesture == GestureType.horizontal) widget.onHorizontalDragEnd();
                if (_activeGesture == GestureType.vertical) widget.onVerticalDragEnd();
                _activeGesture = GestureType.none;
                _dragHorizontalDeltaAccumulated = 0;
                _dragVerticalDeltaAccumulated = 0;
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onHandleTap,
                onDoubleTapDown: widget.onDoubleTapToSeek,
                onVerticalDragStart: (_) {
                  _activeGesture = GestureType.vertical;
                  widget.onScrollingLock(true);
                },
                onVerticalDragUpdate: (details) {
                  widget.onVerticalDragUpdate(details.delta.dy, details.localPosition);
                },
                onVerticalDragEnd: (_) {
                  _activeGesture = GestureType.none;
                  widget.onScrollingLock(false);
                  widget.onVerticalDragEnd();
                },
                onScaleStart: (details) {
                  if (_pointers >= 2) {
                    _isScaling = true;
                    _baseScale = _scale;
                    widget.onScrollingLock(true);
                  }
                },
                onScaleUpdate: (details) {
                  if (_isScaling) {
                    setState(() {
                      _scale = (_baseScale * details.scale).clamp(1.0, 4.0);
                    });
                    return;
                  }

                  if (_activeGesture == GestureType.none) {
                    _dragHorizontalDeltaAccumulated += details.focalPointDelta.dx;
                    // Vertical is handled by onVerticalDragUpdate now
                    if (_dragHorizontalDeltaAccumulated.abs() > _gestureThreshold) {
                      _activeGesture = GestureType.horizontal;
                      widget.onScrollingLock(true);
                    }
                  }

                  if (_activeGesture == GestureType.horizontal) {
                    widget.onUnifiedHorizontalDrag(details.focalPointDelta.dx);
                  }
                },
                onScaleEnd: (details) {
                  if (_activeGesture == GestureType.horizontal) {
                    widget.onHorizontalDragEnd();
                    widget.onScrollingLock(false);
                  }
                  _activeGesture = GestureType.none;
                  _dragHorizontalDeltaAccumulated = 0;
                  _dragVerticalDeltaAccumulated = 0;
                },
              ),
            ),
          ),

          // 3. OVERLAYS (Controls, Scrubbing)
          if (widget.isCurrent) ...[
            widget.playerOverlay,
            ValueListenableBuilder<bool>(
              valueListenable: widget.showScrubbingOverlayVN,
              builder: (context, showScrubbing, _) {
                if (!showScrubbing) return const SizedBox.shrink();
                return widget.buildScrubbingOverlay();
              },
            ),
          ],

          // 4. SECONDARY CONTROLS & PROGRESS BAR
          if (controllerIsHealthy && widget.isCurrent)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Duration and Action Buttons Row
                  ValueListenableBuilder<bool>(
                    valueListenable: widget.showControlsVN,
                    builder: (context, showControls, _) {
                      return AnimatedOpacity(
                        opacity: showControls ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: IgnorePointer(
                          ignoring: !showControls,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(leftPadding, 0, rightPadding, isFull ? 8 : 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                // Duration Text (Instant Frost + Tabular Figures)
                                if (controller != null)
                                  ValueListenableBuilder<VideoPlayerValue>(
                                    valueListenable: controller,
                                    builder: (context, value, _) {
                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.45),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.white.withValues(alpha: 0.15), width: 0.5),
                                        ),
                                        child: Text(
                                          '${widget.formatDuration(value.position)} / ${widget.formatDuration(value.duration)}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            fontFeatures: [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                      );
                                    }
                                  ),
        
                                // Action Buttons (Play/External & Fullscreen)
                                ValueListenableBuilder<bool>(
                                  valueListenable: widget.isControlsLockedVN,
                                  builder: (context, isLocked, _) {
                                    if (isLocked) return const SizedBox.shrink();
                                    return Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // External Player Button
                                        SizedBox(
                                          width: isPortrait ? 30 : 34,
                                          height: isPortrait ? 30 : 34,
                                          child: IconButton(
                                            constraints: const BoxConstraints(),
                                            icon: Icon(
                                              Icons.play_circle_outline_rounded,
                                              color: Colors.white,
                                              size: isPortrait ? 18 : 22,
                                            ),
                                            onPressed: widget.onOpenExternalPlayer,
                                            style: IconButton.styleFrom(
                                              backgroundColor: Colors.black.withValues(alpha: 0.45),
                                              padding: const EdgeInsets.all(4),
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              shape: const CircleBorder(),
                                              side: BorderSide(
                                                  color: Colors.white.withValues(alpha: 0.15), width: 0.5),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        // Fullscreen Button
                                        SizedBox(
                                          width: isPortrait ? 30 : 34,
                                          height: isPortrait ? 30 : 34,
                                          child: IconButton(
                                            constraints: const BoxConstraints(),
                                            icon: Icon(
                                              isPortrait
                                                  ? Icons.fullscreen_rounded
                                                  : Icons.fullscreen_exit_rounded,
                                              color: Colors.white,
                                              size: isPortrait ? 20 : 24,
                                            ),
                                            onPressed: widget.onToggleFullScreen,
                                            style: IconButton.styleFrom(
                                              backgroundColor: Colors.black.withValues(alpha: 0.45),
                                              padding: const EdgeInsets.all(4),
                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              shape: const CircleBorder(),
                                              side: BorderSide(
                                                  color: Colors.white.withValues(alpha: 0.15), width: 0.5),
                                            ),
                                          ),
                                        ),
                                      ],
                                    );
                                  }
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                  ),

                  // Progress Bar (Auto-hide in landscape)
                  ValueListenableBuilder<bool>(
                    valueListenable: widget.showControlsVN,
                    builder: (context, showControls, _) {
                      return AnimatedOpacity(
                        opacity: isFull ? (showControls ? 1.0 : 0.0) : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: IgnorePointer(
                          ignoring: isFull && !showControls,
                          child: Padding(
                            padding: EdgeInsets.only(
                              left: isFull ? leftPadding : 0,
                              right: isFull ? rightPadding : 0,
                            ),
                            child: VayuVideoProgressBar(
                              controller: controller!,
                              height: isFull ? 20 : 12,
                              barHeight: isFull ? 4 : 2,
                              activeBarHeight: isFull ? 10 : 4,
                              thumbRadius: isFull ? 8 : 0,
                              barCenterOffset: isFull ? null : 10,
                              onDragStart: () => widget.onScrollingLock(true),
                              onDragEnd: () => widget.onScrollingLock(false),
                            ),
                          ),
                        ),
                      );
                    }
                  ),
                  // Fixed 32px clearance in landscape for stable placement
                  if (isFull) const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  ),
);
  }
}
