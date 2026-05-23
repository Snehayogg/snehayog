import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:vayug/core/interfaces/i_search_service.dart';
import 'package:vayug/features/auth/data/usermodel.dart';
import 'package:vayug/features/profile/search/data/models/search_suggestions.dart';
import 'package:vayug/features/profile/search/data/services/search_service_impl.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/features/profile/core/presentation/widgets/category_tile_widget.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayug/features/profile/core/presentation/screens/profile_screen.dart';
import 'package:vayug/features/video/vayu/presentation/screens/vayu_long_form_player_screen.dart';
import 'package:vayug/features/video/core/presentation/screens/video_screen.dart';
import 'package:vayug/shared/widgets/unified_video_card.dart';
import 'package:vayug/shared/widgets/vayu_video_card.dart';

class SearchDiscoveryScreen extends StatefulWidget {
  /// **INJECTION POINT — The "FFmpeg Codec Socket".**
  ///
  /// Pass any [ISearchService] implementation here.
  /// Defaults to [SearchServiceImpl] (HTTP backend) when not provided.
  ///
  /// Examples:
  /// ```dart
  /// // Normal usage — no change needed at call sites
  /// const SearchDiscoveryScreen()
  ///
  /// // Swap to AI search tomorrow — zero screen changes
  /// SearchDiscoveryScreen(searchService: AiSearchServiceImpl())
  ///
  /// // Unit test — no real HTTP calls
  /// SearchDiscoveryScreen(searchService: MockSearchService())
  /// ```
  final ISearchService searchService;

  const SearchDiscoveryScreen({
    Key? key,
    ISearchService? searchService,
  })  : searchService = searchService ?? const _DefaultSearchService(),
        super(key: key);

  @override
  State<SearchDiscoveryScreen> createState() => _SearchDiscoveryScreenState();
}

/// Private const sentinel so `const SearchDiscoveryScreen()` still compiles.
/// Delegates every call to [SearchServiceImpl] which is created lazily on first use.
class _DefaultSearchService implements ISearchService {
  const _DefaultSearchService();

  // Lazy singleton — one instance shared across all default usages.
  static final _impl = SearchServiceImpl();

  @override
  Future<List<VideoModel>> searchVideos(String query, {int limit = 20}) =>
      _impl.searchVideos(query, limit: limit);

  @override
  Future<List<UserModel>> searchCreators(String query, {int limit = 20}) =>
      _impl.searchCreators(query, limit: limit);

  @override
  Future<SearchSuggestions> getSuggestions(String query) =>
      _impl.getSuggestions(query);
}

// -----------------------------------------------------------------------------

class _SearchDiscoveryScreenState extends State<SearchDiscoveryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  // Consumed via interface — no concrete class reference here.
  late final ISearchService _searchService = widget.searchService;

  String _query = '';
  Timer? _debounceTimer;
  bool _isSearching = false;

  SearchSuggestions _suggestions = SearchSuggestions.empty;

  bool _showResults = false;
  List<UserModel> _resultCreators = [];
  List<VideoModel> _resultVideos = [];

  final List<Map<String, dynamic>> _categories = [
    {'title': 'Motivation', 'icon': Icons.bolt_rounded},
    {'title': 'Startup', 'icon': Icons.lightbulb_outline_rounded},
    {'title': 'Finance', 'icon': Icons.account_balance_wallet_outlined},
    {'title': 'Technology', 'icon': Icons.devices_other_rounded},
    {'title': 'Education', 'icon': Icons.school_outlined},
    {'title': 'Lifestyle', 'icon': Icons.self_improvement_rounded},
  ];

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _query = value;
      _showResults = false;
    });

    if (value.trim().length < 2) {
      setState(() => _suggestions = SearchSuggestions.empty);
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _fetchSuggestions(value);
    });
  }

  Future<void> _fetchSuggestions(String q) async {
    setState(() => _isSearching = true);
    try {
      final result = await _searchService.getSuggestions(q);
      if (mounted && _query == q) {
        setState(() {
          _suggestions = result;
          _isSearching = false;
        });
      }
    } catch (e) {
      AppLogger.log('❌ SearchDiscovery: Error fetching suggestions: $e');
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _performSearch() async {
    if (_query.trim().isEmpty) return;

    _searchFocusNode.unfocus();
    setState(() {
      _isSearching = true;
      _showResults = true;
    });

    try {
      final creators = await _searchService.searchCreators(_query);
      final videos = await _searchService.searchVideos(_query);

      if (mounted) {
        setState(() {
          _resultCreators = creators;
          _resultVideos = videos;
          _isSearching = false;
        });
      }
    } catch (e) {
      AppLogger.log('❌ SearchDiscovery: Error performing search: $e');
      if (mounted) setState(() => _isSearching = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: AppColors.backgroundPrimary,
            floating: true,
            snap: true,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: _buildSearchBar(),
            titleSpacing: 16,
          ),
          SliverFillRemaining(
            hasScrollBody: true,
            child: _buildBody(),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 44,
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        autofocus: false,
        onChanged: _onSearchChanged,
        onSubmitted: (_) => _performSearch(),
        style: AppTypography.bodyLarge,
        decoration: InputDecoration(
          hintText: 'Search for content, creators...',
          hintStyle:
              AppTypography.bodyMedium.copyWith(color: AppColors.textTertiary),
          border: InputBorder.none,
          prefixIcon:
              const Icon(Icons.search, color: AppColors.textTertiary, size: 20),
          suffixIcon: _query.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                  child: const Icon(Icons.close_rounded,
                      color: AppColors.textTertiary, size: 20),
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_query.isEmpty) return _buildDiscoveryView();
    if (_showResults) return _buildResultsView();
    return _buildSuggestionsView();
  }

  Widget _buildDiscoveryView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.8,
          ),
          itemCount: _categories.length,
          itemBuilder: (context, index) {
            final cat = _categories[index];
            return CategoryTileWidget(
              title: cat['title'],
              icon: cat['icon'],
              onTap: () {
                _searchController.text = cat['title'];
                _onSearchChanged(cat['title']);
                _performSearch();
              },
            );
          },
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  Widget _buildSuggestionsView() {
    if (_isSearching &&
        _suggestions.creators.isEmpty &&
        _suggestions.videos.isEmpty) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (_suggestions.creators.isNotEmpty)
          ..._suggestions.creators.map((u) => _buildCreatorTile(u)),
        if (_suggestions.videos.isNotEmpty)
          ..._suggestions.videos.map((v) => _buildVideoSuggestionTile(v)),
      ],
    );
  }

  Widget _buildResultsView() {
    if (_isSearching) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (_resultCreators.isEmpty && _resultVideos.isEmpty) {
      return _buildNoResults();
    }

    final vayu = _resultVideos.where((v) => v.videoType == 'vayu').toList();
    final yog = _resultVideos.where((v) => v.videoType != 'vayu').toList();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        if (_resultCreators.isNotEmpty) ...[
          ..._resultCreators.take(5).map((u) => _buildCreatorTile(u)),
          if (_resultCreators.length > 5)
            TextButton(
              onPressed: () {
                // Future: Show all creators screen
              },
              child: const Text('Show all creators'),
            ),
        ],
        if (vayu.isNotEmpty) ...[
          SizedBox(
            height: 275,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: vayu.length,
              itemBuilder: (context, index) {
                final video = vayu[index];
                return Padding(
                  padding: const EdgeInsets.only(right: 12.0),
                  child: SizedBox(
                    width: 280,
                    child: VayuVideoCard(
                      video: video,
                      onTap: () => _navigateToVideo(video, _resultVideos),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        if (yog.isNotEmpty) ...[
          _buildShortsGrid(yog, _resultVideos),
        ],
        const SizedBox(height: 48),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Item builders (unchanged logic)
  // ---------------------------------------------------------------------------

  Widget _buildCreatorTile(UserModel user) {
    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundImage: user.profilePic.isNotEmpty
            ? CachedNetworkImageProvider(user.profilePic)
            : null,
        child: user.profilePic.isEmpty ? const Icon(Icons.person) : null,
      ),
      title: Text(user.name,
          style:
              AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.bold)),
      onTap: () {
        Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => ProfileScreen(userId: user.id)));
      },
    );
  }

  Widget _buildVideoSuggestionTile(VideoModel video) {
    return ListTile(
      leading: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          image: DecorationImage(
              image: CachedNetworkImageProvider(video.thumbnailUrl),
              fit: BoxFit.cover),
        ),
      ),
      title: Text(video.videoName,
          style: AppTypography.bodyMedium,
          maxLines: 2,
          overflow: TextOverflow.ellipsis),
      subtitle: Text(video.uploader.name, style: AppTypography.bodySmall),
      onTap: () => _navigateToVideo(video, [video]),
    );
  }

  // Note: _buildVayuCard was removed as it is replaced by the unified VayuVideoCard widget

  Widget _buildShortsGrid(List<VideoModel> yog, List<VideoModel> all) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        const columns = 3;
        final availableWidth = constraints.maxWidth - 24.0; // 12 padding on each side
        final width =
            (availableWidth - spacing * (columns - 1)) / columns;
        final height = width * 2;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: yog.map((v) {
              return SizedBox(
                width: width,
                height: height,
                child: UnifiedVideoCard(
                  video: v,
                  cardType: UnifiedVideoCardType.yug,
                  onTap: () => _navigateToVideo(v, all),
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _navigateToVideo(VideoModel video, List<VideoModel> all) {
    if (video.videoType == 'vayu') {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => VayuLongFormPlayerScreen(
                  video: video, relatedVideos: all)));
    } else {
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) =>
                  VideoScreen(initialVideos: all, initialVideoId: video.id)));
    }
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded,
              size: 64,
              color: AppColors.textTertiary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text('No results found for "$_query"',
              style: AppTypography.bodyLarge
                  .copyWith(color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}
