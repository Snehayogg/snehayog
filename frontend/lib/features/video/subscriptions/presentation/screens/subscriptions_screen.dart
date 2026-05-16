import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/providers/auth_providers.dart';
import 'package:vayug/core/providers/subscription_providers.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/video/vayu/presentation/screens/vayu_long_form_player_screen.dart';
import 'package:vayug/features/video/core/presentation/screens/video_screen.dart';
import 'package:vayug/shared/widgets/unified_video_card.dart';
import 'package:vayug/shared/utils/format_utils.dart';
import 'package:vayug/shared/widgets/interactive_scale_button.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:vayug/features/video/subscriptions/presentation/managers/subscription_state_manager.dart';

class SubscriptionsScreen extends ConsumerStatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  ConsumerState<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen> {
  bool? _wasSignedIn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(subscriptionStateManagerProvider).loadSubscriberContent();
    });
  }

  void _navigateToVideo(VideoModel video, List<VideoModel> allVideos) {
    if (video.videoType == 'vayu') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VayuLongFormPlayerScreen(
            video: video,
            relatedVideos: allVideos.where((v) => v.videoType == 'vayu').toList(),
          ),
        ),
      );
    } else {
      final yugVideos = allVideos.where((v) => v.videoType != 'vayu').toList();
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => VideoScreen(
            initialVideos: yugVideos,
            initialIndex: yugVideos.indexWhere((v) => v.id == video.id).clamp(0, yugVideos.length),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authController = ref.watch(googleSignInProvider);
    final isSignedIn = authController.isSignedIn;
    final state = ref.watch(subscriptionStateManagerProvider);

    // React to Auth Changes
    if (_wasSignedIn != null && _wasSignedIn != isSignedIn) {
      _wasSignedIn = isSignedIn;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (isSignedIn) {
            ref.read(subscriptionStateManagerProvider).loadSubscriberContent(refresh: true);
          } else {
            ref.read(subscriptionStateManagerProvider).reset();
          }
        }
      });
    }
    _wasSignedIn = isSignedIn;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: RefreshIndicator(
        onRefresh: () => ref.read(subscriptionStateManagerProvider).loadSubscriberContent(refresh: true),
        color: Colors.white,
        backgroundColor: AppColors.primary,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            _buildAppBar(),
            if (isSignedIn && !state.isLoading && state.allVideos.isNotEmpty) ...[
              _buildExplanationNote(),
              if (state.exclusiveVideos.isNotEmpty) _buildExclusiveShelf(state),
              _buildCompactFeed(state),
            ] else
              ..._buildBodySlivers(isSignedIn, state),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      backgroundColor: AppColors.backgroundPrimary,
      floating: true,
      snap: true,
      elevation: 0,
      title: Text(
        'Subscriptions',
        style: AppTypography.titleLarge.copyWith(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white, size: 22),
          onPressed: () => ref.read(subscriptionStateManagerProvider).loadSubscriberContent(refresh: true),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildExplanationNote() {
    return SliverToBoxAdapter(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.info_outline, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Ye exclusive videos hain jo creators ne specially aapke liye publish kiye hain.',
                style: AppTypography.bodySmall.copyWith(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExclusiveShelf(SubscriptionStateManager state) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text('Exclusive For You', style: AppTypography.titleMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: state.exclusiveVideos.length,
              itemBuilder: (context, index) {
                final video = state.exclusiveVideos[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: InteractiveScaleButton(
                    onTap: () => _navigateToVideo(video, state.allVideos),
                    child: _buildExclusiveCard(video),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExclusiveCard(VideoModel video) {
    return Container(
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
            CachedNetworkImage(imageUrl: video.thumbnailUrl, fit: BoxFit.cover),
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
              bottom: 8, left: 8, right: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(video.videoName, style: AppTypography.bodyMedium.copyWith(color: Colors.white, fontWeight: FontWeight.bold), maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(video.uploader.name, style: AppTypography.labelSmall.copyWith(color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactFeed(SubscriptionStateManager state) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: state.feedVideos.map((video) {
            final isVayu = video.videoType == 'vayu';
            final width = isVayu ? (MediaQuery.of(context).size.width - 24) / 2 : (MediaQuery.of(context).size.width - 32) / 3;
            final height = isVayu ? width * (9 / 16) : width * 2;
            return SizedBox(
              width: width, height: height,
              child: UnifiedVideoCard(
                video: video,
                cardType: isVayu ? UnifiedVideoCardType.vayu : UnifiedVideoCardType.yug,
                onTap: () => _navigateToVideo(video, state.allVideos),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  List<Widget> _buildBodySlivers(bool isSignedIn, SubscriptionStateManager state) {
    if (!isSignedIn) return [SliverFillRemaining(hasScrollBody: false, child: _buildSignInPrompt())];
    if (state.isLoading && state.allVideos.isEmpty) return [SliverFillRemaining(hasScrollBody: false, child: _buildShimmerList())];
    if (state.status == SubscriptionStatus.error && state.allVideos.isEmpty) {
      return [SliverFillRemaining(hasScrollBody: false, child: _buildErrorView(state.errorMessage))];
    }
    if (state.allVideos.isEmpty) return [SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState())];

    return [
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildVideoCard(state.allVideos[index], state.allVideos),
          ),
          childCount: state.allVideos.length,
        ),
      ),
    ];
  }

  Widget _buildSignInPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const HugeIcon(
            icon: HugeIcons.strokeRoundedUserMultiple02, 
            color: AppColors.primary, 
            size: 48
          ),
          const SizedBox(height: 24),
          Text('Sign in to see exclusive content', style: AppTypography.titleLarge.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Subscriber-only videos from creators you follow will appear here.', textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildErrorView(String? message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, color: AppColors.textSecondary, size: 60),
          const SizedBox(height: 16),
          Text(message ?? 'Unknown error', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => ref.read(subscriptionStateManagerProvider).loadSubscriberContent(refresh: true),
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(child: Text('No subscriber content yet'));
  }

  Widget _buildVideoCard(VideoModel video, List<VideoModel> allVideos) {
    return InteractiveScaleButton(
      onTap: () => _navigateToVideo(video, allVideos),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(imageUrl: video.thumbnailUrl, fit: BoxFit.cover),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                CircleAvatar(backgroundImage: CachedNetworkImageProvider(video.uploader.profilePic)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(video.videoName, style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.bold), maxLines: 2),
                      Text('${video.uploader.name} • ${FormatUtils.formatTimeAgo(video.uploadedAt)}'),
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
    return const Center(child: CircularProgressIndicator());
  }
}
