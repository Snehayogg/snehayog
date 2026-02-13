import 'package:vayu/shared/models/game_model.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:vayu/features/games/data/services/game_pix_service.dart';
import 'package:vayu/features/games/data/services/vayu_game_service.dart';

class GameService {
  static final GameService _instance = GameService._internal();
  factory GameService() => _instance;
  GameService._internal();

  final GamePixService _gamePixService = GamePixService();
  final VayuGameService _vayuGameService = VayuGameService();
  
  /// Returns a curated list of games from both GamePix and Vayu Backend.
  /// Interleaves them for variety.
  Future<List<GameModel>> getGames({int page = 1}) async {
    try {
      // Run both requests in parallel
      final results = await Future.wait([
        _gamePixService.fetchGames(page: page, limit: 12),
        _vayuGameService.fetchGames(page: page, limit: 6)
      ]);

      final gamePixGames = results[0];
      final vayuGames = results[1];

      // Merge Strategy: Interleave
      // 2 GamePix -> 1 Vayu -> Repeat
      List<GameModel> merged = [];
      int gpIndex = 0;
      int vIndex = 0;

      while (gpIndex < gamePixGames.length || vIndex < vayuGames.length) {
        // Add 2 GamePix
        if (gpIndex < gamePixGames.length) merged.add(gamePixGames[gpIndex++]);
        if (gpIndex < gamePixGames.length) merged.add(gamePixGames[gpIndex++]);

        // Add 1 Vayu
        if (vIndex < vayuGames.length) merged.add(vayuGames[vIndex++]);
      }
      
      return merged;
    } catch (e) {
      AppLogger.log('❌ GameService: Failed to fetch games: $e');
      return [];
    }
  }
}
