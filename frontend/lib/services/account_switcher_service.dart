import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vayu/utils/app_logger.dart';

/// Service to manage multiple accounts with separate cache
class AccountSwitcherService {
  static const String _accountsListKey = 'saved_accounts_list';
  static const String _currentAccountKey = 'current_account_id';
  static const String _accountDataPrefix = 'account_data_';
  static const String _accountCachePrefix = 'account_cache_';

  /// Get list of all saved accounts
  Future<List<Map<String, dynamic>>> getSavedAccounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accountsJson = prefs.getString(_accountsListKey);
      if (accountsJson == null || accountsJson.isEmpty) {
        return [];
      }
      final List<dynamic> accountsList = json.decode(accountsJson);
      return accountsList.map((e) => Map<String, dynamic>.from(e)).toList();
    } catch (e) {
      AppLogger.log(
          '⚠️ AccountSwitcherService: Error getting saved accounts: $e');
      return [];
    }
  }

  /// Get current active account ID
  Future<String?> getCurrentAccountId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_currentAccountKey);
    } catch (e) {
      AppLogger.log(
          '⚠️ AccountSwitcherService: Error getting current account: $e');
      return null;
    }
  }

  /// Save account data
  Future<void> saveAccount(Map<String, dynamic> userData) async {
    try {
      final userId = userData['googleId'] ?? userData['id'];
      if (userId == null) {
        AppLogger.log(
            '⚠️ AccountSwitcherService: Cannot save account - no userId');
        return;
      }

      final prefs = await SharedPreferences.getInstance();

      // Get existing accounts
      final accounts = await getSavedAccounts();

      // Check if account already exists
      final existingIndex = accounts.indexWhere(
        (acc) => (acc['googleId'] ?? acc['id']) == userId,
      );

      // Prepare account summary (for list display)
      final accountSummary = {
        'googleId': userData['googleId'] ?? userData['id'],
        'id': userData['id'] ?? userData['googleId'],
        'email': userData['email'] ?? '',
        'name': userData['name'] ?? '',
        'profilePic': userData['profilePic'] ?? '',
        'lastUsed': DateTime.now().millisecondsSinceEpoch,
      };

      if (existingIndex >= 0) {
        // Update existing account
        accounts[existingIndex] = accountSummary;
        AppLogger.log(
            '🔄 AccountSwitcherService: Updated existing account: ${userData['email']}');
      } else {
        // Add new account
        accounts.add(accountSummary);
        AppLogger.log(
            '✅ AccountSwitcherService: Added new account: ${userData['email']}');
      }

      // Save accounts list
      await prefs.setString(_accountsListKey, json.encode(accounts));

      // Save full account data
      await prefs.setString(
        '$_accountDataPrefix$userId',
        json.encode(userData),
      );

      // Set as current account
      await prefs.setString(_currentAccountKey, userId.toString());

      AppLogger.log('✅ AccountSwitcherService: Account saved successfully');
    } catch (e) {
      AppLogger.log('❌ AccountSwitcherService: Error saving account: $e');
    }
  }

  /// Get account data by userId
  Future<Map<String, dynamic>?> getAccountData(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accountDataJson = prefs.getString('$_accountDataPrefix$userId');
      if (accountDataJson == null || accountDataJson.isEmpty) {
        return null;
      }
      return Map<String, dynamic>.from(json.decode(accountDataJson));
    } catch (e) {
      AppLogger.log(
          '⚠️ AccountSwitcherService: Error getting account data: $e');
      return null;
    }
  }

  /// Switch to account (set as current)
  Future<void> switchToAccount(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_currentAccountKey, userId);
      AppLogger.log('✅ AccountSwitcherService: Switched to account: $userId');
    } catch (e) {
      AppLogger.log('❌ AccountSwitcherService: Error switching account: $e');
    }
  }

  /// Remove account from saved accounts
  Future<void> removeAccount(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Remove from accounts list
      final accounts = await getSavedAccounts();
      accounts.removeWhere(
        (acc) => (acc['googleId'] ?? acc['id']) == userId,
      );
      await prefs.setString(_accountsListKey, json.encode(accounts));

      // Remove account data
      await prefs.remove('$_accountDataPrefix$userId');

      // Remove account cache
      await _clearAccountCache(userId);

      // If this was current account, clear current
      final currentId = await getCurrentAccountId();
      if (currentId == userId) {
        await prefs.remove(_currentAccountKey);
      }

      AppLogger.log('✅ AccountSwitcherService: Removed account: $userId');
    } catch (e) {
      AppLogger.log('❌ AccountSwitcherService: Error removing account: $e');
    }
  }

  /// Clear cache for specific account
  Future<void> _clearAccountCache(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();

      for (final key in keys) {
        if (key.startsWith('$_accountCachePrefix$userId') ||
            key.startsWith('profile_cache_$userId') ||
            key.startsWith('earnings_cache_$userId') ||
            key.startsWith('video_profile_$userId') ||
            key.startsWith('user_profile_$userId')) {
          await prefs.remove(key);
        }
      }

      AppLogger.log(
          '✅ AccountSwitcherService: Cleared cache for account: $userId');
    } catch (e) {
      AppLogger.log('⚠️ AccountSwitcherService: Error clearing cache: $e');
    }
  }

  /// Clear all cache for an account (called when switching away)
  Future<void> clearAccountCache(String userId) async {
    await _clearAccountCache(userId);
  }

  /// Get cache key for account-specific data
  static String getAccountCacheKey(String userId, String cacheType) {
    return '$_accountCachePrefix$userId$cacheType';
  }
}
