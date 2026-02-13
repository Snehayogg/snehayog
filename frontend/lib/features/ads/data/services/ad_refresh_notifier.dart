import 'dart:async';

/// Service to notify video feed when ads need to be refreshed
class AdRefreshNotifier {
  static final AdRefreshNotifier _instance = AdRefreshNotifier._internal();
  factory AdRefreshNotifier() => _instance;
  AdRefreshNotifier._internal();

  final StreamController<void> _refreshController =
      StreamController<void>.broadcast();

  /// Stream to listen for ad refresh events
  Stream<void> get refreshStream => _refreshController.stream;

  /// Notify that ads should be refreshed
  void notifyRefresh() {
    print('🔄 AdRefreshNotifier: Notifying ad refresh');
    _refreshController.add(null);
  }

  /// Dispose the notifier
  void dispose() {
    _refreshController.close();
  }
}
