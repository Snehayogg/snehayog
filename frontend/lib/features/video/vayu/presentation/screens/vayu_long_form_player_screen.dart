import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'dart:async';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/features/video/core/data/services/video_service.dart';
import 'package:vayug/features/video/dubbing/data/models/dubbing_models.dart';
import 'package:vayug/features/video/dubbing/data/services/on_device_dubbing_service.dart';
import 'package:vayug/shared/widgets/vayu_snackbar.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/factories/video_controller_factory.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:vayug/features/ads/data/services/active_ads_service.dart';
import 'package:vayug/features/video/feed/presentation/screens/video_feed_advanced/widgets/banner_ad_section.dart';
import 'package:vayug/features/video/core/presentation/managers/video_controller_manager.dart';
import 'package:vayug/features/video/core/presentation/managers/shared_video_controller_pool.dart';
import 'package:vayug/features/video/core/presentation/managers/main_controller.dart';
import 'package:vayug/features/video/core/data/services/video_view_tracker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:vayug/features/video/vayu/presentation/widgets/vayu_player/vayu_feed_item.dart';
import 'package:vayug/features/video/vayu/presentation/widgets/vayu_player/vayu_metadata_section.dart';
import 'package:vayug/features/video/vayu/presentation/widgets/vayu_player/vayu_channel_info.dart';
import 'package:vayug/features/video/vayu/presentation/widgets/vayu_player/vayu_player_overlay.dart';
import 'package:vayug/features/video/vayu/presentation/widgets/vayu_player/vayu_dubbing_status_overlay.dart';
import 'package:vayug/shared/widgets/vayu_bottom_sheet.dart';
import 'package:vayug/shared/widgets/report_dialog_widget.dart';
import 'package:share_plus/share_plus.dart';
import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vibration/vibration.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayug/core/providers/navigation_providers.dart';

class VayuLongFormPlayerScreen extends ConsumerStatefulWidget {
  final VideoModel video;
  final List<VideoModel> relatedVideos;
  final int? parentTabIndex;

  const VayuLongFormPlayerScreen({
    super.key,
    required this.video,
    this.relatedVideos = const [],
    this.parentTabIndex,
  });

  @override
  ConsumerState<VayuLongFormPlayerScreen> createState() => _VayuLongFormPlayerScreenState();
}

class _VayuLongFormPlayerScreenState extends ConsumerState<VayuLongFormPlayerScreen> with WidgetsBindingObserver {


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
  Timer? _controlsTimer;
  bool _isScrollingLocked = false;

  // Gesture state
  double _brightnessValue = 0.5;
  double _volumeValue = 0.5;
  Timer? _overlayTimer;
  SharedPreferences? _prefs;
  String? _currentUserId;

  bool _isSaving = false;
  double _playbackSpeed = 1.0;
  final List<double> _playbackSpeedOptions = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
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

  final Map<int, Timer> _viewUITimers = {};
  final Map<int, Duration> _lastKnownPositions = {};

  // Quiz State
  QuizModel? _activeQuiz;
  final Map<String, Set<int>> _shownQuizzesPerVideo = {};
  final List<QuizModel> _activeQuizHistory = [];
  StreamSubscription<String>? _poolDisposalSubscription;
  final Map<int, VoidCallback> _errorListeners = {};

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
      final otherVideos = List<VideoModel>.from(widget.relatedVideos);
      otherVideos.shuffle();
      _videos.addAll(otherVideos);
    }
    _pageController = PageController(initialPage: 0);

    _initPrefs();
    _viewTracker = VideoViewTracker();
    // _adImpressionService = AdImpressionService();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _startViewTracking(_currentIndex);
    });

    _videoControllerManager.registerOnRoutePopped(() {
      if (mounted) _validateAndRestoreControllers();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        final initialIdx = _videos.indexWhere((v) => v.id == widget.video.id);
        if (initialIdx >= 0) {
          _currentIndex = initialIdx;
          _pageController.jumpToPage(initialIdx);
          _initializePlayer(initialIdx);
        } else {
          final mainController = ref.read(mainControllerProvider);
          final lastIndex = await mainController.getLastViewedVideoIndex(1);
          if (lastIndex > 0 && lastIndex < _videos.length) {
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
        _mainController?.registerVideoObserver(
          onPause: _pauseCurrentVideo,
          onResume: _resumeCurrentVideo,
        );
        _mainController?.forcePauseVideos();
      }
    });

    _poolDisposalSubscription = SharedVideoControllerPool().disposalStream.listen((videoId) {
      if (mounted) {
        final index = _videos.indexWhere((v) => v.id == videoId);
        if (index != -1 && _controllers.containsKey(index)) {
          final oldC = _controllers[index];
          if (oldC != null) {
            try { oldC.removeListener(_onPositionChanged); } catch (_) {}
          }
          setState(() {
            _controllers.remove(index);
            _chewieControllers.remove(index)?.dispose();
          });
          if (index == _currentIndex) {
            _initializePlayer(index);
          }
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mainController = ref.watch(mainControllerProvider);
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
        try { if (controller.value.isPlaying) controller.pause(); } catch (_) {}
      }
    }
  }

  void _resumeCurrentVideo() {
    if (mounted && !_lifecyclePaused) {
      _validateAndRestoreControllers();
      if (widget.parentTabIndex != null) {
        final currentTabIndex = _mainController?.currentIndex ?? 0;
        if (currentTabIndex != widget.parentTabIndex) return;
      }
      final controller = _controllers[_currentIndex];
      if (controller != null && controller.value.isInitialized && !controller.value.isPlaying) {
        controller.play();
        _enableWakelock();
      }
    }
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
    final hasSeenHint = _prefs!.getBool('has_seen_vayu_long_form_scroll_hint') ?? false;
    if (mounted) setState(() => _hasSeenScrollHint = hasSeenHint);
    if (!hasSeenHint) _handleFirstTimeScrollHint(_prefs!);
  }

  Future<void> _handleFirstTimeScrollHint(SharedPreferences prefs) async {
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
    } catch (e) { AppLogger.log('Error scroll hint: $e'); }
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
      final response = await _videoService.getVideos(page: _currentPage, videoType: 'vayu', clearSession: false, random: true);
      List<VideoModel> newVideos = [];
      final List? videosList = response['videos'] ?? response['data'];
      if (videosList != null) {
        newVideos = videosList.map((v) => VideoModel.fromJson(Map<String, dynamic>.from(v))).toList();
        newVideos.shuffle();
      }
      if (newVideos.isEmpty) {
        if (mounted) setState(() => _hasMore = false);
      } else {
        final existingIds = _videos.map((v) => v.id).toSet();
        newVideos.removeWhere((v) => existingIds.contains(v.id));
        if (mounted) {
          setState(() { _videos.addAll(newVideos); _currentPage++; _hasMore = response['hasMore'] as bool? ?? true; });
          if (_currentIndex + 1 < _videos.length) _preloadNearbyVideos();
        }
      }
    } catch (e) { AppLogger.log('Error loading more: $e'); }
    finally { if (mounted) setState(() => _isLoadingMore = false); }
  }

  Future<void> _initializePlayer([int? requestedIndex]) async {
    final index = requestedIndex ?? _currentIndex;
    if (index >= _videos.length) return;
    final videoToPlay = _videos[index];
    VideoPlayerController? existing = _controllerPool.getController(videoToPlay.id);
    if (existing != null && existing.value.isInitialized) {
      if (mounted) {
        setState(() {
          _controllers[index] = existing;
          _chewieControllers[index]?.dispose();
          _chewieControllers[index] = _createChewieController(existing);
        });
        _setupLateInitialization(index, existing);
      }
      return;
    }
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
        setState(() { _controllers[index] = newController; _chewieControllers[index] = chewie; });
        _controllerPool.addController(videoToPlay.id, newController, index: index);
        _setupLateInitialization(index, newController);
      }
    } catch (e) { AppLogger.log('Failed to init: $e'); }
  }

  ChewieController _createChewieController(VideoPlayerController controller) {
    return ChewieController(
      videoPlayerController: controller,
      aspectRatio: 16 / 9,
      autoPlay: true,
      showControls: false,
      customControls: const SizedBox.shrink(),
      materialProgressColors: ChewieProgressColors(playedColor: AppColors.primary, handleColor: AppColors.primary, backgroundColor: AppColors.borderPrimary, bufferedColor: AppColors.textTertiary),
      placeholder: Container(color: Colors.black, child: const Center(child: CircularProgressIndicator(color: AppColors.primary))),
    );
  }

  void _setupLateInitialization(int index, VideoPlayerController controller) async {
    controller.removeListener(_onPositionChanged);
    controller.addListener(_onPositionChanged);
    if (_errorListeners.containsKey(index)) controller.removeListener(_errorListeners[index]!);
    _errorListeners[index] = () => _handleVideoError(index, controller);
    controller.addListener(_errorListeners[index]!);
    if (index == _currentIndex) {
      _enableWakelock(); _resumePlayback(index);
      if (_showControls) _startHideControlsTimer();
      try { _brightnessValue = await ScreenBrightness().application; final vol = await FlutterVolumeController.getVolume(); if (vol != null) _volumeValue = vol; } catch (_) {}
    }
  }

  void _handleVideoError(int index, VideoPlayerController controller) {
    if (!mounted) return;
    try {
      if (SharedVideoControllerPool().isControllerDisposed(controller)) return;
      if (controller.value.hasError) {
        if (index == _currentIndex) _initializePlayer(index);
      }
    } catch (_) {}
  }

  void _onPositionChanged() {
    if (!mounted) return;
    final controller = _controllers[_currentIndex];
    if (controller == null) return;
    setState(() {});
    final currentPos = controller.value.position;
    final lastPos = _lastKnownPositions[_currentIndex] ?? Duration.zero;
    if (currentPos < lastPos && lastPos.inSeconds > 1) {
      _stopViewTracking(_currentIndex); _startViewTracking(_currentIndex);
    }
    _lastKnownPositions[_currentIndex] = currentPos;
    if (controller.value.isPlaying && currentPos.inSeconds % 5 == 0) _savePlaybackPosition(_currentIndex);
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
      if (diff >= 0 && diff < 1500) {
        setState(() { _activeQuiz = quiz; shownQuizzes.add(i); _activeQuizHistory.add(quiz); });
        break;
      }
    }
  }

  @override
  void dispose() {
    _disableWakelock();
    WidgetsBinding.instance.removeObserver(this);
    _mainController?.unregisterVideoObserver(onPause: _pauseCurrentVideo, onResume: _resumeCurrentVideo);
    try { _mainController?.unregisterCallbacks(); } catch (_) {}
    _savePlaybackPosition(_currentIndex);
    _controllers.forEach((index, c) { try { c.removeListener(_onPositionChanged); c.pause(); c.setVolume(0.0); } catch (_) {} });
    _chewieControllers.forEach((index, c) => c?.dispose());
    _pageController.dispose();
    _controlsTimer?.cancel(); _overlayTimer?.cancel();
    _stopViewTracking(_currentIndex); _poolDisposalSubscription?.cancel();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    Future.microtask(() { if (context.mounted) ref.read(mainControllerProvider).setBottomNavVisibility(true); });
    super.dispose();
  }

  void _startViewTracking(int index) {
    if (index < 0 || index >= _videos.length) return;
    final video = _videos[index];
    _viewTracker.startViewTracking(video.id, videoUploaderId: video.uploader.id, videoHash: video.videoHash);
    _viewUITimers[index]?.cancel();
    _viewUITimers[index] = Timer(const Duration(seconds: 3), () {
      if (mounted && _currentIndex == index) {
        setState(() { _videos[index] = _videos[index].copyWith(views: _videos[index].views + 1); });
      }
    });
  }

  void _stopViewTracking(int index) {
    if (index < 0 || index >= _videos.length) return;
    _viewUITimers[index]?.cancel(); _viewUITimers.remove(index);
    _viewTracker.stopViewTracking(_videos[index].id);
  }

  void _handleUnifiedHorizontalDrag(double deltaX) {
    if (_isControlsLocked || !_controllers.containsKey(_currentIndex)) return;
    _horizontalDragTotal += deltaX;
    final controller = _controllers[_currentIndex]!;
    final seekOffset = Duration(milliseconds: (_horizontalDragTotal * 500).toInt());
    var targetPosition = controller.value.position + seekOffset;
    if (targetPosition < Duration.zero) targetPosition = Duration.zero;
    if (targetPosition > controller.value.duration) targetPosition = controller.value.duration;
    setState(() { _showScrubbingOverlay = true; _scrubbingTargetTime = targetPosition; _scrubbingDelta = seekOffset; _isForward = deltaX > 0; });
  }

  void _handleHorizontalDragEnd() {
    if (!_controllers.containsKey(_currentIndex)) return;
    _controllers[_currentIndex]!.seekTo(_scrubbingTargetTime);
    setState(() { _showScrubbingOverlay = false; _horizontalDragTotal = 0.0; _showControls = true; });
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (_isControlsLocked) return;
    final size = MediaQuery.of(context).size;
    final isLeftSide = details.localPosition.dx < size.width / 2;
    final delta = details.primaryDelta! / size.height * 1.5;
    if (isLeftSide) {
      _brightnessValue = (_brightnessValue - delta).clamp(0.0, 1.0);
      ScreenBrightness().setApplicationScreenBrightness(_brightnessValue);
    } else {
      _volumeValue = (_volumeValue - delta).clamp(0.0, 1.0);
      FlutterVolumeController.setVolume(_volumeValue);
    }
    setState(() { _showScrubbingOverlay = false; _showControls = false; });
    _resetOverlayTimer();
    _controlsTimer?.cancel();
  }


  void _resetOverlayTimer() { _overlayTimer?.cancel(); }

  void _handleTap() {
    setState(() => _showControls = !_showControls);
    if (MediaQuery.of(context).orientation == Orientation.landscape) {
      SystemChrome.setEnabledSystemUIMode(_showControls ? SystemUiMode.manual : SystemUiMode.immersiveSticky, overlays: SystemUiOverlay.values);
    }
    if (_showControls) _startHideControlsTimer();
  }

  void _startHideControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() => _showControls = false);
        if (MediaQuery.of(context).orientation == Orientation.landscape) SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
      if (controller.value.isPlaying) { controller.pause(); } else { controller.play(); _hideControlsWithDelay(); }
    });
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
                        width: 100, height: 56,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(8), image: ep['thumbnailUrl'] != null ? DecorationImage(image: CachedNetworkImageProvider(ep['thumbnailUrl']), fit: BoxFit.cover) : null, color: AppColors.backgroundSecondary),
                        child: isCurrent ? Container(decoration: BoxDecoration(color: Colors.black45, borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.play_circle_fill_rounded, color: AppColors.primary, size: 28)) : null,
                      ),
                      title: Text(ep['videoName'] ?? 'Episode ${index + 1}', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.bodyMedium.copyWith(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, color: isCurrent ? AppColors.primary : AppColors.textPrimary)),
                      subtitle: ep['duration'] != null ? Text(_formatDuration(Duration(seconds: (ep['duration'] as num).toInt())), style: AppTypography.bodySmall) : null,
                      onTap: () {
                        Navigator.pop(context);
                        if (!isCurrent) {
                          final epId = ep['id'] ?? ep['_id'];
                          if (epId != null) {
                            final targetIndex = _videos.indexWhere((v) => v.id == epId);
                            if (targetIndex != -1) _pageController.animateToPage(targetIndex, duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                          }
                        }
                      },
                    );
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
    setState(() { _showControls = true; _showScrubbingOverlay = true; _scrubbingTargetTime = target; _scrubbingDelta = seekOffset; _isForward = !isLeftSide; });
    _startHideControlsTimer();
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(milliseconds: 700), () { if (mounted) setState(() => _showScrubbingOverlay = false); });
  }

  void _showShareOptions(VideoModel video) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    VayuBottomSheet.show<void>(
      context: context,
      title: 'Share',
      maxWidth: isLandscape ? 380.0 : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            dense: true, visualDensity: VisualDensity.compact,
            leading: const Icon(Icons.share_rounded, color: AppColors.textPrimary),
            title: const Text('Share Link'),
            onTap: () { Navigator.pop(context); Share.share(video.videoUrl); },
          ),
          ListTile(
            dense: true, visualDensity: VisualDensity.compact,
            leading: const Icon(Icons.play_circle_outline_rounded, color: AppColors.textPrimary),
            title: const Text('Play in External App'),
            onTap: () { Navigator.pop(context); _openInExternalPlayer(video); },
          ),
        ],
      ),
    );
  }

  void _showShareSuggestionBottomSheet(VideoModel video) {
    final TextEditingController controller = TextEditingController();
    VayuBottomSheet.show<void>(
      context: context, title: 'Share Suggestion',
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Did you face any problem while watching this video? share with us', style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            TextField(controller: controller, maxLines: 4, decoration: InputDecoration(hintText: 'Type here...', filled: true, fillColor: AppColors.backgroundSecondary, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 20),
            AppButton(onPressed: () { Navigator.pop(context); _showSnackBar('Suggestion shared!'); }, label: 'Share Suggestion'),
          ],
        ),
      ),
    );
  }

  Future<void> _openInExternalPlayer(VideoModel video) async {
    if (Theme.of(context).platform == TargetPlatform.android) {
      final intent = AndroidIntent(action: 'action_view', data: video.videoUrl, type: 'video/*', flags: <int>[Flag.FLAG_ACTIVITY_NEW_TASK]);
      try { await intent.launch(); } catch (e) { _showSnackBar('No external player found', type: VayuSnackBarType.error); }
    } else {
      final url = Uri.parse(video.videoUrl);
      if (await canLaunchUrl(url)) { await launchUrl(url, mode: LaunchMode.externalApplication); }
    }
  }

  Future<void> _handleToggleSave([int? requestedIndex]) async {
    if (_isSaving) return;
    final index = requestedIndex ?? _currentIndex;
    final video = _videos[index];
    try {
      setState(() => _isSaving = true); HapticFeedback.lightImpact();
      final isSaved = await _videoService.toggleSave(video.id);
      setState(() { video.isSaved = isSaved; _isSaving = false; });
      _showSnackBar(isSaved ? 'Saved' : 'Removed', type: isSaved ? VayuSnackBarType.success : VayuSnackBarType.info);
    } catch (e) { setState(() => _isSaving = false); }
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    if (_playbackSpeed == speed) return;
    try {
      final controller = _controllers[_currentIndex];
      if (controller != null) await controller.setPlaybackSpeed(speed);
      setState(() => _playbackSpeed = speed);
    } catch (e) {
      AppLogger.error('Error setting playback speed', e);
    }
  }

  void _nextVideo() { if (_currentIndex < _videos.length - 1) _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); }
  void _previousVideo() { if (_currentIndex > 0) _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); }

  void _toggleFullScreen() {
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    final controller = _controllers[_currentIndex];
    final aspectRatio = controller?.value.aspectRatio ?? 1.0;
    if (aspectRatio < 1.0) {
      setState(() { _isFullScreenManual = !_isFullScreenManual; _showControls = true; });
    } else {
      SystemChrome.setPreferredOrientations(isPortrait ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight] : [DeviceOrientation.portraitUp]);
      setState(() { _isFullScreenManual = false; _showControls = true; });
    }
    _startHideControlsTimer();
  }

  Future<void> _showMoreOptions() async {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    VayuBottomSheet.show<void>(
      context: context, title: 'More Options',
      maxWidth: isLandscape ? 380.0 : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(dense: true, leading: const Icon(Icons.speed_rounded), title: const Text('Playback Speed'), trailing: Text('${_playbackSpeed}x'), onTap: () { Navigator.pop(context); _showPlaybackSpeedOptions(); }),
          if (_currentIndex < _videos.length) ListTile(dense: true, leading: const Icon(Icons.language_rounded), title: const Text('Audio Language'), onTap: () { Navigator.pop(context); _showLanguageSelector(context, _videos[_currentIndex]); }),
          ListTile(dense: true, leading: Icon(_isControlsLocked ? Icons.lock_rounded : Icons.lock_open_rounded), title: Text(_isControlsLocked ? 'Unlock' : 'Lock'), onTap: () { Navigator.pop(context); setState(() => _isControlsLocked = !_isControlsLocked); }),
          ListTile(dense: true, leading: const Icon(Icons.report_problem_rounded), title: const Text('Report'), onTap: () { Navigator.pop(context); _openReportDialog(); }),
        ],
      ),
    );
  }

  void _openReportDialog() {
    VayuBottomSheet.show(context: context, title: 'Report', child: ReportDialogWidget(targetType: 'video', targetId: _videos[_currentIndex].id));
  }

  Future<void> _showPlaybackSpeedOptions() async {
    VayuBottomSheet.show<void>(
      context: context, title: 'Speed',
      child: Column(mainAxisSize: MainAxisSize.min, children: _playbackSpeedOptions.map((s) => ListTile(title: Text('${s}x', style: TextStyle(color: s == _playbackSpeed ? AppColors.primary : null)), onTap: () { Navigator.pop(context); _setPlaybackSpeed(s); })).toList()),
    );
  }

  void _onPageChanged(int index) {
    if (index == _currentIndex) return;
    _pauseCurrentVideo(); _reprimeWindowIfNeeded(index); _stopViewTracking(_currentIndex);
    setState(() => _currentIndex = index);
    ref.read(mainControllerProvider).updateCurrentVideoIndex(index, tabIndex: 1);
    _startViewTracking(index); _preloadNearbyVideos(); _initializePlayer(index); _loadBannerAd(index);
    if (_videos.length - index < 3) _loadMoreVideos();
  }

  void _reprimeWindowIfNeeded(int current) {
    final keys = _controllers.keys.where((i) => (i - current).abs() > 1).toList();
    for (final i in keys) { _savePlaybackPosition(i); _controllerPool.disposeController(_videos[i].id); _controllers.remove(i); _chewieControllers.remove(i)?.dispose(); }
  }

  void _validateAndRestoreControllers() {
    if (_videos.isEmpty || !mounted) return;
    final indices = {_currentIndex, if (_currentIndex + 1 < _videos.length) _currentIndex + 1, if (_currentIndex - 1 >= 0) _currentIndex - 1};
    for (final idx in indices) { if (!_controllers.containsKey(idx) || SharedVideoControllerPool().isControllerDisposed(_controllers[idx])) _initializePlayer(idx); }
  }

  void _preloadNearbyVideos() {
    if (_currentIndex + 1 < _videos.length) _preloadVideo(_currentIndex + 1);
    if (_currentIndex - 1 >= 0) _preloadVideo(_currentIndex - 1);
  }

  Future<void> _preloadVideo(int index) async {
    if (index < 0 || index >= _videos.length || _controllers.containsKey(index)) return;
    try {
      final c = await VideoControllerFactory.createController(_videos[index]);
      await c.initialize(); _controllers[index] = c; _controllerPool.addController(_videos[index].id, c, index: index);
    } catch (_) {}
  }

  void _enableWakelock() { if (!_wakelockEnabled) { WakelockPlus.enable(); _wakelockEnabled = true; } }
  void _disableWakelock() { if (_wakelockEnabled) { WakelockPlus.disable(); _wakelockEnabled = false; } }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}' : '${two(d.inMinutes.remainder(60))}:${two(d.inSeconds.remainder(60))}';
  }

  Future<void> _loadBannerAd(int index) async {
    if (_bannerAdsByIndex.containsKey(index)) return;
    try {
      final ads = await _activeAdsService.fetchActiveAds();
      final List? banner = ads['banner'] as List?;
      if (mounted && banner != null && banner.isNotEmpty) setState(() => _bannerAdsByIndex[index] = Map<String, dynamic>.from(banner.first));
    } catch (_) {}
  }

  void _onLocalSmartDubTap(VideoModel video, [String targetLang = 'hindi']) async {
    setState(() => _isDubbingProgressVisible = true);
    final resultVN = _getOrCreateNotifier<DubbingResult>(_dubbingResultsVN, video.id, const DubbingResult(status: DubbingStatus.checking));
    _dubbingSubscriptions[video.id]?.cancel();
    _dubbingSubscriptions[video.id] = _onDeviceDubbingService.dubLocalVideo(video.videoUrl, targetLang: targetLang).listen((r) {
      if (!mounted) return;
      resultVN.value = r;
      if (r.status == DubbingStatus.completed && r.dubbedUrl != null) {
        final vIdx = _videos.indexWhere((v) => v.id == video.id);
        if (vIdx != -1) {
          final dubbed = Map<String, String>.from(_videos[vIdx].dubbedUrls ?? {});
          dubbed[r.language ?? targetLang] = r.dubbedUrl!;
          setState(() { _videos[vIdx] = _videos[vIdx].copyWith(dubbedUrls: dubbed); if (vIdx == _currentIndex) { _selectedAudioLanguage[video.id] = r.language ?? targetLang; _controllerPool.disposeController(video.id); _initializePlayer(_currentIndex); } });
        }
      }
    });
  }

  ValueNotifier<T> _getOrCreateNotifier<T>(Map<String, ValueNotifier<T>> map, String key, T initial) {
    return map.putIfAbsent(key, () => ValueNotifier<T>(initial));
  }

  void _showLanguageSelector(BuildContext context, VideoModel video) {
    VayuBottomSheet.show<void>(
      context: context, title: 'Audio',
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _buildLanguageOption(context, video, 'Default', 'default'),
        _buildLanguageOption(context, video, 'English', 'english', available: video.dubbedUrls?.containsKey('english') ?? false),
        _buildLanguageOption(context, video, 'Hindi', 'hindi', available: video.dubbedUrls?.containsKey('hindi') ?? false),
      ]),
    );
  }

  Widget _buildLanguageOption(BuildContext context, VideoModel video, String title, String code, {bool available = true}) {
    final selected = _selectedAudioLanguage[video.id] ?? 'default';
    return ListTile(
      title: Text(title, style: TextStyle(color: selected == code ? AppColors.primary : null)),
      trailing: selected == code ? const Icon(Icons.check, color: AppColors.primary) : (!available ? const Icon(Icons.psychology_outlined, size: 16) : null),
      onTap: () { Navigator.pop(context); if (available || code == 'default') { _handleLanguageSelection(video, code); } else { _onLocalSmartDubTap(video, code); } },
    );
  }

  void _handleLanguageSelection(VideoModel video, String code) {
    if (_selectedAudioLanguage[video.id] == code) return;
    _controllerPool.disposeController(video.id);
    setState(() { _selectedAudioLanguage[video.id] = code; _initializePlayer(_currentIndex); });
  }

  void _showCancelDubbingDialog(String videoId) {
    VayuBottomSheet.show(context: context, title: 'Cancel Dubbing?', child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Text('Aap dubbing cancel karna chahte hain?'),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(child: AppButton(onPressed: () => Navigator.pop(context), label: 'Nahi', variant: AppButtonVariant.secondary)),
        const SizedBox(width: 12),
        Expanded(child: AppButton(onPressed: () {
          Navigator.pop(context);
          _onDeviceDubbingService.cancelDubbing(_videos.firstWhere((v) => v.id == videoId).videoUrl);
          _dubbingSubscriptions[videoId]?.cancel();
          _dubbingResultsVN[videoId]?.value = const DubbingResult(status: DubbingStatus.idle);
        }, label: 'Haan')),
      ]),
    ]));
  }

  Widget _buildScrubbingOverlay() {
    return Align(
      alignment: _isForward ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(_isForward ? Icons.keyboard_double_arrow_right_rounded : Icons.keyboard_double_arrow_left_rounded, color: Colors.white, size: 32),
          const SizedBox(height: 8),
          Text('${_isForward ? "+" : ""}${_scrubbingDelta.inSeconds.abs()}s', style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  String _sanitizeUrl(String url) {
    if (url.isEmpty) return url;
    final trimmed = url.trim();
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return 'https://$trimmed';
    }
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    if (_videos.isEmpty) return const Scaffold(backgroundColor: AppColors.backgroundPrimary, body: Center(child: CircularProgressIndicator(color: AppColors.primary)));
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    return PopScope(
      canPop: !isLandscape,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isLandscape) { _toggleFullScreen(); }
        else if (didPop) { ref.read(mainControllerProvider).setBottomNavVisibility(true); }
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        body: Stack(children: [
          PageView.builder(
            controller: _pageController,
            physics: _isScrollingLocked ? const NeverScrollableScrollPhysics() : const BouncingScrollPhysics(),
            scrollDirection: Axis.vertical,
            onPageChanged: _onPageChanged,
            itemCount: _videos.length,
            itemBuilder: (context, index) => SafeArea(
              top: !isLandscape,
              bottom: false,
              left: false,
              right: false,
              child: _buildFeedItem(index),
            ),
          ),
          if (!_hasSeenScrollHint) Positioned(bottom: isLandscape ? 80 : 140, left: 0, right: 0, child: IgnorePointer(child: AnimatedOpacity(opacity: _showScrollHintOverlay ? 1.0 : 0.0, duration: const Duration(milliseconds: 500), child: Center(child: Container(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(30)), child: const Text('Swipe up to watch more', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600))))))),
        ]),
      ),
    );
  }

  Widget _buildFeedItem(int index) {
    final v = _videos[index];
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    return VayuFeedItem(
      index: index, video: v, controller: _controllers[index], chewie: _chewieControllers[index], isCurrent: index == _currentIndex, isFullScreenManual: _isFullScreenManual, showControls: _showControls, isControlsLocked: _isControlsLocked, showScrubbingOverlay: _showScrubbingOverlay,
      onToggleFullScreen: _toggleFullScreen, onOpenExternalPlayer: () => _openInExternalPlayer(v), onHandleTap: _handleTap, onDoubleTapToSeek: _handleDoubleTapToSeek, onHorizontalDragEnd: _handleHorizontalDragEnd, onVerticalDragUpdate: _handleVerticalDragUpdate, onVerticalDragEnd: () {}, onUnifiedHorizontalDrag: _handleUnifiedHorizontalDrag,
      onScrollingLock: (l) => setState(() => _isScrollingLocked = l), onShowSnackBar: _showSnackBar, buildAdSection: _buildAdSection, buildVideoInfo: (_) => const SizedBox.shrink(), buildChannelRow: (_) => const SizedBox.shrink(), buildScrubbingOverlay: _buildScrubbingOverlay, buildCustomControls: (_) => const SizedBox.shrink(), buildDubbingProgress: (_) => const SizedBox.shrink(), formatDuration: _formatDuration, onQuizDismiss: () => setState(() => _activeQuiz = null), activeQuiz: index == _currentIndex ? _activeQuiz : null,
      metadataSection: VayuMetadataSection(video: v, isPortrait: isPortrait, onShare: () => _showShareOptions(v), onSave: () => _handleToggleSave(index), onVisitLink: () async { final u = Uri.parse(_sanitizeUrl(v.link!)); if (await canLaunchUrl(u)) launchUrl(u, mode: LaunchMode.externalApplication); }, onMoreOptions: _showMoreOptions, onEpisodes: () => _showEpisodeList(context, v), onSuggestion: () => _showShareSuggestionBottomSheet(v), onShowError: (m) => _showSnackBar(m, type: VayuSnackBarType.error)),
      channelInfo: VayuChannelInfo(video: v, isPortrait: isPortrait),
      playerOverlay: VayuPlayerOverlay(controller: _controllers[index], showControls: _showControls, isControlsLocked: _isControlsLocked, isPortrait: isPortrait, isFullScreenManual: _isFullScreenManual, onTogglePlay: _togglePlay, onMoreOptions: _showMoreOptions, onNext: _nextVideo, onPrevious: _previousVideo),
      dubbingOverlay: _buildDubbingOverlay(index),
    );
  }

  Widget _buildDubbingOverlay(int index) {
    if (!_isDubbingProgressVisible) return const SizedBox.shrink();
    return ValueListenableBuilder<DubbingResult>(
      valueListenable: _getOrCreateNotifier(_dubbingResultsVN, _videos[index].id, const DubbingResult(status: DubbingStatus.idle)),
      builder: (context, r, _) => VayuDubbingStatusOverlay(result: r, isVisible: _isDubbingProgressVisible, onCancel: () => _showCancelDubbingDialog(_videos[index].id), onHide: () => setState(() => _isDubbingProgressVisible = false)),
    );
  }

  Widget _buildAdSection(int index) {
    final ad = _bannerAdsByIndex[index];
    if (ad == null) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: BannerAdSection(adData: {...ad, 'creatorId': _videos[index].uploader.id}, onVideoPause: () => _controllers[index]?.pause(), onVideoResume: () => _controllers[index]?.play(), onImpression: () async {}));
  }
}
