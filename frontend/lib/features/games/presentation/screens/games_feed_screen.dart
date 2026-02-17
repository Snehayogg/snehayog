import 'package:flutter/material.dart';
import 'package:vayu/features/games/data/game_model.dart';
import 'package:vayu/features/games/data/services/game_service.dart';
import 'package:vayu/features/games/presentation/widgets/game_feed_item.dart';
import 'package:provider/provider.dart';
import 'package:vayu/features/video/presentation/managers/main_controller.dart';
import 'package:vayu/shared/theme/app_theme.dart';

class GamesFeedScreen extends StatefulWidget {
  const GamesFeedScreen({super.key});

  @override
  State<GamesFeedScreen> createState() => _GamesFeedScreenState();
}

class _GamesFeedScreenState extends State<GamesFeedScreen> with AutomaticKeepAliveClientMixin {
  final PageController _pageController = PageController();
  final List<GameModel> _games = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 1;

  @override
  bool get wantKeepAlive => true; // Keep state alive

  @override
  void initState() {
    super.initState();
    _loadGames();
    
    // As soon as this screen mounts, we should probably pause videos if not already paused by main controller logic.
    WidgetsBinding.instance.addPostFrameCallback((_) {
       final mainController = Provider.of<MainController>(context, listen: false);
       if (mainController.currentIndex == 2) { // Assuming Games is index 2
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
      // Fetch next page
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
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: _games.isEmpty && _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _games.isEmpty && !_isLoading
              ?  Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.auto_awesome, size: 64, color: AppTheme.primary.withValues(alpha:0.5)),
                      const SizedBox(height: 16),
                      Text(
                        'Arcade Fun Game Coming Soon',
                        style: AppTheme.headlineMedium.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 48),
                        child: Text(
                          'We are curating the best interactive experiences for you. Stay tuned!',
                          textAlign: TextAlign.center,
                          style: AppTheme.bodyMedium.copyWith(
                            color: AppTheme.textSecondary,
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
                    // Load more when we're 3 items from the end
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