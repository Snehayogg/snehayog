import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/services/video_service.dart';
import 'package:vayu/view/screens/video_screen.dart';
import 'package:vayu/utils/app_logger.dart';
import 'package:vayu/view/search/video_creator_search_delegate.dart';
import 'package:vayu/core/theme/app_theme.dart';
// Removed unused app_theme.dart
// Removed timeago package dependency in favor of local helper

class VayuScreen extends StatefulWidget {
  const VayuScreen({Key? key}) : super(key: key);

  @override
  State<VayuScreen> createState() => _VayuScreenState();
}

class _VayuScreenState extends State<VayuScreen> {
  final VideoService _videoService = VideoService();
  final ScrollController _scrollController = ScrollController();

  List<VideoModel> _videos = [];
  bool _isLoading = true;
  bool _hasMore = true;
  int _currentPage = 1;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadVideos();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore) {
      _loadMoreVideos();
    }
  }

  Future<void> _loadVideos({bool refresh = false}) async {
    if (refresh) {
      if (!mounted) return;
      setState(() {
        _currentPage = 1;
        _hasMore = true;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final result = await _videoService.getVideos(
        page: _currentPage,
        limit: 10, // Fetch fewer items for list view (larger items)
        videoType: 'vayu',
      );

      if (!mounted) return;

      final List<VideoModel> newVideos = result['videos'];
      final bool hasMore = result['hasMore'] ?? false;

      // **FILTER: Only include videos longer than 2 minutes (120 seconds)**
      final List<VideoModel> longFormVideos =
          newVideos.where((v) => v.duration.inSeconds > 120).toList();

      setState(() {
        if (refresh) {
          _videos = longFormVideos;
        } else {
          final existingIds = _videos.map((v) => v.id).toSet();
          final uniqueNewVideos = longFormVideos
              .where((v) => !existingIds.contains(v.id))
              .toList();
          _videos.addAll(uniqueNewVideos);
        }

        _hasMore = hasMore;
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.log('❌ VayuScreen: Error loading videos: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load videos. Please try again.';
        });
      }
    }
  }

  Future<void> _loadMoreVideos() async {
    if (_isLoading) return;

    setState(() {
      _currentPage++;
    });

    await _loadVideos();
  }

  void _navigateToVideo(int index) {
    if (index >= 0 && index < _videos.length) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoScreen(
            initialVideos: _videos,
            initialIndex: index,
            videoType: 'vayu', // **FIX: Enforce Long Form videos in feed**
            isFullScreen: true, // **NEW: Full-screen mode**
          ),
        ),
      );
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  String _formatViews(int views) {
    if (views >= 1000000) {
      return '${(views / 1000000).toStringAsFixed(1)}M views';
    } else if (views >= 1000) {
      return '${(views / 1000).toStringAsFixed(1)}K views';
    } else {
      return '$views views';
    }
  }

  String _formatTimeAgo(DateTime dateTime) {
    final difference = DateTime.now().difference(dateTime);
    if (difference.inDays > 365) {
      return '${(difference.inDays / 365).floor()} years ago';
    } else if (difference.inDays > 30) {
      return '${(difference.inDays / 30).floor()} months ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minutes ago';
    } else {
      return 'Just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    // Vayu tab uses a purely dark theme (YouTube style)
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        title: Row(
          children: [
            Image.asset(
              'assets/icons/app_icon.png', // Assuming app icon exists
              height: 24,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.play_circle_fill, color: Colors.red),
            ),
            const SizedBox(width: 8),
            Text(
              'Vayu',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: AppTheme.textInverse,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: Colors.white),
            onPressed: () {
              showSearch(
                context: context,
                delegate: VideoCreatorSearchDelegate(),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _videos.isEmpty) {
      return _buildShimmerList(); // Changed to List shimmer
    }

    if (_errorMessage != null && _videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off, color: Colors.white54, size: 60),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textInverse.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => _loadVideos(refresh: true),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textInverse,
                side: BorderSide(color: AppTheme.textInverse.withOpacity(0.3)),
              ),
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
    }

    if (_videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.video_library_outlined,
                color: Colors.white24, size: 80),
            const SizedBox(height: 24),
            Text(
              'No long-form videos yet',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: AppTheme.textInverse,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Upload videos longer than 2 mins to see them here',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textInverse.withOpacity(0.54),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => _loadVideos(refresh: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textInverse,
                foregroundColor: Colors.black,
              ),
              child: const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _loadVideos(refresh: true),
      color: Colors.red,
      backgroundColor: Colors.white,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: _videos.length + (_isLoading && _videos.isNotEmpty ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _videos.length) {
            return const Padding(
              padding: EdgeInsets.all(16.0),
              child:
                  Center(child: CircularProgressIndicator(color: Colors.red)),
            );
          }
          return _buildVideoCard(index);
        },
      ),
    );
  }

  Widget _buildVideoCard(int index) {
    final video = _videos[index];

    print(
        'BuildVideoCard: ${video.videoName} Duration: ${video.duration.inSeconds}s');

    return InkWell(
      onTap: () => _navigateToVideo(index),
      child: Column(
        children: [
          // 1. Thumbnail Section (16:9)
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
                    child:
                        const Icon(Icons.broken_image, color: Colors.white24),
                  ),
                ),
              ),
              // Duration Badge
              if (video.duration.inSeconds > 0)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatDuration(video.duration),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppTheme.textInverse,
                        fontWeight: FontWeight.bold,
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
                  backgroundColor: Colors.grey[800],
                  backgroundImage: video.uploader.profilePic.isNotEmpty
                      ? CachedNetworkImageProvider(video.uploader.profilePic)
                      : null,
                  child: video.uploader.profilePic.isEmpty
                      ? Icon(Icons.person, size: 20, color: AppTheme.textInverse)
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
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppTheme.textInverse,
                          fontWeight: FontWeight.w500,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Meta: Channel • Views • Time
                      Text(
                        '${video.uploader.name} • ${_formatViews(video.views)} • ${_formatTimeAgo(video.uploadedAt)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textInverse.withOpacity(0.54),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                // Filter/More Icon (Optional)
                IconButton(
                  icon: const Icon(Icons.more_vert,
                      color: Colors.white54, size: 20),
                  onPressed: () {
                    // Show options sheet
                  },
                ),
              ],
            ),
          ),
          // Divider between videos (optional, or just spacing)
          // const Divider(color: Colors.white10, height: 1),
        ],
      ),
    );
  }

  Widget _buildShimmerList() {
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (context, index) => _buildShimmerItem(),
    );
  }

  Widget _buildShimmerItem() {
    return Column(
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(color: Colors.grey[900]),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const CircleAvatar(radius: 18, backgroundColor: Colors.white10),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        height: 14,
                        width: double.infinity,
                        color: Colors.white10),
                    const SizedBox(height: 8),
                    Container(height: 12, width: 200, color: Colors.white10),
                  ],
                ),
              )
            ],
          ),
        )
      ],
    );
  }
}
