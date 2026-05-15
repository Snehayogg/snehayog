import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/interfaces/i_notice_service.dart';
import 'package:vayug/features/profile/notices/data/services/notice_service.dart';

final noticeServiceProvider = Provider<INoticeService>((ref) {
  return NoticeService();
});
