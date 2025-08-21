import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:snehayog/core/providers/video_provider.dart';
import 'package:snehayog/core/managers/video_controller_manager.dart';
import 'package:snehayog/core/mixins/video_lifecycle_mixin.dart';
import 'package:snehayog/core/constants/app_constants.dart';
import 'package:snehayog/core/enums/video_state.dart';
import 'package:snehayog/view/widget/video_item_widget.dart';
import 'package:snehayog/view/widget/video_loading_states.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/services/authservices.dart';
import 'package:snehayog/controller/main_controller.dart';
import 'package:snehayog/model/video_model.dart';

class VideoScreenRefactored extends StatefulWidget {
  final int? initialIndex;
  final List<VideoModel>? initialVideos;

  const VideoScreenRefactored({
    Key? key,
    this.initialIndex,
    this.initialVideos,
  }) : super(key: key);

  static GlobalKey<_VideoScreenRefactoredState> createKey() =>
      GlobalKey<_VideoScreenRefactoredState>();

  @override
  _VideoScreenRefactoredState createState() => _VideoScreenRefactoredState();
}

class _VideoScreenRefactoredState extends State<VideoScreenRefactored>
    with VideoLifecycleMixin, WidgetsBindingObserver {
  late VideoControllerManager _controllerManager;
  late PageController _pageController;
  int _activePage = 0;
  bool _isScreenVisible = true;
  final AuthService _authService = AuthService();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _controllerManager = VideoControllerManager();

    // Initialize with provided videos or start empty
    if (widget.initialVideos != null && widget.initialVideos!.isNotEmpty) {
      _initializeWithVideos();
    } else {
      _initializeEmpty();
    }

    _setupMainControllerCallbacks();
  }

  void _initializeWithVideos() {
    final provider = Provider.of<VideoProvider>(context, listen: false);
    provider.loadVideos(isInitialLoad: true);

    _activePage = widget.initialIndex ?? 0;
    _pageController = PageController(initialPage: _activePage);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeFirstVideo();
    });
  }

  void _initializeEmpty() {
    _pageController = PageController();
    _pageController.addListener(_onPageScroll);

    // Load initial videos
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<VideoProvider>(context, listen: false);
      provider.loadVideos(isInitialLoad: true);
    });
  }

  Future<void> _initializeFirstVideo() async {
    final provider = Provider.of<VideoProvider>(context, listen: false);
    if (provider.videos.isNotEmpty) {
      await _controllerManager.initController(0, provider.videos[0]);
      _controllerManager.setActivePage(0);
      _controllerManager.playActiveVideo();
      await _controllerManager.preloadVideosAround(0, provider.videos);
    }
  }

  void _setupMainControllerCallbacks() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mainController =
          Provider.of<MainController>(context, listen: false);
      mainController.registerPauseVideosCallback(_pauseAllVideos);
      mainController.registerResumeVideosCallback(_playActiveVideo);
      mainController.addListener(_onMainControllerChanged);
    });
  }

  void _onPageScroll() {
    if (_pageController.position.pixels >=
            _pageController.position.maxScrollExtent -
                AppConstants.scrollThreshold &&
        !Provider.of<VideoProvider>(context, listen: false).isLoadingMore) {
      _loadMoreVideos();
    }

    final currentPage = _pageController.page?.round() ?? _activePage;
    if (currentPage != _activePage && _isScreenVisible) {
      _onVideoPageChanged(currentPage);
    }
  }

  void _onVideoPageChanged(int newPage) {
    if (newPage != _activePage && newPage >= 0) {
      final provider = Provider.of<VideoProvider>(context, listen: false);
      if (newPage < provider.videos.length) {
        _controllerManager.setActivePage(newPage);
        _activePage = newPage;

        if (_isScreenVisible) {
          _controllerManager.playActiveVideo();
        }
      }
    }
  }

  Future<void> _loadMoreVideos() async {
    final provider = Provider.of<VideoProvider>(context, listen: false);
    if (provider.hasMore && !provider.isLoadingMore) {
      await provider.loadVideos(isInitialLoad: false);
    }
  }

  void _onMainControllerChanged() {
    if (mounted) {
      final mainController =
          Provider.of<MainController>(context, listen: false);
      final isVideoScreenActive = mainController.currentIndex == 0;

      if (isVideoScreenActive && !_isScreenVisible) {
        _isScreenVisible = true;
        Future.delayed(const Duration(milliseconds: 100), () {
          if (mounted && _isScreenVisible && mainController.isAppInForeground) {
            _playActiveVideo();
          }
        });
      } else if (!isVideoScreenActive && _isScreenVisible) {
        _pauseAllVideos();
        _isScreenVisible = false;
      }
    }
  }

  /// Test API connection directly
  Future<void> _testApiConnection() async {
    try {
      print('🧪 VideoScreen: Testing API connection...');
      final videoService = VideoService();
      final response = await videoService.checkServerHealth();
      print('🧪 VideoScreen: API health check result: $response');

      if (response) {
        print('✅ VideoScreen: API is accessible');
        // Try to fetch videos directly
        final videosResponse = await videoService.getVideos(page: 1);
        print('🎬 VideoScreen: Direct API call result: $videosResponse');

        // Test link field specifically
        await videoService.testVideoLinkField();
      } else {
        print('❌ VideoScreen: API is not accessible');
      }
    } catch (e) {
      print('❌ VideoScreen: API test failed: $e');
    }
  }

  /// Handle like button tap
  Future<void> _handleLike(int index) async {
    try {
      final provider = Provider.of<VideoProvider>(context, listen: false);
      final video = provider.videos[index];

      // Get current user ID using AuthService
      final userData = await _authService.getUserData();

      if (userData == null || userData['id'] == null) {
        print('User not signed in, cannot like video');
        return;
      }

      final userId = userData['id'];

      // Toggle like via API
      final videoService = VideoService();
      final updatedVideo = await videoService.toggleLike(video.id, userId);

      // Refresh videos to get updated like status
      await provider.refreshVideos();

      print('Like operation completed successfully');
    } catch (e) {
      print('Error in _handleLike: $e');
    }
  }

  void _pauseAllVideos() {
    _controllerManager.pauseAllVideos();
  }

  void _playActiveVideo() {
    if (_isScreenVisible) {
      _controllerManager.playActiveVideo();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _isScreenVisible = false;
      _pauseAllVideos();
    } else if (state == AppLifecycleState.resumed) {
      if (_isScreenVisible && (ModalRoute.of(context)?.isCurrent ?? false)) {
        _playActiveVideo();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);

    try {
      final mainController =
          Provider.of<MainController>(context, listen: false);
      mainController.unregisterCallbacks();
      mainController.removeListener(_onMainControllerChanged);
    } catch (e) {
      print('Error unregistering callbacks: $e');
    }

    _controllerManager.disposeAll();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Consumer<VideoProvider>(
        builder: (context, videoProvider, child) {
          if (videoProvider.isLoading && videoProvider.videos.isEmpty) {
            return VideoLoadingStates(
              loadState: VideoLoadState.loading,
              onRefresh: () => videoProvider.refreshVideos(),
              onTestApi: _testApiConnection,
            );
          }

          if (videoProvider.videos.isEmpty) {
            return VideoEmptyState(
              onRefresh: () => videoProvider.refreshVideos(),
              onTestApi: _testApiConnection,
            );
          }

          // Only show the video feed (remove debug bar)
          return Expanded(child: _buildVideoFeed(videoProvider));
        },
      ),
    );
  }

  Widget _buildVideoFeed(VideoProvider videoProvider) {
    return RefreshIndicator(
      onRefresh: () async {
        _controllerManager.disposeAll();
        await videoProvider.refreshVideos();
        if (videoProvider.videos.isNotEmpty) {
          _initializeFirstVideo();
        }
      },
      child: VisibilityDetector(
        key: const Key('video_screen_visibility'),
        onVisibilityChanged: (visibilityInfo) {
          if (visibilityInfo.visibleFraction == 0) {
            _pauseAllVideos();
            _isScreenVisible = false;
          } else {
            _isScreenVisible = true;
            _playActiveVideo();
          }
        },
        child: PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          itemCount:
              videoProvider.videos.length + (videoProvider.hasMore ? 1 : 0),
          onPageChanged: _onVideoPageChanged,
          itemBuilder: (context, index) {
            if (index == videoProvider.videos.length) {
              return const Center(child: CircularProgressIndicator());
            }

            final video = videoProvider.videos[index];
            final controller = _controllerManager.getController(index);
            final isActive = index == _activePage;

            return VideoItemWidget(
              video: video,
              index: index,
              controller: controller,
              isActive: isActive,
              onLike: () => _handleLike(index),
            );
          },
        ),
      ),
    );
  }
}
