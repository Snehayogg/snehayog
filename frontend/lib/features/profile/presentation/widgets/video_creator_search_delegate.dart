import 'package:vayu/features/auth/data/services/authservices.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayu/features/auth/data/usermodel.dart';
import 'package:vayu/features/video/video_model.dart';
import 'package:vayu/shared/services/search_service.dart';
import 'package:vayu/features/profile/presentation/screens/profile_screen.dart';
import 'package:vayu/features/video/presentation/screens/video_screen.dart';
import 'package:vayu/shared/theme/app_theme.dart';

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
        backgroundColor: AppTheme.backgroundPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppTheme.textPrimary),
        titleTextStyle: AppTheme.titleLarge.copyWith(
          color: AppTheme.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: InputBorder.none,
        hintStyle: AppTheme.bodyMedium.copyWith(color: AppTheme.textSecondary),
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

    Future<Map<String, dynamic>> search() async {
      final videos = await _searchService.searchVideos(q);
      final creators = await _searchService.searchCreators(q);
      return <String, dynamic>{
        'videos': videos,
        'creators': creators,
      };
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: search(),
      builder:
          (BuildContext context, AsyncSnapshot<Map<String, dynamic>> snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(Icons.error_outline, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  'Search failed. Please try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        final data = snapshot.data ?? <String, dynamic>{};
        final List<VideoModel> videos =
            (data['videos'] as List<VideoModel>? ?? <VideoModel>[]);
        final List<UserModel> creators =
            (data['creators'] as List<UserModel>? ?? <UserModel>[]);

        if (videos.isEmpty && creators.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const Icon(Icons.search_off, size: 48, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  'No results found',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Try a different search term',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ],
            ),
          );
        }

        return ListView(
          children: <Widget>[
            if (creators.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Creators',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ...creators.map(
              (UserModel u) => _buildCreatorResultTile(context, u),
            ),
            if (videos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Videos',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ...videos.map(
              (VideoModel v) => _buildVideoResultTile(context, v, videos),
            ),
          ],
        );
      },
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
      _suggestionDebounce = Timer(const Duration(milliseconds: 200), () async {
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
            ...creators.map(
              (UserModel u) => _buildCreatorSuggestionTile(context, u),
            ),
            if (videos.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.play_circle_outline,
                        size: 18, color: Colors.grey[600]),
                    const SizedBox(width: 8),
                    Text(
                      'Videos',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: Colors.grey[700],
                          ),
                    ),
                  ],
                ),
              ),
            ...videos.map(
              (VideoModel v) => _buildVideoSuggestionTile(context, v, videos),
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
        backgroundColor: AppTheme.backgroundSecondary,
        backgroundImage: creator.profilePic.isNotEmpty
            ? CachedNetworkImageProvider(creator.profilePic)
            : null,
        child: creator.profilePic.isEmpty
            ? const Icon(Icons.person, color: AppTheme.textSecondary)
            : null,
      ),
      title: Text(
        creator.name,
        style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        (creator.bio?.isNotEmpty ?? false) ? creator.bio! : 'View profile',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.bodySmall,
      ),
      trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textTertiary),
      onTap: () {
        close(context, null);
        
        final authService = Provider.of<AuthService>(context, listen: false);
        final myId = authService.currentUserId;
        
        if (creator.id == myId) {
          // If navigating to self, pop to root (Profile Tab root)
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          // Replace if already viewing a creator to avoid deep stacks
          final isPushed = Navigator.of(context).canPop();
          if (isPushed) {
             Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                settings: const RouteSettings(name: 'profile_creator'),
                builder: (_) => ProfileScreen(userId: creator.id),
              ),
            );
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(
                settings: const RouteSettings(name: 'profile_creator'),
                builder: (_) => ProfileScreen(userId: creator.id),
              ),
            );
          }
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
        backgroundColor: AppTheme.backgroundSecondary,
        backgroundImage: creator.profilePic.isNotEmpty
            ? CachedNetworkImageProvider(creator.profilePic)
            : null,
        child: creator.profilePic.isEmpty
            ? const Icon(Icons.person, color: AppTheme.textSecondary, size: 18)
            : null,
      ),
      title: Text(
        creator.name,
        style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        (creator.bio?.isNotEmpty ?? false) ? creator.bio! : 'View profile',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.labelSmall,
      ),
      trailing: const Icon(Icons.north_west, size: 14, color: AppTheme.textTertiary),
      onTap: () {
        close(context, null);
        
        final authService = Provider.of<AuthService>(context, listen: false);
        final myId = authService.currentUserId;
        
        if (creator.id == myId) {
          // If navigating to self, pop to root (Profile Tab root)
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          // Replace if already viewing a creator to avoid deep stacks
          final isPushed = Navigator.of(context).canPop();
          if (isPushed) {
             Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                settings: const RouteSettings(name: 'profile_creator'),
                builder: (_) => ProfileScreen(userId: creator.id),
              ),
            );
          } else {
            Navigator.of(context).push(
              MaterialPageRoute(
                settings: const RouteSettings(name: 'profile_creator'),
                builder: (_) => ProfileScreen(userId: creator.id),
              ),
            );
          }
        }
      },
    );
  }

  /// **PROFESSIONAL: Build video result tile (full search results)**
  Widget _buildVideoResultTile(
      BuildContext context, VideoModel video, List<VideoModel> allVideos) {
    // Find index of this video in the list
    final videoIndex = allVideos.indexWhere((v) => v.id == video.id);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: video.thumbnailUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: video.thumbnailUrl,
                width: 72,
                height: 72,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  width: 72,
                  height: 72,
                  color: Colors.grey[200],
                  child: const Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  width: 72,
                  height: 72,
                  color: AppTheme.backgroundSecondary,
child:
                      const Icon(Icons.play_circle_outline, color: AppTheme.textTertiary),
                ),
              )
            : Container(
                width: 72,
                height: 72,
                color: AppTheme.backgroundSecondary,
                child: const Icon(Icons.play_circle_outline,
                    color: AppTheme.textTertiary, size: 32),
              ),
      ),
      title: Text(
        video.videoName,
        style: AppTheme.titleMedium.copyWith(fontWeight: FontWeight.w600),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            const Icon(Icons.visibility, size: 14, color: AppTheme.textTertiary),
            const SizedBox(width: 4),
            Text(
              _formatViewCount(video.views),
              style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
            ),
          ],
        ),
      ),
      trailing:
          Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
      onTap: () {
        close(context, null);
        // Navigate to video feed with the selected video
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
    );
  }

  /// **PROFESSIONAL: Build video suggestion tile (autocomplete)**
  Widget _buildVideoSuggestionTile(
      BuildContext context, VideoModel video, List<VideoModel> allVideos) {
    // Find index of this video in the list
    final videoIndex = allVideos.indexWhere((v) => v.id == video.id);

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: video.thumbnailUrl.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: video.thumbnailUrl,
                width: 56,
                height: 56,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  width: 56,
                  height: 56,
                  color: Colors.grey[200],
                  child: const Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  width: 56,
                  height: 56,
                  color: AppTheme.backgroundSecondary,
                  child: const Icon(Icons.play_circle_outline,
                      color: AppTheme.textTertiary, size: 24),
                ),
              )
            : Container(
                width: 56,
                height: 56,
                color: AppTheme.backgroundSecondary,
                child: const Icon(Icons.play_circle_outline,
                    color: AppTheme.textTertiary, size: 24),
              ),
      ),
      title: Text(
        video.videoName,
        style: AppTheme.titleSmall.copyWith(fontWeight: FontWeight.w500),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${_formatViewCount(video.views)} views',
        style: AppTheme.bodySmall.copyWith(color: AppTheme.textSecondary),
      ),
      trailing:
          Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey[400]),
      onTap: () {
        close(context, null);
        // Navigate to video feed with the selected video
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
    );
  }

  /// **HELPER: Format view count (e.g., 1000 -> 1K)**
  String _formatViewCount(int views) {
    if (views < 1000) {
      return views.toString();
    } else if (views < 1000000) {
      return '${(views / 1000).toStringAsFixed(1)}K';
    } else {
      return '${(views / 1000000).toStringAsFixed(1)}M';
    }
  }
}
