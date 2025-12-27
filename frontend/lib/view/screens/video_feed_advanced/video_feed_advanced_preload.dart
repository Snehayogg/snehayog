part of 'package:vayu/view/screens/video_feed_advanced.dart';

extension _VideoFeedPreload on _VideoFeedAdvancedState {
  void _startPreloading() {
    _preloadTimer = Timer.periodic(const Duration(seconds: 2), (timer) {
      _preloadNearbyVideos();
    });
  }

  void _preloadNearbyVideos() {
    if (_videos.isEmpty) return;

    final sharedPool = SharedVideoControllerPool();

    // **FIX: Limit preloading when opened from ProfileScreen to prevent memory buildup**
    final bool openedFromProfile =
        widget.initialVideos != null && widget.initialVideos!.isNotEmpty;
    final int preloadWindow = openedFromProfile
        ? 1
        : 2; // Only preload 1 video ahead when from ProfileScreen
    final int keepRange = openedFromProfile
        ? 1
        : 3; // Keep only current video when from ProfileScreen

    for (int i = _currentIndex;
        i <= _currentIndex + preloadWindow && i < _videos.length;
        i++) {
      final video = _videos[i];

      if (sharedPool.isVideoLoaded(video.id)) {
        _preloadedVideos.add(i);
        continue;
      }

      if (!_preloadedVideos.contains(i) && !_loadingVideos.contains(i)) {
        _preloadVideo(i);
      }
    }

    sharedPool.cleanupDistantControllers(_currentIndex, keepRange: keepRange);

    // **FIXED: More aggressive loading - trigger when within threshold**
    // This ensures videos are loaded before user reaches the end
    final distanceFromEnd = _videos.length - _currentIndex;
    if (_hasMore && !_isLoadingMore) {
      // **PROACTIVE: Load when within threshold (5 videos from end)**
      if (_currentIndex >= _videos.length - _infiniteScrollThreshold) {
        AppLogger.log(
          '📡 Triggering load more: index=$_currentIndex, total=${_videos.length}, distanceFromEnd=$distanceFromEnd, hasMore=$_hasMore',
        );
        _loadMoreVideos();
      }
    } else if (!_hasMore) {
      AppLogger.log('✅ All videos loaded, no more to load');
    } else if (_isLoadingMore) {
      AppLogger.log('⏳ Already loading more videos, waiting...');
    }
  }

  Future<void> _preloadVideo(int index) async {
    if (index >= _videos.length) return;

    // **FIX: More aggressive limiting when opened from ProfileScreen**
    final bool openedFromProfile =
        widget.initialVideos != null && widget.initialVideos!.isNotEmpty;
    final int maxConcurrent = openedFromProfile
        ? 1
        : _maxConcurrentInitializations; // Only 1 concurrent when from ProfileScreen

    if (_initializingVideos.length >= maxConcurrent &&
        !_preloadedVideos.contains(index) &&
        !_loadingVideos.contains(index)) {
      AppLogger.log(
        '⏳ Max concurrent initializations reached (${_initializingVideos.length}/$maxConcurrent), deferring video $index',
      );
      // **OPTIMIZED: Reduced delay from 500ms to 100ms for faster retry**
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && !_preloadedVideos.contains(index)) {
          _preloadVideo(index);
        }
      });
      return;
    }

    _loadingVideos.add(index);

    AppLogger.log('🔄 Preloading video $index');
    _printCacheStatus();

    String? videoUrl;
    VideoPlayerController? controller;
    bool isReused = false;

    try {
      final video = _videos[index];

      // **NEW: Skip VideoPlayer setup for image-based entries (product images)**
      final lowerUrl =
          (video.videoUrl.isNotEmpty ? video.videoUrl : video.thumbnailUrl)
              .toLowerCase();
      final isImageEntry = lowerUrl.endsWith('.jpg') ||
          lowerUrl.endsWith('.jpeg') ||
          lowerUrl.endsWith('.png') ||
          lowerUrl.endsWith('.gif') ||
          lowerUrl.endsWith('.webp');

      if (isImageEntry) {
        AppLogger.log(
            '🖼️ Preload: Detected image-based entry at index $index (id=${video.id}), skipping VideoPlayer initialization');
        _preloadedVideos.add(index);
        _loadingVideos.remove(index);
        return;
      }

      videoUrl = await _resolvePlayableUrl(video);
      if (videoUrl == null || videoUrl.isEmpty) {
        AppLogger.log(
          '❌ Invalid video URL for video $index: ${video.videoUrl}',
        );
        _loadingVideos.remove(index);
        return;
      }

      AppLogger.log('🎬 Preloading video $index with URL: $videoUrl');

      final sharedPool = SharedVideoControllerPool();

      final instantController = sharedPool.getControllerForInstantPlay(
        video.id,
      );
      if (instantController != null) {
        controller = instantController;
        isReused = true;
        AppLogger.log(
          '⚡ INSTANT: Reusing controller from shared pool for video: ${video.id}',
        );
        _controllerPool[index] = controller;
        _lastAccessedLocal[index] = DateTime.now();
      } else if (sharedPool.isVideoLoaded(video.id)) {
        final fallbackController = sharedPool.getController(video.id);
        if (fallbackController != null) {
          controller = fallbackController;
          isReused = true;
          AppLogger.log(
            '♻️ Reusing controller from shared pool for video: ${video.id}',
          );
          _controllerPool[index] = controller;
          _lastAccessedLocal[index] = DateTime.now();
        }
      }

      if (controller == null) {
        final Map<String, String> headers = videoUrl.contains('.m3u8')
            ? const {
                'Accept': 'application/vnd.apple.mpegurl,application/x-mpegURL',
              }
            : const {};

        controller = VideoPlayerController.networkUrl(
          Uri.parse(videoUrl),
          videoPlayerOptions: VideoPlayerOptions(
            mixWithOthers: true,
            allowBackgroundPlayback: false,
          ),
          httpHeaders: headers,
        );
      }

      if (!isReused) {
        _initializingVideos.add(index);

        try {
          if (videoUrl.contains('.m3u8')) {
            AppLogger.log('🎬 HLS Video detected: $videoUrl');
            AppLogger.log('🎬 HLS Video duration: ${video.duration}');
            await controller.initialize().timeout(
              const Duration(seconds: 30),
              onTimeout: () {
                throw Exception('HLS video initialization timeout');
              },
            );
            AppLogger.log('✅ HLS Video initialized successfully');
          } else {
            AppLogger.log('🎬 Regular Video detected: $videoUrl');
            await controller.initialize().timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                throw Exception('Video initialization timeout');
              },
            );
            AppLogger.log('✅ Regular Video initialized successfully');
          }
        } finally {
          _initializingVideos.remove(index);
        }
      } else {
        AppLogger.log(
          '♻️ Skipping initialization - reusing initialized controller',
        );

        if (mounted && controller.value.isInitialized) {
          final isPlaying = controller.value.isPlaying;
          setState(() {
            _firstFrameReady[index] ??= ValueNotifier<bool>(false);
            if (_firstFrameReady[index]!.value != true) {
              _firstFrameReady[index]!.value = true;
            }
            if (!_userPaused.containsKey(index)) {
              _userPaused[index] = false;
            }
            if (!_controllerStates.containsKey(index)) {
              _controllerStates[index] = isPlaying;
            }
          });
          AppLogger.log(
            '🔄 Triggered rebuild for reused controller at index $index',
          );
        }
      }

      if (mounted && _loadingVideos.contains(index)) {
        _controllerPool[index] = controller;
        _controllerStates[index] = false;
        _preloadedVideos.add(index);
        _loadingVideos.remove(index);
        _lastAccessedLocal[index] = DateTime.now();

        final sharedPool = SharedVideoControllerPool();
        final video = _videos[index];
        sharedPool.addController(video.id, controller, index: index);
        AppLogger.log(
          '✅ Added video controller to shared pool: ${video.id} (index: $index)',
        );

        if (mounted) {
          setState(() {
            _firstFrameReady[index] ??= ValueNotifier<bool>(false);
            if (!_userPaused.containsKey(index)) {
              _userPaused[index] = false;
            }
            if (!_controllerStates.containsKey(index)) {
              _controllerStates[index] = false;
            }
          });
          AppLogger.log(
            '🔄 Triggered rebuild after controller initialization for index $index',
          );
        }

        _applyLoopingBehavior(controller);
        _attachEndListenerIfNeeded(controller, index);
        _attachBufferingListenerIfNeeded(controller, index);

        _firstFrameReady[index] ??= ValueNotifier<bool>(false);
        _firstFrameReady[index]!.value = false;

        // **WEB FIX: On web, force set firstFrameReady if controller has size**
        // Web video player might not trigger position updates the same way
        if (kIsWeb && controller.value.isInitialized) {
          final hasSize = controller.value.size.width > 0 &&
              controller.value.size.height > 0;
          if (hasSize) {
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted && _firstFrameReady[index]?.value != true) {
                _firstFrameReady[index]?.value = true;
                AppLogger.log(
                  '🌐 WEB FIX: Force set firstFrameReady for index $index (controller has size)',
                );
              }
            });
          }
        }

        if (index <= 1) {
          _forceMountPlayer[index] = ValueNotifier<bool>(false);
          Future.delayed(const Duration(milliseconds: 700), () {
            if (mounted && _firstFrameReady[index]?.value != true) {
              _forceMountPlayer[index]?.value = true;
            }
          });
        }
        final bool shouldPrime = _canPrimeIndex(index);
        if (shouldPrime) {
          try {
            await controller.setVolume(0.0);
            await controller.seekTo(const Duration(milliseconds: 1));
            await controller.play();
          } catch (_) {}
        }

        void markReadyIfNeeded() async {
          if (_firstFrameReady[index]?.value == true) return;
          final v = controller!.value;

          // **WEB FIX: On web, check if controller has size instead of position**
          // Web video might not update position immediately, but size is available
          final bool isReady = kIsWeb
              ? (v.isInitialized && v.size.width > 0 && v.size.height > 0)
              : (v.isInitialized &&
                  v.position > Duration.zero &&
                  !v.isBuffering);

          if (isReady) {
            _firstFrameReady[index]?.value = true;
            try {
              await controller.pause();
              await controller.setVolume(1.0);
            } catch (_) {}

            if (mounted) {
              setState(() {
                if (!_userPaused.containsKey(index)) {
                  _userPaused[index] = false;
                }
                if (!_controllerStates.containsKey(index)) {
                  _controllerStates[index] = false;
                }
              });
              AppLogger.log(
                '🔄 Triggered rebuild when first frame ready for index $index',
              );
            }

            // **NEW: Immediately trigger autoplay for current index when ready**
            if (index == _currentIndex) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _currentIndex == index) {
                  _tryAutoplayCurrentImmediate(index);
                }
              });
            }
          }
        }

        controller.addListener(markReadyIfNeeded);

        // **ENHANCED: For current index, immediately try autoplay after initialization**
        // Don't wait for first frame - this ensures fast autoplay for server-fetched videos
        if (index == _currentIndex && controller.value.isInitialized) {
          AppLogger.log(
            '⚡ VideoFeedAdvanced: Current video initialized, triggering immediate autoplay for index $index',
          );

          // **IMMEDIATE: Try autoplay right away without waiting for buffer**
          // For server-fetched videos, we want to start playing as soon as controller is initialized
          final currentController = controller;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                _currentIndex == index &&
                currentController.value.isInitialized) {
              AppLogger.log(
                '⚡ VideoFeedAdvanced: Triggering immediate autoplay (no buffer wait)',
              );
              _tryAutoplayCurrentImmediate(index);
            }
          });

          // **FALLBACK: Also check using callback in case immediate attempt didn't work**
          // Use postFrameCallback instead of delay for faster retry
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted &&
                _currentIndex == index &&
                currentController.value.isInitialized &&
                !currentController.value.isPlaying &&
                _userPaused[index] != true) {
              AppLogger.log(
                '⚡ VideoFeedAdvanced: Retrying autoplay after callback',
              );
              _tryAutoplayCurrentImmediate(index);
            }
          });

          // **ADDITIONAL FALLBACK: Wait for buffer if needed (reduced delay)**
          // Only if video still hasn't started playing after immediate attempts
          Future.delayed(const Duration(milliseconds: 200), () {
            if (mounted &&
                _currentIndex == index &&
                currentController.value.isInitialized &&
                !currentController.value.isPlaying &&
                _userPaused[index] != true) {
              final hasBuffer =
                  currentController.value.position > Duration.zero ||
                      !currentController.value.isBuffering;

              if (hasBuffer) {
                AppLogger.log(
                  '⚡ VideoFeedAdvanced: Final retry with buffer check',
                );
                _tryAutoplayCurrentImmediate(index);
              }
            }
          });
        }

        if (index == _currentIndex && index < _videos.length) {
          _viewTracker.startViewTracking(
            video.id,
            videoUploaderId: video.uploader.id,
          );
          AppLogger.log(
            '▶️ Started view tracking for preloaded current video: ${video.id}',
          );

          // **NEW: Preload creator's profile in background for instant profile opening**
          if (video.uploader.id.isNotEmpty && video.uploader.id != 'unknown') {
            ProfilePreloader().preloadProfile(video.uploader.id);
          }

          final bool openedFromProfile =
              widget.initialVideos != null && widget.initialVideos!.isNotEmpty;
          if (isReused &&
              controller.value.isInitialized &&
              !controller.value.isPlaying) {
            if (_userPaused[index] == true) {
              AppLogger.log(
                '⏸️ Autoplay suppressed for reused controller: user has manually paused video at index $index',
              );
            } else {
              if (openedFromProfile) {
                if (_allowAutoplay('reused controller (profile)')) {
                  _pauseAllOtherVideos(index);
                  controller.play();
                  _controllerStates[index] = true;
                  _userPaused[index] = false;
                  AppLogger.log(
                    '✅ Started playback for reused controller (from Profile)',
                  );
                }
              } else {
                if (_mainController?.currentIndex == 0 && _isScreenVisible) {
                  if (_allowAutoplay('reused controller at current index')) {
                    _pauseAllOtherVideos(index);
                    controller.play();
                    _controllerStates[index] = true;
                    _userPaused[index] = false;
                    AppLogger.log(
                      '✅ Started playback for reused controller at current index',
                    );
                  }
                }
              }
            }
          }

          if (_wasPlayingBeforeNavigation[index] == true &&
              controller.value.isInitialized &&
              !controller.value.isPlaying) {
            if (_userPaused[index] == true) {
              AppLogger.log(
                '⏸️ Resume suppressed: user has manually paused video ${video.id} at index $index',
              );
              _wasPlayingBeforeNavigation[index] = false;
            } else {
              if (openedFromProfile) {
                if (_allowAutoplay('resume controller (profile)')) {
                  _pauseAllOtherVideos(index);
                  controller.play();
                  _controllerStates[index] = true;
                  _userPaused[index] = false;
                  _wasPlayingBeforeNavigation[index] = false;
                  AppLogger.log(
                    '▶️ Resumed video ${video.id} that was playing before navigation (from Profile)',
                  );
                }
              } else {
                if (_mainController?.currentIndex == 0 && _isScreenVisible) {
                  if (_allowAutoplay('resume controller (current)')) {
                    _pauseAllOtherVideos(index);
                    controller.play();
                    _controllerStates[index] = true;
                    _userPaused[index] = false;
                    _wasPlayingBeforeNavigation[index] = false;
                    AppLogger.log(
                      '▶️ Resumed video ${video.id} that was playing before navigation',
                    );
                  }
                }
              }
            }
          }
        }

        AppLogger.log('✅ Successfully preloaded video $index');

        _preloadHits++;
        AppLogger.log('📊 Cache Status Update:');
        AppLogger.log('   Preload Hits: $_preloadHits');
        AppLogger.log('   Total Controllers: ${_controllerPool.length}');
        AppLogger.log('   Preloaded Videos: ${_preloadedVideos.length}');

        _cleanupOldControllers();
      } else {
        if (!isReused) {
          controller.dispose();
        }
      }
    } catch (e) {
      AppLogger.log('❌ Error preloading video $index: $e');
      _loadingVideos.remove(index);
      _initializingVideos.remove(index);

      if (controller != null && !isReused) {
        try {
          if (controller.value.isInitialized) {
            await controller.pause();
          }
          controller.dispose();
          AppLogger.log('🗑️ Disposed failed controller for video $index');
        } catch (disposeError) {
          AppLogger.log('⚠️ Error disposing failed controller: $disposeError');
        }
      }

      final errorString = e.toString().toLowerCase();
      final isNoMemoryError = errorString.contains('no_memory') ||
          errorString.contains('0xfffffff4') ||
          errorString.contains('error 12') ||
          (errorString.contains('failed to initialize') &&
              errorString.contains('no_memory')) ||
          (errorString.contains('mediacodec') &&
              errorString.contains('memory')) ||
          (errorString.contains('videoplayer') &&
              errorString.contains('exoplaybackexception') &&
              errorString.contains('mediacodec'));

      final retryCount = _preloadRetryCount[index] ?? 0;

      if (isNoMemoryError) {
        AppLogger.log('⚠️ NO_MEMORY error detected for video $index');

        _cleanupOldControllers();

        if (retryCount < _maxRetryAttempts) {
          _preloadRetryCount[index] = retryCount + 1;
          final retryDelay = Duration(seconds: 10 + (retryCount * 5));
          AppLogger.log(
            '🔄 Retrying video $index after ${retryDelay.inSeconds} seconds (attempt ${retryCount + 1}/$_maxRetryAttempts)...',
          );
          Future.delayed(retryDelay, () {
            if (mounted && !_preloadedVideos.contains(index)) {
              _preloadVideo(index);
            }
          });
        } else {
          AppLogger.log(
            '❌ Max retry attempts reached for video $index (NO_MEMORY)',
          );
          _preloadRetryCount.remove(index);
        }
      } else if (videoUrl != null && videoUrl.contains('.m3u8')) {
        if (retryCount < _maxRetryAttempts) {
          _preloadRetryCount[index] = retryCount + 1;
          AppLogger.log('🔄 HLS video failed, retrying in 3 seconds...');
          AppLogger.log('🔄 HLS Error details: $e');
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted && !_preloadedVideos.contains(index)) {
              _preloadVideo(index);
            }
          });
        } else {
          AppLogger.log('❌ Max retry attempts reached for HLS video $index');
          _preloadRetryCount.remove(index);
        }
      } else if (e.toString().contains('400') || e.toString().contains('404')) {
        if (retryCount < _maxRetryAttempts) {
          _preloadRetryCount[index] = retryCount + 1;
          AppLogger.log('🔄 Retrying video $index in 5 seconds...');
          Future.delayed(const Duration(seconds: 5), () {
            if (mounted && !_preloadedVideos.contains(index)) {
              _preloadVideo(index);
            }
          });
        } else {
          AppLogger.log('❌ Max retry attempts reached for video $index');
          _preloadRetryCount.remove(index);
        }
      } else {
        AppLogger.log('❌ Video preload failed with error: $e');
        AppLogger.log('❌ Video URL: $videoUrl');
        AppLogger.log('❌ Video index: $index');
        _preloadRetryCount.remove(index);
      }
    }
  }

  String? _validateAndFixVideoUrl(String url) {
    if (url.isEmpty) return null;

    if (!url.startsWith('http')) {
      String cleanUrl = url;
      if (cleanUrl.startsWith('/')) {
        cleanUrl = cleanUrl.substring(1);
      }
      return '${VideoService.baseUrl}/$cleanUrl';
    }

    try {
      final uri = Uri.parse(url);
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        return url;
      }
    } catch (e) {
      AppLogger.log('❌ Invalid URL format: $url');
    }

    return null;
  }

  Future<String?> _resolvePlayableUrl(VideoModel video) async {
    try {
      final hlsUrl = video.hlsPlaylistUrl?.isNotEmpty == true
          ? video.hlsPlaylistUrl
          : video.hlsMasterPlaylistUrl;
      if (hlsUrl != null && hlsUrl.isNotEmpty) {
        return _validateAndFixVideoUrl(hlsUrl);
      }

      if (video.videoUrl.contains('.m3u8') || video.videoUrl.contains('.mp4')) {
        return _validateAndFixVideoUrl(video.videoUrl);
      }

      final uri = Uri.tryParse(video.videoUrl);
      if (uri != null &&
          uri.host.contains('snehayog.site') &&
          uri.pathSegments.isNotEmpty &&
          uri.pathSegments.first == 'video') {
        try {
          final details = await VideoService().getVideoById(video.id);
          final candidate = details.hlsPlaylistUrl?.isNotEmpty == true
              ? details.hlsPlaylistUrl
              : details.videoUrl;
          if (candidate != null && candidate.isNotEmpty) {
            return _validateAndFixVideoUrl(candidate);
          }
        } catch (_) {}
      }

      return _validateAndFixVideoUrl(video.videoUrl);
    } catch (_) {
      return _validateAndFixVideoUrl(video.videoUrl);
    }
  }

  void _cleanupOldControllers() {
    final sharedPool = SharedVideoControllerPool();

    sharedPool.cleanupDistantControllers(_currentIndex, keepRange: 3);

    final controllersToRemove = <int>[];

    for (final index in _controllerPool.keys.toList()) {
      if (index < _videos.length) {
        final videoId = _videos[index].id;
        if (sharedPool.isVideoLoaded(videoId)) {
          controllersToRemove.add(index);
          continue;
        }
      }

      final distance = (index - _currentIndex).abs();
      if (distance > 3 || _controllerPool.length > 5) {
        controllersToRemove.add(index);
      }
    }

    for (final index in controllersToRemove) {
      final ctrl = _controllerPool[index];

      if (index < _videos.length) {
        final videoId = _videos[index].id;
        if (!sharedPool.isVideoLoaded(videoId) && ctrl != null) {
          try {
            ctrl.removeListener(_bufferingListeners[index] ?? () {});
            ctrl.removeListener(_videoEndListeners[index] ?? () {});
            ctrl.dispose();
          } catch (e) {
            AppLogger.log('⚠️ Error disposing controller at index $index: $e');
          }
        }
      }

      _controllerPool.remove(index);
      _controllerStates.remove(index);
      _preloadedVideos.remove(index);
      _isBuffering.remove(index);
      _bufferingListeners.remove(index);
      _videoEndListeners.remove(index);
      _lastAccessedLocal.remove(index);
      _initializingVideos.remove(index);
      _preloadRetryCount.remove(index);
    }

    if (controllersToRemove.isNotEmpty) {
      AppLogger.log(
        '🧹 Cleaned up ${controllersToRemove.length} local controller trackings',
      );
    }
  }

  VideoPlayerController? _getController(int index) {
    if (index >= _videos.length) return null;

    final video = _videos[index];
    final sharedPool = SharedVideoControllerPool();

    VideoPlayerController? controller = sharedPool.getControllerForInstantPlay(
      video.id,
    );

    if (controller != null && controller.value.isInitialized) {
      AppLogger.log(
        '⚡ INSTANT: Reusing controller from shared pool for video ${video.id}',
      );

      _controllerPool[index] = controller;
      _controllerStates[index] = false;
      _preloadedVideos.add(index);
      _lastAccessedLocal[index] = DateTime.now();
      _firstFrameReady[index] ??= ValueNotifier<bool>(false);
      _firstFrameReady[index]!.value = true;
    }

    if (_controllerPool.containsKey(index)) {
      controller = _controllerPool[index];
      if (controller != null && controller.value.isInitialized) {
        _lastAccessedLocal[index] = DateTime.now();
        _firstFrameReady[index] ??= ValueNotifier<bool>(false);
        _firstFrameReady[index]!.value = true;
        return controller;
      }
    }

    _preloadVideo(index);
    return null;
  }

  void _onPageChanged(int index) {
    if (index == _currentIndex) return;
    _pageChangeTimer?.cancel();
    _pageChangeTimer = Timer(const Duration(milliseconds: 150), () {
      _handlePageChangeDebounced(index);
    });
  }

  void _handlePageChangeDebounced(int index) {
    if (!mounted || index == _currentIndex) return;

    _lifecyclePaused = false;

    _lastAccessedLocal[_currentIndex] = DateTime.now();

    if (_currentIndex < _videos.length) {
      final previousVideo = _videos[_currentIndex];
      _viewTracker.stopViewTracking(previousVideo.id);
      AppLogger.log(
        '⏸️ Stopped view tracking for previous video: ${previousVideo.id}',
      );

      _userPaused[_currentIndex] = false;
    }

    _controllerPool.forEach((idx, controller) {
      if (controller.value.isInitialized && controller.value.isPlaying) {
        try {
          controller.pause();
          _controllerStates[idx] = false;
        } catch (_) {}
      }
    });

    _videoControllerManager.pauseAllVideosOnTabChange();

    final sharedPool = SharedVideoControllerPool();
    sharedPool.pauseAllControllers();

    _currentIndex = index;
    _autoAdvancedForIndex.remove(index);

    // **MEMORY MANAGEMENT: Periodic cleanup on page change**
    // Cleanup every 10 pages to prevent memory buildup
    if (index % 10 == 0 &&
        _videos.length > VideoFeedStateFieldsMixin._videosCleanupThreshold) {
      _cleanupOldVideosFromList();
    }

    // **CRITICAL FIX: Check if we need to load more videos BEFORE checking if we're at the end**
    // This ensures new videos are loaded when approaching the end
    _reprimeWindowIfNeeded();

    // **FIXED: Try to load more videos first before restarting**
    // Only restart if we've truly reached the end AND there are no more videos to load
    if (index >= _videos.length && !_isRefreshing) {
      // If we have more videos available, try loading them first
      if (_hasMore && !_isLoadingMore) {
        AppLogger.log(
          '📡 Reached end but more videos available, loading more...',
        );
        _loadMoreVideos();
        // Wait a bit for videos to load before restarting
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted &&
              index >= _videos.length &&
              !_hasMore &&
              !_isRefreshing) {
            AppLogger.log(
              '🔄 No more videos available, restarting feed...',
            );
            startOver();
          }
        });
        return;
      } else if (!_hasMore) {
        // Only restart if we truly have no more videos
        AppLogger.log(
          '🔄 Reached end of feed at index $index, no more videos, restarting...',
        );
        startOver();
        return;
      }
    }

    final activeController = _controllerPool[_currentIndex];
    if (activeController != null && activeController.value.isInitialized) {
      try {
        activeController.setVolume(1.0);
      } catch (_) {}
    }

    VideoPlayerController? controllerToUse;

    if (index < _videos.length) {
      final video = _videos[index];
      _markVideoAsSeen(video);

      controllerToUse = sharedPool.getControllerForInstantPlay(video.id);

      if (controllerToUse != null && controllerToUse.value.isInitialized) {
        AppLogger.log(
          '⚡ INSTANT: Reusing controller from shared pool for video ${video.id}',
        );

        _controllerPool[index] = controllerToUse;
        _controllerStates[index] = false;
        _preloadedVideos.add(index);
        _lastAccessedLocal[index] = DateTime.now();
        _firstFrameReady[index] ??= ValueNotifier<bool>(false);
        _firstFrameReady[index]!.value = true;
      } else if (sharedPool.isVideoLoaded(video.id)) {
        controllerToUse = sharedPool.getController(video.id);
        if (controllerToUse != null && controllerToUse.value.isInitialized) {
          _controllerPool[index] = controllerToUse;
          _controllerStates[index] = false;
          _preloadedVideos.add(index);
          _lastAccessedLocal[index] = DateTime.now();
          _firstFrameReady[index] ??= ValueNotifier<bool>(false);
          _firstFrameReady[index]!.value = true;
        }
      }
    }

    if (controllerToUse == null && _controllerPool.containsKey(index)) {
      controllerToUse = _controllerPool[index];
      if (controllerToUse != null && !controllerToUse.value.isInitialized) {
        AppLogger.log('⚠️ Controller exists but not initialized, disposing...');
        try {
          controllerToUse.dispose();
        } catch (e) {
          AppLogger.log('Error disposing controller: $e');
        }
        _controllerPool.remove(index);
        _controllerStates.remove(index);
        _preloadedVideos.remove(index);
        _lastAccessedLocal.remove(index);
        controllerToUse = null;
      } else if (controllerToUse != null &&
          controllerToUse.value.isInitialized) {
        _lastAccessedLocal[index] = DateTime.now();
        _firstFrameReady[index] ??= ValueNotifier<bool>(false);
        _firstFrameReady[index]!.value = true;
      }
    }

    if (controllerToUse != null && controllerToUse.value.isInitialized) {
      if (_mainController?.currentIndex != 0 || !_isScreenVisible) {
        AppLogger.log('⏸️ Autoplay blocked (not visible)');
        return;
      }

      if (_userPaused[index] == true) {
        AppLogger.log(
          '⏸️ Autoplay suppressed: user has manually paused video at index $index',
        );
        return;
      }

      if (!_allowAutoplay('page change autoplay')) {
        return;
      }
      _pauseAllOtherVideos(index);

      controllerToUse.setVolume(1.0);
      controllerToUse.play();
      _controllerStates[index] = true;
      _userPaused[index] = false;
      _ensureWakelockForVisibility();
      _applyLoopingBehavior(controllerToUse);
      _attachEndListenerIfNeeded(controllerToUse, index);
      _attachBufferingListenerIfNeeded(controllerToUse, index);

      if (index < _videos.length) {
        final currentVideo = _videos[index];
        _viewTracker.startViewTracking(
          currentVideo.id,
          videoUploaderId: currentVideo.uploader.id,
        );
        AppLogger.log(
          '▶️ Started view tracking for current video: ${currentVideo.id}',
        );

        // **NEW: Preload creator's profile in background for instant profile opening**
        if (currentVideo.uploader.id.isNotEmpty &&
            currentVideo.uploader.id != 'unknown') {
          ProfilePreloader().preloadProfile(currentVideo.uploader.id);
        }
      }

      _preloadNearbyVideosDebounced();
      return;
    }

    if (!_controllerPool.containsKey(index)) {
      AppLogger.log(
        '🔄 Video not preloaded, preloading and will autoplay when ready',
      );
      _preloadVideo(index).then((_) {
        if (mounted &&
            _currentIndex == index &&
            _controllerPool.containsKey(index)) {
          if (_mainController?.currentIndex != 0 || !_isScreenVisible) {
            AppLogger.log('⏸️ Autoplay blocked after preload (not visible)');
            return;
          }
          final loadedController = _controllerPool[index];
          if (loadedController != null &&
              loadedController.value.isInitialized) {
            _lastAccessedLocal[index] = DateTime.now();

            if (!_allowAutoplay('post preload autoplay')) {
              return;
            }
            _pauseAllOtherVideos(index);

            loadedController.setVolume(1.0);
            loadedController.play();
            _controllerStates[index] = true;
            _userPaused[index] = false;
            _ensureWakelockForVisibility();
            _applyLoopingBehavior(loadedController);
            _attachEndListenerIfNeeded(loadedController, index);
            _attachBufferingListenerIfNeeded(loadedController, index);

            if (index < _videos.length) {
              final currentVideo = _videos[index];
              _viewTracker.startViewTracking(
                currentVideo.id,
                videoUploaderId: currentVideo.uploader.id,
              );
              AppLogger.log(
                '▶️ Started view tracking for current video: ${currentVideo.id}',
              );

              // **NEW: Preload creator's profile in background for instant profile opening**
              if (currentVideo.uploader.id.isNotEmpty &&
                  currentVideo.uploader.id != 'unknown') {
                ProfilePreloader().preloadProfile(currentVideo.uploader.id);
              }
            }

            AppLogger.log('✅ Video autoplay started after preloading');
          }
        }
      });
    }

    _preloadNearbyVideosDebounced();
  }

  void _preloadNearbyVideosDebounced() {
    _preloadDebounceTimer?.cancel();
    _preloadDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _preloadNearbyVideos();
    });
  }

  void _applyLoopingBehavior(VideoPlayerController controller) {
    try {
      controller.setLooping(false);
    } catch (e) {
      AppLogger.log('⚠️ Error applying looping behavior: $e');
    }
  }

  void _attachEndListenerIfNeeded(VideoPlayerController controller, int index) {
    final existingListener = _videoEndListeners[index];
    if (existingListener != null) {
      controller.removeListener(existingListener);
    }

    void handleVideoEnd() {
      if (!mounted) return;
      final value = controller.value;
      if (!value.isInitialized) return;

      final duration = value.duration;
      if (duration == Duration.zero) return;

      final position = value.position;
      final remaining = duration - position;

      final bool isCompleted = !value.isPlaying &&
          !value.isBuffering &&
          remaining <= const Duration(milliseconds: 250);

      if (isCompleted) {
        _handleVideoCompleted(index);
      }
    }

    _videoEndListeners[index] = handleVideoEnd;
    controller.addListener(handleVideoEnd);
  }

  void _attachBufferingListenerIfNeeded(
    VideoPlayerController controller,
    int index,
  ) {
    final existingListener = _bufferingListeners[index];
    if (existingListener != null) {
      controller.removeListener(existingListener);
    }

    void handleBuffering() {
      if (!mounted) return;
      final value = controller.value;
      if (!value.isInitialized) return;

      final bool isBuffering = value.isBuffering;
      if (_isBuffering[index] == isBuffering) return;

      _isBuffering[index] = isBuffering;
      final notifier = _isBufferingVN[index] ??= ValueNotifier<bool>(
        isBuffering,
      );
      if (notifier.value != isBuffering) {
        notifier.value = isBuffering;
      }
    }

    _bufferingListeners[index] = handleBuffering;
    controller.addListener(handleBuffering);
    handleBuffering();
  }

  void _handleVideoCompleted(int index) {
    if (_userPaused[index] == true) return;
    if (_autoAdvancedForIndex.contains(index)) return;
    _autoAdvancedForIndex.add(index);

    if (index < _videos.length) {
      final video = _videos[index];
      _viewTracker.stopViewTracking(video.id);

      // **NEW: Track video completion for watch history**
      final controller = _controllerPool[index];
      if (controller != null && controller.value.isInitialized) {
        final duration = controller.value.duration.inSeconds;
        _viewTracker.trackVideoCompletion(
          video.id,
          duration: duration,
        );
      }
      AppLogger.log('⏹️ Completed video playback for ${video.id}');
    }

    _resetControllerForReplay(index);

    if (_autoScrollEnabled) {
      _queueAutoAdvance(index);
    } else {
      _autoAdvancedForIndex.remove(index);
    }
  }

  void _queueAutoAdvance(int index) {
    final nextIndex = index + 1;
    if (nextIndex >= _videos.length) {
      AppLogger.log('ℹ️ Last video reached, auto-scroll skipped');
      _autoAdvancedForIndex.remove(index);
      return;
    }
    if (!_pageController.hasClients) return;
    if (_isAnimatingPage) return;

    _isAnimatingPage = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_pageController.hasClients) {
        _isAnimatingPage = false;
        return;
      }
      _pageController
          .animateToPage(
        nextIndex,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      )
          .whenComplete(() {
        _isAnimatingPage = false;
        _autoAdvancedForIndex.remove(index);
      });
    });
  }

  void _resetControllerForReplay(int index) {
    final controller = _controllerPool[index];
    if (controller == null || !controller.value.isInitialized) return;

    try {
      controller.pause();
      controller.seekTo(Duration.zero);
      controller.setVolume(1.0);
    } catch (e) {
      AppLogger.log('⚠️ Error resetting controller at index $index: $e');
    }

    _controllerStates[index] = false;
    _userPaused[index] = false;
    _isBuffering[index] = false;
    if (_isBufferingVN[index]?.value == true) {
      _isBufferingVN[index]?.value = false;
    }
    _firstFrameReady[index]?.value = true;
    _ensureWakelockForVisibility();
  }

  // **NEW: Immediate autoplay helper that doesn't wait for full buffer**
  void _tryAutoplayCurrentImmediate(int index) {
    if (_videos.isEmpty || _isLoading) return;
    if (index != _currentIndex) return; // Make sure index hasn't changed
    // **CRITICAL FIX: Use _shouldAutoplayForContext instead of _allowAutoplay**
    // This ensures Yug tab visibility is checked before autoplay
    if (!_shouldAutoplayForContext('tryAutoplayCurrentImmediate')) return;

    final controller = _controllerPool[index];
    if (controller != null &&
        controller.value.isInitialized &&
        !controller.value.isPlaying) {
      if (_userPaused[index] == true) {
        AppLogger.log(
          '⏸️ Autoplay suppressed: user has manually paused video at index $index',
        );
        return;
      }

      try {
        controller.setVolume(1.0);
      } catch (_) {}

      // **CRITICAL FIX: Use _shouldAutoplayForContext instead of _allowAutoplay**
      if (!_shouldAutoplayForContext('autoplay immediate')) return;

      _pauseAllOtherVideos(index);

      // **ENHANCED: Try to play immediately, with error handling**
      final controllerToPlay = controller;
      try {
        controllerToPlay.play();
        _ensureWakelockForVisibility();
        _controllerStates[index] = true;
        _userPaused[index] = false;
        _pendingAutoplayAfterLogin = false;
        AppLogger.log(
            '⚡ VideoFeedAdvanced: Immediate autoplay started for index $index');

        // **NEW: Verify play actually started, retry if needed (use callback instead of delay)**
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              _currentIndex == index &&
              controllerToPlay.value.isInitialized &&
              !controllerToPlay.value.isPlaying &&
              _userPaused[index] != true) {
            AppLogger.log(
                '⚠️ VideoFeedAdvanced: Play command didn\'t start, retrying...');
            try {
              controllerToPlay.play();
            } catch (e) {
              AppLogger.log('❌ VideoFeedAdvanced: Retry play failed: $e');
            }
          }
        });
      } catch (e) {
        AppLogger.log(
            '❌ VideoFeedAdvanced: Immediate autoplay failed: $e, will retry');
        // Retry using callback instead of delay for faster recovery
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              _currentIndex == index &&
              controllerToPlay.value.isInitialized &&
              !controllerToPlay.value.isPlaying &&
              _userPaused[index] != true) {
            try {
              controllerToPlay.play();
              _ensureWakelockForVisibility();
              _controllerStates[index] = true;
              _userPaused[index] = false;
              AppLogger.log(
                  '✅ VideoFeedAdvanced: Autoplay started on retry for index $index');
            } catch (retryError) {
              AppLogger.log(
                  '❌ VideoFeedAdvanced: Retry autoplay failed: $retryError');
            }
          }
        });
      }
    }
  }
}
