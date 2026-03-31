import 'dart:convert';
import 'package:vayug/features/auth/data/services/authservices.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:http/http.dart' as http;
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/features/profile/notices/domain/models/notice_model.dart';

class NoticeService {
  Future<List<NoticeModel>> fetchNotices() async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return [];

      final response = await http.get(
        Uri.parse('${NetworkHelper.usersEndpoint}/notices'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final List<dynamic> noticesJson = data['notices'];
          return noticesJson.map((json) => NoticeModel.fromJson(json)).toList();
        }
      }
      return [];
    } catch (e) {
      AppLogger.log('❌ Error fetching notices: $e');
      return [];
    }
  }

  Future<void> markAsSeen(String noticeId) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return;

      await http.put(
        Uri.parse('${NetworkHelper.usersEndpoint}/notices/$noticeId/seen'),
        headers: {
          'Authorization': 'Bearer $token',
        },
      );
    } catch (e) {
      AppLogger.log('❌ Error marking notice as seen: $e');
    }
  }
}
