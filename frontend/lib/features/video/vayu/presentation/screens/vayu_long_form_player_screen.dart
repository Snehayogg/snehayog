import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:vayu/core/providers/auth_providers.dart';
import 'package:vayu/features/video/edit/presentation/screens/edit_video_details.dart';
import 'package:vayu/shared/widgets/report_dialog_widget.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayu/core/providers/navigation_providers.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:vayu/features/video/core/data/models/video_model.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'dart:async';
import 'package:vayu/features/video/core/data/services/video_service.dart';
import 'package:vayu/features/profile/presentation/screens/profile_screen.dart';
import 'dart:math' as math;
import 'package:vayu/features/video/dubbing/data/models/dubbing_models.dart';
import 'package:vayu/features/video/dubbing/data/services/on_device_dubbing_service.dart';
import 'package:vayu/shared/widgets/follow_button_widget.dart';
import 'package:vayu/core/design/colors.dart';
import 'package:vayu/shared/widgets/vayu_bottom_sheet.dart';
import 'package:vayu/core/design/radius.dart';
import 'package:vayu/core/design/typography.dart';
import 'package:vayu/shared/widgets/app_button.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayu/shared/factories/video_controller_factory.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:vayu/features/ads/data/services/active_ads_service.dart';
import 'package:vayu/features/video/feed/presentation/screens/video_feed_advanced/widgets/banner_ad_section.dart';
import 'package:vayu/shared/widgets/interactive_scale_button.dart';
import 'package:vayu/features/video/vayu/presentation/widgets/vayu_video_progress_bar.dart';
import 'package:vayu/shared/utils/format_utils.dart';
import 'package:vayu/features/video/core/presentation/managers/video_controller_manager.dart';
import 'package:vayu/features/video/core/presentation/managers/shared_video_controller_pool.dart';
import 'package:vayu/features/video/core/presentation/managers/main_controller.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

enum AspectRatioMode {
  fit,
  crop,
  stretch,
  ratio16x9,
}

class VayuLongFormPlayerScreen extends ConsumerStatefulWidget {
  final VideoModel video;
  final List<VideoModel> relatedVideos;

  const VayuLongFormPlayerScreen({
    Key? key,
    required this.video,
    this.relatedVideos = const [],
  }) : super(key: key);

  @override
  ConsumerState<VayuLongFormPlayerScreen> createState() =>
      _VayuLongFormPlayerScreenState();
}

class _VayuLongFormPlayerScreenState extends ConsumerState<VayuLongFormPlayerScreen>
    with WidgetsBindingObserver {
  static const _controlTouchSize = 42.0;
  static const _controlIconSize = 21.0;

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
  AspectRatioMode _aspectRatioMode = AspectRatioMode.fit;
  String? _aspectRatioOverlayText;
  Timer? _aspectRatioOverlayTimer;
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
        _mainController?.registerVideoPauseCallback(_pauseCurrentVideo);
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
          }
        } catch (_) {}
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
      if (c != null) _controllerPool.disposeController(videoToPlay.id);
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
    controller.addListener(_onPositionChanged);
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
    if (mounted) setState(() {});
    final controller = _controllers[_currentIndex];
    if (controller != null && controller.value.isPlaying && controller.value.position.inSeconds % 5 == 0) {
      _savePlaybackPosition(_currentIndex);
    }
  }

  @override
  void dispose() {
    _disableWakelock();
    WidgetsBinding.instance.removeObserver(this);
    
    // Safely unregister using captured controller reference
    _mainController?.unregisterCallbacks();
    
    // Save current position before cleaning up
    _savePlaybackPosition(_currentIndex);
    
    // Local cleanup: Stop playback but don't dispose shared controllers globally
    _controllers.forEach((index, c) {
      try {
        c?.pause();
        c?.setVolume(0.0);
      } catch (_) {}
    });
    
    _chewieControllers.forEach((index, c) => c?.dispose());
    
    _pageController.dispose();
    _controlsTimer?.cancel(); // Changed from _hideControlsTimer
    _overlayTimer?.cancel();
    _aspectRatioOverlayTimer?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    Future.microtask(() { if (context.mounted) ref.read(mainControllerProvider).setBottomNavVisibility(true); });
    super.dispose();
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

  void _showSnackBar(String message, {Duration? duration}) {
    if (!mounted) return;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500)),
        duration: duration ?? const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.surfacePrimary.withOpacity(0.9),
        width: isLandscape ? 340.0 : null, // Limit width in landscape
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 6,
      ),
    );
  }

  void _hideControlsWithDelay() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && _controllers[_currentIndex]?.value.isPlaying == true && _showControls) {
        setState(() => _showControls = false);
      }
    });
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
        _showSnackBar(isSaved ? 'Video saved to collection' : 'Video removed from collection', duration: const Duration(seconds: 2));
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
    
    final iconSize = isLandscape ? 20.0 : 20.0;
    final titleSize = isLandscape ? 14.0 : AppTypography.bodyMedium.fontSize;
    final trailingSize = isLandscape ? 12.0 : AppTypography.bodySmall.fontSize;
    
    await VayuBottomSheet.show<void>(
      context: context, 
      title: 'More Options',
      padding: isLandscape ? const EdgeInsets.symmetric(horizontal: 16, vertical: 8) : null,
      child: Align(
        alignment: Alignment.center,
        heightFactor: 1.0,
        child: Container(
          constraints: BoxConstraints(maxWidth: isLandscape ? 380.0 : double.infinity),
          child: SingleChildScrollView(
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
                if (!isLandscape) const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openReportDialog() {
    final video = _videos[_currentIndex];
    showDialog(
      context: context,
      builder: (context) => ReportDialogWidget(
        targetType: 'video', 
        targetId: video.id,
      ),
    );
  }

  Future<void> _showPlaybackSpeedOptions() async {
    if (!mounted) return;
    await VayuBottomSheet.show<void>(
      context: context, title: 'Playback speed',
      child: Align(
        alignment: Alignment.center,
        heightFactor: 1.0,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).orientation == Orientation.landscape ? 380.0 : double.infinity),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _playbackSpeedOptions.map((speed) {
                final isSelected = speed == _playbackSpeed;
                final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
                return ListTile(
                  dense: true, 
                  title: Text(_formatPlaybackSpeed(speed), style: TextStyle(
                    fontSize: isLandscape ? 14.0 : null,
                    color: isSelected ? AppColors.primary : AppColors.textPrimary, 
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
                  )),
                  onTap: () { Navigator.pop(context); _setPlaybackSpeed(speed); },
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }

  void _cycleAspectRatioMode() {
    const modes = AspectRatioMode.values;
    final next = modes[(modes.indexOf(_aspectRatioMode) + 1) % modes.length];
    setState(() { _aspectRatioMode = next; _showControls = true; _aspectRatioOverlayText = 'Aspect ratio: ${_aspectRatioLabel(next)}'; });
    _startHideControlsTimer();
    _aspectRatioOverlayTimer?.cancel();
    _aspectRatioOverlayTimer = Timer(const Duration(milliseconds: 1200), () { if (mounted) setState(() => _aspectRatioOverlayText = null); });
  }

  String _aspectRatioLabel(AspectRatioMode mode) {
    switch (mode) { case AspectRatioMode.fit: return 'Fit'; case AspectRatioMode.crop: return 'Crop'; case AspectRatioMode.stretch: return 'Stretch'; case AspectRatioMode.ratio16x9: return '16:9'; }
  }
  void _onPageChanged(int index) {
    if (index == _currentIndex) return;
    
    _pauseCurrentVideo();
    _reprimeWindowIfNeeded(index);
    
    setState(() {
      _currentIndex = index;
    });

    // **NEW: Persist current video index for Vayu Tab (index 1)**
    ref.read(mainControllerProvider).updateCurrentVideoIndex(index, tabIndex: 1);

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
    final currentResult = _dubbingResultsVN[videoId]?.value;
    // ... previous checks ...
    if (currentResult != null && !currentResult.isDone && currentResult.status != DubbingStatus.idle) {
      // User tapped while dubbing is in progress -> Ask to Cancel
      final bool? cancel = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AppColors.backgroundSecondary,
          title: const Text('Cancel Dubbing?', style: TextStyle(color: AppColors.textPrimary)),
          content: const Text('Are you sure you want to cancel the AI Dubbing process taking place for this video?', style: TextStyle(color: AppColors.textSecondary)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No', style: TextStyle(color: AppColors.textTertiary)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes, Cancel', style: TextStyle(color: Colors.red)),
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
    final hasEnglishDub = video.dubbedUrls?.containsKey('english') ?? false;
    final hasHindiDub = video.dubbedUrls?.containsKey('hindi') ?? false;
    final String detectedSource = hasEnglishDub ? 'Hindi' : (hasHindiDub ? 'English' : 'Original');

    VayuBottomSheet.show<void>(
      context: context, 
      title: 'Audio Language',
      child: Align(
        alignment: Alignment.center,
        heightFactor: 1.0,
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).orientation == Orientation.landscape 
                ? 380.0 
                : double.infinity
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildLanguageOption(context, video, '$detectedSource (Original)', 'default', badge: 'Original'),
              _buildLanguageOption(context, video, 'English', 'english', badge: hasEnglishDub ? 'Dubbed' : null, available: hasEnglishDub),
              _buildLanguageOption(context, video, 'Hindi', 'hindi', badge: hasHindiDub ? 'Dubbed' : null, available: hasHindiDub),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageOption(BuildContext context, VideoModel video, String title, String langCode, {String? badge, bool available = true}) {
    final String currentSelected = _selectedAudioLanguage[video.id] ?? 'default';
    final bool isSelected = currentSelected == langCode;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    
    return ListTile(
      dense: true,
      title: Row(children: [
        Text(title, style: TextStyle(
          fontSize: isLandscape ? 14.0 : null,
          color: isSelected ? AppColors.primary : AppColors.textPrimary, 
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal
        )),
        if (badge != null) ...[const SizedBox(width: 8), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(4)), child: Text(badge, style: const TextStyle(fontSize: 10, color: AppColors.primary)))]
      ]),
      trailing: isSelected ? const Icon(Icons.check, color: AppColors.primary) : (!available ? Icon(Icons.psychology_outlined, color: AppColors.textTertiary, size: isLandscape ? 16 : 16.w) : null),
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
        padding: EdgeInsets.symmetric(horizontal: isLandscape ? 60 : 40.w),
        child: Column(
          mainAxisSize: MainAxisSize.min, 
          children: [
            Container(
              padding: EdgeInsets.symmetric(horizontal: isLandscape ? 16 : 16.w, vertical: isLandscape ? 8 : 8.h), 
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(isLandscape ? 100 : 100.r)), 
              child: Row(
                mainAxisSize: MainAxisSize.min, 
                children: [
                  Icon(_isForward ? Icons.keyboard_double_arrow_right_rounded : Icons.keyboard_double_arrow_left_rounded, color: Colors.white, size: isLandscape ? 32 : 32.w),
                  SizedBox(width: isLandscape ? 12 : 12.w),
                  Text('${_isForward ? "+" : ""}${_scrubbingDelta.inSeconds.abs()}s', style: TextStyle(color: Colors.white, fontSize: isLandscape ? 24 : 24.sp, fontWeight: FontWeight.bold)),
                ]
              )
            ),
          ]
        ),
      )
    );
  }



  Widget _buildAspectRatioOverlay() {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return IgnorePointer(child: Align(alignment: Alignment.topCenter, child: Container(
      margin: EdgeInsets.only(top: isLandscape ? 40 : 72.h), 
      padding: EdgeInsets.symmetric(horizontal: isLandscape ? 12 : 12.w, vertical: isLandscape ? 6 : 6.h), 
      decoration: BoxDecoration(color: Colors.black54, borderRadius: AppRadius.borderRadiusLG), 
      child: Text(_aspectRatioOverlayText!, style: TextStyle(color: Colors.white, fontSize: isLandscape ? 12 : 12.sp, fontWeight: FontWeight.bold))
    )));
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
              left: !isLandscape,
              right: !isLandscape,
              bottom: false, 
              child: _buildFeedItem(index)
            ),
          ),
          if (!_hasSeenScrollHint) Positioned(bottom: isLandscape ? 80 : 140.h, left: 0, right: 0, child: IgnorePointer(child: AnimatedOpacity(opacity: _showScrollHintOverlay ? 1.0 : 0.0, duration: const Duration(milliseconds: 500), child: Center(child: Container(padding: EdgeInsets.symmetric(horizontal: isLandscape ? 24 : 24.w, vertical: isLandscape ? 12 : 12.h), decoration: BoxDecoration(color: Colors.black.withOpacity(0.65), borderRadius: BorderRadius.circular(isLandscape ? 30 : 30.r)), child: Text('Swipe up to watch more', style: TextStyle(color: Colors.white, fontSize: isLandscape ? 16 : 16.sp, fontWeight: FontWeight.w600))))))),
        ]),
      ),
    );
  }

  Widget _buildFeedItem(int index) => VayuFeedItem(
    key: ValueKey('feed_${index}_${_videos[index].id}'),
    index: index, video: _videos[index], controller: _controllers[index], chewie: _chewieControllers[index],
    isCurrent: index == _currentIndex, isFullScreenManual: _isFullScreenManual, showControls: _showControls,
    isControlsLocked: _isControlsLocked, aspectRatioMode: _aspectRatioMode, showScrubbingOverlay: _showScrubbingOverlay,
    aspectRatioOverlayText: _aspectRatioOverlayText, onToggleFullScreen: _toggleFullScreen, onCycleAspectRatio: _cycleAspectRatioMode,
    onHandleTap: _handleTap, onDoubleTapToSeek: _handleDoubleTapToSeek,    onHorizontalDragEnd: _handleHorizontalDragEnd,
    onVerticalDragUpdate: _handleVerticalDragUpdate, onVerticalDragEnd: _handleVerticalDragEnd, 
    onUnifiedHorizontalDrag: _handleUnifiedHorizontalDrag,
    onScrollingLock: (locked) {
      if (mounted) setState(() => _isScrollingLocked = locked);
    },
    onShowSnackBar: _showSnackBar,
    buildAdSection: _buildAdSection, 
    buildVideoInfo: _buildVideoInfo, buildChannelRow: _buildChannelRow,
    buildScrubbingOverlay: _buildScrubbingOverlay, buildAspectRatioOverlay: _buildAspectRatioOverlay,
    buildCustomControls: _buildCustomControls, formatDuration: _formatDuration,
    buildDubbingProgress: _buildDubbingProgress,
  );


  Widget _buildVideoInfo(int index) {
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final v = _videos[index];
    return Padding(padding: EdgeInsets.fromLTRB(isPortrait ? 16.w : 16, 0, isPortrait ? 16.w : 16, isPortrait ? 4.h : 4), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_compactTitle(v.videoName, maxChars: 80), style: AppTypography.bodyLarge.copyWith(color: Theme.of(context).brightness == Brightness.dark ? AppColors.textPrimary : Colors.black87, fontWeight: FontWeight.bold, height: 1.2), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (v.tags != null && v.tags!.isNotEmpty) ...[
                SizedBox(height: isPortrait ? 8.h : 8),
                Wrap(
                  spacing: isPortrait ? 6.w : 6,
                  runSpacing: isPortrait ? 4.h : 4,
                  children: v.tags!.map((tag) => Text(
                    '#$tag',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: isPortrait ? 12.sp : 12,
                      fontWeight: FontWeight.w500,
                    ),
                  )).toList(),
                ),
              ],
            ],
          ),
        ),
        IconButton(
          onPressed: () { 
            _handleToggleSave(index); 
          }, 
          icon: Icon(
            v.isSaved ? Icons.bookmark_rounded : Icons.bookmark_outline_rounded, 
            color: v.isSaved ? AppColors.primary : AppColors.textSecondary, 
            size: isPortrait ? 20 : 20,
          ),
        ),
      ]),
      Transform.translate(offset: Offset(0, isPortrait ? -8.h : -8), child: Text('${FormatUtils.formatViews(v.views)} views • ${FormatUtils.formatTimeAgo(v.uploadedAt)}', style: AppTypography.bodySmall.copyWith(color: AppColors.textTertiary, fontSize: isPortrait ? 12.sp : 12))),
    ]));
  }

  Widget _buildAdSection(int index) {
    final ad = _bannerAdsByIndex[index];
    if (ad == null) return const SizedBox.shrink();
    return Padding(padding: EdgeInsets.symmetric(horizontal: 16.w), child: BannerAdSection(adData: {...ad, 'creatorId': _videos[index].uploader.id}, onVideoPause: () => _controllers[index]?.pause(), onVideoResume: () => _controllers[index]?.play()));
  }

  Widget _buildChannelRow(int index) {
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final v = _videos[index];
    return Padding(padding: EdgeInsets.symmetric(horizontal: isPortrait ? 16.w : 16), child: Row(children: [
      InteractiveScaleButton(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => ProfileScreen(userId: v.uploader.id))), child: CircleAvatar(radius: isPortrait ? 18.r : 18, backgroundImage: v.uploader.profilePic.isNotEmpty ? CachedNetworkImageProvider(v.uploader.profilePic) : null, backgroundColor: AppColors.backgroundSecondary, child: v.uploader.profilePic.isEmpty ? const Icon(Icons.person_rounded, color: Colors.white, size: 21) : null)),
      SizedBox(width: isPortrait ? 10.w : 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(v.uploader.name, style: AppTypography.bodyMedium.copyWith(color: Theme.of(context).brightness == Brightness.dark ? AppColors.textPrimary : Colors.black87, fontWeight: FontWeight.bold), maxLines: 1), if (v.uploader.totalVideos != null) Text('${v.uploader.totalVideos} videos', style: AppTypography.bodySmall.copyWith(color: Theme.of(context).brightness == Brightness.dark ? AppColors.textSecondary : Colors.black54, fontSize: isPortrait ? 10.sp : 10))])),
      FollowButtonWidget(uploaderId: v.uploader.id, uploaderName: v.uploader.name),
    ]));
  }

  Widget _buildCustomControls(int index) {
    final controller = _controllers[index];
    if (controller == null) return const SizedBox.shrink();
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    return Stack(children: [
      // Top Controls (More menu, but also acting as a safe area for top bar)
      Positioned(
        top: 0, right: 0, left: 0,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            isPortrait ? 16 : MediaQuery.of(context).viewPadding.left + 16, 
            isPortrait ? 8 : (MediaQuery.of(context).viewPadding.top + 8), 
            isPortrait ? 16 : MediaQuery.of(context).viewPadding.right + 16, 
            0
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Empty space on the left to balance the More icon
              const SizedBox(width: 30),

              // More Options
              IconButton(
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.more_vert_rounded, color: Colors.white, size: 21),
                onPressed: _showMoreOptions,
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black26,
                  padding: EdgeInsets.zero,
                  fixedSize: Size(isPortrait ? 30.w : 30, isPortrait ? 30.w : 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ),
      ),

      // Lock Button (Middle Left)
      Positioned(
        left: isPortrait ? 16.w : 16, 
        top: 0, bottom: 0,
        child: SafeArea(
          top: false, bottom: false,
          child: Center(
            child: IconButton(
              constraints: const BoxConstraints(),
              icon: Icon(_isControlsLocked ? Icons.lock_rounded : Icons.lock_open_rounded, color: Colors.white, size: isPortrait ? 20 : 20),
              onPressed: () => setState(() => _isControlsLocked = !_isControlsLocked),
              style: IconButton.styleFrom(
                backgroundColor: _isControlsLocked ? AppColors.primary : Colors.black26,
                padding: EdgeInsets.zero,
                fixedSize: Size(isPortrait ? 30.w : 30, isPortrait ? 30.w : 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                    width: isPortrait ? 38.w : 38, height: isPortrait ? 38.h : 38,
                    decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
                    child: Icon(Icons.skip_previous_rounded, color: Colors.white, size: isPortrait ? 26.w : 26),
                  ),
                ),
                SizedBox(width: isPortrait ? 42.w : 42),
              ],
              // Limit the hit area of the Play button to its visual size
              SizedBox(
                width: isPortrait ? 50.w : 50,
                height: isPortrait ? 50.w : 50,
                child: InteractiveScaleButton(
                  onTap: _togglePlay,
                  child: Container(
                    decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
                    child: Icon(
                      controller.value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, 
                      color: Colors.white, 
                      size: isPortrait ? 34.w : 34,
                    ),
                  ),
                ),
              ),
              if (!isPortrait) ...[
                SizedBox(width: isPortrait ? 42.w : 42),
                InteractiveScaleButton(
                  onTap: _nextVideo,
                  child: Container(
                    width: isPortrait ? 38.w : 38, height: isPortrait ? 38.h : 38,
                    decoration: const BoxDecoration(color: Colors.black26, shape: BoxShape.circle),
                    child: Icon(Icons.skip_next_rounded, color: Colors.white, size: isPortrait ? 26.w : 26),
                  ),
                ),
              ],
            ],
          ),
        ),

      // Bottom Right Actions (Aspect Ratio, Full Screen)
      if (!_isControlsLocked) 
        Positioned(
          bottom: isPortrait ? 28 : 58, 
          right: isPortrait ? 16 : (16 + MediaQuery.of(context).viewPadding.right), 
          child: Row(
            children: [
              IconButton(
                constraints: const BoxConstraints(),
                tooltip: 'Aspect Ratio', 
                onPressed: _cycleAspectRatioMode, 
                icon: const Icon(Icons.aspect_ratio_rounded, color: Colors.white, size: 21),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black26,
                  padding: EdgeInsets.zero,
                  fixedSize: Size(isPortrait ? 30.w : 30, isPortrait ? 30.w : 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                constraints: const BoxConstraints(),
                tooltip: 'Full Screen', 
                onPressed: _toggleFullScreen, 
                icon: Icon(isPortrait ? Icons.fullscreen_rounded : Icons.fullscreen_exit_rounded, color: Colors.white, size: 21),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black26,
                  padding: EdgeInsets.zero,
                  fixedSize: Size(isPortrait ? 30.w : 30, isPortrait ? 30.w : 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
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
        
        final horizontalMargin = isLandscape ? 32.0 : 16.w;
        final bottomMargin = isLandscape ? 48.0 : 12.h; // Higher in landscape to stay above progress bar
        
        return Center(
          child: Container(
            constraints: BoxConstraints(maxWidth: isLandscape ? MediaQuery.of(context).size.width * 0.5 : double.infinity),
            margin: EdgeInsets.fromLTRB(horizontalMargin, 0, horizontalMargin, bottomMargin),
            padding: EdgeInsets.symmetric(horizontal: isLandscape ? 12.0 : 12.w, vertical: isLandscape ? 8.0 : 10.h),
            decoration: BoxDecoration(
              color: isLandscape ? Colors.black87 : AppColors.backgroundSecondary.withOpacity(0.9),
              borderRadius: BorderRadius.circular(isLandscape ? 12 : 12.r),
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
                                      fontSize: isLandscape ? 12.0 : 12.sp, 
                                      fontWeight: FontWeight.bold
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '${result.progress}%',
                                  style: TextStyle(
                                    color: AppColors.primary, 
                                    fontSize: isLandscape ? 12.0 : 12.sp, 
                                    fontWeight: FontWeight.bold
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(isLandscape ? 4 : 4.r),
                              child: LinearProgressIndicator(
                                value: progressValue,
                                backgroundColor: isLandscape ? Colors.white24 : AppColors.borderPrimary,
                                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                                minHeight: isLandscape ? 4.0 : 4.h,
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
                          fontSize: isLandscape ? 12.0 : 12.sp,
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
    VayuBottomSheet.show<void>(
      context: context,
      title: 'Dubbing',
      child: Align(
        alignment: Alignment.center,
        heightFactor: 1.0,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).orientation == Orientation.landscape ? 380.0 : double.infinity),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Aap dubbing cancel karna chahte hain?',
                style: AppTypography.bodyLarge.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      onPressed: () => Navigator.pop(context),
                      label: 'Nahi',
                      variant: AppButtonVariant.secondary,
                    ),
                  ),
                  const SizedBox(width: 16),
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
                      label: 'Haan, Cancel Karein',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
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
  final AspectRatioMode aspectRatioMode;
  final bool showScrubbingOverlay;
  final String? aspectRatioOverlayText;
  final VoidCallback onToggleFullScreen;
  final VoidCallback onCycleAspectRatio;
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
  final Widget Function() buildAspectRatioOverlay;
  final Widget Function(int) buildCustomControls;
  final Widget Function(int) buildDubbingProgress;
  final String Function(Duration) formatDuration;

  const VayuFeedItem({
    super.key, required this.index, required this.video, this.controller, this.chewie,
    required this.isCurrent, required this.isFullScreenManual, required this.showControls,
    required this.isControlsLocked, required this.aspectRatioMode, required this.showScrubbingOverlay,
    this.aspectRatioOverlayText, required this.onToggleFullScreen, required this.onCycleAspectRatio,
    required this.onHandleTap, required this.onDoubleTapToSeek, required this.onHorizontalDragEnd,
    required this.onVerticalDragUpdate, required this.onVerticalDragEnd,    required this.onUnifiedHorizontalDrag,
    required this.onScrollingLock, // **NEW: Required callback**
    required this.onShowSnackBar, // **NEW: Required callback**
    required this.buildAdSection,
    required this.buildVideoInfo, required this.buildChannelRow,
    required this.buildScrubbingOverlay, required this.buildAspectRatioOverlay,
    required this.buildCustomControls, required this.buildDubbingProgress, 
    required this.formatDuration,
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
            bottom: isFull ? 40 : 40.h, // Above the video progress bar
            left: 0, right: 0,
            child: widget.buildDubbingProgress(widget.index),
          ),
        ],
      );
    }
    return Column(children: [
      _buildVideoSection(orientation),
      Expanded(child: SingleChildScrollView(child: Column(children: [
        SizedBox(height: 12.h), widget.buildAdSection(widget.index),
        SizedBox(height: 12.h), widget.buildVideoInfo(widget.index),
        SizedBox(height: 8.h), widget.buildChannelRow(widget.index),
        SizedBox(height: 12.h), widget.buildDubbingProgress(widget.index),
        SizedBox(height: 48.h),
      ]))),
    ]);
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
    // Using max of left/right padding to keep it symmetrical and avoid jumps
    final lateralPadding = isFull 
        ? (math.max(MediaQuery.of(context).viewPadding.left, MediaQuery.of(context).viewPadding.right) + (isFull ? 24 : 24.w))
        : 0.0;
        
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
              fit: widget.aspectRatioMode == AspectRatioMode.stretch || widget.aspectRatioMode == AspectRatioMode.ratio16x9
                  ? BoxFit.fill
                  : (widget.aspectRatioMode == AspectRatioMode.crop ? BoxFit.cover : BoxFit.contain),
              clipBehavior: Clip.hardEdge,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: Chewie(controller: chewie),
              ),
            ),
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
        if (widget.aspectRatioOverlayText != null) widget.buildAspectRatioOverlay(),
      ],

      if (controller != null && controllerIsHealthy && widget.isCurrent)
        Positioned(
          left: lateralPadding, 
          right: lateralPadding, 
          bottom: isFull ? MediaQuery.of(context).padding.bottom + 16 : -1, 
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: (!isFull || widget.showControls) ? 1.0 : 0.0,
            child: SafeArea(
              top: false, bottom: false,
              child: Stack(
                clipBehavior: Clip.none,
              children: [
                // hit area: 20px total (Yug Match)
                SizedBox(
                  height: 20,
                  child: VayuVideoProgressBar(
                    controller: controller, 
                    height: 20, 
                    barHeight: 2, 
                    activeBarHeight: 6, 
                    thumbRadius: 6,
                    barCenterOffset: isFull ? null : 19.h, // Precise bottom alignment only in portrait
                  ),
                ),
                // Duration label positioned neatly above the tight progress bar area
                Positioned(
                  left: isFull ? 12 : 12.w,
                  bottom: isFull ? 24 : 24.h, 
                  child: ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: controller,
                    builder: (context, v, _) => AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: widget.showControls ? 1.0 : 0.0,
                      child: Text(
                        '${widget.formatDuration(v.position)} / ${widget.formatDuration(v.duration)}',
                        style: TextStyle(
                          color: Colors.white, 
                          fontSize: isFull ? 12.0 : 12.sp, 
                          fontWeight: FontWeight.bold, 
                          shadows: const [Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 1))]
                        ),
                      ),
                    ),
                  ),
                ),
                ],
              ),
            ),
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

