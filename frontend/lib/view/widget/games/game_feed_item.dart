
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:vayu/model/game_model.dart';
import 'package:vayu/utils/app_logger.dart';
import 'package:vayu/view/screens/games/game_player_screen.dart';

class GameFeedItem extends StatefulWidget {
  final GameModel game;
  final bool isVisible;

  const GameFeedItem({
    super.key,
    required this.game,
    required this.isVisible,
  });

  @override
  State<GameFeedItem> createState() => _GameFeedItemState();
}

class _GameFeedItemState extends State<GameFeedItem> with AutomaticKeepAliveClientMixin {
  
  @override
  bool get wantKeepAlive => true; 

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return VisibilityDetector(
      key: Key('game_${widget.game.id}'),
      onVisibilityChanged: (info) {
        // Placeholder for consistency
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          // 1. Cover Image (Always visible)
          Image.network(
            widget.game.bannerImage ?? widget.game.coverImageUrl,
            fit: BoxFit.cover,
            errorBuilder: (ctx, err, stack) => Container(
              color: Colors.grey[900],
              child: const Center(
                child: Icon(Icons.videogame_asset, size: 80, color: Colors.white24),
              ),
            ),
          ),
            
          // 2. Play Button Overlay
          Container(
            color: Colors.black.withOpacity(0.4),
            child: Center(
              child: GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => GamePlayerScreen(game: widget.game),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF00C853), Color(0xFF64DD17)],
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                       Icon(
                        Icons.play_arrow_rounded,
                        size: 32,
                        color: Colors.white,
                      ),
                       SizedBox(width: 8),
                      Text(
                        'Play Now',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 3. Game Metadata Overlay (Bottom)
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.game.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    shadows: [
                      Shadow(
                        color: Colors.black,
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.game.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                    shadows: const [
                       Shadow(
                        color: Colors.black,
                        blurRadius: 8,
                        offset: Offset(0, 1),
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
}
