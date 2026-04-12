import 'dart:async';
import 'package:flutter/material.dart';
import 'package:vayug/core/design/colors.dart';
import 'package:vayug/core/design/typography.dart';
import 'package:vayug/core/design/radius.dart';
import 'package:vayug/core/design/spacing.dart';
import 'package:vayug/features/auth/data/usermodel.dart';
import 'package:vayug/features/video/core/data/models/video_model.dart';
import 'package:vayug/shared/services/search_service.dart';
import 'package:vayug/features/profile/core/presentation/widgets/category_tile_widget.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/shared/utils/format_utils.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:vayug/features/profile/core/presentation/screens/profile_screen.dart';
import 'package:vayug/features/video/vayu/presentation/screens/vayu_long_form_player_screen.dart';
import 'package:vayug/features/video/core/presentation/screens/video_screen.dart';

class SearchDiscoveryScreen extends StatefulWidget {
  const SearchDiscoveryScreen({Key? key}) : super(key: key);

  @override
  State<SearchDiscoveryScreen> createState() => _SearchDiscoveryScreenState();
}

class _SearchDiscoveryScreenState extends State<SearchDiscoveryScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final SearchService _searchService = SearchService();
  
  String _query = '';
  Timer? _debounceTimer;
  bool _isSearching = false;
  
  List<UserModel> _suggestedCreators = [];
  List<VideoModel> _suggestedVideos = [];
  
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
      setState(() {
        _suggestedCreators = [];
        _suggestedVideos = [];
      });
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
      final suggestions = await _searchService.getSuggestions(q);
      if (mounted && _query == q) {
        setState(() {
          _suggestedCreators = (suggestions['creators'] as List<UserModel>?) ?? [];
          _suggestedVideos = (suggestions['videos'] as List<VideoModel>?) ?? [];
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundPrimary,
        elevation: 0,
        automaticallyImplyLeading: false, // **BACK BUTTON REMOVAL**
        title: _buildSearchBar(),
        titleSpacing: 16, // Add some padding back since leading is gone
      ),
      body: _buildBody(),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      height: 44,
      margin: EdgeInsets.zero, // Remove right margin since it's centered in the title
      decoration: BoxDecoration(
        color: AppColors.backgroundSecondary,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        autofocus: false, // **KEYBOARD FIX: Explicitly set to false**
        onChanged: _onSearchChanged,
        onSubmitted: (_) => _performSearch(),
        style: AppTypography.bodyLarge,
        decoration: InputDecoration(
          hintText: 'Search for content, creators...',
          hintStyle: AppTypography.bodyMedium.copyWith(color: AppColors.textTertiary),
          border: InputBorder.none,
          prefixIcon: const Icon(Icons.search, color: AppColors.textTertiary, size: 20),
          suffixIcon: _query.isNotEmpty
              ? GestureDetector(
                  onTap: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                  child: const Icon(Icons.close_rounded, color: AppColors.textTertiary, size: 20),
                )
              : null,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_query.isEmpty) {
      return _buildDiscoveryView();
    }
    
    if (_showResults) {
      return _buildResultsView();
    }
    
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
            crossAxisSpacing: 12, // Slightly tighter spacing
            mainAxisSpacing: 12,
            childAspectRatio: 2.8, // **REDUCED HEIGHT (Wider than tall)**
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
        // Placeholder for Trending Topics or Popular Creators could go here
      ],
    );
  }

  Widget _buildSuggestionsView() {
    if (_isSearching && _suggestedCreators.isEmpty && _suggestedVideos.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (_suggestedCreators.isNotEmpty) ...[
          _buildSubtitle('Creators'),
          ..._suggestedCreators.map((u) => _buildCreatorTile(u)),
        ],
        if (_suggestedVideos.isNotEmpty) ...[
          _buildSubtitle('Vayu'),
          ..._suggestedVideos.map((v) => _buildVideoSuggestionTile(v)),
        ],
        if (_query.isNotEmpty)
          ListTile(
            leading: const Icon(Icons.search, color: AppColors.primary),
            title: Text(
              'See results for "${_query.trim()}"',
              style: AppTypography.bodyLarge.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
            ),
            onTap: _performSearch,
          ),
      ],
    );
  }

  Widget _buildResultsView() {
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
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
          _buildSubtitle('Creators'),
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
          _buildSubtitle('Vayu'),
          ...vayu.map((v) => _buildVayuCard(v, _resultVideos)),
        ],
        if (yog.isNotEmpty) ...[
          if (vayu.isEmpty) const Divider(color: AppColors.borderPrimary, height: 1),
          _buildSubtitle('Yug'),
          _buildShortsGrid(yog, _resultVideos),
        ],
        const SizedBox(height: 48), // Bottom safe area
      ],
    );
  }

  Widget _buildSubtitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: AppTypography.labelLarge.copyWith(color: AppColors.textTertiary, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildCreatorTile(UserModel user) {
    return ListTile(
      leading: CircleAvatar(
        radius: 20,
        backgroundImage: user.profilePic.isNotEmpty ? CachedNetworkImageProvider(user.profilePic) : null,
        child: user.profilePic.isEmpty ? const Icon(Icons.person) : null,
      ),
      title: Text(user.name, style: AppTypography.bodyLarge.copyWith(fontWeight: FontWeight.bold)),
      subtitle: Text(user.bio?.isNotEmpty == true ? user.bio! : 'View Profile', style: AppTypography.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(userId: user.id)));
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
          image: DecorationImage(image: CachedNetworkImageProvider(video.thumbnailUrl), fit: BoxFit.cover),
        ),
      ),
      title: Text(video.videoName, style: AppTypography.bodyMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
      subtitle: Text(video.uploader.name, style: AppTypography.bodySmall),
      onTap: () {
         _navigateToVideo(video, _videoSuggestionToResult(video));
      },
    );
  }
  
  // Helper to treat a single video as a list for the player
  List<VideoModel> _videoSuggestionToResult(VideoModel video) => [video];

  Widget _buildCreatorsList(List<UserModel> creators) {
    if (creators.isEmpty) return _buildNoResults();
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: creators.length,
      itemBuilder: (context, index) => _buildCreatorTile(creators[index]),
    );
  }

  Widget _buildVideosList(List<VideoModel> videos) {
    if (videos.isEmpty) return _buildNoResults();
    final vayu = videos.where((v) => v.videoType == 'vayu').toList();
    final yog = videos.where((v) => v.videoType != 'vayu').toList();

    return ListView(
      padding: EdgeInsets.zero, // Remove horizontal padding for full-width long video cards
      children: [
        if (vayu.isNotEmpty) ...[
          _buildSubtitle('Vayu'),
          ...vayu.map((v) => _buildVayuCard(v, videos)),
        ],
        if (yog.isNotEmpty) ...[
          _buildSubtitle('Yug'),
          _buildShortsGrid(yog, videos),
        ],
      ],
    );
  }

  Widget _buildVayuCard(VideoModel video, List<VideoModel> all) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Thumbnail Section (16:9)
        GestureDetector(
          onTap: () => _navigateToVideo(video, all),
          child: Stack(
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.zero, // More immersive edge-to-edge
                  child: CachedNetworkImage(
                    imageUrl: video.thumbnailUrl,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              // Duration Badge
              if (video.duration.inSeconds > 0)
                Positioned(
                  bottom: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.7),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      FormatUtils.formatDuration(video.duration),
                      style: AppTypography.labelSmall.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),

        // 2. Info Section
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.backgroundSecondary,
                backgroundImage: video.uploader.profilePic.isNotEmpty
                    ? CachedNetworkImageProvider(video.uploader.profilePic)
                    : null,
                child: video.uploader.profilePic.isEmpty
                    ? const Icon(Icons.person, size: 20, color: Colors.white30)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      video.videoName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyLarge.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${video.uploader.name}  •  ${FormatUtils.formatViews(video.views)} views  •  ${FormatUtils.formatTimeAgo(video.uploadedAt)}',
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white.withOpacity(0.5),
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
    );
  }

  Widget _buildShortsGrid(List<VideoModel> yog, List<VideoModel> all) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.7,
      ),
      itemCount: yog.length,
      itemBuilder: (context, index) {
        final v = yog[index];
        return GestureDetector(
          onTap: () => _navigateToVideo(v, all),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedNetworkImage(imageUrl: v.thumbnailUrl, fit: BoxFit.cover),
          ),
        );
      },
    );
  }

  void _navigateToVideo(VideoModel video, List<VideoModel> all) {
    if (video.videoType == 'vayu') {
      Navigator.push(context, MaterialPageRoute(builder: (_) => VayuLongFormPlayerScreen(video: video, relatedVideos: all)));
    } else {
       Navigator.push(context, MaterialPageRoute(builder: (_) => VideoScreen(initialVideos: all, initialVideoId: video.id)));
    }
  }

  Widget _buildNoResults() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 64, color: AppColors.textTertiary.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text('No results found for "$_query"', style: AppTypography.bodyLarge.copyWith(color: AppColors.textTertiary)),
        ],
      ),
    );
  }
}
