import 'package:flutter/material.dart';
import 'package:vayu/features/video/data/services/video_service.dart';
import 'package:vayu/features/video/video_model.dart';
import 'package:vayu/shared/theme/app_theme.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:vayu/features/video/presentation/screens/video_screen.dart';
import 'package:vayu/features/video/presentation/managers/shared_video_controller_pool.dart';
import 'dart:ui';

class SavedVideosScreen extends StatefulWidget {
  const SavedVideosScreen({super.key});

  @override
  State<SavedVideosScreen> createState() => _SavedVideosScreenState();
}

class _SavedVideosScreenState extends State<SavedVideosScreen> {
  final VideoService _videoService = VideoService();
  List<VideoModel> _savedVideos = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSavedVideos();
  }

  Future<void> _loadSavedVideos() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final videos = await _videoService.getSavedVideos();
      if (mounted) {
        setState(() {
          _savedVideos = videos;
          _isLoading = false;
        });
      }
    } catch (e) {
      AppLogger.log('❌ SavedVideosScreen: Error loading videos: $e');
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  String _formatViews(int views) {
    if (views >= 1000000) {
      return '${(views / 1000000).toStringAsFixed(1).replaceAll('.0', '')}M';
    } else if (views >= 1000) {
      return '${(views / 1000).toStringAsFixed(1).replaceAll('.0', '')}K';
    } else {
      return views.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        title: const Text(
          'Saved Videos',
          style: TextStyle(
            color: AppTheme.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppTheme.backgroundPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
              ),
            )
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: AppTheme.error),
                      const SizedBox(height: 16),
                      Text(
                        'Failed to load saved videos',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      ElevatedButton(
                        onPressed: _loadSavedVideos,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                        ),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _savedVideos.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: AppTheme.surfacePrimary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Icon(
                              Icons.bookmark_outline,
                              size: 40,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'No saved videos',
                            style: TextStyle(
                              color: AppTheme.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Videos you bookmark will appear here.',
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadSavedVideos,
                      color: AppTheme.primary,
                      backgroundColor: AppTheme.surfacePrimary,
                      child: GridView.builder(
                        padding: const EdgeInsets.all(1),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 1,
                          mainAxisSpacing: 1,
                          childAspectRatio: 0.5,
                        ),
                        itemCount: _savedVideos.length,
                        itemBuilder: (context, index) => _buildVideoItem(_savedVideos[index]),
                      ),
                    ),
    );
  }

  Widget _buildVideoItem(VideoModel video) {
    return GestureDetector(
      onTap: () {
        final sharedPool = SharedVideoControllerPool();
        sharedPool.pauseAllControllers();

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoScreen(
              initialVideos: _savedVideos,
              initialVideoId: video.id,
              isFullScreen: true,
            ),
          ),
        );
      },
      child: Stack(
        children: [
          // Thumbnail
          Container(
            width: double.infinity,
            height: double.infinity,
            color: AppTheme.surfacePrimary,
            child: video.thumbnailUrl.isNotEmpty
                ? Image.network(
                    video.thumbnailUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(Icons.video_library, color: AppTheme.textSecondary),
                    ),
                  )
                : const Center(
                    child: Icon(Icons.video_library, color: AppTheme.textSecondary),
                  ),
          ),
          // Views Overlay
          Positioned(
            bottom: 8,
            left: 8,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.visibility, color: Colors.white, size: 12),
                      const SizedBox(width: 4),
                      Text(
                        _formatViews(video.views),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Duration indicator if available (optional)
        ],
      ),
    );
  }
}
