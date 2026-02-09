import 'package:vayu/model/game_model.dart';
import 'package:vayu/utils/app_logger.dart';
import 'package:vayu/view/screens/games/game_pix_service.dart';

class GameService {
  static final GameService _instance = GameService._internal();
  factory GameService() => _instance;
  GameService._internal();

  final GamePixService _gamePixService = GamePixService();
  
  /// Returns a curated list of high-quality HTML5 games from GamePix.
  /// Used to populate the vertical scroll feed.
  Future<List<GameModel>> getGames({int page = 1}) async {
    try {
      return await _gamePixService.fetchGames(page: page);
    } catch (e) {
      AppLogger.log('❌ GameService: Failed to fetch games: $e');
      return [];
    }
  }
}
