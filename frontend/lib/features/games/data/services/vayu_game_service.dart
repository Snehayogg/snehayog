import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vayu/shared/config/app_config.dart';
import 'package:vayu/shared/models/game_model.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VayuGameService {
  static final VayuGameService _instance = VayuGameService._internal();
  factory VayuGameService() => _instance;
  VayuGameService._internal();

  /// Fetches developer uploaded games from Vayu Backend.
  Future<List<GameModel>> fetchGames({int page = 1, int limit = 10}) async {
    try {
      // Use NetworkHelper for reliable base URL
      final String baseUrl = NetworkHelper.apiBaseUrl; 
      final uri = Uri.parse('$baseUrl/games?page=$page&limit=$limit');
      
      // Get token from SharedPreferences directly
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      AppLogger.log('🎮 VayuGameService: Fetching games from $uri');

      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        
        if (data['success'] == true && data['games'] is List) {
          final List<dynamic> items = data['games'];
          final games = items
              .map((item) => GameModel.fromJsonVayu(item))
              .toList();
          
          AppLogger.log('✅ VayuGameService: Fetched ${games.length} games');
          return games;
        } else {
          return [];
        }
      } else {
        AppLogger.log('❌ VayuGameService: HTTP Error ${response.statusCode}');
        return [];
      }
    } catch (e) {
      AppLogger.log('❌ VayuGameService: Error fetching games: $e');
      // Return empty list on error to not block GamePix games
      return [];
    }
  }
}
