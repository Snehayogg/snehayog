import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:vayu/features/auth/data/usermodel.dart';
import 'package:vayu/shared/utils/app_logger.dart';

import 'package:flutter/foundation.dart'; // for kIsWeb

class AutonomousAgentService {
  // **NEW: LAN IP for Physical Device Access (like AppConfig)**
  // User's Machine IP: 192.168.0.187
  // Agent Port: 3000 (from config.js)
  static const String _agentIpBaseUrl = 'http://192.168.0.187:3000';
  static const String _localhostBaseUrl = 'http://localhost:3000';

  static String get _baseUrl {
    if (kIsWeb) {
      return _localhostBaseUrl;
    }
    // For Android/iOS physical devices on same Wi-Fi
    if (Platform.isAndroid || Platform.isIOS) {
      return _agentIpBaseUrl;
    }
    // Fallback/Desktop
    return _localhostBaseUrl;
  } 

  Future<Map<String, dynamic>?> generateContent({
    required UserModel user,
    required String intent,
    List<String>? videoTitles,
  }) async {
    try {
      AppLogger.log('🤖 Autonomous Agent: Generating content for intent: "$intent"');
      if (videoTitles != null && videoTitles.isNotEmpty) {
        AppLogger.log('📹 Autonomous Agent: Using ${videoTitles.length} video titles for context');
      }
      
      final url = Uri.parse('$_baseUrl/agent/generate');
      
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userProfile': {
            'name': user.name,
            'bio': user.bio, // Still sending bio as backup
            'id': user.id,
          },
          'intent': intent,
          'videoTitles': videoTitles ?? [],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        AppLogger.log('✅ Agent Response: ${data['status']}');
        return data;
      } else {
        AppLogger.log('❌ Agent Error: ${response.statusCode} - ${response.body}');
        return null; // Or throw detailed exception
      }
    } catch (e) {
      AppLogger.log('❌ Agent Exception: $e');
      return null;
    }
  }
}
