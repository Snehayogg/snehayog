import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:vayug/shared/widgets/interactive_scale_button.dart';
import 'dart:ui';

class VayuPlayerOverlay extends StatelessWidget {
  final VideoPlayerController? controller;
  final bool showControls;
  final bool isControlsLocked;
  final bool isPortrait;
  final bool isFullScreenManual;
  final VoidCallback onTogglePlay;
  final VoidCallback onMoreOptions;
  final VoidCallback onNext;
  final VoidCallback onPrevious;

  const VayuPlayerOverlay({
    super.key,
    required this.controller,
    required this.showControls,
    required this.isControlsLocked,
    required this.isPortrait,
    required this.isFullScreenManual,
    required this.onTogglePlay,
    required this.onMoreOptions,
    required this.onNext,
    required this.onPrevious,
  });

  @override
  Widget build(BuildContext context) {
    if (controller == null) return const SizedBox.shrink();

    final isFull = !isPortrait || isFullScreenManual;
    final viewPadding = MediaQuery.of(context).viewPadding;
    final sidePadding = isPortrait ? 14.0 : 20.0;
    // Using a fixed 48px offset for landscape to ensure controls never jump
    final horizontalPadding = isFull ? (isPortrait ? 24.0 : 48.0) : 14.0;
    // Stable top offset for landscape
    final topOffset = isPortrait ? 8.0 : 32.0;

    return AnimatedOpacity(
      opacity: showControls ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 300),
      child: IgnorePointer(
        ignoring: !showControls,
        child: Stack(
          children: [
            // TOP SCRIM
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 60,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.8),
                        Colors.black.withValues(alpha: 0.5),
                        Colors.black.withValues(alpha: 0.2),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.3, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // Top Controls (More menu)
            Positioned(
              top: 0,
              right: 0,
              left: 0,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  isPortrait ? sidePadding : horizontalPadding,
                  topOffset,
                  isPortrait ? sidePadding : horizontalPadding,
                  0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const SizedBox(width: 30), // Balance
                    SizedBox(
                      width: isPortrait ? 30 : 34,
                      height: isPortrait ? 30 : 34,
                      child: IconButton(
                        constraints: const BoxConstraints(),
                        icon: Icon(
                          Icons.more_vert_rounded,
                          color: Colors.white,
                          size: isPortrait ? 22 : 26,
                          shadows: [
                            Shadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        onPressed: onMoreOptions,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.45),
                          padding: const EdgeInsets.all(4),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: const CircleBorder(),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.15), width: 0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // BOTTOM SCRIM
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              height: 80,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.8),
                        Colors.black.withValues(alpha: 0.5),
                        Colors.black.withValues(alpha: 0.2),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.3, 0.7, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // Center Controls (Skip/Play/Skip)
            if (!isControlsLocked)
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (!isPortrait) ...[
                      InteractiveScaleButton(
                        onTap: onPrevious,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration:
                              const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                          child: const Icon(
                            Icons.skip_previous_rounded,
                            color: Colors.white,
                            size: 38,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 42),
                    ],
                    Container(
                      width: isPortrait ? 64 : 76,
                      height: isPortrait ? 64 : 76,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.2), width: 0.5),
                      ),
                      child: InteractiveScaleButton(
                        onTap: onTogglePlay,
                        child: Icon(
                          controller!.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: isPortrait ? 48 : 56,
                          shadows: const [
                            Shadow(color: Colors.black54, blurRadius: 15, offset: Offset(0, 2)),
                          ],
                        ),
                      ),
                    ),
                    if (!isPortrait) ...[
                      const SizedBox(width: 42),
                      InteractiveScaleButton(
                        onTap: onNext,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration:
                              const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                          child: const Icon(
                            Icons.skip_next_rounded,
                            color: Colors.white,
                            size: 38,
                            shadows: [
                              Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
