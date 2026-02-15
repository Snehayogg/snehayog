import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:vayu/shared/config/app_config.dart';
import 'package:vayu/features/games/data/game_model.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:http_parser/http_parser.dart';

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
      // Return empty list on error
      return [];
    }
  }

  /// Fetches games uploaded by the authenticated developer.
  Future<List<GameModel>> fetchDeveloperGames() async {
    try {
      final String baseUrl = NetworkHelper.apiBaseUrl;
      final uri = Uri.parse('$baseUrl/games/developer');
      
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      AppLogger.log('🎮 VayuGameService: Fetching developer games from $uri');

      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        
        if (data['success'] == true && data['games'] is List) {
          final List<dynamic> items = data['games'];
          return items
              .map((item) => GameModel.fromJsonVayu(item))
              .toList();
        }
      }
      return [];
    } catch (e) {
      AppLogger.log('❌ VayuGameService: Error fetching developer games: $e');
      return [];
    }
  }

  /// Uploads a game ZIP file.
  Future<bool> uploadGame({
    required File zipFile,
    required String title,
    String? description,
    String orientation = 'portrait',
  }) async {
    try {
      final String baseUrl = NetworkHelper.apiBaseUrl;
      final uri = Uri.parse('$baseUrl/upload/game');
      
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      final request = http.MultipartRequest('POST', uri);
      
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      request.fields['title'] = title;
      request.fields['description'] = description ?? '';
      request.fields['orientation'] = orientation;

      final multipartFile = await http.MultipartFile.fromPath(
        'game',
        zipFile.path,
        contentType: MediaType('application', 'zip'),
      );
      request.files.add(multipartFile);

      AppLogger.log('🎮 VayuGameService: Uploading game to $uri');
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        AppLogger.log('✅ VayuGameService: Game uploaded successfully');
        return true;
      } else {
        AppLogger.log('❌ VayuGameService: Upload failed: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      AppLogger.log('❌ VayuGameService: Error uploading game: $e');
      return false;
    }
  }

  /// Publishes a pending game.
  Future<bool> publishGame(String gameId) async {
    try {
      final String baseUrl = NetworkHelper.apiBaseUrl;
      final uri = Uri.parse('$baseUrl/games/$gameId/publish');
      
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');

      final headers = {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

      AppLogger.log('🎮 VayuGameService: Publishing game $gameId at $uri');

      final response = await http.post(uri, headers: headers);

      if (response.statusCode == 200) {
        AppLogger.log('✅ VayuGameService: Game published successfully');
        return true;
      } else {
        AppLogger.log('❌ VayuGameService: Publish failed: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      AppLogger.log('❌ VayuGameService: Error publishing game: $e');
      return false;
    }
  }
}
