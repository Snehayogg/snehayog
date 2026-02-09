import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/controller/main_controller.dart';
import 'package:vayu/utils/app_logger.dart';
import 'dart:async';
import 'package:vayu/services/video_service.dart';
import 'package:vayu/core/theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayu/core/factories/video_controller_factory.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:flutter_volume_controller/flutter_volume_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  // Controls State
  bool _showControls = true;
  bool _showScrubbingOverlay = false;
  bool _showPlayPauseAnimation = false;
  bool _isAnimatingForward = true;
  Duration _scrubbingTargetTime = Duration.zero;
  Duration _scrubbingDelta = Duration.zero;
  double _horizontalDragTotal = 0.0;
  bool _isForward = true;
  bool _isFullScreen = false;
  Timer? _hideControlsTimer;

  // Gesture state (MX Player style)
  double _verticalDragTotal = 0.0;
  bool _showBrightnessOverlay = false;
  bool _showVolumeOverlay = false;
  double _brightnessValue = 0.5;
  double _volumeValue = 0.5;
  Timer? _overlayTimer;
  SharedPreferences? _prefs;

  // Error state
  bool _hasError = false;
  String _errorMessage = '';

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
      aspectRatio: 16 / 9,
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

  void _handleDoubleTap() {
    _togglePlay();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    // We already use double tap for play/pause, so we'll move skip to triple tap or side buttons
    // For now, keep the requested "double tap play/pause" priority.
    // If the user wants BOTH, we might need a different approach.
    // Let's stick to the requested: single tap = controls, double tap = play/pause.
  }

  void _startHideControlsTimer() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _videoPlayerController.value.isPlaying) {
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
      if (_prefs == null) _prefs = await SharedPreferences.getInstance();
      final key = 'video_pos_${_currentVideo.id}';
      await _prefs!.setInt(key, _videoPlayerController.value.position.inSeconds);
      AppLogger.log('💾 VayuLongFormPlayer: Saved position ${_videoPlayerController.value.position.inSeconds}s for video ${_currentVideo.id}');
    }
  }

  Future<void> _resumePlayback() async {
    if (_prefs == null) _prefs = await SharedPreferences.getInstance();
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

  Widget _buildScrubbingOverlay() {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha:0.9),
          borderRadius: BorderRadius.circular(16),
           boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 10, spreadRadius: 2),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isForward ? Icons.forward_10 : Icons.replay_10,
              color: Colors.black,
              size: 48,
            ),
            const SizedBox(height: 12),
            Text(
              '${_isForward ? "+" : ""}${_scrubbingDelta.inSeconds.abs()}s',
              style: const TextStyle(
                color: Colors.black,
                fontSize: 32,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatDuration(_scrubbingTargetTime),
              style: TextStyle(
                color: Colors.black.withValues(alpha:0.7),
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
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
        width: 140,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha:0.9),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 10, spreadRadius: 2),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.black, size: 36),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                backgroundColor: Colors.black.withValues(alpha:0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primary),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${(value * 100).toInt()}%',
              style: const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 16,
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
            _isFullScreen = true;
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
                _buildVideoSection(orientation),
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
    final videoAspectRatio = orientation == Orientation.landscape 
        ? size.aspectRatio 
        : 16 / 9;

    return AspectRatio(
      aspectRatio: videoAspectRatio,
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
              onDoubleTap: _handleDoubleTap,
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
                decoration: BoxDecoration(
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

  Widget _buildContentSection() {
    return ListView(
      padding: const EdgeInsets.all(AppTheme.spacing4),
      children: [
        // Title
        Text(
          _currentVideo.videoName,
          style: AppTheme.headlineMedium.copyWith(
            color: AppTheme.textInverse,
            fontWeight: AppTheme.weightBold,
          ),
        ),
        const SizedBox(height: AppTheme.spacing2),

        // Meta Info
        Text(
          '${_formatViews(_currentVideo.views)} • ${_formatTimeAgo(_currentVideo.uploadedAt)}',
          style: AppTheme.bodySmall.copyWith(
            color: AppTheme.textInverse.withValues(alpha:0.6),
          ),
        ),
        const SizedBox(height: AppTheme.spacing5),

        // Action Buttons - CLEAN UI: Only Save
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            _buildActionButton(Icons.playlist_add_outlined, 'Save'),
          ],
        ),
        const SizedBox(height: AppTheme.spacing5),
        Divider(color: AppTheme.textInverse.withValues(alpha:0.1)),
        const SizedBox(height: AppTheme.spacing3),

        // Creator Section
        Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.grey[900],
              backgroundImage: _currentVideo.uploader.profilePic.isNotEmpty
                  ? CachedNetworkImageProvider(_currentVideo.uploader.profilePic)
                  : null,
              child: _currentVideo.uploader.profilePic.isEmpty
                  ? const Icon(Icons.person, color: AppTheme.textInverse, size: 20)
                  : null,
            ),
            const SizedBox(width: AppTheme.spacing3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _currentVideo.uploader.name,
                    style: AppTheme.titleMedium.copyWith(
                      color: AppTheme.textInverse,
                      fontWeight: AppTheme.weightBold,
                    ),
                  ),
                  Text(
                    '${_currentVideo.uploader.totalVideos ?? 0} videos',
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textInverse.withValues(alpha:0.6),
                    ),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textInverse,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusXXLarge)),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacing4, vertical: AppTheme.spacing2),
              ),
              child:
                  const Text('Subscribe', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacing3),
        Divider(color: AppTheme.textInverse.withValues(alpha:0.1)),
        const SizedBox(height: AppTheme.spacing5),

        // Recommendations Header
        Text(
          'Recommended Videos',
          style: AppTheme.titleLarge.copyWith(
            color: AppTheme.textInverse,
            fontWeight: AppTheme.weightBold,
          ),
        ),
        const SizedBox(height: AppTheme.spacing4),

        // Recommendations List
        if (_isLoadingRecommendations && _recommendations.isEmpty)
          const Center(child: CircularProgressIndicator(color: AppTheme.primary))
        else if (_recommendations.isEmpty)
          Center(
              child: Text('No recommendations found',
                  style: AppTheme.bodyMedium
                      .copyWith(color: AppTheme.textInverse.withValues(alpha:0.5))))
        else
          ..._recommendations
              .map((video) => _buildRecommendationCard(video))
              .toList(),
      ],
    );
  }

  Widget _buildActionButton(IconData icon, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: AppTheme.textInverse, size: 24),
        const SizedBox(height: AppTheme.spacing1),
        Text(
          label,
          style: AppTheme.labelSmall.copyWith(color: AppTheme.textInverse.withValues(alpha:0.7)),
        ),
      ],
    );
  }

  Widget _buildCustomControls() {
    final isPortrait = MediaQuery.of(context).orientation == Orientation.portrait;
    
    return Stack(
      children: [
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
            padding: EdgeInsets.symmetric(
              horizontal: 16.0, 
              vertical: isPortrait ? 12.0 : 24.0,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                Expanded(
                  child: Text(
                    _currentVideo.videoName,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: isPortrait ? 14 : 16,
                      shadows: const [
                        Shadow(blurRadius: 10, color: Colors.black87, offset: Offset(0, 2)),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Center controls (Rewind, Play/Pause, Forward)
        Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                iconSize: isPortrait ? 36 : 48,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.replay_10, color: Colors.white, shadows: [Shadow(blurRadius: 10, color: Colors.black45)]),
                onPressed: () => _seekRelative(const Duration(seconds: -10)),
              ),
              SizedBox(width: isPortrait ? 32 : 48),
              IconButton(
                iconSize: isPortrait ? 52 : 64,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  _videoPlayerController.value.isPlaying
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_filled,
                  color: Colors.white,
                  shadows: const [Shadow(blurRadius: 20, color: Colors.black45)],
                ),
                onPressed: _togglePlay,
              ),
              SizedBox(width: isPortrait ? 32 : 48),
              IconButton(
                iconSize: isPortrait ? 36 : 48,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(Icons.forward_10, color: Colors.white, shadows: [Shadow(blurRadius: 10, color: Colors.black45)]),
                onPressed: () => _seekRelative(const Duration(seconds: 10)),
              ),
            ],
          ),
        ),

        // Bottom bar (Progress, Timer, Fullscreen)
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Colors.black.withValues(alpha:0.7), Colors.transparent],
              ),
            ),
            padding: EdgeInsets.symmetric(
              horizontal: 16.0, 
              vertical: isPortrait ? 10.0 : 20.0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ValueListenableBuilder(
                      valueListenable: _videoPlayerController,
                      builder: (context, VideoPlayerValue value, child) {
                        return Text(
                          '${_formatDuration(value.position)} / ${_formatDuration(value.duration)}',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: isPortrait ? 11 : 12,
                            fontWeight: FontWeight.bold,
                            shadows: const [Shadow(blurRadius: 4, color: Colors.black, offset: Offset(0, 1))],
                          ),
                        );
                      },
                    ),
                    IconButton(
                      iconSize: isPortrait ? 24 : 28,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        _isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen,
                        color: Colors.white,
                        shadows: const [Shadow(blurRadius: 10, color: Colors.black45)],
                      ),
                      onPressed: _toggleFullScreen,
                    ),
                  ],
                ),
                // Premium Progress Bar
                ValueListenableBuilder(
                  valueListenable: _videoPlayerController,
                  builder: (context, VideoPlayerValue value, child) {
                    return VideoProgressIndicator(
                      _videoPlayerController,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      colors: VideoProgressColors(
                        playedColor: AppTheme.primary,
                        bufferedColor: Colors.white.withValues(alpha:0.3),
                        backgroundColor: Colors.white.withValues(alpha:0.1),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendationCard(VideoModel video) {
    return InkWell(
      onTap: () => _switchVideo(video),
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppTheme.spacing4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Thumbnail
            ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              child: SizedBox(
                width: 160,
                height: 90,
                child: Stack(
                  children: [
                    CachedNetworkImage(
                      imageUrl: video.thumbnailUrl,
                      width: 160,
                      height: 90,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(color: AppTheme.textInverse.withValues(alpha:0.1)),
                      errorWidget: (context, url, error) => Container(color: Colors.grey[900], child: const Icon(Icons.broken_image, color: Colors.white24)),
                    ),
                    Positioned(
                      bottom: AppTheme.spacing1,
                      right: AppTheme.spacing1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha:0.8),
                          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                        ),
                        child: Text(
                          _formatDuration(video.duration),
                          style: AppTheme.labelSmall.copyWith(color: AppTheme.textInverse, fontWeight: AppTheme.weightBold, fontSize: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: AppTheme.spacing3),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.videoName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyLarge.copyWith(
                      color: AppTheme.textInverse,
                      fontWeight: AppTheme.weightMedium,
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacing1),
                  Text(
                    '${video.uploader.name} • ${_formatViews(video.views)}',
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textInverse.withValues(alpha:0.6),
                    ),
                  ),
                  Text(
                    _formatTimeAgo(video.uploadedAt),
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textInverse.withValues(alpha:0.6),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
