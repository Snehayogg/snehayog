abstract class INotificationService {
  Future<Map<String, dynamic>> sendCreatorAlert({
    required String message,
    String? title,
    String? targetUrl,
    List<String>? recipientIds,
  });

  Future<Map<String, dynamic>> updatePreferences({
    bool? globalEnabled,
    String? disabledCreatorId,
    String? enabledCreatorId,
  });

  Future<Map<String, dynamic>> getCreatorAlertStats();
}
