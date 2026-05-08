import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:video_player/video_player.dart';
import 'package:vibration/vibration.dart';

/// Mixin to handle all gesture and control button logic for the Vayu Player.
/// This keeps the main screen file clean from volume, brightness, seeking, and UI overlay timers.
mixin VayuPlayerGesturesMixin<T extends StatefulWidget> on State<T> {
  // Controls State
  bool showControls = true;
  bool showScrubbingOverlay = false;
  Duration scrubbingTargetTime = Duration.zero;
  Duration scrubbingDelta = Duration.zero;
  double horizontalDragTotal = 0.0;
  bool isForward = true;
  Timer? controlsTimer;
  bool isScrollingLocked = false;
  bool isControlsLocked = false;

  // Gesture state
  double brightnessValue = 0.5;
  double volumeValue = 0.5;
  Timer? overlayTimer;

  /// The host state must provide the current active video controller.
  VideoPlayerController? get currentVideoController;

  void handleUnifiedHorizontalDrag(double deltaX) {
    if (isControlsLocked || currentVideoController == null) return;
    horizontalDragTotal += deltaX;
    final controller = currentVideoController!;
    final seekOffset = Duration(milliseconds: (horizontalDragTotal * 500).toInt());
    var targetPosition = controller.value.position + seekOffset;
    if (targetPosition < Duration.zero) targetPosition = Duration.zero;
    if (targetPosition > controller.value.duration) targetPosition = controller.value.duration;

    setState(() {
      showScrubbingOverlay = true;
      scrubbingTargetTime = targetPosition;
      scrubbingDelta = seekOffset;
      isForward = deltaX > 0;
    });
  }

  void handleHorizontalDragEnd() {
    if (currentVideoController == null) return;
    currentVideoController!.seekTo(scrubbingTargetTime);
    setState(() {
      showScrubbingOverlay = false;
      horizontalDragTotal = 0.0;
      showControls = true;
    });
  }

  void handleVerticalDragUpdate(double primaryDelta, Offset localPosition, Size size) {
    if (isControlsLocked) return;
    final isLeftSide = localPosition.dx < size.width / 2;
    final delta = primaryDelta / size.height * 1.5;
    if (isLeftSide) {
      brightnessValue = (brightnessValue - delta).clamp(0.0, 1.0);
      ScreenBrightness().setApplicationScreenBrightness(brightnessValue);
    } else {
      volumeValue = (volumeValue - delta).clamp(0.0, 1.0);
      FlutterVolumeController.setVolume(volumeValue);
    }
    setState(() {
      showScrubbingOverlay = false;
      showControls = false;
    });
    resetOverlayTimer();
    controlsTimer?.cancel();
  }

  void resetOverlayTimer() {
    overlayTimer?.cancel();
  }

  void handleTap(Orientation orientation) {
    setState(() => showControls = !showControls);
    if (orientation == Orientation.landscape) {
      SystemChrome.setEnabledSystemUIMode(
        showControls ? SystemUiMode.manual : SystemUiMode.immersiveSticky,
        overlays: SystemUiOverlay.values,
      );
    }
    if (showControls) startHideControlsTimer(orientation);
  }

  void startHideControlsTimer(Orientation orientation) {
    controlsTimer?.cancel();
    controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => showControls = false);
        if (orientation == Orientation.landscape) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        }
      }
    });
  }

  void handleDoubleTapToSeek(TapDownDetails details, Size size, Orientation orientation) {
    final controller = currentVideoController;
    if (controller == null || !controller.value.isInitialized) return;
    final isLeftSide = details.localPosition.dx < size.width / 2;
    final seekOffset = Duration(seconds: isLeftSide ? -10 : 10);
    var target = controller.value.position + seekOffset;
    if (target < Duration.zero) target = Duration.zero;
    if (target > controller.value.duration) target = controller.value.duration;
    
    controller.seekTo(target);
    setState(() {
      showControls = true;
      showScrubbingOverlay = true;
      scrubbingTargetTime = target;
      scrubbingDelta = seekOffset;
      isForward = !isLeftSide;
    });
    
    startHideControlsTimer(orientation);
    overlayTimer?.cancel();
    overlayTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => showScrubbingOverlay = false);
    });
  }

  void togglePlay() {
    final controller = currentVideoController;
    if (controller == null) return;
    Vibration.vibrate(duration: 50, amplitude: 128);
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
        hideControlsWithDelay();
      }
    });
  }

  void hideControlsWithDelay() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && currentVideoController?.value.isPlaying == true && showControls) {
        setState(() => showControls = false);
      }
    });
  }
}
