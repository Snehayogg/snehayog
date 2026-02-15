import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayu/features/video/video_model.dart';
import 'package:vayu/features/video/data/services/video_service.dart';
import 'package:vayu/features/video/presentation/screens/vayu_long_form_player_screen.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:vayu/features/profile/presentation/widgets/video_creator_search_delegate.dart';
import 'package:vayu/shared/theme/app_theme.dart';


class VayuScreen extends StatefulWidget {
  const VayuScreen({Key? key}) : super(key: key);

  @override
  State<VayuScreen> createState() => VayuScreenState();

  /// **NEW: Global method to trigger refresh from other screens**
  static void refresh(GlobalKey<VayuScreenState> key) {
    key.currentState?.refreshVideos();
  }
}

class VayuScreenState extends State<VayuScreen> {
  final VideoService _videoService = VideoService();
  final ScrollController _scrollController = ScrollController();

  List<VideoModel> _videos = [];
  bool _isLoading = true;
  bool _hasMore = true;
  int _currentPage = 1;
  String? _errorMessage;

  // Banner Ad State


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
        _isLoading = true;
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
        limit: 10,
        videoType: 'vayu',
        clearSession: refresh,
      );

      if (!mounted) return;

      final List<VideoModel> newVideos = result['videos'];
      final bool hasMore = result['hasMore'] ?? false;

      // **BACKEND TRUSTED: Trust vayu category from backend**
      // Previously had a strict >120s filter which might drop valid vayu videos
      final List<VideoModel> longFormVideos = newVideos;

      AppLogger.log(
          'ðŸŽ¬ VayuScreen: Fetched ${newVideos.length} videos from backend');

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
      AppLogger.log('âŒ VayuScreen: Error loading videos: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load videos. Please try again.';
        });
      }
    }
  }

  /// **Expose public refresh method**
  Future<void> refreshVideos() async {
    await _loadVideos(refresh: true);
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
          builder: (context) => VayuLongFormPlayerScreen(
            video: _videos[index],
            relatedVideos: _videos,
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
              'assets/icons/app_icon.png',
              height: 24,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.play_circle_fill, color: AppTheme.primary),
            ),
            const SizedBox(width: AppTheme.spacing2),
            Text(
              'Vayu',
              style: AppTheme.displaySmall.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: AppTheme.weightBold,
                letterSpacing: -0.5,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: AppTheme.textPrimary),
            onPressed: () {
              showSearch(
                context: context,
                delegate: VideoCreatorSearchDelegate(),
              );
            },
          ),
          const SizedBox(width: AppTheme.spacing2),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _videos.isEmpty) {
      return _buildShimmerList();
    }

    if (_errorMessage != null && _videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off, color: AppTheme.textSecondary.withOpacity(0.7), size: 60),
            const SizedBox(height: AppTheme.spacing4),
            Text(
              _errorMessage!,
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary.withOpacity(0.9),
              ),
            ),
            const SizedBox(height: AppTheme.spacing6),
            OutlinedButton(
              onPressed: () => _loadVideos(refresh: true),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textPrimary,
                side: BorderSide(color: AppTheme.textSecondary.withOpacity(0.4)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusMedium)),
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
            Icon(Icons.video_library_outlined,
                color: AppTheme.textSecondary.withOpacity(0.4), size: 80),
            const SizedBox(height: AppTheme.spacing6),
            Text(
              'No long-form videos yet',
              style: AppTheme.headlineLarge.copyWith(
                  color: AppTheme.textPrimary,
                  fontWeight: AppTheme.weightBold),
            ),
            const SizedBox(height: AppTheme.spacing2),
            Text(
              'Browse through your personal video collection',
              style: AppTheme.bodyMedium.copyWith(
                color: AppTheme.textSecondary.withOpacity(0.9),
              ),
            ),
            const SizedBox(height: AppTheme.spacing6),
            ElevatedButton(
              onPressed: _isLoading ? null : () => _loadVideos(refresh: true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.textPrimary,
                foregroundColor: Colors.black,
                disabledBackgroundColor: Colors.white24,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusXXLarge)),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Refresh'),
            ),
          ],
        ),
      );
    }

    // Calculate total items: just videos + loader
    final int totalItems = _videos.length + (_isLoading && _videos.isNotEmpty ? 1 : 0);

    return RefreshIndicator(
      onRefresh: () async {
        await _loadVideos(refresh: true);
      },
      color: Colors.white,
      backgroundColor: AppTheme.primary,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: totalItems,
        itemBuilder: (context, index) {
          if (index >= _videos.length) {
            return const Padding(
              padding: EdgeInsets.all(AppTheme.spacing4),
              child:
                  Center(child: CircularProgressIndicator(color: AppTheme.primary)),
            );
          }
          return _buildVideoCard(index);
        },
      ),
    );
  }

  Widget _buildVideoCard(int index) {
    final video = _videos[index];

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
                  bottom: AppTheme.spacing2,
                  right: AppTheme.spacing2,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                    child: Text(
                      _formatDuration(video.duration),
                      style: AppTheme.labelSmall.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: AppTheme.weightBold,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // 2. Info Section (Below Thumbnail)
          Container(
            padding: const EdgeInsets.all(AppTheme.spacing3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.grey[900],
                  backgroundImage: video.uploader.profilePic.isNotEmpty
                      ? CachedNetworkImageProvider(video.uploader.profilePic)
                      : null,
                  child: video.uploader.profilePic.isEmpty
                      ? const Icon(Icons.person, size: 20, color: AppTheme.textPrimary)
                      : null,
                ),
                const SizedBox(width: AppTheme.spacing3),
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
                          color: AppTheme.textPrimary,
                          fontWeight: AppTheme.weightSemiBold,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacing1),
                      // Meta: Channel â€¢ Views â€¢ Time
                      Text(
                        '${video.uploader.name} â€¢ ${_formatViews(video.views)} â€¢ ${_formatTimeAgo(video.uploadedAt)}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.bodySmall.copyWith(
                          color: AppTheme.textSecondary.withOpacity(0.9),
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
          const SizedBox(height: AppTheme.spacing1),
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
          padding: const EdgeInsets.all(AppTheme.spacing3),
          child: Row(
            children: [
              const CircleAvatar(radius: 18, backgroundColor: Colors.white10),
              const SizedBox(width: AppTheme.spacing3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                        height: 14,
                        width: double.infinity,
                        color: Colors.white10),
                    const SizedBox(height: AppTheme.spacing2),
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


