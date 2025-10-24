import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:vayu/core/managers/profile_state_manager.dart';
import 'package:vayu/core/services/profile_screen_logger.dart';
import 'package:vayu/view/screens/video_screen.dart';

class ProfileVideosWidget extends StatelessWidget {
  final ProfileStateManager stateManager;
  final bool isVideosLoaded;
  final VoidCallback? onVideoTap;
  final VoidCallback? onVideoLongPress;
  final VoidCallback? onVideoSelection;

  const ProfileVideosWidget({
    super.key,
    required this.stateManager,
    required this.isVideosLoaded,
    this.onVideoTap,
    this.onVideoLongPress,
    this.onVideoSelection,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your Videos',
              style: TextStyle(
                color: Color(0xFF1A1A1A),
                fontSize: 20,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 16),
            Consumer<ProfileStateManager>(
              builder: (context, stateManager, child) {
                if (!isVideosLoaded) {
                  return RepaintBoundary(
                    child: Container(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          const SizedBox(
                            width: 40,
                            height: 40,
                            child: CircularProgressIndicator(),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Loading your videos...',
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 16,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                if (stateManager.userVideos.isEmpty) {
                  return RepaintBoundary(
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
                              fontSize: 16,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return RepaintBoundary(
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                      childAspectRatio: 0.75,
                    ),
                    itemCount: stateManager.userVideos.length,
                    itemBuilder: (context, index) {
                      final video = stateManager.userVideos[index];
                      final isSelected =
                          stateManager.selectedVideoIds.contains(video.id);

                      // Simplified video selection logic
                      final canSelectVideo = stateManager.isSelecting &&
                          stateManager.userData != null;
                      return RepaintBoundary(
                        child: GestureDetector(
                          onTap: () {
                            if (!stateManager.isSelecting) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => VideoScreen(
                                    initialIndex: index,
                                    initialVideos: stateManager.userVideos,
                                  ),
                                ),
                              );
                            } else if (stateManager.isSelecting &&
                                canSelectVideo) {
                              // Use proper logic for video selection
                              ProfileScreenLogger.logVideoSelection(
                                  videoId: video.id,
                                  isSelected: !stateManager.selectedVideoIds
                                      .contains(video.id));
                              ProfileScreenLogger.logDebugInfo(
                                  'Video ID: ${video.id}');
                              ProfileScreenLogger.logDebugInfo(
                                  'Can select: $canSelectVideo');
                              stateManager.toggleVideoSelection(video.id);
                            } else {
                              ProfileScreenLogger.logDebugInfo(
                                  'Video tapped but not selectable');
                              ProfileScreenLogger.logDebugInfo(
                                  'isSelecting: ${stateManager.isSelecting}');
                              ProfileScreenLogger.logDebugInfo(
                                  'canSelectVideo: $canSelectVideo');
                            }
                          },
                          onLongPress: () {
                            // Long press: Enter selection mode for deletion
                            ProfileScreenLogger.logDebugInfo(
                                'Long press detected on video');
                            ProfileScreenLogger.logDebugInfo(
                                'userData: ${stateManager.userData != null}');
                            ProfileScreenLogger.logDebugInfo(
                                'canSelectVideo: $canSelectVideo');
                            ProfileScreenLogger.logDebugInfo(
                                'isSelecting: ${stateManager.isSelecting}');

                            if (stateManager.userData != null &&
                                !stateManager.isSelecting) {
                              ProfileScreenLogger.logDebugInfo(
                                  'Entering selection mode via long press');
                              stateManager.enterSelectionMode();
                              stateManager.toggleVideoSelection(video.id);
                            } else {
                              ProfileScreenLogger.logDebugInfo(
                                  'Cannot enter selection mode via long press');
                            }
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.08),
                                  blurRadius: 12,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
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
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                              ProfileScreenLogger.logError(
                                                  'Error loading thumbnail: $error');
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

                                  // Views Overlay
                                  Positioned(
                                    bottom: 12,
                                    left: 12,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
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
                                          color: const Color(0xFFEF4444)
                                              .withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(16),
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
                                  if (stateManager.isSelecting &&
                                      canSelectVideo)
                                    Positioned(
                                      top: 12,
                                      right: 12,
                                      child: GestureDetector(
                                        onTap: () {
                                          stateManager
                                              .toggleVideoSelection(video.id);
                                        },
                                        child: Container(
                                          width: 24,
                                          height: 24,
                                          decoration: BoxDecoration(
                                            color: isSelected
                                                ? const Color(0xFFEF4444)
                                                : Colors.white.withOpacity(0.8),
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
                    },
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
