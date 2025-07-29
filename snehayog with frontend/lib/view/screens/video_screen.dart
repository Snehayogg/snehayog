// Import statements for required Flutter and third-party packages
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/services/google_auth_service.dart';
import 'package:snehayog/view/widget/video_player_widget.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/controller/google_sign_in_controller.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:snehayog/view/screens/profile_screen.dart';
import 'package:url_launcher/url_launcher.dart';

/// Main video screen widget that displays videos in a vertical scrolling format
/// Similar to TikTok/Instagram Reels interface
class VideoScreen extends StatefulWidget {
  // Index of the video to start with when navigating from another screen
  final int? initialIndex;
  // List of videos to display (used when navigating from home screen)
  final List<VideoModel>? initialVideos;

  const VideoScreen({Key? key, this.initialIndex, this.initialVideos})
      : super(key: key);

  // Static helper method to create a type-safe global key for external access
  static GlobalKey<_VideoScreenState> createKey() =>
      GlobalKey<_VideoScreenState>();

  @override
  _VideoScreenState createState() => _VideoScreenState();
}

/// State class for VideoScreen that manages video playback, pagination, and UI interactions
class _VideoScreenState extends State<VideoScreen> with WidgetsBindingObserver {
  // Service to handle video-related API calls
  final VideoService _videoService = VideoService();

  // List of all videos currently loaded
  late List<VideoModel> _videos;

  // Controller for the PageView that handles vertical scrolling
  late PageController _pageController;

  // Map to store video player controllers for each video index
  // Key: video index, Value: VideoPlayerController
  final Map<int, VideoPlayerController> _controllers = {};

  // Number of videos to preload in each direction (for smooth scrolling)
  final int _preloadDistance = 2;

  // Loading states
  bool _isLoading = true; // Initial loading state
  bool _isLoadingMore = false; // Loading more videos state
  bool _hasMore = true; // Whether more videos are available
  int _currentPage = 1; // Current page for pagination
  int _activePage = 0; // Currently active video index

  // Add these properties
  final List<VideoPlayerController> _controllersList = [];
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    // Add observer to handle app lifecycle changes (pause/resume)
    WidgetsBinding.instance.addObserver(this);

    // Check if videos were passed from another screen
    if (widget.initialVideos != null && widget.initialVideos!.isNotEmpty) {
      // Initialize with provided videos
      _videos = List<VideoModel>.from(widget.initialVideos!);
      _activePage = widget.initialIndex ?? 0;
      _pageController = PageController(initialPage: _activePage);
      _isLoading = false;

      // Initialize the current video and preload neighboring videos
      _initController(_activePage).then((_) {
        if (mounted) {
          _controllers[_activePage]?.play();
          _preloadVideosAround(_activePage);
          setState(() {});
        }
      });
    } else {
      // No initial videos provided, start with empty list and load from API
      _videos = [];
      _pageController = PageController();
      _loadVideos();

      // Add listener to detect when user reaches end of list for infinite scrolling
      _pageController.addListener(() {
        if (_pageController.position.pixels >=
                _pageController.position.maxScrollExtent - 200 &&
            !_isLoadingMore) {
          _loadVideos(isInitialLoad: false);
        }
      });
    }
  }

  @override
  void dispose() {
    // Clean up resources when widget is disposed
    WidgetsBinding.instance.removeObserver(this);
    for (var controller in _controllers.values) {
      if (controller.value.isPlaying) {
        controller.pause();
      }
      controller.dispose();
    }
    _controllers.clear();
    _pageController.dispose();
    super.dispose();
  }

  /// Handle app lifecycle changes to pause/resume videos appropriately
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print('AppLifecycleState changed: $state');
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      for (var controller in _controllers.values) {
        if (controller.value.isPlaying) {
          controller.pause();
          print('Paused video controller');
        }
      }
    } else if (state == AppLifecycleState.resumed) {
      // Resume only the active video when app comes back to foreground
      if (ModalRoute.of(context)?.isCurrent ?? false) {
        _controllers[_activePage]?.play();
      }
    }
  }

  /// Handle route changes to pause videos when navigating away
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Pause all videos if this route is not current (another screen is on top)
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
      for (var controller in _controllers.values) {
        if (controller.value.isPlaying) {
          controller.pause();
        }
      }
    }
  }

  /// Preload videos around the given index for smooth scrolling
  /// This creates video controllers for videos that are likely to be viewed next
  Future<void> _preloadVideosAround(int index) async {
    for (int i = index - _preloadDistance; i <= index + _preloadDistance; i++) {
      await _initController(i);
    }
  }

  /// Initialize a video player controller for the video at the given index
  /// This method creates and configures the VideoPlayerController for smooth playback
  Future<void> _initController(int index) async {
    // Check if index is valid and controller doesn't already exist
    if (index < 0 ||
        index >= _videos.length ||
        _controllers.containsKey(index)) {
      return;
    }

    try {
      final url = _videos[index].videoUrl;
      // Create network video player controller
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      controller.setLooping(true); // Enable looping for continuous playback
      _controllers[index] = controller;
    } catch (e) {
      print('Error initializing video at index $index: $e');
    }
  }

  /// Load videos from the API with pagination support
  /// This method handles both initial loading and loading more videos
  Future<void> _loadVideos({bool isInitialLoad = true}) async {
    // Prevent multiple simultaneous requests
    if (!_hasMore || (_isLoadingMore && !isInitialLoad)) return;

    setState(() {
      if (isInitialLoad) {
        _isLoading = true;
      } else {
        _isLoadingMore = true;
      }
    });

    try {
      // Fetch videos from the API
      final response = await _videoService.getVideos(page: _currentPage);
      final List<VideoModel> fetchedVideos = response['videos'];
      final bool hasMore = response['hasMore'];

      if (mounted) {
        setState(() {
          _videos.addAll(fetchedVideos);
          _hasMore = hasMore;
          _currentPage++;
          if (isInitialLoad) {
            _isLoading = false;
          } else {
            _isLoadingMore = false;
          }
        });

        // Initialize first video and preload neighbors if this is initial load
        if (isInitialLoad && _videos.isNotEmpty) {
          await _initController(0);
          if (mounted) {
            _controllers[0]?.play();
            _preloadVideosAround(0);
            setState(() {});
          }
        }
      }
    } catch (e) {
      print("Error loading videos: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  // Add this method
  /// Handle page changes when user scrolls to a different video
  /// This method manages video playback transitions
  void _onPageChanged(int index) {
    for (int i = 0; i < _controllersList.length; i++) {
      if (i != index && _controllersList[i].value.isPlaying) {
        _controllersList[i].pause();
      }
    }
    if (_controllersList[index].value.isInitialized) {
      _controllersList[index].play();
    }
    setState(() {
      _currentIndex = index;
    });
  }

  /// Dispose video controllers that are far from the active video to save memory
  /// This prevents memory leaks from keeping too many video controllers active
  void _disposeOffScreenControllers() {
    _controllers.keys
        .where((key) {
          return (key - _activePage).abs() > _preloadDistance;
        })
        .toList()
        .forEach((key) {
          _controllers[key]?.dispose();
          _controllers.remove(key);
        });
  }

  /// External method to control video playback based on screen visibility
  /// This can be called from parent widgets to pause/play videos
  void onScreenVisible(bool visible) {
    if (_controllers.containsKey(_activePage)) {
      if (visible) {
        _controllers[_activePage]?.play();
      } else {
        _controllers[_activePage]?.pause();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Get the current video being displayed
    final currentVideo = (_videos.isNotEmpty && _activePage < _videos.length)
        ? _videos[_activePage]
        : null;
    // Check if current video has an external link
    final hasLink =
        currentVideo?.link != null && currentVideo!.link!.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Main video player area
          _buildVideoPlayer(),

          // External link button (if video has a link)
          if (hasLink)
            Positioned(
              left: 15,
              right: 15,
              bottom: 56,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () async {
                    // Launch external link when button is tapped
                    final url = Uri.tryParse(currentVideo.link!);
                    if (url != null && await canLaunchUrl(url)) {
                      await launchUrl(url,
                          mode: LaunchMode.externalApplication);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Could not open link.')),
                      );
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [
                          Colors.white.withOpacity(0.18),
                          theme.colorScheme.primary.withOpacity(0.92),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.open_in_new,
                            color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Visit Now',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            letterSpacing: 0.5,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Build the main video player widget with PageView for vertical scrolling
  Widget _buildVideoPlayer() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_videos.isEmpty) {
      return const Center(child: Text("No videos found."));
    }

    return RefreshIndicator(
      onRefresh: () async {
        // Clear current videos and reload from API
        setState(() {
          _videos.clear();
          _currentPage = 1;
          _hasMore = true;
        });
        await _loadVideos(isInitialLoad: true);
      },
      child: VisibilityDetector(
        key: const Key('video_screen_visibility'),
        onVisibilityChanged: (visibilityInfo) {
          if (visibilityInfo.visibleFraction == 0) {
            _controllers[_activePage]?.pause();
          } else {
            _controllers[_activePage]?.play();
          }
        },
        child: PageView.builder(
          controller: _pageController,
          scrollDirection: Axis.vertical,
          itemCount: _videos.length + (_hasMore ? 1 : 0),
          onPageChanged: (index) {
            _onPageChanged(index);
          },
          itemBuilder: (context, index) {
            if (index == _videos.length) {
              return const Center(child: CircularProgressIndicator());
            }
            final video = _videos[index];
            final controller = _controllers[index];
            return Stack(
              fit: StackFit.expand,
              children: [
                VideoPlayerWidget(
                  key: ValueKey(video.id),
                  controller: controller,
                  video: video,
                  play: index == _activePage,
                ),

                // Video information overlay (bottom left)
                Positioned(
                  left: 12,
                  bottom: 12,
                  right: 80,
                  child: _buildVideoInfo(video),
                ),

                // Action buttons overlay (bottom right)
                Positioned(
                  right: 12,
                  bottom: 12,
                  child: _buildActionButtons(video, index),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Build the video information overlay showing title, description, and uploader
  Widget _buildVideoInfo(VideoModel video) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Video title
        Text(
          video.videoName,
          style: const TextStyle(
              color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),

        // Video description (limited to 2 lines)
        Text(
          video.description,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),

        // Uploader information (tappable to go to profile)
        GestureDetector(
          onTap: () {
            // Navigate to uploader's profile screen
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ProfileScreen(userId: video.uploader.id),
              ),
            );
          },
          child: Row(
            children: [
              const CircleAvatar(radius: 16, backgroundColor: Colors.grey),
              const SizedBox(width: 8),
              Text(
                video.uploader.name,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 13),
              )
            ],
          ),
        ),
      ],
    );
  }

  /// Build the action buttons overlay (like, comment, share)
  Widget _buildActionButtons(VideoModel video, int index) {
    // Get current user ID to check if they've liked this video
    final controller =
        Provider.of<GoogleSignInController>(context, listen: false);
    final userData = controller.userData;
    final userId = userData?['id'];
    final isLiked = userId != null && video.likedBy.contains(userId);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Like button - shows filled heart if liked, outline if not
        IconButton(
          icon: Icon(
            isLiked ? Icons.favorite : Icons.favorite_border,
            color: isLiked ? Colors.red : Colors.white,
            size: 32,
          ),
          onPressed: () => _handleLike(index),
        ),
        Text('${video.likes}', style: const TextStyle(color: Colors.white)),
        const SizedBox(height: 20),

        // Comment button
        IconButton(
          icon: const Icon(Icons.comment, color: Colors.white, size: 32),
          onPressed: () => _handleComment(video),
        ),
        Text('${video.comments.length}',
            style: const TextStyle(color: Colors.white)),
        const SizedBox(height: 20),

        // Share button
        IconButton(
          icon: const Icon(Icons.share, color: Colors.white, size: 32),
          onPressed: () => _handleShare(video),
        ),
        Text('${video.shares}', style: const TextStyle(color: Colors.white)),
      ],
    );
  }

  /// Handle like button tap - toggle like status via API
  Future<void> _handleLike(int index) async {
    try {
      // Get current user ID using GoogleAuthService
      final googleAuthService = GoogleAuthService();
      final userData = await googleAuthService.getUserData();

      print('Like button pressed for video at index: $index');
      print('User data: $userData');

      if (userData == null || userData['id'] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to like videos')),
        );
        return;
      }

      final userId = userData['id'];
      final video = _videos[index];

      // Check if user has already liked this video
      final isCurrentlyLiked = video.likedBy.contains(userId);
      print('Is currently liked: $isCurrentlyLiked');

      // Optimistically update UI
      setState(() {
        if (isCurrentlyLiked) {
          // Remove like
          video.likedBy.remove(userId);
          video.likes--;
          print('Removing like - new count: ${video.likes}');
        } else {
          // Add like
          video.likedBy.add(userId);
          video.likes++;
          print('Adding like - new count: ${video.likes}');
        }
      });

      // Call backend API to toggle like
      print('Calling backend API to toggle like...');
      final updatedVideo = await _videoService.toggleLike(video.id, userId);
      print('Backend response received: ${updatedVideo.likes} likes');

      // Update the video with the response from server
      setState(() {
        _videos[index] = VideoModel.fromJson(updatedVideo.toJson());
      });

      print('Like operation completed successfully');
    } catch (e) {
      print('Error in _handleLike: $e');

      // Revert optimistic update on error
      setState(() {
        // Revert the like state
        final video = _videos[index];
        final googleAuthService = GoogleAuthService();
        googleAuthService.getUserData().then((userData) {
          if (userData != null && userData['id'] != null) {
            final userId = userData['id'];
            final isCurrentlyLiked = video.likedBy.contains(userId);

            if (isCurrentlyLiked) {
              video.likedBy.remove(userId);
              video.likes--;
            } else {
              video.likedBy.add(userId);
              video.likes++;
            }
          }
        });
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update like: $e')),
      );
    }
  }

  /// Handle comment button tap - show comments sheet
  void _handleComment(VideoModel video) {
    _showCommentsSheet(video);
  }

  /// Show the comments bottom sheet for a video
  void _showCommentsSheet(VideoModel video) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => CommentsSheet(
        video: video,
        videoService: _videoService,
        onCommentsUpdated: (List<Comment> updatedComments) {
          // Update comments in the video model when new comment is added
          setState(() {
            video.comments = updatedComments;
          });
        },
      ),
    );
  }

  /// Handle share button tap - share video URL
  void _handleShare(VideoModel video) async {
    try {
      // Share the video URL and title
      await Share.share(
        'Check out this video: ${video.videoName}\n\n${video.videoUrl}',
        subject: 'Snehayog Video',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to share video: $e')),
      );
    }
  }
}

/// Bottom sheet widget for displaying and adding comments to a video
class CommentsSheet extends StatefulWidget {
  final VideoModel video; // Video to show comments for
  final VideoService videoService; // Service to handle comment operations
  final ValueChanged<List<Comment>>
      onCommentsUpdated; // Callback when comments change

  const CommentsSheet({
    Key? key,
    required this.video,
    required this.videoService,
    required this.onCommentsUpdated,
  }) : super(key: key);

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

/// State class for CommentsSheet that manages comment display and posting
class _CommentsSheetState extends State<CommentsSheet> {
  // Local copy of comments to manage state
  late List<Comment> _comments;

  // Text controller for the comment input field
  final TextEditingController _controller = TextEditingController();

  // Loading states
  final bool _isLoading = false; // Loading comments state
  bool _isPosting = false; // Posting comment state

  @override
  void initState() {
    super.initState();
    // Initialize with comments from the video
    _comments = List<Comment>.from(widget.video.comments);
  }

  /// Get the current user ID from the Google Sign-In controller
  Future<String?> _getCurrentUserId() async {
    final controller =
        Provider.of<GoogleSignInController>(context, listen: false);
    return controller.userData?['id'];
  }

  /// Post a new comment to the video
  Future<void> _postComment() async {
    // Validate input and prevent multiple simultaneous posts
    if (_controller.text.trim().isEmpty || _isPosting) return;

    setState(() => _isPosting = true);

    try {
      // Get current user ID for the comment
      final userId = await _getCurrentUserId();
      if (userId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in')),
        );
        setState(() => _isPosting = false);
        return;
      }

      // Add comment via API
      final updatedComments = await widget.videoService.addComment(
        widget.video.id,
        _controller.text.trim(),
        userId,
      );

      // Update local state and clear input
      setState(() {
        _comments = updatedComments;
        _controller.clear();
      });

      // Notify parent widget of comment update
      widget.onCommentsUpdated(updatedComments);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to post comment')),
      );
    } finally {
      setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom:
            MediaQuery.of(context).viewInsets.bottom, // Account for keyboard
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle for the bottom sheet
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          const Text('Comments',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),

          // Comments list or loading/empty states
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_comments.isEmpty)
            const Center(child: Text('No comments yet.'))
          else
            SizedBox(
              height: 250,
              child: ListView.builder(
                itemCount: _comments.length,
                itemBuilder: (context, index) {
                  final comment = _comments[index];
                  return ListTile(
                    // User avatar
                    leading: comment.userProfilePic.isNotEmpty
                        ? CircleAvatar(
                            backgroundImage:
                                NetworkImage(comment.userProfilePic))
                        : const CircleAvatar(child: Icon(Icons.person)),
                    // User name
                    title: Text(comment.userName.isNotEmpty
                        ? comment.userName
                        : 'User'),
                    // Comment text
                    subtitle: Text(comment.text),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
          // Comment input field and send button
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    hintText: 'Add a comment...',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 1,
                  maxLines: 3,
                ),
              ),
              const SizedBox(width: 8),

              // Show loading indicator or send button
              _isPosting
                  ? const CircularProgressIndicator(strokeWidth: 2)
                  : IconButton(
                      icon: const Icon(Icons.send),
                      onPressed: _postComment,
                    ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    // Clean up text controller
    _controller.dispose();
    super.dispose();
  }
}
