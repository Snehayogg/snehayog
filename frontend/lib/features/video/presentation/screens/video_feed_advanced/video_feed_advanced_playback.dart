part of '../video_feed_advanced.dart';

extension _VideoFeedPlayback on _VideoFeedAdvancedState {
  void _reprimeWindowIfNeeded() {
    final int start = _currentIndex;
    final int end = (_currentIndex + _decoderPrimeBudget - 1).clamp(
      0,
      _videos.length - 1,
    );

    if (_primedStartIndex == start) return;

    _controllerPool.forEach((videoId, controller) {
      // Find index of this videoId
      int? idx;
      try {
        idx = _videos.indexWhere((v) => v.id == videoId);
      } catch (_) {}

      if (idx == null || idx < start || idx > end) {
        try {
          final value = controller.value;
          if (value.isInitialized && value.isPlaying) {
            controller.pause();
            _controllerStates[videoId] = false;
          }
        } catch (e) {
          AppLogger.log(
            '⚠️ VideoFeedAdvanced: Detected disposed controller for $videoId in _reprimeWindowIfNeeded, cleaning up: $e',
          );
          _controllerPool.remove(videoId);
          _controllerStates.remove(videoId);
        }
      }
    });

    _primedStartIndex = start;
  }

  void _pauseAllOtherVideos(String? currentVideoId) {
    _controllerPool.forEach((videoId, controller) {
      if (videoId == currentVideoId) return;

      try {
        final value = controller.value;
        if (value.isInitialized && value.isPlaying) {
          controller.pause();
          _controllerStates[videoId] = false;
        }
      } catch (e) {
        AppLogger.log(
          '⚠️ VideoFeedAdvanced: Detected disposed controller for $videoId in _pauseAllOtherVideos, cleaning up: $e',
        );
        _controllerPool.remove(videoId);
        _controllerStates.remove(videoId);
      }
    });

    _videoControllerManager.pauseAllVideosOnTabChange();

    final sharedPool = SharedVideoControllerPool();
    sharedPool.pauseAllControllers(exceptVideoId: currentVideoId);
    _ensureWakelockForVisibility();
  }

  void forcePlayCurrent() {
    if (_videos.isEmpty ||
        _currentIndex < 0 ||
        _currentIndex >= _videos.length) {
      return;
    }

    final video = _videos[_currentIndex];
    final videoId = video.id;
    final controller = _controllerPool[videoId];

    bool isInitializedSafe = false;
    if (controller != null) {
      try {
        isInitializedSafe = controller.value.isInitialized;
      } catch (_) {
        _controllerPool.remove(videoId);
        _controllerStates.remove(videoId);
      }
    }

    if (controller != null && isInitializedSafe) {
      _pauseAllOtherVideos(videoId);
      _lifecyclePaused = false;
      controller.play();
      
      safeSetState(() {
        _controllerStates[videoId] = true;
        _userPaused[videoId] = false; // **Ensure user paused is reset**
        _getOrCreateNotifier<bool>(_userPausedVN, videoId, false);
      });
      
      _ensureWakelockForVisibility();
      return;
    }

    _preloadVideo(_currentIndex).then((_) {
      if (!mounted) return;
      final c = _controllerPool[videoId];
      bool cInit = false;
      if (c != null) {
        try {
          cInit = c.value.isInitialized;
        } catch (_) {
          _controllerPool.remove(videoId);
          _controllerStates.remove(videoId);
        }
      }
      if (c != null && cInit) {
        _pauseAllOtherVideos(videoId);
        _lifecyclePaused = false;
        c.play();
        
        safeSetState(() {
          _controllerStates[videoId] = true;
          _userPaused[videoId] = false;
          _getOrCreateNotifier<bool>(_userPausedVN, videoId, false);
        });
        
        _ensureWakelockForVisibility();
      }
    });
  }

  void _pauseCurrentVideo() {
    if (_currentIndex < _videos.length) {
      final currentVideo = _videos[_currentIndex];
      final videoId = currentVideo.id;
      _viewTracker.stopViewTracking(videoId);

      if (_controllerPool.containsKey(videoId)) {
        final controller = _controllerPool[videoId];

        if (controller != null) {
          try {
            final value = controller.value;
            if (value.isInitialized && value.isPlaying) {
              controller.pause();
              _controllerStates[videoId] = false;
            }
          } catch (e) {
            AppLogger.log(
              '⚠️ VideoFeedAdvanced: Detected disposed controller for $videoId in _pauseCurrentVideo, cleaning up: $e',
            );
            _controllerPool.remove(videoId);
            _controllerStates.remove(videoId);
          }
        }
      }
    }

    _videoControllerManager.pauseAllVideosOnTabChange();
  }

  void _pauseAllVideosOnTabSwitch() {
    _controllerPool.forEach((videoId, controller) {
      try {
        final value = controller.value;
        if (value.isInitialized && value.isPlaying) {
          controller.pause();
          _controllerStates[videoId] = false;
        }
      } catch (e) {
        AppLogger.log(
          '⚠️ VideoFeedAdvanced: Detected disposed controller for $videoId in _pauseAllVideosOnTabSwitch, cleaning up: $e',
        );
        _controllerPool.remove(videoId);
        _controllerStates.remove(videoId);
      }
    });

    _videoControllerManager.pauseAllVideosOnTabChange();
    SharedVideoControllerPool().pauseAllControllers();

    _isScreenVisible = false;
    _ensureWakelockForVisibility();
  }

  void _onSmartDubTap(VideoModel video) {
    final videoId = video.id;

    // 1. Check if already completed and has dubbed URL
    final currentResult = _dubbingResultsVN[videoId]?.value;
    if (currentResult != null &&
        currentResult.status == DubbingStatus.completed &&
        currentResult.dubbedUrl != null) {
      AppLogger.log('🎙️ VideoFeedAdvanced: Already dubbed. Opening language selector.');
      _showLanguageSelector(context, video);
      return;
    }

    // 2. If already processing, offer cancellation
    if (currentResult != null &&
        !currentResult.isDone &&
        currentResult.status != DubbingStatus.idle) {
       showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Cancel Dubbing?', style: TextStyle(color: Colors.white)),
          content: const Text(
            'Dubbing is in progress. Do you want to cancel it?',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep Going', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel Dub', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ).then((confirmed) {
        if (confirmed == true && mounted) {
          _dubbingSubscriptions[videoId]?.cancel();
          _dubbingSubscriptions.remove(videoId);
          _dubbingResultsVN[videoId]?.value = const DubbingResult(status: DubbingStatus.idle);
          AppLogger.log('🛑 Dubbing cancelled by user for $videoId');
        }
      });
      return;
    }

    // 3. Start dubbing request
    _dubbingSubscriptions[videoId]?.cancel();

    final resultVN = _getOrCreateNotifier<DubbingResult>(
      _dubbingResultsVN,
      videoId,
      const DubbingResult(status: DubbingStatus.idle),
    );

    final sub = _dubbingService.requestDub(videoId).listen((result) {
      if (!mounted) return;
      resultVN.value = result;

      // Show feedback snackbars for terminal states
      if (result.status == DubbingStatus.completed) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dubbing successful! Tap to play dubbed version.'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (result.status == DubbingStatus.notSuitable) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No vocal detected. Not suitable for dubbing.'),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else if (result.status == DubbingStatus.failed) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? 'Dubbing failed. Please try again.'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    });

    _dubbingSubscriptions[videoId] = sub;
  }

}
