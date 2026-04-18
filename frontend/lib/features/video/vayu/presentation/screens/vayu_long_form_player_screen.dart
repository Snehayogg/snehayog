import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/features/video/edit/presentation/screens/edit_video_details.dart';
import 'package:vayug/shared/widgets/report_dialog_widget.dart';
import 'package:vayug/shared/widgets/vayu_bottom_sheet.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/providers/navigation_providers.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'dart:async';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/features/video/core/data/services/video_service.dart';
import 'package:vayug/features/profile/core/presentation/screens/profile_screen.dart';
import 'package:vayug/features/video/dubbing/data/models/dubbing_models.dart';
import 'package:vayug/features/video/dubbing/data/services/on_device_dubbing_service.dart';
import 'package:vayug/shared/widgets/follow_button_widget.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayug/shared/factories/video_controller_factory.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:vayug/features/ads/data/services/active_ads_service.dart';
import 'package:vayug/features/video/feed/presentation/screens/video_feed_advanced/widgets/banner_ad_section.dart';
import 'package:vayug/shared/widgets/interactive_scale_button.dart';
import 'package:vayug/features/video/vayu/presentation/widgets/vayu_video_progress_bar.dart';
import 'package:vayug/shared/utils/format_utils.dart';
import 'package:vayug/features/video/core/presentation/managers/video_controller_manager.dart';
import 'package:vayug/features/video/core/presentation/managers/shared_video_controller_pool.dart';
import 'package:vayug/features/video/core/presentation/managers/main_controller.dart';
import 'package:vayug/features/video/core/data/services/video_view_tracker.dart';
import 'package:vayug/features/ads/data/services/ad_impression_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayug/features/video/core/presentation/widgets/quiz_overlay.dart';

class VayuLongFormPlayerScreen extends ConsumerStatefulWidget {
  final VideoModel video;
  final List<VideoModel> relatedVideos;
  final int? parentTabIndex; // **NEW: Tab context for autoplay logic**

  const VayuLongFormPlayerScreen({
    Key? key,
    required this.video,
    this.relatedVideos = const [],
    this.parentTabIndex,
  }) : super(key: key);

  @override
  ConsumerState<VayuLongFormPlayerScreen> createState() =>
      _VayuLongFormPlayerScreenState();
}

class _VayuLongFormPlayerScreenState extends ConsumerState<VayuLongFormPlayerScreen>
    with WidgetsBindingObserver {
  static const _controlTouchSize = 42.0;
  static const _controlIconSize = 42.0;

  // Video Feed State
  final List<VideoModel> _videos = [];
  late PageController _pageController;
  int _currentIndex = 0;
  final Map<int, VideoPlayerController> _controllers = {};
  final Map<int, ChewieController?> _chewieControllers = {};

  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  final VideoService _videoService = VideoService();

  // Unified Controller Management
  final VideoControllerManager _videoControllerManager = VideoControllerManager();
  final SharedVideoControllerPool _controllerPool = SharedVideoControllerPool();
  MainController? _mainController;
  bool _lifecyclePaused = false;

  // Banner Ad State
  final ActiveAdsService _activeAdsService = ActiveAdsService();
  final Map<int, Map<String, dynamic>> _bannerAdsByIndex = {};

  // Controls State
  bool _showControls = true;
  bool _showScrubbingOverlay = false;
  Duration _scrubbingTargetTime = Duration.zero;
  Duration _scrubbingDelta = Duration.zero;
  double _horizontalDragTotal = 0.0;
  bool _isForward = true;
  Timer? _controlsTimer; // Renamed from _hideControlsTimer
  bool _isScrollingLocked = false; // **NEW: State for locking PageView scroll**

  // Gesture state
  double _brightnessValue = 0.5;
  double _volumeValue = 0.5;
  Timer? _overlayTimer;
  SharedPreferences? _prefs;
  String? _currentUserId;

  bool _isSaving = false;
  double _playbackSpeed = 1.0;
  final List<double> _playbackSpeedOptions = <double>[
    0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0,
  ];
  bool _isControlsLocked = false;
  bool _wakelockEnabled = false;
  bool _isFullScreenManual = false;

  // Scroll hint
  bool _hasSeenScrollHint = true;
  bool _showScrollHintOverlay = false;

  // Dubbing State
  final OnDeviceDubbingService _onDeviceDubbingService = OnDeviceDubbingService();
  final Map<String, ValueNotifier<DubbingResult>> _dubbingResultsVN = {};
  final Map<String, StreamSubscription> _dubbingSubscriptions = {};
  final Map<String, String> _selectedAudioLanguage = {};
  bool _isDubbingProgressVisible = true;
  
  // Revenue Tracking
  late final VideoViewTracker _viewTracker;
  late final AdImpressionService _adImpressionService;
  final Map<int, Timer> _viewUITimers = {};
  final Map<int, Duration> _lastKnownPositions = {};

  // Quiz State
  QuizModel? _activeQuiz;
  final Map<String, Set<int>> _shownQuizzesPerVideo = {};
  final List<QuizModel> _activeQuizHistory = []; // Stack for current video session
  bool _isQuizListenerAttached = false;


  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);

    _videos.add(widget.video);
    if (widget.relatedVideos.isNotEmpty) {
      _videos.addAll(widget.relatedVideos);
    }
    _pageController = PageController(initialPage: 0);

    _initPrefs();
    _viewTracker = VideoViewTracker();
    _adImpressionService = AdImpressionService();
    
    // Start tracking for the first video after a short delay
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startViewTracking(_currentIndex);
    });

    // Register with VideoControllerManager for tab-switch pauses
    _videoControllerManager.registerOnRoutePopped(() {
      if (mounted) _validateAndRestoreControllers();
    });

    // **NEW: Restore last viewed video index**
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        // Find index of the passed video in the list
        final initialIdx = _videos.indexWhere((v) => v.id == widget.video.id);
        
        if (initialIdx >= 0) {
          AppLogger.log('🚀 VayuPlayer: Starting at selected video index $initialIdx');
          _currentIndex = initialIdx;
          _pageController.jumpToPage(initialIdx);
          _initializePlayer(initialIdx);
        } else {
          // Fallback to restoration ONLY if the selected video isn't in the list (rare)
          final mainController = ref.read(mainControllerProvider);
          final lastIndex = await mainController.getLastViewedVideoIndex(1); // 1 = Vayu
          if (lastIndex > 0 && lastIndex < _videos.length) {
            AppLogger.log('🚀 VayuPlayer: Restoring index to $lastIndex');
            _currentIndex = lastIndex;
            _pageController.jumpToPage(lastIndex);
            _initializePlayer(lastIndex);
          } else {
            _initializePlayer(0);
          }
        }
        
        _preloadNearbyVideos();
        _reprimeWindowIfNeeded(_currentIndex);
      }
    });

    if (_videos.length < 3) {
      _loadMoreVideos();
    }

    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _mainController = ref.read(mainControllerProvider);
        _mainController?.setBottomNavVisibility(false);
        
        // **NEW: Register with MainController as a video observer**
        _mainController?.registerVideoObserver(
          onPause: _pauseCurrentVideo,
          onResume: _resumeCurrentVideo,
        );

        // **NEW: Force pause other videos (like Yug/Profile) when opening the player**
        _mainController?.forcePauseVideos();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mainController = ref.watch(mainControllerProvider);
    
    // **FIX: Update current user ID from auth controller**
    final authController = ref.watch(googleSignInProvider);
    if (authController.isSignedIn && authController.userData != null) {
      final userId = authController.userData!['googleId'] ?? authController.userData!['id'];
      if (_currentUserId != userId) {
        setState(() => _currentUserId = userId);
      }
    } else if (!authController.isSignedIn && _currentUserId != null) {
      setState(() => _currentUserId = null);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        _handleAppMovedToBackground();
        break;
      case AppLifecycleState.resumed:
        _handleAppResumed();
        break;
      case AppLifecycleState.detached:
        _videoControllerManager.disposeAllControllers();
        break;
    }
  }

  void _handleAppMovedToBackground() {
    _pauseCurrentVideo();
    _videoControllerManager.pauseAllVideos();
    _controllerPool.pauseAllControllers();
    _lifecyclePaused = true;
    _disableWakelock();
  }

  void _handleAppResumed() {
    _lifecyclePaused = false;
    final bool isCurrentRoute = ModalRoute.of(context)?.isCurrent ?? true;
    if (isCurrentRoute && mounted && !_lifecyclePaused) {
      final controller = _controllers[_currentIndex];
      if (controller != null && controller.value.isInitialized) {
        controller.play();
        _enableWakelock();
      }
    }
  }

  void _pauseCurrentVideo() {
    if (_currentIndex < _videos.length) {
      final controller = _controllers[_currentIndex];
      if (controller != null) {
        try {
          if (controller.value.isPlaying) {
             controller.pause();
             AppLogger.log('⏸️ VayuPlayer: Paused current video via MainController');
          }
        } catch (_) {}
      }
    }
  }

  void _resumeCurrentVideo() {
    if (mounted && !_lifecyclePaused) {
      // **TAB-AWARE RESUME GUARD**
      if (widget.parentTabIndex != null) {
        final currentTabIndex = _mainController?.currentIndex ?? 0;
        if (currentTabIndex != widget.parentTabIndex) {
          AppLogger.log('🚫 VayuPlayer: Tab hidden (belongsTo=${widget.parentTabIndex}, active=$currentTabIndex). Blocking resume.');
          return;
        }
      }

      final controller = _controllers[_currentIndex];
      if (controller != null && controller.value.isInitialized && !controller.value.isPlaying) {
        controller.play();
        _enableWakelock();
        AppLogger.log('▶️ VayuPlayer: Resumed current video via MainController');
      }
    }
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    final hasSeenHint = _prefs!.getBool('has_seen_vayu_long_form_scroll_hint') ?? false;
    if (mounted) {
      setState(() => _hasSeenScrollHint = hasSeenHint);
    }
    if (!hasSeenHint) {
      _handleFirstTimeScrollHint(_prefs!);
    }
  }

  Future<void> _handleFirstTimeScrollHint(SharedPreferences prefs) async {
    // Disable hint for pushed player (e.g. from Search/Profile)
    if (_videos.length > 1 && widget.relatedVideos.isNotEmpty) return;

    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted || _currentIndex != 0 || _videos.length <= 1) return;

    setState(() => _showScrollHintOverlay = true);
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted || _currentIndex != 0 || !_pageController.hasClients) return;

    final screenHeight = MediaQuery.of(context).size.height;
    final targetOffset = screenHeight * 0.30;

    try {
      await _pageController.animateTo(targetOffset, duration: const Duration(milliseconds: 800), curve: Curves.easeInOut);
      await Future.delayed(const Duration(milliseconds: 150));
      if (!mounted || _currentIndex != 0 || !_pageController.hasClients) return;
      await _pageController.animateTo(0, duration: const Duration(milliseconds: 800), curve: Curves.easeInOut);
    } catch (e) { AppLogger.log('Error in scroll hint animation: $e'); }

    if (!mounted) return;
    setState(() => _showScrollHintOverlay = false);
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() => _hasSeenScrollHint = true);
    await prefs.setBool('has_seen_vayu_long_form_scroll_hint', true);
  }

  Future<void> _loadMoreVideos() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final response = await _videoService.getVideos(
        page: _currentPage, 
        videoType: 'vayu',
        clearSession: false,
      );
      
      List<VideoModel> newVideos = [];
      final List? videosList = response['videos'] ?? response['data'];
      if (videosList != null) {
        newVideos = videosList.map((v) => VideoModel.fromJson(Map<String, dynamic>.from(v))).toList();
      }
      
      if (newVideos.isEmpty) {
        if (mounted) setState(() => _hasMore = false);
      } else {
        final existingIds = _videos.map((v) => v.id).toSet();
        newVideos.removeWhere((v) => existingIds.contains(v.id));
        
        if (mounted) {
          setState(() {
            _videos.addAll(newVideos);
            _currentPage++;
            _hasMore = response['hasMore'] as bool? ?? true;
          });
          if (_currentIndex + 1 < _videos.length) _preloadNearbyVideos();
        }
      }
    } catch (e) { 
      AppLogger.log('Error loading more vayu videos: $e'); 
    } finally { 
      if (mounted) setState(() => _isLoadingMore = false); 
    }
  }

  Future<void> _initializePlayer([int? requestedIndex]) async {
    final index = requestedIndex ?? _currentIndex;
    if (index >= _videos.length) return;
    
    final videoToPlay = _videos[index];

    // Check pool first
    VideoPlayerController? existing = _controllerPool.getController(videoToPlay.id);
    if (existing != null && existing.value.isInitialized) {
       if (mounted) {
         setState(() {
           _controllers[index] = existing;
           _chewieControllers[index]?.dispose(); // Dispose old one before replacing
           _chewieControllers[index] = _createChewieController(existing);
         });
         _setupLateInitialization(index, existing);
       }
       return;
    }

    // Proper disposal of stale local references
    if (_controllers.containsKey(index)) {
      final c = _controllers.remove(index);
      final ch = _chewieControllers.remove(index);
      ch?.dispose();
      
      if (c != null) {
        c.removeListener(_onPositionChanged);
        _controllerPool.disposeController(videoToPlay.id);
      }
    }

    _disableWakelock();

    try {
      final selectedLang = _selectedAudioLanguage[videoToPlay.id] ?? 'default';
      VideoModel effectiveVideo = videoToPlay;
      if (selectedLang != 'default') {
        final dubbedUrl = videoToPlay.dubbedUrls?[selectedLang];
        if (dubbedUrl != null) effectiveVideo = videoToPlay.copyWith(videoUrl: dubbedUrl);
      }

      await _controllerPool.makeRoomForNewController();

      final newController = await VideoControllerFactory.createController(effectiveVideo);
      await newController.initialize().timeout(const Duration(seconds: 15));
      await newController.setPlaybackSpeed(_playbackSpeed);

      if (mounted) {
        final chewie = _createChewieController(newController);
        setState(() {
          _controllers[index] = newController;
          _chewieControllers[index] = chewie;
        });
        
        _controllerPool.addController(videoToPlay.id, newController, index: index);
        _setupLateInitialization(index, newController);
      }
    } catch (e) {
      AppLogger.log('❌ VayuLongFormPlayer: Failed to initialize: $e');
    }
  }

  ChewieController _createChewieController(VideoPlayerController controller) {
    return ChewieController(
      videoPlayerController: controller,
      aspectRatio: 16 / 9,
      autoPlay: true,
      showControls: false,
      customControls: const SizedBox.shrink(),
      materialProgressColors: ChewieProgressColors(
        playedColor: AppColors.primary,
        handleColor: AppColors.primary,
        backgroundColor: AppColors.borderPrimary,
        bufferedColor: AppColors.textTertiary,
      ),
      placeholder: Container(color: Colors.black, child: const Center(child: CircularProgressIndicator(color: AppColors.primary))),
    );
  }

  void _setupLateInitialization(int index, VideoPlayerController controller) async {
    controller.removeListener(_onPositionChanged); // Prevent double-attach
    controller.addListener(_onPositionChanged);
    
    print('🔔 VayuPlayer: Listener attached for index $index (Video ID: ${_videos[index].id})');
    
    if (index == _currentIndex) {
      _enableWakelock();
      _resumePlayback(index);
      
      // **NEW: Start autohide timer if controls are shown on initial load**
      if (_showControls) {
        _startHideControlsTimer();
      }

      try {
        _brightnessValue = await ScreenBrightness().application;
        final vol = await FlutterVolumeController.getVolume();
        if (vol != null) _volumeValue = vol;
      } catch (_) {}
    }
  }

  void _onPositionChanged() {
    if (!mounted) return;
    
    // Check if the current video is actually disposed while swiping
    final controller = _controllers[_currentIndex];
    if (controller == null) return;
    
    if (mounted) setState(() {});
    
    final currentPos = controller.value.position;
    final lastPos = _lastKnownPositions[_currentIndex] ?? Duration.zero;

    // Detect loop or manual restart
    if (currentPos < lastPos && lastPos.inSeconds > 1) {
      AppLogger.log('♻️ VayuPlayer: Loop detected, restarting tracking');
      _stopViewTracking(_currentIndex);
      _startViewTracking(_currentIndex);
    }
    _lastKnownPositions[_currentIndex] = currentPos;

    if (controller.value.isPlaying && currentPos.inSeconds % 5 == 0) {
      _savePlaybackPosition(_currentIndex);
    }

    // Check for Quizzes
    _checkAndTriggerQuiz(controller);
  }

  void _checkAndTriggerQuiz(VideoPlayerController controller) {
    if (_activeQuiz != null) return;

    final video = _videos[_currentIndex];
    final quizzes = video.quizzes;
    if (quizzes == null || quizzes.isEmpty) return;

    final currentMs = controller.value.position.inMilliseconds;
    final shownQuizzes = _shownQuizzesPerVideo[video.id] ??= {};

    for (int i = 0; i < quizzes.length; i++) {
      final quiz = quizzes[i];
      if (shownQuizzes.contains(i)) continue;

      final targetMs = (quiz.timestamp * 1000).toInt();
      final diff = currentMs - targetMs;

      // Trigger quiz if within 1.5s window
      if (diff >= 0 && diff < 1500) {
        setState(() {
          _activeQuiz = quiz;
          shownQuizzes.add(i);
          _activeQuizHistory.add(quiz);
        });
        break;
      }
    }
  }

  @override
  void dispose() {
    _disableWakelock();
    WidgetsBinding.instance.removeObserver(this);
    
    // **NEW: Unregister as MainController video observer**
    _mainController?.unregisterVideoObserver(
      onPause: _pauseCurrentVideo,
      onResume: _resumeCurrentVideo,
    );

    // Safely unregister legacy callbacks
    try {
      _mainController?.unregisterCallbacks();
    } catch (_) {}
    
    // Save current position before cleaning up
    _savePlaybackPosition(_currentIndex);
    
    // Local cleanup: Stop playback and REMOVE listeners to prevent defunct element crashes
    _controllers.forEach((index, c) {
      try {
        c.removeListener(_onPositionChanged);
        c.pause();
        c.setVolume(0.0);
      } catch (_) {}
    });
    
    _chewieControllers.forEach((index, c) => c?.dispose());
    
    _pageController.dispose();
    _controlsTimer?.cancel(); // Changed from _hideControlsTimer
    _overlayTimer?.cancel();
    _stopViewTracking(_currentIndex);
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    Future.microtask(() { if (context.mounted) ref.read(mainControllerProvider).setBottomNavVisibility(true); });
    super.dispose();
  }

  void _startViewTracking(int index) {
    if (index < 0 || index >= _videos.length) return;
    final video = _videos[index];
    AppLogger.log('🎯 VayuPlayer: Starting view tracking for video ${video.id}');
    _viewTracker.startViewTracking(
      video.id,
      videoUploaderId: video.uploader.id,
      videoHash: video.videoHash,
    );
    
    // Cancel any existing UI timer for this index
    _viewUITimers[index]?.cancel();

    // Local UI update simulation (matching backend threshold)
    _viewUITimers[index] = Timer(const Duration(seconds: 3), () {
      if (mounted && _currentIndex == index) {
        setState(() {
          _videos[index] = _videos[index].copyWith(views: _videos[index].views + 1);
        });
        AppLogger.log('✅ VayuPlayer: Local view incremented for video ${video.id}');
      }
    });
  }

  void _stopViewTracking(int index) {
    if (index < 0 || index >= _videos.length) return;
    
    // Cancel the UI timer immediately 
    _viewUITimers[index]?.cancel();
    _viewUITimers.remove(index);

    final video = _videos[index];
    AppLogger.log('🎯 VayuPlayer: Stopping view tracking for video ${video.id}');
    _viewTracker.stopViewTracking(video.id);
  }

  void _handleUnifiedHorizontalDrag(double deltaX) {
    if (_isControlsLocked || !_controllers.containsKey(_currentIndex)) return;
    _horizontalDragTotal += deltaX;
    final controller = _controllers[_currentIndex]!;
    final seekOffset = Duration(milliseconds: (_horizontalDragTotal * 500).toInt());
    var targetPosition = controller.value.position + seekOffset;
    if (targetPosition < Duration.zero) targetPosition = Duration.zero;
    if (targetPosition > controller.value.duration) targetPosition = controller.value.duration;
    setState(() {
      _showScrubbingOverlay = true;
      _scrubbingTargetTime = targetPosition;
      _scrubbingDelta = seekOffset;
      _isForward = deltaX > 0;
    });
  }

  void _handleHorizontalDragEnd() {
    if (!_controllers.containsKey(_currentIndex)) return;
    _controllers[_currentIndex]!.seekTo(_scrubbingTargetTime);
    setState(() {
      _showScrubbingOverlay = false;
      _horizontalDragTotal = 0.0;
      _showControls = true;
    });
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (_isControlsLocked) return;
    final size = MediaQuery.of(context).size;
    final isLeftSide = details.localPosition.dx < size.width / 2;
    final delta = details.primaryDelta! / size.height * 1.5;

    if (isLeftSide) {
       _brightnessValue = (_brightnessValue - delta).clamp(0.0, 1.0);
      ScreenBrightness().setApplicationScreenBrightness(_brightnessValue);
      // No overlay for brightness as requested
    } else {
      _volumeValue = (_volumeValue - delta).clamp(0.0, 1.0);
      FlutterVolumeController.setVolume(_volumeValue);
    }
    setState(() { _showScrubbingOverlay = false; _showControls = false; });
    _resetOverlayTimer();
  }

  void _handleVerticalDragEnd() {
    _resetOverlayTimer();
    _overlayTimer = Timer(const Duration(milliseconds: 500), () {
      // No-op - overlay removed
    });
  }
  
  void _resetOverlayTimer() { 
    _overlayTimer?.cancel(); 
  }

  void _handleTap() {
    setState(() => _showControls = !_showControls);
    if (MediaQuery.of(context).orientation == Orientation.landscape) {
      SystemChrome.setEnabledSystemUIMode(_showControls ? SystemUiMode.manual : SystemUiMode.immersiveSticky, overlays: SystemUiOverlay.values);
    }
    if (_showControls) _startHideControlsTimer();
  }

  void _startHideControlsTimer() {
    _controlsTimer?.cancel(); // Changed from _hideControlsTimer
    _controlsTimer = Timer(const Duration(seconds: 3), () { // Changed from _hideControlsTimer
      if (mounted) {
        setState(() => _showControls = false);
        if (MediaQuery.of(context).orientation == Orientation.landscape) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        }
      }
    });
  }

  void _savePlaybackPosition(int index) async {
    final controller = _controllers[index];
    if (controller != null && controller.value.isInitialized) {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs!.setInt('video_pos_${_videos[index].id}', controller.value.position.inSeconds);
    }
  }

  Future<void> _resumePlayback(int index) async {
    final controller = _controllers[index];
    if (controller == null) return;
    _prefs ??= await SharedPreferences.getInstance();
    final savedSeconds = _prefs!.getInt('video_pos_${_videos[index].id}');
    if (savedSeconds != null && savedSeconds > 0) {
      final pos = Duration(seconds: savedSeconds);
      if (pos < controller.value.duration) controller.seekTo(pos);
    }
  }

  void _togglePlay() {
    final controller = _controllers[_currentIndex];
    if (controller == null) return;
    Vibration.vibrate(duration: 50, amplitude: 128);
    setState(() {
      if (controller.value.isPlaying) { 
        controller.pause(); 
      } else { 
        controller.play(); 
        _hideControlsWithDelay(); 
      }
    });
    _showFeedbackAnimation(controller.value.isPlaying);
  }

  void _showFeedbackAnimation(bool isPlaying) {
    if (isPlaying) {
      _startHideControlsTimer(); 
    } else { 
      setState(() => _showControls = true); 
      _controlsTimer?.cancel(); // Changed from _hideControlsTimer
    }
  }

  void _showSnackBar(String message, {Duration? duration, VayuSnackBarType type = VayuSnackBarType.info}) {
    if (!mounted) return;
    VayuSnackBar.show(context, message, duration: duration ?? const Duration(seconds: 3), type: type);
  }

  void _hideControlsWithDelay() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _controllers[_currentIndex]?.value.isPlaying == true && _showControls) {
        setState(() => _showControls = false);
      }
    });
  }

  void _showEpisodeList(BuildContext context, VideoModel video) {
    if (video.episodes == null || video.episodes!.isEmpty) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.backgroundPrimary,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
          padding: EdgeInsets.symmetric(vertical: AppSpacing.spacing4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing4, vertical: AppSpacing.spacing2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Episodes', style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
                  ],
                ),
              ),
              const Divider(height: 1),
              AppSpacing.vSpace8,
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing4),
                  itemCount: video.episodes!.length,
                  separatorBuilder: (context, index) => AppSpacing.vSpace8,
                  itemBuilder: (context, index) {
                    final ep = video.episodes![index];
                    final isCurrent = ep['id'] == video.id || ep['_id'] == video.id;
                    
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 100, height: 56, // 16:9 ratio
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          image: ep['thumbnailUrl'] != null 
                            ? DecorationImage(image: CachedNetworkImageProvider(ep['thumbnailUrl']), fit: BoxFit.cover)
                            : null,
                          color: AppColors.backgroundSecondary,
                        ),
                        child: isCurrent ? Container(
                          decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)),
                          child: const Icon(Icons.play_circle_fill_rounded, color: AppColors.primary, size: 28),
                        ) : null,
                      ),
                      title: Text(ep['videoName'] ?? 'Episode ${index + 1}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.bodyMedium.copyWith(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, color: isCurrent ? AppColors.primary : AppColors.textPrimary)),
                      subtitle: ep['duration'] != null ? Text(_formatDuration(Duration(seconds: (ep['duration'] as num).toInt())), style: AppTypography.bodySmall) : null,
                      onTap: () {
                        Navigator.pop(context);
                        if (!isCurrent) {
                           final epId = ep['id'] ?? ep['_id'];
                           if (epId != null) {
                             final targetIndex = _videos.indexWhere((v) => v.id == epId);
                             if (targetIndex != -1) {
                               _pageController.animateToPage(
                                 targetIndex,
                                 duration: const Duration(milliseconds: 300),
                                 curve: Curves.easeInOut,
                               );
                             } else {
                               _showSnackBar('Episode is not in current feed.', type: VayuSnackBarType.info);
                             }
                           }
                        }
                      },
                    );
                  },
                ),
              ),
              
              // Quiz Overlay
              if (_activeQuiz != null)
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.spacing2,
                    vertical: AppSpacing.spacing3,
                  ),
                  child: QuizOverlay(
                    quiz: _activeQuiz!,
                    onDismiss: () => setState(() => _activeQuiz = null),
                    onAnswered: (answerIndex) {
                      AppLogger.log('📝 VayuPlayer: Quiz answered: $answerIndex');
                      // Future analytics tracking could go here
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _handleDoubleTapToSeek(TapDownDetails details) {
    final controller = _controllers[_currentIndex];
    if (controller == null || !controller.value.isInitialized) return;
    final size = MediaQuery.of(context).size;
    final isLeftSide = details.localPosition.dx < size.width / 2;
    final seekOffset = Duration(seconds: isLeftSide ? -10 : 10);
    var target = controller.value.position + seekOffset;
    if (target < Duration.zero) target = Duration.zero;
    if (target > controller.value.duration) target = controller.value.duration;
    controller.seekTo(target);
    setState(() {
      _showControls = true;
      _showScrubbingOverlay = true;
      _scrubbingTargetTime = target;
      _scrubbingDelta = seekOffset;
      _isForward = !isLeftSide;
    });
    _startHideControlsTimer();
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(milliseconds: 700), () {
      if (mounted) setState(() => _showScrubbingOverlay = false);
    });
  }

  void _showShareOptions(VideoModel video) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    // Using explicit sizes to match the Vayu UI design pattern
    final iconSize = isLandscape ? 17.0 : 20.0;
    final titleSize = isLandscape ? 12.0 : AppTypography.bodyMedium.fontSize;
    
    VayuBottomSheet.show<void>(
      context: context,
      title: 'Share',
      maxWidth: isLandscape ? 380.0 : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(Icons.share_rounded, color: AppColors.textPrimary, size: iconSize),
            title: Text('Share Link', style: AppTypography.bodyMedium.copyWith(fontSize: titleSize)),
            onTap: () {
              Navigator.pop(context);
              Share.share('Check out this video: ${video.videoUrl}');
            },
          ),
          ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            leading: Icon(Icons.play_circle_outline_rounded, color: AppColors.textPrimary, size: iconSize),
            title: Text('Play in External App', style: AppTypography.bodyMedium.copyWith(fontSize: titleSize)),
            onTap: () async {
              Navigator.pop(context);
              _openInExternalPlayer(video);
            },
          ),
          if (!isLandscape) const SizedBox(height: 12),
        ],
      ),
    );
  }

  void _showShareSuggestionBottomSheet(VideoModel video) {
    final TextEditingController controller = TextEditingController();
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    VayuBottomSheet.show<void>(
      context: context,
      title: 'Share Suggestion',
      maxWidth: isLandscape ? 450.0 : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Did you face any problem while watching this video? share with us',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLines: 4,
              cursorColor: AppColors.primary,
              decoration: InputDecoration(
                hintText: 'Type your suggestion here...',
                hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.textTertiary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.borderPrimary),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.primary, width: 2),
                ),
                filled: true,
                fillColor: AppColors.backgroundSecondary,
              ),
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textPrimary),
            ),
            const SizedBox(height: 20),
            AppButton(
              onPressed: () {
                if (controller.text.trim().isEmpty) {
                  _showSnackBar('Please enter a suggestion', type: VayuSnackBarType.error);
                  return;
                }
                Navigator.pop(context);
                _showSnackBar('Suggestion shared successfully!', type: VayuSnackBarType.success);
              },
              label: 'Share Suggestion',
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Future<void> _openInExternalPlayer(VideoModel video) async {
    if (Theme.of(context).platform == TargetPlatform.android) {
        final intent = AndroidIntent(
          action: 'action_view',
          data: video.videoUrl,
          type: 'video/*',
          flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK],
        );
        try {
          await intent.launch();
        } catch (e) {
          AppLogger.log('Error launching intent: $e');
          _showSnackBar('No external player found', type: VayuSnackBarType.error);
        }
    } else {
        final url = Uri.parse(video.videoUrl);
        if (await canLaunchUrl(url)) {
            await launchUrl(url, mode: LaunchMode.externalApplication);
        } else {
            _showSnackBar('Could not launch external player', type: VayuSnackBarType.error);
        }
    }
  }

  Future<void> _handleToggleSave([int? requestedIndex]) async {
    if (_isSaving) return;
    final index = requestedIndex ?? _currentIndex;
    final video = _videos[index];
    try {
      setState(() => _isSaving = true);
      HapticFeedback.lightImpact();
      final isSaved = await _videoService.toggleSave(video.id);
      setState(() { video.isSaved = isSaved; _isSaving = false; });
      if (mounted) {
        _showSnackBar(
          isSaved ? 'Video saved to collection' : 'Video removed from collection', 
          duration: const Duration(seconds: 2),
          type: isSaved ? VayuSnackBarType.success : VayuSnackBarType.info,
        );
      }
    } catch (e) { setState(() => _isSaving = false); }
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    if (_playbackSpeed == speed) return;
    try {
      final controller = _controllers[_currentIndex];
      if (controller != null && controller.value.isInitialized) {
        await controller.setPlaybackSpeed(speed);
      }
      if (mounted) {
        setState(() => _playbackSpeed = speed); 
      } else {
        _playbackSpeed = speed;
      }
    } catch (e) { AppLogger.log('Failed speed: $e'); }
  }

  void _nextVideo() {
    if (_currentIndex < _videos.length - 1) {
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _previousVideo() {
    if (_currentIndex > 0) {
      _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _toggleFullScreen() {
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final controller = _controllers[_currentIndex];
    final aspectRatio = (controller != null && controller.value.isInitialized) ? controller.value.aspectRatio : 1.0;

    if (aspectRatio < 1.0) {
      setState(() { _isFullScreenManual = !_isFullScreenManual; _showControls = true; });
      SystemChrome.setEnabledSystemUIMode(_isFullScreenManual ? SystemUiMode.immersiveSticky : SystemUiMode.manual, overlays: SystemUiOverlay.values);
    } else {
      SystemChrome.setPreferredOrientations(isPortrait ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight] : [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
      setState(() { _isFullScreenManual = false; _showControls = true; });
    }
    _startHideControlsTimer();
  }

  Future<void> _showMoreOptions() async {
    if (!mounted) return;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    final iconSize = isLandscape ? 17.0 : 20.0;
    final titleSize = isLandscape ? 12.0 : AppTypography.bodyMedium.fontSize;
    final trailingSize = isLandscape ? 10.5 : AppTypography.bodySmall.fontSize;
    
    await VayuBottomSheet.show<void>(
      context: context, 
      title: 'More Options',
      maxWidth: isLandscape ? 380.0 : null,
      padding: isLandscape ? const EdgeInsets.symmetric(horizontal: 12, vertical: 4) : null,
      child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(Icons.speed_rounded, color: AppColors.textPrimary, size: iconSize),
                  title: Text('Playback Speed', style: AppTypography.bodyMedium.copyWith(fontSize: titleSize)),
                  trailing: Text(_formatPlaybackSpeed(_playbackSpeed), style: AppTypography.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: trailingSize)),
                  onTap: () {
                    Navigator.pop(context);
                    _showPlaybackSpeedOptions();
                  },
                ),
                if (_currentIndex < _videos.length)
                  ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(Icons.language_rounded, color: AppColors.textPrimary, size: iconSize),
                    title: Text('Audio Language', style: AppTypography.bodyMedium.copyWith(fontSize: titleSize)),
                    trailing: Text((_selectedAudioLanguage[_videos[_currentIndex].id] ?? 'default').toUpperCase(), style: AppTypography.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: trailingSize)),
                    onTap: () {
                      Navigator.pop(context);
                      _showLanguageSelector(context, _videos[_currentIndex]);
                    },
                  ),
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(_isControlsLocked ? Icons.lock_rounded : Icons.lock_open_rounded, color: AppColors.textPrimary, size: iconSize),
                  title: Text(_isControlsLocked ? 'Unlock' : 'Lock', style: AppTypography.bodyMedium.copyWith(fontSize: titleSize)),
                  onTap: () {
                    Navigator.pop(context);
                    setState(() => _isControlsLocked = !_isControlsLocked);
                  },
                ),
                if (_currentUserId != null && _currentIndex < _videos.length)
                  Builder(
                    builder: (context) {
                      final video = _videos[_currentIndex];
                      final isOwner = video.uploader.googleId == _currentUserId || video.uploader.id == _currentUserId;
                      if (!isOwner) return const SizedBox.shrink();
                      
                      return ListTile(
                        dense: isLandscape,
                        visualDensity: VisualDensity.compact,
                        leading: Icon(Icons.edit_outlined, color: AppColors.textPrimary, size: iconSize),
                        title: Text('Edit Video', style: AppTypography.bodyMedium.copyWith(fontSize: titleSize)),
                        onTap: () async {
                          Navigator.pop(context);
                          final result = await Navigator.of(context).push<Map<String, dynamic>>(
                            MaterialPageRoute(
                              builder: (context) => EditVideoDetails(video: video),
                            ),
                          );

                          if (result != null && mounted) {
                            setState(() {
                              _videos[_currentIndex] = _videos[_currentIndex].copyWith(
                                videoName: result['videoName'],
                                link: result['link'],
                                tags: result['tags'],
                                seriesId: result['seriesId'],
                                episodes: result['episodes'] != null 
                                  ? List<Map<String, dynamic>>.from(result['episodes']) 
                                  : null,
                              );
                            });
                          }
                        },
                      );
                    },
                  ),
                ListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  leading: Icon(Icons.report_problem_rounded, color: AppColors.textPrimary, size: iconSize),
                  title: Text('Report Video', style: AppTypography.bodyMedium.copyWith(fontSize: titleSize)),
                  onTap: () {
                    Navigator.pop(context);
                    _openReportDialog();
                  },
                ),
                StatefulBuilder(
                  builder: (context, setStateSB) => ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    leading: Icon(_isDubbingProgressVisible ? Icons.visibility_rounded : Icons.visibility_off_rounded, color: AppColors.textPrimary, size: iconSize),
                    title: Text('Dubbing Progress', style: AppTypography.bodyMedium.copyWith(fontSize: titleSize)),
                    trailing: Switch(
                      value: _isDubbingProgressVisible,
                      activeColor: AppColors.primary,
                      onChanged: (val) {
                        setStateSB(() => _isDubbingProgressVisible = val);
                        setState(() {});
                      },
                    ),
                    onTap: () {
                      setStateSB(() => _isDubbingProgressVisible = !_isDubbingProgressVisible);
                      setState(() {});
                    },
                  ),
                ),
                if (!isLandscape) const SizedBox(height: 12),
              ],
            ),
    );
  }

  void _openReportDialog() {
    final video = _videos[_currentIndex];
    VayuBottomSheet.show(
      context: context,
      title: 'Report Content',
      icon: Icons.report_problem_outlined,
      child: ReportDialogWidget(
        targetType: 'video',
        targetId: video.id,
      ),
    );
  }

  Future<void> _showPlaybackSpeedOptions() async {
    if (!mounted) return;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    await VayuBottomSheet.show<void>(
      context: context, 
      title: 'Playback speed',
      maxWidth: isLandscape ? 380.0 : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _playbackSpeedOptions.map((speed) {
          final isSelected = speed == _playbackSpeed;
          return ListTile(
            dense: true, 
            visualDensity: VisualDensity.compact,
            title: Text(_formatPlaybackSpeed(speed), style: TextStyle(
              fontSize: isLandscape ? 12.0 : null,
              color: isSelected ? AppColors.primary : AppColors.textPrimary, 
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
            )),
            onTap: () { Navigator.pop(context); _setPlaybackSpeed(speed); },
          );
        }).toList(),
      ),
    );
  }

  void _onPageChanged(int index) {
    if (index == _currentIndex) return;
    
    _pauseCurrentVideo();
    _reprimeWindowIfNeeded(index);
    _stopViewTracking(_currentIndex);
    
    setState(() {
      _currentIndex = index;
    });

    // **NEW: Persist current video index for Vayu Tab (index 1)**
    ref.read(mainControllerProvider).updateCurrentVideoIndex(index, tabIndex: 1);

    _startViewTracking(index);
    _preloadNearbyVideos();
    _initializePlayer(index);
    _loadBannerAd(index);

    if (_videos.length - index < 3) {
      _loadMoreVideos();
    }
  }

  void _reprimeWindowIfNeeded(int current) {
    // Keep window of +/- 1 for long form videos (memory expensive)
    final keys = _controllers.keys.where((i) => (i - current).abs() > 1).toList();
    if (keys.isEmpty) return;

    for (final i in keys) {
       _savePlaybackPosition(i);
       final videoId = _videos[i].id;
       
       // Dispose locally
       final controller = _controllers.remove(i);
       final chewie = _chewieControllers.remove(i);
       
       if (controller != null) {
         _controllerPool.disposeController(videoId);
       }
       chewie?.dispose();
    }
  }

  void _validateAndRestoreControllers() {
    if (_videos.isEmpty) return;
    
    // Check if current controller is still valid
    final video = _videos[_currentIndex];
    if (!_controllers.containsKey(_currentIndex) || 
        _controllerPool.getController(video.id) == null) {
      _initializePlayer(_currentIndex);
    }
  }

  void _preloadNearbyVideos() {
    if (_currentIndex + 1 < _videos.length) _preloadVideo(_currentIndex + 1);
    if (_currentIndex - 1 >= 0) _preloadVideo(_currentIndex - 1);
  }

  Future<void> _preloadVideo(int index) async {
    if (index < 0 || index >= _videos.length) return;
    if (_controllers.containsKey(index)) return;
    
    final video = _videos[index];
    // Don't preload if already in pool
    if (_controllerPool.hasController(video.id)) return;

    try {
      final controller = await VideoControllerFactory.createController(video);
      await controller.initialize();
      _controllers[index] = controller;
      _controllerPool.addController(video.id, controller, index: index);
    } catch (e) {
      AppLogger.log('Failed to preload vayu video: $e');
    }
  }

  void _enableWakelock() { if (!_wakelockEnabled) { WakelockPlus.enable(); _wakelockEnabled = true; } }
  void _disableWakelock() { if (_wakelockEnabled) { WakelockPlus.disable(); _wakelockEnabled = false; } }

  String _formatDuration(Duration duration) {
    String two(int n) => n.toString().padLeft(2, '0');
    final minutes = two(duration.inMinutes.remainder(60));
    final seconds = two(duration.inSeconds.remainder(60));
    return duration.inHours > 0 ? '${duration.inHours}:${two(duration.inMinutes.remainder(60))}:$seconds' : '$minutes:$seconds';
  }

  String _formatPlaybackSpeed(double speed) => speed == speed.roundToDouble() ? '${speed.toInt()}x' : '${speed.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}x';
  String _compactTitle(String t, {required int maxChars}) => t.length <= maxChars ? t : '${t.substring(0, maxChars).trimRight()}...';

  Widget _buildOverlayControlButton({required Widget icon, required VoidCallback onPressed, String? tooltip}) => SizedBox(width: _controlTouchSize, height: _controlTouchSize, child: IconButton(iconSize: _controlIconSize, tooltip: tooltip, onPressed: onPressed, icon: icon, padding: EdgeInsets.zero));

  String _sanitizeUrl(String url) {
    if (url.isEmpty) return url;
    final trimmed = url.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return 'https://$trimmed';
    }
    return trimmed;
  }

  Future<void> _loadBannerAd(int index) async {
    if (_bannerAdsByIndex.containsKey(index)) return;
    try {
      final ads = await _activeAdsService.fetchActiveAds();
      if (mounted) {
        setState(() {
          final List? bannerAds = ads['banner'] as List?;
          if (bannerAds != null && bannerAds.isNotEmpty) {
            final firstAd = bannerAds.first;
            if (firstAd is Map) {
              _bannerAdsByIndex[index] = Map<String, dynamic>.from(firstAd);
            }
          }
        });
      }
    } catch (e) { AppLogger.log('❌ Error loading banner ad for index $index: $e'); }
  }

  void _onLocalSmartDubTap(VideoModel video, [String targetLang = 'hindi']) async {
    final videoId = video.id;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final currentResult = _dubbingResultsVN[videoId]?.value;
    // ... previous checks ...
    if (currentResult != null && !currentResult.isDone && currentResult.status != DubbingStatus.idle) {
      // User tapped while dubbing is in progress -> Ask to Cancel
      final bool? cancel = await VayuBottomSheet.show<bool>(
        context: context,
        title: 'Cancel Dubbing?',
        icon: Icons.cancel_outlined,
        iconColor: Colors.red,
        maxWidth: isLandscape ? 360.0 : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Are you sure you want to cancel the AI Dubbing process for this video?',
              style: AppTypography.bodyMedium.copyWith(
                fontSize: isLandscape ? 13.0 : null,
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    onPressed: () => Navigator.pop(context, false),
                    label: 'No',
                    variant: AppButtonVariant.secondary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: AppButton(
                    onPressed: () => Navigator.pop(context, true),
                    label: 'Yes, Cancel',
                    variant: AppButtonVariant.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

      if (cancel == true) {
        _onDeviceDubbingService.cancelDubbing(video.videoUrl);
        _dubbingSubscriptions[videoId]?.cancel();
        _dubbingResultsVN[videoId]?.value = const DubbingResult(status: DubbingStatus.idle);
        _showSnackBar('Dubbing cancelled.');
      }
      return;
    }

    setState(() => _isDubbingProgressVisible = true);
    _showSnackBar('Dubbing started for ${targetLang.toUpperCase()}...');
    final resultVN = _getOrCreateNotifier<DubbingResult>(_dubbingResultsVN, videoId, const DubbingResult(status: DubbingStatus.checking));
    _dubbingSubscriptions[videoId]?.cancel();
    
    final sub = _onDeviceDubbingService.dubLocalVideo(video.videoUrl, targetLang: targetLang).listen((result) {
      if (!mounted) return;
      resultVN.value = result;
      if (result.status == DubbingStatus.completed) {
        _showSnackBar('Dubbing completed successfully!');
        if (result.dubbedUrl != null) {
          final vIndex = _videos.indexWhere((v) => v.id == videoId);
          if (vIndex != -1) {
            final currentDubbedUrls = Map<String, String>.from(_videos[vIndex].dubbedUrls ?? {});
            final String lang = result.language ?? targetLang; 
            currentDubbedUrls[lang] = result.dubbedUrl!;
            setState(() { 
              _videos[vIndex] = _videos[vIndex].copyWith(dubbedUrls: currentDubbedUrls); 
              
              if (vIndex == _currentIndex && mounted) {
                _selectedAudioLanguage[videoId] = lang;
                _controllerPool.disposeController(videoId);
                _initializePlayer(_currentIndex);
              }
            });
          }
        }
      } else if (result.status == DubbingStatus.failed) {
        if (mounted && result.error?.contains('Cancelled') != true) {
          _showSnackBar('AI Dubbing failed: ${result.error ?? "Unknown error"}');
        }
      }
    });
    _dubbingSubscriptions[videoId] = sub;
  }

  ValueNotifier<T> _getOrCreateNotifier<T>(Map<String, ValueNotifier<T>> map, String key, T initialValue) {
    if (!map.containsKey(key)) { map[key] = ValueNotifier<T>(initialValue); }
    return map[key]!;
  }

  void _showLanguageSelector(BuildContext context, VideoModel video) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final hasEnglishDub = video.dubbedUrls?.containsKey('english') ?? false;
    final hasHindiDub = video.dubbedUrls?.containsKey('hindi') ?? false;
    final String detectedSource = hasEnglishDub ? 'Hindi' : (hasHindiDub ? 'English' : 'Original');

    VayuBottomSheet.show<void>(
      context: context, 
      title: 'Audio Language',
      maxWidth: isLandscape ? 380.0 : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLanguageOption(context, video, '$detectedSource (Original)', 'default', badge: 'Original'),
          _buildLanguageOption(context, video, 'English', 'english', badge: hasEnglishDub ? 'Dubbed' : null, available: hasEnglishDub),
          _buildLanguageOption(context, video, 'Hindi', 'hindi', badge: hasHindiDub ? 'Dubbed' : null, available: hasHindiDub),
        ],
      ),
    );
  }

  Widget _buildLanguageOption(BuildContext context, VideoModel video, String title, String langCode, {String? badge, bool available = true}) {
    final String currentSelected = _selectedAudioLanguage[video.id] ?? 'default';
    final bool isSelected = currentSelected == langCode;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Row(children: [
        Text(title, style: TextStyle(
          fontSize: isLandscape ? 13.0 : null,
          color: isSelected ? AppColors.primary : AppColors.textPrimary, 
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
        )),
        if (badge != null) ...[const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text(badge, style: const TextStyle(fontSize: 10, color: AppColors.primary)))]
      ]),
      trailing: isSelected ? const Icon(Icons.check, color: AppColors.primary) : (!available ? Icon(Icons.psychology_outlined, color: AppColors.textTertiary, size: isLandscape ? 16 : 16) : null),
      onTap: () { 
        Navigator.pop(context); 
        if (available || langCode == 'default') {
          _handleLanguageSelection(video, langCode); 
        } else {
          _onLocalSmartDubTap(video, langCode); 
        }
      },
    );
  }

  void _handleLanguageSelection(VideoModel video, String langCode) {
    if (_selectedAudioLanguage[video.id] == langCode) return;
    
    // Proactively dispose the controller to ensure the new URL is used
    _controllerPool.disposeController(video.id);
    
    setState(() { 
      _selectedAudioLanguage[video.id] = langCode; 
      _initializePlayer(_currentIndex); 
    });
  }


  Widget _buildScrubbingOverlay() {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return Align(
      alignment: _isForward ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: isLandscape ? 60 : 40),
        child: Column(
          mainAxisSize: MainAxisSize.min, 
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isLandscape ? Colors.black54 : Colors.transparent, 
                borderRadius: BorderRadius.circular(100),
              ), 
              child: Row(
                mainAxisSize: MainAxisSize.min, 
                children: [
                  Icon(
                    _isForward ? Icons.keyboard_double_arrow_right_rounded : Icons.keyboard_double_arrow_left_rounded, 
                    color: Colors.white, 
                    size: isLandscape ? 32 : 24,
                    shadows: !isLandscape ? const [Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))] : null,
                  ),
                  SizedBox(width: isLandscape ? 12 : 8),
                  Text(
                    '${_isForward ? "+" : ""}${_scrubbingDelta.inSeconds.abs()}s', 
                    style: TextStyle(
                      color: Colors.white, 
                      fontSize: isLandscape ? 24 : 16, 
                      fontWeight: FontWeight.bold,
                      shadows: !isLandscape ? const [Shadow(color: Colors.black45, blurRadius: 4, offset: Offset(0, 2))] : null,
                    )
                  ),
                ]
              )
            ),
          ]
        ),
      )
    );
  }



  @override
  Widget build(BuildContext context) {
    if (_videos.isEmpty) return const Scaffold(backgroundColor: AppColors.backgroundPrimary, body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return PopScope(
      canPop: !isLandscape,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isLandscape) {
          _toggleFullScreen();
        } else if (didPop) {
          ref.read(mainControllerProvider).setBottomNavVisibility(true);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        body: Stack(children: [
          PageView.builder(
            controller: _pageController,
            physics: _isScrollingLocked 
                ? const NeverScrollableScrollPhysics() 
                : const BouncingScrollPhysics(),
            scrollDirection: Axis.vertical,
            onPageChanged: _onPageChanged,
            itemCount: _videos.length,
            itemBuilder: (context, index) => SafeArea(
              top: !isLandscape,
              left: false,
              right: false,
              bottom: false, 
              child: _buildFeedItem(index)
            ),
          ),
          if (!_hasSeenScrollHint) Positioned(bottom: isLandscape ? 80 : 140, left: 0, right: 0, child: IgnorePointer(child: AnimatedOpacity(opacity: _showScrollHintOverlay ? 1.0 : 0.0, duration: const Duration(milliseconds: 500), child: Center(child: Container(padding: EdgeInsets.symmetric(horizontal: isLandscape ? 24 : 24, vertical: isLandscape ? 12 : 12), decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(isLandscape ? 30 : 30)), child: Text('Swipe up to watch more', style: TextStyle(color: Colors.white, fontSize: isLandscape ? 16 : 16, fontWeight: FontWeight.w600))))))),
        ]),
      ),
    );
  }

  Widget _buildFeedItem(int index) => VayuFeedItem(
    key: ValueKey('feed_${index}_${_videos[index].id}'),
    index: index, video: _videos[index], controller: _controllers[index], chewie: _chewieControllers[index],
    isCurrent: index == _currentIndex, isFullScreenManual: _isFullScreenManual, showControls: _showControls,
    isControlsLocked: _isControlsLocked, showScrubbingOverlay: _showScrubbingOverlay,
    onToggleFullScreen: _toggleFullScreen, onOpenExternalPlayer: () => _openInExternalPlayer(_videos[index]),
    onHandleTap: _handleTap, onDoubleTapToSeek: _handleDoubleTapToSeek,    onHorizontalDragEnd: _handleHorizontalDragEnd,
    onVerticalDragUpdate: _handleVerticalDragUpdate, onVerticalDragEnd: _handleVerticalDragEnd, 
    onUnifiedHorizontalDrag: _handleUnifiedHorizontalDrag,
    onScrollingLock: (locked) {
      if (mounted) setState(() => _isScrollingLocked = locked);
    },
    onShowSnackBar: _showSnackBar,
    activeQuiz: index == _currentIndex ? _activeQuiz : null,
    onQuizDismiss: () {
      if (mounted) setState(() => _activeQuiz = null);
    },
    onQuizBack: () {
      if (_activeQuizHistory.length > 1) {
        setState(() {
          _activeQuizHistory.removeLast(); // Remove current
          _activeQuiz = _activeQuizHistory.last; // Show previous
        });
      }
    },
    buildAdSection: _buildAdSection, 
    buildVideoInfo: _buildVideoInfo, buildChannelRow: _buildChannelRow,
    buildScrubbingOverlay: _buildScrubbingOverlay,
    buildCustomControls: _buildCustomControls, formatDuration: _formatDuration,
    buildDubbingProgress: _buildDubbingProgress,
  );


  Widget _buildVideoInfo(int index) {
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final v = _videos[index];
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: AppSpacing.spacing3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
      Text(_compactTitle(v.videoName, maxChars: 80), style: AppTypography.bodyLarge.copyWith(color: Theme.of(context).brightness == Brightness.dark ? AppColors.textPrimary : Colors.black87, fontWeight: FontWeight.bold, height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
      if (v.tags != null && v.tags!.isNotEmpty) ...[
        SizedBox(height: isPortrait ? 8 : 8),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Wrap(
            spacing: isPortrait ? 6 : 6,
            runSpacing: isPortrait ? 4 : 4,
            children: v.tags!.map((tag) => Text(
              '#$tag',
              style: TextStyle(
                color: AppColors.primary,
                fontSize: isPortrait ? 12 : 12,
                fontWeight: FontWeight.w500,
              ),
            )).toList(),
          ),
        ),
      ],
      const SizedBox(height: 12),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Views and Time
            Text(
              '${FormatUtils.formatViews(v.views)} views • ${FormatUtils.formatTimeAgo(v.uploadedAt)}', 
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary, 
                fontSize: isPortrait ? 11 : 12,
                fontWeight: FontWeight.w500,
              )
            ),
            const SizedBox(width: 10), // Spacing between views and buttons
            
            // Action Buttons
            if (v.link?.isNotEmpty == true) 
              _buildActionButton(
                context,
                icon: Icon(Icons.open_in_new_rounded, color: AppColors.textSecondary, size: isPortrait ? 18 : 20),
                onPressed: () async {
                  final sanitized = _sanitizeUrl(v.link!);
                  final url = Uri.parse(sanitized);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    _showSnackBar('Could not open link', type: VayuSnackBarType.error);
                  }
                },
                tooltip: 'Visit Now',
              ),
            _buildActionButton(
              context,
              icon: Icon(Icons.share_outlined, color: AppColors.textSecondary, size: isPortrait ? 18 : 20),
              onPressed: () => _showShareOptions(v),
              tooltip: 'Share',
            ),
            _buildActionButton(
              context,
              icon: Icon(Icons.tips_and_updates_outlined, color: AppColors.textSecondary, size: isPortrait ? 18 : 20),
              onPressed: () => _showShareSuggestionBottomSheet(v),
              tooltip: 'Share Suggestion',
            ),
            _buildActionButton(
              context,
              icon: Icon(
                v.isSaved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded, 
                color: v.isSaved ? AppColors.primary : AppColors.textSecondary, 
                size: isPortrait ? 18 : 20,
              ),
              onPressed: () => _handleToggleSave(index),
              tooltip: v.isSaved ? 'Saved' : 'Save',
            ),
            if (v.episodes != null && v.episodes!.isNotEmpty) 
              _buildActionButton(
                context,
                icon: Icon(Icons.playlist_play_rounded, color: AppColors.textSecondary, size: isPortrait ? 18 : 20),
                onPressed: () => _showEpisodeList(context, v),
                tooltip: 'Episodes',
              ),
            const SizedBox(width: 12), // End padding for comfortable scrolling
          ],
        ),
      ),
    ]));
  }

  Widget _buildActionButton(BuildContext context, {
    required Widget icon,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.05),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                if (tooltip != null && (tooltip == 'Visit Now' || tooltip == 'Episodes')) ...[
                  const SizedBox(width: 4),
                  Text(
                    tooltip,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdSection(int index) {
    final ad = _bannerAdsByIndex[index];
    if (ad == null) return const SizedBox.shrink();
    
    final userData = ref.read(googleSignInProvider).userData;
    final userId = userData?['id'] ?? userData?['googleId'] ?? 'anonymous';
    
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: AppSpacing.spacing3,
      ),
      child: BannerAdSection(
        adData: {...ad, 'creatorId': _videos[index].uploader.id}, 
        onVideoPause: () => _controllers[index]?.pause(), 
        onVideoResume: () => _controllers[index]?.play(),
        onImpression: () async {
          final adId = ad['id'] ?? ad['_id'];
          if (adId != null) {
            await _adImpressionService.trackBannerAdImpression(
              videoId: _videos[index].id,
              adId: adId.toString(),
              userId: userId.toString(),
            );
          }
        },
      ),
    );
  }

  Widget _buildChannelRow(int index) {
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final v = _videos[index];
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: AppSpacing.spacing3,
      ),
      child: Row(
        children: [
      InteractiveScaleButton(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => ProfileScreen(userId: v.uploader.id))), child: CircleAvatar(radius: isPortrait ? 18 : 18, backgroundImage: v.uploader.profilePic.isNotEmpty ? CachedNetworkImageProvider(v.uploader.profilePic) : null, backgroundColor: AppColors.backgroundSecondary, child: v.uploader.profilePic.isEmpty ? const Icon(Icons.person_rounded, color: Colors.white, size: 21) : null)),
      SizedBox(width: isPortrait ? 10 : 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(v.uploader.name, style: AppTypography.bodyMedium.copyWith(color: Theme.of(context).brightness == Brightness.dark ? AppColors.textPrimary : Colors.black87, fontWeight: FontWeight.bold), maxLines: 1), if (v.uploader.totalVideos != null) Text('${v.uploader.totalVideos} videos', style: AppTypography.bodySmall.copyWith(color: Theme.of(context).brightness == Brightness.dark ? AppColors.textSecondary : Colors.black54, fontSize: isPortrait ? 10 : 10))])),
      FollowButtonWidget(uploaderId: v.uploader.id, uploaderName: v.uploader.name),
    ]));
  }

  Widget _buildCustomControls(int index) {
    final controller = _controllers[index];
    if (controller == null) return const SizedBox.shrink();
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final isFull = !isPortrait || _isFullScreenManual;
    final viewPadding = MediaQuery.of(context).viewPadding;
    final sidePadding = isPortrait ? 14.0 : 20.0;
    final horizontalPadding = isFull ? 60.0 : 14.0;
    
    return Stack(children: [
      // TOP SCRIM (Consistent visibility for top controls)
      Positioned(
        top: 0, left: 0, right: 0,
        height: 60,
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.75),
                  Colors.black.withOpacity(0.40),
                  Colors.black.withOpacity(0.15),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.4, 0.8, 1.0],
              ),
            ),
          ),
        ),
      ),
      
      // Top Controls (More menu)
      Positioned(
        top: 0, right: 0, left: 0,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            isPortrait ? sidePadding : horizontalPadding, 
            isPortrait ? 8 : (viewPadding.top + 8), 
            isPortrait ? sidePadding : horizontalPadding, 
            0
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 30), // Balance
              IconButton(
                constraints: const BoxConstraints(),
                icon: Icon(
                  Icons.more_vert_rounded, 
                  color: Colors.white, 
                  size: isPortrait ? 26 : 30,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                onPressed: _showMoreOptions,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black.withOpacity(0.55), 
                  padding: EdgeInsets.zero,
                  fixedSize: Size(isPortrait ? 26 : 30, isPortrait ? 26 : 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
      ),
      
      // BOTTOM SCRIM (Consistent visibility for progress bar area)
      Positioned(
        bottom: 0, left: 0, right: 0,
        height: 80,
        child: IgnorePointer(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [
                  Colors.black.withOpacity(0.65),
                  Colors.black.withOpacity(0.45),
                  Colors.black.withOpacity(0.20),
                  Colors.transparent,
                ],
                stops: const [0.0, 0.4, 0.8, 1.0],
              ),
            ),
          ),
        ),
      ),

      // Center Controls (Skip/Play/Skip)
      if (!_isControlsLocked) 
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!isPortrait) ...[
                InteractiveScaleButton(
                  onTap: _previousVideo,
                  child: Container(
                    width: 38, height: 38,
                    decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
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
              SizedBox(
                width: 50, height: 50,
                child: InteractiveScaleButton(
                  onTap: _togglePlay,
                  child: Container(
                    decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                    child: Icon(
                      controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, 
                      color: Colors.white, 
                      size: 50,
                      shadows: const [
                        Shadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 2)),
                      ],
                    ),
                  ),
                ),
              ),
              if (!isPortrait) ...[
                const SizedBox(width: 42),
                InteractiveScaleButton(
                  onTap: _nextVideo,
                  child: Container(
                    width: 38, height: 38,
                    decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
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
    ]);
  }

  // Dubbing Progress Overlay - REMOVED from here to be moved outside video stack
  Widget _buildDubbingProgress(int index) {
    if (!_isDubbingProgressVisible) return const SizedBox.shrink();
    final videoId = _videos[index].id;
    return ValueListenableBuilder<DubbingResult>(
      valueListenable: _getOrCreateNotifier<DubbingResult>(_dubbingResultsVN, videoId, const DubbingResult(status: DubbingStatus.idle)),
      builder: (context, result, _) {
        if (result.status == DubbingStatus.idle || result.isDone) {
          return const SizedBox.shrink();
        }

        final progressValue = result.progress / 100.0;
        final statusText = result.statusLabel;
        final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
        
        final horizontalMargin = isLandscape ? 32.0 : 16.0;
        final bottomMargin = isLandscape ? 48.0 : 12.0; // Higher in landscape to stay above progress bar
        
        return Center(
          child: Container(
            constraints: BoxConstraints(maxWidth: isLandscape ? MediaQuery.of(context).size.width * 0.5 : double.infinity),
            margin: EdgeInsets.fromLTRB(horizontalMargin, 0, horizontalMargin, bottomMargin),
            padding: EdgeInsets.symmetric(horizontal: isLandscape ? 12.0 : 12.0, vertical: isLandscape ? 8.0 : 10.0),
            decoration: BoxDecoration(
              color: isLandscape ? Colors.black87 : AppColors.backgroundSecondary.withOpacity(0.9),
              borderRadius: BorderRadius.circular(isLandscape ? 12 : 12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(color: AppColors.primary.withOpacity(0.2), width: 1),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _showCancelDubbingDialog(videoId),
                        behavior: HitTestBehavior.opaque,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    'AI Dubbing: $statusText',
                                    style: TextStyle(
                                      color: isLandscape ? Colors.white : AppColors.textPrimary, 
                                      fontSize: isLandscape ? 12.0 : 12, 
                                      fontWeight: FontWeight.bold
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                  const SizedBox(width: 16),
                                Text(
                                  '${result.progress}%',
                                  style: TextStyle(
                                    color: AppColors.primary, 
                                    fontSize: isLandscape ? 12.0 : 12, 
                                    fontWeight: FontWeight.bold
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(isLandscape ? 4 : 4),
                              child: LinearProgressIndicator(
                                value: progressValue,
                                backgroundColor: isLandscape ? Colors.white24 : AppColors.borderPrimary,
                                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                                minHeight: isLandscape ? 4.0 : 4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    GestureDetector(
                      onTap: () => setState(() => _isDubbingProgressVisible = false),
                      child: Text(
                        'Hide',
                        style: TextStyle(
                          color: isLandscape ? Colors.white : AppColors.primary,
                          fontSize: isLandscape ? 12.0 : 12,
                          fontWeight: FontWeight.bold,
                          decoration: TextDecoration.underline,
                          decorationColor: isLandscape ? Colors.white.withOpacity(0.5) : AppColors.primary.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCancelDubbingDialog(String videoId) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    VayuBottomSheet.show<void>(
      context: context,
      title: 'Dubbing',
      maxWidth: isLandscape ? 380.0 : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Aap dubbing cancel karna chahte hain?',
            style: AppTypography.bodyLarge.copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w500,
              fontSize: isLandscape ? 12.0 : null,
            ),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: isLandscape ? 12 : 20),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  onPressed: () => Navigator.pop(context),
                  label: 'Nahi',
                  variant: AppButtonVariant.secondary,
                  size: isLandscape ? AppButtonSize.small : AppButtonSize.medium,
                  fontSize: isLandscape ? 11.0 : null, // Stable size in landscape
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  onPressed: () {
                    Navigator.pop(context);
                    final video = _videos.firstWhere((v) => v.id == videoId);
                    _onDeviceDubbingService.cancelDubbing(video.videoUrl);
                    _dubbingSubscriptions[videoId]?.cancel();
                    _dubbingResultsVN[videoId]?.value = const DubbingResult(status: DubbingStatus.idle);
                    if (mounted) {
                      _showSnackBar('Dubbing cancelled.');
                    }
                  },
                  label: isLandscape ? 'Haan' : 'Haan, Cancel Karein', // Shorter text for landscape
                  size: isLandscape ? AppButtonSize.small : AppButtonSize.medium,
                  fontSize: isLandscape ? 11.0 : null, // Stable size in landscape
                ),
              ),
            ],
          ),
          SizedBox(height: isLandscape ? 4 : 8),
        ],
      ),
    );
  }
}

enum GestureType { none, horizontal, vertical, scale }

class VayuFeedItem extends ConsumerStatefulWidget {
  final int index;
  final VideoModel video;
  final VideoPlayerController? controller;
  final ChewieController? chewie;
  final bool isCurrent;
  final bool isFullScreenManual;
  final bool showControls;
  final bool isControlsLocked;
  final bool showScrubbingOverlay;
  final VoidCallback onToggleFullScreen;
  final VoidCallback onOpenExternalPlayer;
  final VoidCallback onHandleTap;
  final void Function(TapDownDetails) onDoubleTapToSeek;
  final VoidCallback onHorizontalDragEnd;
  final void Function(DragUpdateDetails) onVerticalDragUpdate;
  final VoidCallback onVerticalDragEnd;
  final void Function(double) onUnifiedHorizontalDrag;
  final void Function(bool) onScrollingLock; // **NEW: Callback to lock/unlock parent scroll**
  final void Function(String) onShowSnackBar; // **NEW: Callback for SnackBars**
  final Widget Function(int) buildAdSection;
  final Widget Function(int) buildVideoInfo;
  final Widget Function(int) buildChannelRow;
  final Widget Function() buildScrubbingOverlay;
  final Widget Function(int) buildCustomControls;
  final Widget Function(int) buildDubbingProgress;
  final String Function(Duration) formatDuration;
  final QuizModel? activeQuiz;
  final VoidCallback onQuizDismiss;
  final VoidCallback? onQuizBack;

  const VayuFeedItem({
    super.key, required this.index, required this.video, this.controller, this.chewie,
    required this.isCurrent, required this.isFullScreenManual, required this.showControls,
    required this.isControlsLocked, required this.showScrubbingOverlay,
    required this.onToggleFullScreen,
    required this.onHandleTap, required this.onDoubleTapToSeek, required this.onHorizontalDragEnd,
    required this.onVerticalDragUpdate, required this.onVerticalDragEnd,    required this.onUnifiedHorizontalDrag,
    required this.onScrollingLock, // **NEW: Required callback**
    required this.onShowSnackBar, // **NEW: Required callback**
    required this.buildAdSection,
    required this.buildVideoInfo, required this.buildChannelRow,
    required this.buildScrubbingOverlay,
    required this.buildCustomControls, required this.buildDubbingProgress, 
    required this.formatDuration,
    required this.onOpenExternalPlayer,
    this.activeQuiz,
    this.onQuizBack,
    required this.onQuizDismiss,
  });

  @override
  ConsumerState<VayuFeedItem> createState() => _VayuFeedItemState();
}

class _VayuFeedItemState extends ConsumerState<VayuFeedItem> {
  double _scale = 1.0;
  Offset _offset = Offset.zero;
  double _baseScale = 1.0;
  int _pointers = 0;
  bool _isScaling = false;

  // Gesture tracking
  GestureType _activeGesture = GestureType.none;
  double _dragHorizontalDeltaAccumulated = 0;
  double _dragVerticalDeltaAccumulated = 0;
  static const double _gestureThreshold = 12.0;

  @override
  Widget build(BuildContext context) {
    final orientation = MediaQuery.of(context).orientation;
    final isFull = orientation == Orientation.landscape || widget.isFullScreenManual;
    if (isFull) {
      return Stack(
        children: [
          _buildVideoSection(orientation),
          Positioned(
            bottom: isFull ? 40 : 40, // Above the video progress bar
            left: 0, right: 0,
            child: widget.buildDubbingProgress(widget.index),
          ),
        ],
      );
    }
    return Column(children: [
      _buildVideoSection(orientation),
      Expanded(
        child: SingleChildScrollView(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing4),
            child: Column(
              children: [
              widget.buildAdSection(widget.index),
              widget.buildVideoInfo(widget.index),
              widget.buildChannelRow(widget.index),
              if (widget.activeQuiz != null)
                Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: AppSpacing.spacing3,
                  ),
                  child: QuizOverlay(
                    quiz: widget.activeQuiz!,
                    onDismiss: widget.onQuizDismiss,
                    onBack: (widget.onQuizBack != null) ? widget.onQuizBack : null,
                    onAnswered: (idx) {},
                  ),
                ),
              widget.buildDubbingProgress(widget.index),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
   ) ]);
  }

  Widget _buildVideoSection(Orientation orientation) {
    final size = MediaQuery.of(context).size;
    final controller = widget.controller;
    final chewie = widget.chewie;
    
    // **SAFE INITIALIZATION CHECK**
    final sharedPool = SharedVideoControllerPool();
    bool controllerIsHealthy = false;
    try {
      if (controller != null && !sharedPool.isControllerDisposed(controller)) {
        controllerIsHealthy = controller.value.isInitialized;
      }
    } catch (_) {
      controllerIsHealthy = false;
    }

    final isFull = orientation == Orientation.landscape || widget.isFullScreenManual;
    final isPortrait = orientation == Orientation.portrait;
    
    // Calculate stable symmetrical padding for horizontal mode
    // Correct: Using 60.0 ONLY in true landscape orientation. In portrait, even if manually expanded, use 14.0.
    final lateralPadding = orientation == Orientation.landscape ? 60.0 : 14.0;
        
    final videoHeight = isPortrait && !isFull ? size.width * 9 / 16 : size.height;

    List<Widget> stackChildren(bool full) => [
      if (chewie != null && controller != null && controllerIsHealthy)
        Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..translate(_offset.dx, _offset.dy)
            ..scale(_scale),
          child: SizedBox.expand(
            child: FittedBox(
              fit: BoxFit.contain,
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: Chewie(controller: chewie),
              ),
            ),
          ),
        ),
      
      // Buffering Feedback
      if (controller != null && controllerIsHealthy)
        Center(
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder: (context, v, _) => v.isBuffering 
                ? const SizedBox(width: 44, height: 44, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                : const SizedBox.shrink(),
          ),
        )
      else Container(color: Colors.black, child: const Center(child: CircularProgressIndicator())),

      Positioned.fill(
        child: Listener(
          onPointerDown: (e) {
            _pointers++;
            widget.onScrollingLock(true); // Lock parent scroll
          },
          onPointerUp: (e) {
            if (_pointers > 0) _pointers--;
            if (_pointers == 0) widget.onScrollingLock(false); // Unlock
          },
          onPointerCancel: (e) {
            if (_pointers > 0) _pointers--;
            if (_pointers == 0) widget.onScrollingLock(false); // Unlock
          },
          child: GestureDetector(
            onTap: () {
              // Tap Guard: If we just started a multi-finger operation, ignore single tap
              if (_pointers > 1) return;
              widget.onHandleTap();
            },
            onDoubleTapDown: widget.onDoubleTapToSeek,
            onScaleStart: (d) {
              if (widget.isControlsLocked) return;
              
              // NEW: Auto-hide controls when a pinch starts
              if (d.pointerCount >= 2 && widget.showControls) {
                widget.onHandleTap();
              }

              _baseScale = _scale;
              _isScaling = false;
              _activeGesture = GestureType.none;
              _dragHorizontalDeltaAccumulated = 0;
              _dragVerticalDeltaAccumulated = 0;
            },
            onScaleUpdate: (d) {
              if (widget.isControlsLocked) return;

              // 1. PINCH ZOOM (Requires 2+ pointers)
              if (d.pointerCount >= 2) {
                _isScaling = true;
                _activeGesture = GestureType.scale;
                setState(() {
                  _scale = (_baseScale * d.scale).clamp(1.0, 5.0);
                  _offset = Offset.zero; 
                });
                return;
              }

              // 2. SINGLE FINGER PAN (Seek / Vol / Brightness)
              if (d.pointerCount == 1 && !_isScaling) {
                final dx = d.focalPointDelta.dx;
                final dy = d.focalPointDelta.dy;

                // Determine gesture type if not already locked
                if (_activeGesture == GestureType.none) {
                  _dragHorizontalDeltaAccumulated += dx.abs();
                  _dragVerticalDeltaAccumulated += dy.abs();

                  if (_dragHorizontalDeltaAccumulated > _gestureThreshold || _dragVerticalDeltaAccumulated > _gestureThreshold) {
                    if (_dragHorizontalDeltaAccumulated > _dragVerticalDeltaAccumulated) {
                      _activeGesture = GestureType.horizontal;
                    } else {
                      _activeGesture = GestureType.vertical;
                    }
                    HapticFeedback.selectionClick();
                  }
                }

                // Execute locked gesture
                if (_activeGesture == GestureType.horizontal) {
                  widget.onUnifiedHorizontalDrag(dx);
                } else if (_activeGesture == GestureType.vertical) {
                  if (_scale == 1.0) {
                    widget.onVerticalDragUpdate(DragUpdateDetails(
                      localPosition: d.localFocalPoint,
                      globalPosition: d.focalPoint,
                      delta: Offset(0, dy),
                      primaryDelta: dy,
                    ));
                  }
                }
              }
            },
            onScaleEnd: (d) {
              if (_activeGesture == GestureType.horizontal) {
                widget.onHorizontalDragEnd();
              } else if (_activeGesture == GestureType.vertical) {
                widget.onVerticalDragEnd();
              }

              if (_scale <= 1.0) {
                setState(() { _scale = 1.0; _offset = Offset.zero; });
              }
              
              _isScaling = false;
              _activeGesture = GestureType.none;
            },
            behavior: HitTestBehavior.opaque,
          ),
        ),
      ),

      if (widget.isCurrent) ...[
        AnimatedOpacity(duration: const Duration(milliseconds: 200), opacity: widget.showControls ? 1.0 : 0.0, child: IgnorePointer(ignoring: !widget.showControls, child: widget.buildCustomControls(widget.index))),
        AnimatedOpacity(duration: const Duration(milliseconds: 150), opacity: widget.showScrubbingOverlay ? 1.0 : 0.0, child: IgnorePointer(ignoring: !widget.showScrubbingOverlay, child: widget.buildScrubbingOverlay())),
      ],

      if (controller != null && controllerIsHealthy && widget.isCurrent)
        Positioned(
          left: 0, 
          right: 0, 
          bottom: isFull ? 32.0 : 0.0, 
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Row: Duration and Buttons (Aligned on the same line)
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: widget.showControls ? 1.0 : 0.0,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: lateralPadding),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Duration text
                      Container(
                        height: 30,
                        padding: const EdgeInsets.symmetric(horizontal: 6), // Tightened from 10 to 6
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.40),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Center(
                          child: ValueListenableBuilder<VideoPlayerValue>(
                            valueListenable: controller,
                            builder: (context, v, _) => Text(
                              '${widget.formatDuration(v.position)} / ${widget.formatDuration(v.duration)}',
                              style: TextStyle(
                                color: Colors.white, 
                                fontSize: isFull ? 11.0 : 11, 
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      
                      // Buttons: Aspect Ratio and Full Screen
                      if (!widget.isControlsLocked) Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Cycle Aspect Ratio
                          IconButton(
                            constraints: const BoxConstraints(),
                            tooltip: 'External Player', 
                            onPressed: widget.onOpenExternalPlayer, 
                            icon: const Icon(Icons.play_circle_outline_rounded, color: Colors.white, size: 26),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black.withOpacity(0.12),
                              padding: EdgeInsets.zero,
                              fixedSize: const Size(30, 30),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 16),
                          // Toggle Full Screen
                          IconButton(
                            constraints: const BoxConstraints(),
                            tooltip: 'Full Screen', 
                            onPressed: widget.onToggleFullScreen, 
                            icon: Icon(isPortrait ? Icons.fullscreen_rounded : Icons.fullscreen_exit_rounded, color: Colors.white, size: 26),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.black.withOpacity(0.12),
                              padding: EdgeInsets.zero,
                              fixedSize: const Size(30, 30),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              
              if (isFull) const SizedBox(height: 7), // Gap only in fullscreen to minimize spacing in portrait
              
              // Progress Bar (Always visible in portrait, hides in landscape)
              AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: (!isFull || widget.showControls) ? 1.0 : 0.0,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: isFull ? lateralPadding : 0.0),
                  child: SizedBox(
                    height: 17,
                    child: VayuVideoProgressBar(
                      controller: controller, 
                      height: 17, 
                      barHeight: isFull ? 4 : 2,
                      activeBarHeight: isFull ? 10 : 4,
                      thumbRadius: isFull ? 8 : 4,
                      barCenterOffset: isFull ? null : 19,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
    ];

    return SizedBox(
      width: size.width, 
      height: videoHeight, 
      child: Container(
        color: AppColors.backgroundPrimary, 
        child: Stack(clipBehavior: Clip.none, children: stackChildren(false)),
      ),
    );
  }
}

