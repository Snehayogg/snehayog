import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayug/core/interfaces/i_notification_service.dart';
import 'package:vayug/features/profile/core/data/services/notification_service.dart';

final notificationServiceProvider = Provider<INotificationService>((ref) {
  return NotificationService();
});
