import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:vayu/features/video/video_model.dart';
import 'package:vayu/features/auth/data/services/authservices.dart';
import 'package:vayu/features/video/presentation/managers/main_controller.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'dart:async';
import 'package:vayu/features/video/data/services/video_service.dart';
import 'package:vayu/features/profile/presentation/screens/profile_screen.dart';
import 'package:vayu/shared/widgets/follow_button_widget.dart';
import 'package:vayu/shared/theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayu/shared/factories/video_controller_factory.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/features/ads/data/services/active_ads_service.dart';
import 'package:vayu/features/ads/data/services/ad_impression_service.dart';
import 'package:vayu/features/video/presentation/screens/video_feed_advanced/widgets/banner_ad_section.dart';

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
  bool _showPlayPauseAnimation = false;
  final bool _isAnimatingForward = true;
  Duration _scrubbingTargetTime = Duration.zero;
  Duration _scrubbingDelta = Duration.zero;
  double _horizontalDragTotal = 0.0;
  bool _isForward = true;
  bool _isFullScreen = false;
  Timer? _hideControlsTimer;

  // Gesture state (MX Player style)
  final double _verticalDragTotal = 0.0;
  bool _showBrightnessOverlay = false;
  bool _showVolumeOverlay = false;
  double _brightnessValue = 0.5;
  double _volumeValue = 0.5;
  Timer? _overlayTimer;
  SharedPreferences? _prefs;

  // Error state
  bool _hasError = false;
  String _errorMessage = '';

  bool _isSaving = false;

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
        playedColor: AppTheme.primary,
        handleColor: AppTheme.primary,
        backgroundColor: Colors.white24,
        bufferedColor: Colors.white54,
      ),
      placeholder: Container(
        color: Colors.black,
        child: const Center(
            child: CircularProgressIndicator(color: AppTheme.primary)),
      ),
      errorBuilder: (context, errorMessage) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              errorMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        );
      },
    );

    if (mounted) setState(() {});

    // Listen for position changes to save periodically
    _videoPlayerController.addListener(_onPositionChanged);

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
    Future.delayed(const Duration(seconds: 3), () async {
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
    _savePlaybackPosition();
    _hideControlsTimer?.cancel();
    _overlayTimer?.cancel();
    // Reset to portrait and system UI
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    _chewieController?.dispose();
    _videoPlayerController.dispose();
    super.dispose();
  }

  void _onPositionChanged() {
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
        _showBrightnessOverlay = true;
        _showVolumeOverlay = false;
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
        _showVolumeOverlay = true;
        _showBrightnessOverlay = false;
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
      if (mounted) {
        setState(() {
          _showBrightnessOverlay = false;
          _showVolumeOverlay = false;
        });
      }
    });
  }

  void _handleTap() {
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
    setState(() {
      _showPlayPauseAnimation = true;
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _showPlayPauseAnimation = false;
        });
      }
    });
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
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
    setState(() {
      if (_videoPlayerController.value.isPlaying) {
        _videoPlayerController.pause();
      } else {
        _videoPlayerController.play();
        _hideControlsWithDelay();
      }
    });
    _showFeedbackAnimation(_videoPlayerController.value.isPlaying);
  }

  void _seekRelative(Duration offset) {
    final newPosition = _videoPlayerController.value.position + offset;
    _videoPlayerController.seekTo(newPosition);
    setState(() {
      _showControls = true;
    });
    
    // Sync system UI in landscape
    if (MediaQuery.of(context).orientation == Orientation.landscape) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    }

    _startHideControlsTimer();
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
    });
    
    if (_isFullScreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      // Sync system UI based on controls
      if (_showControls) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    }
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

  Widget _buildScrubbingOverlay() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Semi-transparent backdrop for content
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(40),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isForward ? Icons.forward_10 : Icons.replay_10,
                  color: Colors.white,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Text(
                  '${_isForward ? "+" : ""}${_scrubbingDelta.inSeconds.abs()}s',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        blurRadius: 10.0,
                        color: Colors.black,
                        offset: Offset(0, 0),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _formatDuration(_scrubbingTargetTime),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              shadows: [
                Shadow(
                  blurRadius: 10.0,
                  color: Colors.black,
                  offset: Offset(2, 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrightnessOverlay() {
    return _buildGestureOverlay(
      icon: Icons.brightness_6,
      value: _brightnessValue,
      label: 'Brightness',
    );
  }

  Widget _buildVolumeOverlay() {
    return _buildGestureOverlay(
      icon: _volumeValue == 0 ? Icons.volume_off : Icons.volume_up,
      value: _volumeValue,
      label: 'Volume',
    );
  }

  Widget _buildGestureOverlay({
    required IconData icon,
    required double value,
    required String label,
  }) {
    return Center(
      child: Container(
        width: 160,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.black45,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white12, width: 1),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Text(
                  '${(value * 100).toInt()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                backgroundColor: Colors.white10,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                minHeight: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: OrientationBuilder(
        builder: (context, orientation) {
          // Auto-fullscreen logic: if device rotates to landscape, enter fullscreen
          if (orientation == Orientation.landscape && !_isFullScreen) {
            _isFullScreen = false;
            // Controls show by default on new video/orientation change, so sync UI
            if (_showControls) {
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
            } else {
              SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
            }
          } else if (orientation == Orientation.portrait && _isFullScreen) {
            _isFullScreen = false;
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
          } else if (orientation == Orientation.portrait) {
            // ALWAYS show system UI in portrait
            SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
          }

          if (orientation == Orientation.landscape) {
            return PopScope(
              canPop: !_isFullScreen,
              onPopInvokedWithResult: (didPop, result) async {
                if (didPop) return;
                if (_isFullScreen) {
                  _toggleFullScreen();
                }
              },
              child: _buildVideoSection(orientation),
            );
          }

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
              color: Colors.black,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white54, size: 48),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        _errorMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _initializePlayer,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try Again'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else if (_chewieController != null &&
                  _chewieController!.videoPlayerController.value.isInitialized)
              Chewie(controller: _chewieController!)
          else
            Container(
                  color: Colors.black,
                  child: const Center(
                      child: CircularProgressIndicator(color: AppTheme.primary)),
                ),

          // Gesture Overlay for Controls and Scrubbing
          if (_chewieController != null &&
              _chewieController!.videoPlayerController.value.isInitialized)
            GestureDetector(
              onTap: _handleTap,
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

          // Play/Pause Feedback Animation
          if (_showPlayPauseAnimation)
            Center(
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Colors.black26,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _videoPlayerController.value.isPlaying
                      ? Icons.play_arrow
                      : Icons.pause,
                  color: Colors.white,
                  size: 60,
                ),
              ),
            ),

          // Brightness Overlay
          if (_showBrightnessOverlay)
            _buildBrightnessOverlay(),

          // Volume Overlay
          if (_showVolumeOverlay)
            _buildVolumeOverlay(),

          // Custom Controls Overlay
          if (_showControls &&
              _chewieController != null &&
              _chewieController!.videoPlayerController.value.isInitialized)
            _buildCustomControls(),

          // Scrubbing UI Overlay
          if (_showScrubbingOverlay) _buildScrubbingOverlay(),
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
        color: Colors.black,
        child: Stack(
          children: [
            if (_hasError)
              Container(
                color: Colors.black,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, color: Colors.white54, size: 48),
                      const SizedBox(height: 16),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          _errorMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (_chewieController != null &&
                _chewieController!.videoPlayerController.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: _videoPlayerController.value.aspectRatio,
                  child: Chewie(controller: _chewieController!),
                ),
              )
            else
              Container(
                color: Colors.black,
                child: const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
              ),

            // Gesture detection overlay
            if (_chewieController != null &&
                _chewieController!.videoPlayerController.value.isInitialized)
            GestureDetector(
              onTap: _handleTap,
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

            if (_showPlayPauseAnimation)
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: const BoxDecoration(
                    color: Colors.black26,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _videoPlayerController.value.isPlaying
                        ? Icons.play_arrow
                        : Icons.pause,
                    color: Colors.white,
                    size: 60,
                  ),
                ),
              ),

            if (_showBrightnessOverlay)
              _buildBrightnessOverlay(),

            if (_showVolumeOverlay)
              _buildVolumeOverlay(),

            if (_showControls &&
                _chewieController != null &&
                _chewieController!.videoPlayerController.value.isInitialized)
              _buildCustomControls(),

            if (_showScrubbingOverlay) _buildScrubbingOverlay(),
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
          const Divider(color: Colors.white24, height: 1),
          _buildChannelRow(),
          const Divider(color: Colors.white24, height: 1),
          _buildRecommendations(),
        ],
      ),
    );
  }

  Widget _buildVideoInfo() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _currentVideo.videoName,
                  style: AppTheme.headlineMedium.copyWith(color: Colors.white),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _handleToggleSave,
                icon: Icon(
                  _currentVideo.isSaved ? Icons.bookmark : Icons.bookmark_border,
                  color: _currentVideo.isSaved ? AppTheme.primary : Colors.white,
                  size: 28,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '${_formatViews(_currentVideo.views)} • ${_formatTimeAgo(_currentVideo.uploadedAt)}',
                style: AppTheme.bodySmall.copyWith(color: Colors.grey),
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
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ProfileScreen(userId: _currentVideo.uploader.id),
                ),
              );
            },
            child: CircleAvatar(
              radius: 20,
              backgroundImage: _currentVideo.uploader.profilePic.isNotEmpty
                  ? CachedNetworkImageProvider(_currentVideo.uploader.profilePic)
                  : null,
              backgroundColor: Colors.grey[800],
              child: _currentVideo.uploader.profilePic.isEmpty
                  ? const Icon(Icons.person, color: Colors.white)
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfileScreen(userId: _currentVideo.uploader.id),
                  ),
                );
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentVideo.uploader.name,
                    style: AppTheme.bodyLarge.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${_currentVideo.uploader.totalVideos ?? 0} videos', 
                    style: AppTheme.bodySmall.copyWith(color: Colors.grey),
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
          color: Colors.black,
          child: const Center(
            child: Text(
              'Sponsored Content Loading...',
              style: TextStyle(color: Colors.white10, fontSize: 10),
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }
    
    AppLogger.log('🎬 VayuLongFormPlayer: Rendering ad section for ${_bannerAdData!['title'] ?? 'Unknown Ad'}');

    return Container(
      width: double.infinity,
      color: Colors.black,
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
            style: AppTheme.headlineMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        if (_isLoadingRecommendations)
          const Center(child: CircularProgressIndicator(color: AppTheme.primary))
        else if (_recommendations.isEmpty)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text('No recommendations available', style: TextStyle(color: Colors.grey)),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _recommendations.length,
            itemBuilder: (context, index) {
              final video = _recommendations[index];
              return InkWell(
                onTap: () => _switchVideo(video),
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
                              color: Colors.grey[900],
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey[900],
                              child: const Icon(Icons.broken_image,
                                  color: Colors.white24),
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
                                color: Colors.black.withOpacity(0.85),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                _formatDuration(video.duration),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
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
                            radius: 18,
                            backgroundColor: Colors.grey[900],
                            backgroundImage: video.uploader.profilePic.isNotEmpty
                                ? CachedNetworkImageProvider(
                                    video.uploader.profilePic)
                                : null,
                            child: video.uploader.profilePic.isEmpty
                                ? const Icon(Icons.person,
                                    size: 20, color: Colors.white)
                                : null,
                          ),
                          const SizedBox(width: 12),
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
                                  style: AppTheme.bodyLarge.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                // Meta: Channel • Views • Time
                                Text(
                                  '${video.uploader.name} • ${_formatViews(video.views)} • ${_formatTimeAgo(video.uploadedAt)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.bodySmall.copyWith(
                                    color: Colors.grey,
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              );
            },
          ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildCustomControls() {
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    
    return Stack(
      children: [
        // Tap on empty area to toggle controls
        Positioned.fill(
          child: GestureDetector(
            onTap: _handleTap,
            behavior: HitTestBehavior.translucent,
            child: Container(color: Colors.transparent),
          ),
        ),
        // Top bar (Back button, Title)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.black.withValues(alpha:0.7), Colors.transparent],
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 8.0, 
              vertical: 4.0,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: AppTheme.iconPrimary, size: 24),
                  onPressed: () => Navigator.of(context).pop(),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _currentVideo.videoName,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: isPortrait ? 13 : 15,
                      shadows: const [
                        Shadow(blurRadius: 4, color: Colors.black45, offset: Offset(0, 1)),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.more_vert, color: AppTheme.iconPrimary, size: 20),
                  onPressed: () {}, // Future options (quality, etc.)
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
          ),
        ),

        // Center Area (No large buttons, just tap to toggle controls)
        Positioned.fill(
          child: Center(
            child: _showPlayPauseAnimation 
              ? Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _videoPlayerController.value.isPlaying
                        ? Icons.play_arrow
                        : Icons.pause,
                    color: AppTheme.iconPrimary,
                    size: 40,
                  ),
                )
              : const SizedBox.shrink(),
          ),
        ),

        // Bottom Bar (Progress Indicator and Controls Row)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withOpacity(0.8), Colors.transparent],
              ),
            ),
            padding: const EdgeInsets.only(
              bottom: 4.0,
              left: 12.0,
              right: 12.0,
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
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
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
                              playedColor: AppTheme.primary,
                              bufferedColor: Colors.white.withOpacity(0.3),
                              backgroundColor: Colors.white.withOpacity(0.1),
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
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
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
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Rewind 10s
                      IconButton(
                        iconSize: 24,
                        onPressed: () => _seekRelative(const Duration(seconds: -10)),
                        icon: const Icon(Icons.replay_10_rounded, color: AppTheme.iconPrimary),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      
                      // Play/Pause
                      IconButton(
                        iconSize: 36,
                        onPressed: _togglePlay,
                        icon: Icon(
                          _videoPlayerController.value.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          color: AppTheme.iconPrimary,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      
                      // Forward 10s
                      IconButton(
                        iconSize: 24,
                        onPressed: () => _seekRelative(const Duration(seconds: 10)),
                        icon: const Icon(Icons.forward_10_rounded, color: AppTheme.iconPrimary),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      
                      // Fullscreen
                      IconButton(
                        iconSize: 22,
                        onPressed: _toggleFullScreen,
                        icon: Icon(
                          _isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
                          color: AppTheme.iconPrimary,
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
