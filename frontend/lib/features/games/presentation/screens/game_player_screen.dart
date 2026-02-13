import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/shared/models/game_model.dart';
import 'package:vayu/shared/utils/app_logger.dart';
import 'package:vayu/shared/config/app_config.dart';

class GamePlayerScreen extends StatefulWidget {
  final GameModel game;

  const GamePlayerScreen({Key? key, required this.game}) : super(key: key);

  @override
  State<GamePlayerScreen> createState() => _GamePlayerScreenState();
}

class _GamePlayerScreenState extends State<GamePlayerScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initWebView();
    
    // **NEW: Set Orientation** 
    if (widget.game.orientation == 'landscape') {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  @override
  void dispose() {
    // **NEW: Reset Orientation**
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);
    super.dispose();
  }

  void _initWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF000000))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            if (mounted) setState(() => _isLoading = true);
          },
          onPageFinished: (String url) {
            if (mounted) setState(() => _isLoading = false);
          },
          onWebResourceError: (WebResourceError error) {
            AppLogger.log('WebView Error: ${error.description}');
          },
        ),
      )
      ..addJavaScriptChannel(
        'VayuApp', // **The Bridge Name**
        onMessageReceived: (JavaScriptMessage message) {
          _handleGameMessage(message.message);
        },
      )
      ..loadRequest(Uri.parse(widget.game.gameUrl));
  }

  // **NEW: Handle Messages from Game**
  Future<void> _handleGameMessage(String message) async {
    try {
      final Map<String, dynamic> data = jsonDecode(message);
      final String type = data['type'];
      
      if (type == 'save') {
        AppLogger.log('💾 Game requested SAVE');
        await _saveGameData(data['payload']);
      } else if (type == 'load') {
        AppLogger.log('📂 Game requested LOAD');
        await _loadGameData();
      }
    } catch (e) {
      AppLogger.log('❌ Error parsing game message: $e');
    }
  }

  // **NEW: Logic to Save Data to Backend**
  Future<void> _saveGameData(dynamic payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) return; // Can't save if not logged in

      final String baseUrl = NetworkHelper.apiBaseUrl;
      final uri = Uri.parse('$baseUrl/games/${widget.game.id}/storage');

      await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'data': payload,
          // Extract score if present for leaderboard
          if (payload is Map && payload.containsKey('score')) 
            'score': payload['score']
        }),
      );
      
      // Notify Game
      _controller.runJavaScript('if(window.onVayuSaveComplete) window.onVayuSaveComplete(true);');
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Game Saved!'), duration: Duration(seconds: 1)),
      );
    } catch (e) {
      AppLogger.log('❌ Failed to save game data: $e');
      _controller.runJavaScript('if(window.onVayuSaveComplete) window.onVayuSaveComplete(false);');
    }
  }

  // **NEW: Logic to Load Data from Backend**
  Future<void> _loadGameData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('jwt_token');
      if (token == null) {
        // Return null/empty if not logged in
        _controller.runJavaScript('if(window.onVayuLoadComplete) window.onVayuLoadComplete(null);');
        return;
      }

      final String baseUrl = NetworkHelper.apiBaseUrl;
      final uri = Uri.parse('$baseUrl/games/${widget.game.id}/storage');

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> resData = jsonDecode(response.body);
        final gameData = resData['data']; // "Open Box" data
        
        // Send back to Game
        final jsonStr = jsonEncode(gameData);
        _controller.runJavaScript('if(window.onVayuLoadComplete) window.onVayuLoadComplete($jsonStr);');
      } else {
        _controller.runJavaScript('if(window.onVayuLoadComplete) window.onVayuLoadComplete(null);');
      }
    } catch (e) {
      AppLogger.log('❌ Failed to load game data: $e');
      _controller.runJavaScript('if(window.onVayuLoadComplete) window.onVayuLoadComplete(null);');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            WebViewWidget(controller: _controller),
            
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

             // Close Button
            Positioned(
              top: 16,
              left: 16,
              child: SafeArea(
                child: CircleAvatar(
                  backgroundColor: Colors.black.withOpacity(0.5),
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
