part of 'package:vayu/view/screens/video_feed_advanced.dart';

extension _VideoFeedPlayback on _VideoFeedAdvancedState {
  bool _canPrimeIndex(int index) {
    final bool isYugVisible =
        _mainController?.currentIndex == 0 && _isScreenVisible;
    if (!isYugVisible) return false;

    if (index == _currentIndex) return false;

    final int start = (_currentIndex + 1).clamp(0, _videos.length - 1);
    final int end = (_currentIndex + _decoderPrimeBudget - 1).clamp(
      0,
      _videos.length - 1,
    );
    return index >= start && index <= end;
  }

  void _reprimeWindowIfNeeded() {
    final int start = _currentIndex;
    final int end = (_currentIndex + _decoderPrimeBudget - 1).clamp(
      0,
      _videos.length - 1,
    );

    if (_primedStartIndex == start) return;

    _controllerPool.forEach((idx, controller) {
      if (idx < start || idx > end) {
        if (controller.value.isInitialized && controller.value.isPlaying) {
          try {
            controller.pause();
            _controllerStates[idx] = false;
          } catch (_) {}
        }
      }
    });

    _primedStartIndex = start;
  }

  void _pauseAllOtherVideos(int currentIndex) {
    _controllerPool.forEach((idx, controller) {
      if (idx != currentIndex &&
          controller.value.isInitialized &&
          controller.value.isPlaying) {
        try {
          controller.pause();
          _controllerStates[idx] = false;
        } catch (_) {}
      }
    });

    _videoControllerManager.pauseAllVideosOnTabChange();

    final sharedPool = SharedVideoControllerPool();
    sharedPool.pauseAllControllers();
    _ensureWakelockForVisibility();
  }

  void forcePlayCurrent() {
    if (_videos.isEmpty ||
        _currentIndex < 0 ||
        _currentIndex >= _videos.length) {
      return;
    }

    final controller = _controllerPool[_currentIndex];
    if (controller != null && controller.value.isInitialized) {
      _pauseAllOtherVideos(_currentIndex);
      _lifecyclePaused = false;
      controller.play();
      _controllerStates[_currentIndex] = true;
      _userPaused[_currentIndex] = false;
      _ensureWakelockForVisibility();
      return;
    }

    _preloadVideo(_currentIndex).then((_) {
      if (!mounted) return;
      final c = _controllerPool[_currentIndex];
      if (c != null && c.value.isInitialized) {
        _pauseAllOtherVideos(_currentIndex);
        _lifecyclePaused = false;
        c.play();
        _controllerStates[_currentIndex] = true;
        _userPaused[_currentIndex] = false;
        _ensureWakelockForVisibility();
      }
    });
  }

  void _pauseCurrentVideo() {
    if (_currentIndex < _videos.length) {
      final currentVideo = _videos[_currentIndex];
      _viewTracker.stopViewTracking(currentVideo.id);
    }

    if (_controllerPool.containsKey(_currentIndex)) {
      final controller = _controllerPool[_currentIndex];

      if (controller != null &&
          controller.value.isInitialized &&
          controller.value.isPlaying) {
        controller.pause();
        _controllerStates[_currentIndex] = false;
      }
    }

    _videoControllerManager.pauseAllVideosOnTabChange();
    SharedVideoControllerPool().pauseAllControllers();
  }

  void _pauseAllVideosOnTabSwitch() {
    _controllerPool.forEach((index, controller) {
      if (controller.value.isInitialized && controller.value.isPlaying) {
        controller.pause();
        _controllerStates[index] = false;
      }
    });

    _videoControllerManager.pauseAllVideosOnTabChange();
    SharedVideoControllerPool().pauseAllControllers();

    _isScreenVisible = false;
    _disableWakelock();
  }
}
