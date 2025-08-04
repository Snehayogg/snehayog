import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:snehayog/services/google_auth_service.dart';
import 'package:snehayog/services/video_service.dart';

class UserService {
  final GoogleAuthService _authService = GoogleAuthService();

Future<Map<String, dynamic>> getUserById(String id) async {
  final token = (await _authService.getUserData())?['token'];
  if (token == null) {
    throw Exception('Not authenticated');
  }

  final response = await http.get(
    Uri.parse('${VideoService.baseUrl}/api/users/$id'), 
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    },
  );

  if (response.statusCode == 200) {
    return jsonDecode(response.body);
  } else {
    print(
        'Failed to load user. Status code: ${response.statusCode}, Body: ${response.body}');
    throw Exception('Failed to load user');
  }
}

}
