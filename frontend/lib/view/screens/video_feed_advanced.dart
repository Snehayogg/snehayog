import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/model/carousel_ad_model.dart';
import 'package:vayu/services/video_service.dart';
import 'package:vayu/services/authservices.dart';
import 'package:vayu/services/user_service.dart';
import 'package:vayu/core/managers/carousel_ad_manager.dart';
import 'package:vayu/view/widget/comments_sheet_widget.dart';
import 'package:vayu/services/comments/video_comments_data_source.dart';
import 'package:vayu/services/active_ads_service.dart';
import 'package:vayu/services/video_view_tracker.dart';
import 'package:vayu/services/ad_refresh_notifier.dart';
import 'package:vayu/services/background_profile_preloader.dart';
import 'package:vayu/services/profile_preloader.dart';
import 'package:vayu/services/ad_impression_service.dart';
import 'package:vayu/view/widget/ads/carousel_ad_widget.dart';
import 'package:vayu/view/screens/video_feed_advanced/widgets/banner_ad_section.dart';
import 'package:vayu/view/screens/video_feed_advanced/widgets/heart_animation.dart';
import 'package:vayu/services/connectivity_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:vayu/config/app_config.dart';
import 'package:vayu/view/screens/profile_screen.dart';
import 'package:vayu/view/screens/login_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayu/controller/main_controller.dart';
import 'package:vayu/core/managers/video_controller_manager.dart';
import 'package:vayu/core/managers/shared_video_controller_pool.dart';
import 'package:vayu/view/widget/report/report_dialog_widget.dart';
import 'package:vayu/core/managers/smart_cache_manager.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayu/view/widget/custom_share_widget.dart';
import 'package:vayu/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/controller/google_sign_in_controller.dart';
import 'package:vayu/services/earnings_service.dart';
import 'package:vayu/core/utils/video_engagement_ranker.dart';
import 'package:vayu/config/admob_config.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vayu/view/screens/profile_screen.dart';

part 'video_feed_advanced/video_feed_advanced_state_fields.dart';
part 'video_feed_advanced/video_feed_advanced_playback.dart';
part 'video_feed_advanced/video_feed_advanced_persistence.dart';
part 'video_feed_advanced/video_feed_advanced_initialization.dart';
part 'video_feed_advanced/video_feed_advanced_data.dart';
part 'video_feed_advanced/video_feed_advanced_preload.dart';
part 'video_feed_advanced/video_feed_advanced_ui.dart';

// #region agent log
// Debug logging helper for instrumentation
Future<void> _debugLog(String location, String message,
    Map<String, dynamic> data, String hypothesisId) async {
  try {
    final payload = {
      'id': 'log_${DateTime.now().millisecondsSinceEpoch}_${hypothesisId}',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'location': location,
      'message': message,
      'data': data,
      'sessionId': 'debug-session',
      'runId': 'run1',
      'hypothesisId': hypothesisId,
    };
    // Try to write to workspace log file (for desktop/web)
    try {
      final logFile = File(r'c:\Users\sanje\apps\Vayu\.cursor\debug.log');
      await logFile.writeAsString('${jsonEncode(payload)}\n',
          mode: FileMode.append);
    } catch (_) {
      // Fallback: write to app documents directory
      try {
        final appDir = await getApplicationDocumentsDirectory();
        final logFile = File('${appDir.path}/debug.log');
        await logFile.writeAsString('${jsonEncode(payload)}\n',
            mode: FileMode.append);
      } catch (_) {
        // If both fail, at least log to console
        AppLogger.log(
            '🔍 DEBUG [$hypothesisId]: $message - ${jsonEncode(data)}');
      }
    }
  } catch (_) {}
}
// #endregion

class VideoFeedAdvanced extends StatefulWidget {
  final int? initialIndex;
  final List<VideoModel>? initialVideos;
  final String? initialVideoId;
  final String? videoType;
  // Removed forceAutoplay; we'll infer autoplay from initialVideos presence

  const VideoFeedAdvanced({
    Key? key,
    this.initialIndex,
    this.initialVideos,
    this.initialVideoId,
    this.videoType, // **NEW: Accept videoType parameter**
  }) : super(key: key);

  @override
  _VideoFeedAdvancedState createState() => _VideoFeedAdvancedState();
}

class _VideoFeedAdvancedState extends State<VideoFeedAdvanced>
    with
        WidgetsBindingObserver,
        AutomaticKeepAliveClientMixin,
        VideoFeedStateFieldsMixin {
  final Map<String, bool> _likeInProgress = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    // **NEW: Track when screen was first opened for sign-in prompt delay**
    _screenFirstOpenedAt = DateTime.now();

    // Add app lifecycle observer
    WidgetsBinding.instance.addObserver(this);

    // Initialize services
    _initializeServices();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
        _handleAppMovedToBackground(state);
        break;
      case AppLifecycleState.inactive:
        _handleAppMovedToBackground(state);
        break;
      case AppLifecycleState.resumed:
        _videoControllerManager.onAppResumed();
        // **FIX: Set screen visible again when app resumes**
        _isScreenVisible = true;
        _ensureWakelockForVisibility();
        _lifecyclePaused = false;
        // Try restoring state after resume
        _restoreBackgroundStateIfAny().then((_) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_lifecyclePaused) {
              AppLogger.log(
                '⏸️ Resume detected but autoplay blocked until user interaction.',
              );
              return;
            }
            final openedFromProfile = widget.initialVideos != null &&
                widget.initialVideos!.isNotEmpty;
            if (openedFromProfile) {
              _tryAutoplayCurrent();
              return;
            }
            if (_mainController?.currentIndex == 0 &&
                !_mainController!.isMediaPickerActive &&
                !_mainController!.recentlyReturnedFromPicker) {
              _tryAutoplayCurrent();
            }
          });
        });
        break;
      case AppLifecycleState.detached:
        _videoControllerManager.disposeAllControllers();
        _videoControllerManager.onAppDetached();
        _ensureWakelockForVisibility();
        break;
      case AppLifecycleState.hidden:
        _handleAppMovedToBackground(state);
        break;
    }
  }

  void _handleAppMovedToBackground(AppLifecycleState state) {
    _saveBackgroundState();
    _pauseAllVideosOnTabSwitch();
    _videoControllerManager.pauseAllVideos();
    _videoControllerManager.onAppPaused();
    SharedVideoControllerPool().pauseAllControllers();
    _lifecyclePaused = true;
    _pendingAutoplayAfterLogin = false;
    _ensureWakelockForVisibility();
    AppLogger.log(
      '📱 VideoFeedAdvanced: Lifecycle state $state triggered background handling; all videos paused.',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // **PERFORMANCE: Cache MainController to avoid repeated Provider.of() calls**
    _mainController = Provider.of<MainController>(context, listen: false);

    // **PERFORMANCE: Cache MediaQuery data to avoid repeated lookups**
    final mediaQuery = MediaQuery.of(context);
    _screenWidth = mediaQuery.size.width;
    _screenHeight = mediaQuery.size.height;

    // **FIXED: Listen to auth state changes from GoogleSignInController**
    final authController = Provider.of<GoogleSignInController>(
      context,
      listen: false,
    );
    if (authController.isSignedIn && authController.userData != null) {
      // Use googleId as the single source of truth for likes (backend returns likedBy as googleIds)
      final userId = authController.userData!['googleId'] ??
          authController.userData!['id'];
      if (userId != null && _currentUserId != userId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() {
              _currentUserId = userId;
            });
            AppLogger.log(
              '✅ VideoFeedAdvanced: User ID updated from auth state: $userId',
            );
          }
        });
      }
    } else if (!authController.isSignedIn && _currentUserId != null) {
      // User signed out - clear current user ID
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _currentUserId = null;
          });
          AppLogger.log('✅ VideoFeedAdvanced: User ID cleared (signed out)');
        }
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // **FIX: Allow autoplay when opened from ProfileScreen OR when on Yug tab AND screen is visible**
      final bool isYugTabActive = _mainController?.currentIndex == 0 &&
          !_mainController!.isMediaPickerActive &&
          !_mainController!.recentlyReturnedFromPicker;

      // **CRITICAL FIX: Set _isScreenVisible = true when Yug tab is active (not opened from profile)**
      // This ensures videos autoplay when Yug tab is first loaded
      if (!_openedFromProfile && isYugTabActive && !_isScreenVisible) {
        _isScreenVisible = true;
        _ensureWakelockForVisibility();
        AppLogger.log(
          '✅ VideoFeedAdvanced: Yug tab active - setting _isScreenVisible = true',
        );
      }

      final bool shouldAttemptAutoplay =
          _openedFromProfile || (isYugTabActive && _isScreenVisible);

      if (shouldAttemptAutoplay) {
        // **FIX: Ensure screen is visible when opened from ProfileScreen**
        if (_openedFromProfile) {
          _isScreenVisible = true;
          _ensureWakelockForVisibility();
        }

        // **FIX: Ensure video is preloaded before trying autoplay**
        if (_videos.isNotEmpty && _currentIndex < _videos.length) {
          // If controller not initialized, preload first
          if (!_controllerPool.containsKey(_currentIndex) ||
              _controllerPool[_currentIndex]?.value.isInitialized != true) {
            _preloadVideo(_currentIndex).then((_) {
              if (mounted) {
                Future.delayed(const Duration(milliseconds: 100), () {
                  if (mounted) {
                    _tryAutoplayCurrent();
                  }
                });
              }
            });
          } else {
            _tryAutoplayCurrent();
          }
        }
      }
    });
  }

  /// **TRY AUTOPLAY CURRENT: Ensure current video starts playing**
  void _tryAutoplayCurrent() {
    if (_videos.isEmpty || _isLoading) return;
    if (!_shouldAutoplayForContext('tryAutoplayCurrent')) return;
    _autoAdvancedForIndex.remove(_currentIndex);

    // Check if current video is preloaded
    if (_controllerPool.containsKey(_currentIndex)) {
      final controller = _controllerPool[_currentIndex];
      if (controller != null &&
          controller.value.isInitialized &&
          !controller.value.isPlaying) {
        if (_userPaused[_currentIndex] == true) {
          AppLogger.log(
            '⏸️ Autoplay suppressed: user has manually paused video at index $_currentIndex',
          );
          return;
        }

        try {
          controller.setVolume(1.0);
        } catch (_) {}
        if (!_shouldAutoplayForContext('autoplay current immediate')) return;
        _pauseAllOtherVideos(_currentIndex);
        controller.play();
        _ensureWakelockForVisibility();
        _controllerStates[_currentIndex] = true;
        _userPaused[_currentIndex] = false;
        _pendingAutoplayAfterLogin = false;
        AppLogger.log('✅ VideoFeedAdvanced: Current video autoplay started');
      }
    } else {
      // Video not preloaded, preload it and play when ready
      AppLogger.log(
        '🔄 VideoFeedAdvanced: Current video not preloaded, preloading...',
      );
      _preloadVideo(_currentIndex).then((_) {
        if (mounted && _controllerPool.containsKey(_currentIndex)) {
          final controller = _controllerPool[_currentIndex];
          if (controller != null && controller.value.isInitialized) {
            // **FIX: Don't autoplay if user has manually paused the video**
            if (_userPaused[_currentIndex] == true) {
              AppLogger.log(
                '⏸️ Autoplay suppressed after preload: user has manually paused video at index $_currentIndex',
              );
              return;
            }
            if (!_shouldAutoplayForContext('autoplay current after preload')) {
              return;
            }

            try {
              controller.setVolume(1.0);
            } catch (_) {}
            _pauseAllOtherVideos(_currentIndex);
            controller.play();
            _ensureWakelockForVisibility();
            _controllerStates[_currentIndex] = true;
            _userPaused[_currentIndex] = false;
            _pendingAutoplayAfterLogin = false;
            AppLogger.log(
              '✅ VideoFeedAdvanced: Current video autoplay started after preloading',
            );
          }
        }
      });
    }
  }

  // (Reverted: removed _autoplayWhenReady helper)

  /// **HANDLE VISIBILITY CHANGES: Pause/resume videos based on tab visibility**
  void _handleVisibilityChange(bool isVisible) {
    if (_isScreenVisible != isVisible) {
      _isScreenVisible = isVisible;

      if (isVisible) {
        // Returning to Yug tab - ensure current video autoplays (no audio overlap)
        // 1) Mark first frame ready if controller already initialized
        if (_currentIndex < _videos.length) {
          final controller = _controllerPool[_currentIndex];
          if (controller != null && controller.value.isInitialized) {
            _firstFrameReady[_currentIndex]?.value = true;
          }
        }

        // 2) Pause all other videos to avoid audio overlap
        _pauseAllVideosOnTabSwitch();
        _isScreenVisible =
            true; // set visible again after pause helper sets false
        _ensureWakelockForVisibility();

        // 3) Autoplay the current video
        AppLogger.log(
          '▶️ VideoFeedAdvanced: Yug tab visible - trying autoplay',
        );
        _tryAutoplayCurrent();

        // 4) Start background profile preloading
        _profilePreloader.startBackgroundPreloading();
      } else {
        // Screen became hidden - pause current video
        _pauseCurrentVideo();

        // **NEW: Stop background profile preloading**
        _profilePreloader.stopBackgroundPreloading();
        _ensureWakelockForVisibility();
      }
    }
  }

  void _enableWakelock() {
    if (_wakelockEnabled) return;
    WakelockPlus.enable();
    _wakelockEnabled = true;
  }

  void _disableWakelock() {
    if (!_wakelockEnabled) return;
    WakelockPlus.disable();
    _wakelockEnabled = false;
  }

  bool _hasActivePlayback() {
    for (final controller in _controllerPool.values) {
      if (controller.value.isInitialized && controller.value.isPlaying) {
        return true;
      }
    }
    return SharedVideoControllerPool().hasActivePlayback();
  }

  bool get _openedFromProfile =>
      widget.initialVideos != null && widget.initialVideos!.isNotEmpty;

  bool get _openedFromDeepLink =>
      widget.initialVideoId != null && widget.initialVideos == null;

  bool _shouldAutoplayForContext(String context) {
    if (!_allowAutoplay(context)) {
      return false;
    }
    // **ENHANCED: Allow autoplay for profile videos and deep links**
    if (_openedFromProfile || _openedFromDeepLink) {
      AppLogger.log(
        '✅ Autoplay allowed ($context): ${_openedFromProfile ? "opened from profile" : "opened from deep link"}',
      );
      return true;
    }
    final bool isVideoTabActive =
        (_mainController?.currentIndex ?? 0) == 0 && _isScreenVisible;
    if (!isVideoTabActive) {
      AppLogger.log(
        '⏸️ Autoplay suppressed ($context): Yug tab not active or screen hidden',
      );
      return false;
    }
    return true;
  }

  void _scheduleAutoplayAfterLogin() {
    if (!_pendingAutoplayAfterLogin) return;

    Future.delayed(const Duration(milliseconds: 150), () {
      if (!mounted) return;

      if (!_shouldAutoplayForContext('autoplay after login')) {
        AppLogger.log(
          '⏸️ Autoplay deferred (login): Yug tab not active or screen hidden',
        );
        return;
      }

      _pendingAutoplayAfterLogin = false;
      AppLogger.log('🚀 Triggering autoplay after login');
      forcePlayCurrent();
    });
  }

  void _ensureWakelockForVisibility() {
    final bool shouldKeepAwake =
        (_isScreenVisible && !_lifecyclePaused) || _hasActivePlayback();
    if (shouldKeepAwake) {
      _enableWakelock();
    } else {
      _disableWakelock();
    }
  }

  bool _allowAutoplay(String context) {
    if (_lifecyclePaused) {
      AppLogger.log('⏸️ Autoplay blocked ($context) due to lifecycle pause.');
      return false;
    }
    return true;
  }

  /// **PAUSE CURRENT VIDEO: When screen becomes hidden**
  void _pauseCurrentVideo() {
    // **NEW: Stop view tracking when pausing**
    if (_currentIndex < _videos.length) {
      final currentVideo = _videos[_currentIndex];
      _viewTracker.stopViewTracking(currentVideo.id);
    }

    // Pause local controller pool
    if (_controllerPool.containsKey(_currentIndex)) {
      final controller = _controllerPool[_currentIndex];

      if (controller != null &&
          controller.value.isInitialized &&
          controller.value.isPlaying) {
        controller.pause();
        _controllerStates[_currentIndex] = false;
      }
    }

    // Also pause VideoControllerManager videos
    _videoControllerManager.pauseAllVideosOnTabChange();
  }

  void _pauseAllVideosOnTabSwitch() {
    // Pause all active controllers in the pool
    _controllerPool.forEach((index, controller) {
      if (controller.value.isInitialized && controller.value.isPlaying) {
        controller.pause();
        _controllerStates[index] = false;
      }
    });

    // Also pause VideoControllerManager videos
    _videoControllerManager.pauseAllVideosOnTabChange();
    SharedVideoControllerPool().pauseAllControllers();

    // Update screen visibility state
    _isScreenVisible = false;
    _disableWakelock();
  }

  /// **NEW: Pause videos before navigating away (e.g., to creator profile)**
  void _pauseVideosForProfileNavigation() {
    try {
      AppLogger.log(
          '⏸️ VideoFeedAdvanced: Pausing current video before navigation');
      _pauseCurrentVideo();
    } catch (e) {
      AppLogger.log('⚠️ VideoFeedAdvanced: Error pausing current video: $e');
    }

    try {
      final sharedPool = SharedVideoControllerPool();
      sharedPool.pauseAllControllers();
    } catch (e) {
      AppLogger.log(
          '⚠️ VideoFeedAdvanced: Error pausing SharedVideoControllerPool: $e');
    }

    try {
      _videoControllerManager.pauseAllVideosOnTabChange();
    } catch (e) {
      AppLogger.log(
          '⚠️ VideoFeedAdvanced: Error pausing VideoControllerManager: $e');
    }
  }

  /// **PRELOAD SINGLE VIDEO**
  Future<void> _preloadVideo(int index) async {
    if (index >= _videos.length) return;

    // **NEW: Check if we're already at max concurrent initializations**
    if (_initializingVideos.length >= _maxConcurrentInitializations &&
        !_preloadedVideos.contains(index) &&
        !_loadingVideos.contains(index)) {
      // Queue this video for later initialization
      AppLogger.log(
        '⏳ Max concurrent initializations reached, deferring video $index',
      );
      Future.delayed(const Duration(milliseconds: 500), () {
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

      // **REMOVED: Processing status check - backend now only returns completed videos**

      // **FIXED: Resolve playable URL (handles share page URLs)**
      videoUrl = await _resolvePlayableUrl(video);
      if (videoUrl == null || videoUrl.isEmpty) {
        AppLogger.log(
          '❌ Invalid video URL for video $index: ${video.videoUrl}',
        );
        _loadingVideos.remove(index);
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
            await controller.initialize().timeout(
              const Duration(seconds: 30), // Increased timeout for HLS
              onTimeout: () {
                throw Exception('HLS video initialization timeout');
              },
            );
            AppLogger.log('✅ HLS Video initialized successfully');
          } else {
            AppLogger.log('🎬 Regular Video detected: $videoUrl');
            // **FIXED: Add timeout and better error handling for regular videos**
            await controller.initialize().timeout(
              const Duration(seconds: 10),
              onTimeout: () {
                throw Exception('Video initialization timeout');
              },
            );
            AppLogger.log('✅ Regular Video initialized successfully');
          }
        } finally {
          // **NEW: Always remove from initializing set**
          _initializingVideos.remove(index);
        }
      } else {
        AppLogger.log(
          '♻️ Skipping initialization - reusing initialized controller',
        );

        // **FIX: Trigger rebuild for reused controllers too to ensure progress bar and pause state work**
        if (mounted && controller.value.isInitialized) {
          final isPlaying =
              controller.value.isPlaying; // Store value for null safety
          setState(() {
            // Ensure first frame ready is initialized (reused controllers already have first frame)
            _firstFrameReady[index] ??= ValueNotifier<bool>(true);
            // Initialize user paused state if not already set
            if (!_userPaused.containsKey(index)) {
              _userPaused[index] = false;
            }
            // Ensure controller state is initialized based on actual controller state
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
        _controllerStates[index] = false; // Not playing initially
        _preloadedVideos.add(index);
        _loadingVideos.remove(index);
        _lastAccessedLocal[index] = DateTime.now();

        // **UNIFIED STRATEGY: Always add to shared pool with index tracking**
        final sharedPool = SharedVideoControllerPool();
        final video = _videos[index];
        sharedPool.addController(video.id, controller, index: index);
        AppLogger.log(
          '✅ Added video controller to shared pool: ${video.id} (index: $index)',
        );

        // **FIX: Trigger rebuild after controller initialization to ensure progress bar and pause state are properly initialized**
        if (mounted) {
          setState(() {
            // Ensure first frame ready is initialized
            _firstFrameReady[index] ??= ValueNotifier<bool>(false);
            // Initialize user paused state if not already set
            if (!_userPaused.containsKey(index)) {
              _userPaused[index] = false;
            }
            // Ensure controller state is set
            if (!_controllerStates.containsKey(index)) {
              _controllerStates[index] = false;
            }
          });
          AppLogger.log(
            '🔄 Triggered rebuild after controller initialization for index $index',
          );
        }

        // Apply looping vs auto-advance behavior
        _applyLoopingBehavior(controller);
        // Attach end listener for auto-scroll
        _attachEndListenerIfNeeded(controller, index);
        // Attach buffering listener to track mid-playback stalls
        _attachBufferingListenerIfNeeded(controller, index);

        // First-frame priming: play muted off-screen to obtain first frame, then pause
        _firstFrameReady[index] = ValueNotifier<bool>(false);
        // Fallback force-mount for top items if first frame is slow
        if (index <= 1) {
          _forceMountPlayer[index] = ValueNotifier<bool>(false);
          Future.delayed(const Duration(milliseconds: 700), () {
            if (mounted && _firstFrameReady[index]?.value != true) {
              _forceMountPlayer[index]?.value = true;
            }
          });
        }
        // Prime only within decoder budget (current + next), and only when visible
        final bool shouldPrime = _canPrimeIndex(index);
        if (shouldPrime) {
          try {
            await controller.setVolume(0.0);
            // Tiny seek helps codecs surface a real frame
            await controller.seekTo(const Duration(milliseconds: 1));
            await controller.play();
          } catch (_) {}
        }

        // Listen until first frame appears, then pause and mark ready
        void markReadyIfNeeded() async {
          if (_firstFrameReady[index]?.value == true) return;
          final v = controller!.value;
          if (v.isInitialized && v.position > Duration.zero && !v.isBuffering) {
            _firstFrameReady[index]?.value = true;
            try {
              await controller.pause();
              await controller.setVolume(1.0);
            } catch (_) {}

            // **FIX: Trigger rebuild when first frame is ready to ensure progress bar shows**
            if (mounted) {
              setState(() {
                // Ensure user paused state is initialized
                if (!_userPaused.containsKey(index)) {
                  _userPaused[index] = false;
                }
                // Ensure controller state is initialized
                if (!_controllerStates.containsKey(index)) {
                  _controllerStates[index] = false;
                }
              });
              AppLogger.log(
                '🔄 Triggered rebuild when first frame ready for index $index',
              );
            }

            // If this is the active cell and visible, start playback now
            if (index == _currentIndex) {
              // **FIX: Don't autoplay if user has manually paused the video**
              if (_userPaused[index] == true) {
                AppLogger.log(
                  '⏸️ Autoplay suppressed in markReadyIfNeeded: user has manually paused video at index $index',
                );
                return;
              }

              if (_shouldAutoplayForContext('markReadyIfNeeded')) {
                try {
                  await controller.setVolume(
                    1.0,
                  ); // ensure audible on first start
                  _pauseAllOtherVideos(index);
                  await controller.play();
                  _controllerStates[_currentIndex] = true;
                  _userPaused[_currentIndex] = false;
                  _pendingAutoplayAfterLogin = false;
                } catch (_) {}
              }
            }
          }
        }

        controller.addListener(markReadyIfNeeded);

        // **NEW: Start view tracking if this is the current video**
        if (index == _currentIndex && index < _videos.length) {
          _viewTracker.startViewTracking(
            video.id,
            videoUploaderId: video.uploader.id,
          );
          AppLogger.log(
            '▶️ Started view tracking for preloaded current video: ${video.id}',
          );

          // **CRITICAL FIX: If reused controller for current video, start playing immediately**
          final bool openedFromProfile = _openedFromProfile;
          if (isReused &&
              controller.value.isInitialized &&
              !controller.value.isPlaying) {
            // **FIX: Don't autoplay if user has manually paused the video**
            if (_userPaused[index] == true) {
              AppLogger.log(
                '⏸️ Autoplay suppressed for reused controller: user has manually paused video at index $index',
              );
            } else {
              if (_shouldAutoplayForContext(openedFromProfile
                  ? 'reused controller (profile)'
                  : 'reused controller at current index')) {
                _pauseAllOtherVideos(index);
                controller.play();
                _controllerStates[index] = true;
                _userPaused[index] = false;
                _pendingAutoplayAfterLogin = false;
                AppLogger.log(
                  openedFromProfile
                      ? '✅ Started playback for reused controller (from Profile)'
                      : '✅ Started playback for reused controller at current index',
                );
              }
            }
          }

          // **NEW: Resume video if it was playing before navigation (better UX)**
          if (_wasPlayingBeforeNavigation[index] == true &&
              controller.value.isInitialized &&
              !controller.value.isPlaying) {
            // **FIX: Don't autoplay if user has manually paused the video**
            if (_userPaused[index] == true) {
              AppLogger.log(
                '⏸️ Resume suppressed: user has manually paused video ${video.id} at index $index',
              );
              _wasPlayingBeforeNavigation[index] = false; // Clear the flag
            } else {
              if (_shouldAutoplayForContext(openedFromProfile
                  ? 'resume controller (profile)'
                  : 'resume controller (current)')) {
                _pauseAllOtherVideos(index);
                controller.play();
                _controllerStates[index] = true;
                _userPaused[index] = false;
                _wasPlayingBeforeNavigation[index] = false; // Clear the flag
                _pendingAutoplayAfterLogin = false;
                AppLogger.log(
                  openedFromProfile
                      ? '▶️ Resumed video ${video.id} that was playing before navigation (from Profile)'
                      : '▶️ Resumed video ${video.id} that was playing before navigation',
                );
              }
            }
          }
        }

        AppLogger.log('✅ Successfully preloaded video $index');

        // **CACHE STATUS UPDATE AFTER SUCCESSFUL PRELOAD**
        _preloadHits++;
        AppLogger.log('📊 Cache Status Update:');
        AppLogger.log('   Preload Hits: $_preloadHits');
        AppLogger.log('   Total Controllers: ${_controllerPool.length}');
        AppLogger.log('   Preloaded Videos: ${_preloadedVideos.length}');

        // Clean up old controllers to prevent memory leaks
        _cleanupOldControllers();
      } else {
        // **CRITICAL: Only dispose if not reused from shared pool**
        if (!isReused) {
          controller.dispose();
        }
      }
    } catch (e) {
      AppLogger.log('❌ Error preloading video $index: $e');
      _loadingVideos.remove(index);
      _initializingVideos.remove(index);

      // **NEW: Always dispose failed controllers to free decoder resources**
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

      // **NEW: Detect NO_MEMORY errors specifically**
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

      // **NEW: Check retry count**
      final retryCount = _preloadRetryCount[index] ?? 0;

      if (isNoMemoryError) {
        AppLogger.log('⚠️ NO_MEMORY error detected for video $index');

        // **NEW: Clean up old controllers first when out of memory**
        _cleanupOldControllers();

        // **NEW: Wait longer and reduce concurrent load for NO_MEMORY errors**
        if (retryCount < _maxRetryAttempts) {
          _preloadRetryCount[index] = retryCount + 1;
          final retryDelay = Duration(
            seconds: 10 + (retryCount * 5),
          ); // Exponential backoff
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
        // **HLS SUPPORT: Enhanced retry logic for HLS videos**
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

  /// **VALIDATE AND FIX VIDEO URL**
  String? _validateAndFixVideoUrl(String url) {
    if (url.isEmpty) return null;

    // **FIXED: Handle relative URLs and ensure proper base URL**
    if (!url.startsWith('http')) {
      // Remove leading slash if present to avoid double slash
      String cleanUrl = url;
      if (cleanUrl.startsWith('/')) {
        cleanUrl = cleanUrl.substring(1);
      }
      return '${VideoService.baseUrl}/$cleanUrl';
    }

    // **FIXED: Validate URL format**
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

  /// **RESOLVE PLAYABLE URL:** Prefer HLS, handle web-share page URLs
  Future<String?> _resolvePlayableUrl(VideoModel video) async {
    try {
      // 1) Prefer HLS fields if available in model
      final hlsUrl = video.hlsPlaylistUrl?.isNotEmpty == true
          ? video.hlsPlaylistUrl
          : video.hlsMasterPlaylistUrl;
      if (hlsUrl != null && hlsUrl.isNotEmpty) {
        return _validateAndFixVideoUrl(hlsUrl);
      }

      // 2) If video.videoUrl is already HLS/progressive direct URL
      if (video.videoUrl.contains('.m3u8') || video.videoUrl.contains('.mp4')) {
        return _validateAndFixVideoUrl(video.videoUrl);
      }

      // 3) If it's an app/web route like snehayog.app/video/<id>, fetch the API to get real URLs
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

      // 4) Fallback to original with baseUrl fix
      return _validateAndFixVideoUrl(video.videoUrl);
    } catch (_) {
      return _validateAndFixVideoUrl(video.videoUrl);
    }
  }

  void _cleanupOldControllers() {
    final sharedPool = SharedVideoControllerPool();

    // **UNIFIED STRATEGY: Let shared pool handle cleanup based on distance**
    sharedPool.cleanupDistantControllers(_currentIndex, keepRange: 3);

    // **LOCAL CLEANUP: Only remove local tracking for controllers not in shared pool**
    final controllersToRemove = <int>[];

    for (final index in _controllerPool.keys.toList()) {
      // Keep controllers that are in shared pool (they're managed there)
      if (index < _videos.length) {
        final videoId = _videos[index].id;
        if (sharedPool.isVideoLoaded(videoId)) {
          // Controller is in shared pool, just remove from local tracking
          controllersToRemove.add(index);
          continue;
        }
      }

      // Remove local tracking for distant or invalid controllers
      final distance = (index - _currentIndex).abs();
      if (distance > 3 || _controllerPool.length > 5) {
        controllersToRemove.add(index);
      }
    }

    // **CLEANUP: Remove only local tracking (controllers are in shared pool)**
    for (final index in controllersToRemove) {
      final ctrl = _controllerPool[index];

      // **CRITICAL: Only dispose if NOT in shared pool**
      if (index < _videos.length) {
        final videoId = _videos[index].id;
        if (!sharedPool.isVideoLoaded(videoId) && ctrl != null) {
          // Controller not in shared pool, dispose it
          try {
            ctrl.removeListener(_bufferingListeners[index] ?? () {});
            ctrl.removeListener(_videoEndListeners[index] ?? () {});
            ctrl.dispose();
          } catch (e) {
            AppLogger.log('⚠️ Error disposing controller at index $index: $e');
          }
        }
      }

      // Remove local tracking
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

  /// **GET OR CREATE CONTROLLER: Unified shared pool strategy**
  VideoPlayerController? _getController(int index) {
    if (index >= _videos.length) return null;

    final video = _videos[index];
    final sharedPool = SharedVideoControllerPool();

    // **PRIMARY: Check shared pool first (guaranteed instant playback)**
    VideoPlayerController? controller = sharedPool.getControllerForInstantPlay(
      video.id,
    );

    if (controller != null && controller.value.isInitialized) {
      // **CACHE HIT: Reuse from shared pool**
      AppLogger.log(
        '⚡ INSTANT: Reusing controller from shared pool for video ${video.id}',
      );

      // Add to local pool for UI tracking only
      _controllerPool[index] = controller;
      _controllerStates[index] = false;
      _preloadedVideos.add(index);
      _lastAccessedLocal[index] = DateTime.now();

      // **FIX: Mark first frame as ready since controller is already initialized**
      _firstFrameReady[index] = ValueNotifier<bool>(true);

      return controller;
    }

    // **FALLBACK: Check local pool**
    if (_controllerPool.containsKey(index)) {
      controller = _controllerPool[index];
      if (controller != null && controller.value.isInitialized) {
        _lastAccessedLocal[index] = DateTime.now();
        // **FIX: Mark first frame as ready since controller is already initialized**
        _firstFrameReady[index] = ValueNotifier<bool>(true);
        return controller;
      }
    }

    // **PRELOAD: If not in any pool, preload it**
    _preloadVideo(index);
    return null;
  }

  /// **HANDLE PAGE CHANGES** - Debounced for fast scrolling
  void _onPageChanged(int index) {
    if (index == _currentIndex) return;
    _pageChangeTimer?.cancel();
    _pageChangeTimer = Timer(const Duration(milliseconds: 150), () {
      _handlePageChangeDebounced(index);
    });
  }

  /// **DEBOUNCED PAGE CHANGE HANDLER**
  void _handlePageChangeDebounced(int index) {
    if (!mounted || index == _currentIndex) return;

    // **LRU: Track access time for previous index**
    _lastAccessedLocal[_currentIndex] = DateTime.now();

    // **NEW: Stop view tracking for previous video**
    if (_currentIndex < _videos.length) {
      final previousVideo = _videos[_currentIndex];
      _viewTracker.stopViewTracking(previousVideo.id);
      AppLogger.log(
        '⏸️ Stopped view tracking for previous video: ${previousVideo.id}',
      );

      // **NEW: Clear userPaused flag so returning to this video autoplays**
      _userPaused[_currentIndex] = false;
    }

    // **CRITICAL: Pause ALL videos (including current) before switching to new one**
    // Pause videos from local controller pool
    _controllerPool.forEach((idx, controller) {
      if (controller.value.isInitialized && controller.value.isPlaying) {
        try {
          controller.pause();
          _controllerStates[idx] = false;
        } catch (_) {}
      }
    });

    // **CRITICAL FIX: Also pause videos from VideoControllerManager**
    _videoControllerManager.pauseAllVideosOnTabChange();

    // **CRITICAL FIX: Also pause videos from SharedVideoControllerPool**
    final sharedPool = SharedVideoControllerPool();
    sharedPool.pauseAllControllers();

    _currentIndex = index;
    _reprimeWindowIfNeeded();

    // Safety: ensure newly active video's audio is unmuted
    final activeController = _controllerPool[_currentIndex];
    if (activeController != null && activeController.value.isInitialized) {
      try {
        activeController.setVolume(1.0);
      } catch (_) {}
    }
    // No force-unmute; priming excludes current index.

    // **UNIFIED STRATEGY: Use shared pool as primary source (Instant playback)**
    VideoPlayerController? controllerToUse;

    if (index < _videos.length) {
      final video = _videos[index];

      // **INSTANT LOADING: Try to get controller with instant playback guarantee**
      controllerToUse = sharedPool.getControllerForInstantPlay(video.id);

      if (controllerToUse != null && controllerToUse.value.isInitialized) {
        AppLogger.log(
          '⚡ INSTANT: Reusing controller from shared pool for video ${video.id}',
        );

        // Add to local pool for tracking only
        _controllerPool[index] = controllerToUse;
        _controllerStates[index] = false;
        _preloadedVideos.add(index);
        _lastAccessedLocal[index] = DateTime.now();

        // **FIX: Mark first frame as ready since controller is already initialized**
        _firstFrameReady[index] = ValueNotifier<bool>(true);

        // **MEMORY MANAGEMENT: Cleanup distant controllers**
        sharedPool.cleanupDistantControllers(index, keepRange: 3);
      } else if (sharedPool.isVideoLoaded(video.id)) {
        // Fallback: Get any available controller
        controllerToUse = sharedPool.getController(video.id);
        if (controllerToUse != null && controllerToUse.value.isInitialized) {
          _controllerPool[index] = controllerToUse;
          _controllerStates[index] = false;
          _preloadedVideos.add(index);
          _lastAccessedLocal[index] = DateTime.now();
          // **FIX: Mark first frame as ready since controller is already initialized**
          _firstFrameReady[index] = ValueNotifier<bool>(true);
        }
      }
    }

    // **FALLBACK: Check local pool only if shared pool doesn't have it**
    if (controllerToUse == null && _controllerPool.containsKey(index)) {
      controllerToUse = _controllerPool[index];
      if (controllerToUse != null && !controllerToUse.value.isInitialized) {
        // **AUTO-CLEANUP: Remove invalid controllers**
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
        // **FIX: Mark first frame as ready since controller is already initialized**
        _firstFrameReady[index] = ValueNotifier<bool>(true);
      }
    }

    // **FIXED: Play current video if we have a valid controller**
    if (controllerToUse != null && controllerToUse.value.isInitialized) {
      // Controller is ready; ensure context allows autoplay
      if (!_shouldAutoplayForContext('handlePageChange immediate')) {
        return;
      }

      // **FIX: Don't autoplay if user has manually paused the video**
      if (_userPaused[index] == true) {
        AppLogger.log(
          '⏸️ Autoplay suppressed: user has manually paused video at index $index',
        );
        return;
      }

      // **CRITICAL: Pause ALL other videos before playing current video**
      _pauseAllOtherVideos(index);

      controllerToUse.setVolume(1.0);
      controllerToUse.play();
      _controllerStates[index] = true;
      _userPaused[index] = false;
      _applyLoopingBehavior(controllerToUse);
      _attachEndListenerIfNeeded(controllerToUse, index);
      _attachBufferingListenerIfNeeded(controllerToUse, index);
      _pendingAutoplayAfterLogin = false;

      // **NEW: Start view tracking for current video**
      if (index < _videos.length) {
        final currentVideo = _videos[index];
        _viewTracker.startViewTracking(
          currentVideo.id,
          videoUploaderId: currentVideo.uploader.id,
        );
        AppLogger.log(
          '▶️ Started view tracking for current video: ${currentVideo.id}',
        );
      }

      // Preload nearby videos for smooth scrolling
      _preloadNearbyVideosDebounced();
      return; // Exit early - video is ready!
    }

    // **FIX: If still no controller, preload and mark as loading immediately**
    if (!_controllerPool.containsKey(index)) {
      AppLogger.log(
        '🔄 Video not preloaded, preloading and will autoplay when ready',
      );
      // Mark as loading immediately so UI shows thumbnail/loading instead of grey
      // No need for setState - the _loadingVideos set is already updated
      _preloadVideo(index).then((_) {
        // After preloading, check if this is still the current video
        if (mounted &&
            _currentIndex == index &&
            _controllerPool.containsKey(index)) {
          // Guard again: only autoplay if context allows it
          if (!_shouldAutoplayForContext('handlePageChange after preload')) {
            return;
          }
          final loadedController = _controllerPool[index];
          if (loadedController != null &&
              loadedController.value.isInitialized) {
            // **LRU: Track access time**
            _lastAccessedLocal[index] = DateTime.now();

            // **CRITICAL: Pause ALL other videos before playing current video**
            _pauseAllOtherVideos(index);

            loadedController.setVolume(1.0);
            loadedController.play();
            _controllerStates[index] = true;
            _userPaused[index] = false;
            _applyLoopingBehavior(loadedController);
            _attachEndListenerIfNeeded(loadedController, index);
            _attachBufferingListenerIfNeeded(loadedController, index);

            // **NEW: Start view tracking for current video**
            if (index < _videos.length) {
              final currentVideo = _videos[index];
              _viewTracker.startViewTracking(
                currentVideo.id,
                videoUploaderId: currentVideo.uploader.id,
              );
              AppLogger.log(
                '▶️ Started view tracking for current video: ${currentVideo.id}',
              );
            }

            AppLogger.log('✅ Video autoplay started after preloading');
            _pendingAutoplayAfterLogin = false;
          }
        }
      });
    }

    _preloadNearbyVideosDebounced();
  }

  /// **DEBOUNCED PRELOAD: Avoid too many preloads during fast scrolling**
  void _preloadNearbyVideosDebounced() {
    _preloadDebounceTimer?.cancel();
    _preloadDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      _preloadNearbyVideos();
    });
  }

  void _openReportDialog(String videoId) {
    if (videoId.isEmpty) return;
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) =>
          ReportDialogWidget(targetType: 'video', targetId: videoId),
    );
  }

  void _seekToPosition(VideoPlayerController controller, dynamic details) {
    if (!controller.value.isInitialized) return;

    final RenderBox renderBox = context.findRenderObject() as RenderBox;
    final localPosition = renderBox.globalToLocal(details.globalPosition);
    final screenWidth = _screenWidth ?? MediaQuery.of(context).size.width;
    final seekPosition = (localPosition.dx / screenWidth).clamp(0.0, 1.0);

    final duration = controller.value.duration;
    final newPosition = duration * seekPosition;

    controller.seekTo(newPosition);
  }

  // Quality indicator methods removed per requirement

  void _togglePlayPause(int index) {
    // **FIX: Prevent multiple simultaneous toggles on the same video (race condition fix)**
    if (_togglingVideos.contains(index)) {
      AppLogger.log(
        '⚠️ _togglePlayPause: Already toggling video at index $index, ignoring duplicate tap',
      );
      return;
    }

    // **FIX: If controller not initialized, preload it first then play**
    final controller = _controllerPool[index];
    if (controller == null || !controller.value.isInitialized) {
      AppLogger.log(
        '⚠️ _togglePlayPause: Controller not available or not initialized for index $index, preloading...',
      );

      // Preload video and then play it
      _preloadVideo(index).then((_) {
        if (!mounted) return;
        final c = _controllerPool[index];
        if (c != null && c.value.isInitialized) {
          try {
            _pauseAllOtherVideos(index);
            _autoAdvancedForIndex.remove(index);
            c.play();
            setState(() {
              _controllerStates[index] = true;
              _userPaused[index] = false;
            });
            AppLogger.log(
              '▶️ Successfully played video at index $index after preload',
            );

            // Start view tracking
            if (index < _videos.length) {
              final video = _videos[index];
              _viewTracker.startViewTracking(
                video.id,
                videoUploaderId: video.uploader.id,
              );
              AppLogger.log(
                '▶️ User played video: ${video.id}, started view tracking',
              );
            }
          } catch (e) {
            AppLogger.log(
              '❌ Error playing video after preload at index $index: $e',
            );
          }
        }
      }).catchError((e) {
        AppLogger.log(
          '❌ Error preloading video for play/pause at index $index: $e',
        );
      });
      return;
    }

    // **FIX: Add lock to prevent concurrent toggles**
    _togglingVideos.add(index);

    // **FIX: Check actual controller state instead of relying on _controllerStates map**
    // This ensures we always have the correct state, even if map is out of sync
    final isCurrentlyPlaying = controller.value.isPlaying;

    AppLogger.log(
      '🔄 _togglePlayPause: Video $index - Current state: ${isCurrentlyPlaying ? "playing" : "paused"}',
    );

    if (isCurrentlyPlaying) {
      // **FIX: Video is playing, so pause it - update state immediately before pause**
      try {
        // **CRITICAL: Update state FIRST, then pause - this ensures UI responds immediately**
        setState(() {
          _controllerStates[index] = false;
          _userPaused[index] = true;
        });

        // Now pause the controller
        controller.pause();
        _ensureWakelockForVisibility();

        AppLogger.log('⏸️ Successfully paused video at index $index');

        // **NEW: Stop view tracking when user pauses**
        if (index < _videos.length) {
          final video = _videos[index];
          _viewTracker.stopViewTracking(video.id);
          AppLogger.log(
            '⏸️ User paused video: ${video.id}, stopped view tracking',
          );
        }
      } catch (e) {
        AppLogger.log('❌ Error pausing video at index $index: $e');
        // **FIX: Remove lock on error**
        _togglingVideos.remove(index);
        return;
      }
    } else {
      // **FIX: Video is paused, so play it - update state immediately before play**
      try {
        _pauseAllOtherVideos(index);

        // **CRITICAL: Update state FIRST, then play - this ensures UI responds immediately**
        setState(() {
          _controllerStates[index] = true;
          _userPaused[index] = false; // hide when playing
        });
        _lifecyclePaused = false;

        // Now play the controller
        _autoAdvancedForIndex.remove(index);
        controller.play();
        _ensureWakelockForVisibility();

        AppLogger.log('▶️ Successfully played video at index $index');

        // **NEW: Start view tracking when user plays**
        if (index < _videos.length) {
          final video = _videos[index];
          _viewTracker.startViewTracking(
            video.id,
            videoUploaderId: video.uploader.id,
          );
          AppLogger.log(
            '▶️ User played video: ${video.id}, started view tracking',
          );
        }
      } catch (e) {
        AppLogger.log('❌ Error playing video at index $index: $e');
        // **FIX: Remove lock on error**
        _togglingVideos.remove(index);
        return;
      }
    }

    // **FIX: Remove lock after a short delay to allow state to settle**
    // This prevents rapid taps from causing race conditions
    Future.delayed(const Duration(milliseconds: 200), () {
      _togglingVideos.remove(index);
    });
  }

  /// **BUILD CAROUSEL AD PAGE: Full-screen carousel ad within horizontal PageView**
  void _attachEndListenerIfNeeded(VideoPlayerController controller, int index) {
    controller.removeListener(_videoEndListeners[index] ?? () {});
    void listener() {
      if (!_autoScrollEnabled) return;
      final position = controller.value.position;
      final duration = controller.value.duration;
      if (duration.inMilliseconds > 0 &&
          (duration - position).inMilliseconds <= 200) {
        // Near end: advance to next page
        if (_isAnimatingPage) return;
        if (_autoAdvancedForIndex.contains(index)) return;
        final int next = (_currentIndex + 1).clamp(0, _videos.length);
        if (next != _currentIndex && next < _videos.length) {
          _isAnimatingPage = true;
          _autoAdvancedForIndex.add(index);
          _pageController
              .animateToPage(
                next,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              )
              .whenComplete(() => _isAnimatingPage = false);
        }
      }
    }

    controller.addListener(listener);
    _videoEndListeners[index] = listener;
  }

  void _attachBufferingListenerIfNeeded(
    VideoPlayerController controller,
    int index,
  ) {
    controller.removeListener(_bufferingListeners[index] ?? () {});
    void listener() {
      if (!mounted) return;
      final bool next =
          controller.value.isInitialized && controller.value.isBuffering;
      final bool current = _isBuffering[index] ?? false;
      if (current != next) {
        // Update map (for any legacy reads)
        _isBuffering[index] = next;
        // Update ValueNotifier to avoid rebuilding the whole Stack
        (_isBufferingVN[index] ??= ValueNotifier<bool>(false)).value = next;
      }
    }

    controller.addListener(listener);
    _bufferingListeners[index] = listener;

    // (Removed first-frame tracking listener per revert)
  }

  @override
  final Map<int, VoidCallback> _videoEndListeners = {};

  void _applyLoopingBehavior(VideoPlayerController controller) {
    controller.setLooping(!_autoScrollEnabled);
  }

  /// **GET USER-FRIENDLY ERROR MESSAGE: Convert technical errors to user-friendly messages**
  String _getUserFriendlyErrorMessage(dynamic error) {
    // Use ConnectivityService for network error detection
    if (ConnectivityService.isNetworkError(error)) {
      return ConnectivityService.getNetworkErrorMessage(error);
    }

    final errorString = error.toString().toLowerCase();

    if (errorString.contains('timeout')) {
      return 'Request timed out. Please check your internet connection.';
    } else if (errorString.contains('404')) {
      return 'Videos not found';
    } else if (errorString.contains('500')) {
      return 'Server error. Please try again later.';
    } else if (errorString.contains('unauthorized') ||
        errorString.contains('401')) {
      return 'Authentication required. Please sign in again.';
    } else if (errorString.contains('403')) {
      return 'Access denied. You may not have permission for this action.';
    } else {
      return 'Unable to load videos. Please try again.';
    }
  }

  /// **HANDLE DOUBLE TAP LIKE: Show animation and like**
  Future<void> _handleDoubleTapLike(VideoModel video, int index) async {
    // Show heart animation
    _showHeartAnimation[index] ??= ValueNotifier<bool>(false);
    _showHeartAnimation[index]!.value = true;

    // Hide animation after 1 second
    Future.delayed(const Duration(milliseconds: 1000), () {
      _showHeartAnimation[index]?.value = false;
    });

    // If the video is already liked by the current user, only show animation.
    // Double-tap should act as "like", not toggle like/unlike twice.
    if (_currentUserId != null && video.likedBy.contains(_currentUserId)) {
      AppLogger.log(
        '🔴 DoubleTap Like: Video already liked by current user – showing animation only',
      );
      return;
    }

    // Handle the like (will respect _likeInProgress guard below)
    await _handleLike(video, index);
  }

  /// **HANDLE LIKE: With API integration**
  Future<void> _handleLike(VideoModel video, int index) async {
    AppLogger.log('🔴 ========== LIKE BUTTON CLICKED ==========');
    AppLogger.log('🔴 Video ID: ${video.id}');
    AppLogger.log('🔴 Video Name: ${video.videoName}');
    AppLogger.log('🔴 Current User ID: $_currentUserId');
    AppLogger.log('🔴 Current Likes: ${video.likes}');
    AppLogger.log('🔴 Current LikedBy: ${video.likedBy.length} users');

    // Guard against multiple rapid taps / concurrent calls for the same video.
    if (_likeInProgress[video.id] == true) {
      AppLogger.log(
        '⚠️ Like Handler: Like already in progress for video ${video.id}, ignoring duplicate tap',
      );
      return;
    }

    if (_currentUserId == null) {
      AppLogger.log('❌ Like Handler: User not logged in');
      // **NEW: Only show sign-in prompt if 5 minutes have passed**
      if (_canShowSignInPrompt()) {
        _navigateToLoginScreen();
      } else {
        final timeRemaining = _signInPromptDelay -
            DateTime.now().difference(_screenFirstOpenedAt!);
        final minutesRemaining = timeRemaining.inMinutes;
        AppLogger.log(
          '⏱️ Sign-in prompt delayed for like action. Time remaining: ${minutesRemaining}m',
        );
      }
      return;
    }

    // **OPTIMISTIC UPDATE: Update UI immediately for instant feedback (heart fills red instantly)**
    final wasLiked = video.likedBy.contains(_currentUserId);
    final originalLikes = video.likes;
    final originalLikedBy = List<String>.from(video.likedBy);

    AppLogger.log(
        '🔴 Like Handler: Current state - wasLiked: $wasLiked, originalLikes: $originalLikes');

    // Update UI immediately (optimistic) - this makes heart fill red instantly
    final videoIndex = _videos.indexWhere((v) => v.id == video.id);
    if (videoIndex != -1) {
      AppLogger.log(
          '🔴 Like Handler: Updating UI optimistically (before API call)');
      setState(() {
        if (wasLiked) {
          // User is currently liking, so unlike
          video.likedBy.remove(_currentUserId);
          video.likes = (video.likes - 1).clamp(0, double.infinity).toInt();
          AppLogger.log(
              '🔴 Like Handler: Optimistic UNLIKE - new count: ${video.likes}');
        } else {
          // User is not currently liking, so like
          video.likedBy.add(_currentUserId!);
          video.likes++;
          AppLogger.log(
              '🔴 Like Handler: Optimistic LIKE - new count: ${video.likes}');
        }
      });
    } else {
      AppLogger.log('⚠️ Like Handler: Video not found in _videos list!');
    }

    try {
      _likeInProgress[video.id] = true;
      AppLogger.log('🔴 Like Handler: Calling API to sync with backend...');
      AppLogger.log('🔴 Like Handler: API call starting at ${DateTime.now()}');

      // **SYNC WITH BACKEND: Get actual data from backend (ensures persistence)**
      VideoModel updatedVideo = await _videoService.toggleLike(video.id);

      AppLogger.log('🔴 Like Handler: API call completed at ${DateTime.now()}');
      AppLogger.log('✅ Successfully toggled like for video ${video.id}');
      AppLogger.log(
          '🔴 Like Handler: Backend response - likes: ${updatedVideo.likes}, likedBy: ${updatedVideo.likedBy.length}');

      // **CRITICAL: Replace with backend response to ensure persistence (trust backend counts)**
      if (videoIndex != -1) {
        AppLogger.log(
            '🔴 Like Handler: Updating video in list with backend response');
        setState(() {
          _videos[videoIndex] = updatedVideo;
        });
        AppLogger.log(
            '✅ VideoFeedAdvanced: Synced with backend - likes: ${updatedVideo.likes}, likedBy: ${updatedVideo.likedBy.length}');
        AppLogger.log('🔴 Like Handler: UI updated with backend data');
      } else {
        AppLogger.log('⚠️ VideoFeedAdvanced: Video not found in list for sync');
      }

      AppLogger.log('🔴 ========== LIKE SUCCESSFUL ==========');
    } catch (e) {
      AppLogger.log('🔴 ========== LIKE ERROR ==========');
      AppLogger.log('❌ Error handling like: $e');
      AppLogger.log('❌ Error type: ${e.runtimeType}');
      AppLogger.log('❌ Error details: ${e.toString()}');

      // **REVERT: If backend fails, revert optimistic update**
      AppLogger.log(
          '🔴 Like Handler: Reverting optimistic update due to error');
      if (videoIndex != -1) {
        setState(() {
          video.likedBy.clear();
          video.likedBy.addAll(originalLikedBy);
          video.likes = originalLikes;
        });
        AppLogger.log(
            '🔴 Like Handler: Reverted to original state - likes: ${video.likes}');
      }

      // **FIX: Show actual error message from backend**
      String errorMessage = 'Failed to like video';
      final errorString = e.toString();

      if (errorString.contains('sign in') ||
          errorString.contains('authenticated')) {
        errorMessage = 'Please sign in again to like videos';
        // **NEW: Only show sign-in prompt if 5 minutes have passed**
        if (_canShowSignInPrompt()) {
          Future.delayed(const Duration(milliseconds: 500), () {
            _navigateToLoginScreen();
          });
        }
      } else if (errorString.contains('User not found')) {
        errorMessage =
            'Please sign in again. Your account may not be registered.';
      } else if (errorString.contains('Video not found')) {
        errorMessage = 'Video not found';
      } else if (errorString.length > 100) {
        // Extract meaningful part of error
        errorMessage = errorString.substring(0, 100);
      } else {
        errorMessage = errorString.replaceAll('Exception: ', '');
      }

      _showSnackBar(errorMessage, isError: true);
      AppLogger.log('🔴 ========== LIKE FAILED ==========');
    } finally {
      // Always clear in-progress flag so future likes work.
      _likeInProgress[video.id] = false;
      AppLogger.log(
        '🔄 Like Handler: Cleared in-progress flag for video ${video.id}',
      );
    }
  }

  /// **NEW: Check if 5 minutes have passed since screen was first opened**
  bool _canShowSignInPrompt() {
    if (_screenFirstOpenedAt == null) {
      // If timestamp is not set, allow showing prompt (fallback)
      return true;
    }
    final timeSinceOpened = DateTime.now().difference(_screenFirstOpenedAt!);
    return timeSinceOpened >= _signInPromptDelay;
  }

  void _navigateToLoginScreen() {
    // **NEW: Only show sign-in prompt if 5 minutes have passed**
    if (!_canShowSignInPrompt()) {
      final timeRemaining =
          _signInPromptDelay - DateTime.now().difference(_screenFirstOpenedAt!);
      final minutesRemaining = timeRemaining.inMinutes;
      final secondsRemaining = timeRemaining.inSeconds % 60;
      AppLogger.log(
        '⏱️ Sign-in prompt delayed. Time remaining: ${minutesRemaining}m ${secondsRemaining}s',
      );
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  /// **HANDLE COMMENT: Open comment sheet**
  void _handleComment(VideoModel video) {
    // **FIX: Check if user is signed in before opening comment sheet**
    if (_currentUserId == null) {
      // **NEW: Only show sign-in prompt if 5 minutes have passed**
      if (_canShowSignInPrompt()) {
        _showSnackBar('Please sign in to view and add comments', isError: true);
        Future.delayed(const Duration(milliseconds: 500), () {
          _navigateToLoginScreen();
        });
      } else {
        final timeRemaining = _signInPromptDelay -
            DateTime.now().difference(_screenFirstOpenedAt!);
        final minutesRemaining = timeRemaining.inMinutes;
        AppLogger.log(
          '⏱️ Sign-in prompt delayed for comment action. Time remaining: ${minutesRemaining}m',
        );
      }
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => CommentsSheetWidget(
        video: video,
        videoService: _videoService,
        dataSource: VideoCommentsDataSource(
          videoId: video.id,
          videoService: _videoService,
        ),
        onCommentsUpdated: (updatedComments) {
          // Update video comments in the list
          setState(() {
            video.comments = updatedComments;
          });
        },
      ),
    );
  }

  /// **HANDLE SHARE: Show custom share widget with only 4 options**
  Future<void> _handleShare(VideoModel video) async {
    try {
      // Show custom share widget instead of system share
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => CustomShareWidget(video: video),
      );
    } catch (e) {
      AppLogger.log('❌ Error showing share widget: $e');
      _showSnackBar('Failed to open share options', isError: true);
    }
  }

  /// **HANDLE VISIT NOW: Open link in browser**
  Future<void> _handleVisitNow(VideoModel video) async {
    try {
      if (video.link?.isNotEmpty == true) {
        AppLogger.log('🔗 Visit Now tapped for: ${video.link}');

        // Use url_launcher to open the link
        final Uri url = Uri.parse(video.link!);

        // Check if the URL is valid
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        } else {
          _showSnackBar('Could not open link', isError: true);
        }
      }
    } catch (e) {
      AppLogger.log('❌ Error opening link: $e');
      _showSnackBar('Failed to open link', isError: true);
    }
  }

  /// **SHOW SNACKBAR: Helper method**
  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// **NAVIGATE TO CAROUSEL AD: Switch to carousel ad page (no rebuild)**
  void _navigateToCarouselAd(int index) {
    if (_carouselAds.isNotEmpty && _currentHorizontalPage.containsKey(index)) {
      _currentHorizontalPage[index]!.value =
          1; // Switch to carousel ad page - no setState needed!
      AppLogger.log('🎯 Navigated to carousel ad for video $index');
    }
  }

  /// **BUILD FOLLOW TEXT BUTTON: Professional follow/unfollow button**
  Widget _buildFollowTextButton(VideoModel video) {
    // Don't show follow button for own videos
    if (_currentUserId != null && video.uploader.id == _currentUserId) {
      return const SizedBox.shrink();
    }

    final isFollowing = _isFollowing(video.uploader.id);

    return GestureDetector(
      onTap: () => _handleFollow(video),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isFollowing ? Colors.grey[800] : Colors.blue[600],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isFollowing ? Colors.grey[600]! : Colors.blue[600]!,
            width: 1,
          ),
        ),
        child: Text(
          isFollowing ? 'Following' : 'Follow',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
        ),
      ),
    );
  }

  /// **HANDLE FOLLOW/UNFOLLOW: With API integration**
  Future<void> _handleFollow(VideoModel video) async {
    if (_currentUserId == null) {
      // Silent return if not logged in
      return;
    }

    if (video.uploader.id == _currentUserId) {
      // Silent return for self
      return;
    }

    try {
      final isFollowing = _isFollowing(video.uploader.id);

      // Optimistic UI update
      setState(() {
        if (isFollowing) {
          _followingUsers.remove(video.uploader.id);
        } else {
          _followingUsers.add(video.uploader.id);
        }
      });

      // Call API using UserService
      final userService = UserService();
      if (isFollowing) {
        await userService.unfollowUser(video.uploader.id);
      } else {
        await userService.followUser(video.uploader.id);
      }
    } catch (e) {
      AppLogger.log('❌ Error handling follow/unfollow: $e');

      // Revert optimistic update on error
      setState(() {
        final isFollowing = _isFollowing(video.uploader.id);
        if (isFollowing) {
          _followingUsers.remove(video.uploader.id);
        } else {
          _followingUsers.add(video.uploader.id);
        }
      });

      // Silent on error per requirement
    }
  }

  /// **CHECK IF USER IS FOLLOWING**
  bool _isFollowing(String userId) {
    return _followingUsers.contains(userId);
  }

  /// **CHECK IF VIDEO IS LIKED**
  /// **SIMPLIFIED: Just check if currentUserId is in likedBy array**
  bool _isLiked(VideoModel video) {
    return _currentUserId != null && video.likedBy.contains(_currentUserId);
  }

  /// **NAVIGATE TO CREATOR PROFILE: Navigate to user profile screen**
  void _navigateToCreatorProfile(VideoModel video) {
    final candidateIds = <String>[
      if (video.uploader.googleId != null) video.uploader.googleId!.trim(),
      if (video.uploader.id.isNotEmpty) video.uploader.id.trim(),
    ]
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty && id.toLowerCase() != 'unknown')
        .toList();

    AppLogger.log('🔗 Creator profile candidate IDs: $candidateIds');

    final targetUserId = candidateIds.isNotEmpty ? candidateIds.first : '';

    if (targetUserId.isEmpty) {
      _showSnackBar('User profile not available', isError: true);
      return;
    }

    AppLogger.log('🔗 Navigating to creator profile: $targetUserId');
    _pauseVideosForProfileNavigation();

    // Navigate to profile screen
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProfileScreen(userId: targetUserId),
      ),
    ).catchError((error) {
      AppLogger.log('❌ Error navigating to profile: $error');
      _showSnackBar('Failed to open profile', isError: true);
      return null; // Return null to satisfy the return type
    });
  }

  /// **TEST API CONNECTION: Test if the API is reachable**
  Future<void> _testApiConnection() async {
    try {
      AppLogger.log('🔍 VideoFeedAdvanced: Testing API connection...');

      // Show loading state
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
                SizedBox(width: 12),
                Text('Testing connection...'),
              ],
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }

      // Try to make a simple API call
      await _videoService.getVideos(page: 1, limit: 1);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 8),
                Text('Connection successful!'),
              ],
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Clear error and try to refresh
        setState(() {
          _errorMessage = null;
        });
        await refreshVideos();
      }
    } catch (e) {
      AppLogger.log('❌ VideoFeedAdvanced: API connection test failed: $e');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Connection failed: ${_getUserFriendlyErrorMessage(e)}',
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin

    return Consumer<GoogleSignInController>(
      builder: (context, authController, _) {
        final bool isSignedIn = authController.isSignedIn;
        if (isSignedIn != _wasSignedIn) {
          _wasSignedIn = isSignedIn;
          if (isSignedIn) {
            _pendingAutoplayAfterLogin = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                _scheduleAutoplayAfterLogin();
              }
            });
          } else {
            _pendingAutoplayAfterLogin = false;
          }
        }

        // **FIXED: Listen to auth state changes and update user ID**
        // **FIX: Prioritize googleId over id to match backend likedBy array**
        if (isSignedIn && authController.userData != null) {
          final userId = authController.userData!['googleId'] ??
              authController.userData!['id'];
          if (userId != null && _currentUserId != userId) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() {
                  _currentUserId = userId;
                });
                AppLogger.log(
                  '✅ VideoFeedAdvanced: User ID synced from auth: $userId',
                );
              }
            });
          }
        } else if (!isSignedIn && _currentUserId != null) {
          // User signed out - clear user ID
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _currentUserId = null;
              });
              AppLogger.log(
                '✅ VideoFeedAdvanced: User ID cleared (signed out)',
              );
            }
          });
        }

        return Consumer<MainController>(
          builder: (context, mainController, child) {
            final isVideoTabActive = mainController.currentIndex == 0;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              _handleVisibilityChange(isVideoTabActive);
            });

            // #region agent log
            _debugLog(
                'video_feed_advanced.dart:2207',
                'UI build condition check',
                {
                  'isLoading': _isLoading,
                  'errorMessage': _errorMessage,
                  'videosLength': _videos.length,
                  'willShowEmpty':
                      !_isLoading && _errorMessage == null && _videos.isEmpty,
                },
                'E');
            // #endregion

            return Scaffold(
              backgroundColor: Colors.black,
              body: Stack(
                children: [
                  _isLoading
                      ? Center(child: _buildGreenSpinner(size: 40))
                      : _errorMessage != null
                          ? _buildErrorState()
                          : _videos.isEmpty
                              ? _buildEmptyState()
                              : _buildVideoFeed(),
                  // **OFFLINE INDICATOR: Show when no internet connection**
                  _buildOfflineIndicator(),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  void dispose() {
    // **CRITICAL: Unregister callbacks from MainController**
    try {
      _mainController?.unregisterCallbacks();
      AppLogger.log(
        '📱 VideoFeedAdvanced: Unregistered callbacks from MainController',
      );
    } catch (e) {
      AppLogger.log('⚠️ VideoFeedAdvanced: Error unregistering callbacks: $e');
    }

    // **NEW: Clean up views service**
    _viewTracker.dispose();
    AppLogger.log('🎯 VideoFeedAdvanced: Disposed ViewsService');

    // **NEW: Clean up background profile preloader**
    _profilePreloader.dispose();
    AppLogger.log('🚀 VideoFeedAdvanced: Disposed BackgroundProfilePreloader');

    final sharedPool = SharedVideoControllerPool();
    final bool openedFromProfile = _openedFromProfile;
    int savedControllers = 0;

    // **FIX: Create a copy of the pool to avoid modification during iteration**
    final controllersToDispose =
        Map<int, VideoPlayerController>.from(_controllerPool);

    controllersToDispose.forEach((index, controller) {
      if (index < _videos.length) {
        final video = _videos[index];
        try {
          // **FIX: Remove listeners to avoid memory leaks (once, before branching)**
          controller.removeListener(_bufferingListeners[index] ?? () {});
          controller.removeListener(_videoEndListeners[index] ?? () {});

          if (openedFromProfile) {
            // **PROFILE FLOW: Fully dispose controllers to free decoder resources**
            try {
              if (controller.value.isInitialized) {
                if (controller.value.isPlaying) {
                  controller.pause();
                }
                controller.setVolume(0.0);
              }
            } catch (e) {
              AppLogger.log(
                '⚠️ VideoFeedAdvanced: Error pausing controller before disposal: $e',
              );
            }

            // **FIX: Remove from shared pool first, then dispose**
            try {
              sharedPool.removeController(video.id);
              controller.dispose();
              AppLogger.log(
                '🗑️ VideoFeedAdvanced: Disposed controller for video ${video.id} (profile flow)',
              );
            } catch (e) {
              AppLogger.log(
                '⚠️ VideoFeedAdvanced: Error disposing controller: $e',
              );
            }
          } else {
            // **TAB FLOW: Preserve controller in shared pool for quick resume**
            final wasPlaying = _controllerStates[index] == true &&
                !(_userPaused[index] ?? false);
            _wasPlayingBeforeNavigation[index] = wasPlaying;
            AppLogger.log(
              '💾 VideoFeedAdvanced: Video ${video.id} was ${wasPlaying ? "playing" : "paused"} before navigation',
            );

            if (wasPlaying &&
                controller.value.isInitialized &&
                controller.value.isPlaying) {
              controller.pause();
              _controllerStates[index] = false;
              AppLogger.log(
                '⏸️ VideoFeedAdvanced: Paused video ${video.id} before saving to shared pool',
              );
            }

            sharedPool.addController(video.id, controller,
                skipDisposeOld: true);
            savedControllers++;
            AppLogger.log(
              '💾 VideoFeedAdvanced: Saved controller for video ${video.id} to shared pool',
            );
          }
        } catch (e) {
          AppLogger.log('⚠️ Error saving controller for video ${video.id}: $e');
          try {
            controller.dispose();
          } catch (_) {}
        }
      } else {
        // Dispose orphaned controllers (no corresponding video)
        try {
          controller.dispose();
        } catch (_) {}
      }
    });

    AppLogger.log(
      '💾 VideoFeedAdvanced: Saved $savedControllers controllers to shared pool',
    );

    // **MEMORY MANAGEMENT: Aggressively clean up when opened from ProfileScreen**
    if (openedFromProfile) {
      AppLogger.log(
        '🧹 VideoFeedAdvanced: Cleaning up shared pool for profile flow (disposing all controllers)',
      );
      // **FIX: Dispose all controllers in shared pool when opened from ProfileScreen**
      // This prevents accumulation of controllers when quickly switching between videos
      sharedPool.clearAll();
    } else if (savedControllers > 2) {
      AppLogger.log(
        '🧹 VideoFeedAdvanced: Triggering memory management (keeping only 2 controllers)',
      );
      sharedPool.disposeControllersForMemoryManagement();
    }

    // Clear local pools but controllers remain in shared pool for reuse
    _controllerPool.clear();
    _controllerStates.clear();
    _isBuffering.clear();
    _bufferingListeners.clear();
    _videoEndListeners.clear();
    _wasPlayingBeforeNavigation.clear();
    _loadingVideos.clear();
    _initializingVideos.clear();
    _preloadRetryCount.clear();
    _preloadedVideos.clear();
    // Dispose ValueNotifiers
    for (final notifier in _firstFrameReady.values) {
      notifier.dispose();
    }
    _firstFrameReady.clear();
    for (final notifier in _forceMountPlayer.values) {
      notifier.dispose();
    }
    _forceMountPlayer.clear();
    for (final notifier in _showHeartAnimation.values) {
      notifier.dispose();
    }
    _showHeartAnimation.clear();

    // **NEW: Dispose VideoControllerManager**
    _videoControllerManager.dispose();
    AppLogger.log('🗑️ VideoFeedAdvanced: Disposed VideoControllerManager');

    // Dispose page controller
    _pageController.dispose();

    // Cancel timers
    _preloadTimer?.cancel();
    _pageChangeTimer?.cancel();
    _preloadDebounceTimer?.cancel();

    // **NEW: Cancel ad refresh subscription**
    _adRefreshSubscription?.cancel();

    // Remove observer
    WidgetsBinding.instance.removeObserver(this);

    _disableWakelock();
    super.dispose();
  }

  /// **PRINT CACHE STATUS: Real-time cache information**
  void _printCacheStatus() {
    if (_totalRequests > 0) {
      final hitRate = (_cacheHits / _totalRequests * 100).toStringAsFixed(2);
      AppLogger.log('   Hit Rate: $hitRate%');
    }
  }

  /// **GET DETAILED CACHE INFO: Comprehensive cache information**
  Map<String, dynamic> _getDetailedCacheInfo() {
    final cacheStats = _cacheManager.getStats();

    return {
      'videoControllerPool': {
        'totalControllers': _controllerPool.length,
        'controllerKeys': _controllerPool.keys.toList(),
        'controllerStates': _controllerStates,
        'preloadedVideos': _preloadedVideos.toList(),
        'loadingVideos': _loadingVideos.toList(),
      },
      'cacheStatistics': {
        'cacheHits': _cacheHits,
        'cacheMisses': _cacheMisses,
        'preloadHits': _preloadHits,
        'totalRequests': _totalRequests,
        'hitRate': _totalRequests > 0
            ? (_cacheHits / _totalRequests * 100).toStringAsFixed(2)
            : '0.00',
      },
      'smartCacheManager': cacheStats,
      'videoLoadingStatus': {
        'currentIndex': _currentIndex,
        'totalVideos': _videos.length,
        'maxPoolSize': _maxPoolSize,
        'isLoading': _isLoading,
        'isScreenVisible': _isScreenVisible,
      },
      'memoryUsage': {
        'controllerPoolSize': _controllerPool.length,
        'preloadedVideosCount': _preloadedVideos.length,
        'loadingVideosCount': _loadingVideos.length,
      },
    };
  }

  /// **PRINT DETAILED CACHE INFO: For debugging purposes**
  void _printDetailedCacheInfo() {
    final info = _getDetailedCacheInfo();

    final poolInfo = info['videoControllerPool'] as Map<String, dynamic>;
    poolInfo.forEach((key, value) {
      AppLogger.log('   $key: $value');
    });

    AppLogger.log('📈 Cache Statistics:');
    final statsInfo = info['cacheStatistics'] as Map<String, dynamic>;
    statsInfo.forEach((key, value) {
      AppLogger.log('   $key: $value');
    });

    AppLogger.log('🧠 Smart Cache Manager:');
    final smartCacheInfo = info['smartCacheManager'] as Map<String, dynamic>;
    smartCacheInfo.forEach((key, value) {
      AppLogger.log('   $key: $value');
    });

    AppLogger.log('🎥 Video Loading Status:');
    final loadingInfo = info['videoLoadingStatus'] as Map<String, dynamic>;
    loadingInfo.forEach((key, value) {
      AppLogger.log('   $key: $value');
    });

    AppLogger.log('💾 Memory Usage:');
    final memoryInfo = info['memoryUsage'] as Map<String, dynamic>;
    memoryInfo.forEach((key, value) {
      AppLogger.log('   $key: $value');
    });

    AppLogger.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  }

  /// **MANUAL CACHE STATUS CHECK: Call this method to check cache status**
  void checkCacheStatus() {
    AppLogger.log('🔍 Manual Cache Status Check Triggered');
    _printDetailedCacheInfo();
  }

  /// **GET CACHE SUMMARY: Quick cache overview**
  Map<String, dynamic> getCacheSummary() {
    return {
      'totalVideos': _videos.length,
      'preloadedVideos': _preloadedVideos.length,
      'loadingVideos': _loadingVideos.length,
      'controllerPoolSize': _controllerPool.length,
      'cacheHits': _cacheHits,
      'cacheMisses': _cacheMisses,
      'hitRate': _totalRequests > 0
          ? (_cacheHits / _totalRequests * 100).toStringAsFixed(2)
          : '0.00',
      'currentIndex': _currentIndex,
      'isLoading': _isLoading,
    };
  }
}

/// **THROTTLED PROGRESS BAR: Updates at 30fps instead of every frame**
/// This prevents CPU/GPU waste by limiting UI updates to 30fps (33ms intervals)
class _ThrottledProgressBar extends StatefulWidget {
  final VideoPlayerController controller;
  final double screenWidth;
  final Function(dynamic) onSeek;

  const _ThrottledProgressBar({
    required this.controller,
    required this.screenWidth,
    required this.onSeek,
  });

  @override
  State<_ThrottledProgressBar> createState() => _ThrottledProgressBarState();
}

class _ThrottledProgressBarState extends State<_ThrottledProgressBar> {
  double _progress = 0.0;
  Timer? _updateTimer;
  DateTime _lastUpdate = DateTime.now();
  static const Duration _updateInterval = Duration(milliseconds: 33); // ~30fps

  @override
  void initState() {
    super.initState();
    _updateProgress();
    // Listen to controller changes but throttle updates
    widget.controller.addListener(_onControllerUpdate);
  }

  @override
  void dispose() {
    _updateTimer?.cancel();
    widget.controller.removeListener(_onControllerUpdate);
    super.dispose();
  }

  void _onControllerUpdate() {
    final now = DateTime.now();
    final timeSinceLastUpdate = now.difference(_lastUpdate);

    // Only update if enough time has passed (throttle to 30fps)
    if (timeSinceLastUpdate >= _updateInterval) {
      _updateProgress();
      _lastUpdate = now;
    } else {
      // Schedule update for the remaining time
      _updateTimer?.cancel();
      final remainingTime = _updateInterval - timeSinceLastUpdate;
      _updateTimer = Timer(remainingTime, () {
        if (mounted) {
          _updateProgress();
          _lastUpdate = DateTime.now();
        }
      });
    }
  }

  void _updateProgress() {
    if (!mounted || !widget.controller.value.isInitialized) return;

    final duration = widget.controller.value.duration;
    final position = widget.controller.value.position;
    final totalMs = duration.inMilliseconds;
    final posMs = position.inMilliseconds;
    final newProgress = totalMs > 0 ? (posMs / totalMs).clamp(0.0, 1.0) : 0.0;

    if ((newProgress - _progress).abs() > 0.001) {
      // Only update if progress changed significantly (0.1% threshold)
      setState(() {
        _progress = newProgress;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onSeek,
      onPanUpdate: widget.onSeek,
      child: Container(
        height: 4,
        color: Colors.black.withOpacity(0.2),
        child: Stack(
          children: [
            Container(
              height: 2,
              margin: const EdgeInsets.only(top: 1),
              color: Colors.grey.withOpacity(0.2),
            ),
            // Progress bar filled portion
            Positioned(
              top: 1,
              left: 0,
              child: Container(
                height: 2,
                width: widget.screenWidth * _progress,
                color: Colors.green[400],
              ),
            ),
            // Seek handle (thumb)
            if (_progress > 0)
              Positioned(
                top: 0,
                left: (widget.screenWidth * _progress) - 4,
                child: Container(
                  width: 8,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.green[400],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
