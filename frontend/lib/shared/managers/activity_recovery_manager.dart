import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/shared/models/app_activity.dart';
import 'package:vayu/shared/utils/app_logger.dart';

class ActivityRecoveryManager {
  static final ActivityRecoveryManager _instance = ActivityRecoveryManager._internal();
  factory ActivityRecoveryManager() => _instance;
  ActivityRecoveryManager._internal();

  static const String _key = 'current_app_activity';

  /// **Save current activity to disk**
  Future<void> saveActivity(ActivityType type, Map<String, dynamic> data) async {
    try {
      final activity = AppActivity(type: type, data: data);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(activity.toJson()));
      AppLogger.log('💾 ActivityRecoveryManager: Saved activity ${type.name}');
    } catch (e) {
      AppLogger.log('❌ ActivityRecoveryManager: Error saving activity: $e');
    }
  }

  /// **Get saved activity from disk**
  Future<AppActivity?> getSavedActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_key);
      
      if (jsonStr == null) return null;

      final activity = AppActivity.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
      
      if (activity.isExpired) {
        AppLogger.log('🕒 ActivityRecoveryManager: Saved activity expired, clearing');
        await clearActivity();
        return null;
      }

      return activity;
    } catch (e) {
      AppLogger.log('❌ ActivityRecoveryManager: Error getting activity: $e');
      return null;
    }
  }

  /// **Clear activity from disk**
  Future<void> clearActivity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
      AppLogger.log('🗑️ ActivityRecoveryManager: Activity cleared');
    } catch (e) {
      AppLogger.log('❌ ActivityRecoveryManager: Error clearing activity: $e');
    }
  }

  /// **Check if recovery is needed**
  Future<bool> hasRecoverableActivity() async {
    final activity = await getSavedActivity();
    return activity != null && activity.type != ActivityType.none;
  }
}
