import 'package:flutter/material.dart';
import 'package:vayu/features/video/presentation/managers/video_controller_manager.dart';
import 'package:vayu/shared/models/video_model.dart';

/// **Mixin for easy Hot UI State integration in video screens**
/// Add this to your video screen widgets for WhatsApp-style state preservation
mixin HotUIStateMixin<T extends StatefulWidget>
    on State<T>, WidgetsBindingObserver {
  final VideoControllerManager _controllerManager = VideoControllerManager();

  // Override these in your widget
  int get currentVideoIndex;
  double get currentScrollPosition;
  Map<int, VideoModel> get currentVideos;

  // Callbacks for state restoration
  void onStateRestored(Map<String, dynamic> restoredState) {}
  void onScrollPositionRestored(double position) {}
  void onVideoIndexRestored(int index) {}

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Try to restore state on init
    _tryRestoreState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _saveCurrentState();
        break;
      case AppLifecycleState.resumed:
        _tryRestoreState();
        break;
      default:
        break;
    }
  }

  /// **Save current state when app goes to background**
  void _saveCurrentState() {
    print('💾 HotUIStateMixin: Saving current video state');

    _controllerManager.saveUIStateForBackground(
      currentVideoIndex,
      currentScrollPosition,
      currentVideos,
    );
  }

  /// **Try to restore state when app resumes**
  void _tryRestoreState() {
    print('🔄 HotUIStateMixin: Attempting to restore video state');

    final restoredState = _controllerManager.restoreUIStateFromBackground();

    if (restoredState != null) {
      print('✅ HotUIStateMixin: State restored successfully');

      final lastIndex = restoredState['lastActiveIndex'] as int?;
      final lastScrollPosition = restoredState['lastScrollPosition'] as double?;

      // Notify the widget about restored state
      onStateRestored(restoredState);

      if (lastIndex != null) {
        onVideoIndexRestored(lastIndex);
      }

      if (lastScrollPosition != null) {
        onScrollPositionRestored(lastScrollPosition);
      }
    } else {
      print('ℹ️ HotUIStateMixin: No preserved state found');
    }
  }

  /// **Manual save state (call this when user navigates away)**
  void saveStateManually() {
    _saveCurrentState();
  }

  /// **Get state summary for debugging**
  Map<String, dynamic> getStateSummary() {
    return _controllerManager.getHotUIStateSummary();
  }

  /// **Check if we have preserved state**
  bool get hasPreservedState => _controllerManager.hasPreservedState;
}
