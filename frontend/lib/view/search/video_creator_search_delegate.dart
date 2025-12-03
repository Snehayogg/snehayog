import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vayu/model/usermodel.dart';
import 'package:vayu/model/video_model.dart';
import 'package:vayu/services/search_service.dart';
import 'package:vayu/view/screens/profile_screen.dart';

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

    Future<Map<String, dynamic>> _search() async {
      final videos = await _searchService.searchVideos(q);
      final creators = await _searchService.searchCreators(q);
      return <String, dynamic>{
        'videos': videos,
        'creators': creators,
      };
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _search(),
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
              (UserModel u) => ListTile(
                leading: CircleAvatar(
                  backgroundImage: u.profilePic.isNotEmpty
                      ? NetworkImage(u.profilePic)
                      : null,
                  child: u.profilePic.isEmpty
                      ? const Icon(Icons.person)
                      : const SizedBox.shrink(),
                ),
                title: Text(u.name),
                subtitle: Text(u.email),
                onTap: () {
                  close(context, null);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProfileScreen(userId: u.id),
                    ),
                  );
                },
              ),
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
              (VideoModel v) => ListTile(
                leading: v.thumbnailUrl.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          v.thumbnailUrl,
                          width: 56,
                          height: 56,
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Icon(Icons.play_circle_outline),
                title: Text(
                  v.videoName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${v.views} views'),
                onTap: () {
                  close(context, null);
                  Navigator.of(context).pushNamed(
                    '/video',
                    arguments: <String, dynamic>{'videoId': v.id},
                  );
                },
              ),
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
      _suggestionDebounce = Timer(const Duration(milliseconds: 300), () async {
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
              (UserModel u) => ListTile(
                leading: CircleAvatar(
                  radius: 20,
                  backgroundImage: u.profilePic.isNotEmpty
                      ? NetworkImage(u.profilePic)
                      : null,
                  child: u.profilePic.isEmpty
                      ? const Icon(Icons.person, size: 20)
                      : const SizedBox.shrink(),
                ),
                title: Text(
                  u.name,
                  style: const TextStyle(fontSize: 15),
                ),
                subtitle: Text(
                  u.email,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Icon(Icons.arrow_forward_ios,
                    size: 16, color: Colors.grey[400]),
                onTap: () {
                  query = u.name; // Fill search field
                  showResults(context); // Show full results
                },
              ),
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
              (VideoModel v) => ListTile(
                leading: v.thumbnailUrl.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: Image.network(
                          v.thumbnailUrl,
                          width: 48,
                          height: 48,
                          fit: BoxFit.cover,
                        ),
                      )
                    : const Icon(Icons.play_circle_outline, size: 24),
                title: Text(
                  v.videoName,
                  style: const TextStyle(fontSize: 15),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  '${v.views} views',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                trailing: Icon(Icons.arrow_forward_ios,
                    size: 16, color: Colors.grey[400]),
                onTap: () {
                  query = v.videoName; // Fill search field
                  showResults(context); // Show full results
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
