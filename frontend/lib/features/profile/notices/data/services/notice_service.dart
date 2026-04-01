import 'dart:convert';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/features/profile/notices/domain/models/notice_model.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/services/http_client_service.dart';

class NoticeService {
  Future<List<NoticeModel>> fetchNotices() async {
    try {
      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.usersEndpoint}/notices'),
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
      await httpClientService.put(
        Uri.parse('${NetworkHelper.usersEndpoint}/notices/$noticeId/seen'),
      );
    } catch (e) {
      AppLogger.log('❌ Error marking notice as seen: $e');
    }
  }
}
