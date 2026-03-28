import 'package:vayu/features/auth/data/services/authservices.dart';
import 'package:provider/provider.dart' as provider;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayu/features/auth/data/usermodel.dart';
import 'package:vayu/features/video/core/data/models/video_model.dart';
import 'package:vayu/shared/services/search_service.dart';
import 'package:vayu/features/profile/presentation/screens/profile_screen.dart';
import 'package:vayu/features/video/core/presentation/screens/video_screen.dart';
import 'package:vayu/core/design/theme.dart';
import 'package:vayu/core/design/colors.dart';
import 'package:vayu/core/design/typography.dart';
import 'package:vayu/shared/utils/format_utils.dart';
import 'package:vayu/features/video/vayu/presentation/screens/vayu_long_form_player_screen.dart';

/// Global search UI for videos and creators.
class VideoCreatorSearchDelegate extends SearchDelegate<void> {
  final SearchService _searchService;
  Timer? _suggestionDebounce;
  String _lastSuggestionQuery =
      ''; // **FIX: Track last query for proper rebuilds**
  Future<Map<String, dynamic>>? _suggestionFuture; // **FIX: Track future**

  VideoCreatorSearchDelegate({SearchService? searchService})
      : _searchService = searchService ?? SearchService();

  @override
  void dispose() {
    _suggestionDebounce?.cancel();
    super.dispose();
  }

  @override
  String? get searchFieldLabel => 'Search videos, creators...';

  @override
  ThemeData appBarTheme(BuildContext context) {
    return AppTheme.lightTheme.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.backgroundPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        titleTextStyle: AppTypography.titleLarge.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: InputBorder.none,
        hintStyle:
            AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
      ),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    return <Widget>[
      if (query.isNotEmpty)
        IconButton(
          icon: const Icon(Icons.clear),
          onPressed: () {
            query = '';
            showSuggestions(context);
          },
        ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    final String q = query.trim();
    if (q.isEmpty) {
      return const Center(
        child: Text('Type a name or video to search'),
      );
    }

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: 'Top'),
              Tab(text: 'Videos'),
              Tab(text: 'Creators'),
            ],
          ),
          Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
              future: _performSearch(q),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return _buildErrorState();
                }

                final data = snapshot.data ?? {};
                final videos = data['videos'] as List<VideoModel>? ?? [];
                final creators = data['creators'] as List<UserModel>? ?? [];

                if (videos.isEmpty && creators.isEmpty) {
                  return _buildNoResultsState();
                }

                return TabBarView(
                  children: [
                    _buildTopTab(context, videos, creators),
                    _buildVideosTab(context, videos),
                    _buildCreatorsTab(context, creators),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<Map<String, dynamic>> _performSearch(String q) async {
    final videos = await _searchService.searchVideos(q);
    final creators = await _searchService.searchCreators(q);
    return {'videos': videos, 'creators': creators};
  }

  Widget _buildTopTab(
      BuildContext context, List<VideoModel> videos, List<UserModel> creators) {
    // Separate videos by type for non-uniform layout
    final vayuVideos = videos.where((v) => v.videoType == 'vayu').toList();
    final yogVideos = videos.where((v) => v.videoType != 'vayu').toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (creators.isNotEmpty) ...[
          _buildSectionHeader(context, 'Creators'),
          ...creators
              .take(3)
              .map((u) => _buildCreatorResultTile(context, u)),
          if (creators.length > 3)
            _buildSeeMoreButton(context, 2), // Index 2 is Creators tab
        ],
        if (vayuVideos.isNotEmpty) ...[
          _buildSectionHeader(context, 'Videos'),
          ...vayuVideos.take(2).map((v) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: _buildVayuVideoCard(context, v, videos),
              )),
          if (vayuVideos.length > 2 || yogVideos.isNotEmpty)
            _buildSeeMoreButton(context, 1),
        ],
        if (yogVideos.isNotEmpty && vayuVideos.isEmpty) ...[
          _buildSectionHeader(context, 'Shorts'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.5,
              ),
              itemCount: yogVideos.length > 6 ? 6 : yogVideos.length,
              itemBuilder: (context, index) =>
                  _buildYogVideoGridItem(context, yogVideos[index], videos),
            ),
          ),
          if (yogVideos.length > 6)
            _buildSeeMoreButton(context, 1),
        ],
      ],
    );
  }

  Widget _buildVideosTab(BuildContext context, List<VideoModel> videos) {
    if (videos.isEmpty) return _buildNoResultsState();

    final vayuVideos = videos.where((v) => v.videoType == 'vayu').toList();
    final yogVideos = videos.where((v) => v.videoType != 'vayu').toList();

    return CustomScrollView(
      slivers: [
        if (vayuVideos.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _buildSectionHeader(context, 'Long Videos'),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: _buildVayuVideoCard(context, vayuVideos[index], videos),
                ),
                childCount: vayuVideos.length,
              ),
            ),
          ),
        ],
        if (yogVideos.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _buildSectionHeader(context, 'Shorts'),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 10,
                childAspectRatio: 0.5,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) =>
                    _buildYogVideoGridItem(context, yogVideos[index], videos),
                childCount: yogVideos.length,
              ),
            ),
          ),
        ],
        // Extra space at bottom
        const SliverToBoxAdapter(child: SizedBox(height: 80)),
      ],
    );
  }

  Widget _buildCreatorsTab(BuildContext context, List<UserModel> creators) {
    if (creators.isEmpty) return _buildNoResultsState();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: creators.length,
      itemBuilder: (context, index) =>
          _buildCreatorResultTile(context, creators[index]),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: AppTypography.titleMedium.copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _buildSeeMoreButton(BuildContext context, int tabIndex) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Center(
        child: TextButton(
          onPressed: () {
            DefaultTabController.of(context).animateTo(tabIndex);
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'See more in results',
                style: AppTypography.labelMedium.copyWith(color: AppColors.primary),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.arrow_forward, size: 14, color: AppColors.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'Search failed. Please try again.',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResultsState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off, size: 48, color: Colors.grey),
          const SizedBox(height: 16),
          Text(
            'No results found',
            style: AppTypography.titleMedium.copyWith(color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    final String q = query.trim();

    // Show empty state when query is too short
    if (q.isEmpty) {
      _lastSuggestionQuery = '';
      _suggestionFuture = null;
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.search, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'Search for creators or videos',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Type at least 2 characters to see suggestions',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    if (q.length < 2) {
      _lastSuggestionQuery = '';
      _suggestionFuture = null;
      return Center(
        child: Text(
          'Type at least 2 characters...',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    // **FIX: Create new future only when query changes**
    if (q != _lastSuggestionQuery) {
      _lastSuggestionQuery = q;
      _suggestionDebounce?.cancel();
      final completer = Completer<Map<String, dynamic>>();
      _suggestionDebounce = Timer(const Duration(milliseconds: 600), () async {
        try {
          final result = await _searchService.getSuggestions(q);
          if (!completer.isCompleted) {
            completer.complete(result);
          }
        } catch (e) {
          if (!completer.isCompleted) {
            completer.complete(<String, dynamic>{
              'creators': <UserModel>[],
              'videos': <VideoModel>[],
            });
          }
        }
      });
      _suggestionFuture = completer.future;
    }

    // **FIX: Use FutureBuilder with key to force rebuild on query change**
    return FutureBuilder<Map<String, dynamic>>(
      key: ValueKey<String>(q), // **FIX: Force rebuild when query changes**
      future: _suggestionFuture,
      builder:
          (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data ?? <String, dynamic>{};
        final List<UserModel> creators =
            (data['creators'] as List<UserModel>? ?? <UserModel>[]);
        final List<VideoModel> videos =
            (data['videos'] as List<VideoModel>? ?? <VideoModel>[]);

        if (creators.isEmpty && videos.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(Icons.search_off, size: 48, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No suggestions found',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Press Enter to search anyway',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView(
          children: <Widget>[
            if (creators.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.person, size: 18, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Text(
                      'Creators',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                    ),
                  ],
                ),
              ),
            ...creators.take(5).map(
              (UserModel u) => _buildCreatorSuggestionTile(context, u),
            ),
            // **FIX: Only show "Tap to see all results" for videos while typing**
            if (videos.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.search, color: AppColors.primary),
                title: Text(
                  'Search for "${query.trim()}" in videos',
                  style: AppTypography.titleSmall.copyWith(color: AppColors.primary),
                ),
                onTap: () => showResults(context),
              ),
          ],
        );
      },
    );
  }

  /// **PROFESSIONAL: Build creator result tile (full search results)**
  Widget _buildCreatorResultTile(BuildContext context, UserModel creator) {
    return ListTile(
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.backgroundSecondary,
        backgroundImage: creator.profilePic.isNotEmpty
            ? CachedNetworkImageProvider(creator.profilePic)
            : null,
        child: creator.profilePic.isEmpty
            ? const Icon(Icons.person, color: AppColors.textSecondary)
            : null,
      ),
      title: Text(
        creator.name,
        style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        (creator.bio?.isNotEmpty ?? false) ? creator.bio! : 'View profile',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.bodySmall,
      ),
      trailing: const Icon(Icons.arrow_forward_ios,
          size: 14, color: AppColors.textTertiary),
      onTap: () {
        close(context, null);

        final authService = provider.Provider.of<AuthService>(context, listen: false);
        final myId = authService.currentUserId;

        if (creator.id == myId) {
          // If navigating to self, pop to root (Profile Tab root)
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          // Push profile screen
          Navigator.of(context).push(
            MaterialPageRoute(
              settings: const RouteSettings(name: 'profile_creator'),
              builder: (_) => ProfileScreen(userId: creator.id),
            ),
          );
        }
      },
    );
  }

  /// **PROFESSIONAL: Build creator suggestion tile (autocomplete)**
  Widget _buildCreatorSuggestionTile(BuildContext context, UserModel creator) {
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 18,
        backgroundColor: AppColors.backgroundSecondary,
        backgroundImage: creator.profilePic.isNotEmpty
            ? CachedNetworkImageProvider(creator.profilePic)
            : null,
        child: creator.profilePic.isEmpty
            ? const Icon(Icons.person, color: AppColors.textSecondary, size: 18)
            : null,
      ),
      title: Text(
        creator.name,
        style: AppTypography.titleSmall.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        (creator.bio?.isNotEmpty ?? false) ? creator.bio! : 'View profile',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.labelSmall,
      ),
      trailing:
          const Icon(Icons.north_west, size: 14, color: AppColors.textTertiary),
      onTap: () {
        close(context, null);

        final authService = provider.Provider.of<AuthService>(context, listen: false);
        final myId = authService.currentUserId;

        if (creator.id == myId) {
          // If navigating to self, pop to root (Profile Tab root)
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          // Push profile screen
          Navigator.of(context).push(
            MaterialPageRoute(
              settings: const RouteSettings(name: 'profile_creator'),
              builder: (_) => ProfileScreen(userId: creator.id),
            ),
          );
        }
      },
    );
  }

  /// **Large format card for Vayu (Long-form) videos**
  Widget _buildVayuVideoCard(BuildContext context, VideoModel video, List<VideoModel> allVideos) {
    return GestureDetector(
      onTap: () {
        // DON'T call close(context, null) to allow back navigation to search
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VayuLongFormPlayerScreen(
              video: video,
              relatedVideos: allVideos.where((v) => v.id != video.id).toList(),
            ),
          ),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.backgroundSecondary,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CachedNetworkImage(
                    imageUrl: video.thumbnailUrl,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(color: Colors.grey[200]),
                    errorWidget: (context, url, error) => const Icon(Icons.error),
                  ),
                  if (video.duration.inSeconds > 0)
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          FormatUtils.formatDuration(video.duration),
                          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundImage: video.uploader.profilePic.isNotEmpty
                      ? CachedNetworkImageProvider(video.uploader.profilePic)
                      : null,
                  child: video.uploader.profilePic.isEmpty ? const Icon(Icons.person, size: 20) : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.videoName,
                        style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.w700, height: 1.2),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${video.uploader.name} • ${FormatUtils.formatViews(video.views)} views • ${FormatUtils.formatTimeAgo(video.uploadedAt)}',
                        style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
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

  /// **Yog (Short-form) grid item style**
  Widget _buildYogVideoGridItem(BuildContext context, VideoModel video, List<VideoModel> allVideos) {
    final videoIndex = allVideos.indexWhere((v) => v.id == video.id);

    return GestureDetector(
      onTap: () {
        // DON'T call close(context, null) to allow back navigation to search
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoScreen(
              initialVideos: allVideos,
              initialVideoId: video.id,
              initialIndex: videoIndex >= 0 ? videoIndex : 0,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.backgroundSecondary,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: video.thumbnailUrl,
              fit: BoxFit.cover,
              errorWidget: (context, url, error) => const Icon(Icons.play_circle_outline, color: AppColors.textTertiary),
            ),
            // Views overlay at bottom
            Positioned(
              bottom: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_arrow, color: Colors.white, size: 10),
                    Text(
                      FormatUtils.formatViews(video.views),
                      style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

