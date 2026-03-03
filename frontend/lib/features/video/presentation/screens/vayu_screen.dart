import 'package:flutter/material.dart';
import 'package:vayu/core/design/spacing.dart';
import 'package:vayu/core/design/radius.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayu/features/video/video_model.dart';
import 'package:vayu/features/video/data/services/video_service.dart';
import 'package:vayu/features/video/presentation/screens/vayu_long_form_player_screen.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:vayu/features/profile/presentation/widgets/video_creator_search_delegate.dart';
import 'package:vayu/core/design/colors.dart';
import 'package:vayu/core/design/typography.dart';
import 'package:vayu/shared/widgets/vayu_logo.dart';
import 'package:vayu/features/agent/presentation/screens/agent_screen.dart';
import 'package:vayu/shared/config/feature_flags.dart';
import 'package:vayu/shared/widgets/app_button.dart';
import 'package:provider/provider.dart';
import 'package:vayu/features/auth/presentation/controllers/google_sign_in_controller.dart';

import 'package:vayu/shared/services/local_gallery_service.dart';
import 'package:vayu/shared/widgets/interactive_scale_button.dart';

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
  bool? _wasSignedIn;
  bool _isOfflineMode = false;

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
        _isOfflineMode = false; // Updated
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

      // **BACKEND TRUSTED: API already filters for 'vayu'**
      // We still apply a local filter just to be 100% sure only long form appears
      final List<VideoModel> longFormVideos = newVideos.where((v) => 
        (v.videoType == 'vayu' || v.duration.inSeconds > 60) && v.aspectRatio > 0.9
      ).toList();

      AppLogger.log(
          '🎬 VayuScreen: Fetched ${newVideos.length} videos from backend');

      setState(() {
        if (refresh) {
          _videos = longFormVideos;
        } else {
          final existingIds = _videos.map((v) => v.id).toSet();
          final uniqueNewVideos =
              longFormVideos.where((v) => !existingIds.contains(v.id)).toList();
          _videos.addAll(uniqueNewVideos);
        }

        _hasMore = hasMore;
        _isOfflineMode = false; // Updated
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.log(
          '❌ VayuScreen: Error loading videos from backend: $e. Falling back to local gallery...');

      try {
        // Fallback to local gallery videos if offline
        // Vayu specifically wants videos > 1 minute
        final localVideos = await localGalleryService.fetchGalleryVideos(
          page: _currentPage - 1,
          limit: 10,
          minDuration: const Duration(minutes: 1),
        );

        if (!mounted) return;

        setState(() {
          if (refresh) {
            _videos = localVideos;
          } else {
            final existingIds = _videos.map((v) => v.id).toSet();
            final uniqueNewVideos =
                localVideos.where((v) => !existingIds.contains(v.id)).toList();
            _videos.addAll(uniqueNewVideos);
          }

          _hasMore = localVideos.length >= 10;
          _isOfflineMode = true;
          _isLoading = false;
          _errorMessage =
              null; // Clear error since we are showing offline content
        });

        AppLogger.log(
            '✅ VayuScreen: Loaded ${localVideos.length} local Vayu videos for offline mode');
      } catch (galleryError) {
        AppLogger.log(
            '❌ VayuScreen: Error loading local gallery videos: $galleryError');
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage =
                'Failed to load videos and offline gallery access failed.';
          });
        }
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
    return Consumer<GoogleSignInController>(
      builder: (context, authController, _) {
        final bool isSignedIn = authController.isSignedIn;

        // **SYNC: Trigger refresh when auth state changes**
        if (_wasSignedIn != null && _wasSignedIn != isSignedIn) {
          _wasSignedIn = isSignedIn;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              refreshVideos();
            }
          });
        }
        _wasSignedIn = isSignedIn;

        return Scaffold(
          backgroundColor: AppColors.backgroundPrimary,
          appBar: AppBar(
            backgroundColor: AppColors.backgroundPrimary,
            elevation: 0,
            title: Row(
              children: [
                const VayuLogo(fontSize: 22),
                if (_isOfflineMode) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.cloud_off,
                            size: 12, color: Colors.orange),
                       const SizedBox(width: 4),
                        Text(
                          'OFFLINE',
                          style: AppTypography.labelSmall.copyWith(
                            color: Colors.orange,
                            fontWeight: AppTypography.weightBold,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.search_rounded,
                    color: AppColors.textPrimary, size: 22),
                onPressed: () {
                  showSearch(
                    context: context,
                    delegate: VideoCreatorSearchDelegate(),
                  );
                },
                tooltip: 'Search',
              ),
              if (FeatureFlags.isAgentEnabled)
                IconButton(
                  icon: const Icon(Icons.auto_awesome_outlined,
                      color: AppColors.textPrimary, size: 22),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (context) => const AgentScreen()),
                    );
                  },
                  tooltip: 'Agent',
                ),
              SizedBox(width: AppSpacing.spacing2),
            ],
          ),
          body: _buildBody(),
        );
      },
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
            Icon(Icons.wifi_off,
                color: AppColors.textSecondary.withValues(alpha: 0.7), size: 60),
            SizedBox(height: AppSpacing.spacing4),
            Text(
              _errorMessage!,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary.withValues(alpha: 0.9),
              ),
            ),
            SizedBox(height: AppSpacing.spacing6),
            AppButton(
              onPressed: () => _loadVideos(refresh: true),
              label: 'Try Again',
              variant: AppButtonVariant.outline,
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
                color: AppColors.textSecondary.withValues(alpha: 0.4), size: 80),
            SizedBox(height: AppSpacing.spacing6),
            Text(
              'No long-form videos yet',
              style: AppTypography.headlineLarge.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: AppTypography.weightBold),
            ),
            SizedBox(height: AppSpacing.spacing2),
            Text(
              'Browse through your personal video collection',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary.withValues(alpha: 0.9),
              ),
            ),
            SizedBox(height: AppSpacing.spacing6),
            AppButton(
              onPressed: () => _loadVideos(refresh: true),
              isLoading: _isLoading,
              isDisabled: _isLoading,
              label: 'Refresh',
              variant: AppButtonVariant.primary,
            ),
          ],
        ),
      );
    }

    // Calculate total items: just videos + loader
    final int totalItems =
        _videos.length + (_isLoading && _videos.isNotEmpty ? 1 : 0);

    return RefreshIndicator(
      onRefresh: () async {
        await _loadVideos(refresh: true);
      },
      color: Colors.white,
      backgroundColor: AppColors.primary,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: totalItems,
        itemBuilder: (context, index) {
          if (index >= _videos.length) {
            return Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.spacing8),
              child: const Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            );
          }
          return Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.spacing4),
            child: _buildVideoCard(index),
          );
        },
      ),
    );
  }

  Widget _buildVideoCard(int index) {
    final video = _videos[index];

    return InteractiveScaleButton(
      onTap: () => _navigateToVideo(index),
      scaleDownFactor: 0.96, // Slight scale for large cards
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Thumbnail Section (16:9)
          Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: CachedNetworkImage(
                    imageUrl: video.thumbnailUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: Icon(Icons.broken_image_outlined,
                          color: Colors.white10, size: 32),
                    ),
                  ),
                ),
              ),
              // Duration Badge
              if (video.duration.inSeconds > 0)
                Positioned(
                  bottom: AppSpacing.spacing2,
                  right: AppSpacing.spacing2,
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _formatDuration(video.duration),
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white,
                        fontWeight: AppTypography.weightBold,
                        fontSize: 11,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
            ],
          ),

          // 2. Info Section (Below Thumbnail)
          Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.spacing1,
                AppSpacing.spacing3, AppSpacing.spacing1, AppSpacing.spacing2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.white.withValues(alpha: 0.05),
                    backgroundImage: video.uploader.profilePic.isNotEmpty
                        ? CachedNetworkImageProvider(video.uploader.profilePic)
                        : null,
                    child: video.uploader.profilePic.isEmpty
                        ? Icon(Icons.person_outline,
                            size: 20, color: Colors.white30)
                        : null,
                  ),
                ),
                SizedBox(width: AppSpacing.spacing3),
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
                        style: AppTypography.bodyLarge.copyWith(
                          color: Colors.white,
                          fontWeight:
                              AppTypography.weightBold, // Stronger title
                          height: 1.3,
                          fontSize: 15,
                        ),
                      ),
                      SizedBox(height: 4),
                      // Channel Name
                      Text(
                        video.uploader.name,
                        style: AppTypography.bodySmall.copyWith(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontWeight: AppTypography.weightMedium,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(height: 4),
                      // Meta: Views • Time
                      Text(
                        '${_formatViews(video.views)} • ${_formatTimeAgo(video.uploadedAt)}',
                        style: AppTypography.bodySmall.copyWith(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShimmerList() {
    return ListView.builder(
      itemCount: 4,
      padding: EdgeInsets.only(bottom: AppSpacing.spacing4),
      itemBuilder: (context, index) => Padding(
        padding: EdgeInsets.only(bottom: AppSpacing.spacing4),
        child: _buildShimmerItem(),
      ),
    );
  }

  Widget _buildShimmerItem() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(AppSpacing.spacing1,
              AppSpacing.spacing3, AppSpacing.spacing1, AppSpacing.spacing2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.03),
                ),
              ),
              SizedBox(width: AppSpacing.spacing3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 16,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    SizedBox(height: 8),
                    Container(
                      height: 14,
                      width: 150,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.02),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
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
