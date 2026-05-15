import 'dart:convert';
import 'package:vayug/shared/services/http_client_service.dart';
import 'package:vayug/shared/config/app_config.dart';
import 'package:vayug/shared/utils/app_logger.dart';
import 'package:vayug/features/profile/notices/domain/models/notice_model.dart';
import 'package:vayug/core/interfaces/i_notice_service.dart';

class NoticeService implements INoticeService {
  @override
  Future<List<NoticeModel>> fetchNotices() async {
    try {
      final response = await httpClientService.get(
        Uri.parse('${NetworkHelper.apiBaseUrl}/notices'),
      );

      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body);
        return data.map((json) => NoticeModel.fromJson(json)).toList();
      } else {
        AppLogger.log('Failed to fetch notices: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      AppLogger.log('Error fetching notices: $e');
      return [];
    }
  }

  @override
  Future<NoticeModel?> getActiveNotice() async {
    final notices = await fetchNotices();
    if (notices.isNotEmpty) {
      // Return the most recent/active notice
      return notices.first;
    }
    return null;
  }

  @override
  Future<void> markAsSeen(String noticeId) async {
    try {
      await httpClientService.post(
        Uri.parse('${NetworkHelper.apiBaseUrl}/notices/$noticeId/seen'),
        body: {},
      );
    } catch (e) {
      AppLogger.log('Error marking notice as seen: $e');
    }
  }
}
