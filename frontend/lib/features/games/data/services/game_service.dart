import 'package:vayu/features/games/data/game_model.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:vayu/features/games/data/services/vayu_game_service.dart';

class GameService {
  static final GameService _instance = GameService._internal();
  factory GameService() => _instance;
  GameService._internal();

  final VayuGameService _vayuGameService = VayuGameService();
  
  /// Returns a curated list of games from Vayu Backend.
  Future<List<GameModel>> getGames({int page = 1}) async {
    try {
      // Fetch only from Vayu Backend
      final games = await _vayuGameService.fetchGames(page: page, limit: 10);
      return games;
    } catch (e) {
      AppLogger.log('❌ GameService: Failed to fetch games: $e');
      return [];
    }
  }
}
