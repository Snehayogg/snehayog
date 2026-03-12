import 'package:flutter/material.dart';
import 'package:vayu/features/games/data/game_model.dart';
import 'package:vayu/features/games/data/services/game_service.dart';
import 'package:vayu/features/games/presentation/widgets/game_feed_item.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayu/core/providers/navigation_providers.dart';
import 'package:vayu/core/providers/auth_providers.dart';
import 'package:vayu/core/design/colors.dart';
import 'package:vayu/core/design/typography.dart';

class GamesFeedScreen extends ConsumerStatefulWidget {
  const GamesFeedScreen({super.key});

  @override
  ConsumerState<GamesFeedScreen> createState() => _GamesFeedScreenState();
}

class _GamesFeedScreenState extends ConsumerState<GamesFeedScreen>
    with AutomaticKeepAliveClientMixin {
  final PageController _pageController = PageController();
  final List<GameModel> _games = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 1;
  bool? _wasSignedIn;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadGames();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final mainController = ref.read(mainControllerProvider);
      if (mainController.currentIndex == 2) {
        mainController.forcePauseVideos();
      }
    });
  }

  Future<void> _loadGames() async {
    if (_isLoading || !_hasMore) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final newGames = await GameService().getGames(page: _currentPage);

      if (newGames.isEmpty && _games.isEmpty) {
        setState(() {
          _hasMore = false;
          _isLoading = false;
        });
      } else {
        setState(() {
          _games.addAll(newGames);
          _currentPage++;
          _isLoading = false;
          if (newGames.isEmpty) _hasMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshGames() async {
    if (!mounted) return;
    setState(() {
      _games.clear();
      _currentPage = 1;
      _hasMore = true;
      _isLoading = false;
    });
    await _loadGames();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final authController = ref.watch(googleSignInProvider);
    final bool isSignedIn = authController.isSignedIn;

    if (_wasSignedIn != null && _wasSignedIn != isSignedIn) {
      _wasSignedIn = isSignedIn;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _refreshGames();
        }
      });
    }
    _wasSignedIn = isSignedIn;

    return Scaffold(
      backgroundColor: AppColors.backgroundPrimary,
      body: _games.isEmpty && _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _games.isEmpty && !_isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.auto_awesome,
                          size: 64,
                          color: AppColors.primary.withValues(alpha: 0.5)),
                      const SizedBox(height: 16),
                      Text(
                        'Arcade Fun Coming Soon',
                        style: AppTypography.headlineMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 48),
                        child: Text(
                          'We are curating the best interactive experiences for you. Stay tuned!',
                          textAlign: TextAlign.center,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : PageView.builder(
                  controller: _pageController,
                  scrollDirection: Axis.vertical,
                  itemCount: _games.length,
                  onPageChanged: (index) {
                    if (index >= _games.length - 3) {
                      _loadGames();
                    }
                  },
                  itemBuilder: (context, index) {
                    return GameFeedItem(
                      game: _games[index],
                      isVisible: true,
                    );
                  },
                ),
    );
  }
}
