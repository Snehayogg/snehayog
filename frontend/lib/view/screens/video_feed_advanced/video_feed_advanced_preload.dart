part of '../video_feed_advanced.dart';

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

      }
      
      // **DYNAMIC POOL: Configure shared pool based on device power**
      SharedVideoControllerPool().configurePool(isLowEndDevice: _isLowEndDevice);
      
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
      
      // Prefetch initial 500KB chunk for instant playback
      videoCacheProxy.prefetchInitialChunk(currentUrl, kilobytes: 500).catchError((_){});
    }
    
    // Still preload controller normally (initializes player)
    _preloadVideo(_currentIndex);
    
    // **STRICT DIRECTIONAL WINDOWS (User Request)**
    // Down: Focus on Current & Next (n+1). Clean everything else (past).
    // Up: Focus on Current & Prev (n-1). Clean everything else (future).
    
    int keepStart;
    int keepEnd;
    
    if (isScrollingDown) {
        // SCROLLING DOWN -> Keep [Current, Current+1]
        keepStart = _currentIndex;       
        keepEnd = _currentIndex + 1;
        
        // Priority 1: Current (handled above with 500KB chunk)
        // Priority 2: Next Video (n+1) - Smaller chunk (300KB)
        if (_currentIndex + 1 < _videos.length) {
            final nextVideo = _videos[_currentIndex + 1];
            final nextUrl = nextVideo.hlsPlaylistUrl?.isNotEmpty == true
                ? nextVideo.hlsPlaylistUrl!
                : (nextVideo.hlsMasterPlaylistUrl?.isNotEmpty == true
                    ? nextVideo.hlsMasterPlaylistUrl!
                    : nextVideo.videoUrl);
            
            // Prefetch smaller chunk for next video (lower priority)
            videoCacheProxy.prefetchInitialChunk(nextUrl, kilobytes: 300).catchError((_){});
            
            // Preload controller for next video
            _preloadVideo(_currentIndex + 1);
        }
    } else {
        // SCROLLING UP -> Keep [Current-1, Current]
        keepStart = _currentIndex - 1;
        keepEnd = _currentIndex;
        
        // Priority 1: Current (handled above with 500KB chunk)
        // Priority 2: Prev Video (n-1) - Smaller chunk (300KB)
        if (_currentIndex - 1 >= 0) {
            final prevVideo = _videos[_currentIndex - 1];
            final prevUrl = prevVideo.hlsPlaylistUrl?.isNotEmpty == true
                ? prevVideo.hlsPlaylistUrl!
                : (prevVideo.hlsMasterPlaylistUrl?.isNotEmpty == true
                    ? prevVideo.hlsMasterPlaylistUrl!
                    : prevVideo.videoUrl);
            
            // Prefetch smaller chunk for previous video
            videoCacheProxy.prefetchInitialChunk(prevUrl, kilobytes: 300).catchError((_){});
            
            // Preload controller for previous video
            _preloadVideo(_currentIndex - 1);
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
      const triggerDistance = 20;
      if (distanceFromEnd <= triggerDistance) {
        _loadMoreVideos();
      }
    }
  }

  /// **PRELOAD SINGLE VIDEO**
  Future<void> _preloadVideo(int index) async {
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
          _preloadVideo(index);
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

      // **FIXED: Resolve playable URL (handles share page URLs)**
      videoUrl = await _resolvePlayableUrl(video);
      if (videoUrl == null || videoUrl.isEmpty) {
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
      if (instantController != null) {
        controller = instantController;
        isReused = true;
        _controllerPool[videoId] = controller;
        _lastAccessedLocal[videoId] = DateTime.now();
      } else if (sharedPool.isVideoLoaded(video.id)) {
        final fallbackController = sharedPool.getController(video.id);
        if (fallbackController != null) {
          controller = fallbackController;
          isReused = true;
          _controllerPool[videoId] = controller;
          _lastAccessedLocal[videoId] = DateTime.now();
        }
      }

      if (controller != null && index != _currentIndex && controller.value.isPlaying) {
        controller.pause();
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
            await controller.initialize().timeout(
              const Duration(seconds: 12),
              onTimeout: () => throw Exception('HLS timeout'),
            );
          } else {
            await controller.initialize().timeout(
              const Duration(seconds: 8),
              onTimeout: () => throw Exception('Video timeout'),
            );
          }
          
          if (index != _currentIndex && controller.value.isPlaying) {
             controller.pause();
          }
        } finally {
          _initializingVideos.remove(videoId);
        }

        // **RELEVANCY CHECKPOINT #3: After initialization**
        if (mounted && (index - _currentIndex).abs() > 1 && index != _currentIndex) {
          _loadingVideos.remove(videoId);
          controller.dispose();
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
          _getOrCreateNotifier<bool>(_firstFrameReady, videoId, isReused);
          
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
        _attachErrorListenerIfNeeded(controller, index);

        _getOrCreateNotifier<bool>(_firstFrameReady, videoId, isReused);
        if (index <= 1 && !isReused) {
          _forceMountPlayer[videoId] = ValueNotifier<bool>(false);
          Future.delayed(const Duration(milliseconds: 700), () {
            if (mounted && _firstFrameReady[videoId]?.value != true) {
              _getOrCreateNotifier<bool>(_forceMountPlayer, videoId, true);
            }
          });
        }
      }

      if (mounted && index == _currentIndex) {
         _tryAutoplayCurrentImmediate(index);
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

      // **NEW: Bypass URL fixing for local gallery videos**
      if (video.videoType == 'local_gallery') {
         return video.videoUrl;
      }

      // 2. **Fallback: MP4 (if HLS is missing)**
      // Check for 480p optimized URL first
      if (video.lowQualityUrl != null && video.lowQualityUrl!.isNotEmpty) {
         if (!video.lowQualityUrl!.contains('.m3u8')) {
            final url = _validateAndFixVideoUrl(video.lowQualityUrl!);

            return url;
         }
      }

      // 3. **Deep Link Handling (snehayog.site)**
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

      // 3. **Final Fallback: videoUrl**
      // Checks main URL. Note: VideoService might have already optimized this to HLS.
      return _validateAndFixVideoUrl(video.videoUrl);
    } catch (_) {
      return _validateAndFixVideoUrl(video.videoUrl);
    }
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
             ctrl.pause();
             ctrl.setVolume(0.0);
          }
          ctrl.removeListener(_bufferingListeners[videoId] ?? () {});
          ctrl.removeListener(_videoEndListeners[videoId] ?? () {});
          
          if (_errorListeners.containsKey(videoId)) {
             ctrl.removeListener(_errorListeners[videoId]!);
             _errorListeners.remove(videoId);
          }
          ctrl.dispose();
        } catch (e) {
          AppLogger.log('⚠️ Error disposing controller for video $videoId: $e');
        }
      }

      _controllerPool.remove(videoId);
      _controllerStates.remove(videoId);
      _preloadedVideos.remove(videoId);
      _isBuffering.remove(videoId);
      
      if (_firstFrameReady.containsKey(videoId)) {
        _firstFrameReady[videoId]?.value = false;
        _firstFrameReady.remove(videoId);
      }
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
          if (_userPaused[videoId] == true) return;
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
            _getOrCreateNotifier<bool>(_isSlowConnectionVN, videoId, false);
          }
    
          _getOrCreateNotifier<bool>(_isBufferingVN, videoId, isBuffering);
      }
      
      // **2. SILENT STALL DETECTION Watchdog**
      // Detects when video claims to be playing but position isn't moving
      if (value.isPlaying && !value.isBuffering) {
          if (lastPosition == value.position) {
             // Position hasn't moved
             lastMoveTime ??= DateTime.now();
             
             if (DateTime.now().difference(lastMoveTime!) > const Duration(milliseconds: 3000)) {
                 // **STALL DETECTED (>3s freeze)**
                 AppLogger.log('❄️ Silent Stall detected for video $videoId (Frozen for 3s). Kicking...');
                 
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
      final value = controller.value;
      
      if (value.hasError) {
        final errorMessage = value.errorDescription ?? 'Unknown playback error';
        if (_videoErrors[videoId] != errorMessage) {
          AppLogger.log('❌ Runtime Video Error for video $videoId: $errorMessage');
          safeSetState(() {
            _videoErrors[videoId] = errorMessage;
            // Force hide loading state if error occurs
            _loadingVideos.remove(videoId);
            _isBuffering[videoId] = false;
            _isBufferingVN[videoId]?.value = false;
            
            // **CRITICAL FIX: Zombie Audio Killer**
            // If error occurs, immediate kill the controller to stop any background audio
            try {
               controller.pause();
               controller.setVolume(0.0);
               // Remove from pools immediately
               _controllerPool.remove(videoId);
               if (_controllerPool.containsKey(videoId)) {
                  // Double safety
                  _controllerPool[videoId]?.dispose(); 
               }
            } catch (_) {}
          });
        }
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
    _firstFrameReady[videoId]?.value = true;
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
}
