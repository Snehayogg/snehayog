import 'package:flutter/material.dart';
import 'package:vayu/model/game_model.dart';
import 'package:vayu/view/screens/games/game_service.dart';
import 'package:vayu/view/widget/games/game_feed_item.dart';
import 'package:provider/provider.dart';
import 'package:vayu/controller/main_controller.dart';

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
      
      if (newGames.isEmpty) {
        setState(() {
          _hasMore = false;
          _isLoading = false;
        });
      } else {
        setState(() {
          _games.addAll(newGames);
          _currentPage++;
          _isLoading = false;
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
              ? const Center(
                  child: Text(
                    'No games available',
                    style: TextStyle(color: Colors.white),
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