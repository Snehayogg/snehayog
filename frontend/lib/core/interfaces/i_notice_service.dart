import 'package:vayug/features/profile/notices/domain/models/notice_model.dart';

abstract class INoticeService {
  Future<List<NoticeModel>> fetchNotices();
  Future<NoticeModel?> getActiveNotice();
  Future<void> markAsSeen(String noticeId);
}
