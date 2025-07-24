import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:snehayog/model/video_model.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/view/widget/video_player_widget.dart';
import 'package:share_plus/share_plus.dart';
import 'package:provider/provider.dart';
import 'package:snehayog/controller/google_sign_in_controller.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:snehayog/view/screens/profile_screen.dart';

class VideoScreen extends StatefulWidget {
  final int? initialIndex;
  final List<VideoModel>? initialVideos;

  const VideoScreen({Key? key, this.initialIndex, this.initialVideos})
      : super(key: key);

  // Add this static helper for type-safe key usage
  static GlobalKey<_VideoScreenState> createKey() =>
      GlobalKey<_VideoScreenState>();

  @override
  _VideoScreenState createState() => _VideoScreenState();
}

class _VideoScreenState extends State<VideoScreen> {
  final VideoService _videoService = VideoService();
  late List<VideoModel> _videos;
  late PageController _pageController;
  final Map<int, VideoPlayerController> _controllers = {};

  final int _preloadDistance =
      2; // How many videos to preload in each direction

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _currentPage = 1;
  int _activePage = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialVideos != null && widget.initialVideos!.isNotEmpty) {
      _videos = List<VideoModel>.from(widget.initialVideos!);
      _activePage = widget.initialIndex ?? 0;
      _pageController = PageController(initialPage: _activePage);
      _isLoading = false;
      // Initialize the current video, then preload neighbors
      _initController(_activePage).then((_) {
        if (mounted) {
          _controllers[_activePage]?.play();
          _preloadVideosAround(_activePage);
          setState(() {});
        }
      });
    } else {
      _videos = [];
      _pageController = PageController();
      _loadVideos();
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
    for (var c in _controllers.values) {
      c.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _preloadVideosAround(int index) async {
    for (int i = index - _preloadDistance; i <= index + _preloadDistance; i++) {
      await _initController(i);
    }
  }

  Future<void> _initController(int index) async {
    if (index < 0 ||
        index >= _videos.length ||
        _controllers.containsKey(index)) {
      return;
    }

    try {
      final url = _videos[index].videoUrl;
      final controller = VideoPlayerController.networkUrl(Uri.parse(url));
      await controller.initialize();
      controller.setLooping(true);
      _controllers[index] = controller;
    } catch (e) {
      print('Error initializing video at index $index: $e');
    }
  }

  Future<void> _loadVideos({bool isInitialLoad = true}) async {
    if (!_hasMore || (_isLoadingMore && !isInitialLoad)) return;

    setState(() {
      if (isInitialLoad) {
        _isLoading = true;
      } else {
        _isLoadingMore = true;
      }
    });

    try {
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
        // Preload initial videos
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

  Future<void> _onPageChanged(int index) async {
    // Stop the previous video
    _controllers[_activePage]?.pause();

    // Update the active page
    _activePage = index;

    // Asynchronously preload and dispose videos
    _preloadVideosAround(index);
    _disposeOffScreenControllers();

    // Play the new video. If it's not ready, initialize it first.
    if (_controllers.containsKey(index)) {
      _controllers[index]?.play();
    } else {
      await _initController(index);
      if (mounted) {
        _controllers[index]?.play();
        setState(() {});
      }
    }
  }

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

  // Add this method for external visibility control
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: _buildVideoPlayer(),
    );
  }

  Widget _buildVideoPlayer() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_videos.isEmpty) {
      return const Center(child: Text("No videos found."));
    }

    return VisibilityDetector(
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
              // Video info and uploader (bottom left)
              Positioned(
                left: 12,
                bottom: 12,
                right: 80,
                child: _buildVideoInfo(video),
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: _buildActionButtons(video, index),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildVideoInfo(VideoModel video) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          video.videoName,
          style: const TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          video.description,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 20),
        GestureDetector(
          onTap: () {
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
                    color: Colors.white, fontWeight: FontWeight.bold),
              )
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(VideoModel video, int index) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.favorite, color: Colors.white, size: 32),
          onPressed: () => _handleLike(index),
        ),
        Text('${video.likes}', style: const TextStyle(color: Colors.white)),
        const SizedBox(height: 20),
        IconButton(
          icon: const Icon(Icons.comment, color: Colors.white, size: 32),
          onPressed: () => _handleComment(video),
        ),
        Text('${video.comments.length}',
            style: const TextStyle(color: Colors.white)),
        const SizedBox(height: 20),
        IconButton(
          icon: const Icon(Icons.share, color: Colors.white, size: 32),
          onPressed: () => _handleShare(video),
        ),
        Text('${video.shares}', style: const TextStyle(color: Colors.white)),
      ],
    );
  }

  void _handleLike(int index) {
    setState(() {
      _videos[index].likes += 1; // Toggle logic can be added
    });
  }

  void _handleComment(VideoModel video) {
    _showCommentsSheet(video);
  }

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
          setState(() {
            video.comments = updatedComments;
          });
        },
      ),
    );
  }

  void _handleShare(VideoModel video) async {
    try {
      // Share the Cloudinary URL directly
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

class CommentsSheet extends StatefulWidget {
  final VideoModel video;
  final VideoService videoService;
  final ValueChanged<List<Comment>> onCommentsUpdated;

  const CommentsSheet({
    Key? key,
    required this.video,
    required this.videoService,
    required this.onCommentsUpdated,
  }) : super(key: key);

  @override
  State<CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<CommentsSheet> {
  late List<Comment> _comments;
  final TextEditingController _controller = TextEditingController();
  final bool _isLoading = false;
  bool _isPosting = false;

  @override
  void initState() {
    super.initState();
    _comments = List<Comment>.from(widget.video.comments);
  }

  Future<String?> _getCurrentUserId() async {
    final controller =
        Provider.of<GoogleSignInController>(context, listen: false);
    return controller.userData?['id'];
  }

  Future<void> _postComment() async {
    if (_controller.text.trim().isEmpty || _isPosting) return;
    setState(() => _isPosting = true);
    try {
      // Get userId from your auth logic (replace with actual user id)
      final userId = await _getCurrentUserId();
      if (userId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to comment')),
        );
        setState(() => _isPosting = false);
        return;
      }
      final updatedComments = await widget.videoService.addComment(
        widget.video.id,
        _controller.text.trim(),
        userId,
      );
      setState(() {
        _comments = updatedComments;
        _controller.clear();
      });
      widget.onCommentsUpdated(updatedComments);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add comment: $e')),
      );
    } finally {
      setState(() => _isPosting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Text('Comments',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
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
                    leading: comment.userProfilePic.isNotEmpty
                        ? CircleAvatar(
                            backgroundImage:
                                NetworkImage(comment.userProfilePic))
                        : const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(comment.userName.isNotEmpty
                        ? comment.userName
                        : 'User'),
                    subtitle: Text(comment.text),
                  );
                },
              ),
            ),
          const SizedBox(height: 12),
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
    _controller.dispose();
    super.dispose();
  }
}
