part of 'package:vayu/view/screens/video_feed_advanced.dart';

extension _VideoFeedPreload on _VideoFeedAdvancedState {
  static bool _isLowEndDevice = false; // Default to false (assume high-end)



  Future<void> _checkDeviceCapabilities() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        // Consider devices with <= 4GB RAM as "Low End" for heavy video tasks
        // isLowRamDevice is a reliable flag from Android API
        // physicalRamSize is in MB (device_info_plus)
        final ramInMB = (androidInfo.physicalRamSize).toDouble();
        _isLowEndDevice = androidInfo.isLowRamDevice || (ramInMB <= 4096);
        AppLogger.log('📱 Device Capability: ${_isLowEndDevice ? "Low End" : "High End"} (RAM: ${(ramInMB / 1024).toStringAsFixed(1)} GB)');
        // iOS memory management is better, but safe default
        // final iosInfo = await DeviceInfoPlugin().iosInfo;
        // iPhone 8 or older / iPads with < 3GB RAM could be considered low end
        // Simple heuristic: assume modern iOS devices are high end unless very old
        _isLowEndDevice = false; 
      }
    } catch (e) {
      AppLogger.log('⚠️ Error checking device capabilities: $e');
    }
  }

  void _preloadNearbyVideos() {
    if (_videos.isEmpty) return;

    // **SMART NETWORK CLEANUP: Before adding new requests, cancel old/distant ones**
    _cleanupOldControllers();

    final sharedPool = SharedVideoControllerPool();
    
    // **SMART STRATEGY: Directional Awareness + Device Capability**
    final isScrollingDown = _currentIndex >= _previousIndex;
    
    // **CONFIG: Window Sizes based on Device Tier**
    // Low End: Focus ONLY on next video. Kill previous instantly.
    // High End: Keep buffer behind and ahead for smooth "flick" scrolling.
    
    final int nextWindow = _isLowEndDevice ? 1 : 2;
    // Low End: 0 Previous (Ghost Cache will handle back navigation)
    // High End: 2 Previous (Keep them hot in RAM)
    final int prevWindow = _isLowEndDevice ? 0 : 2; 

    // **1. PRELOAD NEXT (Forward Direction)**
    // Always priority #1 as users mostly scroll down
    for (int i = _currentIndex + 1; i <= _currentIndex + nextWindow && i < _videos.length; i++) {
       _preloadVideo(i);
    }

    // **2. PRELOAD PREVIOUS (Backward Direction)**
    // Only if High End OR if user is actually scrolling UP
    if (!_isLowEndDevice || !isScrollingDown) {
        // If scrolling UP on low-end, we temporarily allow 1 previous
        final effectivePrevWindow = (!isScrollingDown && _isLowEndDevice) ? 1 : prevWindow;
        
        for (int i = _currentIndex - 1; i >= _currentIndex - effectivePrevWindow && i >= 0; i--) {
           _preloadVideo(i);
        }
    }

    // **3. CLEANUP (The "Focus Mode")**
    // Aggressively kill anything outside our smart windows
    // Calculate keep range based on windows
    final safeRangeStart = _currentIndex - prevWindow;
    final safeRangeEnd = _currentIndex + nextWindow;
    
    sharedPool.cleanupSmart(_currentIndex, safeRangeStart, safeRangeEnd);

    // **NEW: Background preload of second page immediately after first page**
    if (!_hasStartedBackgroundPreload &&
        _videos.isNotEmpty &&
        _hasMore &&
        !_isLoadingMore) {
      // One-time log, okay to keep
      AppLogger.log(
          '🚀 Background Preload: Starting to load Page 2 in background...');
      _hasStartedBackgroundPreload = true;
      _loadMoreVideos();
    }

    // **FIXED: Dynamic loading trigger based on total videos**
    final distanceFromEnd = _videos.length - _currentIndex;
    if (_hasMore && !_isLoadingMore) {
      const triggerDistance = 20;
      if (distanceFromEnd <= triggerDistance) {
        _loadMoreVideos();
      }
    }
  }

  /// **PRELOAD SINGLE VIDEO**
  Future<void> _preloadVideo(int index) async {
    if (index >= _videos.length) return;

    // **RACE CONDITION FIX: Don't double-load if already loading**
    if (_loadingVideos.contains(index)) {
      // Ensure we re-check smart autoplay even if skipping load
      if (mounted && index == _currentIndex) {
        AppLogger.log('⏳ Video $index already loading, queuing smart autoplay check');
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && index == _currentIndex) {
             _tryAutoplayCurrentImmediate(index);
          }
        });
      }
      return;
    }

    // **NEW: Check if we're already at max concurrent initializations**
    if (_initializingVideos.length >= _maxConcurrentInitializations &&
        !_preloadedVideos.contains(index) &&
        !_loadingVideos.contains(index)) {
      // Queue this video for later initialization
      AppLogger.log(
        '⏳ Max concurrent initializations reached, deferring video $index',
      );
      Future.delayed(const Duration(milliseconds: 100), () {
        if (mounted && !_preloadedVideos.contains(index)) {
          _preloadVideo(index);
        }
      });
      return;
    }

    _loadingVideos.add(index);

    // **CACHE STATUS CHECK ON PRELOAD**
    AppLogger.log('🔄 Preloading video $index');
    _printCacheStatus();

    String? videoUrl;
    VideoPlayerController? controller;
    bool isReused = false;

    try {
      final video = _videos[index];

      // **FIXED: Resolve playable URL (handles share page URLs)**
      videoUrl = await _resolvePlayableUrl(video);
      if (videoUrl == null || videoUrl.isEmpty) {
        AppLogger.log(
          '❌ Invalid video URL for video $index: ${video.videoUrl}',
        );
        if (mounted) {
          safeSetState(() {
            _loadingVideos.remove(index);
          });
        }
        return;
      }

      AppLogger.log('🎬 Preloading video $index with URL: $videoUrl');

      // **UNIFIED STRATEGY: Check shared pool FIRST for instant playback**
      final sharedPool = SharedVideoControllerPool();

      // **INSTANT LOADING: Try to get controller with instant playback guarantee**
      final instantController = sharedPool.getControllerForInstantPlay(
        video.id,
      );
      if (instantController != null) {
        controller = instantController;
        isReused = true;
        AppLogger.log(
          '⚡ INSTANT: Reusing controller from shared pool for video: ${video.id}',
        );
        // **CRITICAL: Add to local tracking for UI updates**
        _controllerPool[index] = controller;
        _lastAccessedLocal[index] = DateTime.now();
      } else if (sharedPool.isVideoLoaded(video.id)) {
        // Fallback: Get any controller from shared pool
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

      // **FIX: Ensure background videos are PAUSED if reused**
      // If we grabbed a playing controller for a future/past video, stop it now.
      if (controller != null && index != _currentIndex && controller.value.isPlaying) {
        AppLogger.log('⏸️ Pausing reused background controller at index $index');
        controller.pause();
      }

      // If no controller in shared pool, create new one
      if (controller == null) {
        // **HLS SUPPORT: Check if URL is HLS and configure accordingly**
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

      // **SKIP INITIALIZATION: If reusing from shared pool, controller is already initialized**
      if (!isReused) {
        // **NEW: Track concurrent initializations**
        _initializingVideos.add(index);

        try {
          // **HLS SUPPORT: Add HLS-specific configuration**
          if (videoUrl.contains('.m3u8')) {
            AppLogger.log('🎬 HLS Video detected: $videoUrl');
            AppLogger.log('🎬 HLS Video duration: ${video.duration}');
            await controller!.initialize().timeout(
              const Duration(seconds: 12), // **OPTIMIZED: 30s -> 12s (Fail Fast)**
              onTimeout: () {
                throw Exception('HLS video initialization timeout');
              },
            );
            AppLogger.log('✅ HLS Video initialized successfully');
          } else {
             AppLogger.log('🎬 Regular Video detected: $videoUrl');
            // **FIXED: Add timeout and better error handling for regular videos**
            await controller!.initialize().timeout(
              const Duration(seconds: 8), // **OPTIMIZED: 10s -> 8s (Fail Fast)**
              onTimeout: () {
                throw Exception('Video initialization timeout');
              },
            );
            AppLogger.log('✅ Regular Video initialized successfully');
          }
          
          // **DEFENSIVE FIX: Ensure new controller didn't auto-start**
          if (index != _currentIndex && controller!.value.isPlaying) {
             AppLogger.log('⏸️ Auto-started video paused at index $index');
             controller.pause();
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
          // **OPTIMIZED: No setState needed - just update maps directly**
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
          AppLogger.log(
            '🔄 Triggered rebuild for reused controller at index $index',
          );
        }
      }

      if (mounted && _loadingVideos.contains(index)) {
        // **FIX: Use safeSetState (helper in main class) to trigger UI rebuild**
        safeSetState(() {
          _controllerPool[index] = controller!;
          _controllerStates[index] = false;
          _preloadedVideos.add(index);
          _loadingVideos.remove(index);
          _lastAccessedLocal[index] = DateTime.now();
        });

        final sharedPool = SharedVideoControllerPool();
        final video = _videos[index];
        sharedPool.addController(video.id, controller, index: index);
        AppLogger.log(
          '✅ Added video controller to shared pool: ${video.id} (index: $index)',
        );

        // **FIX: Trigger rebuild after controller initialization**
        if (mounted) {
          // **FIXED: Use safeSetState instead of raw setState**
          safeSetState(() {
            _firstFrameReady[index] ??= ValueNotifier<bool>(false);
            if (!_userPaused.containsKey(index)) {
              _userPaused[index] = false;
            }
            if (!_controllerStates.containsKey(index)) {
              _controllerStates[index] = false;
            }
          });
        }

        // Apply behaviors and listeners
        _applyLoopingBehavior(controller);
        _attachEndListenerIfNeeded(controller, index);
        _attachBufferingListenerIfNeeded(controller, index);
        _attachErrorListenerIfNeeded(controller, index);

        // First-frame priming
        _firstFrameReady[index] = ValueNotifier<bool>(isReused);
        if (index <= 1 && !isReused) {
          _forceMountPlayer[index] = ValueNotifier<bool>(false);
          Future.delayed(const Duration(milliseconds: 700), () {
            if (mounted && _firstFrameReady[index]?.value != true) {
              _forceMountPlayer[index]?.value = true;
            }
          });
        }
      }

      // **SMART AUTOPLAY: If this video finished loading and user is watching it, PLAY NOW**
      if (mounted && index == _currentIndex) {
         AppLogger.log('🎯 Smart Autoplay: Video $index finished loading and is active. Calling Play.');
         
         // **CRITICAL FIX: Explicitly call play() instantly to avoid any state race conditions**
         if (controller.value.isInitialized) {
             await controller.play();
         }
         
         _tryAutoplayCurrentImmediate(index);
      }

    } catch (e) {
      if (mounted) {
        safeSetState(() {
           _loadingVideos.remove(index);
        });
      }
      final retryCount = _preloadRetryCount[index] ?? 0;
      if (e.toString().contains('NO_MEMORY') ||
          e.toString().contains('OutOfMemory')) {
        if (retryCount < _maxRetryAttempts) {
          _preloadRetryCount[index] = retryCount + 1;
          _cleanupOldControllers();
          final retryDelay = Duration(milliseconds: 500 * (retryCount + 1));
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
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted && !_preloadedVideos.contains(index)) {
              _preloadVideo(index);
            }
          });
        } else {
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
          _preloadRetryCount.remove(index);
        }
      } else {
        AppLogger.log('❌ Video preload failed with error: $e');
        _preloadRetryCount.remove(index);
      }
    }
  }


  String? _validateAndFixVideoUrl(String url) {
    if (url.isEmpty) return null;

    String finalUrl = url;

    if (!url.startsWith('http')) {
      String cleanUrl = url;
      if (cleanUrl.startsWith('/')) {
        cleanUrl = cleanUrl.substring(1);
      }
      finalUrl = '${VideoService.baseUrl}/$cleanUrl';
    } else {
      try {
        final uri = Uri.parse(url);
        if (uri.scheme == 'http' || uri.scheme == 'https') {
          finalUrl = url;
        }
      } catch (e) {
        AppLogger.log('❌ Invalid URL format: $url');
        return null;
      }
    }

    // **OPTIMIZATION: Hybrid Caching Strategy**
    // 1. HLS (.m3u8): Now routed through proxy-hls for advanced rewriting & caching.
    // 2. MP4: Proxied via standard file proxy.
    // This ensures BOTH formats are cached to disk to prevent re-downloading.
    return videoCacheProxy.proxyUrl(finalUrl);
  }

  Future<String?> _resolvePlayableUrl(VideoModel video) async {
    try {
      // **MATCHING STRATEGY: HLS (m3u8) matches Hive Cache & VideoService Logic**
      // Hive stores HLS URLs (VideoService promotes them).
      // We MUST play HLS to hit the pre-warmed cache (0ms start).

      // 1. **Priority #1: HLS (Adaptive Streaming)**
      // This matches what we save in Hive and what HlsWarmupService preloads.
      final hlsUrl = video.hlsPlaylistUrl?.isNotEmpty == true
          ? video.hlsPlaylistUrl
          : video.hlsMasterPlaylistUrl;
      
      if (hlsUrl != null && hlsUrl.isNotEmpty) {
        // **SUCCESS: Play HLS**
        return _validateAndFixVideoUrl(hlsUrl);
      }

      // 2. **Fallback: MP4 (if HLS is missing)**
      // Check for 480p optimized URL first
      if (video.lowQualityUrl != null && video.lowQualityUrl!.isNotEmpty) {
         if (!video.lowQualityUrl!.contains('.m3u8')) {
            final url = _validateAndFixVideoUrl(video.lowQualityUrl!);
            AppLogger.log('🎬 Using 480p (Low Quality) URL: $url');
            return url;
         }
      }

      // 3. **Final Fallback: videoUrl**
      // Checks main URL. Note: VideoService might have already optimized this to HLS.
      return _validateAndFixVideoUrl(video.videoUrl);
    } catch (_) {
      return _validateAndFixVideoUrl(video.videoUrl);
    }
  }

  void _cleanupOldControllers() {
    final sharedPool = SharedVideoControllerPool();

    sharedPool.cleanupDistantControllers(_currentIndex, keepRange: 3);

    final controllersToRemove = <int>[];

    // **SMART CLEANUP: Cancel pending/initializing videos if they are too far**
    // This allows "Fast Scrolling" without network congestion
    final initializingList = _initializingVideos.toList(); // Copy to avoid modification error
    for (final index in initializingList) {
       final distance = (index - _currentIndex).abs();
       // **SNIPER MODE: Relaxed threshold (distance > 8)**
       // If I am at index 5, kill index 1 or 9 (distance > 8)
       // Relaxed from 4 to 8 to prevent aggressive cancellation during medium-speed scrolling
       if (distance > 8) { 
          AppLogger.log('🛑 Cancelled pending preload for video $index (Too far: $distance)');
          _initializingVideos.remove(index);
          _loadingVideos.remove(index);
          
          // If controller exists, dispose it immediately
          if (_controllerPool.containsKey(index)) {
             try {
                _controllerPool[index]?.dispose();
                _controllerPool.remove(index);
             } catch (_) {}
          }
       }
    }

    for (final index in _controllerPool.keys.toList()) {
      if (index < _videos.length) {
        final videoId = _videos[index].id;
        if (sharedPool.isVideoLoaded(videoId)) {
          controllersToRemove.add(index);
          continue;
        }
      }

      final distance = (index - _currentIndex).abs();
      // Keep slightly more controllers for reliability (was 3, then 5)
      // Relaxed to 5 to prevent aggressive cleanup during fast scroll
      if (distance > 5 || _controllerPool.length > 8) {
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
      // **CRITICAL FIX: Reset firstFrameReady so thumbnail shows if we scroll back**
      if (_firstFrameReady.containsKey(index)) {
        _firstFrameReady[index]?.value = false;
        _firstFrameReady.remove(index);
      }
      _bufferingListeners.remove(index);
      _videoEndListeners.remove(index);
      _lastAccessedLocal.remove(index);
      _initializingVideos.remove(index);
      _preloadRetryCount.remove(index);
      _videoErrors.remove(index); // **FIX: Clear error state on cleanup**
    }

    if (controllersToRemove.isNotEmpty) {
      AppLogger.log(
        '🧹 Cleaned up ${controllersToRemove.length} local controller trackings',
      );
    }
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

      // **FIX: Robust completion check with Debounce**
      // Sometimes videos stall near the end or duration updates (HLS).
      // We check if it "looks" done, but wait to verify it stays done.
      final bool looksComplete = !value.isPlaying &&
          !value.isBuffering &&
          remaining <= const Duration(milliseconds: 250);

      if (looksComplete) {
        // **DEBOUNCE: Wait 250ms to ensure it's truly the end**
        // This prevents triggering if:
        // 1. Duration updates (HLS)
        // 2. Playback resumes (buffering glitch)
        // 3. User seeks back
        Future.delayed(const Duration(milliseconds: 250), () {
          if (!mounted) return;
          
          // Check controller again
          final newValue = controller.value;
          if (!newValue.isInitialized) return;
          
          // If status changed, abort
          if (newValue.isPlaying) return;
          if (newValue.isBuffering) return;
          
          // Check user intent
          if (_userPaused[index] == true) return;
          if (_autoAdvancedForIndex.contains(index)) return;

          // Re-calculate remaining time (crucial for HLS duration updates)
          final newDuration = newValue.duration;
          final newPosition = newValue.position;
          final newRemaining = newDuration - newPosition;

          // Only trigger if STILL close to end
          if (newRemaining <= const Duration(milliseconds: 300)) {
            AppLogger.log('✅ Video $index confirmed complete (Debounced). Auto-advancing...');
            _handleVideoCompleted(index);
          } else {
             AppLogger.log('⚠️ Video $index false completion detected (Duration grew?). Remaining: ${newRemaining.inMilliseconds}ms');
          }
        });
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

      // **NEW: Handle Slow Connection feedback timer**
      if (isBuffering) {
        _bufferingTimers[index]?.cancel();
        _bufferingTimers[index] = Timer(const Duration(seconds: 5), () {
          if (mounted && _isBuffering[index] == true) {
            _isSlowConnectionVN[index] ??= ValueNotifier<bool>(false);
            _isSlowConnectionVN[index]!.value = true;
          }
        });
      } else {
        _bufferingTimers[index]?.cancel();
        _bufferingTimers.remove(index);
        _isSlowConnectionVN[index]?.value = false;
      }

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

  // **NEW: Error Listener to catch runtime playback errors (Grey Screen Fix)**
  void _attachErrorListenerIfNeeded(
    VideoPlayerController controller,
    int index,
  ) {
    void handleError() {
      if (!mounted) return;
      final value = controller.value;
      
      if (value.hasError) {
        final errorMessage = value.errorDescription ?? 'Unknown playback error';
        if (_videoErrors[index] != errorMessage) {
          AppLogger.log('❌ Runtime Video Error at index $index: $errorMessage');
          safeSetState(() {
            _videoErrors[index] = errorMessage;
            // Force hide loading state if error occurs
            _loadingVideos.remove(index);
            _isBuffering[index] = false;
            _isBufferingVN[index]?.value = false;
          });
        }
      }
    }

    controller.addListener(handleError);
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
          videoHash: video.videoHash, // **NEW: Pass video hash**
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
    // **FIX: Removed _isLoading check so video plays even if feed is refreshing**
    if (_videos.isEmpty) return;
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
        
        // **NEW: Start view tracking with videoHash for immediate play**
        if (index < _videos.length) {
          final video = _videos[index];
          _viewTracker.startViewTracking(
            video.id, 
            videoUploaderId: video.uploader.id,
            videoHash: video.videoHash,
          );
        }

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
              
              // **NEW: Start view tracking with videoHash for retry play**
              if (index < _videos.length) {
                final video = _videos[index];
                _viewTracker.startViewTracking(
                  video.id, 
                  videoUploaderId: video.uploader.id,
                  videoHash: video.videoHash,
                );
              }

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
