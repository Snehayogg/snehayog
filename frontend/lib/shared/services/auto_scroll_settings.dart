import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AutoScrollSettings {
  static const String _keyAutoScrollEnabled = 'auto_scroll_enabled';
  static final ValueNotifier<bool> notifier =
      ValueNotifier<bool>(true); // **UPDATED: Default to true**

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getBool(_keyAutoScrollEnabled) ?? true;
    if (notifier.value != value) notifier.value = value;
    return value;
  }

  static Future<void> setEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoScrollEnabled, enabled);
    if (notifier.value != enabled) notifier.value = enabled;
  }
}
