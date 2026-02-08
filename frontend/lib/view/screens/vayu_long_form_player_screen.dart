import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:chewie/chewie.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/services/video_service.dart';
import 'package:vayu/core/theme/app_theme.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_fonts/google_fonts.dart';

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

  @override
  void initState() {
    super.initState();
    _currentVideo = widget.video;
    _recommendations = widget.relatedVideos.where((v) => v.id != _currentVideo.id).toList();
    _initializePlayer();
    if (_recommendations.isEmpty) {
      _loadRecommendations();
    }
  }

  Future<void> _initializePlayer() async {
    // Show loading while initializing
    if (mounted) {
      setState(() {
        _chewieController = null;
      });
    }

    _videoPlayerController = VideoPlayerController.networkUrl(Uri.parse(_currentVideo.videoUrl));
    
    await _videoPlayerController.initialize();

    _chewieController = ChewieController(
      videoPlayerController: _videoPlayerController,
      aspectRatio: 16 / 9,
      autoPlay: true,
      looping: false,
      allowFullScreen: true,
      allowPlaybackSpeedChanging: true,
      showControls: true,
      materialProgressColors: ChewieProgressColors(
        playedColor: AppTheme.primary,
        handleColor: AppTheme.primary,
        backgroundColor: Colors.white24,
        bufferedColor: Colors.white54,
      ),
      placeholder: Container(
        color: Colors.black,
        child: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      ),
      errorBuilder: (context, errorMessage) {
        return Center(
          child: Text(
            errorMessage,
            style: const TextStyle(color: Colors.white),
          ),
        );
      },
    );

    if (mounted) setState(() {});
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
    _chewieController?.dispose();
    _videoPlayerController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Video Player Section
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _chewieController != null && _chewieController!.videoPlayerController.value.isInitialized
                  ? Chewie(controller: _chewieController!)
                  : Container(
                      color: Colors.black,
                      child: const Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                    ),
            ),

            // 2. Content Section (Scrollable)
            Expanded(
              child: ListView(
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
                      color: AppTheme.textInverse.withOpacity(0.6),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacing5),

                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildActionButton(Icons.thumb_up_outlined, 'Like'),
                      _buildActionButton(Icons.share_outlined, 'Share'),
                      _buildActionButton(Icons.download_outlined, 'Download'),
                      _buildActionButton(Icons.playlist_add_outlined, 'Save'),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacing5),
                  Divider(color: AppTheme.textInverse.withOpacity(0.1)),
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
                                color: AppTheme.textInverse.withOpacity(0.6),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusXXLarge)),
                          padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacing4, vertical: AppTheme.spacing2),
                        ),
                        child: const Text('Subscribe', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacing3),
                  Divider(color: AppTheme.textInverse.withOpacity(0.1)),
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
                    Center(child: Text('No recommendations found', style: AppTheme.bodyMedium.copyWith(color: AppTheme.textInverse.withOpacity(0.5))))
                  else
                    ..._recommendations.map((video) => _buildRecommendationCard(video)).toList(),
                ],
              ),
            ),
          ],
        ),
      ),
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
          style: AppTheme.labelSmall.copyWith(color: AppTheme.textInverse.withOpacity(0.7)),
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
                      placeholder: (context, url) => Container(color: AppTheme.textInverse.withOpacity(0.1)),
                      errorWidget: (context, url, error) => Container(color: Colors.grey[900], child: const Icon(Icons.broken_image, color: Colors.white24)),
                    ),
                    Positioned(
                      bottom: AppTheme.spacing1,
                      right: AppTheme.spacing1,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.8),
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
                      color: AppTheme.textInverse.withOpacity(0.6),
                    ),
                  ),
                  Text(
                    _formatTimeAgo(video.uploadedAt),
                    style: AppTheme.bodySmall.copyWith(
                      color: AppTheme.textInverse.withOpacity(0.6),
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
