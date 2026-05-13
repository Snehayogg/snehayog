import 'package:flutter/material.dart';
import 'package:vayug/features/video/core/data/services/video_service.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/features/video/core/presentation/screens/video_screen.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/features/video/vayu/presentation/screens/vayu_long_form_player_screen.dart';
import 'package:vayug/shared/widgets/unified_video_card.dart';
import 'package:vayug/features/video/core/presentation/managers/shared_video_controller_pool.dart';
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


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text(
              'Saved Videos',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
            backgroundColor: AppColors.backgroundPrimary,
            floating: true,
            snap: true,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline,
                        size: 48, color: AppColors.error),
                    const SizedBox(height: 16),
                    const Text(
                      'Failed to load saved videos',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 8),
                    AppButton(
                      onPressed: _loadSavedVideos,
                      label: 'Retry',
                      variant: AppButtonVariant.primary,
                    ),
                  ],
                ),
              ),
            )
          else if (_savedVideos.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        color: AppColors.surfacePrimary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.bookmark_outline,
                        size: 40,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'No saved videos',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Videos you bookmark will appear here.',
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final video = _savedVideos[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: SizedBox(
                      height: 120,
                      child: UnifiedVideoCard(
                        video: video,
                        cardType: video.videoType == 'vayu' 
                            ? UnifiedVideoCardType.vayu 
                            : UnifiedVideoCardType.yug,
                        onTap: () {
                          final sharedPool = SharedVideoControllerPool();
                          sharedPool.pauseAllControllers();
    
                          if (video.videoType == 'vayu') {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => VayuLongFormPlayerScreen(
                                  video: video,
                                  relatedVideos: _savedVideos,
                                ),
                              ),
                            );
                          } else {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => VideoScreen(
                                  initialVideos: _savedVideos,
                                  initialVideoId: video.id,
                                ),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  );
                },
                childCount: _savedVideos.length,
              ),
            ),
        ],
      ),
    );
  }
}

