import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayu/core/providers/navigation_providers.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:vayu/features/video/video_model.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'dart:async';
import 'package:vayu/features/video/data/services/video_service.dart';
import 'package:vayu/features/profile/presentation/screens/profile_screen.dart';
import 'package:vayu/shared/widgets/follow_button_widget.dart';
import 'package:vayu/core/design/colors.dart';
import 'package:vayu/shared/widgets/vayu_bottom_sheet.dart';
import 'package:vayu/core/design/radius.dart';
import 'package:vayu/core/design/spacing.dart';
import 'package:vayu/core/design/typography.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayu/shared/factories/video_controller_factory.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:vayu/features/ads/data/services/active_ads_service.dart';
import 'package:vayu/features/video/presentation/screens/video_feed_advanced/widgets/banner_ad_section.dart';
import 'package:vayu/shared/widgets/interactive_scale_button.dart';

enum _AspectRatioMode {
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
  static const _controlTouchSize = 48.0;
  static const _controlIconSize = 24.0;

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

  // Banner Ad State
  final ActiveAdsService _activeAdsService = ActiveAdsService();
  // Map of banner ad data per video index to ensure consistency when scrolling back
  final Map<int, Map<String, dynamic>> _bannerAdsByIndex = {};


  // Controls State
  bool _showControls = true;
  bool _showScrubbingOverlay = false;
  Duration _scrubbingTargetTime = Duration.zero;
  Duration _scrubbingDelta = Duration.zero;
  double _horizontalDragTotal = 0.0;
  bool _isForward = true;
  Timer? _hideControlsTimer;

  // Gesture state (MX Player style)
  double _brightnessValue = 0.5;
  double _volumeValue = 0.5;
  Timer? _overlayTimer;
  SharedPreferences? _prefs;


  bool _isSaving = false;
  double _playbackSpeed = 1.0;
  _AspectRatioMode _aspectRatioMode = _AspectRatioMode.fit;
  String? _aspectRatioOverlayText;
  Timer? _aspectRatioOverlayTimer;
  final List<double> _playbackSpeedOptions = <double>[
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
  ];
  bool _isControlsLocked = false;
  bool _wakelockEnabled = false;
  bool _isFullScreenManual = false;

  // Scroll hint animation states
  bool _hasSeenScrollHint = true; // Default true, updated in _initPrefs
  bool _showScrollHintOverlay = false;

  Future<void> _loadMoreVideos() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final response =
          await _videoService.getVideos(page: _currentPage, videoType: 'vayu');
      List<VideoModel> newVideos = [];
      if (response['videos'] != null) {
        newVideos = (response['videos'] as List)
            .map((v) => VideoModel.fromJson(v))
            .toList();
      } else if (response.containsKey('data')) {
        newVideos = (response['data'] as List)
            .map((v) => VideoModel.fromJson(v))
            .toList();
      }

      if (newVideos.isEmpty) {
        if (mounted) setState(() => _hasMore = false);
      } else {
        // Randomize the feed order as requested
        newVideos.shuffle();

        // Remove any videos that are already in the feed to avoid duplicates
        final existingIds = _videos.map((v) => v.id).toSet();
        newVideos.removeWhere((v) => existingIds.contains(v.id));

        if (mounted) {
          setState(() {
            _videos.addAll(newVideos);
            _currentPage++;
          });

          // Preload upcoming videos dynamically if we just added more
          if (_currentIndex + 1 < _videos.length) {
            _initializePlayer(_currentIndex + 1);
          }
        }
      }
    } catch (e) {
      AppLogger.log('Error loading more videos: $e');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  @override
  void initState() {
    super.initState();
    // Allow all orientations for auto-rotation
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    // Ensure system UI is visible in portrait initially
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);

    // Initialize feed with the starting video
    _videos.add(widget.video);
    if (widget.relatedVideos.isNotEmpty) {
      _videos.addAll(widget.relatedVideos);
    }
    _pageController = PageController(initialPage: 0);

    _initPrefs();

    // Initialize the first video player
    _initializePlayer(0);

    // Load more videos immediately to fill the feed if we don't have enough
    if (_videos.length < 3) {
      _loadMoreVideos();
    }

    // **NAVIGATION VISIBILITY: Hide bottom nav when entering player**
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(mainControllerProvider).setBottomNavVisibility(false);
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _disableWakelock();
    } else if (state == AppLifecycleState.resumed) {
      // Re-enable wakelock when coming back to the app on this screen
      _enableWakelock();
    }
  }

  Future<void> _initPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeenHint =
        prefs.getBool('has_seen_vayu_long_form_scroll_hint') ?? false;

    if (mounted) {
      setState(() {
        _hasSeenScrollHint = hasSeenHint;
      });
    }

    if (!hasSeenHint) {
      _handleFirstTimeScrollHint(prefs);
    }
  }

  Future<void> _handleFirstTimeScrollHint(SharedPreferences prefs) async {
    // Wait for the first video to initialize and start playing
    await Future.delayed(const Duration(milliseconds: 2000));
    if (!mounted || _currentIndex != 0) return;

    // Proceed only if there's more than 1 video available to scroll to
    if (_videos.length <= 1) return;

    setState(() {
      _showScrollHintOverlay = true;
    });

    // Wait a moment for the user to read the text before animating
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted || _currentIndex != 0 || !_pageController.hasClients) return;

    final screenHeight = MediaQuery.of(context).size.height;
    final targetOffset = screenHeight * 0.30; // ~30% scroll

    try {
      // Animate up
      await _pageController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
      );

      // Pause slightly at the peak of the scroll
      await Future.delayed(const Duration(milliseconds: 150));

      if (!mounted || _currentIndex != 0 || !_pageController.hasClients) return;

      // Animate back down to original position
      await _pageController.animateTo(
        0,
        duration: const Duration(milliseconds: 800),
        curve: Curves.easeInOut,
      );
    } catch (e) {
      AppLogger.log('Error in scroll hint animation: $e');
    }

    if (!mounted) return;

    // Fade out overlay
    setState(() {
      _showScrollHintOverlay = false;
    });

    // Wait for fade out animation to finish before removing from tree
    await Future.delayed(const Duration(milliseconds: 600));
    if (mounted) {
      setState(() {
        _hasSeenScrollHint = true;
      });
    }

    // Save flag
    await prefs.setBool('has_seen_vayu_long_form_scroll_hint', true);
  }

  Future<void> _initializePlayer([int? requestedIndex]) async {
    final index = requestedIndex ?? _currentIndex;
    if (mounted) {
      setState(() {
        _chewieControllers[index] = null;
      });
    }

    _disableWakelock();

    // **NEW: Force pause any other videos (e.g. from Yug tab) before starting long form**
    try {
      if (mounted) {
        final mainController = ref.read(mainControllerProvider);
        mainController.forcePauseVideos();
      }
      AppLogger.log(
          '🎬 VayuLongFormPlayer: Requested force pause of other videos');
    } catch (e) {
      AppLogger.log('⚠️ VayuLongFormPlayer: Error requesting video pause: $e');
    }

    // Proper disposal of existing controllers before re-initializing
    try {
      if (_chewieControllers[index] != null) {
        _chewieControllers[index]!.dispose();
        _chewieControllers[index] = null;
      }
      if (_controllers[index] != null) {
        _controllers[index]!.dispose();
        _controllers.remove(index);
      }
    } catch (e) {
      AppLogger.log('⚠️ VayuLongFormPlayer: Error disposing controllers: $e');
    }

    try {
      final videoToPlay = _videos[index];
      // **ENHANCED: Use VideoControllerFactory for optimized controller creation**
      AppLogger.log(
          '🎬 VayuLongFormPlayer: Initializing for ${videoToPlay.videoName}');
      AppLogger.log('🔗 URL: ${videoToPlay.videoUrl}');

      _controllers[index] =
          await VideoControllerFactory.createController(videoToPlay);

      // **TIMEOUT PROTECTION**: Ensure initialization doesn't hang indefinitely
      await _controllers[index]!.initialize().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException(
              'Video loading timed out. Please check your connection.');
        },
      );

      // Re-apply selected playback speed for newly initialized videos.
      try {
        await _controllers[index]!.setPlaybackSpeed(_playbackSpeed);
      } catch (e) {
        AppLogger.log('⚠️ VayuLongFormPlayer: Failed to apply saved speed: $e');
      }

      _chewieControllers[index] = ChewieController(
        videoPlayerController: _controllers[index]!,
        aspectRatio: _controllers[index]!.value.aspectRatio,
        autoPlay: true,
        looping: false,
        allowFullScreen: true,
        allowPlaybackSpeedChanging: true,
        showControls: false, // Hide default controls
        customControls:
            const SizedBox.shrink(), // Ensure no default controls are rendered
        materialProgressColors: ChewieProgressColors(
          playedColor: AppColors.primary,
          handleColor: AppColors.primary,
          backgroundColor: AppColors.borderPrimary,
          bufferedColor: AppColors.textTertiary,
        ),
        placeholder: Container(
          color: AppColors.backgroundPrimary,
          child: const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
        ),
        errorBuilder: (context, errorMessage) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const HugeIcon(
                    icon: HugeIcons.strokeRoundedVideoOff,
                    color: AppColors.textTertiary,
                    size: 48,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    errorMessage.contains('TimeoutException')
                        ? 'Connection timed out'
                        : 'Video unavailable',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: AppTypography.weightSemiBold,
                      fontSize: AppTypography.fontSizeLG,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please try again later',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: AppTypography.fontSizeSM,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );

      if (mounted) setState(() {});

      // Listen for position changes to save periodically
      _controllers[index]!.addListener(_onPositionChanged);
      _enableWakelock(); // **ENHANCED: Keep screen on as soon as player is ready**

      // Resume playback logic
      _resumePlayback(index);

      // Fetch initial brightness and volume
      try {
        _brightnessValue = await ScreenBrightness().application;
        final currentVolume = await FlutterVolumeController.getVolume();
        if (currentVolume != null) {
          _volumeValue = currentVolume;
        }
      } catch (e) {
        AppLogger.log(
            '⚠️ VayuLongFormPlayer: Error fetching system values: $e');
      }
    } catch (e) {
      AppLogger.log('❌ VayuLongFormPlayer: Failed to initialize: $e',
          isError: true);
      if (mounted) {
        setState(() {
          // Error is handled by Chewie's errorBuilder or shown via logs
        });
      }
    }
  }

  // _onContentScroll REPLACED by PageView pagination

  Future<void> _loadBannerAd(int index) async {
    if (_bannerAdsByIndex.containsKey(index)) {
      return; // Already loaded for this index
    }

    try {
      AppLogger.log('🔍 VayuLongFormPlayer: Fetching ad for index $index');
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
    } catch (e) {
      AppLogger.log('❌ Error loading banner ad for index $index: $e');
    }
  }

  @override
  void dispose() {
    _disableWakelock();
    WidgetsBinding.instance.removeObserver(this);

    // Save current positions
    _controllers.forEach((index, controller) {
      _savePlaybackPosition(index);
      controller.dispose();
    });

    _chewieControllers.forEach((index, chewie) {
      chewie?.dispose();
    });

    _pageController.dispose();
    _hideControlsTimer?.cancel();
    _overlayTimer?.cancel();
    _aspectRatioOverlayTimer?.cancel();

    // Ensure Bottom Navigation Bar comes back when leaving
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
        overlays: SystemUiOverlay.values);
    _isFullScreenManual = false;

    // **NAVIGATION VISIBILITY: Restore bottom nav on dispose**
    Future.microtask(() {
      if (context.mounted) {
        ref.read(mainControllerProvider).setBottomNavVisibility(true);
      }
    });
    super.dispose();
  }

  void _onPositionChanged() {
    final controller = _controllers[_currentIndex];
    if (controller != null && controller.value.isPlaying) {
      // Save every 5 seconds (roughly)
      if (controller.value.position.inSeconds % 5 == 0) {
        _savePlaybackPosition(_currentIndex);
      }
    }
  }

  String _formatViews(int views) {
    if (views >= 1000000) {
      return '${(views / 1000000).toStringAsFixed(1)}M views';
    }
    if (views >= 1000) return '${(views / 1000).toStringAsFixed(1)}K views';
    return '$views views';
  }

  String _formatTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()} years ago';
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()} months ago';
    if (diff.inDays > 0) return '${diff.inDays} days ago';
    if (diff.inHours > 0) return '${diff.inHours} hours ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes} minutes ago';
    return 'Just now';
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    if (_isControlsLocked) return;
    if (_chewieControllers[_currentIndex] == null) return;

    _horizontalDragTotal += details.primaryDelta!;
    final currentPosition = _controllers[_currentIndex]!.value.position;
    final totalDuration = _controllers[_currentIndex]!.value.duration;

    // Sensitivity: 1 pixel = 800ms (Agressive seeking for long-form content)
    final seekOffset =
        Duration(milliseconds: (_horizontalDragTotal * 100).toInt());
    var targetPosition = currentPosition + seekOffset;

    // Clamp target position
    if (targetPosition < Duration.zero) targetPosition = Duration.zero;
    if (targetPosition > totalDuration) targetPosition = totalDuration;

    setState(() {
      _showScrubbingOverlay = true;
      _scrubbingTargetTime = targetPosition;
      _scrubbingDelta = seekOffset;
      _isForward = details.primaryDelta! > 0;
    });
  }

  void _handleHorizontalDragEnd() {
    if (_chewieControllers[_currentIndex] == null) return;

    _controllers[_currentIndex]!.seekTo(_scrubbingTargetTime);

    setState(() {
      _showScrubbingOverlay = false;
      _horizontalDragTotal = 0.0;
      _showControls = true; // Show controls after scrubbing
    });
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (_isControlsLocked) return;
    if (_chewieControllers[_currentIndex] == null) return;

    final size = MediaQuery.of(context).size;
    final isLeftSide = details.localPosition.dx < size.width / 2;

    // Sensitivity: SWIPE_DISTANCE / SCREEN_HEIGHT
    // Increase sensitivity slightly (multiply by 1.2 or similar)
    final delta = details.primaryDelta! / size.height * 1.5;

    if (isLeftSide) {
      // Brightness
      _brightnessValue -= delta;
      _brightnessValue = _brightnessValue.clamp(0.0, 1.0);
      try {
        ScreenBrightness().setApplicationScreenBrightness(_brightnessValue);
      } catch (e) {
        AppLogger.log('❌ Error setting brightness: $e');
      }
      setState(() {
        _showScrubbingOverlay = false;
        _showControls = false; // Hide controls while gestured
      });
    } else {
      // Volume
      _volumeValue -= delta;
      _volumeValue = _volumeValue.clamp(0.0, 1.0);
      try {
        FlutterVolumeController.setVolume(_volumeValue);
      } catch (e) {
        AppLogger.log('❌ Error setting volume: $e');
      }
      setState(() {
        _showScrubbingOverlay = false;
        _showControls = false;
      });
    }

    _resetOverlayTimer();
  }

  void _handleVerticalDragEnd() {
    // Overlays will hide after delay
    _resetOverlayTimer();
  }

  void _resetOverlayTimer() {
    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(seconds: 2), () {
      // Intentionally left blank or handle other overlay clearing
    });
  }

  void _handleTap() {
    if (_isControlsLocked) {
      setState(() {
        _showControls = !_showControls;
      });
      if (_showControls) {
        _startHideControlsTimer();
      }
      return;
    }

    setState(() {
      _showControls = !_showControls;
    });

    // Sync system UI in landscape
    if (MediaQuery.of(context).orientation == Orientation.landscape) {
      if (_showControls) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
            overlays: SystemUiOverlay.values);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    }

    if (_showControls) {
      _startHideControlsTimer();
    }
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _showControls = false;
        });
        // Sync system UI in landscape
        if (MediaQuery.of(context).orientation == Orientation.landscape) {
          SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        }
      }
    });
  }

  Future<void> _savePlaybackPosition(int index) async {
    final controller = _controllers[index];
    if (controller != null && controller.value.isInitialized) {
      _prefs ??= await SharedPreferences.getInstance();
      final video = _videos[index];
      final key = 'video_pos_${video.id}';
      await _prefs!.setInt(key, controller.value.position.inSeconds);
    }
  }

  Future<void> _resumePlayback(int index) async {
    final controller = _controllers[index];
    if (controller == null) return;

    _prefs ??= await SharedPreferences.getInstance();
    final video = _videos[index];
    final key = 'video_pos_${video.id}';
    final savedSeconds = _prefs!.getInt(key);

    if (savedSeconds != null && savedSeconds > 0) {
      final duration = Duration(seconds: savedSeconds);
      if (duration < controller.value.duration) {
        controller.seekTo(duration);
      }
    }
  }

  void _showFeedbackAnimation(bool isPlaying) {
    // Toggle controls visibility: hiding them if playing, showing if paused
    if (isPlaying) {
      _startHideControlsTimer();
    } else {
      setState(() {
        _showControls = true;
      });
      _hideControlsTimer?.cancel();
    }
  }

  void _hideControlsWithDelay() {
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted &&
          _controllers[_currentIndex]!.value.isPlaying &&
          _showControls) {
        setState(() {
          _showControls = false;
        });
      }
    });
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

  void _handleDoubleTapToSeek(TapDownDetails details) {
    final controller = _controllers[_currentIndex];
    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    final size = MediaQuery.of(context).size;
    final isLeftSide = details.localPosition.dx < size.width / 2;
    final seekOffset = Duration(seconds: isLeftSide ? -10 : 10);
    final duration = controller.value.duration;
    var targetPosition = controller.value.position + seekOffset;

    if (targetPosition < Duration.zero) targetPosition = Duration.zero;
    if (targetPosition > duration) targetPosition = duration;

    controller.seekTo(targetPosition);

    setState(() {
      _showControls = true;
      _showScrubbingOverlay = true;
      _scrubbingTargetTime = targetPosition;
      _scrubbingDelta = seekOffset;
      _isForward = !isLeftSide;
    });

    _startHideControlsTimer();

    _overlayTimer?.cancel();
    _overlayTimer = Timer(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      setState(() {
        _showScrubbingOverlay = false;
      });
    });
  }

  String _compactTitle(String rawTitle, {required int maxChars}) {
    final normalized = rawTitle.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxChars) return normalized;
    return '${normalized.substring(0, maxChars).trimRight()}...';
  }

  Future<void> _handleToggleSave([int? requestedIndex]) async {
    if (_isSaving) return;

    final index = requestedIndex ?? _currentIndex;
    final video = _videos[index];

    try {
      setState(() => _isSaving = true);
      HapticFeedback.lightImpact();

      final isSaved = await _videoService.toggleSave(video.id);

      setState(() {
        video.isSaved = isSaved;
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isSaved
                ? 'Video saved to bookmarks'
                : 'Video removed from bookmarks'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  Future<void> _setPlaybackSpeed(double speed) async {
    if (_playbackSpeed == speed) return;

    try {
      final controller = _controllers[_currentIndex];
      if (controller != null && controller.value.isInitialized) {
        await controller.setPlaybackSpeed(speed);
      }

      if (mounted) {
        setState(() {
          _playbackSpeed = speed;
        });
      } else {
        _playbackSpeed = speed;
      }
    } catch (e) {
      AppLogger.log(
          '❌ VayuLongFormPlayer: Failed to change playback speed: $e');
    }
  }

  void _toggleFullScreen() {
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    final controller = _controllers[_currentIndex];
    final aspectRatio = (controller != null && controller.value.isInitialized)
        ? controller.value.aspectRatio
        : 1.0;

    if (aspectRatio < 1.0) {
      setState(() {
        _isFullScreenManual = !_isFullScreenManual;
        _showControls = true;
      });

      if (_isFullScreenManual) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
            overlays: SystemUiOverlay.values);
      }
    } else {
      if (isPortrait) {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ]);
      }
      setState(() {
        _isFullScreenManual = false;
        _showControls = true;
      });
    }
    _startHideControlsTimer();
  }

  Future<void> _showPlaybackSpeedOptions() async {
    if (!mounted) return;

    await VayuBottomSheet.show<void>(
      context: context,
      title: 'Playback speed',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _playbackSpeedOptions.map((speed) {
          final isSelected = speed == _playbackSpeed;
          return ListTile(
            dense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            leading: SizedBox(
              width: 20,
              child: isSelected
                  ? const HugeIcon(
                      icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                      size: 18,
                      color: AppColors.primary,
                    )
                  : null,
            ),
            title: Text(
              _formatPlaybackSpeed(speed),
              style: TextStyle(
                color: isSelected
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
                fontWeight: isSelected
                    ? AppTypography.weightSemiBold
                    : AppTypography.weightMedium,
              ),
            ),
            onTap: () async {
              Navigator.of(context).pop();
              await _setPlaybackSpeed(speed);
            },
          );
        }).toList(),
      ),
    );
  }

  BoxFit _boxFitForAspectMode() {
    switch (_aspectRatioMode) {
      case _AspectRatioMode.fit:
      case _AspectRatioMode.ratio16x9:
        return BoxFit.contain;
      case _AspectRatioMode.crop:
        return BoxFit.cover;
      case _AspectRatioMode.stretch:
        return BoxFit.fill;
    }
  }

  String _aspectRatioLabel(_AspectRatioMode mode) {
    switch (mode) {
      case _AspectRatioMode.fit:
        return 'Fit';
      case _AspectRatioMode.crop:
        return 'Crop';
      case _AspectRatioMode.stretch:
        return 'Stretch';
      case _AspectRatioMode.ratio16x9:
        return '16:9';
    }
  }

  void _cycleAspectRatioMode() {
    const modes = _AspectRatioMode.values;
    final currentIndex = modes.indexOf(_aspectRatioMode);
    final nextMode = modes[(currentIndex + 1) % modes.length];

    if (!mounted) {
      _aspectRatioMode = nextMode;
      return;
    }

    setState(() {
      _aspectRatioMode = nextMode;
      _showControls = true;
      _aspectRatioOverlayText = 'Aspect ratio: ${_aspectRatioLabel(nextMode)}';
    });

    _startHideControlsTimer();
    _aspectRatioOverlayTimer?.cancel();
    _aspectRatioOverlayTimer = Timer(const Duration(milliseconds: 1200), () {
      if (!mounted) return;
      setState(() {
        _aspectRatioOverlayText = null;
      });
    });
  }

  Widget _buildVideoPlayerWithAspectMode(ChewieController chewie) {
    final controller = chewie.videoPlayerController;
    final sourceSize = controller.value.size;
    final bool hasValidSize = sourceSize.width > 0 && sourceSize.height > 0;
    final double sourceWidth = hasValidSize ? sourceSize.width : 1920;
    final double sourceHeight = hasValidSize ? sourceSize.height : 1080;

    final Widget player = SizedBox(
      width: sourceWidth,
      height: sourceHeight,
      child: Chewie(controller: chewie),
    );

    final Widget fittedPlayer = ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: _boxFitForAspectMode(),
          child: player,
        ),
      ),
    );

    if (_aspectRatioMode == _AspectRatioMode.ratio16x9) {
      return Center(
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: fittedPlayer,
        ),
      );
    }

    return fittedPlayer;
  }

  Widget _buildOverlayControlButton({
    required Widget icon,
    required VoidCallback onPressed,
    String? tooltip,
  }) {
    return SizedBox(
      width: _controlTouchSize,
      height: _controlTouchSize,
      child: IconButton(
        iconSize: _controlIconSize,
        tooltip: tooltip,
        onPressed: onPressed,
        icon: icon,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: _controlTouchSize,
          minHeight: _controlTouchSize,
        ),
      ),
    );
  }

  String _formatPlaybackSpeed(double speed) {
    if (speed == speed.roundToDouble()) {
      return '${speed.toInt()}x';
    }
    return '${speed.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')}x';
  }

  Widget _buildScrubbingOverlay() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Semi-transparent backdrop for content
          Container(
            padding: EdgeInsets.symmetric(
                horizontal: AppSpacing.spacing6, vertical: AppSpacing.spacing3),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary.withValues(alpha: 0.45),
              borderRadius: AppRadius.borderRadiusPill,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HugeIcon(
                  icon: _isForward
                      ? HugeIcons.strokeRoundedArrowRightDouble
                      : HugeIcons.strokeRoundedArrowLeftDouble,
                  color: AppColors.textPrimary,
                  size: 32,
                ),
                AppSpacing.hSpace12,
                Text(
                  '${_isForward ? "+" : ""}${_scrubbingDelta.inSeconds.abs()}s',
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: AppTypography.weightBold,
                    shadows: [
                      Shadow(
                        blurRadius: 10.0,
                        color: AppColors.backgroundPrimary,
                        offset: Offset(0, 0),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          AppSpacing.vSpace12,
          Text(
            _formatDuration(_scrubbingTargetTime),
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: AppTypography.weightSemiBold,
              shadows: [
                Shadow(
                  blurRadius: 10.0,
                  color: AppColors.backgroundPrimary,
                  offset: Offset(2, 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAspectRatioOverlay() {
    if (_aspectRatioOverlayText == null) {
      return const SizedBox.shrink();
    }

    return IgnorePointer(
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          margin: const EdgeInsets.only(top: 72),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.backgroundSecondary.withValues(alpha: 0.54),
            borderRadius: AppRadius.borderRadiusLG,
          ),
          child: Text(
            _aspectRatioOverlayText!,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: AppTypography.weightSemiBold,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_videos.isEmpty) {
      return const Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          ref.read(mainControllerProvider).setBottomNavVisibility(true);
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.backgroundPrimary,
        body: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              scrollDirection: Axis.vertical,
              onPageChanged: _onPageChanged,
              itemCount: _videos.length,
              itemBuilder: (context, index) {
                return _buildFeedItem(index);
              },
            ),
            if (!_hasSeenScrollHint)
              Positioned(
                bottom: 140,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: _showScrollHintOverlay ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 500),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.65),
                          borderRadius: BorderRadius.circular(30),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Text(
                          'Swipe up to watch more',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeedItem(int index) {
    return OrientationBuilder(
      builder: (context, orientation) {
        final isLandscape = orientation == Orientation.landscape;
        final isFullScreen = isLandscape || _isFullScreenManual;

        if (isFullScreen) {
          if (_showControls && index == _currentIndex) {
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
                overlays: SystemUiOverlay.values);
          } else if (index == _currentIndex) {
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
          }
          return _buildVideoSection(index, orientation);
        }

        return SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildVideoSection(index, orientation),
              Expanded(
                child: _buildPortraitContent(index),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVideoSection(int index, Orientation orientation) {
    final size = MediaQuery.of(context).size;
    final isLandscape = orientation == Orientation.landscape;
    final video = _videos[index];
    final controller = _controllers[index];
    final chewie = _chewieControllers[index];

    if (isLandscape || _isFullScreenManual) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: SizedBox(
              width: size.width,
              child: Stack(
                children: [
                  if (chewie != null &&
                      controller != null &&
                      controller.value.isInitialized)
                    Hero(
                      tag: 'video_player_${video.id}',
                      child: _buildVideoPlayerWithAspectMode(chewie),
                    )
                  else
                    Container(
                      color: AppColors.backgroundPrimary,
                      child: const Center(
                          child: CircularProgressIndicator(
                              color: AppColors.primary)),
                    ),

                  // Gesture Overlay
                  if (chewie != null &&
                      controller != null &&
                      controller.value.isInitialized)
                    GestureDetector(
                      onTap: _handleTap,
                      onDoubleTapDown: _handleDoubleTapToSeek,
                      onHorizontalDragStart: (details) {
                        if (index != _currentIndex) return;
                        setState(() {
                          _horizontalDragTotal = 0.0;
                          _showControls = false;
                        });
                      },
                      onHorizontalDragUpdate: (details) {
                        if (index != _currentIndex) return;
                        _handleHorizontalDragUpdate(details);
                      },
                      onHorizontalDragEnd: (details) {
                        if (index != _currentIndex) return;
                        _handleHorizontalDragEnd();
                      },
                      onVerticalDragUpdate: _handleVerticalDragUpdate,
                      onVerticalDragEnd: (details) => _handleVerticalDragEnd(),
                      behavior: HitTestBehavior.translucent,
                    ),

                  // Buffering Indicator
                  if (controller != null)
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: controller,
                      builder: (context, value, child) {
                        if (value.isBuffering) {
                          return const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.primary));
                        }
                        return const SizedBox.shrink();
                      },
                    ),

                  // Controls
                  if (chewie != null &&
                      controller != null &&
                      controller.value.isInitialized &&
                      index == _currentIndex)
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _showControls ? 1.0 : 0.0,
                      child: IgnorePointer(
                        ignoring: !_showControls,
                        child: _buildCustomControls(index),
                      ),
                    ),

                  if (index == _currentIndex) ...[
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 150),
                      opacity: _showScrubbingOverlay ? 1.0 : 0.0,
                      child: IgnorePointer(
                        ignoring: !_showScrubbingOverlay,
                        child: _buildScrubbingOverlay(),
                      ),
                    ),
                    if (_aspectRatioOverlayText != null)
                      _buildAspectRatioOverlay(),
                  ],
                ],
              ),
            ),
          ),

          // **NEW: Sleek Edge-to-Edge Progress Bar for Full Screen**
          if (controller != null && controller.value.isInitialized)
            Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewPadding.bottom,
                left: MediaQuery.of(context).viewPadding.left,
                right: MediaQuery.of(context).viewPadding.right,
              ),
              child: SizedBox(
                height: 3.0, // Minimalist thin line
                width: size.width,
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  padding: EdgeInsets
                      .zero, // Edge-to-edge relative to padded container
                  colors: VideoProgressColors(
                    playedColor: AppColors.primary,
                    bufferedColor: AppColors.textPrimary.withValues(alpha: 0.2),
                    backgroundColor: AppColors.backgroundSecondary,
                  ),
                ),
              ),
            ),
        ],
      );
    }

    // Portrait mode
    final fixedHeight = size.width * 9 / 16;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: size.width,
          height: fixedHeight,
          child: Container(
            color: AppColors.backgroundPrimary,
            child: Stack(
              children: [
                if (chewie != null &&
                    controller != null &&
                    controller.value.isInitialized)
                  Hero(
                    tag: 'video_player_${video.id}',
                    child: _buildVideoPlayerWithAspectMode(chewie),
                  )
                else
                  Container(
                    color: AppColors.backgroundPrimary,
                    child: const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.textPrimary)),
                  ),

                // Gesture detection
                if (chewie != null &&
                    controller != null &&
                    controller.value.isInitialized)
                  GestureDetector(
                    onTap: _handleTap,
                    onDoubleTapDown: _handleDoubleTapToSeek,
                    onHorizontalDragStart: (details) {
                      if (index != _currentIndex) return;
                      setState(() {
                        _horizontalDragTotal = 0.0;
                        _showControls = false;
                      });
                    },
                    onHorizontalDragUpdate: (details) {
                      if (index != _currentIndex) return;
                      _handleHorizontalDragUpdate(details);
                    },
                    onHorizontalDragEnd: (details) {
                      if (index != _currentIndex) return;
                      _handleHorizontalDragEnd();
                    },
                    onVerticalDragUpdate: _handleVerticalDragUpdate,
                    onVerticalDragEnd: (details) => _handleVerticalDragEnd(),
                    behavior: HitTestBehavior.translucent,
                  ),

                if (chewie != null &&
                    controller != null &&
                    controller.value.isInitialized &&
                    index == _currentIndex)
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _showControls ? 1.0 : 0.0,
                    child: IgnorePointer(
                      ignoring: !_showControls,
                      child: _buildCustomControls(index),
                    ),
                  ),

                if (index == _currentIndex)
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _showScrubbingOverlay ? 1.0 : 0.0,
                    child: IgnorePointer(
                      ignoring: !_showScrubbingOverlay,
                      child: _buildScrubbingOverlay(),
                    ),
                  ),

                if (controller != null)
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: controller,
                    builder: (context, value, child) {
                      if (value.isBuffering) {
                        return const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.primary));
                      }
                      return const SizedBox.shrink();
                    },
                  ),

                if (_aspectRatioOverlayText != null && index == _currentIndex)
                  _buildAspectRatioOverlay(),
              ],
            ),
          ),
        ),

        // **NEW: Sleek Edge-to-Edge Progress Bar Divider**
        if (controller != null && controller.value.isInitialized)
          SizedBox(
            height: 3.0, // Minimalist thin line
            width: size.width,
            child: VideoProgressIndicator(
              controller,
              allowScrubbing: true,
              padding: EdgeInsets.zero, // Edge-to-edge
              colors: VideoProgressColors(
                playedColor: AppColors.primary,
                bufferedColor: AppColors.textPrimary.withValues(alpha: 0.2),
                backgroundColor: AppColors.backgroundSecondary,
              ),
            ),
          ),
      ],
    );
  }

  // Removed old scroll sections

  Widget _buildCustomControls(int index) {
    if (index != _currentIndex) return const SizedBox.shrink();

    final mediaQuery = MediaQuery.of(context);
    final isPortrait = mediaQuery.orientation == Orientation.portrait;
    final viewPadding = mediaQuery.viewPadding;
    final double landscapeLeftInset = isPortrait ? 0.0 : viewPadding.left;
    final double landscapeRightInset = isPortrait ? 0.0 : viewPadding.right;
    final double landscapeTopInset = isPortrait ? 0.0 : viewPadding.top;
    final double landscapeBottomInset = isPortrait ? 0.0 : viewPadding.bottom;

    final controller = _controllers[index];
    if (controller == null) return const SizedBox.shrink();

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: _handleTap,
            onDoubleTapDown: _handleDoubleTapToSeek,
            onHorizontalDragStart: (details) {
              if (_isControlsLocked) return;
              setState(() {
                _horizontalDragTotal = 0.0;
                _showControls = false;
              });
            },
            onHorizontalDragUpdate: (details) =>
                _handleHorizontalDragUpdate(details),
            onHorizontalDragEnd: (details) => _handleHorizontalDragEnd(),
            onVerticalDragUpdate: _handleVerticalDragUpdate,
            onVerticalDragEnd: (details) => _handleVerticalDragEnd(),
            behavior: HitTestBehavior.translucent,
            child: Container(color: Colors.transparent),
          ),
        ),

        // Lock Toggle
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          left: _showControls ? (12.0 + landscapeLeftInset) : -60.0,
          top: mediaQuery.size.height / 2 - 24,
          child: _isControlsLocked
              ? _buildUnlockButton(landscapeLeftInset)
              : _buildLockButton(landscapeLeftInset),
        ),

        // Center Play/Pause
        if (!_isControlsLocked)
          Center(
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: _showControls ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: controller,
                  builder: (context, value, _) {
                    final isPlaying = value.isPlaying;
                    return GestureDetector(
                      onTap: _togglePlay,
                      child: Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white.withValues(alpha: 0.9),
                        size: isPortrait ? 48 : 64,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

        // Top bar (Only More Options)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _showControls && !_isControlsLocked ? 1.0 : 0.0,
            child: IgnorePointer(
              ignoring: !_showControls || _isControlsLocked,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.backgroundPrimary.withValues(alpha: 0.7),
                      Colors.transparent
                    ],
                  ),
                ),
                padding: EdgeInsets.fromLTRB(
                  8.0 + landscapeLeftInset,
                  4.0 + landscapeTopInset,
                  8.0 + landscapeRightInset,
                  4.0,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    PopupMenuButton<String>(
                      tooltip: 'More options',
                      color:
                          AppColors.backgroundSecondary.withValues(alpha: 0.95),
                      onSelected: (value) {
                        if (value == 'playback_speed') {
                          _showPlaybackSpeedOptions();
                        }
                      },
                      iconSize: _controlIconSize,
                      icon: const HugeIcon(
                          icon: HugeIcons.strokeRoundedMoreVertical,
                          color: AppColors.iconPrimary),
                      itemBuilder: (context) {
                        return [
                          PopupMenuItem<String>(
                            value: 'playback_speed',
                            child: Row(
                              children: [
                                const HugeIcon(
                                  icon: HugeIcons.strokeRoundedDashboardCircle,
                                  size: 18,
                                  color: AppColors.iconPrimary,
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Playback speed',
                                    style:
                                        TextStyle(color: AppColors.textPrimary),
                                  ),
                                ),
                                Text(
                                  _formatPlaybackSpeed(_playbackSpeed),
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontWeight: AppTypography.weightMedium,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ];
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Bottom Bar (Progress Indicator and Controls Row)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _showControls && !_isControlsLocked ? 1.0 : 0.0,
            child: IgnorePointer(
              ignoring: !_showControls || _isControlsLocked,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      AppColors.backgroundPrimary.withValues(alpha: 0.8),
                      Colors.transparent
                    ],
                  ),
                ),
                padding: EdgeInsets.only(
                  bottom: (isPortrait && _isFullScreenManual)
                      ? math.max(48.0, mediaQuery.padding.bottom + 24.0)
                      : (isPortrait ? 0.0 : 8.0 + landscapeBottomInset),
                  left: 12.0 + landscapeLeftInset,
                  right: 12.0 + landscapeRightInset,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Controls Row Above Progress Bar
                    Padding(
                      padding: const EdgeInsets.only(bottom: 0.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          // Aspect Ratio Control (Expansion Icon)
                          _buildOverlayControlButton(
                            tooltip:
                                'Aspect Ratio (${_aspectRatioLabel(_aspectRatioMode)})',
                            onPressed: _cycleAspectRatioMode,
                            icon: HugeIcon(
                              icon: isPortrait
                                  ? HugeIcons.strokeRoundedArrowExpand01
                                  : HugeIcons.strokeRoundedArrowShrink01,
                              color: AppColors.iconPrimary,
                              size: _controlIconSize,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Full Screen Toggle
                          _buildOverlayControlButton(
                            tooltip: (isPortrait && _isFullScreenManual)
                                ? 'Exit Full Screen'
                                : (isPortrait
                                    ? 'Enter Full Screen'
                                    : 'Exit Full Screen'),
                            onPressed: _toggleFullScreen,
                            icon: Icon(
                              (isPortrait && _isFullScreenManual)
                                  ? CupertinoIcons.device_phone_portrait
                                  : (isPortrait
                                      ? CupertinoIcons.device_phone_landscape
                                      : CupertinoIcons.device_phone_portrait),
                              color: AppColors.iconPrimary,
                              size: _controlIconSize,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // REMOVED Progress Indicator from here. It is now a divider below the video frame.
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLockButton(double landscapeLeftInset) {
    return _buildOverlayControlButton(
      tooltip: 'Lock Screen',
      onPressed: () {
        setState(() {
          _isControlsLocked = true;
          _showControls = true; // Show lock button for a bit
        });
        _startHideControlsTimer();
        Vibration.vibrate(duration: 50, amplitude: 128);
      },
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.lock_open,
          color: AppColors.iconPrimary,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildUnlockButton(double landscapeLeftInset) {
    return _buildOverlayControlButton(
      tooltip: 'Unlock Screen',
      onPressed: () {
        setState(() {
          _isControlsLocked = false;
        });
        _startHideControlsTimer();
        Vibration.vibrate(duration: 50, amplitude: 128);
      },
      icon: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.7),
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.lock,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '${duration.inHours}:${twoDigits(duration.inMinutes.remainder(60))}:$seconds';
    }
    return '$minutes:$seconds';
  }

  // **NEW: Strict single-video memory management**
  void _disposeOffScreenControllers(int currentIndex) {
    final keysToRemove = <int>[];

    _controllers.forEach((index, controller) {
      if (index != currentIndex) {
        keysToRemove.add(index);
      }
    });

    for (final index in keysToRemove) {
      _savePlaybackPosition(index);

      try {
        _chewieControllers[index]?.dispose();
        _chewieControllers.remove(index);

        _controllers[index]?.dispose();
        _controllers.remove(index);

        AppLogger.log(
            '🧹 VayuLongFormPlayer: Strict disposal for off-screen video at index $index');
      } catch (e) {
        AppLogger.log(
            '⚠️ VayuLongFormPlayer: Error disposing controller for index $index: $e');
      }
    }
  }

  void _onPageChanged(int index) {
    if (index == _currentIndex) return;

    final oldIndex = _currentIndex;
    _savePlaybackPosition(oldIndex);
    _controllers[oldIndex]?.pause();

    setState(() {
      _currentIndex = index;
      _showControls = true;
    });

    // Make sure the newly scrolled-to video is initialized
    if (!_controllers.containsKey(index)) {
      _initializePlayer(index);
    } else {
      _controllers[index]?.play();
    }

    _startHideControlsTimer();

    // STRICT MEMORY MODE: Dispose all non-current videos so 100% bandwidth goes to current video
    _disposeOffScreenControllers(index);

    _loadBannerAd(index);

    if (index >= _videos.length - 3 && _hasMore && !_isLoadingMore) {
      _loadMoreVideos();
    }
  }

  Widget _buildPortraitContent(int index) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSpacing.vSpace12, // Reduced padding above banner ad
          _buildAdSection(index),
          AppSpacing.vSpace12, // Minimal spacing
          _buildVideoInfo(index),
          AppSpacing.vSpace8, // Tight spacing between info and channel
          _buildChannelRow(index),
          AppSpacing.vSpace48,
        ],
      ),
    );
  }

  Widget _buildVideoInfo(int index) {
    final video = _videos[index];
    final isPortrait =
        MediaQuery.of(context).orientation == Orientation.portrait;
    return Padding(
      // Minimalist padding: less top/bottom, strong horizontal
      padding: isPortrait
          ? const EdgeInsets.fromLTRB(16, 0, 16, 4)
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _compactTitle(video.videoName, maxChars: 80),
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: AppTypography
                        .weightSemiBold, // Slightly bolder but tighter
                    height: 1.2, // Tighter line height
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppSpacing.hSpace8,
              // Negative spacing effect to align icon perfectly with top text
              Transform.translate(
                offset: const Offset(8, -8),
                child: IconButton(
                  onPressed: () => _handleToggleSave(index),
                  icon: HugeIcon(
                    icon: video.isSaved
                        ? HugeIcons.strokeRoundedBookmark01
                        : HugeIcons.strokeRoundedBookmark01,
                    color: video.isSaved
                        ? AppColors.primary
                        : AppColors.textSecondary, // Softer unselected color
                    size: 24, // Slightly smaller icon
                  ),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                ),
              ),
            ],
          ),
          // Negative or no spacing here to pull the timestamp closer to title
          Transform.translate(
            offset: const Offset(0, -8),
            child: Text(
              '${_formatViews(video.views)} • ${_formatTimeAgo(video.uploadedAt)}',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textTertiary, // More subtle timestamp
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdSection(int index) {
    final adData = _bannerAdsByIndex[index];
    if (adData == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: BannerAdSection(
        adData: {
          ...adData,
          'creatorId': _videos[index].uploader.id,
        },
        onVideoPause: () => _controllers[index]?.pause(),
        onVideoResume: () => _controllers[index]?.play(),
      ),
    );
  }

  Widget _buildChannelRow(int index) {
    final video = _videos[index];
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: 16.0), // Removed vertical padding
      child: Row(
        children: [
          InteractiveScaleButton(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ProfileScreen(userId: video.uploader.id),
                ),
              );
            },
            scaleDownFactor: 0.9,
            child: CircleAvatar(
              radius: 20,
              backgroundImage: video.uploader.profilePic.isNotEmpty
                  ? CachedNetworkImageProvider(video.uploader.profilePic)
                  : null,
              backgroundColor: AppColors.backgroundSecondary,
              child: video.uploader.profilePic.isEmpty
                  ? const HugeIcon(
                      icon: HugeIcons.strokeRoundedUser,
                      color: AppColors.textPrimary)
                  : null,
            ),
          ),
          AppSpacing.hSpace12,
          Expanded(
            child: InteractiveScaleButton(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        ProfileScreen(userId: video.uploader.id),
                  ),
                );
              },
              scaleDownFactor: 0.98,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.uploader.name,
                    style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: AppTypography.weightBold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (video.uploader.totalVideos != null &&
                      video.uploader.totalVideos! > 0)
                    Text(
                      '${video.uploader.totalVideos} videos',
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.textSecondary),
                    ),
                ],
              ),
            ),
          ),
          AppSpacing.hSpace12,
          FollowButtonWidget(
            uploaderId: video.uploader.id,
            uploaderName: video.uploader.name,
          ),
        ],
      ),
    );
  }
}
