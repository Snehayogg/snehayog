import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/video/core/data/services/video_service.dart';
import 'package:vayug/features/video/vayu/presentation/screens/vayu_long_form_player_screen.dart';
import 'package:vayug/features/video/core/presentation/screens/video_screen.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/utils/format_utils.dart';
import 'package:vayug/shared/widgets/app_button.dart';
import 'package:vayug/shared/widgets/interactive_scale_button.dart';
import 'package:vayug/shared/widgets/vayu_logo.dart';
import 'package:hugeicons/hugeicons.dart';

class SubscriptionsScreen extends ConsumerStatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  ConsumerState<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen> {
  final VideoService _videoService = VideoService();
  final ScrollController _scrollController = ScrollController();

  List<VideoModel> _videos = [];
  List<VideoModel> _exclusiveVideos = [];
  List<VideoModel> _feedVideos = [];
  List<Uploader> _creators = [];
  
  bool _isLoading = true;
  String? _errorMessage;
  bool? _wasSignedIn;
  Uploader? _selectedCreator;

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadVideos({bool refresh = false}) async {
    if (refresh || _videos.isEmpty) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final videos = await _videoService.getSubscriberVideos();

      if (!mounted) return;

      // Extract unique creators for the Hub
      final creatorsMap = <String, Uploader>{};
      for (var v in videos) {
        creatorsMap[v.uploader.id] = v.uploader;
      }

      setState(() {
        _videos = videos;
        // Logic for separation: 
        // 1. Exclusive: Specific for that user (using a heuristic/flag)
        // 2. Feed: Available to all
        // For now, let's assume videos with "Exclusive" in name or certain tags are exclusive
        _exclusiveVideos = videos.where((v) => 
          v.videoName.toLowerCase().contains('exclusive') || 
          (v.tags?.contains('exclusive') ?? false)
        ).toList();
        
        _feedVideos = videos.where((v) => !_exclusiveVideos.contains(v)).toList();
        _creators = creatorsMap.values.toList();
        _isLoading = false;
      });
    } catch (e) {
      AppLogger.log('❌ SubscriptionsScreen: Error loading videos: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  void _navigateToVideo(int index) {
    if (index >= 0 && index < _videos.length) {
      final video = _videos[index];
      if (video.videoType == 'vayu') {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VayuLongFormPlayerScreen(
              video: video,
              relatedVideos: _videos.where((v) => v.videoType == 'vayu').toList(),
            ),
          ),
        );
      } else {
        // For short-form (yug) videos, push a standalone VideoScreen
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => VideoScreen(
              initialVideos: _videos.where((v) => v.videoType != 'vayu').toList(),
              initialIndex: _videos.where((v) => v.videoType != 'vayu').toList().indexWhere((v) => v.id == video.id).clamp(0, _videos.length),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authController = ref.watch(googleSignInProvider);
    final bool isSignedIn = authController.isSignedIn;

    // Refresh when auth state changes
    if (_wasSignedIn != null && _wasSignedIn != isSignedIn) {
      _wasSignedIn = isSignedIn;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadVideos(refresh: true);
      });
    }
    _wasSignedIn = isSignedIn;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.backgroundPrimary,
            floating: true,
            snap: true,
            elevation: 0,
            title: const VayuLogo(fontSize: 22),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white, size: 22),
                onPressed: () => _loadVideos(refresh: true),
                tooltip: 'Refresh',
              ),
              SizedBox(width: AppSpacing.spacing2),
            ],
          ),
          if (isSignedIn && !_isLoading && _videos.isNotEmpty) ...[
            _buildCreatorHub(),
            if (_exclusiveVideos.isNotEmpty) _buildExclusiveShelf(),
            _buildSectionHeader('Latest from Subscriptions'),
            _buildCompactFeed(),
          ] else
            ..._buildBodySlivers(isSignedIn),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.fromLTRB(AppSpacing.spacing3, AppSpacing.spacing3, AppSpacing.spacing3, AppSpacing.spacing1),
        child: Row(
          children: [
            Text(
              title,
              style: AppTypography.titleMedium.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            const Spacer(),
            if (title.contains('Exclusive'))
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
                ),
                child: Text(
                  'PREMIUM',
                  style: AppTypography.labelSmall.copyWith(color: Colors.amber, fontSize: 10),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCreatorHub() {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing1),
              itemCount: _creators.length,
              itemBuilder: (context, index) {
                final creator = _creators[index];
                final isSelected = _selectedCreator?.id == creator.id;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedCreator = isSelected ? null : creator;
                      if (_selectedCreator != null) {
                        _feedVideos = _videos.where((v) => v.uploader.id == creator.id).toList();
                      } else {
                        _feedVideos = _videos.where((v) => !_exclusiveVideos.contains(v)).toList();
                      }
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(2),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: isSelected ? AppColors.primary : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: CircleAvatar(
                            radius: 28,
                            backgroundImage: creator.profilePic.isNotEmpty 
                                ? CachedNetworkImageProvider(creator.profilePic) 
                                : null,
                            child: creator.profilePic.isEmpty ? const Icon(Icons.person) : null,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SizedBox(
                          width: 60,
                          child: Text(
                            creator.name,
                            style: AppTypography.labelSmall.copyWith(
                              color: isSelected ? AppColors.primary : Colors.white70,
                              fontSize: 10,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(color: Colors.white10, height: 1),
        ],
      ),
    );
  }

  Widget _buildExclusiveShelf() {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Exclusive For You'),
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing1),
              itemCount: _exclusiveVideos.length,
              itemBuilder: (context, index) {
                final video = _exclusiveVideos[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: InteractiveScaleButton(
                    onTap: () => _navigateToVideo(_videos.indexOf(video)),
                    child: Container(
                      width: 280,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: video.thumbnailUrl,
                              fit: BoxFit.cover,
                            ),
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.black.withValues(alpha: 0.8)],
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 8,
                              left: 8,
                              right: 8,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    video.videoName,
                                    style: AppTypography.bodyMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    video.uploader.name,
                                    style: AppTypography.labelSmall.copyWith(color: Colors.white70),
                                  ),
                                ],
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
          ),
        ],
      ),
    );
  }

  Widget _buildCompactFeed() {
    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: AppSpacing.spacing1),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 16,
          childAspectRatio: 0.7, // Portrait focus
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final video = _feedVideos[index];
            if (video.videoType == 'vayu') {
              return _buildCompactVayuCard(video);
            } else {
              return _buildPortraitYugCard(video);
            }
          },
          childCount: _feedVideos.length,
        ),
      ),
    );
  }

  Widget _buildPortraitYugCard(VideoModel video) {
    return InteractiveScaleButton(
      onTap: () => _navigateToVideo(_videos.indexOf(video)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: video.thumbnailUrl,
                    fit: BoxFit.cover,
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                    child: const Icon(Icons.bolt, color: Colors.amber, size: 12),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            video.videoName,
            style: AppTypography.labelMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '${FormatUtils.formatViews(video.views)} views',
            style: AppTypography.labelSmall.copyWith(color: Colors.white54, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactVayuCard(VideoModel video) {
    return InteractiveScaleButton(
      onTap: () => _navigateToVideo(_videos.indexOf(video)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: video.thumbnailUrl,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            video.videoName,
            style: AppTypography.labelMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Row(
            children: [
              const Icon(Icons.play_circle_outline, color: Colors.white54, size: 10),
              const SizedBox(width: 4),
              Text(
                FormatUtils.formatDuration(video.duration),
                style: AppTypography.labelSmall.copyWith(color: Colors.white54, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(bool isSignedIn) {
    if (!isSignedIn) {
      return _buildSignInPrompt();
    }

    if (_isLoading && _videos.isEmpty) {
      return _buildShimmerList();
    }

    if (_errorMessage != null && _videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline,
                color: AppColors.textSecondary.withValues(alpha: 0.7),
                size: 60),
            SizedBox(height: AppSpacing.spacing4),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
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
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: () => _loadVideos(refresh: true),
      color: Colors.white,
      backgroundColor: AppColors.primary,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(bottom: AppSpacing.spacing3),
        itemCount: _videos.length,
        itemBuilder: (context, index) {
          return Padding(
            padding: EdgeInsets.only(bottom: AppSpacing.spacing3),
            child: _buildVideoCard(index),
          );
        },
      ),
    );
  }

  List<Widget> _buildBodySlivers(bool isSignedIn) {
    if (!isSignedIn) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildSignInPrompt(),
        ),
      ];
    }

    if (_isLoading && _videos.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildShimmerList(),
        ),
      ];
    }

    if (_errorMessage != null && _videos.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline,
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                    size: 60),
                SizedBox(height: AppSpacing.spacing4),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
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
          ),
        ),
      ];
    }

    if (_videos.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildEmptyState(),
        ),
      ];
    }

    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            return Padding(
              padding: EdgeInsets.only(bottom: AppSpacing.spacing3),
              child: _buildVideoCard(index),
            );
          },
          childCount: _videos.length,
        ),
      ),
    ];
  }

  Widget _buildSignInPrompt() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.spacing6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const HugeIcon(
                icon: HugeIcons.strokeRoundedUserMultiple02,
                color: AppColors.primary,
                size: 48,
              ),
            ),
            SizedBox(height: AppSpacing.spacing6),
            Text(
              'Sign in to see exclusive content',
              style: AppTypography.titleLarge.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: AppSpacing.spacing2),
            Text(
              'Subscriber-only videos from creators you follow will appear here.',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.spacing6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                shape: BoxShape.circle,
              ),
              child: const HugeIcon(
                icon: HugeIcons.strokeRoundedPlayList,
                color: AppColors.textSecondary,
                size: 48,
              ),
            ),
            SizedBox(height: AppSpacing.spacing6),
            Text(
              'No subscriber content yet',
              style: AppTypography.headlineLarge.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: AppSpacing.spacing2),
            Text(
              'When creators share exclusive content with you, it will show up here.',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoCard(int index) {
    final video = _videos[index];

    return InteractiveScaleButton(
      onTap: () => _navigateToVideo(index),
      scaleDownFactor: 0.96,
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
                      child: const Icon(Icons.broken_image_outlined,
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
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      FormatUtils.formatDuration(video.duration),
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
                AppSpacing.spacing1, AppSpacing.spacing1, AppSpacing.spacing1),
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
                        offset: const Offset(0, 2),
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
                        ? const Icon(Icons.person_outline,
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
                          fontWeight: AppTypography.weightBold,
                          height: 1.3,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Channel Name
                      Text(
                        video.uploader.name,
                        style: AppTypography.bodySmall.copyWith(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontWeight: AppTypography.weightMedium,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // Meta: Views • Time
                      Text(
                        '${FormatUtils.formatViews(video.views)} views • ${FormatUtils.formatTimeAgo(video.uploadedAt)}',
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
          padding: EdgeInsets.fromLTRB(AppSpacing.spacing1, AppSpacing.spacing3,
              AppSpacing.spacing1, AppSpacing.spacing2),
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
                    const SizedBox(height: 8),
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
