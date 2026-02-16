import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:vayu/features/video/video_model.dart';
import 'package:vayu/features/video/data/services/video_service.dart';
import 'package:vayu/features/auth/data/services/authservices.dart';
import 'package:vayu/features/profile/data/services/user_service.dart';
import 'package:vayu/shared/managers/carousel_ad_manager.dart';
import 'package:like_button/like_button.dart';
import 'package:vayu/shared/constants/app_constants.dart';
import 'package:vayu/shared/theme/app_theme.dart';

import 'package:vayu/features/ads/data/services/active_ads_service.dart';
import 'package:vayu/features/video/data/services/video_view_tracker.dart';
import 'package:vayu/features/ads/data/services/ad_refresh_notifier.dart';
import 'package:vayu/features/profile/data/services/background_profile_preloader.dart';

import 'package:vayu/features/ads/data/services/ad_impression_service.dart';
import 'package:vayu/features/ads/presentation/widgets/carousel_ad_widget.dart';
import 'package:vayu/features/video/presentation/screens/video_feed_advanced/widgets/banner_ad_section.dart';
import 'package:vayu/features/video/presentation/screens/video_feed_advanced/widgets/heart_animation.dart';
import 'package:vayu/shared/services/connectivity_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:vayu/shared/config/app_config.dart';
import 'package:vayu/features/profile/presentation/screens/profile_screen.dart';
import 'package:vayu/features/auth/presentation/screens/login_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayu/features/video/presentation/managers/main_controller.dart';
import 'package:vayu/features/video/presentation/managers/video_controller_manager.dart';
import 'package:vayu/features/video/presentation/managers/shared_video_controller_pool.dart';
import 'package:vayu/shared/widgets/report_dialog_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayu/shared/widgets/custom_share_widget.dart';
import 'video_feed_advanced/widgets/throttled_progress_bar.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/features/auth/presentation/controllers/google_sign_in_controller.dart';
import 'package:vayu/features/onboarding/presentation/managers/app_initialization_manager.dart';



import 'package:vayu/features/video/presentation/widgets/video_feed_skeleton.dart';

import 'package:vayu/features/video/data/services/video_cache_proxy_service.dart';
import 'package:vayu/shared/services/local_gallery_service.dart';

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
  // **OPTIMIZATION: Disabled filesystem logging in debug mode to prevent UI hangs**
  return;
}
// #endregion



class VideoFeedAdvanced extends StatefulWidget {
  final int? initialIndex;
  final List<VideoModel>? initialVideos;
  final String? initialVideoId;
  final String? videoType;
  final bool isFullScreen; // **NEW: Flag for full-screen mode**
  // Removed forceAutoplay; we'll infer autoplay from initialVideos presence

  const VideoFeedAdvanced({
    Key? key,
    this.initialIndex,
    this.initialVideos,
    this.initialVideoId,
    this.videoType, // **NEW: Accept videoType parameter**
    this.isFullScreen = false, // Default to false
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
  Timer? _pageChangeDebounceTimer; // **NEW: Timer for debouncing page rapid scrolls**

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
    _checkDeviceCapabilities();
  }

  /// **Helper to allow extensions to call setState safely**
  void safeSetState(VoidCallback fn) {
    if (mounted) {
      setState(fn);
    }
  }

  /// **Helper to get or create a ValueNotifier in a map without replacing the object**
  ValueNotifier<T> _getOrCreateNotifier<T>(
    Map<String, ValueNotifier<T>> map,
    String key,
    T initialValue,
  ) {
    if (map.containsKey(key)) {
      return map[key]!;
    } else {
      final notifier = ValueNotifier<T>(initialValue);
      map[key] = notifier;
      return notifier;
    }
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

        // **FIX: Removed arbitrary 30-minute forced refresh**
        // Let the OS manage memory. If app is still alive, resume where we left off.
        // If OS killed it, proper state restoration (coming next) will handle it.
        _lastPausedAt = null; // Clear after use

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
    // **NEW: Background Buffering Strategy**
    // Trigger independent download of CURRENT video so it's ready when we return.
    if (_currentIndex < _videos.length) {
       final url = _videos[_currentIndex].videoUrl;
       // Fire and forget - this runs in background (IO thread)
       // We use 10MB to ensure we have a healthy buffer on resume
       videoCacheProxy.prefetchChunk(url, megabytes: 10).catchError((_) {});
    }

    _saveBackgroundState();
    _pauseAllVideosOnTabSwitch();
    _videoControllerManager.pauseAllVideos();
    _videoControllerManager.onAppPaused();
    SharedVideoControllerPool().pauseAllControllers();
    _lifecyclePaused = true;
    _pendingAutoplayAfterLogin = false;
    _ensureWakelockForVisibility();
    AppLogger.log(
      '📱 VideoFeedAdvanced: Lifecycle state $state triggered background handling; current video buffering initiated.',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // **PERFORMANCE: Cache MainController to avoid repeated Provider.of() calls**
    _mainController = Provider.of<MainController>(context, listen: false);
    
    // **NEW: Register pause callback with MainController**
    _mainController?.registerVideoPauseCallback(_pauseCurrentVideo);

    // **PERFORMANCE: Cache MediaQuery data to avoid repeated lookups**
    final mediaQuery = MediaQuery.of(context);
    _screenWidth = mediaQuery.size.width;

    // **FIXED: Listen to auth state changes from GoogleSignInController**
    final authController = Provider.of<GoogleSignInController>(
      context,
      listen: false,
    );
    
    // **FIX: Only clear ID if definitely signed out AND not loading**
    // This prevents clearing the ID during the brief initialization phase
    if (!authController.isSignedIn && !authController.isLoading && _currentUserId != null) {
      // User signed out - clear current user ID
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _currentUserId = null;
          });
          // **FIX: Update all like notifiers when user signs out**
          for (final video in _videos) {
            if (_isLikedVN.containsKey(video.id)) {
              _isLikedVN[video.id]!.value = false;
            }
          }
          AppLogger.log('✅ VideoFeedAdvanced: User ID cleared (verified signed out)');
        }
      });
    }

    if (authController.isSignedIn && authController.userData != null) {
       final userId = authController.userData!['googleId'] ?? authController.userData!['id'];
       final userObjectId = authController.userData!['_id'] ?? authController.userData!['id'];
       
       if (userId != null && (_currentUserId != userId || _currentUserObjectId != userObjectId)) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
             if (mounted) {
                setState(() {
                   _currentUserId = userId;
                   _currentUserObjectId = userObjectId?.toString();
                });
                
                AppLogger.log('👤 VideoFeedAdvanced: Current User IDs synchronized:');
                AppLogger.log('   - Google ID: $_currentUserId');
                AppLogger.log('   - Object ID: $_currentUserObjectId');

                // **FIX: Update all like notifiers based on isLiked status**
                for (final video in _videos) {
                   if (_isLikedVN.containsKey(video.id)) {
                      _isLikedVN[video.id]!.value = video.isLiked;
                   }
                }
             }
          });
       }
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
        /* AppLogger.log(
          '✅ VideoFeedAdvanced: Yug tab active - setting _isScreenVisible = true',
        ); */
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
                // No delay - autoplay checks controller readiness
                _tryAutoplayCurrent();
              }
            });
          } else {
            _tryAutoplayCurrent();
          }
        }
      }
    });
  }

  void _tryAutoplayCurrent() {
    if (_videos.isEmpty || _isLoading) return;
    if (!_shouldAutoplayForContext('tryAutoplayCurrent')) return;
    _autoAdvancedForIndex.remove(_currentIndex);

    // Check if current video is preloaded
    final video = _videos[_currentIndex];
    final controller = _controllerPool[video.id];

    if (controller != null && controller.value.isInitialized) {
      if (controller.value.isPlaying) {
        return;
      }

      if (_userPaused[video.id] == true) {
        /* AppLogger.log(
          '⏸️ Autoplay suppressed: user has manually paused video at index $_currentIndex',
        ); */
        return;
      }

      try {
        controller.setVolume(1.0);
      } catch (_) {}
      if (!_shouldAutoplayForContext('autoplay current immediate')) return;
      _pauseAllOtherVideos(_videos[_currentIndex].id);
      controller.play();
      _ensureWakelockForVisibility();
      _controllerStates[video.id] = true;
      _userPaused[video.id] = false;
      _pendingAutoplayAfterLogin = false;

      // **NEW: Start view tracking with videoHash**
      if (_currentIndex < _videos.length) {
        final currentVideo = _videos[_currentIndex];
        _viewTracker.startViewTracking(
          currentVideo.id,
          videoUploaderId: currentVideo.uploader.id,
          videoHash: currentVideo.videoHash,
        );
      }

      // AppLogger.log('✅ VideoFeedAdvanced: Current video autoplay started');
    } else {
      // Video not preloaded, preload it and play when ready
      /* AppLogger.log(
        '🔄 VideoFeedAdvanced: Current video not preloaded, preloading...',
      ); */
      final indexToPlay = _currentIndex;
      final videoToPlay = _videos[indexToPlay];
      _preloadVideo(indexToPlay).then((_) {
        if (mounted && _currentIndex == indexToPlay && _controllerPool.containsKey(videoToPlay.id)) {
          final pController = _controllerPool[videoToPlay.id];
          if (pController != null && pController.value.isInitialized) {
            // **FIX: Don't autoplay if user has manually paused the video**
            if (_userPaused[videoToPlay.id] == true) {
              AppLogger.log(
                '⏸️ Autoplay suppressed after preload: user has manually paused video at index $indexToPlay',
              );
              return;
            }
            if (!_shouldAutoplayForContext('autoplay current after preload')) {
              return;
            }

            try {
              pController.setVolume(1.0);
            } catch (_) {}
            _pauseAllOtherVideos(_videos[indexToPlay].id);
            pController.play();
            _ensureWakelockForVisibility();
            _controllerStates[videoToPlay.id] = true;
            _userPaused[videoToPlay.id] = false;
            _pendingAutoplayAfterLogin = false;

            // **NEW: Start view tracking with videoHash**
            if (indexToPlay < _videos.length) {
              final currentVideo = _videos[indexToPlay];
              _viewTracker.startViewTracking(
                currentVideo.id,
                videoUploaderId: currentVideo.uploader.id,
                videoHash: currentVideo.videoHash,
              );
            }

            /* AppLogger.log(
              '✅ VideoFeedAdvanced: Current video autoplay started after preloading',
            ); */
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
          final video = _videos[_currentIndex];
          final controller = _controllerPool[video.id];
          if (controller != null && controller.value.isInitialized) {
            _firstFrameReady[video.id]?.value = true;
          }
        }

        // 2) Pause all other videos to avoid audio overlap
        _pauseAllVideosOnTabSwitch();
        _isScreenVisible =
            true; // set visible again after pause helper sets false
        _ensureWakelockForVisibility();

        // 3) Autoplay the current video
        /* AppLogger.log(
          '▶️ VideoFeedAdvanced: Yug tab visible - trying autoplay',
        ); */
        _tryAutoplayCurrent();

        // 4) Start background profile preloading
        _profilePreloader.startBackgroundPreloading();
      } else {
        // Screen became hidden - pause current video
        _pauseCurrentVideo();

        // **BANDWIDTH FIX: Cancel all prefetches to prioritize Profile screen**
        videoCacheProxy.cancelAllPrefetches();

        // **NEW: Stop background profile preloading**
        _profilePreloader.stopBackgroundPreloading();
        _ensureWakelockForVisibility();
      }
    }
    
    // **NEW: RE-INITIALIZATION CHECK**
    // When becoming visible, validate controllers to ensure they weren't disposed externally
    if (isVisible) {
      _validateAndRestoreControllers();
    }
  }

  /// **NEW: Validate and restore disposed controllers**
  void _validateAndRestoreControllers() {
    if (_videos.isEmpty) return;
    
    final sharedPool = SharedVideoControllerPool();
    final List<int> indicesToRestore = [];
    
    // Check current and adjacent videos (priority range)
    final indicesToCheck = {
      _currentIndex, 
      if (_currentIndex + 1 < _videos.length) _currentIndex + 1,
      if (_currentIndex - 1 >= 0) _currentIndex - 1
    };
    
    for (final index in indicesToCheck) {
      final video = _videos[index];
      bool needsRestore = false;
      
      // Check local pool
      if (_controllerPool.containsKey(video.id)) {
        final controller = _controllerPool[video.id];
        if (sharedPool.isControllerDisposed(controller)) {
           AppLogger.log('⚠️ VideoFeedAdvanced: Controller for ${video.id} is DISPOSED (local). Marking for restore.');
           _controllerPool.remove(video.id);
           _controllerStates.remove(video.id);
           needsRestore = true;
        }
      } else {
        // Not in local pool - if it's the CURRENT video, we definitely need it
        if (index == _currentIndex) {
           needsRestore = true;
        }
      }
      
      if (needsRestore) {
        indicesToRestore.add(index);
      }
    }
    
    // Restore identified videos
    for (final index in indicesToRestore) {
         // Only log if index matches current to avoid noise
         if (index == _currentIndex) {
           AppLogger.log('🔄 VideoFeedAdvanced: Restoring controller for index $index (Current Video)');
         }
         
      _preloadVideo(index).then((_) {
         if (mounted && index == _currentIndex && _isScreenVisible) {
            // If we restored the current video and screen is visible, try playing
            _tryAutoplayCurrent();
         }
      });
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
      /* AppLogger.log(
        '✅ Autoplay allowed ($context): ${_openedFromProfile ? "opened from profile" : "opened from deep link"}',
      ); */
      return true;
    }
    final bool isVideoTabActive =
        (_mainController?.currentIndex ?? 0) == 0 && _isScreenVisible;
    if (!isVideoTabActive) {
      /* AppLogger.log(
        '⏸️ Autoplay suppressed ($context): Yug tab not active or screen hidden',
      ); */
      return false;
    }
    return true;
  }

  void _scheduleAutoplayAfterLogin() {
    if (!_pendingAutoplayAfterLogin) return;

    // Use postFrameCallback instead of delay for faster autoplay
    WidgetsBinding.instance.addPostFrameCallback((_) {
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
    // **FIX: Extra safeguard - check actual system lifecycle state**
    if (WidgetsBinding.instance.lifecycleState != null && 
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      AppLogger.log('⏸️ Autoplay blocked ($context): System state is ${WidgetsBinding.instance.lifecycleState}');
      return false;
    }
    return true;
  }



  /// **NEW: Pause videos before navigating away (e.g., to creator profile)**
  void _pauseVideosForProfileNavigation() {
    try {
      AppLogger.log(
          '⏸️ VideoFeedAdvanced: Pausing current video before navigation');
      
      // **CRITICAL FIX: Explicitly mark as user paused to prevent race condition autoplay**
      // If video is still loading, this flag ensures it won't autoplay when ready.
      // **OPTIMIZED: Use ValueNotifier for granular updates - NO setState**
       final video = _videos[_currentIndex];
       _userPaused[video.id] = true;
       _userPausedVN[video.id]?.value = true;
       _controllerStates[video.id] = false;
      
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

  // Duplicate methods removed to use video_feed_advanced_preload.dart implementation


  /// **GET OR CREATE CONTROLLER: Unified shared pool strategy**
  VideoPlayerController? _getController(int index) {
    if (index >= _videos.length) return null;

    final video = _videos[index];
    final sharedPool = SharedVideoControllerPool();

    // **PRIMARY: Check shared pool first (guaranteed instant playback)**
    VideoPlayerController? controller;
    
    try {
      controller = sharedPool.getControllerForInstantPlay(video.id);

      if (controller != null && controller.value.isInitialized) {
        // **CACHE HIT: Reuse from shared pool**
        AppLogger.log(
          '⚡ INSTANT: Reusing controller from shared pool for video ${video.id}',
        );

        // Add to local pool for UI tracking only
        _controllerPool[video.id] = controller;
        _controllerStates[video.id] = false;
        _preloadedVideos.add(video.id);
        _lastAccessedLocal[video.id] = DateTime.now();

        // **FIX: Explicitly set value to true since _getOrCreateNotifier no longer resets**
        _getOrCreateNotifier<bool>(_firstFrameReady, video.id, true).value = true;

        return controller;
      }
    } catch (e) {
      AppLogger.log('⚠️ VideoFeedAdvanced: Disposed controller detected in shared pool for ${video.id}');
      sharedPool.removeController(video.id);
      controller = null; 
    }

    // **FALLBACK: Check local pool**
    if (_controllerPool.containsKey(video.id)) {
      try {
        controller = _controllerPool[video.id];
        if (controller != null && controller.value.isInitialized) {
          _lastAccessedLocal[video.id] = DateTime.now();
          // **FIX: Explicitly set value to true since _getOrCreateNotifier no longer resets**
          _getOrCreateNotifier<bool>(_firstFrameReady, video.id, true).value = true;
          return controller;
        }
      } catch (e) {
        AppLogger.log('⚠️ VideoFeedAdvanced: Disposed controller detected in local pool at index $index');
        _controllerPool.remove(video.id);
        _controllerStates.remove(video.id); // Also remove from _controllerStates
        controller = null;
      }
    }

    // **PRELOAD: If not in any pool, preload it**
    // **FIX: Removed explicit preload to prevent 'fire hose' during fast scroll.**
    // _preloadVideo(index) is now handled exclusively by _handlePageChange (debounced).
    // _preloadVideo(index);
    return null;
  }

  /// **HANDLE PAGE CHANGES** - Debounced for fast scrolling
  void _onPageChanged(int index) {
    if (index == _currentIndex) return;

    // **NEW: Scroll Velocity Detection**
    final currentTime = DateTime.now();
    final scrollDelta = currentTime.difference(_lastPageChangeTime).inMilliseconds;
    _lastPageChangeTime = currentTime;
    final bool isFastScroll = scrollDelta < 300; // Threshold for "Ruthless" mode
    _wasLastScrollFast = isFastScroll; // Store for preloader to use

    // **NEW: INSTANT RESOURCE PROTECTION (The "Cut Cable" Logic)**
    // As soon as the user scrolls, we:
    // 1. Identify "Safe" videos (Current Target)
    // 2. Kill network for EVERYTHING else immediately.
    // This prevents "Zombie Downloads" from eating bandwidth.
    if (_currentIndex < _videos.length) {
      // Build Safe List (URLs we MUST NOT cancel)
      final List<String> safeUrls = [];
      
      // Helper to add all variants of a video (HLS & MP4) to be safe
      void addSafeVideo(VideoModel v) {
         if (v.hlsPlaylistUrl?.isNotEmpty == true) safeUrls.add(v.hlsPlaylistUrl!);
         if (v.hlsMasterPlaylistUrl?.isNotEmpty == true) safeUrls.add(v.hlsMasterPlaylistUrl!);
         if (v.videoUrl.isNotEmpty) safeUrls.add(v.videoUrl);
      }

      // 1. Current (Target) Video - ALWAYS SAFE
      if (index < _videos.length) addSafeVideo(_videos[index]);
      
      // 2. Next Video - ONLY SAFE if NOT scrolling fast
      // Agar user fast scroll kar raha hai toh hum next video ka bandwidth bhi current video ko de denge.
      if (!isFastScroll && index + 1 < _videos.length) {
          addSafeVideo(_videos[index + 1]);
      }
      
      // **IMMEDIATE PRIORITY SHIFT: YouTube Shorts Style**
      // The moment the finger swipes, we must signal an Instant Cancellation 
      // of all pending loads and stop any video that is not the one currently visible.
      _cancelIrrelevantPreloads(index);
      
      // **EXECUTE ATOMIC CANCELLATION**
      // This is Microsecond-level latency (local check) vs Second-level savings (network).
      videoCacheProxy.cancelAllStreamingExcept(safeUrls);
    }


    // 1. Pause current local controller if active
    if (_currentIndex < _videos.length) {
      final currentVideoId = _videos[_currentIndex].id;
      for (final id in _controllerPool.keys.toList()) {
        if (id != currentVideoId) {
          final controller = _controllerPool[id];
          if (controller != null &&
              controller.value.isInitialized &&
              controller.value.isPlaying) {
            controller.pause();
            _controllerStates[id] = false;
          }
        }
      }
      
      // 2. Pause shared controller if active (redundancy check)
      final video = _videos[_currentIndex];
      final sharedPool = SharedVideoControllerPool();
      if (sharedPool.hasController(video.id)) {
        final ctrl = sharedPool.getController(video.id);
        if (ctrl != null && ctrl.value.isPlaying) {
          ctrl.pause();
        }
      }
    }

    // **CRITICAL FIX: Removed synchronous _loadMoreVideos trigger**
    // It is already handled in _handlePageChange (debounced) and _buildFeedItem (UI builder).
    // Removing it here prevents API spam during fast scrolling.

    // **FIX: Fast Scroll Debounce Logic**
    // If user is scrolling fast, cancel previous timer and restart
    // This prevents "Fire Hose" effect of loading every skipped video
    _pageChangeDebounceTimer?.cancel();
    _pageChangeDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted && index == _currentIndex) { // Ensure index is still valid
         _handlePageChange(index);
      }
    });

    // But we DO NOT trigger heavy video loading yet.
    if (_currentIndex != index) {
      safeSetState(() {
        _currentIndex = index;
      });
    }
  }

  /// **CANCELLATION HELPER: Discard work for videos the user skipped**
  void _cancelIrrelevantPreloads(int currentIndex) {
    // 1. Cancel all debounce timers except for the one we might be about to start
    _preloadDebounceTimers.forEach((videoId, timer) {
      // If videoId doesn't belong to index or index±1, kill it
      bool isRelevant = false;
      for (int i = currentIndex - 1; i <= currentIndex + 1; i++) {
        if (i >= 0 && i < _videos.length && _videos[i].id == videoId) {
          isRelevant = true;
          break;
        }
      }
      if (!isRelevant) {
        timer.cancel();
      }
    });

    // 2. Clear loading/initializing flags for far-away videos
    // This allows Relevancy Checkpoints in _preloadVideo to trigger correctly
    _loadingVideos.removeWhere((videoId) {
      bool isRelevant = false;
      for (int i = currentIndex - 1; i <= currentIndex + 1; i++) {
        if (i >= 0 && i < _videos.length && _videos[i].id == videoId) {
          isRelevant = true;
          break;
        }
      }
      return !isRelevant;
    });

    // 3. Ruthless Disposal: Kill controllers that are definitely not needed
    // This frees hardware decoders instantly during fast scroll
    final sharedPool = SharedVideoControllerPool();
    sharedPool.cleanupDistantControllers(currentIndex, keepRange: 1);
  }

  /// **PAGE CHANGE HANDLER**
  void _handlePageChange(int index) {
    if (!mounted) return;

    // **LRU: Track access time for previous index**
    if (_currentIndex < _videos.length) {
      final video = _videos[_currentIndex];
      _lastAccessedLocal[video.id] = DateTime.now();
    }

    // **NEW: Stop view tracking for previous video**
    if (_currentIndex < _videos.length) {
      final previousVideo = _videos[_currentIndex];
      _viewTracker.stopViewTracking(previousVideo.id);
      AppLogger.log(
        '⏸️ Stopped view tracking for previous video: ${previousVideo.id}',
      );

      // **NEW: Clear userPaused flag so returning to this video autoplays**
      _userPaused[previousVideo.id] = false;
      _userPausedVN[previousVideo.id]?.value = false; // **Reset VN**
    }

    // **OPTIMIZATION: Single Pass Pause**
    // Use the optimized pause method instead of manually iterating multiple pools.
    _pauseAllOtherVideos(_videos[index].id); // This pauses local pool, shared pool, and manager videos


    // **IMMEDIATE SYNC: Update internal index (moved from _onPageChanged)**
    _currentIndex = index;
    _autoAdvancedForIndex.remove(index);

    // **FIXED: Reset user paused state for the NEW video so it can autoplay**
    if (_currentIndex < _videos.length) {
      final video = _videos[_currentIndex];
      _userPaused[video.id] = false;
      _userPausedVN[video.id]?.value = false; // **Reset VN**
    }

    // **RESUME FEATURE: Save state immediately when user settles on a page**
    // This ensures we can resume even if app crashes or is killed ungracefully
    if (mounted) {
      _saveBackgroundState();
    }

    // **MEMORY MANAGEMENT: Periodic cleanup on page change**
    if (index % 10 == 0 &&
        _videos.length > VideoFeedStateFieldsMixin._videosCleanupThreshold) {
      _cleanupOldVideosFromList();
    }

    _reprimeWindowIfNeeded();

    // **CENTRALIZED PRELOADING STRATEGY (Strict Cleanup)**
    // Uses strict directional logic: 
    // - Down: Keep [n, n+1], Kill [n-1...]
    // - Up: Keep [n-1, n], Kill [n+1...]
    if (mounted) {
       _preloadNearbyVideos();
    }


    // Safety: ensure newly active video's audio is unmuted
    final activeController = _controllerPool[_videos[index].id];
    if (activeController != null && activeController.value.isInitialized) {
      try {
        activeController.setVolume(1.0);
      } catch (_) {}
    }
    // No force-unmute; priming excludes current index.

    // **UNIFIED STRATEGY: Use shared pool as primary source (Instant playback)**
    final sharedPool = SharedVideoControllerPool();
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
        _controllerPool[video.id] = controllerToUse;
        _controllerStates[video.id] = false;
        _preloadedVideos.add(video.id);
        _lastAccessedLocal[video.id] = DateTime.now();

        // **FIX: Use helper to avoid replacing notifier object**
        _getOrCreateNotifier<bool>(_firstFrameReady, video.id, true);

        // **MEMORY MANAGEMENT: Cleanup distant controllers**
        sharedPool.cleanupDistantControllers(index, keepRange: 3);
      } else if (sharedPool.isVideoLoaded(video.id)) {
        // Fallback: Get any available controller
        controllerToUse = sharedPool.getController(video.id);
        if (controllerToUse != null && controllerToUse.value.isInitialized) {
          _controllerPool[video.id] = controllerToUse;
          _controllerStates[video.id] = false;
          _preloadedVideos.add(video.id);
          _lastAccessedLocal[video.id] = DateTime.now();
          // **FIX: Use helper to avoid replacing notifier object**
          _getOrCreateNotifier<bool>(_firstFrameReady, video.id, true);
        }
      }
    }

    // **FALLBACK: Check local pool only if shared pool doesn't have it**
    if (controllerToUse == null && _controllerPool.containsKey(_videos[index].id)) {
      controllerToUse = _controllerPool[_videos[index].id];
      if (controllerToUse != null && !controllerToUse.value.isInitialized) {
        // **AUTO-CLEANUP: Remove invalid controllers**
        AppLogger.log('⚠️ Controller exists but not initialized, disposing...');
        try {
          controllerToUse.dispose();
        } catch (e) {
          AppLogger.log('Error disposing controller: $e');
        }
        _controllerPool.remove(_videos[index].id);
        _controllerStates.remove(_videos[index].id);
        _preloadedVideos.remove(_videos[index].id);
        _lastAccessedLocal.remove(_videos[index].id);
        controllerToUse = null;
      } else if (controllerToUse != null &&
          controllerToUse.value.isInitialized) {
        _lastAccessedLocal[_videos[index].id] = DateTime.now();
        // **FIX: Use helper to avoid replacing notifier object**
        _getOrCreateNotifier<bool>(_firstFrameReady, _videos[index].id, true);
      }
    }

    // **FIXED: Play current video if we have a valid controller**
    if (controllerToUse != null && controllerToUse.value.isInitialized) {
      // Controller is ready; ensure context allows autoplay
      if (!_shouldAutoplayForContext('handlePageChange immediate')) {
        return;
      }

      // (Check removed to force autoplay on scroll)

      // **CRITICAL: Pause ALL other videos before playing current video**
      _pauseAllOtherVideos(_videos[index].id);

      // **FIX: Reset position to start when switching to this video**
      // This ensures previous session or background play doesn't affect new view
      controllerToUse.seekTo(Duration.zero);

      controllerToUse.setVolume(1.0);
      controllerToUse.play();
      _controllerStates[_videos[index].id] = true;
      _userPaused[_videos[index].id] = false;
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
    if (!_controllerPool.containsKey(_videos[index].id)) {
      AppLogger.log(
        '🔄 Video not preloaded, preloading and will autoplay when ready',
      );
      _preloadVideo(index).then((_) {
        if (mounted && _currentIndex == index) {
          forcePlayCurrent();
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
    if (index >= _videos.length) return;
    final video = _videos[index];
    final String videoId = video.id;

    // **FIX: Prevent multiple simultaneous toggles on the same video (race condition fix)**
    if (_togglingVideos.contains(videoId)) {
      AppLogger.log(
        '⚠️ _togglePlayPause: Already toggling video $videoId, ignoring duplicate tap',
      );
      return;
    }
    final controller = _controllerPool[video.id];
    if (controller == null || !controller.value.isInitialized) {
      AppLogger.log(
        '⚠️ _togglePlayPause: Controller not available or not initialized for index $index, preloading...',
      );

      // Preload video and then play it
      _preloadVideo(index).then((_) {
        if (!mounted) return;
        final c = _controllerPool[videoId];
        if (c != null && c.value.isInitialized) {
          try {
            _pauseAllOtherVideos(videoId);
            _autoAdvancedForIndex.remove(index);
            c.play();
            // **OPTIMIZED: Use ValueNotifier - NO setState**
             _controllerStates[videoId] = true;
             _userPaused[videoId] = false;
             _userPausedVN[videoId]?.value = false;

            AppLogger.log(
              '▶️ Successfully played video at index $index after preload',
            );

            // Start view tracking
            if (index < _videos.length) {
              final currentVideo = _videos[index];
              _viewTracker.startViewTracking(
                currentVideo.id,
                videoUploaderId: currentVideo.uploader.id,
              );
              AppLogger.log(
                '▶️ User played video: ${currentVideo.id}, started view tracking',
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
    _togglingVideos.add(videoId);

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
        // **OPTIMIZED: Use ValueNotifier for granular updates - NO setState**
        _controllerStates[videoId] = false;
        _userPaused[videoId] = true;
        _userPausedVN[videoId]?.value = true;

        // Now pause the controller
        controller.pause();
        _ensureWakelockForVisibility();

        AppLogger.log('⏸️ Successfully paused video at index $index');

        // **NEW: Stop view tracking when user pauses**
        if (index < _videos.length) {
          final currentVideo = _videos[index];
          _viewTracker.stopViewTracking(currentVideo.id);
          AppLogger.log(
            '⏸️ User paused video: ${currentVideo.id}, stopped view tracking',
          );
        }
      } catch (e) {
        AppLogger.log('❌ Error pausing video at index $index: $e');
        // **FIX: Remove lock on error**
        _togglingVideos.remove(videoId);
        return;
      }
    } else {
      // **FIX: Video is paused, so play it - update state immediately before play**
      try {
        _pauseAllOtherVideos(videoId);

        // **CRITICAL: Update state FIRST, then play - this ensures UI responds immediately**
        // **OPTIMIZED: Use ValueNotifier for granular updates - NO setState**
        _controllerStates[videoId] = true;
        _userPaused[videoId] = false; // hide when playing
        _userPausedVN[videoId]?.value = false;
        
        _lifecyclePaused = false;

        // Now play the controller
        _autoAdvancedForIndex.remove(index);
        controller.play();
        _ensureWakelockForVisibility();

        AppLogger.log('▶️ Successfully played video at index $index');

        // **NEW: Start view tracking when user plays**
        if (index < _videos.length) {
          final currentVideo = _videos[index];
          _viewTracker.startViewTracking(
            currentVideo.id,
            videoUploaderId: currentVideo.uploader.id,
          );
          AppLogger.log(
            '▶️ User played video: ${currentVideo.id}, started view tracking',
          );
        }
      } catch (e) {
        AppLogger.log('❌ Error playing video at index $index: $e');
        // **FIX: Remove lock on error**
        _togglingVideos.remove(videoId);
        return;
      }
    }

    // **FIX: Remove lock after a short delay to allow state to settle**
    // This prevents rapid taps from causing race conditions
    Future.delayed(const Duration(milliseconds: 200), () {
      _togglingVideos.remove(videoId);
    });
  }

  /// **BUILD CAROUSEL AD PAGE: Full-screen carousel ad within horizontal PageView**
  void _attachEndListenerIfNeeded(VideoPlayerController controller, int index) {
    final videoId = _videos[index].id;
    controller.removeListener(_videoEndListeners[videoId] ?? () {});
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
    _videoEndListeners[videoId] = listener;
  }

  void _attachBufferingListenerIfNeeded(
    VideoPlayerController controller,
    int index,
  ) {
    final videoId = _videos[index].id;
    controller.removeListener(_bufferingListeners[videoId] ?? () {});
    void listener() {
      if (!mounted) return;
      final bool next =
          controller.value.isInitialized && controller.value.isBuffering;
      final bool current = _isBuffering[videoId] ?? false;
      if (current != next) {
        // Update map (for any legacy reads)
        _isBuffering[videoId] = next;
        // Update ValueNotifier to avoid rebuilding the whole Stack
        (_isBufferingVN[videoId] ??= ValueNotifier<bool>(false)).value = next;
      }
    }

    controller.addListener(listener);
    _bufferingListeners[videoId] = listener;

    // (Removed first-frame tracking listener per revert)
  }



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
  Future<void> _handleDoubleTapLike(VideoModel video) async {
    // Show heart animation
    _showHeartAnimation[video.id] ??= ValueNotifier<bool>(false);
    _showHeartAnimation[video.id]!.value = true;

    // Hide animation after 1 second
    Future.delayed(const Duration(milliseconds: 1000), () {
      _showHeartAnimation[video.id]?.value = false;
    });

    // Check if valid user
    if (_currentUserId == null) {
      _triggerGoogleSignIn();
      return;
    }

    // If the video is already liked by the current user, only show animation
    // Check our specific notifier first for most up-to-date state
    final isLikedNotifier = _isLikedVN.putIfAbsent(video.id, 
        () => ValueNotifier<bool>(video.isLiked));
    
    if (isLikedNotifier.value) {
      AppLogger.log(
        '🔴 DoubleTap Like: Video already liked by current user – showing animation only',
      );
      return;
    }

    // Handle the like
    await _handleLike(video);
  }

  /// **HANDLE LIKE: With API integration (Optimized - No SetState)**
  Future<void> _handleLike(VideoModel video) async {
    // Helper to get or create notifiers ensuring they are synced with model initially
    ValueNotifier<bool> getLikedNotifier() {
       return _isLikedVN.putIfAbsent(video.id, 
          () => ValueNotifier<bool>(video.isLiked));
    }
    ValueNotifier<int> getCountNotifier() {
       return _likeCountVN.putIfAbsent(video.id, 
          () => ValueNotifier<int>(video.likes));
    }

    AppLogger.log('🔴 ========== LIKE BUTTON CLICKED (Optimized) ==========');
    AppLogger.log('🔴 Video ID: ${video.id}');

    // Guard against multiple rapid taps
    if (_likeInProgress[video.id] == true) {
      return;
    }

    // **FIX: Proceed to VideoService even if local _currentUserId is null**
    // If we have a token, VideoService will handle it. We only prompt sign-in 
    // if we are sure there's no user session at all.
    if (_currentUserId == null) {
      AppLogger.log('🔍 _handleLike: Local _currentUserId is null, relying on service-level token check.');
    }

    // Get notifiers
    final likedVN = getLikedNotifier();
    final countVN = getCountNotifier();

    // **OPTIMISTIC UPDATE: Update Notifiers immediately (No setState)**
    final wasLiked = likedVN.value;
    final originalLikes = countVN.value;
    
    // 1. Update Notifiers (Drives UI)
    likedVN.value = !wasLiked;
    countVN.value = wasLiked 
        ? (originalLikes - 1).clamp(0, double.infinity).toInt()
        : originalLikes + 1;

    // 2. Update Model (Keeps data consistent if we scroll away)
    // We update isLiked field instead of manual likedBy mutation
    video.isLiked = !wasLiked;
    video.likes = countVN.value;

    AppLogger.log(
        '🔴 Like Handler: Optimistic Update - Liked: ${likedVN.value}, Count: ${countVN.value}');

    try {
      _likeInProgress[video.id] = true;

      // **SYNC WITH BACKEND**
      VideoModel updatedVideo = await _videoService.toggleLike(video.id);

      AppLogger.log('✅ Successfully toggled like for video ${video.id}');

      // **CRITICAL: Sync Notifiers & Model with Backend Response**
      // We don't replace the object in the list (which requires setState or complex listeners),
      // we just update its properties and the notifiers.
      
      // Update Model properties
      video.likes = updatedVideo.likes;
      // Use the injected isLiked from backend
      video.isLiked = updatedVideo.isLiked;
      
      // Update Notifiers with authoritative backend values
      countVN.value = updatedVideo.likes;
      likedVN.value = updatedVideo.isLiked;

    } catch (e) {
      AppLogger.log('❌ Error handling like: $e');

      // **REVERT: If backend fails, revert optimistic update**
      AppLogger.log('🔴 Like Handler: Reverting optimistic update due to error');
      
      // Revert Notifiers
      likedVN.value = wasLiked;
      countVN.value = originalLikes;

      // Revert Model
      video.isLiked = wasLiked;
      video.likes = originalLikes;

      // Show error
      String errorMessage = 'Failed to like video';
      final errorString = e.toString();
      if (errorString.contains('sign in') || errorString.contains('authenticated')) {
        errorMessage = 'Please sign in again to like videos';
        Future.delayed(const Duration(milliseconds: 500), () {
          _triggerGoogleSignIn();
        });
      }
      _showSnackBar(errorMessage, isError: true);

    } finally {
      _likeInProgress[video.id] = false;
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
    if (!_canShowSignInPrompt()) {
      if (_screenFirstOpenedAt != null) {
        final timeRemaining = _signInPromptDelay - DateTime.now().difference(_screenFirstOpenedAt!);
        final minutesRemaining = timeRemaining.inMinutes;
        final secondsRemaining = timeRemaining.inSeconds % 60;
        AppLogger.log(
          '⏱️ Sign-in prompt delayed. Time remaining: ${minutesRemaining}m ${secondsRemaining}s',
        );
      }
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  /// **NEW: Trigger Google Sign-In directly (shows account picker popup)**
  Future<void> _triggerGoogleSignIn() async {
    try {
      final authController =
          Provider.of<GoogleSignInController>(context, listen: false);
      final user = await authController.signIn();
      if (user != null) {
        AppLogger.log('✅ Sign-in successful after like/comment action');
        // User is now signed in, they can retry the action
      } else {
        AppLogger.log('ℹ️ User cancelled sign-in');
      }
    } catch (e) {
      AppLogger.log('❌ Error triggering sign-in: $e');
      _showSnackBar('Failed to sign in. Please try again.', isError: true);
    }
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
    if (index >= _videos.length) return;
    final videoId = _videos[index].id;
    if (_carouselAdManager.getTotalCarouselAds() > 0 && 
        _currentHorizontalPage.containsKey(videoId)) {
      _currentHorizontalPage[videoId]!.value =
          1; // Switch to carousel ad page - no setState needed!
      AppLogger.log('🎯 Navigated to carousel ad for video $videoId');
    } else {
      AppLogger.log('❌ Failed to navigate to carousel ad:');
      AppLogger.log('   Carousel Ads Empty: ${_carouselAdManager.getTotalCarouselAds() == 0}');
      AppLogger.log('   Video ID Key Exists: ${_currentHorizontalPage.containsKey(videoId)}');
      
      // Attempt to reload ads if empty
      if (_carouselAdManager.getTotalCarouselAds() == 0) {
        _carouselAdManager.loadCarouselAds();
      }
    }
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
                  _isLoading && _videos.isEmpty
                      ? const VideoFeedSkeleton()
                      : _videos.isEmpty && _errorMessage != null
                          ? RefreshIndicator(
                              onRefresh: refreshVideos,
                              child: SingleChildScrollView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                child: SizedBox(
                                  height: MediaQuery.of(context).size.height,
                                  child: _buildErrorState(),
                                ),
                              ),
                            )
                          : _videos.isEmpty
                              ? RefreshIndicator(
                                  onRefresh: refreshVideos,
                                  child: SingleChildScrollView(
                                    physics: const AlwaysScrollableScrollPhysics(),
                                    child: SizedBox(
                                      height: MediaQuery.of(context).size.height,
                                      child: _buildEmptyState(),
                                    ),
                                  ),
                                )
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
        Map<String, VideoPlayerController>.from(_controllerPool);

    controllersToDispose.forEach((videoId, controller) {
      try {
        // **FIX: Remove listeners to avoid memory leaks**
        controller.removeListener(_bufferingListeners[videoId] ?? () {});
        controller.removeListener(_videoEndListeners[videoId] ?? () {});

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
            sharedPool.removeController(videoId);
            controller.dispose();
            AppLogger.log(
              '🗑️ VideoFeedAdvanced: Disposed controller for video $videoId (profile flow)',
            );
          } catch (e) {
            AppLogger.log(
              '⚠️ VideoFeedAdvanced: Error disposing controller: $e',
            );
          }
        } else {
          // **TAB FLOW: Preserve controller in shared pool for quick resume**
          // Check if it was playing (requires finding the index for _wasPlayingBeforeNavigation)
          // Actually, we can use videoId for _wasPlayingBeforeNavigation too if we wanted, 
          // but for now let's just save it.
          
          if (controller.value.isInitialized && controller.value.isPlaying) {
            controller.pause();
            _controllerStates[videoId] = false;
            AppLogger.log(
              '⏸️ VideoFeedAdvanced: Paused video $videoId before saving to shared pool',
            );
          }

          sharedPool.addController(videoId, controller, skipDisposeOld: true);
          savedControllers++;
          AppLogger.log(
            '💾 VideoFeedAdvanced: Saved controller for video $videoId (ID) to shared pool',
          );
        }
      } catch (e) {
        AppLogger.log('⚠️ Error saving controller for video $videoId: $e');
        try {
          controller.dispose();
        } catch (_) {}
      }
    });

    AppLogger.log(
      '💾 VideoFeedAdvanced: Saved $savedControllers controllers to shared pool',
    );

    // **MEMORY MANAGEMENT: Aggressively clean up when opened from ProfileScreen**
    // FIX: Removed aggressive cleanup (sharedPool.clearAll()) to prevent disposed controller error
    
    // Manage memory for standard flow
    if (savedControllers > 2) {
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
    _longPressAdAutoHideTimer?.cancel();
    _showLongPressAdOverlayVN.dispose();

    // **NEW: Cancel ad refresh subscription**
    _adRefreshSubscription?.cancel();
    _connectivitySubscription?.cancel();

    // Remove observer
    WidgetsBinding.instance.removeObserver(this);

    _disableWakelock();
    super.dispose();
  }


  /// **GET DETAILED CACHE INFO: Comprehensive cache information**
  Map<String, dynamic> _getDetailedCacheInfo() {
    final cacheStats = {};

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

