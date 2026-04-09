import 'package:flutter/material.dart';
import 'package:vayug/features/video/core/presentation/managers/main_controller.dart';
import 'package:provider/provider.dart' as provider;
import 'package:vayug/features/profile/core/presentation/managers/profile_state_manager.dart';
import 'package:vayug/features/video/core/presentation/screens/video_screen.dart';
import 'package:vayug/features/video/core/presentation/managers/shared_video_controller_pool.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/features/video/vayu/presentation/screens/vayu_long_form_player_screen.dart';
import 'package:vayug/shared/widgets/vayu_bottom_sheet.dart';
import 'package:vayug/shared/utils/format_utils.dart';
import 'package:vayug/features/video/edit/presentation/screens/edit_video_details.dart';

class ProfileVideosWidget extends StatelessWidget {
  final ProfileStateManager stateManager;
  final VoidCallback? onVideoTap;
  final VoidCallback? onVideoLongPress;
  final VoidCallback? onVideoSelection;
  final bool showHeader;
  final bool isSliver;
  final String? filterVideoType;

  const ProfileVideosWidget({
    super.key,
    required this.stateManager,
    this.onVideoTap,
    this.onVideoLongPress,
    this.onVideoSelection,
    this.showHeader = true,
    this.isSliver = false,
    this.filterVideoType,
  });

  void _preloadVideoThumbnails(BuildContext context, List<VideoModel> videos) {
    Future.microtask(() async {
      for (final video in videos.take(5)) {
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

  bool _isVideoProcessing(VideoModel video) {
    final status = video.processingStatus.toLowerCase();
    return video.isOptimistic ||
        status == 'queued' ||
        status == 'pending' ||
        status == 'processing';
  }

  String _processingLabel(VideoModel video) {
    final progress = video.processingProgress.clamp(0, 100);
    return 'Processing $progress%';
  }

  Widget _buildCrossPostStatus(VideoModel video) {
    if (video.crossPostStatus == null || video.crossPostStatus!.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: video.crossPostStatus!.entries.map((entry) {
          final platform = entry.key;
          final status = entry.value.toLowerCase();
          
          IconData icon;
          Color iconColor;
          
          switch (platform) {
            case 'youtube': icon = Icons.play_circle_filled; break;
            case 'instagram': icon = Icons.camera_alt; break;
            case 'facebook': icon = Icons.facebook; break;
            case 'linkedin': icon = Icons.work; break;
            default: icon = Icons.share;
          }

          switch (status) {
            case 'completed': iconColor = Colors.green; break;
            case 'failed': iconColor = Colors.red; break;
            case 'processing': iconColor = Colors.orange; break;
            default: iconColor = Colors.white70;
          }

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2.0),
            child: Icon(icon, size: 12, color: iconColor),
          );
        }).toList(),
      ),
    );
  }

  String _normalizedVideoType(VideoModel video) {
    if (video.aspectRatio > 1.1) return 'vayu';
    if (video.aspectRatio < 0.9) return 'yog';

    final normalized = video.videoType.trim().toLowerCase();
    if (normalized == 'long' ||
        normalized == 'longform' ||
        normalized == 'long_form' ||
        normalized == 'long-form') {
      return 'vayu';
    }
    if (normalized == 'short' ||
        normalized == 'shortform' ||
        normalized == 'short_form' ||
        normalized == 'short-form' ||
        normalized == 'reel') {
      return 'yog';
    }
    if (normalized == 'vayu' || normalized == 'yog') {
      return normalized;
    }
    return normalized;
  }

  bool _matchesFilter(VideoModel video) {
    if (filterVideoType == null || filterVideoType!.isEmpty) return true;
    
    final normalizedType = _normalizedVideoType(video);
    return normalizedType == filterVideoType!.toLowerCase();
  }

  String _emptyTitle() {
    switch (filterVideoType?.trim().toLowerCase()) {
      case 'yog':
        return 'No Yug videos yet';
      case 'vayu':
        return 'No Vayu videos yet';
      default:
        return 'No videos yet';
    }
  }

  String _emptySubtitle() {
    switch (filterVideoType?.trim().toLowerCase()) {
      case 'yog':
        return 'Short-form Yug videos will appear here.';
      case 'vayu':
        return 'Long-form Vayu videos will appear here.';
      default:
        return 'Upload your first video to get started!';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (stateManager.userVideos.isNotEmpty) {
      _preloadVideoThumbnails(context, stateManager.userVideos);
    }

    return provider.Consumer<ProfileStateManager>(
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
          return isSliver
              ? SliverToBoxAdapter(child: loadingWidget)
              : loadingWidget;
        }

        final List<VideoModel> filteredVideos =
            manager.userVideos.where(_matchesFilter).toList(growable: false);

        if (manager.userVideos.isEmpty || filteredVideos.isEmpty) {
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
                  Text(
                    _emptyTitle(),
                    style: const TextStyle(
                      color: Color(0xFF374151),
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _emptySubtitle(),
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
          return isSliver
              ? SliverToBoxAdapter(child: emptyWidget)
              : emptyWidget;
        }

        final List<VideoModel> displayVideos = [];
        final Set<String> processedSeriesIds = {};

        for (final video in filteredVideos) {
          if (video.seriesId != null) {
            if (!processedSeriesIds.contains(video.seriesId)) {
              processedSeriesIds.add(video.seriesId!);
              displayVideos.add(video);
            }
          } else {
            displayVideos.add(video);
          }
        }

        final bool isVayu = filterVideoType?.toLowerCase() == 'vayu';
        final gridDelegate = SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: isVayu ? 2 : 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: isVayu ? (16 / 9) : 0.5,
        );

        if (isSliver) {
          return SliverGrid.builder(
            gridDelegate: gridDelegate,
            itemCount: displayVideos.length,
            itemBuilder: (context, index) => _buildVideoItem(
                context, manager, displayVideos, displayVideos[index], index),
          );
        }

        return RepaintBoundary(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showHeader) ...[
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: gridDelegate,
                  itemCount: displayVideos.length,
                  itemBuilder: (context, index) => _buildVideoItem(context,
                      manager, displayVideos, displayVideos[index], index),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVideoItem(BuildContext context, ProfileStateManager manager,
      List<VideoModel> displayVideos, VideoModel video, int index) {
    final isSelected = manager.selectedVideoIds.contains(video.id);
    final bool isSeries = video.seriesId != null;
    final bool isProcessing = _isVideoProcessing(video);
    final canSelectVideo =
        manager.isSelecting && manager.isOwner && manager.userData != null;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () async {
          if (isProcessing && !manager.isSelecting) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Video is still processing. It will be playable shortly.'),
                duration: Duration(seconds: 2),
              ),
            );
            return;
          }

          if (isSeries && video.episodes != null && video.episodes!.isNotEmpty && !manager.isSelecting) {
            AppLogger.log('🎬 ProfileVideosWidget: Series detected: ${video.id}. Opening episode list.');
            _showEpisodeList(context, video);
            return;
          }

          if (!manager.isSelecting) {
            final sharedPool = SharedVideoControllerPool();
            sharedPool.pauseAllControllers();

            if (_normalizedVideoType(video) == 'vayu') {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => VayuLongFormPlayerScreen(
                    video: video,
                    relatedVideos: displayVideos,
                  ),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => VideoScreen(
                    initialVideos: displayVideos,
                    initialVideoId: video.id,
                  ),
                ),
              );
            }
          } else if (manager.isSelecting && canSelectVideo) {
            manager.toggleVideoSelection(video.id);
          }
        },
        onLongPress: () {
          if (manager.isOwner &&
              manager.userData != null &&
              !manager.isSelecting) {
            manager.enterSelectionMode();
            manager.toggleVideoSelection(video.id);
          }
        },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Stack(
              children: [
                Hero(
                  tag: 'video_player_${video.id}',
                  child: Container(
                    width: double.infinity,
                    height: double.infinity,
                    color: isProcessing
                        ? AppColors.backgroundSecondary
                        : const Color(0xFFF3F4F6),
                    child: video.thumbnailUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: video.thumbnailUrl,
                            fit: BoxFit.cover,
                            width: double.infinity,
                            height: double.infinity,
                            errorWidget: (context, url, error) {
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
                ),

                if (isSeries)
                  Positioned(
                    top: 8,
                    right: (manager.isOwner && !manager.isSelecting && _normalizedVideoType(video) == 'vayu') ? 36 : 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                            width: 0.5),
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

                if (isProcessing)
                  Positioned.fill(
                    child: Container(
                      color:
                          AppColors.backgroundPrimary.withValues(alpha: 0.72),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                value: video.processingProgress.clamp(0, 100) /
                                    100.0,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                    AppColors.primary),
                                backgroundColor: AppColors.borderPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _processingLabel(video),
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                if (!isProcessing && video.crossPostStatus != null)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: _buildCrossPostStatus(video),
                  ),
                
                if (manager.isOwner && !manager.isSelecting && _normalizedVideoType(video) == 'vayu')
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () async {
                        final result = await Navigator.push<Map<String, dynamic>>(
                          context,
                          MaterialPageRoute(
                            builder: (context) => EditVideoDetails(video: video),
                          ),
                        );
                        
                          if (result != null) {
                            manager.refreshData();
                         }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.edit_outlined,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ),

                if (isSelected)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.2),
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

                if (!isProcessing)
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.play_arrow_outlined,
                              color: Colors.white, size: 12),
                          const SizedBox(width: 2),
                          Text(
                            FormatUtils.formatViews(video.views),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

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
                          color: isSelected
                              ? const Color(0xFFEF4444)
                              : Colors.white.withValues(alpha: 0.8),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFFEF4444)
                                : Colors.white,
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
    AppLogger.log('🎬 ProfileVideosWidget: Showing episode list for series: ${video.seriesId}');
    VayuBottomSheet.show(
      context: context,
      title: 'More Episodes',
      useDraggable: true,
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.8,
      padding: const EdgeInsets.all(16),
      builder: (context, scrollController) {
        return GridView.builder(
          controller: scrollController,
          padding: EdgeInsets.zero,
          physics: const BouncingScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 0.7,
          ),
          itemCount: video.episodes!.length,
          itemBuilder: (context, index) {
            final episodeData = video.episodes![index];
            final String episodeId = (episodeData['_id'] ?? episodeData['id'])?.toString() ?? '';
            final String thumbnailUrl =
                (episodeData['thumbnailUrl'] ?? video.thumbnailUrl)?.toString() ?? '';
            final String sequenceNumber = (index + 1).toString();

            return GestureDetector(
              onTap: () {
                AppLogger.log('🎬 ProfileVideosWidget: Selected episode: $episodeId');
                Navigator.pop(context);
                final parentType = _normalizedVideoType(video);
                final filteredVideos = stateManager.userVideos
                    .where((item) => _normalizedVideoType(item) == parentType)
                    .toList(growable: false);
                if (parentType == 'vayu') {
                  final selectedEpisodeIndex =
                      filteredVideos.indexWhere((item) => item.id == episodeId);
                  final selectedEpisode = selectedEpisodeIndex >= 0
                      ? filteredVideos[selectedEpisodeIndex]
                      : video;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => VayuLongFormPlayerScreen(
                        video: selectedEpisode,
                        relatedVideos: filteredVideos,
                      ),
                    ),
                  );
                } else {
                    final mainController = provider.Provider.of<MainController>(context, listen: false);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => VideoScreen(
                          initialVideos: filteredVideos,
                          initialVideoId: episodeId,
                          parentTabIndex: mainController.currentIndex,
                        ),
                      ),
                    );
                }
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
                            placeholder: (context, url) =>
                                Container(color: Colors.grey[300]),
                            errorWidget: (context, url, error) => Container(
                              color: Colors.grey[300],
                              child: const Icon(Icons.error),
                            ),
                          )
                        : Container(color: Colors.black12),
                  ),
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
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
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
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
        );
      },
    );
  }
}
