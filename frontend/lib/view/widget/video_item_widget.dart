import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/model/ad_model.dart';
import 'package:snehayog/view/widget/ad_display_widget.dart';
import 'package:snehayog/services/ad_service.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:cached_network_image/cached_network_image.dart';

class VideoItemWidget extends StatefulWidget {
  final VideoModel video;
  final VideoPlayerController? controller;
  final bool isActive;
  final int index;
  final VoidCallback? onLike;
  final VoidCallback? onComment;
  final VoidCallback? onShare;
  final VoidCallback? onProfileTap;
  final VoidCallback? onVisitNow;
  final Function(bool isPlaying)? onManualPlayPause;

  const VideoItemWidget({
    Key? key,
    required this.video,
    required this.controller,
    required this.isActive,
    required this.index,
    this.onLike,
    this.onComment,
    this.onShare,
    this.onProfileTap,
    this.onVisitNow,
    this.onManualPlayPause,
  }) : super(key: key);

  @override
  State<VideoItemWidget> createState() => _VideoItemWidgetState();
}

class _VideoItemWidgetState extends State<VideoItemWidget> {
  final AdService _adService = AdService();
  final AuthService _authService = AuthService();
  bool _isAd = false;
  Map<String, dynamic>? _adData;

  // Play-pause state variables
  bool _showPlayPauseIcon = false;
  bool _isVideoPlaying = false;

  // **NEW: Video display state management**
  bool _isVideoReady = false;
  bool _isControllerInitialized = false;

  @override
  void initState() {
    super.initState();
    _checkIfAd();
    _initializeVideoState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkVideoStateAfterBuild();
    });
  }

  void _initializeVideoState() {
    print(
        '🔄 VideoItemWidget: _initializeVideoState called for: ${widget.video.videoName}');

    // Listen to video controller state changes
    if (widget.controller != null) {
      print('🔄 VideoItemWidget: Adding listener to existing controller');
      widget.controller!.addListener(_onVideoStateChanged);
      _updateVideoState();
    } else {
      print(
          '🔄 VideoItemWidget: No controller available during initialization');
    }
  }

  void _updateVideoState() {
    print(
        '🔄 VideoItemWidget: _updateVideoState called for: ${widget.video.videoName}');

    if (widget.controller != null) {
      final oldInitialized = _isControllerInitialized;
      final oldReady = _isVideoReady;
      final oldPlaying = _isVideoPlaying;

      final newPlaying = widget.controller!.value.isPlaying;
      final newInitialized = widget.controller!.value.isInitialized;
      final newReady = widget.controller!.value.isInitialized &&
          !widget.controller!.value.hasError;

      // **FIXED: Only update state if there are actual changes**
      if (newPlaying != oldPlaying ||
          newInitialized != oldInitialized ||
          newReady != oldReady) {
        setState(() {
          _isVideoPlaying = newPlaying;
          _isControllerInitialized = newInitialized;
          _isVideoReady = newReady;
        });

        // **NEW: Debug state changes**
        print(
            '🔄 VideoItemWidget: State updated - initialized: $_isControllerInitialized (was: $oldInitialized), ready: $_isVideoReady (was: $oldReady), playing: $_isVideoPlaying (was: $oldPlaying)');

        if (!oldReady && newReady) {
          print(
              '🎉 VideoItemWidget: Video became ready! Video should display now.');
        }
      } else {
        print(
            '🔄 VideoItemWidget: No state changes detected, skipping rebuild');
      }
    } else {
      print('🔄 VideoItemWidget: No controller available for state update');
    }
  }

  void _checkVideoStateAfterBuild() {
    print(
        '🔄 VideoItemWidget: _checkVideoStateAfterBuild called for: ${widget.video.videoName}');

    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && widget.controller != null) {
        print('🔄 VideoItemWidget: Checking state after 100ms delay');
        _updateVideoState();

        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && widget.controller != null) {
            print('🔄 VideoItemWidget: Checking state after 500ms delay');
            _updateVideoState();
          }
        });
      } else {
        print(
            '🔄 VideoItemWidget: Widget not mounted or no controller after 100ms delay');
      }
    });
  }

  void _onVideoStateChanged() {
    if (mounted && widget.controller != null) {
      final wasVideoReady = _isVideoReady;
      final wasPlaying = _isVideoPlaying;
      final wasInitialized = _isControllerInitialized;

      // **FIXED: Only update state if there are actual changes**
      final newPlaying = widget.controller!.value.isPlaying;
      final newInitialized = widget.controller!.value.isInitialized;
      final newReady = widget.controller!.value.isInitialized &&
          !widget.controller!.value.hasError;

      // **FIXED: Prevent unnecessary rebuilds**
      if (newPlaying != wasPlaying ||
          newInitialized != wasInitialized ||
          newReady != wasVideoReady) {
        setState(() {
          _isVideoPlaying = newPlaying;
          _isControllerInitialized = newInitialized;
          _isVideoReady = newReady;
        });

        // **NEW: Debug logging for video state changes**
        if (!wasVideoReady && newReady) {
          print(
              '🎉 VideoItemWidget: Video became ready - ${widget.video.videoName}');
        } else if (wasVideoReady && !newReady) {
          print(
              '⚠️ VideoItemWidget: Video became not ready - ${widget.video.videoName}');
        }

        print(
            '🔄 VideoItemWidget: Controller state changed - initialized: $_isControllerInitialized, ready: $_isVideoReady, playing: $_isVideoPlaying');
      }
    }
  }

  @override
  void didUpdateWidget(VideoItemWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    print(
        '🔄 VideoItemWidget: didUpdateWidget called for: ${widget.video.videoName}');
    print(
        '🔄 VideoItemWidget: Old controller: ${oldWidget.controller != null}, New controller: ${widget.controller != null}');

    if (oldWidget.controller != widget.controller) {
      print(
          '🔄 VideoItemWidget: Controller changed! Updating listeners and state...');

      if (oldWidget.controller != null) {
        print('🔄 VideoItemWidget: Removing listener from old controller');
        oldWidget.controller!.removeListener(_onVideoStateChanged);
      }

      if (widget.controller != null) {
        print('🔄 VideoItemWidget: Adding listener to new controller');
        widget.controller!.addListener(_onVideoStateChanged);
        setState(() {
          _isVideoPlaying = widget.controller!.value.isPlaying;
          _isControllerInitialized = widget.controller!.value.isInitialized;
          _isVideoReady = widget.controller!.value.isInitialized &&
              !widget.controller!.value.hasError;
        });
        print(
            '🔄 VideoItemWidget: New controller state - initialized: $_isControllerInitialized, ready: $_isVideoReady');
      } else {
        print('🔄 VideoItemWidget: New controller is null, resetting state');
        setState(() {
          _isVideoPlaying = false;
          _isControllerInitialized = false;
          _isVideoReady = false;
        });
      }
    } else {
      print('🔄 VideoItemWidget: Controller unchanged, no action needed');
    }
  }

  @override
  void dispose() {
    // Remove video controller listener
    if (widget.controller != null) {
      widget.controller!.removeListener(_onVideoStateChanged);
    }
    super.dispose();
  }

  void _checkIfAd() {
    if (widget.video.videoType == 'ad' || widget.video.id.startsWith('ad_')) {
      _isAd = true;
      // Extract ad data if available
      if (widget.video.description?.contains('Sponsored') ?? true) {
        _adData = {
          'title': widget.video.videoName,
          'description': widget.video.description,
          'imageUrl': widget.video.thumbnailUrl,
          'videoUrl': widget.video.videoUrl,
          'link': widget.video.link,
          'adType': 'interstitial',
        };
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // **NEW: Reduced debug logging to prevent spam**
    if (widget.controller != null && !_isVideoReady) {
      print(
          '🏗️ VideoItemWidget: Building widget for video: ${widget.video.videoName} - controller ready: ${widget.controller!.value.isInitialized}, state: $_isVideoReady');
    }

    if (_isAd) {
      return _buildAdWidget();
    }
    return _buildVideoWidget();
  }

  Widget _buildAdWidget() {
    return Container(
      width: double.infinity,
      height: MediaQuery.of(context).size.height,
      color: Colors.black,
      child: Stack(
        children: [
          // Ad content
          if (_adData != null)
            AdDisplayWidget(
              ad: AdModel.fromJson(_adData!),
              isVideoFeed: true,
              onAdClosed: () {
                // Handle ad close - could skip to next video
                print('Ad closed by user');
              },
            )
          else
            _buildFallbackAdWidget(),

          // Ad tag overlay
          Positioned(
            top: 50,
            left: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.campaign, color: Colors.white, size: 16),
                  SizedBox(width: 4),
                  Text(
                    'Ad',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Skip button for ads
          Positioned(
            top: 50,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                'Skip in 3s',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackAdWidget() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.blue.withOpacity(0.8),
            Colors.purple.withOpacity(0.8),
          ],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.campaign, size: 64, color: Colors.white),
            const SizedBox(height: 16),
            Text(
              widget.video.videoName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.video.description ?? 'No description available',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                // Handle ad click
                if (widget.video.link != null &&
                    widget.video.link!.isNotEmpty) {
                  // Launch ad link
                  print('Ad clicked: ${widget.video.link}');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
              child: const Text(
                'Learn More',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoWidget() {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Video player - Full screen
        _buildVideoPlayer(),

        // Play-Pause detector overlay (covers entire video area)
        Positioned.fill(child: _buildPlayPauseDetector()),

        // Right side action buttons (like Instagram Reels)
        Positioned(
          right: 16,
          bottom: 60,
          child: _buildActionButtons(),
        ),

        // Bottom info section (title, uploader, visit now)
        Positioned(
          left: 16,
          right: 80, // Leave space for action buttons
          bottom: 20,
          child: _buildBottomInfo(),
        ),
      ],
    );
  }

  /// Video player with proper controller initialization
  Widget _buildVideoPlayer() {
    // **FIXED: Use state variables to ensure proper video display**
    if (widget.controller == null ||
        !_isControllerInitialized ||
        !_isVideoReady) {
      print(
          '🎬 VideoItemWidget: Video not ready - controller: ${widget.controller != null}, initialized: $_isControllerInitialized, ready: $_isVideoReady');

      if (widget.controller != null) {
        print(
            '🎬 VideoItemWidget: Controller state - initialized: ${widget.controller!.value.isInitialized}, hasError: ${widget.controller!.value.hasError}, duration: ${widget.controller!.value.duration}');

        // **NEW: Force state update if controller is actually ready**
        if (widget.controller!.value.isInitialized &&
            !widget.controller!.value.hasError) {
          print(
              '🔄 VideoItemWidget: Controller is actually ready, updating state...');
          _updateVideoState();
        }
      }

      return _buildThumbnail();
    }

    // **FIXED: Ensure video displays immediately when controller is ready**
    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: VideoPlayer(widget.controller!),
    );
  }

  /// Simple action buttons (like, comment, share)
  Widget _buildActionButtons() {
    return Column(
      children: [
        // Like button
        _buildActionButton(
          icon: widget.video.likedBy.isNotEmpty
              ? Icons.favorite
              : Icons.favorite_border,
          color: widget.video.likedBy.isNotEmpty ? Colors.red : Colors.white,
          onTap: widget.onLike,
          label: '${widget.video.likes}',
        ),
        const SizedBox(height: 20),

        // Comment button
        _buildActionButton(
          icon: Icons.comment_outlined,
          color: Colors.white,
          onTap: widget.onComment,
          label: '${widget.video.comments.length ?? 0}',
        ),
        const SizedBox(height: 20),

        // Share button
        _buildActionButton(
          icon: Icons.share_outlined,
          color: Colors.white,
          onTap: widget.onShare,
          label: 'Share',
        ),
      ],
    );
  }

  /// Clean action button
  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
    String? label,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Bottom info section with title, uploader, and visit now button
  Widget _buildBottomInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Uploader name (clickable)
        GestureDetector(
          onTap: widget.onProfileTap,
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundImage: widget.video.uploader.profilePic.isNotEmpty
                    ? CachedNetworkImageProvider(
                        widget.video.uploader.profilePic,
                      )
                    : null,
                child: widget.video.uploader.profilePic.isEmpty
                    ? Text(
                        widget.video.uploader.name.isNotEmpty
                            ? widget.video.uploader.name[0].toUpperCase()
                            : 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              Text(
                widget.video.uploader.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  shadows: [
                    Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 2,
                      color: Colors.black54,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // Video title
        Text(
          widget.video.videoName,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(
                offset: Offset(0, 1),
                blurRadius: 2,
                color: Colors.black54,
              ),
            ],
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),

        // Visit Now button (only if link exists)
        if (widget.video.link?.isNotEmpty == true)
          GestureDetector(
            onTap: widget.onVisitNow,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withOpacity(0.3)),
              ),
              child: const Text(
                'Visit Now',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Play-Pause detector overlay that covers entire video area
  Widget _buildPlayPauseDetector() {
    return GestureDetector(
      onTap: () {
        _handleVideoPlayPause();
      },
      child: Container(
        color: Colors.transparent, // Transparent overlay
        child: Center(
          child: AnimatedOpacity(
            opacity: _showPlayPauseIcon ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 300),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.6),
                borderRadius: BorderRadius.circular(50),
              ),
              child: Icon(
                _isVideoPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Handle video play/pause when screen is tapped
  void _handleVideoPlayPause() {
    if (widget.controller == null || !widget.controller!.value.isInitialized) {
      return;
    }

    setState(() {
      _showPlayPauseIcon = true;
    });

    // Hide icon after 1 second
    Future.delayed(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() {
          _showPlayPauseIcon = false;
        });
      }
    });

    // Toggle play/pause
    if (widget.controller!.value.isPlaying) {
      widget.controller!.pause();
      setState(() {
        _isVideoPlaying = false;
      });
    } else {
      widget.controller!.play();
      setState(() {
        _isVideoPlaying = true;
      });
    }

    // Notify parent about play/pause change
    if (widget.onManualPlayPause != null) {
      widget.onManualPlayPause!(_isVideoPlaying);
    }
  }

  /// Thumbnail builder for when video is not loaded
  Widget _buildThumbnail() {
    if (widget.video.thumbnailUrl.isEmpty) {
      return _buildFallbackThumbnail();
    }

    return CachedNetworkImage(
      imageUrl: widget.video.thumbnailUrl,
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
      placeholder: (context, url) => _buildFallbackThumbnail(),
      errorWidget: (context, url, error) {
        print('❌ Thumbnail loading error for $url: $error');
        return _buildFallbackThumbnail();
      },
      httpHeaders: const {'User-Agent': 'Snehayog-App/1.0'},
    );
  }

  /// Fallback thumbnail when image fails to load
  Widget _buildFallbackThumbnail() {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.video_library, size: 32, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(
              'Video',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
