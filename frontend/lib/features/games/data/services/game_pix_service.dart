import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vayu/features/games/data/game_model.dart';
import 'package:vayu/shared/utils/app_logger.dart';

class GamePixService {
  static final GamePixService _instance = GamePixService._internal();
  factory GamePixService() => _instance;
  GamePixService._internal();

  static const String _baseUrl = 'https://feeds.gamepix.com/v2/json';
  static const String _sid = '9913V';

  Future<List<GameModel>> fetchGames({int page = 1, int limit = 24}) async {
    try {
      final uri = Uri.parse('$_baseUrl?sid=$_sid&pagination=$limit&page=$page');
      AppLogger.log('🎮 GamePixService: Fetching games from $uri');

      final response = await http.get(uri);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        
        if (data.containsKey('items') && data['items'] is List) {
          final List<dynamic> items = data['items'];
          final games = items
              .map((item) => GameModel.fromJsonGamePix(item))
              .toList();
          
          AppLogger.log('✅ GamePixService: Fetched ${games.length} games');
          return games;
        } else {
          AppLogger.log('⚠️ GamePixService: No items found in response');
          return [];
        }
      } else {
        AppLogger.log('❌ GamePixService: HTTP Error ${response.statusCode}');
        throw Exception('Failed to load games: ${response.statusCode}');
      }
    } catch (e) {
      AppLogger.log('❌ GamePixService: Error fetching games: $e');
      rethrow;
    }
  }
}
