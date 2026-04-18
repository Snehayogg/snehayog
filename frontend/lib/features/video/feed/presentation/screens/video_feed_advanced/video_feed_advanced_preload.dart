part of '../video_feed_advanced.dart';

extension _VideoFeedPreload on _VideoFeedAdvancedState {




  Future<void> _checkDeviceCapabilities() async {
    try {
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        // Consider devices with <= 4GB RAM as "Low End" for heavy video tasks
        // isLowRamDevice is a reliable flag from Android API
        // physicalRamSize is in MB (device_info_plus)
        final ramInMB = (androidInfo.physicalRamSize).toDouble();
        _isLowEndDevice = androidInfo.isLowRamDevice || (ramInMB <= 4096);

      }
      
      // **DYNAMIC POOL: Configure shared pool based on device power**
      SharedVideoControllerPool().configurePool(isLowEndDevice: _isLowEndDevice);
      
      // **DYNAMIC CACHE: Configure disk cache limit + Quality filtering**
      videoCacheProxy.configureService(isLowEndDevice: _isLowEndDevice);
      
    } catch (e) {
      AppLogger.log('⚠️ Error checking device capabilities: $e');
    }
  }

  void _preloadNearbyVideos() {
    if (_videos.isEmpty) return;
    
    // **CRITICAL BANDWIDTH FIX: Kill all previous background downloads**
    // This ensures that when user scrolls, we stop downloading old stuff IMMEDIATELY.
    videoCacheProxy.cancelAllPrefetches();

    final bool isScrollingDown = _currentIndex >= _previousIndex;
    
    // **PRIORITY 0: CURRENT VIDEO - SMART INITIAL CHUNK**
    // Prefetch only the first 500KB for instant playback (0.5 seconds)
    // The rest will be loaded by ExoPlayer in the background
    if (_currentIndex < _videos.length) {
      final currentVideo = _videos[_currentIndex];
      final currentUrl = currentVideo.hlsPlaylistUrl?.isNotEmpty == true
          ? currentVideo.hlsPlaylistUrl!
          : (currentVideo.hlsMasterPlaylistUrl?.isNotEmpty == true
              ? currentVideo.hlsMasterPlaylistUrl!
              : currentVideo.videoUrl);
      
      // Prefetch initial 150KB chunk for instant playback (approx 5s at 400kbps)
      videoCacheProxy.prefetchInitialChunk(currentUrl, kilobytes: 150).catchError((_){});

      // **PROACTIVE PROFILE PRELOAD: Target only the current creator to focus bandwidth**
      // By pre-fetching here, we ensure SmartCache is warm when user taps on profile.
      final creatorId = currentVideo.uploader.googleId?.isNotEmpty == true
          ? currentVideo.uploader.googleId!
          : currentVideo.uploader.id;
      
      if (creatorId.isNotEmpty && creatorId.toLowerCase() != 'unknown') {
        ProfilePreloader().preloadProfile(creatorId);
      }
    }

    
    // Still preload controller normally (initializes player)
    _preloadVideo(_currentIndex);
    
    // **STRICT DIRECTIONAL WINDOWS (User Request)**
    // Down: Focus on Current & Next (n+1). Clean everything else (past).
    // Up: Focus on Current & Prev (n-1). Clean everything else (future).
    
    // **SAFE WINDOW: Adjust window based on device power**
    // High-end: keep [Current-1, Current+1] (Total 3)
    // Low-end: keep [Current, Current+1] if down, [Current-1, Current] if up (Total 2)
    int keepStart, keepEnd;
    if (_isLowEndDevice) {
      if (isScrollingDown) {
        keepStart = _currentIndex;
        keepEnd = (_currentIndex + 1).clamp(0, _videos.length - 1);
      } else {
        keepStart = (_currentIndex - 1).clamp(0, _videos.length - 1);
        keepEnd = _currentIndex;
      }
    } else {
      keepStart = (_currentIndex - 1).clamp(0, _videos.length - 1);
      keepEnd = (_currentIndex + 1).clamp(0, _videos.length - 1);
    }
    
    // **STRICT DIRECTIONAL WINDOWS (Optimization)**
    // While we keep the safe buffer above, we prioritize preloading in the scroll direction.
    if (isScrollingDown) {
        // SCROLLING DOWN -> Priority Next Video (n+1)
        if (_currentIndex + 1 < _videos.length) {
            final nextVideo = _videos[_currentIndex + 1];
            final nextUrl = nextVideo.hlsPlaylistUrl?.isNotEmpty == true
                ? nextVideo.hlsPlaylistUrl!
                : (nextVideo.hlsMasterPlaylistUrl?.isNotEmpty == true
                    ? nextVideo.hlsMasterPlaylistUrl!
                    : nextVideo.videoUrl);
            
            if (_wasLastScrollFast) {
              _preloadDebounceTimers[nextVideo.id]?.cancel();
              _preloadDebounceTimers[nextVideo.id] = Timer(const Duration(milliseconds: 1500), () {
                if (mounted && _currentIndex == (keepStart + 1)) {
                  videoCacheProxy.prefetchInitialChunk(nextUrl, kilobytes: 50).catchError((_){});
                  _preloadVideo(_currentIndex + 1);
                }
              });
            } else {
              videoCacheProxy.prefetchInitialChunk(nextUrl, kilobytes: 50).catchError((_){});
              _preloadVideo(_currentIndex + 1);
            }
        }
    } else {
        // SCROLLING UP -> Priority Prev Video (n-1)
        if (_currentIndex - 1 >= 0) {
            final prevVideo = _videos[_currentIndex - 1];
            final prevUrl = prevVideo.hlsPlaylistUrl?.isNotEmpty == true
                ? prevVideo.hlsPlaylistUrl!
                : (prevVideo.hlsMasterPlaylistUrl?.isNotEmpty == true
                    ? prevVideo.hlsMasterPlaylistUrl!
                    : prevVideo.videoUrl);
            
            if (_wasLastScrollFast) {
              _preloadDebounceTimers[prevVideo.id]?.cancel();
              _preloadDebounceTimers[prevVideo.id] = Timer(const Duration(milliseconds: 1500), () {
                if (mounted && _currentIndex == keepEnd) {
                  videoCacheProxy.prefetchInitialChunk(prevUrl, kilobytes: 50).catchError((_){});
                  _preloadVideo(_currentIndex - 1);
                }
              });
            } else {
              videoCacheProxy.prefetchInitialChunk(prevUrl, kilobytes: 50).catchError((_){});
              _preloadVideo(_currentIndex - 1);
            }
        }
    }

    // **AGGRESSIVE CLEANUP**
    // Dispose everything outside the calculated window immediately
    _cleanupOldControllers(keepStart: keepStart, keepEnd: keepEnd);

    // **SHARED POOL CLEANUP**
    SharedVideoControllerPool().cleanupSmart(_currentIndex, keepStart, keepEnd);

    // **MANIFEST PREFETCH (Lightweight)**
    // Still useful to fetch manifests for HLS further down (no memory cost, just disk cache)
    // We keep this but reduce range to preventing network congestion
    if (isScrollingDown) {
        final int prefetchStart = _currentIndex + 2;
        final int prefetchEnd = _currentIndex + 3;
        for (int i = prefetchStart; i <= prefetchEnd && i < _videos.length; i++) {
           final video = _videos[i];
           final hlsUrl = video.hlsPlaylistUrl?.isNotEmpty == true
               ? video.hlsPlaylistUrl
               : video.hlsMasterPlaylistUrl;
           if (hlsUrl != null && hlsUrl.isNotEmpty) {
               videoCacheProxy.prefetchChunk(hlsUrl, megabytes: 1).catchError((_){});
           }
        }
    }

    // **NEW: Background preload of second page immediately after first page**
    if (!_hasStartedBackgroundPreload &&
        _videos.isNotEmpty &&
        _hasMore &&
        !_isLoadingMore) {
      _hasStartedBackgroundPreload = true;
      _loadMoreVideos();
    }

    // **FIXED: Dynamic loading trigger based on total videos**
    final distanceFromEnd = _videos.length - _currentIndex;
    if (_hasMore && !_isLoadingMore) {
      // **OPTIMIZATION: Smaller batch trigger for low-end devices**
      final int triggerDistance = _isLowEndDevice ? 5 : 20;
      if (distanceFromEnd <= triggerDistance) {
        _loadMoreVideos();
      }
    }
  }

  /// **PRELOAD SINGLE VIDEO**
  Future<void> _preloadVideo(int index, {bool bypassProxy = false}) async {
    final video = _videos[index];
    final String videoId = video.id;

    // **RACE CONDITION FIX: Don't double-load if already loading**
    if (_loadingVideos.contains(videoId)) {
      // Ensure we re-check smart autoplay even if skipping load
      if (mounted && index == _currentIndex) {

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && index == _currentIndex) {
             _tryAutoplayCurrentImmediate(index);
          }
        });
      }
      return;
    }

    // **NEW: Check if we're already at max concurrent initializations**
    // **VIP PASS: If it's the current video, BYPASS this check and load immediately!**
    if (index != _currentIndex &&
        _initializingVideos.length >= _maxConcurrentInitializations &&
        !_preloadedVideos.contains(videoId) &&
        !_loadingVideos.contains(videoId)) {
      // Queue this video for later initialization
      // **FIX: Use a unique timer for each videoId to prevent closure capturing issues**
      _preloadDebounceTimers[videoId]?.cancel();
      _preloadDebounceTimers[videoId] = Timer(const Duration(milliseconds: 200), () {
        if (mounted && !_preloadedVideos.contains(videoId)) {
          _preloadVideo(index, bypassProxy: bypassProxy);
        }
      });
      return;
    }

    // **OPTIMIZED: Removed "Buffer Gate" logic - HLS handles bandwidth adaptation automatically**
    // Preload normally and let the HLS player manage quality switching based on network conditions

    // **RELEVANCY CHECK: Abort if video is too far from current index (Zombie Load Check)**
    // This prevents "Ghost Loading" when user scrolls fast past this video.
    // **FIX: Tightened from 3 to 2 to prevent far-off videos from loading during fast scroll**
    if (mounted && (index - _currentIndex).abs() > 2) {

      _loadingVideos.remove(videoId); // Ensure we clear the loading flag
      return;
    }

    // **CACHE STATUS CHECK ON PRELOAD**

    String? videoUrl;
    VideoPlayerController? controller;
    bool isReused = false;

    try { 
      // **CRITICAL FIX: Start tracking loading immediately inside TRY block to ensure cleanup in FINALLY**
      _loadingVideos.add(videoId);
      
      // **FIX: Clear any previous error state when starting a new load**
      if (mounted && _videoErrors.containsKey(videoId)) {
         _videoErrors.remove(videoId);
      }

      final video = _videos[index];

      // **NEW: Use effective URL (Original or Dubbed)**
      videoUrl = _getActingUrl(video);
      
      // **PROXY LOGIC: Apply proxy URL unless bypassing due to previous error**
      if (!bypassProxy) {
          videoUrl = videoCacheProxy.proxyUrl(videoUrl);
      } else {
          AppLogger.log('🛡️ Fallback: Loading $videoId directly from CDN (Bypassing Proxy)');
      }
      if (videoUrl.isEmpty) {
        AppLogger.log('❌ Invalid video URL for $index: ${video.videoUrl}');
        _loadingVideos.remove(videoId);
        return;
      }

      // **RELEVANCY CHECKPOINT #1: After URL resolution**
      if (mounted && (index - _currentIndex).abs() > 1 && index != _currentIndex) {
        _loadingVideos.remove(videoId);
        return;
      }

      final sharedPool = SharedVideoControllerPool();

      // **INSTANT LOADING: Try to get controller from shared pool**
      final instantController = sharedPool.getControllerForInstantPlay(video.id);
      if (instantController != null && !sharedPool.isControllerDisposed(instantController)) {
        controller = instantController;
        isReused = true;
        _controllerPool[videoId] = controller;
        _lastAccessedLocal[videoId] = DateTime.now();
      } else if (sharedPool.isVideoLoaded(video.id)) {
        final fallbackController = sharedPool.getController(video.id);
        if (fallbackController != null && !sharedPool.isControllerDisposed(fallbackController)) {
          controller = fallbackController;
          isReused = true;
          _controllerPool[videoId] = controller;
          _lastAccessedLocal[videoId] = DateTime.now();
        }
      }

      if (controller != null && index != _currentIndex) {
        try {
          if (controller.value.isPlaying) {
            controller.pause();
          }
        } catch (_) {
          controller = null;
        }
      }

      if (controller == null) {
        // **PROACTIVE CLEANUP: Make room before allocating new decoder**
        await sharedPool.makeRoomForNewController();

        if (video.videoType == 'local_gallery') {
          // **NEW: Use File controller for local gallery videos**
          controller = VideoPlayerController.file(
            File(videoUrl),
            videoPlayerOptions: VideoPlayerOptions(
              mixWithOthers: true,
              allowBackgroundPlayback: false,
            ),
          );
        } else {
          final Map<String, String> headers = videoUrl.contains('.m3u8')
              ? const {'Accept': 'application/vnd.apple.mpegurl,application/x-mpegURL'}
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
      }

      // **RELEVANCY CHECKPOINT #2: Before initialization**
      if (!isReused && mounted && (index - _currentIndex).abs() > 1 && index != _currentIndex) {
        _loadingVideos.remove(videoId);
        controller.dispose(); 
        return;
      }

      if (!isReused) {
        _initializingVideos.add(videoId);

        try {
          if (videoUrl.contains('.m3u8')) {
            // **VIP: Increase timeout for low-end hardware/network combinations**
            final timeoutSeconds = _isLowEndDevice ? 25 : 15;
            await controller.initialize().timeout(
              Duration(seconds: timeoutSeconds),
              onTimeout: () => throw Exception('HLS timeout'),
            );
          } else {
            final timeoutSeconds = _isLowEndDevice ? 15 : 10;
            await controller.initialize().timeout(
              Duration(seconds: timeoutSeconds),
              onTimeout: () => throw Exception('Video timeout'),
            );
          }
          
          if (index != _currentIndex) {
            try {
              if (controller.value.isPlaying) {
                controller.pause();
              }
            } catch (_) {}
          }
        } finally {
          _initializingVideos.remove(videoId);
        }

        // **LIFECYCLE CHECK: Ensure controller is still valid after async initialization**
        if (!mounted || (index - _currentIndex).abs() > 1 && index != _currentIndex) {
          _loadingVideos.remove(videoId);
          controller.dispose();
          return;
        }

        // **POST-INIT CHECK: Safe check for disposal**
        try {
          if (controller.value.isInitialized) {
            // Success
          }
        } catch (_) {
          // Controller might be disposed already
          _loadingVideos.remove(videoId);
          return;
        }
      }

      if (mounted && _loadingVideos.contains(videoId)) {
        safeSetState(() {
          _controllerPool[videoId] = controller!;
          _controllerStates[videoId] = false;
          _preloadedVideos.add(videoId);
          _loadingVideos.remove(videoId);
          _lastAccessedLocal[videoId] = DateTime.now();
        });

        sharedPool.addController(video.id, controller, index: index);
        
        if (mounted) {

          
          if (!_userPaused.containsKey(videoId)) {
            _userPaused[videoId] = false;
          }
          _getOrCreateNotifier<bool>(_userPausedVN, videoId, false);

          if (!_controllerStates.containsKey(videoId)) {
            _controllerStates[videoId] = false;
          }
        }

        _applyLoopingBehavior(controller);
        _attachEndListenerIfNeeded(controller, index);
        _attachBufferingListenerIfNeeded(controller, index);
        _attachQuizListenerIfNeeded(controller, index);
        _attachErrorListenerIfNeeded(controller, index);



      }

      if (mounted && index == _currentIndex) {
         // **FIX: When opened from profile, use forcePlayCurrent() which bypasses
         // all context checks (visibility, tab, lifecycle) and directly plays.
         // This ensures reliable autoplay regardless of timing/race conditions.**
         if (_openedFromProfile) {
           forcePlayCurrent();
         } else {
           _tryAutoplayCurrentImmediate(index);
         }
      }

    } catch (e) {
      if (mounted) {
        safeSetState(() {
           _loadingVideos.remove(videoId);
           _videoErrors[videoId] = e.toString();
        });
      }
      
      // **CRITICAL: Dispose leaked controller on error**
      if (controller != null && !isReused) {
        try {
          controller.dispose();
        } catch (_) {}
      }
      
      final retryCount = _preloadRetryCount[videoId] ?? 0;
      if (retryCount < 1) { 
        _preloadRetryCount[videoId] = retryCount + 1;
        AppLogger.log('🔄 Video $index failed, retrying... Error: $e');
        
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted && !_preloadedVideos.contains(videoId) && (index - _currentIndex).abs() <= 1) {
            _preloadVideo(index);
          }
        });
      } else {
        AppLogger.log('❌ Video $index failed after retry: $e');
        _preloadRetryCount.remove(videoId);
      }
    }
  }


  String? _validateAndFixVideoUrl(String url) {
    if (url.isEmpty) return null;

    String finalUrl = url;

    if (!url.startsWith('http')) {
      // **NEW: Check if it's already a local file path**
      if (url.startsWith('/') || url.contains(':/') || url.contains(':\\')) {
        // Absolute local path, don't prefix with baseUrl
        return url;
      }
      
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

  /// **NEW: Get acting URL representing original or dubbed state**
  String _getActingUrl(VideoModel video) {
    final String selectedLang = _selectedAudioLanguage[video.id] ?? 'default';
    String? targetUrl;

    if (selectedLang != 'default') {
      targetUrl = video.dubbedUrls?[selectedLang];
    }

    if (targetUrl == null || targetUrl.isEmpty) {
      // Standard logic (Source Audio)
      final hlsUrl = video.hlsPlaylistUrl?.isNotEmpty == true
          ? video.hlsPlaylistUrl
          : video.hlsMasterPlaylistUrl;
      
      targetUrl = (hlsUrl != null && hlsUrl.isNotEmpty) ? hlsUrl : video.videoUrl;
    }

    // **CRITICAL FIX: Bypass proxy for local gallery videos**
    if (video.videoType == 'local_gallery') {
      return targetUrl;
    }

    final fixedUrl = _validateAndFixVideoUrl(targetUrl);
    final finalUrl = videoCacheProxy.proxyUrl(fixedUrl ?? targetUrl);
    
    return finalUrl;
  }


  void _cleanupOldControllers({int? keepStart, int? keepEnd}) {
    final sharedPool = SharedVideoControllerPool();
    
    // Default to safe tight range if not specified
    final int start = keepStart ?? (_currentIndex - 1);
    final int end = keepEnd ?? (_currentIndex + 1);

    // Update Shared Pool too (redundancy check)
    sharedPool.cleanupSmart(_currentIndex, start, end); // Use Smart Cleanup logic in Shared Pool

    final controllersToRemove = <String>[];

    // **SMART CLEANUP: Cancel pending/initializing videos if they are outside window**
    final initializingList = _initializingVideos.toList();
    for (final videoId in initializingList) {
        // Find index of this videoId
        int? index;
        try {
           index = _videos.indexWhere((v) => v.id == videoId);
        } catch (_) {}

        // Destroy anything outside the keep range
       if (index == null || index < start || index > end) { 

          
          // **FIX: Cancel Debounce Timer if it exists**
          if (_preloadDebounceTimers.containsKey(videoId)) {
             _preloadDebounceTimers[videoId]?.cancel();
             _preloadDebounceTimers.remove(videoId);
          }

          _initializingVideos.remove(videoId);
          _loadingVideos.remove(videoId);
          
          if (_controllerPool.containsKey(videoId)) {
             try {
                _controllerPool[videoId]?.dispose();
                _controllerPool.remove(videoId);
             } catch (_) {}
          }
       }
    }

    // **NEW: Cleanup Debounce Timers specifically**
    // Sometimes timers exist even if not in _initializingVideos
    final timersToRemove = <String>[];
    for (final videoId in _preloadDebounceTimers.keys) {
      int? idx;
      try {
        idx = _videos.indexWhere((v) => v.id == videoId);
      } catch (_) {}

      if (idx == null || idx < start || idx > end) {
         timersToRemove.add(videoId);
      }
    }
    for (final videoId in timersToRemove) {
       _preloadDebounceTimers[videoId]?.cancel();
       _preloadDebounceTimers.remove(videoId);
    }

    // **LOCAL POOL CLEANUP**
    for (final videoId in _controllerPool.keys.toList()) {
      int? index;
      try {
         index = _videos.indexWhere((v) => v.id == videoId);
      } catch (_) {}

      // Check range
      if (index == null || index < start || index > end) {
        controllersToRemove.add(videoId);
      }
    }

    for (final videoId in controllersToRemove) {
      final ctrl = _controllerPool[videoId];

      if (ctrl != null) {
        try {
          if (ctrl.value.isInitialized) {
            try {
              ctrl.pause();
              ctrl.setVolume(0.0);
            } catch (_) {}
          }
          
          final bufferingListener = _bufferingListeners[videoId];
          if (bufferingListener != null) {
            try {
              ctrl.removeListener(bufferingListener);
            } catch (_) {}
            _bufferingListeners.remove(videoId);
          }

          final endListener = _videoEndListeners[videoId];
          if (endListener != null) {
            try {
              ctrl.removeListener(endListener);
            } catch (_) {}
            _videoEndListeners.remove(videoId);
          }
          
          final errorListener = _errorListeners[videoId];
          if (errorListener != null) {
            try {
              ctrl.removeListener(errorListener);
            } catch (_) {}
            _errorListeners.remove(videoId);
          }

          final quizListener = _quizListeners[videoId];
          if (quizListener != null) {
            try {
              ctrl.removeListener(quizListener);
            } catch (_) {}
            _quizListeners.remove(videoId);
          }

          try {
            ctrl.dispose();
          } catch (e) {
            AppLogger.log('⚠️ Error during ctrl.dispose() for $videoId: $e');
          }
        } catch (e) {
          AppLogger.log('⚠️ Error during full disposal sequence for video $videoId: $e');
        }
      }

      _controllerPool.remove(videoId);
      _controllerStates.remove(videoId);
      _preloadedVideos.remove(videoId);
      _isBuffering.remove(videoId);
      

      _bufferingListeners.remove(videoId);
      _videoEndListeners.remove(videoId);
      _lastAccessedLocal.remove(videoId);
      _initializingVideos.remove(videoId);
      _preloadRetryCount.remove(videoId);
      _videoErrors.remove(videoId);
        
      if (_errorListeners.containsKey(videoId)) {
            _errorListeners.remove(videoId);
      }
    }

    if (controllersToRemove.isNotEmpty) {
      // Cleanup complete
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
    if (index >= _videos.length) return;
    final videoId = _videos[index].id;
    final existingListener = _videoEndListeners[videoId];
    if (existingListener != null) {
      controller.removeListener(existingListener);
    }

    void handleVideoEnd() {
      if (!mounted) return;
      
      // **CRASH-PROOF: Safety check for disposal before accessing value**
      try {
        if (SharedVideoControllerPool().isControllerDisposed(controller)) return;
        
        final value = controller.value;
        if (!value.isInitialized) return;

        final duration = value.duration;
        if (duration == Duration.zero) return;

        final position = value.position;
        final remaining = duration - position;

        // **TRIGGER: 600ms before end for "Instant" feel**
        if (remaining <= const Duration(milliseconds: 600)) {
          if (_userPaused[videoId] == true) return;
          if (_autoAdvancedForIndex.contains(index)) return;
          
          AppLogger.log('✅ Video $index near completion. Auto-advancing...');
          _handleVideoCompleted(index);
        }
      } catch (e) {
        // Silently ignore disposal errors in listener
      }
    }
 
    _videoEndListeners[videoId] = handleVideoEnd;
    controller.addListener(handleVideoEnd);
  }

  void _attachBufferingListenerIfNeeded(
    VideoPlayerController controller,
    int index,
  ) {
    if (index >= _videos.length) return;
    final videoId = _videos[index].id;

    final existingListener = _bufferingListeners[videoId];
    if (existingListener != null) {
      controller.removeListener(existingListener);
    }

    // **STALL DETECTOR STATE**
    Duration? lastPosition;
    DateTime? lastMoveTime;

    void handlePlaybackStatus() {
      if (!mounted) return;
      
      // **CRASH-PROOF: Safety check for disposal before accessing value**
      try {
        if (SharedVideoControllerPool().isControllerDisposed(controller)) return;
        
        final value = controller.value;
        if (!value.isInitialized) return;

        final bool isBuffering = value.isBuffering;
      
      // **1. BUFFERING LOGIC**
      if (_isBuffering[videoId] != isBuffering) {
          _isBuffering[videoId] = isBuffering;

          // **NEW: Handle Slow Connection feedback timer**
          if (isBuffering) {
            _bufferingTimers[videoId]?.cancel();
            
            // **ADAPTIVE: Immediate trigger for Low Bandwidth Mode**
            if (!_isLowBandwidthMode && mounted) {
               // Don't switch mode immediately, wait a bit to avoid false positives on seek
               // _isLowBandwidthMode = true; 
            }
            _consecutiveSmoothPlays = 0; // Reset recovery counter
    
            _bufferingTimers[videoId] = Timer(const Duration(seconds: 5), () {
              if (!mounted) return;
              
              if (_isBuffering[videoId] == true) {
                 // If still buffering after 5 seconds...
                 
                 // 1. Show Slow Internet UI
                 // **NEW: Throttle display frequency**
                 if (_slowConnectionShownCount < _maxSlowConnectionShows) {
                    _getOrCreateNotifier<bool>(_isSlowConnectionVN, videoId, true);
                    _slowConnectionShownCount++;
                    AppLogger.log('🐢 Slow Internet Banner shown: $_slowConnectionShownCount/$_maxSlowConnectionShows');
                 }
                _isLowBandwidthMode = true; // Now we confirm it's slow
                
                // 2. **KICKSTART LOGIC (Stale Connection Fix)**
                final controller = _controllerPool[videoId];
                if (controller != null && controller.value.isInitialized) {
                   AppLogger.log('🐢 Stale Buffering detected for video $videoId. Attempting Kickstart...');
                   try {
                      final position = controller.value.position;
                      controller.seekTo(position); // Re-trigger buffer fill
                   } catch (e) {
                      AppLogger.log('❌ Kickstart failed: $e');
                   }
                }
              }
            });
          } else {
            _bufferingTimers[videoId]?.cancel();
            _bufferingTimers.remove(videoId);
            final slowConnectionVN =
                _getOrCreateNotifier<bool>(_isSlowConnectionVN, videoId, false);
            if (slowConnectionVN.value != false) {
              slowConnectionVN.value = false;
            }
          }
    
          final bufferingVN =
              _getOrCreateNotifier<bool>(_isBufferingVN, videoId, isBuffering);
          if (bufferingVN.value != isBuffering) {
            bufferingVN.value = isBuffering;
          }
      }
      
      // **2. SILENT STALL DETECTION Watchdog**
      // Detects when video claims to be playing but position isn't moving
      if (value.isPlaying && !value.isBuffering) {
          // Playback is healthy; force-clear stale buffering UI state.
          if (_isBuffering[videoId] == true) {
            _isBuffering[videoId] = false;
          }
          if (_isBufferingVN[videoId]?.value == true) {
            _isBufferingVN[videoId]!.value = false;
          }
          if (_isSlowConnectionVN[videoId]?.value == true) {
            _isSlowConnectionVN[videoId]!.value = false;
          }
          _bufferingTimers[videoId]?.cancel();
          _bufferingTimers.remove(videoId);

          if (lastPosition == value.position) {
             // Position hasn't moved
             lastMoveTime ??= DateTime.now();
             
             if (DateTime.now().difference(lastMoveTime!) > const Duration(milliseconds: 3000)) {
                 // AppLogger.log('❄️ Silent Stall detected for video $videoId (Frozen for 3s). Kicking...');
                 
                 lastMoveTime = DateTime.now(); // Reset to prevent spamming
                 
                 // Force kickstart
                 try {
                    controller.seekTo(value.position);
                 } catch (_) {}
             }
          } else {
             // Moving fine
             lastPosition = value.position;
             lastMoveTime = null;
          }
        } else {
            // Not playing or legitimately buffering, reset stall timer
            lastMoveTime = null;
        }
      } catch (_) {
        // Silently ignore disposal errors in listener
      }
    }

    _bufferingListeners[videoId] = handlePlaybackStatus;
    controller.addListener(handlePlaybackStatus);
    handlePlaybackStatus();
  }

  // **NEW: Error Listener to catch runtime playback errors (Grey Screen Fix)**
  // **FIX: Track listener in map to allow cleanup (Prevent duplicate listeners on reuse)**
  void _attachErrorListenerIfNeeded(
    VideoPlayerController controller,
    int index,
  ) {
    if (index >= _videos.length) return;
    final videoId = _videos[index].id;

    if (_errorListeners.containsKey(videoId)) {
       controller.removeListener(_errorListeners[videoId]!);
    }
    void handleError() {
      if (!mounted) return;
      try {
        if (SharedVideoControllerPool().isControllerDisposed(controller)) return;
        
        final value = controller.value;
        
        if (value.hasError) {
          final errorMessage = value.errorDescription ?? 'Unknown playback error';
          if (_videoErrors[videoId] != errorMessage) {
            AppLogger.log('❌ Runtime Video Error for video $videoId: $errorMessage');
            
            // **VIP FALLBACK: If proxy fails on old phone, retry with Raw URL**
            bool handledByFallback = false;
            if (videoCacheProxy.isProxyUrl(controller.dataSource)) {
               AppLogger.log('🔄 Fallback: Proxy failed on $videoId. Retrying with Raw URL...');
               handledByFallback = true;
               
               safeSetState(() {
                  _videoErrors.remove(videoId);
                  _loadingVideos.add(videoId);
               });

               // Kill old controller and retry without proxy
               _controllerPool[videoId]?.dispose();
               _controllerPool.remove(videoId);
               
               // Trigger direct load (bypass proxy completely)
               _preloadVideo(index, bypassProxy: true).then((_) {
                   if (mounted && index == _currentIndex) {
                      _tryAutoplayCurrentImmediate(index);
                   }
               });
            }

            if (!handledByFallback) {
              safeSetState(() {
                _videoErrors[videoId] = errorMessage;
                _loadingVideos.remove(videoId);
                _isBuffering[videoId] = false;
                _isBufferingVN[videoId]?.value = false;
                
                try {
                   controller.pause();
                   controller.setVolume(0.0);
                   _controllerPool.remove(videoId);
                } catch (_) {}
              });
            }
          }
        }
      } catch (_) {
        // Silently ignore disposal errors in listener
      }
    }

    controller.addListener(handleError);
    _errorListeners[videoId] = handleError;
  }

  void _handleVideoCompleted(int index) {
    if (index >= _videos.length) return;
    final videoId = _videos[index].id;
    if (_userPaused[videoId] == true) return;
    if (_autoAdvancedForIndex.contains(index)) return;
    _autoAdvancedForIndex.add(index);

    if (index < _videos.length) {
      final video = _videos[index];
      _viewTracker.stopViewTracking(video.id);

      // **NEW: Track video completion for watch history**
      final controller = _controllerPool[videoId];
      if (controller != null && controller.value.isInitialized) {
        final duration = controller.value.duration.inSeconds;
        _viewTracker.trackVideoCompletion(
          video.id,
          duration: duration,
          videoHash: video.videoHash, // **NEW: Pass video hash**
        );
      }
      AppLogger.log('⏹️ Completed video playback for ${video.id}');

      // **ADAPTIVE RECOVERY: If video played smoothly, try to recover**
      if (_isLowBandwidthMode && mounted) {
        _consecutiveSmoothPlays++;
        if (_consecutiveSmoothPlays >= 3) {
           _isLowBandwidthMode = false;
           _consecutiveSmoothPlays = 0;
           // AppLogger.log('✅ Adaptive Network: Recovered to High Bandwidth Mode');
        }
      }
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
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      )
          .whenComplete(() {
        _isAnimatingPage = false;
        _autoAdvancedForIndex.remove(index);
      });
    });
  }

  void _resetControllerForReplay(int index) {
    if (index >= _videos.length) return;
    final videoId = _videos[index].id;
    final controller = _controllerPool[videoId];
    if (controller == null || !controller.value.isInitialized) return;

    try {
      controller.pause();
      controller.seekTo(Duration.zero);
      controller.setVolume(1.0);
    } catch (e) {
      AppLogger.log('⚠️ Error resetting controller for video $videoId: $e');
    }

    _controllerStates[videoId] = false;
    _userPaused[videoId] = false;
    _isBuffering[videoId] = false;
    if (_isBufferingVN[videoId]?.value == true) {
      _isBufferingVN[videoId]?.value = false;
    }

    _ensureWakelockForVisibility();
  }

  // **NEW: Immediate autoplay helper that doesn't wait for full buffer**
  void _tryAutoplayCurrentImmediate(int index) {
    // **FIX: Removed _isLoading check so video plays even if feed is refreshing**
    if (_videos.isEmpty || index >= _videos.length) return;
    final video = _videos[index];
    final videoId = video.id;

    if (index != _currentIndex) return; // Make sure index hasn't changed
    // **CRITICAL FIX: Use _shouldAutoplayForContext instead of _allowAutoplay**
    // This ensures Yug tab visibility is checked before autoplay
    if (!_shouldAutoplayForContext('tryAutoplayCurrentImmediate')) return;

    final controller = _controllerPool[videoId];
    if (controller != null &&
        controller.value.isInitialized &&
        !controller.value.isPlaying) {
      if (_userPaused[videoId] == true) {
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

      _pauseAllOtherVideos(videoId);

      // **ENHANCED: Try to play immediately, with error handling**
      final controllerToPlay = controller;
      try {
        controllerToPlay.play();
        _ensureWakelockForVisibility();
        _controllerStates[videoId] = true;
        _userPaused[videoId] = false;
        _pendingAutoplayAfterLogin = false;
        
        // **NEW: Start view tracking with videoHash for immediate play**
        if (index < _videos.length) {
          _viewTracker.startViewTracking(
            videoId, 
            videoUploaderId: video.uploader.id,
            videoHash: video.videoHash,
          );
        }

        AppLogger.log(
            '⚡ VideoFeedAdvanced: Immediate autoplay started for video $videoId (index $index)');

        // **NEW: Verify play actually started, retry if needed (use callback instead of delay)**
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              _currentIndex == index &&
              controllerToPlay.value.isInitialized &&
              !controllerToPlay.value.isPlaying &&
              _userPaused[videoId] != true) {
            
            // **CRITICAL FIX: strictly check lifecycle before retrying**
            if (!_shouldAutoplayForContext('retry immediate')) return;

            AppLogger.log(
                '⚠️ VideoFeedAdvanced: Play command didn\'t start for $videoId, retrying...');
            try {
              controllerToPlay.play();
            } catch (e) {
              AppLogger.log('❌ VideoFeedAdvanced: Retry play failed for $videoId: $e');
            }
          }
        });
      } catch (e) {
        AppLogger.log(
            '❌ VideoFeedAdvanced: Immediate autoplay failed for $videoId: $e, will retry');
        // Retry using callback instead of delay for faster recovery
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted &&
              _currentIndex == index &&
              controllerToPlay.value.isInitialized &&
              !controllerToPlay.value.isPlaying &&
              _userPaused[videoId] != true) {
            
             // **CRITICAL FIX: strictly check lifecycle before retrying**
            if (!_shouldAutoplayForContext('retry catch')) return;

            try {
              controllerToPlay.play();
              _ensureWakelockForVisibility();
              _controllerStates[videoId] = true;
              _userPaused[videoId] = false;
              _userPausedVN[videoId]?.value = false; // **Sync VN**
              
              // **NEW: Start view tracking with videoHash for retry play**
              if (index < _videos.length) {
                _viewTracker.startViewTracking(
                  videoId, 
                  videoUploaderId: video.uploader.id,
                  videoHash: video.videoHash,
                );
              }

              AppLogger.log(
                  '✅ VideoFeedAdvanced: Autoplay started on retry for video $videoId');
            } catch (retryError) {
              AppLogger.log(
                  '❌ VideoFeedAdvanced: Retry autoplay failed for $videoId: $retryError');
            }
          }
        });
      }
    }
  }

  void _attachQuizListenerIfNeeded(VideoPlayerController controller, int index) {
    if (index >= _videos.length) return;
    final video = _videos[index];
    final videoId = video.id;

    if (video.quizzes == null || video.quizzes!.isEmpty) return;

    final existingListener = _quizListeners[videoId];
    if (existingListener != null) {
      controller.removeListener(existingListener);
    }

    void handleQuizCheck() {
      if (!mounted) return;
      if (_currentIndex != index) return;
      if (_activeQuizVN.value != null) return;

      try {
        if (SharedVideoControllerPool().isControllerDisposed(controller)) return;
        if (!controller.value.isInitialized) return;

        final currentPosition = controller.value.position;
        final currentSeconds = currentPosition.inSeconds;
        final currentMillis = currentPosition.inMilliseconds;
        final shownQuizzes = _shownQuizzesPerVideo[videoId] ??= {};

        for (int i = 0; i < video.quizzes!.length; i++) {
          final quiz = video.quizzes![i];
          if (shownQuizzes.contains(i)) continue;

          // **ROBUST TRIGGER (Senior Move)**:
          // 1. Check if we are within 1 second of the target
          // 2. OR check if we just passed the target in the last 500ms
          // This prevents "skipping" the trigger due to frame drops or streaming lag.
          final targetMillis = quiz.timestamp * 1000;
          final diff = currentMillis - targetMillis;

          if (diff >= 0 && diff < 1500) { // If we are at or up to 1.5s past the mark
            _activeQuizVN.value = quiz;
            shownQuizzes.add(i);
            (_quizHistoryPerVideo[videoId] ??= []).add(quiz);
            AppLogger.log('🎉 YugFeed: Triggered quiz "${quiz.question}" at $currentSeconds seconds');
            break;
          }
        }
      } catch (e) {
        // Silently ignore disposal errors
      }
    }

    _quizListeners[videoId] = handleQuizCheck;
    controller.addListener(handleQuizCheck);
  }
}
