import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:vibration/vibration.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:vayu/features/video/video_model.dart';
import 'package:vayu/features/auth/data/services/authservices.dart';
import 'package:vayu/features/video/presentation/managers/main_controller.dart';
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
import 'package:vayu/features/ads/data/services/ad_impression_service.dart';
import 'package:vayu/features/video/presentation/screens/video_feed_advanced/widgets/banner_ad_section.dart';
import 'package:vayu/shared/widgets/app_button.dart';
import 'package:vayu/features/auth/presentation/controllers/google_sign_in_controller.dart';
import 'package:vayu/shared/widgets/interactive_scale_button.dart';

enum _AspectRatioMode {
  fit,
  crop,
  stretch,
  ratio16x9,
}

class VayuLongFormPlayerScreen extends StatefulWidget {
  final VideoModel video;
  final List<VideoModel> relatedVideos;

  const VayuLongFormPlayerScreen({
    Key? key,
    required this.video,
    this.relatedVideos = const [],
  }) : super(key: key);

  @override
  State<VayuLongFormPlayerScreen> createState() => _VayuLongFormPlayerScreenState();
}

class _VayuLongFormPlayerScreenState extends State<VayuLongFormPlayerScreen> {
  static const _controlTouchSize = 48.0;
  static const _controlIconSize = 24.0;

  late VideoPlayerController _videoPlayerController;
  ChewieController? _chewieController;
  late VideoModel _currentVideo;
  List<VideoModel> _recommendations = [];
  bool _isLoadingRecommendations = false;
  final VideoService _videoService = VideoService();

  // Banner Ad State
  final ActiveAdsService _activeAdsService = ActiveAdsService();
  final AdImpressionService _adImpressionService = AdImpressionService();
  final AuthService _authService = AuthService();
  Map<String, dynamic>? _bannerAdData;
  bool _isLoadingAd = false;

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

  // Error state
  bool _hasError = false;
  String _errorMessage = '';

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
  bool _isControlsLocked = false; // **NEW: Screen Lock State**
  bool _wakelockEnabled = false;

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
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    _currentVideo = widget.video;
    _recommendations = widget.relatedVideos.where((v) => v.id != _currentVideo.id).toList();
    _initPrefs();
    _initializePlayer();
    if (_recommendations.isEmpty) {
      _loadRecommendations();
    }
    // Load banner ad
    _loadBannerAd();

    // **NAVIGATION VISIBILITY: Hide bottom nav when entering player**
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<MainController>(context, listen: false)
            .setBottomNavVisibility(false);
      }
    });
  }

  Future<void> _initPrefs() async {
    _prefs = await SharedPreferences.getInstance();
  }

  Future<void> _initializePlayer() async {
  if (mounted) {
    setState(() {
      _hasError = false;
      _errorMessage = '';
      _chewieController = null;
    });
  }

  _disableWakelock();

  // **NEW: Force pause any other videos (e.g. from Yug tab) before starting long form**
  try {
    final mainController =
        Provider.of<MainController>(context, listen: false);
    mainController.forcePauseVideos();
    AppLogger.log(
        '🎬 VayuLongFormPlayer: Requested force pause of other videos');
  } catch (e) {
    AppLogger.log('⚠️ VayuLongFormPlayer: Error requesting video pause: $e');
  }

  // Proper disposal of existing controllers before re-initializing
  try {
    if (_chewieController != null) {
      _chewieController!.dispose();
      _chewieController = null;
    }
    // Only dispose if it was initialized or assigned
    // ignore: unnecessary_null_comparison
    if (_videoPlayerController != null) {
      _videoPlayerController.dispose();
    }
  } catch (e) {
    AppLogger.log('⚠️ VayuLongFormPlayer: Error disposing controllers: $e');
  }

  try {
    // **ENHANCED: Use VideoControllerFactory for optimized controller creation**
    AppLogger.log('🎬 VayuLongFormPlayer: Initializing for ${_currentVideo.videoName}');
    AppLogger.log('🔗 URL: ${_currentVideo.videoUrl}');

    _videoPlayerController =
        await VideoControllerFactory.createController(_currentVideo);

    // **TIMEOUT PROTECTION**: Ensure initialization doesn't hang indefinitely
    await _videoPlayerController.initialize().timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        throw TimeoutException(
            'Video loading timed out. Please check your connection.');
      },
    );
    
    // Re-apply selected playback speed for newly initialized videos.
    try {
      await _videoPlayerController.setPlaybackSpeed(_playbackSpeed);
    } catch (e) {
      AppLogger.log('⚠️ VayuLongFormPlayer: Failed to apply saved speed: $e');
    }

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      aspectRatio: _videoPlayerController.value.aspectRatio,
      autoPlay: true,
      looping: false,
      allowFullScreen: true,
      allowPlaybackSpeedChanging: true,
      showControls: false, // Hide default controls
      customControls: const SizedBox.shrink(), // Ensure no default controls are rendered
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
            child: Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textPrimary),
            ),
          ),
        );
      },
    );

    if (mounted) setState(() {});

    // Listen for position changes to save periodically
    _videoPlayerController.addListener(_onPositionChanged);
    _syncWakelockWithPlayback();

    // Resume playback logic
    _resumePlayback();

    // Fetch initial brightness and volume
    try {
      _brightnessValue = await ScreenBrightness().current;
      final currentVolume = await FlutterVolumeController.getVolume();
      if (currentVolume != null) {
        _volumeValue = currentVolume;
      }
    } catch (e) {
      AppLogger.log('⚠️ VayuLongFormPlayer: Error fetching system values: $e');
    }
  } catch (e) {
    AppLogger.log('❌ VayuLongFormPlayer: Failed to initialize: $e', isError: true);
    if (mounted) {
      setState(() {
        _hasError = true;
        _errorMessage = e.toString().contains('TimeoutException')
            ? 'Playback timed out. Check your connection.'
            : 'Failed to play video. Please try again.';
      });
    }
  }
}

  Future<void> _loadRecommendations() async {
    if (_isLoadingRecommendations) return;
    setState(() => _isLoadingRecommendations = true);
    
    try {
      final result = await _videoService.getVideos(
        videoType: 'vayu',
        limit: 10,
      );
      final List<VideoModel> videos = result['videos'];
      if (mounted) {
        setState(() {
          _recommendations = videos.where((v) => v.id != _currentVideo.id).toList();
          _isLoadingRecommendations = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingRecommendations = false);
    }
  }

  Future<void> _loadBannerAd() async {
    if (_isLoadingAd) return;
    setState(() => _isLoadingAd = true);

    try {
      AppLogger.log('🔍 VayuLongFormPlayer: Fetching ads using unified fetcher');
      
      // Use unified fetcher like Yug tab
      final ads = await _activeAdsService.fetchActiveAds();

      if (mounted) {
        setState(() {
          final List? bannerAds = ads['banner'] as List?;
          if (bannerAds != null && bannerAds.isNotEmpty) {
            final firstAd = bannerAds.first;
            if (firstAd is Map) {
              _bannerAdData = Map<String, dynamic>.from(firstAd);
              AppLogger.log('✅ VayuLongFormPlayer: Banner ad loaded: ${_bannerAdData!['title']}');
            } else {
              AppLogger.log('⚠️ VayuLongFormPlayer: First ad is not a Map: $firstAd');
              _retryLoadAdAfterDelay();
            }
          } else {
             AppLogger.log('❌ VayuLongFormPlayer: No banner ads found in unified fetch, will retry in 3s...');
             _retryLoadAdAfterDelay();
          }
          _isLoadingAd = false;
        });
      }
    } catch (e) {
      AppLogger.log('❌ Error loading banner ad: $e');
      if (mounted) {
        setState(() => _isLoadingAd = false);
        _retryLoadAdAfterDelay();
      }
    }
  }

  /// **NEW: Retry ad loading after a short delay**
  void _retryLoadAdAfterDelay() {
    if (!mounted) return;
    Future.delayed(Duration(seconds: 3), () async {
      if (!mounted || _bannerAdData != null) return;
      try {
        AppLogger.log('🔄 VayuLongFormPlayer: Retrying ad load with unified fetcher...');
        final ads = await _activeAdsService.fetchActiveAds();
        
        if (mounted) {
          final List? bannerAds = ads['banner'] as List?;
          if (bannerAds != null && bannerAds.isNotEmpty) {
            final firstAd = bannerAds.first;
            if (firstAd is Map) {
              setState(() {
                _bannerAdData = Map<String, dynamic>.from(firstAd);
              });
              AppLogger.log('✅ VayuLongFormPlayer: Ad loaded on retry');
            }
          }
        }
      } catch (e) {
        AppLogger.log('⚠️ VayuLongFormPlayer: Retry failed: $e');
      }
    });
  }

  void _switchVideo(VideoModel newVideo) {
    setState(() {
      _currentVideo = newVideo;
      // We don't clear recommendations if we navigated from a list, 
      // but let's refresh them to match the new video context if needed
    });
    _initializePlayer();
  }

  @override
  void dispose() {
    _videoPlayerController.removeListener(_onPositionChanged);
    _disableWakelock();
    _savePlaybackPosition();
    _hideControlsTimer?.cancel();
    _overlayTimer?.cancel();
    _aspectRatioOverlayTimer?.cancel();
    
    // Ensure Bottom Navigation Bar comes back when leaving
    // Reset to portrait and system UI
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    _chewieController?.dispose();
    _videoPlayerController.dispose();

    // **NAVIGATION VISIBILITY: Restore bottom nav on dispose**
    // Using a delay to ensure it doesn't flicker before the transition starts
    Future.microtask(() {
      if (context.mounted) {
        Provider.of<MainController>(context, listen: false)
            .setBottomNavVisibility(true);
      }
    });
    super.dispose();
  }

  void _onPositionChanged() {
    _syncWakelockWithPlayback();

    if (_videoPlayerController.value.isPlaying) {
      // Save every 5 seconds (roughly)
      if (_videoPlayerController.value.position.inSeconds % 5 == 0) {
        _savePlaybackPosition();
      }
    }
  }

  String _formatViews(int views) {
    if (views >= 1000000) return '${(views / 1000000).toStringAsFixed(1)}M views';
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
    if (_chewieController == null) return;
    
    _horizontalDragTotal += details.primaryDelta!;
    final currentPosition = _videoPlayerController.value.position;
    final totalDuration = _videoPlayerController.value.duration;
    
    // Sensitivity: 1 pixel = 100ms (adjust as needed)
    final seekOffset = Duration(milliseconds: (_horizontalDragTotal * 100).toInt());
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
    if (_chewieController == null) return;
    
    _videoPlayerController.seekTo(_scrubbingTargetTime);
    
    setState(() {
      _showScrubbingOverlay = false;
      _horizontalDragTotal = 0.0;
      _showControls = true; // Show controls after scrubbing
    });
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (_isControlsLocked) return;
    if (_chewieController == null) return;

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
        ScreenBrightness().setScreenBrightness(_brightnessValue);
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
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
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

  Future<void> _savePlaybackPosition() async {
    if (_videoPlayerController.value.isInitialized) {
      _prefs ??= await SharedPreferences.getInstance();
      final key = 'video_pos_${_currentVideo.id}';
      await _prefs!.setInt(key, _videoPlayerController.value.position.inSeconds);
      AppLogger.log('💾 VayuLongFormPlayer: Saved position ${_videoPlayerController.value.position.inSeconds}s for video ${_currentVideo.id}');
    }
  }

  Future<void> _resumePlayback() async {
    _prefs ??= await SharedPreferences.getInstance();
    final key = 'video_pos_${_currentVideo.id}';
    final savedSeconds = _prefs!.getInt(key);
    
    if (savedSeconds != null && savedSeconds > 0) {
      final duration = Duration(seconds: savedSeconds);
      // Ensure we don't seek past the end
      if (duration < _videoPlayerController.value.duration) {
        _videoPlayerController.seekTo(duration);
        AppLogger.log('⏪ VayuLongFormPlayer: Resumed at ${savedSeconds}s');
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
      if (mounted && _videoPlayerController.value.isPlaying && _showControls) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  void _togglePlay() {
  Vibration.vibrate(duration: 50, amplitude: 128);
    setState(() {
      if (_videoPlayerController.value.isPlaying) {
        _videoPlayerController.pause();
      } else {
        _videoPlayerController.play();
        _hideControlsWithDelay();
      }
    });
    _syncWakelockWithPlayback();
    _showFeedbackAnimation(_videoPlayerController.value.isPlaying);
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

  void _syncWakelockWithPlayback() {
    if (_videoPlayerController.value.isInitialized &&
        _videoPlayerController.value.isPlaying) {
      _enableWakelock();
      return;
    }
    _disableWakelock();
  }

  void _handleDoubleTapToSeek(TapDownDetails details) {
    if (_chewieController == null ||
        !_videoPlayerController.value.isInitialized) {
      return;
    }

    final size = MediaQuery.of(context).size;
    final isLeftSide = details.localPosition.dx < size.width / 2;
    final seekOffset =
        Duration(seconds: isLeftSide ? -10 : 10);
    final duration = _videoPlayerController.value.duration;
    var targetPosition = _videoPlayerController.value.position + seekOffset;

    if (targetPosition < Duration.zero) targetPosition = Duration.zero;
    if (targetPosition > duration) targetPosition = duration;

    _videoPlayerController.seekTo(targetPosition);

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

  Future<void> _handleToggleSave() async {
    if (_isSaving) return;

    try {
      setState(() => _isSaving = true);
      HapticFeedback.lightImpact();

      final isSaved = await _videoService.toggleSave(_currentVideo.id);

      setState(() {
        _currentVideo.isSaved = isSaved;
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isSaved ? 'Video saved to bookmarks' : 'Video removed from bookmarks'),
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
      if (_videoPlayerController.value.isInitialized) {
        await _videoPlayerController.setPlaybackSpeed(speed);
      }

      if (mounted) {
        setState(() {
          _playbackSpeed = speed;
        });
      } else {
        _playbackSpeed = speed;
      }
    } catch (e) {
      AppLogger.log('❌ VayuLongFormPlayer: Failed to change playback speed: $e');
    }
  }

  void _toggleFullScreen() {
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
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
      _showControls = true;
    });
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
            leading: SizedBox(
              width: 20,
              child: isSelected
                  ? const HugeIcon(icon: HugeIcons.strokeRoundedCheckmarkCircle01,
                      size: 18,
                      color: AppColors.primary,
                    )
                  : null,
            ),
            title: Text(
              _formatPlaybackSpeed(speed),
              style: TextStyle(
                color: isSelected ? AppColors.textPrimary : AppColors.textSecondary,
                fontWeight: isSelected ? AppTypography.weightSemiBold : AppTypography.weightMedium,
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

  Widget _buildVideoPlayerWithAspectMode() {
    final controller = _chewieController!.videoPlayerController;
    final sourceSize = controller.value.size;
    final bool hasValidSize = sourceSize.width > 0 && sourceSize.height > 0;
    final double sourceWidth = hasValidSize ? sourceSize.width : 1920;
    final double sourceHeight = hasValidSize ? sourceSize.height : 1080;

    final Widget player = SizedBox(
      width: sourceWidth,
      height: sourceHeight,
      child: Chewie(controller: _chewieController!),
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
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.spacing6, vertical: AppSpacing.spacing3),
            decoration: BoxDecoration(
              color: AppColors.backgroundSecondary.withOpacity(0.45),
              borderRadius: AppRadius.borderRadiusPill,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HugeIcon(
                  icon: _isForward ? HugeIcons.strokeRoundedArrowRightDouble : HugeIcons.strokeRoundedArrowLeftDouble,
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
            color: AppColors.backgroundSecondary.withOpacity(0.54),
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
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          // **NAVIGATION VISIBILITY: Ensure bottom nav is restored on pop**
          Provider.of<MainController>(context, listen: false)
              .setBottomNavVisibility(true);
        }
      },
      child: Consumer<GoogleSignInController>(
        builder: (context, authController, _) {
          return Scaffold(
            backgroundColor: AppColors.backgroundPrimary,
            body: OrientationBuilder(
              builder: (context, orientation) {
                if (orientation == Orientation.landscape) {
                  if (_showControls) {
                    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
                        overlays: SystemUiOverlay.values);
                  } else {
                    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
                  }
                  return _buildVideoSection(orientation);
                }

                // ALWAYS show system UI in portrait
                SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual,
                    overlays: SystemUiOverlay.values);

                return SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildVideoSection(orientation), // Video Player
                      // _buildAdSection moved to _buildContentSection
                      Expanded(
                        child: _buildContentSection(),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildVideoSection(Orientation orientation) {
    final size = MediaQuery.of(context).size;

    if (orientation == Orientation.landscape) {
      // Fullscreen: fill entire screen
      return SizedBox(
        width: size.width,
        height: size.height,
        child: Stack(
        children: [
          if (_hasError)
            Container(
              color: AppColors.backgroundPrimary,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const HugeIcon(icon: HugeIcons.strokeRoundedAlertCircle, color: AppColors.textTertiary, size: 48),
                    AppSpacing.vSpace16,
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _errorMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                      ),
                    ),
                    AppSpacing.vSpace24,
                    AppButton(
                      onPressed: _initializePlayer,
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedRefresh),
                      label: 'Try Again',
                      variant: AppButtonVariant.primary,
                    ),
                  ],
                ),
              ),
            )
          else if (_chewieController != null &&
                  _chewieController!.videoPlayerController.value.isInitialized)
              Hero(
                tag: 'video_player_${_currentVideo.id}',
                child: _buildVideoPlayerWithAspectMode(),
              )
          else
            Container(
                  color: AppColors.backgroundPrimary,
                  child: const Center(
                      child: CircularProgressIndicator(color: AppColors.primary)),
                ),

          // Gesture Overlay for Controls and Scrubbing
          if (_chewieController != null &&
              _chewieController!.videoPlayerController.value.isInitialized)
            GestureDetector(
              onTap: _handleTap,
              onDoubleTapDown: _handleDoubleTapToSeek,
              onHorizontalDragStart: (details) {
                setState(() {
                  _horizontalDragTotal = 0.0;
                  _showControls = false;
                });
              },
              onHorizontalDragUpdate: (details) {
                _handleHorizontalDragUpdate(details);
              },
              onHorizontalDragEnd: (details) {
                _handleHorizontalDragEnd();
              },
              onVerticalDragUpdate: _handleVerticalDragUpdate,
              onVerticalDragEnd: (details) => _handleVerticalDragEnd(),
              behavior: HitTestBehavior.translucent,
            ),

          // Custom Controls Overlay including Center Area
          if (_chewieController != null &&
              _chewieController!.videoPlayerController.value.isInitialized)
            AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: _showControls ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: _buildCustomControls(),
              ),
            ),

          // Scrubbing UI Overlay
          AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: _showScrubbingOverlay ? 1.0 : 0.0,
            child: IgnorePointer(
              ignoring: !_showScrubbingOverlay,
              child: _buildScrubbingOverlay(),
            ),
          ),
          if (_aspectRatioOverlayText != null) _buildAspectRatioOverlay(),
        ],
      ),
    );
    }

    // Portrait mode: fixed height regardless of video aspect ratio
    // Video will be letterboxed/pillarboxed inside this fixed container
    final fixedHeight = size.width * 9 / 16; // Standard 16:9 height
    return SizedBox(
      width: size.width,
      height: fixedHeight,
      child: Container(
        color: AppColors.backgroundPrimary,
        child: Stack(
          children: [
            if (_hasError)
              Container(
                color: AppColors.backgroundPrimary,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                       const HugeIcon(icon: HugeIcons.strokeRoundedAlertCircle, color: AppColors.textTertiary, size: 48),
                      AppSpacing.vSpace16,
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          _errorMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (_chewieController != null &&
                _chewieController!.videoPlayerController.value.isInitialized)
              Hero(
                tag: 'video_player_${_currentVideo.id}',
                child: _buildVideoPlayerWithAspectMode(),
              )
            else
              Container(
                color: AppColors.backgroundPrimary,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.textPrimary),
                ),
              ),

            // Gesture detection overlay
            if (_chewieController != null &&
                _chewieController!.videoPlayerController.value.isInitialized)
            GestureDetector(
              onTap: _handleTap,
              onDoubleTapDown: _handleDoubleTapToSeek,
              onHorizontalDragStart: (details) {
                setState(() {
                  _horizontalDragTotal = 0.0;
                  _showControls = false;
                });
              },
              onHorizontalDragUpdate: (details) {
                _handleHorizontalDragUpdate(details);
              },
              onHorizontalDragEnd: (details) {
                _handleHorizontalDragEnd();
              },
              onVerticalDragUpdate: _handleVerticalDragUpdate,
              onVerticalDragEnd: (details) => _handleVerticalDragEnd(),
              behavior: HitTestBehavior.translucent,
            ),

            if (_chewieController != null &&
                _chewieController!.videoPlayerController.value.isInitialized)
              AnimatedOpacity(
                duration: Duration(milliseconds: 200),
                opacity: _showControls ? 1.0 : 0.0,
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: _buildCustomControls(),
                ),
              ),

            AnimatedOpacity(
              duration: Duration(milliseconds: 150),
              opacity: _showScrubbingOverlay ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !_showScrubbingOverlay,
                child: _buildScrubbingOverlay(),
              ),
            ),
            if (_aspectRatioOverlayText != null) _buildAspectRatioOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildContentSection() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAdSection(),
          _buildVideoInfo(),
          _buildActionBar(),
          AppSpacing.vSpace16,
          _buildChannelRow(),
          AppSpacing.vSpace24,
          _buildRecommendations(),
        ],
      ),
    );
  }

  Widget _buildVideoInfo() {
    return Padding(
      padding: AppSpacing.edgeInsetsAll16,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _compactTitle(_currentVideo.videoName, maxChars: 80),
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: AppTypography.weightMedium,
                    height: 1.25,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              AppSpacing.hSpace8,
              IconButton(
                onPressed: _handleToggleSave,
                icon: HugeIcon(
                  icon: _currentVideo.isSaved ? HugeIcons.strokeRoundedBookmark01 : HugeIcons.strokeRoundedBookmark01,
                  color: _currentVideo.isSaved ? AppColors.primary : AppColors.textPrimary,
                  size: 28,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          AppSpacing.vSpace4,
          Row(
            children: [
              Text(
                '${_formatViews(_currentVideo.views)} • ${_formatTimeAgo(_currentVideo.uploadedAt)}',
                style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return const SizedBox.shrink(); // Save button moved to title area
  }

  Widget _buildChannelRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          InteractiveScaleButton(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileScreen(userId: _currentVideo.uploader.id),
                ),
              );
            },
            scaleDownFactor: 0.9,
            child: CircleAvatar(
              radius: 20,
              backgroundImage: _currentVideo.uploader.profilePic.isNotEmpty
                  ? CachedNetworkImageProvider(_currentVideo.uploader.profilePic)
                  : null,
              backgroundColor: AppColors.backgroundSecondary,
              child: _currentVideo.uploader.profilePic.isEmpty
                  ? const HugeIcon(icon: HugeIcons.strokeRoundedUser, color: AppColors.textPrimary)
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
                    builder: (context) => ProfileScreen(userId: _currentVideo.uploader.id),
                  ),
                );
              },
              scaleDownFactor: 0.98,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentVideo.uploader.name,
                    style: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary, fontWeight: AppTypography.weightBold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${_currentVideo.uploader.totalVideos ?? 0} videos', 
                    style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          FollowButtonWidget(
            uploaderId: _currentVideo.uploader.id,
            uploaderName: _currentVideo.uploader.name,
            followText: 'Subscribe',
            followingText: 'Subscribed',
            onFollowChanged: () {
              // Optionally refresh uploader info if needed
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAdSection() {
    if (_bannerAdData == null) {
      if (_isLoadingAd) {
        return Container(
          width: double.infinity,
          height: 60,
          color: AppColors.backgroundPrimary,
          child: Center(
            child: Text(
              'Sponsored Content Loading...',
              style: TextStyle(color: AppColors.textTertiary.withOpacity(0.1), fontSize: 10),
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }
    
    AppLogger.log('🎬 VayuLongFormPlayer: Rendering ad section for ${_bannerAdData!['title'] ?? 'Unknown Ad'}');

    return Container(
      width: double.infinity,
      color: AppColors.backgroundPrimary,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        height: 60,
        child: Stack(
          children: [
            BannerAdSection(
              adData: {
                ..._bannerAdData!,
                'creatorId': _currentVideo.uploader.id, // **NEW: Pass creatorId**
              },
              onVideoPause: () {
                // Pause the long-form video while the browser is open
                if (_videoPlayerController.value.isPlaying) {
                  _videoPlayerController.pause();
                }
              },
              onVideoResume: () {
                // Resume the long-form video when the browser is closed
                _videoPlayerController.play();
              },
              onClick: () {
                AppLogger.log('🖱️ Banner Ad Clicked');
              },
              onImpression: () async {
                if (_bannerAdData != null) {
                  final adId = _bannerAdData!['_id'] ?? _bannerAdData!['id'];

                  // **NEW: Check if viewer is the creator**
                  final userData = await _authService.getUserData();
                  final currentUserId = userData?['id'];
                  
                  if (currentUserId != null && currentUserId == _currentVideo.uploader.id) {
                       AppLogger.log('🚫 Player: Self-impression prevented (video owner)');
                       return;
                  }

                  if (adId != null) {
                    await _adImpressionService.trackBannerAdImpression(
                      videoId: _currentVideo.id,
                      adId: adId.toString(),
                      userId: currentUserId ?? _currentVideo.uploader.id,
                    );
                    AppLogger.log('📊 Banner Ad Impression tracked');
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendations() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Text(
            'Up Next',
            style: AppTypography.headlineMedium.copyWith(
              color: AppColors.textPrimary,
              fontWeight: AppTypography.weightBold,
            ),
          ),
        ),
        if (_isLoadingRecommendations)
          const Center(child: CircularProgressIndicator(color: AppColors.primary))
        else if (_recommendations.isEmpty)
          const Padding(
            padding: AppSpacing.edgeInsetsAll16,
            child: Text('No recommendations available', style: TextStyle(color: AppColors.textSecondary)),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _recommendations.length,
            itemBuilder: (context, index) {
              final video = _recommendations[index];
              return InteractiveScaleButton(
                onTap: () => _switchVideo(video),
                scaleDownFactor: 0.98,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Thumbnail Section (16:9 full width)
                    Stack(
                      children: [
                        AspectRatio(
                          aspectRatio: 16 / 9,
                          child: CachedNetworkImage(
                            imageUrl: video.thumbnailUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              color: AppColors.backgroundPrimary,
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: AppColors.backgroundPrimary,
                              child: const HugeIcon(icon: HugeIcons.strokeRoundedImage01,
                                  color: AppColors.borderPrimary),
                            ),
                          ),
                        ),
                        // Duration Badge
                        if (video.duration.inSeconds > 0)
                          Positioned(
                            bottom: 8,
                            right: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.backgroundPrimary.withOpacity(0.85),
                                borderRadius: AppRadius.borderRadiusXS,
                              ),
                              child: Text(
                                _formatDuration(video.duration),
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontWeight: AppTypography.weightBold,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),

                    // 2. Info Section (Below Thumbnail)
                    Container(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Avatar
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: AppColors.backgroundPrimary,
                            backgroundImage: video.uploader.profilePic.isNotEmpty
                                ? CachedNetworkImageProvider(
                                    video.uploader.profilePic)
                                : null,
                            child: video.uploader.profilePic.isEmpty
                                ? const HugeIcon(icon: HugeIcons.strokeRoundedUser,
                                    size: 20, color: AppColors.textPrimary)
                                : null,
                          ),
                          AppSpacing.hSpace12,
                          // Text Info
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Title
                                Text(
                                  video.videoName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.bodyLarge.copyWith(
                                    color: AppColors.textPrimary,
                                    fontWeight: AppTypography.weightSemiBold,
                                    height: 1.2,
                                  ),
                                ),
                                AppSpacing.vSpace4,
                                // Meta: Channel • Views • Time
                                Text(
                                  '${video.uploader.name} • ${_formatViews(video.views)} • ${_formatTimeAgo(video.uploadedAt)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.textSecondary,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    AppSpacing.vSpace8,
                  ],
                ),
              );
            },
          ),
        SizedBox(height: 20),
      ],
    );
  }

  Widget _buildCustomControls() {
    final mediaQuery = MediaQuery.of(context);
    final isPortrait = mediaQuery.orientation == Orientation.portrait;
    final viewPadding = mediaQuery.viewPadding;
    // In landscape, keep controls away from system nav/cutout edges.
    final double landscapeLeftInset = isPortrait ? 0.0 : viewPadding.left;
    final double landscapeRightInset = isPortrait ? 0.0 : viewPadding.right;
    final double landscapeTopInset = isPortrait ? 0.0 : viewPadding.top;
    final double landscapeBottomInset = isPortrait ? 0.0 : viewPadding.bottom;
    
    return Stack(
      children: [
        // Tap on empty area to toggle controls
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
            onHorizontalDragUpdate: (details) {
              _handleHorizontalDragUpdate(details);
            },
            onHorizontalDragEnd: (details) {
              _handleHorizontalDragEnd();
            },
            onVerticalDragUpdate: _handleVerticalDragUpdate,
            onVerticalDragEnd: (details) => _handleVerticalDragEnd(),
            behavior: HitTestBehavior.translucent,
            child: Container(color: Colors.transparent),
          ),
        ),

        // Lock Toggle Button (Floating on the left)
        AnimatedPositioned(
          duration: const Duration(milliseconds: 250),
          left: _showControls ? (12.0 + landscapeLeftInset) : -60.0,
          top: mediaQuery.size.height / 2 - 24,
          child: _isControlsLocked
              ? _buildUnlockButton(landscapeLeftInset)
              : _buildLockButton(landscapeLeftInset),
        ),

        // Top bar (Back button, Title)
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
                    colors: [AppColors.backgroundPrimary.withValues(alpha:0.7), Colors.transparent],
                  ),
                ),
                padding: EdgeInsets.fromLTRB(
                  8.0 + landscapeLeftInset,
                  4.0 + landscapeTopInset,
                  8.0 + landscapeRightInset,
                  4.0,
                ),
                child: Row(
                  children: [
                    SizedBox(
                      width: _controlTouchSize,
                      height: _controlTouchSize,
                      child: IconButton(
                        iconSize: _controlIconSize,
                        icon: const HugeIcon(icon: HugeIcons.strokeRoundedArrowLeft01, color: AppColors.iconPrimary),
                        onPressed: () => Navigator.of(context).pop(),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: _controlTouchSize,
                          minHeight: _controlTouchSize,
                        ),
                      ),
                    ),
                    AppSpacing.hSpace8,
                    Expanded(
                      child: Text(
                        _compactTitle(
                          _currentVideo.videoName,
                          maxChars: isPortrait ? 72 : 56,
                        ),
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: AppTypography.weightMedium,
                          fontSize: isPortrait ? 12 : 14,
                          shadows: [
                            Shadow(blurRadius: 4, color: AppColors.backgroundSecondary.withOpacity(0.45), offset: Offset(0, 1)),
                          ],
                        ),
                        maxLines: isPortrait ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'More options',
                      color: AppColors.backgroundSecondary.withOpacity(0.95),
                      onSelected: (value) {
                        if (value == 'playback_speed') {
                          _showPlaybackSpeedOptions();
                        }
                      },
                      iconSize: _controlIconSize,
                      icon: const HugeIcon(icon: HugeIcons.strokeRoundedMoreVertical, color: AppColors.iconPrimary),
                      itemBuilder: (context) {
                        return [
                          PopupMenuItem<String>(
                            value: 'playback_speed',
                            child: Row(
                              children: [
                                const HugeIcon(icon: HugeIcons.strokeRoundedDashboardCircle,
                                  size: 18,
                                  color: AppColors.iconPrimary,
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Text(
                                    'Playback speed',
                                    style: TextStyle(color: AppColors.textPrimary),
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
                    colors: [AppColors.backgroundPrimary.withOpacity(0.8), Colors.transparent],
                  ),
                ),
                padding: EdgeInsets.only(
                  bottom: 4.0 + landscapeBottomInset,
                  left: 12.0 + landscapeLeftInset,
                  right: 12.0 + landscapeRightInset,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Progress Indicator with Time Labels
                    Row(
                      children: [
                        ValueListenableBuilder(
                          valueListenable: _videoPlayerController,
                          builder: (context, VideoPlayerValue value, child) {
                            return Text(
                              _formatDuration(value.position),
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 10,
                                fontWeight: AppTypography.weightMedium,
                              ),
                            );
                          },
                        ),
                        Expanded(
                          child: ValueListenableBuilder(
                            valueListenable: _videoPlayerController,
                            builder: (context, VideoPlayerValue value, child) {
                              return VideoProgressIndicator(
                                _videoPlayerController,
                                allowScrubbing: true,
                                padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 8.0),
                                colors: VideoProgressColors(
                                  playedColor: AppColors.primary,
                                  bufferedColor: AppColors.textPrimary.withValues(alpha: 0.3),
                                  backgroundColor: AppColors.textPrimary.withValues(alpha: 0.1),
                                ),
                              );
                            },
                          ),
                        ),
                        ValueListenableBuilder(
                          valueListenable: _videoPlayerController,
                          builder: (context, VideoPlayerValue value, child) {
                            return Text(
                              _formatDuration(value.duration),
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 10,
                                fontWeight: AppTypography.weightMedium,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    // Controls Row
                    Padding(
                      padding: const EdgeInsets.only(top: 0.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Play/Pause (center)
                          ValueListenableBuilder<VideoPlayerValue>(
                            valueListenable: _videoPlayerController,
                            builder: (context, value, _) {
                              final isPlaying = value.isPlaying;
                              return _buildOverlayControlButton(
                                icon: HugeIcon(
                                  icon: isPlaying
                                      ? HugeIcons.strokeRoundedPause
                                      : HugeIcons.strokeRoundedPlay,
                                  color: AppColors.iconPrimary,
                                  size: _controlIconSize,
                                ),
                                onPressed: _togglePlay,
                                tooltip: isPlaying ? 'Pause' : 'Play',
                              );
                            },
                          ),
                          const SizedBox(width: 16),
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
                          const SizedBox(width: 16),
                          // Full Screen Toggle (Orientation Icon)
                          _buildOverlayControlButton(
                            tooltip: isPortrait ? 'Enter Full Screen' : 'Exit Full Screen',
                            onPressed: _toggleFullScreen,
                            icon: Icon(
                              isPortrait
                                  ? CupertinoIcons.device_phone_landscape
                                  : CupertinoIcons.device_phone_portrait,
                              color: AppColors.iconPrimary,
                              size: _controlIconSize,
                            ),
                          ),
                        ],
                      ),
                    ),
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
          color: AppColors.backgroundSecondary.withOpacity(0.5),
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
          color: AppColors.primary.withOpacity(0.7),
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
}
