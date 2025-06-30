import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:snehayog/services/video_service.dart';
import 'package:snehayog/services/google_auth_service.dart';
import 'package:share_plus/share_plus.dart';

class VideoDetailScreen extends StatefulWidget {
  final Map<String, dynamic> video;

  const VideoDetailScreen({
    Key? key,
    required this.video,
  }) : super(key: key);

  @override
  State<VideoDetailScreen> createState() => _VideoDetailScreenState();
}

class _VideoDetailScreenState extends State<VideoDetailScreen> {
  final VideoService _videoService = VideoService();
  final GoogleAuthService _authService = GoogleAuthService();
  VideoPlayerController? _videoController;
  ChewieController? _chewieController;
  bool _isLiked = false;
  int _likeCount = 0;
  final TextEditingController _commentController = TextEditingController();
  List<Map<String, dynamic>> _comments = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
    _loadComments();
    _likeCount = widget.video['likes'] ?? 0;
  }

  Future<void> _initializeVideo() async {
    _videoController = VideoPlayerController.network(widget.video['videoUrl']);
    await _videoController!.initialize();

    _chewieController = ChewieController(
      videoPlayerController: _videoController!,
      autoPlay: true,
      looping: false,
      aspectRatio: 16 / 9,
      placeholder: Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
      allowedScreenSleep: false,
      showControls: true,
      showOptions: true,
      customControls: const MaterialControls(),
      additionalOptions: (context) {
        return <OptionItem>[
          OptionItem(
            onTap: (context) => _changeVideoQuality('1080p'),
            iconData: Icons.hd,
            title: '1080p',
          ),
          OptionItem(
            onTap: (context) => _changeVideoQuality('720p'),
            iconData: Icons.hd,
            title: '720p',
          ),
          OptionItem(
            onTap: (context) => _changeVideoQuality('480p'),
            iconData: Icons.hd,
            title: '480p',
          ),
          OptionItem(
            onTap: (context) => _changeVideoQuality('360p'),
            iconData: Icons.hd,
            title: '360p',
          ),
        ];
      },
    );
    setState(() {});
  }

  Future<void> _changeVideoQuality(String quality) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Switching to $quality quality...'),
        duration: const Duration(seconds: 2),
      ),
    );

    // In a real app, you would:
    // 1. Get the new quality URL from your video object
    // 2. Dispose of the current controllers
    // 3. Initialize new controllers with the new URL
    // 4. Update the UI
  }

  Future<void> _loadComments() async {
    setState(() => _isLoading = true);
    try {
      // Here you would typically fetch comments from your server
      // For now, using mock data
      _comments = [
        {
          'user': 'User1',
          'text': 'Great video!',
          'time': '2 hours ago',
        },
        {
          'user': 'User2',
          'text': 'Very informative',
          'time': '1 day ago',
        },
      ];
    } catch (e) {
      print('Error loading comments: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleLike() async {
    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to like videos')),
        );
        return;
      }

      setState(() {
        _isLiked = !_isLiked;
        _likeCount += _isLiked ? 1 : -1;
      });

      // Here you would typically update the like status on your server
    } catch (e) {
      print('Error handling like: $e');
      setState(() {
        _isLiked = !_isLiked;
        _likeCount += _isLiked ? 1 : -1;
      });
    }
  }

  Future<void> _handleComment() async {
    if (_commentController.text.isEmpty) return;

    try {
      final userData = await _authService.getUserData();
      if (userData == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please sign in to comment')),
        );
        return;
      }

      setState(() {
        _comments.insert(0, {
          'user': userData['name'] ?? 'User',
          'text': _commentController.text,
          'time': 'Just now',
        });
      });

      _commentController.clear();
      // Here you would typically save the comment to your server
    } catch (e) {
      print('Error adding comment: $e');
    }
  }

  Future<void> _handleShare() async {
    try {
      await Share.share(
        'Check out this video on Snehayog!\n\n${widget.video['title']}\n\n${widget.video['videoUrl']}',
        subject: 'Snehayog Video',
      );
    } catch (e) {
      print('Error sharing video: $e');
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _chewieController?.dispose();
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Video Player
            if (_chewieController != null)
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Chewie(controller: _chewieController!),
              )
            else
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  color: Colors.black,
                  child: const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Loading video...',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Video Info and Actions
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title and Views
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.video['title'],
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${widget.video['views']} views • ${widget.video['uploadTime']}',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Action Buttons
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildActionButton(
                            icon: _isLiked
                                ? Icons.favorite
                                : Icons.favorite_border,
                            label: '$_likeCount',
                            color: _isLiked ? Colors.red : null,
                            onTap: _handleLike,
                          ),
                          _buildActionButton(
                            icon: Icons.comment_outlined,
                            label: '${_comments.length}',
                            onTap: () {},
                          ),
                          _buildActionButton(
                            icon: Icons.share_outlined,
                            label: 'Share',
                            onTap: _handleShare,
                          ),
                        ],
                      ),
                    ),

                    const Divider(height: 32),

                    // Comments Section
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Comments',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Comment Input
                          Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: Colors.grey[300],
                                child: const Icon(Icons.person),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _commentController,
                                  decoration: InputDecoration(
                                    hintText: 'Add a comment...',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.send),
                                onPressed: _handleComment,
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Comments List
                          if (_isLoading)
                            const Center(child: CircularProgressIndicator())
                          else
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _comments.length,
                              itemBuilder: (context, index) {
                                final comment = _comments[index];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 16.0),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: Colors.grey[300],
                                        child: const Icon(Icons.person),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              comment['user'],
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            Text(comment['text']),
                                            Text(
                                              comment['time'],
                                              style: TextStyle(
                                                color: Colors.grey[600],
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    Color? color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
