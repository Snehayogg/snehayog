import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/features/profile/presentation/managers/profile_state_manager.dart';
import 'package:vayu/shared/services/profile_screen_logger.dart';
import 'package:vayu/features/video/presentation/screens/video_screen.dart';
import 'package:vayu/features/video/presentation/managers/shared_video_controller_pool.dart';
import 'package:vayu/features/video/video_model.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:cached_network_image/cached_network_image.dart'; // Needed for the new method

class ProfileVideosWidget extends StatelessWidget {
  final ProfileStateManager stateManager;
  final VoidCallback? onVideoTap;
  final VoidCallback? onVideoLongPress;
  final VoidCallback? onVideoSelection;
  final bool showHeader;
  final bool isSliver;

  const ProfileVideosWidget({
    super.key,
    required this.stateManager,
    this.onVideoTap,
    this.onVideoLongPress,
    this.onVideoSelection,
    this.showHeader = true,
    this.isSliver = false,
  });

  /// **NEW: Preload video thumbnails for faster loading**
  void _preloadVideoThumbnails(BuildContext context, List<VideoModel> videos) {
    // Preload thumbnails in background for better performance
    Future.microtask(() async {
      for (final video in videos.take(5)) {
        // Preload first 5 videos
        if (video.thumbnailUrl.isNotEmpty) {
          try {
            await precacheImage(NetworkImage(video.thumbnailUrl), context);
          } catch (e) {
            AppLogger.log(
                '⚠️ ProfileVideosWidget: Failed to preload thumbnail: $e');
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // **OPTIMIZED: Preload video thumbnails for better performance**
    if (stateManager.userVideos.isNotEmpty) {
      _preloadVideoThumbnails(context, stateManager.userVideos);
    }

    return Consumer<ProfileStateManager>(
      builder: (context, manager, child) {
        if (manager.isVideosLoading) {
          final loadingWidget = RepaintBoundary(
            child: SizedBox(
              height: 200,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                      strokeWidth: 5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.green.shade500,
                      ),
                      backgroundColor: Colors.green.shade100,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Fetching your videos...',
                    style: TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please wait while we get everything ready.',
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
          return isSliver ? SliverToBoxAdapter(child: loadingWidget) : loadingWidget;
        }

        if (manager.userVideos.isEmpty) {
          final emptyWidget = RepaintBoundary(
            child: Container(
              padding: const EdgeInsets.all(48),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.video_library_outlined,
                      size: 40,
                      color: Color(0xFF9CA3AF),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'No videos yet',
                    style: TextStyle(
                      color: Color(0xFF374151),
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Upload your first video to get started!',
                    style: TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
          return isSliver ? SliverToBoxAdapter(child: emptyWidget) : emptyWidget;
        }

        // **PRE-PROCESSING: Group Series Videos**
        final List<VideoModel> displayVideos = [];
        final Set<String> processedSeriesIds = {};

        for (final video in manager.userVideos) {
          if (video.seriesId != null) {
            if (!processedSeriesIds.contains(video.seriesId)) {
              processedSeriesIds.add(video.seriesId!);
              displayVideos.add(video);
            }
          } else {
            displayVideos.add(video);
          }
        }

        const gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 1,
          mainAxisSpacing: 1,
          childAspectRatio: 0.5,
        );

        if (isSliver) {
          return SliverGrid.builder(
            gridDelegate: gridDelegate,
            itemCount: displayVideos.length,
            itemBuilder: (context, index) => _buildVideoItem(context, manager, displayVideos[index], index),
          );
        }

        return RepaintBoundary(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHeader) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'Your Videos',
                    style: TextStyle(
                      color: Color(0xFF1A1A1A),
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: gridDelegate,
                itemCount: displayVideos.length,
                itemBuilder: (context, index) => _buildVideoItem(context, manager, displayVideos[index], index),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVideoItem(BuildContext context, ProfileStateManager manager, VideoModel video, int index) {
    final isSelected = manager.selectedVideoIds.contains(video.id);
    final bool isSeries = video.seriesId != null;
    final canSelectVideo = manager.isSelecting && manager.isOwner && manager.userData != null;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () async {
          if (isSeries && !manager.isSelecting) {
            _showEpisodeList(context, video);
            return;
          }

          if (!manager.isSelecting) {
            final sharedPool = SharedVideoControllerPool();
            // **FIX: Stop using clearAll() as it destroys controllers needed by Other tabs**
            // sharedPool.clearAll();
            sharedPool.pauseAllControllers(); 

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => VideoScreen(
                  initialVideos: manager.userVideos,
                  initialVideoId: video.id,
                  isFullScreen: true, // **NEW: Full-screen mode**
                ),
              ),
            );
          } else if (manager.isSelecting && canSelectVideo) {
            manager.toggleVideoSelection(video.id);
          }
        },
        onLongPress: () {
          if (manager.isOwner && manager.userData != null && !manager.isSelecting) {
            manager.enterSelectionMode();
            manager.toggleVideoSelection(video.id);
          }
        },
        child: Container(
          decoration: const BoxDecoration(),
          child: ClipRRect(
            borderRadius: BorderRadius.zero,
            child: Stack(
              children: [
                // Video Thumbnail
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  color: const Color(0xFFF3F4F6),
                  child: video.thumbnailUrl.isNotEmpty
                      ? Image.network(
                          video.thumbnailUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          height: double.infinity,
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Icon(
                                Icons.video_library,
                                color: Color(0xFF9CA3AF),
                                size: 32,
                              ),
                            );
                          },
                        )
                      : const Center(
                          child: Icon(
                            Icons.video_library,
                            color: Color(0xFF9CA3AF),
                            size: 32,
                          ),
                        ),
                ),

                // SERIES BADGE
                if (isSeries)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white.withOpacity(0.3), width: 0.5),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.layers, color: Colors.white, size: 12),
                          SizedBox(width: 4),
                          Text(
                            'SERIES',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Views Overlay
                Positioned(
                  bottom: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.visibility,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${video.views}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Selection Overlay
                if (isSelected)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withOpacity(0.2),
                        borderRadius: BorderRadius.zero,
                        border: Border.all(
                          color: const Color(0xFFEF4444),
                          width: 3,
                        ),
                      ),
                      child: Center(
                        child: Container(
                          width: 48,
                          height: 48,
                          decoration: const BoxDecoration(
                            color: Color(0xFFEF4444),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Selection Checkbox
                if (manager.isSelecting && canSelectVideo)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: GestureDetector(
                      onTap: () {
                        stateManager.toggleVideoSelection(video.id);
                      },
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFFEF4444) : Colors.white.withOpacity(0.8),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? const Color(0xFFEF4444) : Colors.white,
                            width: 2,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 16,
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showEpisodeList(BuildContext context, VideoModel video) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.3,
          maxChildSize: 0.8,
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // Handle bar
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Title
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        const Icon(Icons.playlist_play, color: Colors.black),
                        const SizedBox(width: 8),
                        Text(
                          'More Episodes',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(),
                  // List
                  Expanded(
                    child: GridView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                        childAspectRatio: 0.7,
                      ),
                      itemCount: video.episodes!.length,
                      itemBuilder: (context, index) {
                        // **FIX: Handle both Map (from backend) and VideoModel types**
                        final episodeData = video.episodes![index];
                        final String episodeId = (episodeData['_id'] ?? episodeData['id']);
                        final String thumbnailUrl = (episodeData['thumbnailUrl'] ?? video.thumbnailUrl);
                        final String sequenceNumber = (index + 1).toString();

                        return GestureDetector(
                          onTap: () {
                              Navigator.pop(context);
                              // Navigate to the selected episode using VideoScreen (Profile Player)
                              // To match "Feed" behavior exactly, we should use VideoFeedAdvanced, 
                              // but this is Profile, so VideoScreen is safer for context.
                              // User said "same as we do in when user click on episode button".
                              // The original code navigates to `VideoFeedAdvanced`.
                              // I will stick to `VideoScreen` for Profile consistency, 
                              // but keep the UI identical.
                              
                              // ... actually, let's use VideoScreen which is already imported.
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => VideoScreen(
                                    initialVideos: stateManager.userVideos, // Context of profile videos
                                    initialVideoId: episodeId,
                                    isFullScreen: true, // **NEW: Full-screen mode**
                                  ),
                                ),
                              );
                              AppLogger.log('Selected episode $sequenceNumber: $episodeId');
                          },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: thumbnailUrl.isNotEmpty 
                                ? CachedNetworkImage(
                                  imageUrl: thumbnailUrl,
                                  fit: BoxFit.cover,
                                  placeholder: (context, url) => Container(color: Colors.grey[300]),
                                  errorWidget: (context, url, error) => Container(
                                    color: Colors.grey[300],
                                    child: const Icon(Icons.error),
                                  ),
                                )
                                : Container(color: Colors.black12),
                              ),
                              // Sequence Number Overlay
                              Positioned(
                                top: 4,
                                left: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.7),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    sequenceNumber,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                              // Play Icon Overlay
                              Center(
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withOpacity(0.5),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
